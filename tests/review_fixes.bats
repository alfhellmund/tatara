#!/usr/bin/env bats
# Tests fuer 6 Findings aus dem Skript-Gesamtreview — Red-Phase (TDD).
#
# Jeder Test ist einem Finding zugeordnet (FIX-M1, FIX-M3, FIX-M4, FIX-M5, FIX-L1, FIX-L7).
# Alle Tests schlagen fehl, solange die entsprechenden Fixes fehlen — kein Test
# faellt aufgrund von Harness-Problemen aus.
#
# Locale-Kontrolle: setup() setzt KEIN TATARA_LANG — jeder Test steuert selbst.
# PATH-Isolation: Stubs-DIR wird in STUB_PATH eingebunden; Tests mit echtem git
# verwenden _path_real_git() wie in kickoff.bats.

TATARA="/Users/alfhellmund/Development/tatara/tatara"
STUBS_DIR="/Users/alfhellmund/Development/tatara/tests/stubs"

setup() {
    # KEIN TATARA_LANG-Pinning — jeder Test setzt Sprache/Locale selbst.
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

# ---------------------------------------------------------------------------
# Hilfs-Funktionen (nach Muster aus kickoff.bats)
# ---------------------------------------------------------------------------

# Volles ~/.claude-Verzeichnis anlegen (8 Dateien: CLAUDE.md, workflow.md, 6 Agenten)
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

# PATH ohne claude-Binary.
_path_no_claude() {
    local nodir="$BATS_TEST_TMPDIR/noclaudebin_$$"
    mkdir -p "$nodir"
    cp "$STUBS_DIR/git"  "$nodir/git"
    cp "$STUBS_DIR/bd"   "$nodir/bd"
    cp "$STUBS_DIR/curl" "$nodir/curl"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "Darwin\n"' > "$nodir/uname"
    chmod +x "$nodir/uname"
    local clean="" dir
    local IFS=':'
    for dir in $PATH; do
        [ -n "$dir" ] && [ -x "$dir/claude" ] && continue
        clean="${clean:+$clean:}$dir"
    done
    printf '%s' "${nodir}:${clean}"
}

# PATH mit echtem git, Stubs fuer bd/claude/curl.
# Gibt leeren String zurueck (exit 1) wenn kein echtes git gefunden.
_path_real_git() {
    local realdir="$BATS_TEST_TMPDIR/real_git_$$"
    mkdir -p "$realdir"
    local real_git=""
    local dir
    local IFS=':'
    for dir in $PATH; do
        [ -n "$dir" ] || continue
        [[ "$dir" == "$STUBS_DIR" ]] && continue
        if [ -x "$dir/git" ]; then
            real_git="$dir/git"
            break
        fi
    done
    if [[ -z "$real_git" ]]; then
        printf ''
        return 1
    fi
    ln -sf "$real_git" "$realdir/git"
    cp "$STUBS_DIR/bd"     "$realdir/bd"
    cp "$STUBS_DIR/claude" "$realdir/claude"
    cp "$STUBS_DIR/curl"   "$realdir/curl"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "Darwin\n"' > "$realdir/uname"
    chmod +x "$realdir/uname"
    local clean="" d
    for d in $PATH; do
        [ -n "$d" ] || continue
        [[ "$d" == "$STUBS_DIR" ]] && continue
        clean="${clean:+$clean:}$d"
    done
    printf '%s' "${realdir}:${clean}"
}

# ==============================================================================
# FIX-M1 — kickoff_instructions: /reload-skills-Zeile muss unter TATARA_LANG=en
#           englisch sein (kein hartkodiertes Deutsch)
# ==============================================================================

# FIX-M1a: Unter TATARA_LANG=en enthaelt die kickoff_instructions-Ausgabe
# '/reload-skills', aber NICHT den deutschen Text 'falls nicht angeboten'.
@test "FIX-M1a: TATARA_LANG=en -> kickoff_instructions-Zeile mit /reload-skills ist englisch (kein 'falls nicht angeboten')" {
    # FIX-M1: Die Zeile mit /reload-skills ist bisher hartkodiert deutsch.
    # Nach Fix: Unter TATARA_LANG=en muss diese Zeile auf Englisch ausgegeben werden.
    # Teststrategie: TATARA_INTERACTIVE=0 + CLAUDECODE ungesetzt + claude eingeloggt
    # -> kickoff_handoff druckt Anleitung (non-interaktiv -> kein exec).
    _setup_full_globals
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        export TATARA_LANG=en
        export TATARA_INTERACTIVE=0
        export LC_ALL=en_US.UTF-8
        export LANG=en_US.UTF-8
        export LC_MESSAGES=en_US.UTF-8
        unset CLAUDECODE
        bash '${TATARA}' proj </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "FIX-M1a: Exit-Code $status erwartet 0. Output: $output"; false; }
    # /reload-skills muss erscheinen
    [[ "$output" == *"/reload-skills"* ]] \
        || { echo "FIX-M1a: '/reload-skills' fehlt im Output. Output: $output"; false; }
    # Deutscher Text darf NICHT erscheinen
    [[ "$output" != *"falls nicht angeboten"* ]] \
        || { echo "FIX-M1a: TATARA_LANG=en -> 'falls nicht angeboten' (hart-deutsch) erscheint im Output — Fix fehlt. Output: $output"; false; }
    [[ "$output" != *"dann erneut"* ]] \
        || { echo "FIX-M1a: TATARA_LANG=en -> 'dann erneut' (hart-deutsch) erscheint im Output — Fix fehlt. Output: $output"; false; }
}

# FIX-M1b: Unter TATARA_LANG=de erscheint 'falls nicht angeboten' weiterhin
# (Rueckwaertskompatibilitaet / de-Pfad unveraendert).
@test "FIX-M1b: TATARA_LANG=de -> kickoff_instructions enthaelt weiterhin 'falls nicht angeboten' (de-Pfad unveraendert)" {
    # FIX-M1: Negativtest: Im de-Pfad soll der bisherige Text erhalten bleiben.
    _setup_full_globals
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        export TATARA_LANG=de
        export TATARA_INTERACTIVE=0
        export LC_ALL=de_DE.UTF-8
        export LANG=de_DE.UTF-8
        export LC_MESSAGES=de_DE.UTF-8
        unset CLAUDECODE
        bash '${TATARA}' proj </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "FIX-M1b: Exit-Code $status erwartet 0. Output: $output"; false; }
    [[ "$output" == *"/reload-skills"* ]] \
        || { echo "FIX-M1b: '/reload-skills' fehlt im de-Output. Output: $output"; false; }
    [[ "$output" == *"falls nicht angeboten"* ]] \
        || { echo "FIX-M1b: TATARA_LANG=de -> 'falls nicht angeboten' fehlt im Output (de-Pfad soll unveraendert bleiben). Output: $output"; false; }
}

# ==============================================================================
# FIX-M3 — Snapshot-Delimiter-Kollisions-Guard:
#           --snapshot-globals bricht ab, wenn eine Quelldatei einen Delimiter
#           als exakte Zeile enthaelt, statt ein korruptes Skript zu schreiben.
# ==============================================================================

@test "FIX-M3: --snapshot-globals bricht mit Fehler ab, wenn Agenten-Datei 'AGENT_END' als Zeile enthaelt (kein korruptes Skript)" {
    # FIX-M3: Enthaelt eine Quelldatei eine Zeile die exakt 'AGENT_END' ist,
    # muss mode_snapshot_globals mit Exit != 0 und Fehlermeldung abbrechen.
    # Die Skript-Kopie (tatara_copy) muss unveraendert bleiben (bash -n sauber).
    _setup_full_globals

    # Eine Agenten-Datei mit Delimiter-Kollision praeperieren
    local collision_file="${BATS_TEST_TMPDIR}/home/.claude/agents/architect.md"
    printf 'normaler Inhalt\nAGENT_END\nnoch mehr Inhalt\n' > "$collision_file"

    # Auf einer Kopie arbeiten — --snapshot-globals wuerde das aufrufende Skript selbst veraendern!
    local tatara_copy="${BATS_TEST_TMPDIR}/tatara_m3_copy"
    cp "${TATARA}" "$tatara_copy"
    chmod +x "$tatara_copy"

    # Pruefen ob bash -n vor dem Aufruf sauber ist (Baseline)
    bash -n "$tatara_copy" \
        || { echo "FIX-M3: tatara_copy ist bereits vor dem Aufruf bash -n-unsauber — Test-Setup-Fehler"; false; }

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export TATARA_LANG=de
        unset CLAUDECODE
        bash '$tatara_copy' --snapshot-globals </dev/null 2>&1
    "
    # Muss mit Exit != 0 abbrechen
    [ "$status" -ne 0 ] \
        || { echo "FIX-M3: --snapshot-globals lieferte Exit 0 trotz AGENT_END-Kollision — Kollisions-Guard fehlt. Output: $output"; false; }

    # Fehlermeldung muss Kollision / Datei / Delimiter erwaehnen
    local found_collision_hint=0
    [[ "$output" == *"AGENT_END"*       ]] && found_collision_hint=1
    [[ "$output" == *"Kollision"*       ]] && found_collision_hint=1
    [[ "$output" == *"collision"*       ]] && found_collision_hint=1
    [[ "$output" == *"delimiter"*       ]] && found_collision_hint=1
    [[ "$output" == *"Delimiter"*       ]] && found_collision_hint=1
    [[ "$output" == *"architect.md"*    ]] && found_collision_hint=1
    [ "$found_collision_hint" -eq 1 ] \
        || { echo "FIX-M3: Fehlermeldung nennt weder 'AGENT_END' noch Dateiname noch 'Kollision'/'collision'. Output: $output"; false; }

    # Kopie muss bash -n-sauber geblieben sein (kein korruptes Skript geschrieben)
    bash -n "$tatara_copy" \
        || { echo "FIX-M3: tatara_copy ist nach fehlgeschlagenem --snapshot-globals bash -n-unsauber — korruptes Skript wurde dennoch geschrieben!"; false; }
}

# ==============================================================================
# FIX-M4 — git-Identity-Preflight:
#           tatara <name> bricht ab, wenn git-Identity fehlt — VOR mkdir.
# ==============================================================================

@test "FIX-M4: fehlende git-Identity (kein .gitconfig, GIT_*-Vars ungesetzt) -> Exit != 0 vor Projekt-mkdir, Meldung erwaehnt user.email oder git config" {
    # FIX-M4: Ohne git user.email/user.name wuerde 'git commit' spaeter scheitern.
    # Nach Fix bricht tatara VOR dem Anlegen des Projektverzeichnisses ab.
    # Voraussetzung: echtes git (Stub-git ignoriert identity-Pruefung).
    if ! git --version >/dev/null 2>&1; then
        skip "echtes git nicht verfuegbar"
    fi
    local real_git_path
    real_git_path="$(_path_real_git)" || { skip "echtes git nicht im PATH auffindbar"; }
    [ -n "$real_git_path" ] || skip "echtes git nicht im PATH auffindbar"

    _setup_full_globals

    # Leeres HOME ohne .gitconfig -> keine git-Identity
    # GIT_*-Vars loeschen + GIT_CONFIG_NOSYSTEM=1 damit kein System-gitconfig greift
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${real_git_path}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        export TATARA_LANG=de
        export GIT_CONFIG_NOSYSTEM=1
        unset GIT_AUTHOR_NAME
        unset GIT_AUTHOR_EMAIL
        unset GIT_COMMITTER_NAME
        unset GIT_COMMITTER_EMAIL
        unset CLAUDECODE
        bash '${TATARA}' proj </dev/null 2>&1
    "
    # Muss abbrechen
    [ "$status" -ne 0 ] \
        || { echo "FIX-M4: Exit-Code 0 obwohl keine git-Identity — Preflight fehlt. Output: $output"; false; }

    # Fehlermeldung muss user.email oder git config erwaehnen
    local found_identity_hint=0
    [[ "$output" == *"user.email"*  ]] && found_identity_hint=1
    [[ "$output" == *"user.name"*   ]] && found_identity_hint=1
    [[ "$output" == *"git config"*  ]] && found_identity_hint=1
    [[ "$output" == *"Identity"*    ]] && found_identity_hint=1
    [[ "$output" == *"identity"*    ]] && found_identity_hint=1
    [ "$found_identity_hint" -eq 1 ] \
        || { echo "FIX-M4: Fehlermeldung erwaehnt weder 'user.email' noch 'user.name' noch 'git config'. Output: $output"; false; }

    # Projektverzeichnis darf NICHT existieren (Abbruch VOR mkdir)
    [ ! -d "${BATS_TEST_TMPDIR}/dev/proj" ] \
        || { echo "FIX-M4: Projektverzeichnis '${BATS_TEST_TMPDIR}/dev/proj' wurde trotz fehlendem Preflight angelegt — Abbruch kam zu spaet. Output: $output"; false; }
}

# ==============================================================================
# FIX-M5 — fable_available unter CLAUDECODE=1 kein -p-Call:
#           Im CLAUDECODE-Kontext darf fable_available keinen claude -p-Aufruf machen.
# ==============================================================================

@test "FIX-M5: CLAUDECODE=1 + Globals-Heilung -> CLAUDE_STUB_LOG enthaelt keinen -p-Aufruf (fable_available macht keinen -p-Call)" {
    # FIX-M5: Unter CLAUDECODE=1 laeuft tatara bereits in einer Claude-Session.
    # Ein verschachtelter 'claude -p'-Call in fable_available ist unerwuenscht und
    # nach Fix verboten. Nachweis via CLAUDE_STUB_LOG: kein '-p'-Argument darf auftauchen.
    # Leeres HOME (Globals fehlen -> Heilung via ensure_globals -> fable_available-Pfad).

    # claude-Stub ist eingeloggt, damit fable_available bis zum -p-Probe-Call kommt
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        export CLAUDECODE=1
        export TATARA_LANG=de
        export TATARA_INTERACTIVE=0
        unset TATARA_ARCHITECT_MODEL
        bash '${TATARA}' proj </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "FIX-M5: Exit-Code $status erwartet 0 (Projekt soll angelegt werden). Output: $output"; false; }

    # Projektverzeichnis muss existieren
    [ -d "${BATS_TEST_TMPDIR}/dev/proj" ] \
        || { echo "FIX-M5: Projekt 'proj' wurde nicht angelegt. Output: $output"; false; }

    # Kein -p-Aufruf im CLAUDE_STUB_LOG
    if [ -f "$CLAUDE_STUB_LOG" ]; then
        # Muster: -p als eigenstaendiges Argument (nicht Teil eines laengeren Strings)
        if grep -Eq '(^|[[:space:]"])-p([[:space:]"]|$)' "$CLAUDE_STUB_LOG"; then
            echo "FIX-M5: CLAUDE_STUB_LOG enthaelt einen '-p'-Aufruf unter CLAUDECODE=1 — fable_available macht verschachtelten -p-Call. Log:"
            cat "$CLAUDE_STUB_LOG"
            echo "Output: $output"
            false
        fi
    fi
    # Wenn kein Log existiert: kein claude-Aufruf -> kein -p-Call -> Test besteht
    # (falls CLAUDECODE=1 -> ensure_claude returniert direkt ohne Call -> kein Log normal)
}

# ==============================================================================
# FIX-L1 — TATARA_INTERACTIVE-Validierung:
#           Ungueltige Werte erzeugen eine Warnung; Exit bleibt 0.
# ==============================================================================

@test "FIX-L1a: TATARA_INTERACTIVE=banane + tatara -h -> Exit 0, -h funktioniert, Warnung nennt 'TATARA_INTERACTIVE' und 'banane'" {
    # FIX-L1: Ein ungültiger TATARA_INTERACTIVE-Wert (weder 1, 0 noch leer)
    # muss eine Warnung ausgeben — analog zur TATARA_LANG-Validierung.
    # Der Exit-Code bleibt 0 (non-fatal).
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export TATARA_INTERACTIVE=banane
        export TATARA_LANG=de
        export LC_ALL=C
        unset CLAUDECODE
        bash '${TATARA}' -h 2>&1
    "
    # Exit 0 (non-fatal)
    [ "$status" -eq 0 ] \
        || { echo "FIX-L1a: TATARA_INTERACTIVE=banane -> Exit $status erwartet 0 (non-fatal). Output: $output"; false; }

    # -h muss funktionieren (USAGE-Sektion erscheint)
    local found_help=0
    [[ "$output" == *"NUTZUNG"* ]] && found_help=1
    [[ "$output" == *"USAGE"*   ]] && found_help=1
    [ "$found_help" -eq 1 ] \
        || { echo "FIX-L1a: TATARA_INTERACTIVE=banane -> -h zeigt keine Hilfe (kein 'NUTZUNG'/'USAGE'). Output: $output"; false; }

    # Warnung muss 'TATARA_INTERACTIVE' nennen
    [[ "$output" == *"TATARA_INTERACTIVE"* ]] \
        || { echo "FIX-L1a: Warnung nennt 'TATARA_INTERACTIVE' nicht. Output: $output"; false; }

    # Warnung muss den ungültigen Wert 'banane' nennen
    [[ "$output" == *"banane"* ]] \
        || { echo "FIX-L1a: Warnung nennt den ungültigen Wert 'banane' nicht. Output: $output"; false; }
}

@test "FIX-L1b: TATARA_INTERACTIVE=1 und TATARA_INTERACTIVE=0 und leer -> kein Warn-Output mit 'TATARA_INTERACTIVE'" {
    # FIX-L1: Gueltige Werte (1, 0, leer) duerfen KEINE Warnung ueber TATARA_INTERACTIVE erzeugen.
    for val in "1" "0" ""; do
        run bash -c "
            export HOME='${BATS_TEST_TMPDIR}/home'
            export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
            export PATH='${STUB_PATH}'
            export TATARA_INTERACTIVE='${val}'
            export TATARA_LANG=de
            export LC_ALL=C
            unset CLAUDECODE
            bash '${TATARA}' -h 2>&1
        "
        [ "$status" -eq 0 ] \
            || { echo "FIX-L1b: TATARA_INTERACTIVE='${val}' -> Exit $status erwartet 0. Output: $output"; false; }
        # Kein TATARA_INTERACTIVE-Warn-Output fuer gueltige Werte
        if [[ "$output" == *"TATARA_INTERACTIVE"* ]]; then
            # Pruefe ob es sich um eine Warnung handelt (nicht nur den Hilfetext)
            # Hilfetext erwaehnt TATARA_INTERACTIVE legitim — suche nach Warnungs-Praefixen
            local warn_found=0
            [[ "$output" == *"[warn]"*  && "$output" == *"TATARA_INTERACTIVE"* ]] && warn_found=1
            [[ "$output" == *"[warnung]"* && "$output" == *"TATARA_INTERACTIVE"* ]] && warn_found=1
            # Auch ohne expliziten Praefix: ungueltige Werte wuerden 'banane' aehnlichen Text enthalten
            # Hier: val ist gueltig, daher kein Warntext erwartet
            if [ "$warn_found" -eq 1 ]; then
                echo "FIX-L1b: TATARA_INTERACTIVE='${val}' (gueltig) -> unerwartete Warnung ueber TATARA_INTERACTIVE. Output: $output"
                false
            fi
        fi
    done
}

# ==============================================================================
# FIX-L7 — ueberzaehlige Argumente:
#           tatara <name> <desc> <extra...> warnt, dass zusaetzliche Argumente
#           ignoriert werden; Projekt wird trotzdem angelegt (Exit 0).
# ==============================================================================

@test "FIX-L7: tatara proj wort1 wort2 wort3 (3 Extra-Args) -> Warnung ueber ignorierte/ueberzaehlige Argumente; Projekt 'proj' angelegt; Exit 0" {
    # FIX-L7: Mehr als 2 Argumente (name + desc) -> Warnung; kein Abbruch.
    # Aktueller Bestand: mode_tatara nimmt '$@' still, ignoriert arg3+ ohne Warnung.
    _setup_full_globals
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        export TATARA_LANG=de
        export TATARA_INTERACTIVE=0
        export LC_ALL=C
        unset CLAUDECODE
        bash '${TATARA}' proj wort1 wort2 wort3 </dev/null 2>&1
    "
    # Projekt soll trotzdem angelegt werden
    [ "$status" -eq 0 ] \
        || { echo "FIX-L7: Exit-Code $status erwartet 0 (Warnung non-fatal, Projekt angelegt). Output: $output"; false; }

    # Projektverzeichnis muss existieren
    [ -d "${BATS_TEST_TMPDIR}/dev/proj" ] \
        || { echo "FIX-L7: Projekt 'proj' nicht angelegt. Output: $output"; false; }

    # Warnung ueber ignorierte/ueberzaehlige Argumente muss im Output erscheinen
    local found_warn=0
    [[ "$output" == *"ignorier"*    ]] && found_warn=1   # ignoriert/ignoriert werden
    [[ "$output" == *"ignored"*     ]] && found_warn=1
    [[ "$output" == *"ueberzaehlig"* ]] && found_warn=1
    [[ "$output" == *"überzählig"*  ]] && found_warn=1
    [[ "$output" == *"extra"*       ]] && found_warn=1
    [[ "$output" == *"zu viel"*     ]] && found_warn=1
    [[ "$output" == *"Anführungszeichen"* ]] && found_warn=1   # Hinweis: desc in quotes
    [[ "$output" == *"Anfuehrungszeichen"* ]] && found_warn=1
    [[ "$output" == *"quotes"*      ]] && found_warn=1
    [[ "$output" == *"wort2"*       ]] && found_warn=1   # Extra-Arg selbst genannt
    [[ "$output" == *"wort3"*       ]] && found_warn=1
    [ "$found_warn" -eq 1 ] \
        || { echo "FIX-L7: Keine Warnung ueber ueberzaehlige/ignorierte Argumente im Output. Output: $output"; false; }
}
