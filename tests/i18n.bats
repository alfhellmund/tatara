#!/usr/bin/env bats
# Tests fuer Phase 5 / Stufe M1 — i18n-Infrastruktur
#
# Jeder Test kontrolliert Sprache/Locale explizit — kein TATARA_LANG-Pinning
# in setup(). Locale-Isolation: jeder Test setzt LC_ALL/LANG/LC_MESSAGES
# explizit im bash -c-Block.
#
# Unit-Idiom (aus model_policy.bats):
#   main(){ :; }; source '$TATARA'; set +euo pipefail; <fn>

TATARA="/Users/alfhellmund/Development/tatara/tatara"
STUBS_DIR="/Users/alfhellmund/Development/tatara/tests/stubs"

setup() {
    # KEIN TATARA_LANG-Pinning — jeder Test setzt Locale selbst
    HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"

    PROJECTS_ROOT="$BATS_TEST_TMPDIR/dev"
    mkdir -p "$PROJECTS_ROOT"

    CLAUDE_STUB_LOG="$BATS_TEST_TMPDIR/claude_calls.log"
    CURL_STUB_LOG="$BATS_TEST_TMPDIR/curl_calls.log"
    export CLAUDE_STUB_LOG
    export CURL_STUB_LOG
    export HOME
    export PROJECTS_ROOT

    STUB_PATH="${STUBS_DIR}:${PATH}"
}

# Hilfs-Funktion: Volles ~/.claude-Verzeichnis anlegen (8 Dateien)
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
# I18N-AK-1 — detect_lang: LC_ALL=de_DE.UTF-8 → de
# ==============================================================================

@test "I18N-AK-1: detect_lang bei LC_ALL=de_DE.UTF-8 gibt 'de' aus" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        unset TATARA_LANG
        export LC_ALL=de_DE.UTF-8
        export LANG=de_DE.UTF-8
        export LC_MESSAGES=de_DE.UTF-8
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        result=\$(detect_lang 2>/dev/null)
        printf '%s' \"\$result\"
    "
    [ "$output" = "de" ] \
        || { echo "I18N-AK-1: detect_lang bei LC_ALL=de_DE.UTF-8 -> erwartet 'de', got '${output}'"; false; }
}

# ==============================================================================
# I18N-AK-2 — detect_lang: Prioritaet LC_ALL > LC_MESSAGES > LANG (2 Subfaelle)
# ==============================================================================

@test "I18N-AK-2a: detect_lang: LC_ALL leer + LC_MESSAGES=de_CH.UTF-8 + LANG=en_US.UTF-8 -> 'de'" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        unset TATARA_LANG
        unset LC_ALL
        export LC_MESSAGES=de_CH.UTF-8
        export LANG=en_US.UTF-8
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        result=\$(detect_lang 2>/dev/null)
        printf '%s' \"\$result\"
    "
    [ "$output" = "de" ] \
        || { echo "I18N-AK-2a: detect_lang mit LC_MESSAGES=de_CH + LANG=en_US -> erwartet 'de', got '${output}'"; false; }
}

@test "I18N-AK-2b: detect_lang: LC_ALL=en_US.UTF-8 + LC_MESSAGES=de_DE.UTF-8 -> 'en' (LC_ALL hat Prioritaet)" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        unset TATARA_LANG
        export LC_ALL=en_US.UTF-8
        export LC_MESSAGES=de_DE.UTF-8
        export LANG=de_DE.UTF-8
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        result=\$(detect_lang 2>/dev/null)
        printf '%s' \"\$result\"
    "
    [ "$output" = "en" ] \
        || { echo "I18N-AK-2b: detect_lang mit LC_ALL=en_US (trumpft LC_MESSAGES=de_DE) -> erwartet 'en', got '${output}'"; false; }
}

# ==============================================================================
# I18N-AK-3 — detect_lang: C, POSIX, leer → je 'en' (3 Subfaelle)
# ==============================================================================

@test "I18N-AK-3a: detect_lang: LC_ALL=C -> 'en'" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        unset TATARA_LANG
        export LC_ALL=C
        unset LC_MESSAGES
        unset LANG
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        result=\$(detect_lang 2>/dev/null)
        printf '%s' \"\$result\"
    "
    [ "$output" = "en" ] \
        || { echo "I18N-AK-3a: detect_lang mit LC_ALL=C -> erwartet 'en', got '${output}'"; false; }
}

@test "I18N-AK-3b: detect_lang: LC_ALL=POSIX -> 'en'" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        unset TATARA_LANG
        export LC_ALL=POSIX
        unset LC_MESSAGES
        unset LANG
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        result=\$(detect_lang 2>/dev/null)
        printf '%s' \"\$result\"
    "
    [ "$output" = "en" ] \
        || { echo "I18N-AK-3b: detect_lang mit LC_ALL=POSIX -> erwartet 'en', got '${output}'"; false; }
}

@test "I18N-AK-3c: detect_lang: alle Locale-Vars leer/ungesetzt -> 'en'" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        unset TATARA_LANG
        unset LC_ALL
        unset LC_MESSAGES
        unset LANG
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        result=\$(detect_lang 2>/dev/null)
        printf '%s' \"\$result\"
    "
    [ "$output" = "en" ] \
        || { echo "I18N-AK-3c: detect_lang ohne Locale-Vars -> erwartet 'en', got '${output}'"; false; }
}

# ==============================================================================
# I18N-AK-4 — detect_lang: Verschiedene Locale-Werte (5 Subfaelle)
# ==============================================================================

@test "I18N-AK-4a: detect_lang: LC_ALL=es_ES.UTF-8 -> 'en'" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        unset TATARA_LANG
        export LC_ALL=es_ES.UTF-8
        unset LC_MESSAGES
        unset LANG
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        result=\$(detect_lang 2>/dev/null)
        printf '%s' \"\$result\"
    "
    [ "$output" = "en" ] \
        || { echo "I18N-AK-4a: detect_lang mit LC_ALL=es_ES.UTF-8 -> erwartet 'en', got '${output}'"; false; }
}

@test "I18N-AK-4b: detect_lang: LC_ALL=de_AT.UTF-8 -> 'de'" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        unset TATARA_LANG
        export LC_ALL=de_AT.UTF-8
        unset LC_MESSAGES
        unset LANG
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        result=\$(detect_lang 2>/dev/null)
        printf '%s' \"\$result\"
    "
    [ "$output" = "de" ] \
        || { echo "I18N-AK-4b: detect_lang mit LC_ALL=de_AT.UTF-8 -> erwartet 'de', got '${output}'"; false; }
}

@test "I18N-AK-4c: detect_lang: LC_ALL=de_DE@euro -> 'de'" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        unset TATARA_LANG
        export LC_ALL=de_DE@euro
        unset LC_MESSAGES
        unset LANG
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        result=\$(detect_lang 2>/dev/null)
        printf '%s' \"\$result\"
    "
    [ "$output" = "de" ] \
        || { echo "I18N-AK-4c: detect_lang mit LC_ALL=de_DE@euro -> erwartet 'de', got '${output}'"; false; }
}

@test "I18N-AK-4d: detect_lang: LC_ALL=german -> 'de' (Legacy-Alias)" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        unset TATARA_LANG
        export LC_ALL=german
        unset LC_MESSAGES
        unset LANG
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        result=\$(detect_lang 2>/dev/null)
        printf '%s' \"\$result\"
    "
    [ "$output" = "de" ] \
        || { echo "I18N-AK-4d: detect_lang mit LC_ALL=german -> erwartet 'de', got '${output}'"; false; }
}

@test "I18N-AK-4e: detect_lang: LC_ALL=deutsch -> 'de' (Legacy-Alias)" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        unset TATARA_LANG
        export LC_ALL=deutsch
        unset LC_MESSAGES
        unset LANG
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        result=\$(detect_lang 2>/dev/null)
        printf '%s' \"\$result\"
    "
    [ "$output" = "de" ] \
        || { echo "I18N-AK-4e: detect_lang mit LC_ALL=deutsch -> erwartet 'de', got '${output}'"; false; }
}

# ==============================================================================
# I18N-AK-5 — Override TATARA_LANG schlaegt Locale (-h Ausgabe)
# ==============================================================================

@test "I18N-AK-5a: TATARA_LANG=en + LC_ALL=de_DE.UTF-8 -> tatara -h enthaelt 'USAGE', nicht 'NUTZUNG'" {
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_LANG=en
        export LC_ALL=de_DE.UTF-8
        export LANG=de_DE.UTF-8
        export LC_MESSAGES=de_DE.UTF-8
        bash '${TATARA}' -h 2>&1
    "
    [[ "$output" == *"USAGE"* ]] \
        || { echo "I18N-AK-5a: TATARA_LANG=en + de-Locale -> erwartet 'USAGE' in -h. Output: $output"; false; }
    [[ "$output" != *"NUTZUNG"* ]] \
        || { echo "I18N-AK-5a: TATARA_LANG=en + de-Locale -> 'NUTZUNG' darf nicht in -h erscheinen. Output: $output"; false; }
}

@test "I18N-AK-5b: TATARA_LANG=de + en-Locale -> tatara -h enthaelt 'NUTZUNG' nicht 'USAGE'; TATARA_LANG=en + en-Locale enthaelt 'USAGE' nicht 'NUTZUNG' (symmetrisch)" {
    # Prueft beide Richtungen in einem Test: Symmetrie beweist dass TATARA_LANG wirkt
    # und nicht nur der hart-kodierte Bestandstext.
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_LANG=de
        export LC_ALL=en_US.UTF-8
        export LANG=en_US.UTF-8
        export LC_MESSAGES=en_US.UTF-8
        bash '${TATARA}' -h 2>&1
    "
    [[ "$output" == *"NUTZUNG"* ]] \
        || { echo "I18N-AK-5b: TATARA_LANG=de + en-Locale -> erwartet 'NUTZUNG' in -h. Output: $output"; false; }
    [[ "$output" != *"USAGE"* ]] \
        || { echo "I18N-AK-5b: TATARA_LANG=de + en-Locale -> 'USAGE' darf nicht in -h erscheinen. Output: $output"; false; }

    # Symmetrie-Nachweis: TATARA_LANG=en + en-Locale muss 'USAGE' zeigen
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_LANG=en
        export LC_ALL=en_US.UTF-8
        export LANG=en_US.UTF-8
        export LC_MESSAGES=en_US.UTF-8
        bash '${TATARA}' -h 2>&1
    "
    [[ "$output" == *"USAGE"* ]] \
        || { echo "I18N-AK-5b Symmetrie: TATARA_LANG=en + en-Locale -> erwartet 'USAGE' in -h. Output: $output"; false; }
    [[ "$output" != *"NUTZUNG"* ]] \
        || { echo "I18N-AK-5b Symmetrie: TATARA_LANG=en + en-Locale -> 'NUTZUNG' darf nicht erscheinen. Output: $output"; false; }
}

# ==============================================================================
# I18N-AK-6 — TATARA_LANG='' (leer) + de-Locale -> Locale-Erkennung greift -> 'NUTZUNG'
# ==============================================================================

@test "I18N-AK-6: TATARA_LANG='' (leer) steuert ueber Locale: de-Locale -> 'NUTZUNG'; en-Locale -> 'USAGE' (kein Override)" {
    # Prueft beide Richtungen: leer + de = NUTZUNG; leer + en = USAGE.
    # Der zweite Subfall beweist, dass leer kein Override=de ist, sondern die
    # Locale-Erkennung greift. Dieser Subfall ist mit dem Bestandscode rot.
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_LANG=''
        export LC_ALL=de_DE.UTF-8
        export LANG=de_DE.UTF-8
        export LC_MESSAGES=de_DE.UTF-8
        bash '${TATARA}' -h 2>&1
    "
    [[ "$output" == *"NUTZUNG"* ]] \
        || { echo "I18N-AK-6: TATARA_LANG=leer + de-Locale -> erwartet 'NUTZUNG' in -h. Output: $output"; false; }

    # Symmetrie: leer + en-Locale -> muss 'USAGE' zeigen (Locale-Erkennung, kein Override)
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_LANG=''
        export LC_ALL=en_US.UTF-8
        export LANG=en_US.UTF-8
        export LC_MESSAGES=en_US.UTF-8
        bash '${TATARA}' -h 2>&1
    "
    [[ "$output" == *"USAGE"* ]] \
        || { echo "I18N-AK-6 Symmetrie: TATARA_LANG=leer + en-Locale -> erwartet 'USAGE' in -h. Output: $output"; false; }
    [[ "$output" != *"NUTZUNG"* ]] \
        || { echo "I18N-AK-6 Symmetrie: TATARA_LANG=leer + en-Locale -> 'NUTZUNG' darf nicht erscheinen. Output: $output"; false; }
}

# ==============================================================================
# I18N-AK-7 — TATARA_LANG=banane: non-fatal, Fallback, Warnung mit Schluesselwoertern
# ==============================================================================

@test "I18N-AK-7: TATARA_LANG=banane + LC_ALL=de_DE.UTF-8 -> tatara -h Exit 0, enthaelt 'NUTZUNG', Warnung mit 'banane' und erlaubten Werten" {
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_LANG=banane
        export LC_ALL=de_DE.UTF-8
        export LANG=de_DE.UTF-8
        export LC_MESSAGES=de_DE.UTF-8
        bash '${TATARA}' -h 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "I18N-AK-7: tatara -h mit TATARA_LANG=banane -> erwartet Exit 0, got $status. Output: $output"; false; }
    [[ "$output" == *"NUTZUNG"* ]] \
        || { echo "I18N-AK-7: -h funktioniert nicht (kein 'NUTZUNG' mit de-Locale-Fallback). Output: $output"; false; }
    # Warnung muss den ungültigen Wert nennen
    [[ "$output" == *"banane"* ]] \
        || { echo "I18N-AK-7: Warnung nennt den ungültigen Wert 'banane' nicht. Output: $output"; false; }
    # Warnung muss erlaubte Werte nennen (de und en)
    local found_de=0 found_en=0
    [[ "$output" == *" de"* || "$output" == *"'de'"* || "$output" == *'"de"'* ]] && found_de=1
    [[ "$output" == *" en"* || "$output" == *"'en'"* || "$output" == *'"en"'* ]] && found_en=1
    [ "$found_de" -eq 1 ] \
        || { echo "I18N-AK-7: Warnung nennt erlaubten Wert 'de' nicht. Output: $output"; false; }
    [ "$found_en" -eq 1 ] \
        || { echo "I18N-AK-7: Warnung nennt erlaubten Wert 'en' nicht. Output: $output"; false; }
}

# ==============================================================================
# I18N-AK-8 — msg KEY ARG: Argument eingesetzt; de ≠ en
# Annahme: Key 'tatara_project_ready' mit einem %s-Argument (Projektname)
# Falls der Implementierer einen anderen Key waehlt, muss dieser Test angepasst werden.
# ==============================================================================

@test "I18N-AK-8: msg tatara_project_ready testprojekt: Arg eingesetzt; TATARA_LANG=de != TATARA_LANG=en" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_LANG=de
        export LC_ALL=C
        unset LC_MESSAGES LANG
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        result_de=\$(msg tatara_project_ready 'testprojekt' 2>/dev/null)
        printf '%s' \"\$result_de\"
    "
    local result_de="$output"
    # Argument muss eingesetzt sein (kein literal '%s' im Output)
    [[ "$result_de" != *"%s"* ]] \
        || { echo "I18N-AK-8: msg tatara_project_ready 'testprojekt' (de) -> '%s' literal im Output (Arg nicht eingesetzt). Output: $result_de"; false; }
    # Argument muss vorkommen
    [[ "$result_de" == *"testprojekt"* ]] \
        || { echo "I18N-AK-8: msg tatara_project_ready (de) -> 'testprojekt' nicht im Output. Output: $result_de"; false; }

    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_LANG=en
        export LC_ALL=C
        unset LC_MESSAGES LANG
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        result_en=\$(msg tatara_project_ready 'testprojekt' 2>/dev/null)
        printf '%s' \"\$result_en\"
    "
    local result_en="$output"
    # en-Ergebnis muss ebenfalls Arg enthalten
    [[ "$result_en" == *"testprojekt"* ]] \
        || { echo "I18N-AK-8: msg tatara_project_ready (en) -> 'testprojekt' nicht im Output. Output: $result_en"; false; }
    # de und en muessen unterschiedlich sein
    [ "$result_de" != "$result_en" ] \
        || { echo "I18N-AK-8: msg tatara_project_ready de-Ausgabe == en-Ausgabe (Parität verletzt). de='$result_de' en='$result_en'"; false; }
}

# ==============================================================================
# I18N-AK-9 — Injection: msg KEY '100%s' -> Output enthaelt literal '100%s'
# Annahme: derselbe Key wie AK-8 (tatara_project_ready, ein %s-Slot)
# ==============================================================================

@test "I18N-AK-9: msg tatara_project_ready '100%s' -> Output enthaelt literal '100%s' (kein Format-Injection)" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_LANG=de
        export LC_ALL=C
        unset LC_MESSAGES LANG
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        result=\$(msg tatara_project_ready '100%s' 2>/dev/null)
        printf '%s' \"\$result\"
    "
    [[ "$output" == *'100%s'* ]] \
        || { echo "I18N-AK-9: msg tatara_project_ready '100%s' -> '100%s' nicht literal im Output (Format-Injection!). Output: $output"; false; }
}

# ==============================================================================
# I18N-AK-10 — msg gibtsnicht_xyz: stdout enthaelt '??gibtsnicht_xyz??'; RC 0; stderr-Hinweis
# ==============================================================================

@test "I18N-AK-10: msg gibtsnicht_xyz -> stdout '??gibtsnicht_xyz??', RC 0, stderr-Hinweis auf fehlenden Key" {
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_LANG=de
        export LC_ALL=C
        unset LC_MESSAGES LANG
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        result=\$(msg gibtsnicht_xyz 2>/tmp/i18n_ak10_stderr_\$\$)
        rc=\$?
        printf 'RC:%d\n' \$rc
        printf 'OUT:[%s]\n' \"\$result\"
        printf 'STDERR:[%s]\n' \"\$(cat /tmp/i18n_ak10_stderr_\$\$ 2>/dev/null)\"
        rm -f /tmp/i18n_ak10_stderr_\$\$
    "
    [[ "$output" == *"RC:0"* ]] \
        || { echo "I18N-AK-10: msg gibtsnicht_xyz -> erwartet RC:0. Output: $output"; false; }
    [[ "$output" == *"??gibtsnicht_xyz??"* ]] \
        || { echo "I18N-AK-10: msg gibtsnicht_xyz -> erwartet '??gibtsnicht_xyz??' im stdout. Output: $output"; false; }
    # stderr muss Hinweis enthalten (Key-Name oder 'missing' oder 'key' oder 'warn')
    local found_stderr_hint=0
    [[ "$output" == *"gibtsnicht_xyz"* && "$output" == *"STDERR:["* ]] && {
        # Extrahiere STDERR-Teil aus output und prüfe ob er nicht leer ist
        local stderr_part
        stderr_part="$(printf '%s' "$output" | grep 'STDERR:' | sed 's/STDERR:\[//' | sed 's/\]$//')"
        [[ -n "$stderr_part" ]] && found_stderr_hint=1
    }
    [ "$found_stderr_hint" -eq 1 ] \
        || { echo "I18N-AK-10: msg gibtsnicht_xyz -> kein stderr-Hinweis auf fehlenden Key. Output: $output"; false; }
}

# ==============================================================================
# I18N-AK-11 — Parität: Keys aus CATALOG extrahieren (ERE), msg_fmt de + en nicht leer
# ==============================================================================

@test "I18N-AK-11: CATALOG-Keys >= 1; fuer jeden Key msg_fmt de + en nicht leer" {
    # Prüft: grep -E '^[[:space:]]+[a-z0-9_]+\)$' liefert mindestens 1 Key
    # und für jeden Key ist msg_fmt unter de UND en nicht-leer.
    local catalog_keys
    catalog_keys="$(
        awk '/BEGIN MESSAGE CATALOG/,/END MESSAGE CATALOG/' "${TATARA}" \
        | grep -E '^[[:space:]]+[a-z0-9_]+\)$' \
        | sed 's/[[:space:]]//g; s/)$//'
    )"
    local key_count
    key_count="$(printf '%s\n' "$catalog_keys" | grep -c '.' || true)"
    [ "$key_count" -ge 1 ] \
        || { echo "I18N-AK-11: Keine Keys im MESSAGE CATALOG gefunden (erwartet >= 1). Moegliche Ursache: Marker fehlt oder Keys nicht im erwarteten Format."; false; }

    # Fuer jeden Key: msg_fmt de und en pruefen
    local key
    while IFS= read -r key; do
        [ -n "$key" ] || continue
        run bash -c "
            set +euo pipefail
            export HOME='${BATS_TEST_TMPDIR}/home'
            export PATH='${STUB_PATH}'
            export LC_ALL=C
            unset LC_MESSAGES LANG TATARA_LANG
            main() { :; }
            source '${TATARA}' >/dev/null 2>&1 || true
            set +euo pipefail
            de_val=\$(msg_fmt '${key}' de 2>/dev/null)
            en_val=\$(msg_fmt '${key}' en 2>/dev/null)
            printf 'DE:[%s]\n' \"\$de_val\"
            printf 'EN:[%s]\n' \"\$en_val\"
        "
        [[ "$output" != *"DE:[]"* ]] \
            || { echo "I18N-AK-11: Key '${key}' -> msg_fmt de ist leer. Output: $output"; false; }
        [[ "$output" != *"EN:[]"* ]] \
            || { echo "I18N-AK-11: Key '${key}' -> msg_fmt en ist leer. Output: $output"; false; }
    done <<< "$catalog_keys"
}

# ==============================================================================
# I18N-AK-12 — Format-Direktiven-Parität: printf-Direktiven de == en pro Key
# ==============================================================================

@test "I18N-AK-12: Format-Direktiven-Parität: für jeden CATALOG-Key sind %s/%d/%-Direktiven unter de == en" {
    local catalog_keys
    catalog_keys="$(
        awk '/BEGIN MESSAGE CATALOG/,/END MESSAGE CATALOG/' "${TATARA}" \
        | grep -E '^[[:space:]]+[a-z0-9_]+\)$' \
        | sed 's/[[:space:]]//g; s/)$//'
    )"
    [ -n "$catalog_keys" ] \
        || { echo "I18N-AK-12: Keine Keys im MESSAGE CATALOG gefunden — Impl fehlt."; false; }

    local key
    while IFS= read -r key; do
        [ -n "$key" ] || continue
        run bash -c "
            set +euo pipefail
            export HOME='${BATS_TEST_TMPDIR}/home'
            export PATH='${STUB_PATH}'
            export LC_ALL=C
            unset LC_MESSAGES LANG TATARA_LANG
            main() { :; }
            source '${TATARA}' >/dev/null 2>&1 || true
            set +euo pipefail
            de_val=\$(msg_fmt '${key}' de 2>/dev/null)
            en_val=\$(msg_fmt '${key}' en 2>/dev/null)
            # %% entfernen, dann %s/%d/% zaehlen
            de_dirs=\$(printf '%s' \"\$de_val\" | sed 's/%%//g' | grep -o '%[sd%]' | sort | tr -d '\n')
            en_dirs=\$(printf '%s' \"\$en_val\" | sed 's/%%//g' | grep -o '%[sd%]' | sort | tr -d '\n')
            printf 'KEY:[${key}]\n'
            printf 'DE_DIRS:[%s]\n' \"\$de_dirs\"
            printf 'EN_DIRS:[%s]\n' \"\$en_dirs\"
        "
        local de_dirs en_dirs
        de_dirs="$(printf '%s' "$output" | grep 'DE_DIRS:' | sed 's/DE_DIRS:\[//; s/\]$//')"
        en_dirs="$(printf '%s' "$output" | grep 'EN_DIRS:' | sed 's/EN_DIRS:\[//; s/\]$//')"
        [ "$de_dirs" = "$en_dirs" ] \
            || { echo "I18N-AK-12: Key '${key}' -> Format-Direktiven-Parität verletzt: de='${de_dirs}' en='${en_dirs}'. Full output: $output"; false; }
    done <<< "$catalog_keys"
}

# ==============================================================================
# I18N-AK-15 — mode_check: Sprachzeile mit 'override' bei TATARA_LANG; 'locale' ohne
# ==============================================================================

@test "I18N-AK-15a: mode_check mit TATARA_LANG=en -> Ausgabe enthaelt Sprachzeile mit 'override'" {
    _setup_full_globals
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        export TATARA_LANG=en
        export LC_ALL=de_DE.UTF-8
        export LANG=de_DE.UTF-8
        export LC_MESSAGES=de_DE.UTF-8
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        mode_check 2>&1 || true
    "
    [[ "$output" == *"override"* ]] \
        || { echo "I18N-AK-15a: mode_check mit TATARA_LANG=en -> erwartet 'override' in Sprachzeile. Output: $output"; false; }
}

@test "I18N-AK-15b: mode_check ohne TATARA_LANG (de-Locale) -> Ausgabe enthaelt Sprachzeile mit 'locale'" {
    _setup_full_globals
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        unset TATARA_LANG
        export LC_ALL=de_DE.UTF-8
        export LANG=de_DE.UTF-8
        export LC_MESSAGES=de_DE.UTF-8
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        mode_check 2>&1 || true
    "
    [[ "$output" == *"locale"* ]] \
        || { echo "I18N-AK-15b: mode_check ohne TATARA_LANG (de-Locale) -> erwartet 'locale' in Sprachzeile. Output: $output"; false; }
}

# ==============================================================================
# I18N-AK-H1 — err-Praefix lokalisiert: en -> '[error]'; de -> '[fehler]'
# ==============================================================================

@test "I18N-AK-H1a: TATARA_LANG=en + leerer Projektname -> stderr enthaelt '[error]', nicht '[fehler]'" {
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export TATARA_LANG=en
        export LC_ALL=en_US.UTF-8
        export LANG=en_US.UTF-8
        export LC_MESSAGES=en_US.UTF-8
        bash '${TATARA}' '' 2>&1
    "
    [[ "$output" == *"[error]"* ]] \
        || { echo "I18N-AK-H1a: TATARA_LANG=en + leerer Name -> erwartet '[error]' im Output. Output: $output"; false; }
    [[ "$output" != *"[fehler]"* ]] \
        || { echo "I18N-AK-H1a: TATARA_LANG=en + leerer Name -> '[fehler]' darf nicht erscheinen. Output: $output"; false; }
}

@test "I18N-AK-H1b: TATARA_LANG=de + leerer Projektname -> stderr enthaelt '[fehler]', nicht '[error]'" {
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export TATARA_LANG=de
        export LC_ALL=de_DE.UTF-8
        export LANG=de_DE.UTF-8
        export LC_MESSAGES=de_DE.UTF-8
        bash '${TATARA}' '' 2>&1
    "
    [[ "$output" == *"[fehler]"* ]] \
        || { echo "I18N-AK-H1b: TATARA_LANG=de + leerer Name -> erwartet '[fehler]' im Output. Output: $output"; false; }
    [[ "$output" != *"[error]"* ]] \
        || { echo "I18N-AK-H1b: TATARA_LANG=de + leerer Name -> '[error]' darf nicht erscheinen. Output: $output"; false; }
}

# ==============================================================================
# I18N-AK-21 — msg_fmt() definiert VOR BEGIN AUTO-SNAPSHOT TEMPLATES-Marker
# ==============================================================================

@test "I18N-AK-21: msg_fmt() ist im Skript VOR dem '# === BEGIN AUTO-SNAPSHOT TEMPLATES ===' Marker definiert" {
    local msg_fmt_line snapshot_line
    msg_fmt_line="$(grep -n '^msg_fmt()' "${TATARA}" | head -1 | cut -d: -f1)"
    snapshot_line="$(grep -n '# === BEGIN AUTO-SNAPSHOT TEMPLATES ===' "${TATARA}" | head -1 | cut -d: -f1)"

    [ -n "$msg_fmt_line" ] \
        || { echo "I18N-AK-21: 'msg_fmt()' nicht im Skript gefunden — Impl fehlt."; false; }
    [ -n "$snapshot_line" ] \
        || { echo "I18N-AK-21: '# === BEGIN AUTO-SNAPSHOT TEMPLATES ===' Marker nicht gefunden."; false; }
    [ "$msg_fmt_line" -lt "$snapshot_line" ] \
        || { echo "I18N-AK-21: msg_fmt() (Zeile $msg_fmt_line) ist NICHT vor BEGIN AUTO-SNAPSHOT (Zeile $snapshot_line)."; false; }
}
