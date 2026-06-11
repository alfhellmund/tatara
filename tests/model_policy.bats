#!/usr/bin/env bats
# Tests fuer Phase 1 — Architekt-Modell-Policy (fable_available / resolve_architect_model /
# substitute_architect_model / mode_bootstrap_globals / mode_check)
#
# WICHTIG — set -e / bats-Interaktion:
#   Das tatara-Skript aktiviert beim Sourcen 'set -euo pipefail'. Das wuerde im bats-
#   Testkontext bei jeder Funktion mit Exit != 0 sofort den Test abbrechen, bevor die
#   Assertion laeuft. Loesung: Unit-Funktionen werden in Subshells aufgerufen:
#     run bash -c 'set +euo pipefail; source <skript>; <funktion>'
#   Dabei wird main() VOR dem Source als No-op ueberschrieben, damit das Skript beim
#   Sourcen nicht in show_help+exit1 laeuft. Nach dem Source heben wir set -e mit
#   'set +euo pipefail' erneut auf, damit Nicht-Null-Exits der Funktionen den Test
#   nicht abwuergen. Blackbox-Tests laufen als eigener 'bash tatara --flag'-Prozess.

TATARA="/Users/alfhellmund/Development/tatara/tatara"
STUBS_DIR="/Users/alfhellmund/Development/tatara/tests/stubs"

setup() {
    # Isoliertes HOME fuer jeden Test
    HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"

    # Stub-Log-Datei (wird von claude-Stub beschrieben)
    CLAUDE_STUB_LOG="$BATS_TEST_TMPDIR/calls.log"
    export CLAUDE_STUB_LOG
    export HOME

    # Standard-PATH: Stubs (claude+git+bd) vorgelagert
    STUB_PATH="${STUBS_DIR}:${PATH}"
}

# Hilfsfunktion: PATH ohne claude-Stub, aber mit git + bd
_path_no_claude() {
    local nodir="$BATS_TEST_TMPDIR/nostubs_$$"
    mkdir -p "$nodir"
    cp "$STUBS_DIR/git" "$nodir/git"
    cp "$STUBS_DIR/bd"  "$nodir/bd"
    printf '%s' "${nodir}:${PATH}"
}

# ==============================================================================
# Smoke-Tests
# ==============================================================================

@test "smoke: bash -n Syntaxpruefung besteht" {
    run bash -n "$TATARA"
    [ "$status" -eq 0 ]
}

@test "smoke: shellcheck besteht (falls shellcheck im PATH)" {
    if ! command -v shellcheck >/dev/null 2>&1; then
        skip "shellcheck nicht im PATH"
    fi
    run shellcheck "$TATARA"
    [ "$status" -eq 0 ]
}

# ==============================================================================
# AK-17 — Source-Guard: tatara ist sourcebar, Funktionen werden definiert
# ==============================================================================

@test "AK-17: source tatara definiert fable_available ohne main-Nebeneffekt in stdout" {
    # tatara hat keinen BASH_SOURCE-Guard: 'main \"\$@\"' am Dateiende wird beim Source
    # ausgefuehrt. Workaround: main() VOR dem Source als No-op setzen. Das Skript
    # definiert main() spaeter neu — deshalb nutzen wir eine abweichende Funktion
    # als Sentinel: Wir ueberschreiben 'err' damit die require_supported_os-Kette
    # sicher ist und leiten ALLES nach /dev/null.
    # AK-17 prueft: Nach Impl mit Source-Guard ist fable_available definiert.
    # Vor Impl existiert fable_available NICHT -> Assertion failt -> rot.
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        # Beide Ausgabewege nach /dev/null; main als No-op BEVOR source
        main() { : ; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        # Funktion listen — Output enthaelt nur 'fable_available () ...' wenn definiert
        declare -f fable_available 2>/dev/null
    "
    # Funktion muss definiert sein (rot: Funktion existiert noch nicht)
    [[ "$output" == *"fable_available"* ]] \
        || { echo "AK-17: fable_available nach source nicht definiert (Impl fehlt noch). Output: '$output'"; false; }
    # Kein Hilfe-/Bootstrap-Text in stdout (Nebeneffektfreiheit nach Impl)
    [[ "$output" != *"Bootstrap"* ]] \
        || { echo "AK-17: main()-Nebeneffekt (Bootstrap-Text) in stdout sichtbar"; false; }
}

# ==============================================================================
# Hilfsfunktion: Unit-Funktion in Subshell ausfuehren und Output+Status liefern.
# Strategie: main() vor source als No-op, nach source set +euo pipefail,
# dann Funktion aufrufen. Der run-Befehl faengt stdout + exit.
# ==============================================================================

# AK-1: kein claude im PATH -> resolve_architect_model stdout = 'opus fallback no-claude', exit 0
@test "AK-1: kein claude im PATH -> 'opus fallback no-claude'" {
    local no_claude_path
    no_claude_path="$(_path_no_claude)"

    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export PATH='${no_claude_path}'
        main() { : ; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        resolve_architect_model
    "
    # Output-Assertion (primaer — failt wenn Funktion fehlt oder falschen Wert liefert)
    [ "$output" = "opus fallback no-claude" ] \
        || { echo "AK-1: stdout='$output' (exit=$status) erwartet 'opus fallback no-claude'"; false; }
    [ "$status" -eq 0 ] \
        || { echo "AK-1: Exit-Code $status erwartet 0"; false; }
}

# AK-2: claude da, auth status->loggedIn:false -> 'opus fallback not-logged-in'; KEIN -p-Call
@test "AK-2: loggedIn:false -> 'opus fallback not-logged-in', kein -p-Call" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOGGED_IN=0
        main() { : ; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        resolve_architect_model
    "
    [ "$output" = "opus fallback not-logged-in" ] \
        || { echo "AK-2: stdout='$output' (exit=$status) erwartet 'opus fallback not-logged-in'"; false; }
    [ "$status" -eq 0 ] \
        || { echo "AK-2: Exit-Code $status erwartet 0"; false; }
    # Kein -p-Call: Log darf kein '-p' enthalten
    if [[ -f "$CLAUDE_STUB_LOG" ]]; then
        if grep -qF '"-p"' "$CLAUDE_STUB_LOG" 2>/dev/null; then
            echo "AK-2: Stub-Log enthaelt -p-Call — kein Probe erlaubt bei not-logged-in:"
            cat "$CLAUDE_STUB_LOG"
            false
        fi
    fi
}

# AK-3: eingeloggt + Probe is_error:false, subtype:success -> fable auto (mit jq)
@test "AK-3: Probe-JSON success -> 'fable auto' (mit jq)" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOGGED_IN=1
        export CLAUDE_STUB_FABLE=ok
        main() { : ; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        resolve_architect_model
    "
    [ "$output" = "fable auto" ] \
        || { echo "AK-3: stdout='$output' (exit=$status) erwartet 'fable auto'"; false; }
    [ "$status" -eq 0 ] \
        || { echo "AK-3: Exit-Code $status erwartet 0"; false; }
}

# AK-3b: eingeloggt + Probe success -> fable auto (grep-Fallback, ohne jq).
# 'kein jq' wird simuliert, indem in der Subshell nach dem Source eine jq()-
# Shell-Funktion definiert wird, die 'command not found' zurueckgibt (exit 127).
# Dies ist robuster als PATH-Manipulation, da /usr/bin nicht entfernt werden kann.
@test "AK-3b: Probe-JSON success -> 'fable auto' (grep-Fallback, ohne jq)" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOGGED_IN=1
        export CLAUDE_STUB_FABLE=ok
        main() { : ; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        # jq als Shell-Funktion maskieren: immer exit 127 -> simuliert 'kein jq'
        jq() { return 127; }
        resolve_architect_model
    "
    [ "$output" = "fable auto" ] \
        || { echo "AK-3b: stdout='$output' (exit=$status) erwartet 'fable auto' (ohne jq)"; false; }
    [ "$status" -eq 0 ] \
        || { echo "AK-3b: Exit-Code $status erwartet 0"; false; }
}

# AK-4: eingeloggt + Probe is_error:true -> opus fallback probe-failed (mit jq)
@test "AK-4: Probe-JSON is_error:true -> 'opus fallback probe-failed' (mit jq)" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOGGED_IN=1
        export CLAUDE_STUB_FABLE=denied
        main() { : ; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        resolve_architect_model
    "
    [ "$output" = "opus fallback probe-failed" ] \
        || { echo "AK-4: stdout='$output' (exit=$status) erwartet 'opus fallback probe-failed'"; false; }
    [ "$status" -eq 0 ] \
        || { echo "AK-4: Exit-Code $status erwartet 0"; false; }
}

# AK-4b: eingeloggt + Probe is_error:true -> opus fallback probe-failed (grep-Fallback, ohne jq)
@test "AK-4b: Probe-JSON is_error:true -> 'opus fallback probe-failed' (grep-Fallback, ohne jq)" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOGGED_IN=1
        export CLAUDE_STUB_FABLE=denied
        main() { : ; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        jq() { return 127; }
        resolve_architect_model
    "
    [ "$output" = "opus fallback probe-failed" ] \
        || { echo "AK-4b: stdout='$output' (exit=$status) erwartet 'opus fallback probe-failed' (ohne jq)"; false; }
    [ "$status" -eq 0 ] \
        || { echo "AK-4b: Exit-Code $status erwartet 0"; false; }
}

# AK-5: eingeloggt + Probe liefert Nicht-JSON-Muell -> opus fallback probe-failed
@test "AK-5: Probe liefert Nicht-JSON -> 'opus fallback probe-failed'" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOGGED_IN=1
        export CLAUDE_STUB_FABLE=garbage
        main() { : ; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        resolve_architect_model
    "
    [ "$output" = "opus fallback probe-failed" ] \
        || { echo "AK-5: stdout='$output' (exit=$status) erwartet 'opus fallback probe-failed'"; false; }
    [ "$status" -eq 0 ] \
        || { echo "AK-5: Exit-Code $status erwartet 0"; false; }
}

# AK-6: TATARA_ARCHITECT_MODEL=fable -> fable override, KEIN claude-Call (kein Log-Eintrag)
@test "AK-6: TATARA_ARCHITECT_MODEL=fable -> 'fable override', kein claude-Call" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export PATH='${STUB_PATH}'
        export TATARA_ARCHITECT_MODEL=fable
        main() { : ; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        resolve_architect_model
    "
    [ "$output" = "fable override" ] \
        || { echo "AK-6: stdout='$output' (exit=$status) erwartet 'fable override'"; false; }
    [ "$status" -eq 0 ] \
        || { echo "AK-6: Exit-Code $status erwartet 0"; false; }
    # Kein claude-Call: Log darf nicht existieren oder muss leer sein
    if [[ -f "$CLAUDE_STUB_LOG" ]] && [[ -s "$CLAUDE_STUB_LOG" ]]; then
        echo "AK-6: Stub-Log enthaelt Eintraege obwohl kein claude-Call erlaubt:"
        cat "$CLAUDE_STUB_LOG"
        false
    fi
}

# AK-6 Zusatz: TATARA_ARCHITECT_MODEL=opus -> opus override, kein claude-Call
@test "AK-6-opus: TATARA_ARCHITECT_MODEL=opus -> 'opus override', kein claude-Call" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export PATH='${STUB_PATH}'
        export TATARA_ARCHITECT_MODEL=opus
        main() { : ; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        resolve_architect_model
    "
    [ "$output" = "opus override" ] \
        || { echo "AK-6-opus: stdout='$output' (exit=$status) erwartet 'opus override'"; false; }
    [ "$status" -eq 0 ] \
        || { echo "AK-6-opus: Exit-Code $status erwartet 0"; false; }
    if [[ -f "$CLAUDE_STUB_LOG" ]] && [[ -s "$CLAUDE_STUB_LOG" ]]; then
        echo "AK-6-opus: Stub-Log enthaelt Eintraege obwohl kein claude-Call erlaubt:"
        cat "$CLAUDE_STUB_LOG"
        false
    fi
}

# AK-16: TATARA_ARCHITECT_MODEL='' (leer) verhaelt sich wie ungesetzt -> fable auto bei Stub-ok
@test "AK-16: TATARA_ARCHITECT_MODEL=leer verhaelt sich wie ungesetzt -> 'fable auto'" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export PATH='${STUB_PATH}'
        export TATARA_ARCHITECT_MODEL=''
        export CLAUDE_STUB_LOGGED_IN=1
        export CLAUDE_STUB_FABLE=ok
        main() { : ; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        resolve_architect_model
    "
    [ "$output" = "fable auto" ] \
        || { echo "AK-16: stdout='$output' (exit=$status) erwartet 'fable auto'"; false; }
    [ "$status" -eq 0 ] \
        || { echo "AK-16: Exit-Code $status erwartet 0"; false; }
}

# AK-8-unit: Ungültiger Override -> return 1 (kein exit), stdout leer, warn auf stderr
@test "AK-8-unit: ungueltig TATARA_ARCHITECT_MODEL=banane -> return 1, stdout leer" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export PATH='${STUB_PATH}'
        export TATARA_ARCHITECT_MODEL=banane
        main() { : ; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        resolve_architect_model
        echo \"EXIT:\$?\"
    "
    # return 1 erwartet: die Funktion darf KEIN exit ausfuehren (sonst wuerde
    # 'echo EXIT:...' nicht erreicht). Wenn exit aufgerufen wird, failt der Test
    # weil 'EXIT:1' nicht im Output steht.
    [[ "$output" == *"EXIT:1"* ]] \
        || { echo "AK-8-unit: Erwartet 'EXIT:1' im Output — Funktion hat moeglicherweise exit statt return genutzt. Output: '$output'"; false; }
    # Vor dem EXIT:-Marker darf kein Output stehen (stdout leer ausser der EXIT-Zeile)
    local before_exit
    before_exit="${output%%EXIT:*}"
    [ -z "$before_exit" ] \
        || { echo "AK-8-unit: Stdout vor EXIT-Marker nicht leer: '$before_exit'"; false; }
}

# ==============================================================================
# Unit-Tests fuer substitute_architect_model (AK-15)
# ==============================================================================

@test "AK-15a: substitute_architect_model ersetzt nur das ERSTE 'model: fable'" {
    # Input: 'model: fable' im Frontmatter (Zeile 3) + identische Zeile am Ende (Zeile 7)
    # Erwartung: Zeile 3 -> 'model: opus'; Zeile 7 bleibt 'model: fable'
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        main() { : ; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        printf '%s\n' \
            '---' \
            'name: architect' \
            'model: fable' \
            '---' \
            '' \
            'Some text about model: fable here.' \
            'model: fable' \
        | substitute_architect_model
    "
    [ "$status" -eq 0 ] \
        || { echo "AK-15a: Exit-Code $status erwartet 0"; false; }

    # Erste 'model:'-Zeile muss 'model: opus' sein
    local first_model_line
    first_model_line="$(printf '%s\n' "$output" | grep '^model:' | head -1)"
    [ "$first_model_line" = "model: opus" ] \
        || { echo "AK-15a: Erstes '^model:'-Vorkommen ist '$first_model_line', erwartet 'model: opus'"; false; }

    # Letzte 'model:'-Zeile (zweites Vorkommen auf Zeilenanfang) muss unveraendert 'model: fable' sein
    local last_model_line
    last_model_line="$(printf '%s\n' "$output" | grep '^model:' | tail -1)"
    [ "$last_model_line" = "model: fable" ] \
        || { echo "AK-15a: Zweites '^model:'-Vorkommen ist '$last_model_line', erwartet unveraendert 'model: fable'"; false; }

    # Inline-Zeile (kein Zeilenanfang) muss unveraendert 'model: fable' enthalten
    printf '%s\n' "$output" | grep -qF 'Some text about model: fable here.' \
        || { echo "AK-15a: Inline-Zeile 'Some text about model: fable here.' fehlt oder wurde veraendert"; false; }
}

@test "AK-15b: substitute_architect_model laesst Input ohne 'model: fable' byte-identisch" {
    local tmpfile="$BATS_TEST_TMPDIR/input_no_fable.txt"
    printf '%s\n' \
        '---' \
        'name: developer' \
        'model: sonnet' \
        '---' \
        '' \
        'Some content here.' > "$tmpfile"

    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        main() { : ; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        cat '${tmpfile}' | substitute_architect_model
    "
    [ "$status" -eq 0 ] \
        || { echo "AK-15b: Exit-Code $status erwartet 0"; false; }

    # Output muss byte-identisch zum Input sein
    local outfile="$BATS_TEST_TMPDIR/output_no_fable.txt"
    printf '%s\n' "$output" > "$outfile"
    cmp "$tmpfile" "$outfile" \
        || { echo "AK-15b: Output nicht byte-identisch zu Input (cmp fehlgeschlagen):"; diff "$tmpfile" "$outfile"; false; }
}

# ==============================================================================
# Hilfsfunktion: Volles ~/.claude-Verzeichnis aufsetzen (damit --check nicht
# wegen fehlender Globals failt, sondern wegen Policy-Logik)
# ==============================================================================

_setup_full_globals() {
    local claude_dir="${BATS_TEST_TMPDIR}/home/.claude"
    local agents_dir="${claude_dir}/agents"
    mkdir -p "$agents_dir"
    printf 'dummy\n' > "${claude_dir}/CLAUDE.md"
    printf 'dummy\n' > "${claude_dir}/software-development-workflow.md"
    for agent in architect architect-reviewer developer qa-reviewer security-reviewer test-writer; do
        printf 'dummy\n' > "${agents_dir}/${agent}.md"
    done
}

# ==============================================================================
# Blackbox-Tests fuer mode_bootstrap_globals (AK-7, AK-8, AK-9, AK-10)
# ==============================================================================

# AK-7: TATARA_ARCHITECT_MODEL=opus + Bootstrap in leerem ~/.claude ->
#         architect.md + architect-reviewer.md: 'model: opus';
#         developer.md + test-writer.md: 'model: sonnet';
#         qa-reviewer.md + security-reviewer.md: 'model: opus'
@test "AK-7: Bootstrap mit opus-Override schreibt korrekte Modell-Zeilen in alle Agent-Dateien" {
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_ARCHITECT_MODEL=opus
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        bash '${TATARA}' --bootstrap-globals
    "
    [ "$status" -eq 0 ] \
        || { echo "AK-7: Bootstrap Exit-Code $status erwartet 0. Output: $output"; false; }

    local agents_dir="${BATS_TEST_TMPDIR}/home/.claude/agents"

    # architect.md -> model: opus
    grep -q '^model: opus' "${agents_dir}/architect.md" \
        || { echo "AK-7: architect.md enthaelt nicht 'model: opus'. Inhalt:"; grep '^model:' "${agents_dir}/architect.md" 2>/dev/null || echo "(Datei fehlt)"; false; }

    # architect-reviewer.md -> model: opus
    grep -q '^model: opus' "${agents_dir}/architect-reviewer.md" \
        || { echo "AK-7: architect-reviewer.md enthaelt nicht 'model: opus'"; false; }

    # developer.md -> model: sonnet
    grep -q '^model: sonnet' "${agents_dir}/developer.md" \
        || { echo "AK-7: developer.md enthaelt nicht 'model: sonnet'. Inhalt:"; grep '^model:' "${agents_dir}/developer.md" 2>/dev/null || echo "(Datei fehlt)"; false; }

    # test-writer.md -> model: sonnet
    grep -q '^model: sonnet' "${agents_dir}/test-writer.md" \
        || { echo "AK-7: test-writer.md enthaelt nicht 'model: sonnet'"; false; }

    # qa-reviewer.md -> model: opus
    grep -q '^model: opus' "${agents_dir}/qa-reviewer.md" \
        || { echo "AK-7: qa-reviewer.md enthaelt nicht 'model: opus'"; false; }

    # security-reviewer.md -> model: opus
    grep -q '^model: opus' "${agents_dir}/security-reviewer.md" \
        || { echo "AK-7: security-reviewer.md enthaelt nicht 'model: opus'"; false; }
}

# AK-8: TATARA_ARCHITECT_MODEL=banane + Bootstrap -> Exit 1, stderr nennt 'banane',
#         KEINE Datei unter ~/.claude/agents/ angelegt
@test "AK-8: Ungültiger Override 'banane' -> Exit 1, stderr nennt Wert, keine agents-Dateien" {
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_ARCHITECT_MODEL=banane
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        bash '${TATARA}' --bootstrap-globals 2>&1
    "
    [ "$status" -eq 1 ] \
        || { echo "AK-8: Exit-Code $status erwartet 1"; false; }
    [[ "$output" == *"banane"* ]] \
        || { echo "AK-8: Output (stdout+stderr) enthaelt nicht 'banane': $output"; false; }

    # Keine agents-Dateien angelegt
    local agents_dir="${BATS_TEST_TMPDIR}/home/.claude/agents"
    if [[ -d "$agents_dir" ]]; then
        local count
        count="$(ls "$agents_dir" 2>/dev/null | wc -l | tr -d ' ')"
        [ "$count" -eq 0 ] \
            || { echo "AK-8: $count Dateien in agents/ angelegt obwohl ungültiger Override:"; ls "$agents_dir"; false; }
    fi
}

# AK-9: Idempotenz — architect.md mit 'model: fable' vorhanden, Bootstrap mit opus-Policy ->
#         Datei bleibt byte-identisch (cmp), stdout enthaelt 'behalten:'
@test "AK-9: Idempotenz — vorhandene architect.md bleibt unveraendert, stdout zeigt 'behalten:'" {
    local agents_dir="${BATS_TEST_TMPDIR}/home/.claude/agents"
    mkdir -p "$agents_dir"

    # Vorhandene Datei mit 'model: fable'
    printf '%s\n' \
        '---' \
        'name: architect' \
        'model: fable' \
        '---' \
        'Content here.' > "${agents_dir}/architect.md"

    local snapshot_file="$BATS_TEST_TMPDIR/architect_snapshot.md"
    cp "${agents_dir}/architect.md" "$snapshot_file"

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_ARCHITECT_MODEL=opus
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        bash '${TATARA}' --bootstrap-globals
    "
    [ "$status" -eq 0 ] \
        || { echo "AK-9: Exit-Code $status erwartet 0"; false; }

    # Datei muss byte-identisch geblieben sein
    cmp "${agents_dir}/architect.md" "$snapshot_file" \
        || { echo "AK-9: architect.md wurde modifiziert, byte-identisch erwartet:"; diff "$snapshot_file" "${agents_dir}/architect.md"; false; }

    # stdout muss 'behalten:' enthalten
    [[ "$output" == *"behalten:"* ]] \
        || { echo "AK-9: stdout enthaelt nicht 'behalten:'. Output: $output"; false; }
}

# AK-10: Lazy — nur developer.md fehlt, alle anderen vorhanden, ENV ungesetzt ->
#          kein claude-Call, developer.md wird mit 'model: sonnet' geschrieben
@test "AK-10: Lazy-Bootstrap schreibt nur fehlende developer.md, kein claude-Call" {
    local agents_dir="${BATS_TEST_TMPDIR}/home/.claude/agents"
    local claude_dir="${BATS_TEST_TMPDIR}/home/.claude"
    mkdir -p "$agents_dir"

    # Alle Dateien ausser developer.md anlegen
    printf 'dummy\n' > "${claude_dir}/CLAUDE.md"
    printf 'dummy\n' > "${claude_dir}/software-development-workflow.md"
    for agent in architect architect-reviewer qa-reviewer security-reviewer test-writer; do
        printf 'dummy\n' > "${agents_dir}/${agent}.md"
    done
    # developer.md absichtlich NICHT anlegen

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        unset TATARA_ARCHITECT_MODEL
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        bash '${TATARA}' --bootstrap-globals
    "
    [ "$status" -eq 0 ] \
        || { echo "AK-10: Exit-Code $status erwartet 0"; false; }

    # developer.md muss existieren und 'model: sonnet' enthalten
    [[ -f "${agents_dir}/developer.md" ]] \
        || { echo "AK-10: developer.md wurde nicht angelegt"; false; }
    grep -q '^model: sonnet' "${agents_dir}/developer.md" \
        || { echo "AK-10: developer.md enthaelt nicht 'model: sonnet'. Inhalt:"; grep '^model:' "${agents_dir}/developer.md" 2>/dev/null || echo "(kein model:-Feld)"; false; }

    # Kein claude-Call: Stub-Log darf nicht existieren oder leer sein
    if [[ -f "$CLAUDE_STUB_LOG" ]] && [[ -s "$CLAUDE_STUB_LOG" ]]; then
        echo "AK-10: Stub-Log enthaelt Eintraege obwohl kein claude-Call erlaubt:"
        cat "$CLAUDE_STUB_LOG"
        false
    fi
}

# ==============================================================================
# Blackbox-Tests fuer mode_check (AK-11, AK-12, AK-13, AK-14)
# WICHTIG M2: --check darf NIE einen 'claude -p'-Probe-Call machen.
# ==============================================================================

# AK-11: --check ohne Override, claude eingeloggt -> Policy-Zeile in stdout erwaehnt
#         'Architekt' + 'Modell' (oder 'Architect' + 'Model'); kein -p-Call
@test "AK-11: --check mit eingeloggtem claude -> Policy-Zeile in stdout, kein -p-Call" {
    _setup_full_globals

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOGGED_IN=1
        export CLAUDE_STUB_FABLE=ok
        unset TATARA_ARCHITECT_MODEL
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        bash '${TATARA}' --check
    "
    # stdout muss eine Zeile mit Architekt-Modell-Policy-Info enthalten
    # Exakter Text ist dem Entwickler freigestellt; wir pruefen auf Schluesselbegriffe
    local found_policy=0
    while IFS= read -r line; do
        # Kombinationen: Architekt+Modell, architect+model, rchitect+odel
        if [[ "$line" == *[Aa]rchitekt*[Mm]odell* ]] \
           || [[ "$line" == *[Aa]rchitect*[Mm]odel* ]] \
           || [[ "$line" == *[Aa]rchitekt*-*[Mm]odell* ]]; then
            found_policy=1
            break
        fi
    done <<< "$output"
    [ "$found_policy" -eq 1 ] \
        || { echo "AK-11: Keine Policy-Zeile mit 'Architekt-Modell' / 'architect model' in stdout gefunden. Vollstaendiger Output:"; printf '%s\n' "$output"; false; }

    # Kein -p-Call: --check darf nie proben
    if [[ -f "$CLAUDE_STUB_LOG" ]]; then
        if grep -qF '"-p"' "$CLAUDE_STUB_LOG" 2>/dev/null; then
            echo "AK-11: Stub-Log enthaelt -p-Call — --check darf nie proben:"
            cat "$CLAUDE_STUB_LOG"
            false
        fi
    fi
}

# AK-12: --check mit TATARA_ARCHITECT_MODEL=opus -> Policy-Zeile erwaehnt Override
@test "AK-12: --check mit TATARA_ARCHITECT_MODEL=opus -> Policy-Zeile erwaehnt 'override'" {
    _setup_full_globals

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_ARCHITECT_MODEL=opus
        export CLAUDE_STUB_LOGGED_IN=1
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        bash '${TATARA}' --check
    "
    # Policy-Zeile muss 'override' ODER 'TATARA_ARCHITECT_MODEL' erwaehnen
    local found_override=0
    while IFS= read -r line; do
        if [[ "$line" == *override* ]] || [[ "$line" == *TATARA_ARCHITECT_MODEL* ]]; then
            found_override=1
            break
        fi
    done <<< "$output"
    [ "$found_override" -eq 1 ] \
        || { echo "AK-12: Kein 'override'/'TATARA_ARCHITECT_MODEL' in stdout. Output: $output"; false; }
}

# AK-13: --check ohne claude (kein Stub im PATH), git+bd+Globals vorhanden ->
#         Policy-Zeile zeigt opus-bezogenen Status, Gesamt-Exit 0, kein -p-Call
@test "AK-13: --check ohne claude -> opus-Status in Policy-Zeile, Exit 0, kein -p-Call" {
    _setup_full_globals

    local no_claude_path
    no_claude_path="$(_path_no_claude)"

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${no_claude_path}'
        unset TATARA_ARCHITECT_MODEL
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        bash '${TATARA}' --check
    "
    # Exit 0: Policy ist Soft-Check; kein claude ist kein Hard-Fehler (opus-Fallback)
    [ "$status" -eq 0 ] \
        || { echo "AK-13: Exit-Code $status erwartet 0. Output: $output"; false; }

    # 'opus' muss in stdout erscheinen (Policy-Zeile zeigt Fallback-Grund)
    [[ "$output" == *"opus"* ]] \
        || { echo "AK-13: 'opus' nicht in stdout. Output: $output"; false; }

    # Kein -p-Call
    if [[ -f "$CLAUDE_STUB_LOG" ]] && [[ -s "$CLAUDE_STUB_LOG" ]]; then
        if grep -qF '"-p"' "$CLAUDE_STUB_LOG" 2>/dev/null; then
            echo "AK-13: Stub-Log enthaelt -p-Call — kein Probe ohne claude:"
            cat "$CLAUDE_STUB_LOG"
            false
        fi
    fi
}

# AK-14: --check mit ungültigem Override -> Exit 1, Restdiagnose (git/bd-Zeilen) in stdout
@test "AK-14: --check mit ungueltigem Override -> Exit 1, Restdiagnose in stdout" {
    _setup_full_globals

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_ARCHITECT_MODEL=banane
        export CLAUDE_STUB_LOGGED_IN=1
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        bash '${TATARA}' --check 2>&1
    "
    [ "$status" -eq 1 ] \
        || { echo "AK-14: Exit-Code $status erwartet 1. Output: $output"; false; }

    # Restdiagnose: git oder bd muss in stdout erscheinen
    local found_diag=0
    while IFS= read -r line; do
        if [[ "$line" == *"git"* ]] || [[ "$line" == *" bd "* ]] || [[ "$line" == *"[ok]"* ]]; then
            found_diag=1
            break
        fi
    done <<< "$output"
    [ "$found_diag" -eq 1 ] \
        || { echo "AK-14: Keine Restdiagnose (git/bd/[ok]-Zeile) in stdout bei Exit 1. Output: $output"; false; }
}

# ==============================================================================
# AK-18 — Privacy: Auth-Daten aus 'claude auth status' duerfen nie in Ausgabe erscheinen.
# Diese Tests sind Invarianten-Tests: gruen wenn kein Leak, rot wenn Impl Daten durchleitet.
# Aktuell gruen (kein auth-Call existent) — werden rot bei Implementierungsfehler.
# ==============================================================================

@test "AK-18a: --bootstrap-globals gibt keine Privacy-Marker aus" {
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOGGED_IN=1
        unset TATARA_ARCHITECT_MODEL
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        bash '${TATARA}' --bootstrap-globals 2>&1
    "
    [[ "$output" != *"subscriptionType"* ]] \
        || { echo "AK-18a: 'subscriptionType' in --bootstrap-globals Ausgabe sichtbar (Privacy-Leak)"; false; }
    [[ "$output" != *"x@y.z"* ]] \
        || { echo "AK-18a: E-Mail 'x@y.z' in --bootstrap-globals Ausgabe sichtbar (Privacy-Leak)"; false; }
    [[ "$output" != *"ORG-SECRET"* ]] \
        || { echo "AK-18a: 'ORG-SECRET' in --bootstrap-globals Ausgabe sichtbar (Privacy-Leak)"; false; }
}

@test "AK-18b: --check gibt keine Privacy-Marker aus" {
    _setup_full_globals

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOGGED_IN=1
        unset TATARA_ARCHITECT_MODEL
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        bash '${TATARA}' --check 2>&1
    "
    [[ "$output" != *"subscriptionType"* ]] \
        || { echo "AK-18b: 'subscriptionType' in --check Ausgabe sichtbar (Privacy-Leak)"; false; }
    [[ "$output" != *"x@y.z"* ]] \
        || { echo "AK-18b: E-Mail 'x@y.z' in --check Ausgabe sichtbar (Privacy-Leak)"; false; }
    [[ "$output" != *"ORG-SECRET"* ]] \
        || { echo "AK-18b: 'ORG-SECRET' in --check Ausgabe sichtbar (Privacy-Leak)"; false; }
}
