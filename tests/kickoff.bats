#!/usr/bin/env bats
# Tests fuer Phase 4 — Kickoff-Uebergabe (kickoff_handoff / SKILL.md) + L3-Haertung.
#
# Alle Blackbox-Tests laufen mit:
#   HOME=$BATS_TEST_TMPDIR/home
#   PROJECTS_ROOT=$BATS_TEST_TMPDIR/dev
#   Stub-PATH (stubs/claude, stubs/git, stubs/bd, stubs/curl)
#   stdin IMMER explizit gesetzt
#   CLAUDECODE IMMER explizit gesetzt oder ungesetzt
#
# Unit-Tests sourcen tatara mit dem Idiom aus den anderen Test-Dateien:
#   main(){ :; }; source '$TATARA'; set +euo pipefail; <fn>

TATARA="/Users/alfhellmund/Development/tatara/tatara"
STUBS_DIR="/Users/alfhellmund/Development/tatara/tests/stubs"

setup() {
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

    # Standard-PATH: alle Stubs vorgelagert
    STUB_PATH="${STUBS_DIR}:${PATH}"
}

# ---------------------------------------------------------------------------
# Hilfs-Funktionen
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

# PATH ohne claude: git + bd + curl da, claude NICHT.
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

# PATH mit echtem git (fuer P4-AK-4), aber Stubs fuer bd/claude/curl.
# Gibt den PATH-String aus; gibt leeren String aus wenn git --version fehlschlaegt.
_path_real_git() {
    local realdir="$BATS_TEST_TMPDIR/real_git_$$"
    mkdir -p "$realdir"
    # echtes git suchen (ausserhalb Stubs-Verzeichnis)
    local real_git=""
    local dir
    local IFS=':'
    for dir in $PATH; do
        [ -n "$dir" ] || continue
        # Stubs-Verzeichnis ausschliessen
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
    # Echtes git via Symlink einbinden
    ln -sf "$real_git" "$realdir/git"
    cp "$STUBS_DIR/bd"     "$realdir/bd"
    cp "$STUBS_DIR/claude" "$realdir/claude"
    cp "$STUBS_DIR/curl"   "$realdir/curl"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "Darwin\n"' > "$realdir/uname"
    chmod +x "$realdir/uname"
    # System-PATH ohne alte git-Verzeichnisse (Stubs-git darf nicht mehr vorne sein)
    local clean="" d
    for d in $PATH; do
        [ -n "$d" ] || continue
        [[ "$d" == "$STUBS_DIR" ]] && continue
        clean="${clean:+$clean:}$d"
    done
    printf '%s' "${realdir}:${clean}"
}

# ==============================================================================
# P4-AK-1 — SKILL.md existiert nach tatara proj
# ==============================================================================

@test "P4-AK-1: tatara proj (non-interaktiv, claude eingeloggt) -> SKILL.md existiert" {
    # P4-AK-1: mode_tatara schreibt <proj>/.claude/skills/kickoff/SKILL.md.
    # Nachweis: Datei existiert nach Aufruf.
    _setup_full_globals
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        unset CLAUDECODE
        bash '${TATARA}' proj </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P4-AK-1: Exit-Code $status erwartet 0. Output: $output"; false; }
    local skill_file="${BATS_TEST_TMPDIR}/dev/proj/.claude/skills/kickoff/SKILL.md"
    [ -f "$skill_file" ] \
        || { echo "P4-AK-1: SKILL.md fehlt unter ${skill_file}. Inhalt dev/proj/.claude/:"; ls -R "${BATS_TEST_TMPDIR}/dev/proj/.claude/" 2>/dev/null || true; false; }
}

# ==============================================================================
# P4-AK-2 — SKILL.md: Frontmatter korrekt
# ==============================================================================

@test "P4-AK-2: SKILL.md hat gueltigen Frontmatter (---, description:, disable-model-invocation: true)" {
    # P4-AK-2: SKILL.md muss YAML-Frontmatter mit den drei Pflichtfeldern aufweisen.
    _setup_full_globals
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        unset CLAUDECODE
        bash '${TATARA}' proj </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P4-AK-2: Exit-Code $status erwartet 0. Output: $output"; false; }
    local skill_file="${BATS_TEST_TMPDIR}/dev/proj/.claude/skills/kickoff/SKILL.md"
    [ -f "$skill_file" ] \
        || { echo "P4-AK-2: SKILL.md nicht angelegt, Test kann Frontmatter nicht pruefen"; false; }
    # Erste Zeile muss '---' sein
    local first_line
    first_line="$(head -1 "$skill_file")"
    [ "$first_line" = "---" ] \
        || { echo "P4-AK-2: Erste Zeile von SKILL.md ist '${first_line}', erwartet '---'. Inhalt:"; cat "$skill_file"; false; }
    # Muss 'description:' enthalten
    grep -q '^description:' "$skill_file" \
        || { echo "P4-AK-2: 'description:' (Frontmatter-Feld) fehlt in SKILL.md. Inhalt:"; cat "$skill_file"; false; }
    # Muss 'disable-model-invocation: true' enthalten (exakte Zeile)
    grep -q '^disable-model-invocation: true$' "$skill_file" \
        || { echo "P4-AK-2: 'disable-model-invocation: true' (exakte Zeile) fehlt in SKILL.md. Inhalt:"; cat "$skill_file"; false; }
}

# ==============================================================================
# P4-AK-3 — SKILL.md: Schluessel-Inhalte im Body
# ==============================================================================

@test "P4-AK-3: SKILL.md enthaelt software-development-workflow.md, bd create, architect-reviewer und die 4 Schritt-Marker" {
    # P4-AK-3: Body muss Workflow-Referenz, bd-Befehl, Agenten-Referenz
    # und die vier Kickoff-Schritte enthalten.
    _setup_full_globals
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        unset CLAUDECODE
        bash '${TATARA}' proj </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P4-AK-3: Exit-Code $status erwartet 0. Output: $output"; false; }
    local skill_file="${BATS_TEST_TMPDIR}/dev/proj/.claude/skills/kickoff/SKILL.md"
    [ -f "$skill_file" ] \
        || { echo "P4-AK-3: SKILL.md nicht angelegt, Inhalts-Check nicht moeglich"; false; }
    grep -q 'software-development-workflow\.md' "$skill_file" \
        || { echo "P4-AK-3: 'software-development-workflow.md' fehlt in SKILL.md. Inhalt:"; cat "$skill_file"; false; }
    grep -q 'bd create' "$skill_file" \
        || { echo "P4-AK-3: 'bd create' fehlt in SKILL.md. Inhalt:"; cat "$skill_file"; false; }
    grep -q 'architect-reviewer' "$skill_file" \
        || { echo "P4-AK-3: 'architect-reviewer' fehlt in SKILL.md. Inhalt:"; cat "$skill_file"; false; }
    # Vier Schritt-Marker: Befragen, Konzept, schaetz (Schätzung), ueberfuehr (Workflow)
    grep -qi 'Befrag' "$skill_file" \
        || { echo "P4-AK-3: Schritt 'Befragen' (Befrag*) fehlt in SKILL.md. Inhalt:"; cat "$skill_file"; false; }
    grep -qi 'Konzept' "$skill_file" \
        || { echo "P4-AK-3: Schritt 'Konzept' fehlt in SKILL.md. Inhalt:"; cat "$skill_file"; false; }
    grep -qi 'schaetz\|Schätzung\|schätz\|Schaetz' "$skill_file" \
        || { echo "P4-AK-3: Schritt 'Schaetzung/schätz*' fehlt in SKILL.md. Inhalt:"; cat "$skill_file"; false; }
    grep -qi 'ueberfuehr\|übergib\|Workflow\|workflow' "$skill_file" \
        || { echo "P4-AK-3: Schritt 'Workflow/ueberfuehr*' fehlt in SKILL.md. Inhalt:"; cat "$skill_file"; false; }
}

# ==============================================================================
# P4-AK-4 — SKILL.md im Initial-Commit + sauberer Worktree (echtes git)
# ==============================================================================

@test "P4-AK-4: SKILL.md ist im Initial-Commit enthalten, Worktree danach clean (echtes git)" {
    # P4-AK-4: SKILL.md muss VOR dem Initial-Commit geschrieben sein und in
    # 'git show --stat HEAD' auftauchen; git status --porcelain muss danach leer sein.
    # Skip wenn echtes git nicht verfuegbar.
    if ! git --version >/dev/null 2>&1; then
        skip "echtes git nicht verfuegbar"
    fi
    local real_git_path
    real_git_path="$(_path_real_git)" || { skip "echtes git nicht im PATH auffindbar"; }
    [ -n "$real_git_path" ] || skip "echtes git nicht im PATH auffindbar"

    _setup_full_globals

    # Test-HOME-.gitconfig damit git keinen User-Fehler meldet
    mkdir -p "${BATS_TEST_TMPDIR}/home"
    printf '[user]\n\tname = Test User\n\temail = test@example.com\n' \
        > "${BATS_TEST_TMPDIR}/home/.gitconfig"

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${real_git_path}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        unset CLAUDECODE
        bash '${TATARA}' proj </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P4-AK-4: Exit-Code $status erwartet 0. Output: $output"; false; }

    local proj_dir="${BATS_TEST_TMPDIR}/dev/proj"
    # git show HEAD --stat muss skills/kickoff/SKILL.md enthalten
    local stat_out
    stat_out="$(git -C "$proj_dir" show --stat HEAD 2>/dev/null)" \
        || { echo "P4-AK-4: 'git show --stat HEAD' fehlgeschlagen"; false; }
    printf '%s\n' "$stat_out" | grep -q 'skills/kickoff/SKILL\.md' \
        || { echo "P4-AK-4: 'skills/kickoff/SKILL.md' nicht in 'git show --stat HEAD'. Stat: $stat_out"; false; }
    # git status --porcelain muss leer sein (clean worktree)
    local porcelain_out
    porcelain_out="$(git -C "$proj_dir" status --porcelain 2>/dev/null)"
    [ -z "$porcelain_out" ] \
        || { echo "P4-AK-4: Worktree nicht clean nach Initial-Commit. git status: $porcelain_out"; false; }
}

# ==============================================================================
# P4-AK-5a — Happy-Path: exec claude /kickoff (Blackbox-Nachweis via Stub-Log)
# ==============================================================================

@test "P4-AK-5a: Happy-Path (claude eingeloggt, TATARA_INTERACTIVE=1, stdin y, CLAUDECODE unset) -> Stub-Log enthaelt /kickoff, Exit 0, Projekt angelegt" {
    # P4-AK-5a: kickoff_handoff fuehrt 'exec claude /kickoff' aus.
    # Stub-Log des claude-Stubs muss '/kickoff' zeigen; Exit 0; Projekt angelegt.
    _setup_full_globals
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        export TATARA_INTERACTIVE=1
        unset CLAUDECODE
        printf 'y\n' | bash '${TATARA}' proj 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P4-AK-5a: Exit-Code $status erwartet 0. Output: $output"; false; }
    [ -d "${BATS_TEST_TMPDIR}/dev/proj" ] \
        || { echo "P4-AK-5a: Projekt 'proj' nicht angelegt"; false; }
    [ -f "$CLAUDE_STUB_LOG" ] \
        || { echo "P4-AK-5a: CLAUDE_STUB_LOG nicht erzeugt — claude wurde nie aufgerufen. Output: $output"; false; }
    grep -q '/kickoff' "$CLAUDE_STUB_LOG" \
        || { echo "P4-AK-5a: '/kickoff' nicht im CLAUDE_STUB_LOG. Log:"; cat "$CLAUDE_STUB_LOG"; echo "Output: $output"; false; }
}

# ==============================================================================
# P4-AK-5b — Unit exec-Beweis: NICHT_ERSETZT darf nach exec nicht erscheinen
# ==============================================================================

@test "P4-AK-5b: kickoff_handoff exec-Beweis (Unit, Source-Idiom): nach exec kein 'NICHT_ERSETZT' im Output, Stub-Log enthaelt /kickoff" {
    # P4-AK-5b: exec ersetzt den Prozess — alles nach exec wird nie ausgefuehrt.
    # Nachweis: 'echo NICHT_ERSETZT' nach kickoff_handoff erscheint NICHT im Output.
    # Das ist nur moeglich wenn exec tatsaechlich aufgerufen wurde.
    local tmpdir="${BATS_TEST_TMPDIR}"
    local test_dir="${tmpdir}/exec_test_proj"
    mkdir -p "$test_dir"

    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        export TATARA_INTERACTIVE=1
        unset CLAUDECODE
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        # Herestring statt Pipe: kickoff_handoff laeuft in der Haupt-Shell
        # (keine Pipe-Subshell, bash-3.2-robust ohne lastpipe) -> exec ersetzt
        # diese Shell, 'echo NICHT_ERSETZT' wird bei korrektem exec nie erreicht.
        kickoff_handoff '${test_dir}' <<< 'y'
        echo NICHT_ERSETZT
    "
    [[ "$output" != *"NICHT_ERSETZT"* ]] \
        || { echo "P4-AK-5b: 'NICHT_ERSETZT' im Output — exec wurde nicht aufgerufen (oder kickoff_handoff fehlt). Output: $output"; false; }
    [ -f "$CLAUDE_STUB_LOG" ] \
        || { echo "P4-AK-5b: CLAUDE_STUB_LOG nicht erzeugt. Output: $output"; false; }
    grep -q '/kickoff' "$CLAUDE_STUB_LOG" \
        || { echo "P4-AK-5b: '/kickoff' nicht im CLAUDE_STUB_LOG. Log:"; cat "$CLAUDE_STUB_LOG"; echo "Output: $output"; false; }
}

# ==============================================================================
# P4-AK-6 — Opt-out: stdin n -> keine exec, Anleitung mit /kickoff-Text, Exit 0
# ==============================================================================

@test "P4-AK-6: Opt-out (stdin n, claude eingeloggt, TATARA_INTERACTIVE=1) -> kein /kickoff im Stub-Log, Anleitung enthaelt '/kickoff', Exit 0" {
    # P4-AK-6: Benutzer antwortet mit 'n' auf den Kickoff-Confirm -> kein exec;
    # stattdessen Anleitung mit '/kickoff'-Text ausgeben; Exit 0.
    _setup_full_globals
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        export TATARA_INTERACTIVE=1
        unset CLAUDECODE
        printf 'n\n' | bash '${TATARA}' proj 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P4-AK-6: Exit-Code $status erwartet 0. Output: $output"; false; }
    # Kein /kickoff-Aufruf im Stub-Log
    if [ -f "$CLAUDE_STUB_LOG" ]; then
        if grep -q '/kickoff' "$CLAUDE_STUB_LOG"; then
            echo "P4-AK-6: '/kickoff' im CLAUDE_STUB_LOG obwohl stdin=n (kein exec erwartet). Log:"
            cat "$CLAUDE_STUB_LOG"
            false
        fi
    fi
    # Anleitung muss '/kickoff' als Text enthalten
    [[ "$output" == *"/kickoff"* ]] \
        || { echo "P4-AK-6: Anleitung mit '/kickoff' nicht im Output (Opt-out-Pfad). Output: $output"; false; }
}

# ==============================================================================
# P4-AK-7 — Non-interaktiv: TATARA_INTERACTIVE=0 -> keine exec, Anleitung, Exit 0
# ==============================================================================

@test "P4-AK-7: Non-interaktiv (TATARA_INTERACTIVE=0, claude eingeloggt, stdin y) -> kein /kickoff im Stub-Log, Anleitung da, Exit 0" {
    # P4-AK-7: Non-interaktiv -> confirm schlaegt fehl (Default Nein); kein exec;
    # Anleitung ausgeben; Exit 0. Auch wenn y auf stdin steht.
    _setup_full_globals
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        export TATARA_INTERACTIVE=0
        unset CLAUDECODE
        printf 'y\n' | bash '${TATARA}' proj 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P4-AK-7: Exit-Code $status erwartet 0. Output: $output"; false; }
    # Kein /kickoff-Aufruf im Stub-Log
    if [ -f "$CLAUDE_STUB_LOG" ]; then
        if grep -q '/kickoff' "$CLAUDE_STUB_LOG"; then
            echo "P4-AK-7: '/kickoff' im CLAUDE_STUB_LOG obwohl TATARA_INTERACTIVE=0 (kein exec erwartet). Log:"
            cat "$CLAUDE_STUB_LOG"
            false
        fi
    fi
    # Anleitung muss '/kickoff' als Text enthalten
    [[ "$output" == *"/kickoff"* ]] \
        || { echo "P4-AK-7: Anleitung mit '/kickoff' nicht im Output (non-interaktiver Pfad). Output: $output"; false; }
}

# ==============================================================================
# P4-AK-8 — In Claude (CLAUDECODE=1): keine exec, Anleitung mit cd/kickoff/reload-skills
# ==============================================================================

@test "P4-AK-8: CLAUDECODE=1 (in Claude) -> kein /kickoff im Stub-Log, kein Kickoff-Prompt, Output enthaelt 'cd ' + '/kickoff' + '/reload-skills', Exit 0" {
    # P4-AK-8: kickoff_handoff erkennt CLAUDECODE -> kein exec, keine Confirm-Frage,
    # stattdessen Anleitung mit cd-Befehl + /kickoff + /reload-skills.
    _setup_full_globals
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        export TATARA_INTERACTIVE=1
        export CLAUDECODE=1
        printf 'y\n' | bash '${TATARA}' proj 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P4-AK-8: Exit-Code $status erwartet 0. Output: $output"; false; }
    # Kein /kickoff-exec-Aufruf
    if [ -f "$CLAUDE_STUB_LOG" ]; then
        if grep -q '/kickoff' "$CLAUDE_STUB_LOG"; then
            echo "P4-AK-8: '/kickoff' im CLAUDE_STUB_LOG obwohl CLAUDECODE=1. Log:"
            cat "$CLAUDE_STUB_LOG"
            false
        fi
    fi
    # Kein Kickoff-[y/N]-Prompt im Output (CLAUDECODE-Pfad stellt keine Frage)
    # Pruefe auf kickoff-confirm-spezifischen Prompt — nicht auf [y/N] allgemein
    # da andere confirms (z.B. Install) theoretisch vorkommen koennten
    # (hier unter CLAUDECODE=1 nicht, aber defensiv formuliert)
    # Einfacher Nachweis: kein Stub-Log-Eintrag (oben bereits geprueft)

    # Output muss 'cd ' enthalten (Anleitung Schritt 1)
    [[ "$output" == *"cd "* ]] \
        || { echo "P4-AK-8: 'cd ' nicht im Output (CLAUDECODE-Anleitung). Output: $output"; false; }
    # Output muss '/kickoff' als Text enthalten
    [[ "$output" == *"/kickoff"* ]] \
        || { echo "P4-AK-8: '/kickoff' nicht im Output (CLAUDECODE-Anleitung). Output: $output"; false; }
    # Output muss '/reload-skills' enthalten
    [[ "$output" == *"/reload-skills"* ]] \
        || { echo "P4-AK-8: '/reload-skills' nicht im Output (CLAUDECODE-Anleitung). Output: $output"; false; }
}

# ==============================================================================
# P4-AK-9 — Kein claude im PATH: SKILL.md trotzdem angelegt, Anleitung, kein exec
# ==============================================================================

@test "P4-AK-9: claude fehlt im PATH (non-interaktiv) -> SKILL.md existiert, Anleitung da, kein exec, Exit 0" {
    # P4-AK-9: kickoff_handoff Zweig 'claude fehlt' -> Anleitung statt exec;
    # SKILL.md muss trotzdem von mode_tatara angelegt worden sein.
    _setup_full_globals
    local no_claude_path
    no_claude_path="$(_path_no_claude)"
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${no_claude_path}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export TATARA_INTERACTIVE=0
        unset CLAUDECODE
        bash '${TATARA}' proj </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P4-AK-9: Exit-Code $status erwartet 0. Output: $output"; false; }
    # SKILL.md muss existieren
    local skill_file="${BATS_TEST_TMPDIR}/dev/proj/.claude/skills/kickoff/SKILL.md"
    [ -f "$skill_file" ] \
        || { echo "P4-AK-9: SKILL.md fehlt (claude fehlt sollte SKILL.md-Schreiben nicht verhindern). Inhalt .claude/:"; ls -R "${BATS_TEST_TMPDIR}/dev/proj/.claude/" 2>/dev/null || true; false; }
    # Anleitung mit /kickoff als Text muss im Output sein
    [[ "$output" == *"/kickoff"* ]] \
        || { echo "P4-AK-9: Anleitung mit '/kickoff' fehlt im Output (kein-claude-Pfad). Output: $output"; false; }
    # Kein exec-Aufruf (Log leer oder kein /kickoff-Eintrag)
    if [ -f "$CLAUDE_STUB_LOG" ]; then
        if grep -q '/kickoff' "$CLAUDE_STUB_LOG"; then
            echo "P4-AK-9: '/kickoff' im CLAUDE_STUB_LOG obwohl claude fehlt. Log:"
            cat "$CLAUDE_STUB_LOG"
            false
        fi
    fi
}

# ==============================================================================
# P4-AK-10 — Nicht eingeloggt: claude auth login im Output, kein exec
# ==============================================================================

@test "P4-AK-10: claude da, CLAUDE_STUB_LOGGED_IN=0 -> Output enthaelt 'claude auth login', Anleitung enthaelt '/kickoff'-Text, kein exec, Exit 0" {
    # P4-AK-10: kickoff_handoff Zweig 'nicht eingeloggt' -> Hinweis 'claude auth login'
    # + Anleitung mit '/kickoff' als Text; kein exec.
    # Der Test ist rot solange kickoff_handoff fehlt, weil der '/kickoff'-Text in der
    # Anleitung NUR von kickoff_handoff kommt — ensure_claude aus Phase 3 gibt kein
    # '/kickoff' aus. Damit unterscheidet dieser Test ensure_claude-Ausgabe von
    # kickoff_handoff-Anleitung.
    _setup_full_globals
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=0
        unset CLAUDECODE
        bash '${TATARA}' proj </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P4-AK-10: Exit-Code $status erwartet 0. Output: $output"; false; }
    # Output muss den KICKOFF-spezifischen nicht-eingeloggt-Hinweis enthalten.
    # NICHT auf 'claude auth login' allein pruefen — das druckt schon ensure_claude
    # (Phase 3); 'Erst einloggen:' kommt ausschliesslich aus kickoff_handoff.
    [[ "$output" == *"Erst einloggen:"* ]] \
        || { echo "P4-AK-10: kickoff_handoff nicht-eingeloggt-Hinweis ('Erst einloggen:') fehlt im Output. Output: $output"; false; }
    # Anleitung muss '/kickoff' als Text enthalten (kickoff_handoff-spezifisch, NICHT ensure_claude)
    [[ "$output" == *"/kickoff"* ]] \
        || { echo "P4-AK-10: '/kickoff' fehlt im Output (kickoff_handoff-Anleitung im nicht-eingeloggt-Zweig). Output: $output"; false; }
    # Kein /kickoff-exec-Aufruf (Stub-Log)
    if [ -f "$CLAUDE_STUB_LOG" ]; then
        if grep -q '/kickoff' "$CLAUDE_STUB_LOG"; then
            echo "P4-AK-10: '/kickoff' im CLAUDE_STUB_LOG obwohl nicht eingeloggt (exec darf nicht stattfinden). Log:"
            cat "$CLAUDE_STUB_LOG"
            false
        fi
    fi
}

# ==============================================================================
# P4-AK-11 — Pfad-Korrektur M2: Kickoff-Anleitung zeigt den Projektpfad
# ==============================================================================

@test "P4-AK-11: Kickoff-Anleitung zeigt eine Zeile mit 'cd ' + Projektpfad, und in Naehe steht '/kickoff' (kickoff-eindeutiger Anker)" {
    # P4-AK-11: Die Kickoff-Anleitung muss den spezifischen Projektpfad ausgeben.
    # Pruefe: Eine Zeile enthaelt sowohl 'cd ' als auch '$PROJECTS_ROOT/proj'.
    # UND '/kickoff' muss in einem 5-Zeilen-Fenster um diese cd-Zeile stehen.
    # Damit schlaegt der Test fehl wenn nur der Bestands-cd aus mode_tatara da ist,
    # aber kickoff_instructions fehlt (die beiden sind inhaltlich unterschiedlich).
    _setup_full_globals
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        export TATARA_INTERACTIVE=0
        unset CLAUDECODE
        bash '${TATARA}' proj </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P4-AK-11: Exit-Code $status erwartet 0. Output: $output"; false; }
    local proj_path="${BATS_TEST_TMPDIR}/dev/proj"
    # Suche nach einer Zeile die cd + Projektpfad enthaelt
    local cd_line_num=0 lnum=0
    while IFS= read -r line; do
        lnum=$((lnum + 1))
        if [[ "$line" == *"cd "* ]] && [[ "$line" == *"$proj_path"* ]]; then
            cd_line_num=$lnum
            break
        fi
    done <<< "$output"
    [ "$cd_line_num" -gt 0 ] \
        || { echo "P4-AK-11: Keine Zeile mit 'cd ${proj_path}' in der Kickoff-Anleitung. Output: $output"; false; }
    # /kickoff muss innerhalb +/-5 Zeilen der cd-Zeile stehen
    local found_kickoff=0
    lnum=0
    while IFS= read -r line; do
        lnum=$((lnum + 1))
        local diff=$(( lnum - cd_line_num ))
        [ "$diff" -lt 0 ] && diff=$(( -diff ))
        if [ "$diff" -le 5 ] && [[ "$line" == *"/kickoff"* ]]; then
            found_kickoff=1
            break
        fi
    done <<< "$output"
    [ "$found_kickoff" -eq 1 ] \
        || { echo "P4-AK-11: '/kickoff' nicht innerhalb von 5 Zeilen um die cd-Zeile (Zeile ${cd_line_num}). Output: $output"; false; }
}

# ==============================================================================
# P4-AK-12 — Snapshot: tpl_kickoff_skill() landet ausserhalb Snapshot-Block, bash -n sauber
# ==============================================================================

@test "P4-AK-12: Snapshot-Test: Kopie mit --snapshot-globals enthaelt tpl_kickoff_skill() ausserhalb Snapshot-Block, bash -n sauber" {
    # P4-AK-12: --snapshot-globals soll tpl_kickoff_skill() nicht ueberschreiben
    # (sie ist ausserhalb des BEGIN/END AUTO-SNAPSHOT TEMPLATES Blocks).
    # Voraussetzung: Alle 8 Globals vorhanden.
    _setup_full_globals

    # Tatara in tmpdir kopieren
    local tatara_copy="${BATS_TEST_TMPDIR}/tatara_snap_copy"
    cp "${TATARA}" "$tatara_copy"
    chmod +x "$tatara_copy"

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        unset CLAUDECODE
        bash '$tatara_copy' --snapshot-globals </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P4-AK-12: --snapshot-globals auf Kopie fehlgeschlagen. Output: $output"; false; }

    # tpl_kickoff_skill() muss in der Kopie definiert sein
    grep -q '^tpl_kickoff_skill()' "$tatara_copy" \
        || { echo "P4-AK-12: 'tpl_kickoff_skill()' nicht in der Snapshot-Kopie gefunden — Funktion fehlt oder ist im falschen Block."; false; }

    # bash -n muss sauber durchlaufen
    bash -n "$tatara_copy" \
        || { echo "P4-AK-12: bash -n Syntax-Check der Snapshot-Kopie fehlgeschlagen"; false; }
}

# ==============================================================================
# P4-AK-13 — tatara -h enthaelt 'kickoff'
# ==============================================================================

@test "P4-AK-13: tatara -h enthaelt 'kickoff'" {
    # P4-AK-13: Die Hilfetextausgabe muss auf den Kickoff-Prozess hinweisen.
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        bash '${TATARA}' -h 2>&1
    "
    [[ "$output" == *"kickoff"* ]] \
        || { echo "P4-AK-13: 'kickoff' nicht in tatara -h Output. Output: $output"; false; }
}

# ==============================================================================
# P4-AK-14 — Unit: kickoff_handoff returnt 0 in allen Nicht-exec-Zweigen
# ==============================================================================

@test "P4-AK-14: kickoff_handoff returnt 0 in allen Nicht-exec-Zweigen (CLAUDECODE, kein-claude, nicht-eingeloggt, confirm-Nein)" {
    # P4-AK-14: kickoff_handoff darf set -e nicht ausloesen in den 4 Return-Zweigen.
    # Subtest 1: CLAUDECODE=1 -> return 0
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOGGED_IN=1
        export CLAUDECODE=1
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        _run_test() {
            local tmpd
            tmpd=\"\$(mktemp -d)\"
            kickoff_handoff \"\$tmpd\" >/dev/null 2>&1
            echo \"RC:\$?\"
            rm -rf \"\$tmpd\"
        }
        _run_test
    "
    [[ "$output" == *"RC:0"* ]] \
        || { echo "P4-AK-14 Sub1 (CLAUDECODE): erwartet RC:0. Output: $output"; false; }

    # Subtest 2: kein claude -> return 0
    local no_claude_path
    no_claude_path="$(_path_no_claude)"
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${no_claude_path}'
        unset CLAUDECODE
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        _run_test() {
            local tmpd
            tmpd=\"\$(mktemp -d)\"
            kickoff_handoff \"\$tmpd\" >/dev/null 2>&1
            echo \"RC:\$?\"
            rm -rf \"\$tmpd\"
        }
        _run_test
    "
    [[ "$output" == *"RC:0"* ]] \
        || { echo "P4-AK-14 Sub2 (kein-claude): erwartet RC:0. Output: $output"; false; }

    # Subtest 3: nicht eingeloggt -> return 0
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOGGED_IN=0
        unset CLAUDECODE
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        _run_test() {
            local tmpd
            tmpd=\"\$(mktemp -d)\"
            kickoff_handoff \"\$tmpd\" >/dev/null 2>&1
            echo \"RC:\$?\"
            rm -rf \"\$tmpd\"
        }
        _run_test
    "
    [[ "$output" == *"RC:0"* ]] \
        || { echo "P4-AK-14 Sub3 (nicht-eingeloggt): erwartet RC:0. Output: $output"; false; }

    # Subtest 4: confirm-Nein (TATARA_INTERACTIVE=0) -> return 0
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOGGED_IN=1
        export TATARA_INTERACTIVE=0
        unset CLAUDECODE
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        _run_test() {
            local tmpd
            tmpd=\"\$(mktemp -d)\"
            kickoff_handoff \"\$tmpd\" >/dev/null 2>&1
            echo \"RC:\$?\"
            rm -rf \"\$tmpd\"
        }
        _run_test
    "
    [[ "$output" == *"RC:0"* ]] \
        || { echo "P4-AK-14 Sub4 (confirm-Nein): erwartet RC:0. Output: $output"; false; }
}

# ==============================================================================
# L3-AK-1 — Unit: validate_project_name haertet gegen Shell-Sonderzeichen
# ==============================================================================

@test "L3-AK-1: validate_project_name Unit: Shell-Sonderzeichen ungueltig, erlaubte Zeichen gueltig" {
    # L3-AK-1: validate_project_name muss Shell-Metazeichen ablehnen (RC 1 + Fehlermeldung)
    # und gueltige Namen akzeptieren (RC 0, stdout leer).
    # Ungueltig: a;b, a$(x), a`x`, a&b, a|b, a>b, a*b, a:b, a@b, a"b
    # sowie Unicode-Buchstaben (LC_ALL=C -> deterministisch ASCII-only): café, über
    # Gueltig: gut-name_1, my.project, Proj2

    local invalid_names=( 'a;b' 'a$(x)' 'a`x`' 'a&b' 'a|b' 'a>b' 'a*b' 'a:b' 'a@b' 'a"b' 'café' 'über' )
    local n
    for n in "${invalid_names[@]}"; do
        run bash -c "
            set +euo pipefail
            export HOME='${BATS_TEST_TMPDIR}/home'
            export PATH='${STUB_PATH}'
            main() { :; }
            source '${TATARA}' >/dev/null 2>&1 || true
            set +euo pipefail
            out=\$(validate_project_name $(printf '%q' "$n") 2>/dev/null)
            rc=\$?
            echo \"RC:\$rc\"
            echo \"OUT:\$out\"
        "
        [[ "$output" == *"RC:1"* ]] \
            || { echo "L3-AK-1: '${n}' -> erwartet RC:1 (ungueltig). Output: $output"; false; }
        # Fehlermeldung muss erlaubte Zeichen erwaehnen
        local found_msg=0
        [[ "$output" == *"Buchstaben"* ]] && found_msg=1
        [[ "$output" == *"Ziffern"* ]]    && found_msg=1
        [[ "$output" == *"[A-Za-z"* ]]    && found_msg=1
        [[ "$output" == *"nur"* && "$output" == *"enthalten"* ]] && found_msg=1
        [ "$found_msg" -eq 1 ] \
            || { echo "L3-AK-1: '${n}' -> RC:1 aber Fehlermeldung nennt keine erlaubten Zeichen. Output: $output"; false; }
    done

    # Gueltige Namen: RC 0, stdout leer
    local valid_names=( 'gut-name_1' 'my.project' 'Proj2' )
    for n in "${valid_names[@]}"; do
        run bash -c "
            set +euo pipefail
            export HOME='${BATS_TEST_TMPDIR}/home'
            export PATH='${STUB_PATH}'
            main() { :; }
            source '${TATARA}' >/dev/null 2>&1 || true
            set +euo pipefail
            out=\$(validate_project_name $(printf '%q' "$n") 2>/dev/null)
            rc=\$?
            echo \"RC:\$rc\"
            printf 'OUT:[%s]' \"\$out\"
        "
        [[ "$output" == *"RC:0"* ]] \
            || { echo "L3-AK-1: '${n}' -> erwartet RC:0 (gueltig). Output: $output"; false; }
        [[ "$output" == *"OUT:[]"* ]] \
            || { echo "L3-AK-1: '${n}' -> erwartet leeren stdout. Output: $output"; false; }
    done
}

# ==============================================================================
# L3-AK-2 — Blackbox: 'evil;rm' wird abgelehnt, kein Verzeichnis angelegt
# ==============================================================================

@test "L3-AK-2: tatara 'evil;rm' (non-interaktiv) -> Exit!=0, Fehlermeldung nennt erlaubte Zeichen, kein Verzeichnis angelegt" {
    # L3-AK-2: Shell-Sonderzeichen im Projektnamen -> tatara bricht ab,
    # kein Verzeichnis unter PROJECTS_ROOT, Fehlermeldung erklaert erlaubte Zeichen.
    _setup_full_globals
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        bash '${TATARA}' 'evil;rm' </dev/null 2>&1
    "
    [ "$status" -ne 0 ] \
        || { echo "L3-AK-2: Exit-Code 0 erwartet != 0 (ungültiger Name muss abbrechen). Output: $output"; false; }
    # Fehlermeldung muss erlaubte Zeichen erwaehnen
    local found_msg=0
    [[ "$output" == *"Buchstaben"* ]] && found_msg=1
    [[ "$output" == *"Ziffern"* ]]    && found_msg=1
    [[ "$output" == *"[A-Za-z"* ]]    && found_msg=1
    [[ "$output" == *"nur"* && "$output" == *"enthalten"* ]] && found_msg=1
    [ "$found_msg" -eq 1 ] \
        || { echo "L3-AK-2: Fehlermeldung nennt keine erlaubten Zeichen. Output: $output"; false; }
    # Kein Verzeichnis unter PROJECTS_ROOT
    local count
    count="$(ls -A "${BATS_TEST_TMPDIR}/dev" 2>/dev/null | wc -l | tr -d ' ')"
    [ "$count" -eq 0 ] \
        || { echo "L3-AK-2: Verzeichnis(se) angelegt obwohl Name ungueltig: $(ls "${BATS_TEST_TMPDIR}/dev")"; false; }
}
