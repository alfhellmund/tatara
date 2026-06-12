#!/usr/bin/env bats
# Tests fuer Phase 2 — Onboarding-Verbesserungen:
# is_interactive / confirm / validate_project_name / prompt_project_name /
# mode_wizard / Selbst-Heilung in mode_tatara / main ohne Argumente
#
# Alle Blackbox-Tests laufen mit:
#   HOME=$BATS_TEST_TMPDIR/home
#   PROJECTS_ROOT=$BATS_TEST_TMPDIR/dev
#   Stub-PATH
#   stdin IMMER explizit gesetzt (</dev/null oder Pipe)
#
# Unit-Tests sourcen tatara mit dem Idiom aus model_policy.bats:
#   main(){ :; }; source '$TATARA'; set +euo pipefail; <fn>

TATARA="/Users/alfhellmund/Development/tatara/tatara"
STUBS_DIR="/Users/alfhellmund/Development/tatara/tests/stubs"

setup() {
    HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"

    PROJECTS_ROOT="$BATS_TEST_TMPDIR/dev"
    mkdir -p "$PROJECTS_ROOT"

    CLAUDE_STUB_LOG="$BATS_TEST_TMPDIR/calls.log"
    export CLAUDE_STUB_LOG
    export HOME
    export PROJECTS_ROOT

    # Standard-PATH: Stubs vorgelagert
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

# PATH ohne git: filtert Verzeichnisse mit git-Binary heraus; stellt
# uname-Stub bereit falls das echte uname-Verzeichnis dabei entfaellt.
# bd + claude + curl-Stubs bleiben erhalten (M-3: Haertung gegen echtes curl).
_path_no_git() {
    local nodir="$BATS_TEST_TMPDIR/nogit_$$"
    mkdir -p "$nodir"
    cp "$STUBS_DIR/bd"     "$nodir/bd"
    cp "$STUBS_DIR/claude" "$nodir/claude"
    cp "$STUBS_DIR/curl"   "$nodir/curl"
    # uname-Stub: gibt Darwin zurueck (reicht fuer OS-Detection)
    printf '%s\n' '#!/usr/bin/env bash' 'printf "Darwin\n"' > "$nodir/uname"
    chmod +x "$nodir/uname"
    # System-PATH beibehalten, aber jedes Verzeichnis mit git-Binary herausfiltern
    local clean="" dir
    local IFS=':'
    for dir in $PATH; do
        [ -n "$dir" ] && [ -x "$dir/git" ] && continue
        clean="${clean:+$clean:}$dir"
    done
    printf '%s' "${nodir}:${clean}"
}

# ==============================================================================
# P2-AK-1 — main ohne Args, non-interaktiv -> Exit 1 + NUTZUNG, kein Verzeichnis
# ==============================================================================

@test "P2-AK-1: main ohne Args, TATARA_INTERACTIVE ungesetzt, stdin /dev/null -> Exit 1, stdout enthaelt NUTZUNG, kein Verzeichnis angelegt" {
    # P2-AK-1: bash tatara ohne Args, TATARA_INTERACTIVE ungesetzt, </dev/null -> Exit 1;
    # stdout enthaelt NUTZUNG; kein Verzeichnis unter $PROJECTS_ROOT
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        unset TATARA_INTERACTIVE
        bash '${TATARA}' </dev/null 2>&1
    "
    [ "$status" -eq 1 ] \
        || { echo "P2-AK-1: Exit-Code $status erwartet 1. Output: $output"; false; }
    [[ "$output" == *"NUTZUNG"* ]] \
        || { echo "P2-AK-1: 'NUTZUNG' nicht in stdout. Output: $output"; false; }
    # Kein Verzeichnis unter PROJECTS_ROOT
    local count
    count="$(ls -A "${BATS_TEST_TMPDIR}/dev" 2>/dev/null | wc -l | tr -d ' ')"
    [ "$count" -eq 0 ] \
        || { echo "P2-AK-1: Verzeichnis(se) unter PROJECTS_ROOT angelegt obwohl Exit 1 erwartet: $(ls "${BATS_TEST_TMPDIR}/dev")"; false; }
}

# ==============================================================================
# P2-AK-2 — Wizard interaktiv, Name + Beschreibung -> Projekt vollstaendig angelegt
# ==============================================================================

@test "P2-AK-2: Wizard mit TATARA_INTERACTIVE=1, Name+Beschreibung -> Projekt vollstaendig angelegt, README.md enthaelt Beschreibung" {
    # P2-AK-2: TATARA_INTERACTIVE=1, stdin 'proj\nEine Beschreibung\n' -> Exit 0;
    # Projekt-Dateien vorhanden; README.md enthaelt 'Eine Beschreibung'
    _setup_full_globals
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export TATARA_INTERACTIVE=1
        printf 'proj\nEine Beschreibung\n' | bash '${TATARA}' 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P2-AK-2: Exit-Code $status erwartet 0. Output: $output"; false; }
    # Pflichtdateien vorhanden
    local proj="${BATS_TEST_TMPDIR}/dev/proj"
    [ -f "${proj}/README.md" ] \
        || { echo "P2-AK-2: README.md fehlt in ${proj}"; false; }
    [ -f "${proj}/CLAUDE.md" ] \
        || { echo "P2-AK-2: CLAUDE.md fehlt in ${proj}"; false; }
    [ -f "${proj}/.gitignore" ] \
        || { echo "P2-AK-2: .gitignore fehlt in ${proj}"; false; }
    [ -f "${proj}/.claude/settings.json" ] \
        || { echo "P2-AK-2: .claude/settings.json fehlt in ${proj}"; false; }
    [ -f "${proj}/.claude/hooks/post-commit-verify.sh" ] \
        || { echo "P2-AK-2: .claude/hooks/post-commit-verify.sh fehlt in ${proj}"; false; }
    # README.md enthaelt die Beschreibung
    grep -q "Eine Beschreibung" "${proj}/README.md" \
        || { echo "P2-AK-2: 'Eine Beschreibung' nicht in README.md. Inhalt:"; cat "${proj}/README.md"; false; }
}

# ==============================================================================
# P2-AK-3 — Wizard leere Beschreibung -> Platzhalter in CLAUDE.md
# ==============================================================================

@test "P2-AK-3: Wizard leere Beschreibung (stdin 'proj\\n\\n') -> CLAUDE.md enthaelt Platzhalter" {
    # P2-AK-3: Wizard leere Beschreibung -> CLAUDE.md enthaelt '_Eine Zeile Projektbeschreibung._'
    _setup_full_globals
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export TATARA_INTERACTIVE=1
        printf 'proj\n\n' | bash '${TATARA}' 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P2-AK-3: Exit-Code $status erwartet 0. Output: $output"; false; }
    local proj="${BATS_TEST_TMPDIR}/dev/proj"
    grep -q '_Eine Zeile Projektbeschreibung._' "${proj}/CLAUDE.md" \
        || { echo "P2-AK-3: Platzhalter '_Eine Zeile Projektbeschreibung._' nicht in CLAUDE.md. Inhalt:"; cat "${proj}/CLAUDE.md"; false; }
}

# ==============================================================================
# P2-AK-4 — Wizard Validierungsschleife: ungueltige Namen werden abgelehnt
# ==============================================================================

@test "P2-AK-4: Wizard-Schleife lehnt 'has space', '.dot', 'sl/ash' ab, akzeptiert 'gut', Fehlertexte in Ausgabe" {
    # P2-AK-4: Wizard, stdin 'has space\n.dot\nsl/ash\ngut\n\n' -> Exit 0;
    # Projekt 'gut' existiert; Ausgabe enthaelt 'Leerzeichen', 'nicht mit .', 'kein /';
    # keine Dirs 'has space'/.dot unter PROJECTS_ROOT
    _setup_full_globals
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export TATARA_INTERACTIVE=1
        printf 'has space\n.dot\nsl/ash\ngut\n\n' | bash '${TATARA}' 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P2-AK-4: Exit-Code $status erwartet 0. Output: $output"; false; }
    # Projekt 'gut' muss angelegt sein
    [ -d "${BATS_TEST_TMPDIR}/dev/gut" ] \
        || { echo "P2-AK-4: Verzeichnis 'gut' wurde nicht angelegt. Inhalt von dev:"; ls "${BATS_TEST_TMPDIR}/dev" 2>/dev/null; false; }
    # Fehlertexte in der Gesamtausgabe
    [[ "$output" == *"Leerzeichen"* ]] \
        || { echo "P2-AK-4: 'Leerzeichen' nicht in Ausgabe. Output: $output"; false; }
    [[ "$output" == *"nicht mit ."* ]] || [[ "$output" == *"mit ."* ]] \
        || { echo "P2-AK-4: Kein Hinweis auf fuehrenden Punkt ('nicht mit .' o.ae.) in Ausgabe. Output: $output"; false; }
    [[ "$output" == *"kein /"* ]] || [[ "$output" == *"/"* && "$output" == *"erlaubt"* ]] \
        || { echo "P2-AK-4: Kein Hinweis auf unerlaubtes '/' in Ausgabe. Output: $output"; false; }
    # Keine ungeltigen Verzeichnisse angelegt
    [ ! -d "${BATS_TEST_TMPDIR}/dev/has space" ] \
        || { echo "P2-AK-4: Verzeichnis 'has space' wurde faelschlicherweise angelegt"; false; }
    [ ! -d "${BATS_TEST_TMPDIR}/dev/.dot" ] \
        || { echo "P2-AK-4: Verzeichnis '.dot' wurde faelschlicherweise angelegt"; false; }
}

# ==============================================================================
# P2-AK-5 — Wizard, sofort EOF -> Exit 1, keine Endlosschleife
# ==============================================================================

@test "P2-AK-5: Wizard, TATARA_INTERACTIVE=1, stdin sofort EOF -> Exit 1, Output enthaelt 'Eingabe abgebrochen', kein Hang, kein Projekt" {
    # P2-AK-5: TATARA_INTERACTIVE=1, stdin </dev/null (sofort EOF) -> Exit 1;
    # Output enthaelt 'Eingabe abgebrochen'; Test terminiert innerhalb 15s (kein Hang); kein Projekt
    # Timeout via Bash-Background + kill (portabel, kein externes timeout noetig)
    _setup_full_globals
    local outfile="${BATS_TEST_TMPDIR}/ak5_output.txt"
    local pidfile="${BATS_TEST_TMPDIR}/ak5_pid.txt"

    # Starte tatara im Hintergrund, leite Output in Datei
    (
        set +e
        export HOME="${BATS_TEST_TMPDIR}/home"
        export PROJECTS_ROOT="${BATS_TEST_TMPDIR}/dev"
        export PATH="${STUB_PATH}"
        export CLAUDE_STUB_LOG="${CLAUDE_STUB_LOG}"
        export TATARA_INTERACTIVE=1
        bash "${TATARA}" </dev/null 2>&1
        echo "TATARA_EXIT:$?"
    ) > "$outfile" &
    local bg_pid=$!
    echo "$bg_pid" > "$pidfile"

    # Warte maximal 15 Sekunden
    local i=0
    while [ $i -lt 15 ]; do
        sleep 1
        i=$((i + 1))
        kill -0 "$bg_pid" 2>/dev/null || break
    done

    # Falls noch laueft: kill (Hang-Nachweis)
    local hung=0
    if kill -0 "$bg_pid" 2>/dev/null; then
        hung=1
        kill "$bg_pid" 2>/dev/null || true
        wait "$bg_pid" 2>/dev/null || true
    else
        wait "$bg_pid" 2>/dev/null || true
    fi

    local ak5_output
    ak5_output="$(cat "$outfile" 2>/dev/null || true)"

    [ "$hung" -eq 0 ] \
        || { echo "P2-AK-5: Prozess hat nach 15s nicht terminiert — Hang. Output bisher: $ak5_output"; false; }

    # tatara muss mit Exit 1 beendet haben
    [[ "$ak5_output" == *"TATARA_EXIT:1"* ]] \
        || { echo "P2-AK-5: Erwartet TATARA_EXIT:1. Output: $ak5_output"; false; }

    # Output enthaelt 'Eingabe abgebrochen'
    [[ "$ak5_output" == *"Eingabe abgebrochen"* ]] \
        || { echo "P2-AK-5: 'Eingabe abgebrochen' nicht in Output. Output: $ak5_output"; false; }

    # Kein Projekt angelegt
    local count
    count="$(ls -A "${BATS_TEST_TMPDIR}/dev" 2>/dev/null | wc -l | tr -d ' ')"
    [ "$count" -eq 0 ] \
        || { echo "P2-AK-5: Projekt(e) angelegt obwohl EOF: $(ls "${BATS_TEST_TMPDIR}/dev")"; false; }
}

# ==============================================================================
# P2-AK-6 — Selbst-Heilung komplett: leeres ~/.claude + ENV-Modell + Projekt anlegen
# ==============================================================================

@test "P2-AK-6: Selbst-Heilung komplett: leeres ~/.claude, TATARA_ARCHITECT_MODEL=opus, tatara proj -> alle 8 Globals angelegt, architect.md enthaelt 'opus', Projekt angelegt, kein 'Lauf zuerst'" {
    # P2-AK-6: leeres ~/.claude, TATARA_ARCHITECT_MODEL=opus, bash tatara proj </dev/null ->
    # Exit 0; alle 8 Globals existieren; architect.md enthaelt 'model: opus';
    # Projekt angelegt; Output enthaelt NICHT 'Lauf zuerst'
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export TATARA_ARCHITECT_MODEL=opus
        bash '${TATARA}' proj </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P2-AK-6: Exit-Code $status erwartet 0. Output: $output"; false; }
    # Alle 8 Global-Dateien muessen existieren
    local claude_dir="${BATS_TEST_TMPDIR}/home/.claude"
    [ -f "${claude_dir}/CLAUDE.md" ] \
        || { echo "P2-AK-6: ~/.claude/CLAUDE.md fehlt"; false; }
    [ -f "${claude_dir}/software-development-workflow.md" ] \
        || { echo "P2-AK-6: ~/.claude/software-development-workflow.md fehlt"; false; }
    for agent in architect architect-reviewer developer qa-reviewer security-reviewer test-writer; do
        [ -f "${claude_dir}/agents/${agent}.md" ] \
            || { echo "P2-AK-6: ~/.claude/agents/${agent}.md fehlt"; false; }
    done
    # architect.md enthaelt 'model: opus'
    grep -q '^model: opus' "${claude_dir}/agents/architect.md" \
        || { echo "P2-AK-6: architect.md enthaelt nicht 'model: opus'. Inhalt:"; grep '^model:' "${claude_dir}/agents/architect.md" 2>/dev/null || echo "(kein model-Feld)"; false; }
    # Projekt angelegt
    [ -d "${BATS_TEST_TMPDIR}/dev/proj" ] \
        || { echo "P2-AK-6: Projekt 'proj' wurde nicht angelegt"; false; }
    # Output enthaelt NICHT 'Lauf zuerst'
    [[ "$output" != *"Lauf zuerst"* ]] \
        || { echo "P2-AK-6: Output enthaelt 'Lauf zuerst' obwohl Selbst-Heilung erwartet. Output: $output"; false; }
}

# ==============================================================================
# P2-AK-7 — Selbst-Heilung partiell: nur developer.md fehlt, architect.md unveraendert
# ==============================================================================

@test "P2-AK-7: Selbst-Heilung partiell: developer.md fehlt -> wird angelegt mit 'model: sonnet'; architect.md byte-identisch; kein -p-Call" {
    # P2-AK-7: alle Globals vorhanden ausser developer.md, ENV ungesetzt ->
    # Exit 0; developer.md mit 'model: sonnet'; architect.md byte-identisch (cmp); kein -p-Call.
    # CLAUDE_STUB_LOGGED_IN=1: Profi=eingeloggt=still (Phase-3: ensure_claude erzeugt sonst Login-Warnung).
    local claude_dir="${BATS_TEST_TMPDIR}/home/.claude"
    local agents_dir="${claude_dir}/agents"
    mkdir -p "$agents_dir"
    printf 'dummy\n' > "${claude_dir}/CLAUDE.md"
    printf 'dummy\n' > "${claude_dir}/software-development-workflow.md"
    # architect.md mit echtem Inhalt (model: fable), um cmp pruefbar zu machen
    printf '%s\n' \
        '---' \
        'name: architect' \
        'description: Test-Architect' \
        'model: fable' \
        '---' \
        'Architect content.' > "${agents_dir}/architect.md"
    # Snapshot fuer cmp
    local snapshot_file="${BATS_TEST_TMPDIR}/architect_before.md"
    cp "${agents_dir}/architect.md" "$snapshot_file"
    # Restliche Agenten als Dummy
    for agent in architect-reviewer qa-reviewer security-reviewer test-writer; do
        printf 'dummy\n' > "${agents_dir}/${agent}.md"
    done
    # developer.md absichtlich NICHT anlegen

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        unset TATARA_ARCHITECT_MODEL
        unset CLAUDECODE
        bash '${TATARA}' proj </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P2-AK-7: Exit-Code $status erwartet 0. Output: $output"; false; }
    # developer.md wurde angelegt mit 'model: sonnet'
    [ -f "${agents_dir}/developer.md" ] \
        || { echo "P2-AK-7: developer.md wurde nicht angelegt"; false; }
    grep -q '^model: sonnet' "${agents_dir}/developer.md" \
        || { echo "P2-AK-7: developer.md enthaelt nicht 'model: sonnet'. Inhalt:"; cat "${agents_dir}/developer.md"; false; }
    # architect.md byte-identisch (wurde NICHT ueberschrieben)
    cmp "${agents_dir}/architect.md" "$snapshot_file" \
        || { echo "P2-AK-7: architect.md wurde modifiziert, byte-identisch erwartet:"; diff "$snapshot_file" "${agents_dir}/architect.md"; false; }
    # Kein -p-Call (Lockerung: Log darf existieren z.B. fuer auth status, aber kein -p)
    if [[ -f "$CLAUDE_STUB_LOG" ]]; then
        if grep -Eq '(^|[[:space:]"])-p([[:space:]"]|$)' "$CLAUDE_STUB_LOG" 2>/dev/null; then
            echo "P2-AK-7: Stub-Log enthaelt -p-Call obwohl kein Probe erlaubt:"
            cat "$CLAUDE_STUB_LOG"
            false
        fi
    fi
}

# ==============================================================================
# P2-AK-8 — Profi-No-op: vollstaendige Globals -> stiller Durchlauf
# ==============================================================================

@test "P2-AK-8: Vollstaendige Globals -> kein 'geschrieben:', kein 'behalten:', kein 'bootstrappe', kein -p-Call" {
    # P2-AK-8: vollstaendige Dummy-Globals -> Exit 0;
    # Output enthaelt weder 'geschrieben:' noch 'behalten:' noch 'bootstrappe';
    # CLAUDE_STUB_LOG enthaelt keinen -p-Call (Lockerung: auth-status-Call fuer ensure_claude ist ok).
    # CLAUDE_STUB_LOGGED_IN=1: Profi=eingeloggt=still (Phase-3: ensure_claude erzeugt sonst Login-Warnung).
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
        || { echo "P2-AK-8: Exit-Code $status erwartet 0. Output: $output"; false; }
    [[ "$output" != *"geschrieben:"* ]] \
        || { echo "P2-AK-8: 'geschrieben:' in Output obwohl No-op erwartet. Output: $output"; false; }
    [[ "$output" != *"behalten:"* ]] \
        || { echo "P2-AK-8: 'behalten:' in Output obwohl No-op erwartet. Output: $output"; false; }
    [[ "$output" != *"bootstrappe"* ]] \
        || { echo "P2-AK-8: 'bootstrappe' in Output obwohl No-op erwartet. Output: $output"; false; }
    # Kein -p-Call (Lockerung: Log darf existieren z.B. fuer auth status, aber kein -p)
    if [[ -f "$CLAUDE_STUB_LOG" ]]; then
        if grep -Eq '(^|[[:space:]"])-p([[:space:]"]|$)' "$CLAUDE_STUB_LOG" 2>/dev/null; then
            echo "P2-AK-8: Stub-Log enthaelt -p-Call obwohl kein Probe erlaubt:"
            cat "$CLAUDE_STUB_LOG"
            false
        fi
    fi
}

# ==============================================================================
# P2-AK-9 — Non-TTY confirm ignoriert gepiptes y: git fehlt -> Exit 1, kein brew-Hinweis
# ==============================================================================

@test "P2-AK-9: Non-TTY confirm ignoriert gepiptes 'y': kein git im PATH, TATARA_INTERACTIVE=0 -> Exit 1, Output enthaelt 'git wird benoetigt', kein 'brew install'" {
    # P2-AK-9: PATH ohne git, volle Globals, stdin 'y\n', TATARA_INTERACTIVE=0 ->
    # Exit 1; Output enthaelt 'git wird benoetigt'; Output enthaelt NICHT 'brew install'
    _setup_full_globals
    local no_git_path
    no_git_path="$(_path_no_git)"
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${no_git_path}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export TATARA_INTERACTIVE=0
        printf 'y\n' | bash '${TATARA}' proj 2>&1
    "
    [ "$status" -eq 1 ] \
        || { echo "P2-AK-9: Exit-Code $status erwartet 1. Output: $output"; false; }
    # 'git wird benoetigt' (oder Variante ohne Umlaute: 'git wird benoetigt')
    [[ "$output" == *"git wird benoetigt"* ]] || [[ "$output" == *"git wird ben"* ]] \
        || { echo "P2-AK-9: 'git wird benoetigt' nicht in Output. Output: $output"; false; }
    # Keine echte Installation: auf den log-Marker '-> brew install' pruefen
    # (Pipe-Praefix aus log()), NICHT den nackten Substring 'brew install' —
    # der steckt auch in Prompt-Texten (z.B. bd-Prompt) und waere ein
    # falsch-rot-Proxy. '-> brew install' erscheint nur bei echtem pkg_install.
    [[ "$output" != *"-> brew install"* ]] \
        || { echo "P2-AK-9: echte Installation (-> brew install) gestartet, obwohl Non-TTY confirm Default-Nein sein soll. Output: $output"; false; }
}

# ==============================================================================
# P2-AK-10 — Unit: confirm Verhalten mit TATARA_INTERACTIVE=1
# ==============================================================================

@test "P2-AK-10: confirm Unit: TATARA_INTERACTIVE=1+'y'->0; +'n'->1; +EOF->1; TATARA_INTERACTIVE=0+'y'->1 (stdin-Ignore)" {
    # P2-AK-10: confirm mit TATARA_INTERACTIVE=1: printf 'y\n'->0; printf 'n\n'->1; </dev/null->1 (EOF)
    # ZUSATZ: TATARA_INTERACTIVE=0 + printf 'y\n' -> 1 (Non-TTY ignoriert stdin)

    # Subtest 1: TATARA_INTERACTIVE=1, y -> 0
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_INTERACTIVE=1
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        printf 'y\n' | confirm 'Test?'
        echo \"RC:\$?\"
    "
    [[ "$output" == *"RC:0"* ]] \
        || { echo "P2-AK-10 Subtest1: TATARA_INTERACTIVE=1+'y' -> erwartet RC:0, got: $output"; false; }

    # Subtest 2: TATARA_INTERACTIVE=1, n -> 1
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_INTERACTIVE=1
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        printf 'n\n' | confirm 'Test?'
        echo \"RC:\$?\"
    "
    [[ "$output" == *"RC:1"* ]] \
        || { echo "P2-AK-10 Subtest2: TATARA_INTERACTIVE=1+'n' -> erwartet RC:1, got: $output"; false; }

    # Subtest 3: TATARA_INTERACTIVE=1, EOF -> 1 (kein Hang)
    # Laueft in Background + kill nach 8s falls Hang
    local outfile3="${BATS_TEST_TMPDIR}/ak10_sub3.txt"
    (
        set +euo pipefail
        export HOME="${BATS_TEST_TMPDIR}/home"
        export PATH="${STUB_PATH}"
        export TATARA_INTERACTIVE=1
        main() { :; }
        source "${TATARA}" >/dev/null 2>&1 || true
        set +euo pipefail
        confirm "Test?" </dev/null
        echo "RC:$?"
    ) > "$outfile3" 2>&1 &
    local bg3=$!
    local j=0
    while [ $j -lt 8 ]; do sleep 1; j=$((j+1)); kill -0 "$bg3" 2>/dev/null || break; done
    local hung3=0
    if kill -0 "$bg3" 2>/dev/null; then hung3=1; kill "$bg3" 2>/dev/null || true; fi
    wait "$bg3" 2>/dev/null || true
    local out3
    out3="$(cat "$outfile3" 2>/dev/null || true)"
    [ "$hung3" -eq 0 ] \
        || { echo "P2-AK-10 Subtest3: confirm haengt bei EOF (Hang nach 8s). Bisheriger Output: $out3"; false; }
    [[ "$out3" == *"RC:1"* ]] \
        || { echo "P2-AK-10 Subtest3: EOF -> erwartet RC:1. Output: $out3"; false; }

    # Subtest 4 (Phase-2-kritisch): TATARA_INTERACTIVE=0 + 'y' auf stdin -> MUSS 1 zurueckgeben
    # Die bestehende Impl liest stdin auch ohne TATARA_INTERACTIVE -> dieser Subtest ist ROT
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_INTERACTIVE=0
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        printf 'y\n' | confirm 'Test?' 2>/dev/null
        echo \"RC:\$?\"
    "
    [[ "$output" == *"RC:1"* ]] \
        || { echo "P2-AK-10 Subtest4: TATARA_INTERACTIVE=0+'y' -> erwartet RC:1 (Non-TTY ignoriert stdin). Output: $output"; false; }
}

# ==============================================================================
# P2-AK-11 — Unit: is_interactive Verhalten
# ==============================================================================

@test "P2-AK-11: is_interactive Unit: TATARA_INTERACTIVE=1->0; =0->1; ungesetzt+Pipe-stdin->1" {
    # P2-AK-11: is_interactive: =1->0; =0->1; ungesetzt+Pipe-stdin->1

    # Subtest 1: TATARA_INTERACTIVE=1 -> return 0
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_INTERACTIVE=1
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        is_interactive
        echo \"RC:\$?\"
    "
    [[ "$output" == *"RC:0"* ]] \
        || { echo "P2-AK-11: TATARA_INTERACTIVE=1 -> erwartet RC:0. Output: $output"; false; }

    # Subtest 2: TATARA_INTERACTIVE=0 -> return 1
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_INTERACTIVE=0
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        is_interactive
        echo \"RC:\$?\"
    "
    [[ "$output" == *"RC:1"* ]] \
        || { echo "P2-AK-11: TATARA_INTERACTIVE=0 -> erwartet RC:1. Output: $output"; false; }

    # Subtest 3: ungesetzt + Pipe-stdin (kein TTY) -> return 1
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        unset TATARA_INTERACTIVE
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        is_interactive
        echo \"RC:\$?\"
    " </dev/null
    [[ "$output" == *"RC:1"* ]] \
        || { echo "P2-AK-11: ungesetzt+Pipe -> erwartet RC:1 (kein TTY). Output: $output"; false; }
}

# ==============================================================================
# P2-AK-12 — Unit: validate_project_name Regeln
# ==============================================================================

@test "P2-AK-12: validate_project_name Unit: leer->1+leer; a/b->1+/; 'a b'->1+Leerzeichen; 'a<TAB>b'->1+Leerzeichen; '.x'->1+mit.; 'ok-name_1'->0+leerer-stdout" {
    # P2-AK-12: validate_project_name: ''"->1+leer; a/b->1+/; a b->1+Leerzeichen;
    # a<TAB>b->1+Leerzeichen; .x->1+mit.; ok-name_1->0+leerer stdout

    # Subtest 1: leer -> 1 + stdout enthaelt 'leer'
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        out=\$(validate_project_name '')
        rc=\$?
        echo \"RC:\$rc\"
        echo \"OUT:\$out\"
    "
    [[ "$output" == *"RC:1"* ]] \
        || { echo "P2-AK-12: leer -> erwartet RC:1. Output: $output"; false; }
    [[ "$output" == *"leer"* ]] \
        || { echo "P2-AK-12: leer -> erwartet 'leer' in stdout. Output: $output"; false; }

    # Subtest 2: a/b -> 1 + stdout enthaelt '/'
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        out=\$(validate_project_name 'a/b')
        rc=\$?
        echo \"RC:\$rc\"
        echo \"OUT:\$out\"
    "
    [[ "$output" == *"RC:1"* ]] \
        || { echo "P2-AK-12: a/b -> erwartet RC:1. Output: $output"; false; }
    [[ "$output" == *"/"* ]] \
        || { echo "P2-AK-12: a/b -> erwartet '/' in stdout. Output: $output"; false; }

    # Subtest 3: 'a b' -> 1 + stdout enthaelt 'Leerzeichen'
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        out=\$(validate_project_name 'a b')
        rc=\$?
        echo \"RC:\$rc\"
        echo \"OUT:\$out\"
    "
    [[ "$output" == *"RC:1"* ]] \
        || { echo "P2-AK-12: 'a b' -> erwartet RC:1. Output: $output"; false; }
    [[ "$output" == *"Leerzeichen"* ]] \
        || { echo "P2-AK-12: 'a b' -> erwartet 'Leerzeichen' in stdout. Output: $output"; false; }

    # Subtest 4: 'a<TAB>b' -> 1 + stdout enthaelt 'Leerzeichen'
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        out=\$(validate_project_name \$'a\tb')
        rc=\$?
        echo \"RC:\$rc\"
        echo \"OUT:\$out\"
    "
    [[ "$output" == *"RC:1"* ]] \
        || { echo "P2-AK-12: 'a<TAB>b' -> erwartet RC:1. Output: $output"; false; }
    [[ "$output" == *"Leerzeichen"* ]] \
        || { echo "P2-AK-12: 'a<TAB>b' -> erwartet 'Leerzeichen' in stdout. Output: $output"; false; }

    # Subtest 5: '.x' -> 1 + stdout enthaelt 'mit .'
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        out=\$(validate_project_name '.x')
        rc=\$?
        echo \"RC:\$rc\"
        echo \"OUT:\$out\"
    "
    [[ "$output" == *"RC:1"* ]] \
        || { echo "P2-AK-12: '.x' -> erwartet RC:1. Output: $output"; false; }
    [[ "$output" == *"mit ."* ]] \
        || { echo "P2-AK-12: '.x' -> erwartet 'mit .' in stdout. Output: $output"; false; }

    # Subtest 6: 'ok-name_1' -> 0 + stdout leer
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        out=\$(validate_project_name 'ok-name_1')
        rc=\$?
        echo \"RC:\$rc\"
        printf 'OUT:[%s]' \"\$out\"
    "
    [[ "$output" == *"RC:0"* ]] \
        || { echo "P2-AK-12: 'ok-name_1' -> erwartet RC:0. Output: $output"; false; }
    [[ "$output" == *"OUT:[]"* ]] \
        || { echo "P2-AK-12: 'ok-name_1' -> erwartet leeren stdout. Output: $output"; false; }
}

# ==============================================================================
# P2-AK-13 — Unit: prompt_project_name stdout isoliert (nur Name, keine Warnungen)
# ==============================================================================

@test "P2-AK-13: prompt_project_name Unit: stdin 'bad name\\ngut\\n' -> stdout exakt 'gut' (Warnungen NUR auf stderr)" {
    # P2-AK-13: prompt_project_name: stdin 'bad name\ngut\n' ->
    # stdout exakt 'gut'; Warnungen nicht auf stdout (2>/dev/null bei stdout-Capture)
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export TATARA_INTERACTIVE=1
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        # stdout isoliert: stderr nach /dev/null
        result=\$(printf 'bad name\ngut\n' | prompt_project_name 2>/dev/null)
        echo \"RESULT:[\$result]\"
    "
    [[ "$output" == *"RESULT:[gut]"* ]] \
        || { echo "P2-AK-13: prompt_project_name stdout erwartet exakt 'gut'. Output: $output"; false; }
}

# ==============================================================================
# P2-AK-14 — Name als Arg, non-TTY: volle Globals -> Exit 0, Projekt angelegt
# ==============================================================================

@test "P2-AK-14: Name als Arg non-TTY, volle Globals, stdin /dev/null -> Exit 0, Projekt angelegt" {
    # P2-AK-14: volle Globals, bash tatara proj </dev/null (ohne TATARA_INTERACTIVE) ->
    # Exit 0; Projekt angelegt
    _setup_full_globals
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        unset TATARA_INTERACTIVE
        bash '${TATARA}' proj </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P2-AK-14: Exit-Code $status erwartet 0. Output: $output"; false; }
    [ -d "${BATS_TEST_TMPDIR}/dev/proj" ] \
        || { echo "P2-AK-14: Projekt 'proj' nicht angelegt. dev-Inhalt:"; ls "${BATS_TEST_TMPDIR}/dev" 2>/dev/null; false; }
}

# ==============================================================================
# P2-AK-15 — tatara -h enthaelt TATARA_INTERACTIVE + Wizard-Erwaehnung
# ==============================================================================

@test "P2-AK-15: tatara -h enthaelt 'TATARA_INTERACTIVE' und Hinweis auf argumentlosen Wizard/interaktiven Modus" {
    # P2-AK-15: tatara -h -> Output enthaelt 'TATARA_INTERACTIVE' UND
    # nennt den argumentlosen Wizard-Modus (z.B. 'ohne Argumente'/'Assistent'/'interaktiv')
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        bash '${TATARA}' -h 2>&1
    "
    [[ "$output" == *"TATARA_INTERACTIVE"* ]] \
        || { echo "P2-AK-15: 'TATARA_INTERACTIVE' nicht in -h Output. Output: $output"; false; }
    # Wizard-Modus-Erwaehnung: eines dieser Schluesselwoerter muss vorkommen
    local found_wizard=0
    [[ "$output" == *"ohne Argumente"* ]] && found_wizard=1
    [[ "$output" == *"Assistent"* ]]       && found_wizard=1
    [[ "$output" == *"interaktiv"* ]]      && found_wizard=1
    [[ "$output" == *"Wizard"* ]]          && found_wizard=1
    [ "$found_wizard" -eq 1 ] \
        || { echo "P2-AK-15: Kein Wizard/interaktiv-Hinweis in -h Output. Output: $output"; false; }
}

# ==============================================================================
# P2-AK-16 — Sonderzeichen-Beschreibung: kein Code-Injection via Beschreibungsfeld
# ==============================================================================

@test "P2-AK-16: Sonderzeichen-Beschreibung wird literal gespeichert, kein Code-Injection (keine Datei 'pwned')" {
    # P2-AK-16: Wizard, Name 'proj', Beschreibung mit Shell-Sonderzeichen ->
    # Exit 0; keine Datei 'pwned' entsteht; README.md enthaelt Literal-String oder Teile davon
    _setup_full_globals
    # Beschreibung mit Command-Substitution, Backticks, Doublequotes
    local evil_desc='$(touch pwned) `evil` "quote"'
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export TATARA_INTERACTIVE=1
        printf 'proj\n%s\n' \"\$(printf '%s' '${evil_desc}')\" \
            | bash '${TATARA}' 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P2-AK-16: Exit-Code $status erwartet 0. Output: $output"; false; }
    # Keine Datei 'pwned' in Projekt, cwd oder PROJECTS_ROOT
    [ ! -f "${BATS_TEST_TMPDIR}/dev/pwned" ] \
        || { echo "P2-AK-16: Datei 'pwned' unter PROJECTS_ROOT entstanden — Injection!"; false; }
    [ ! -f "${BATS_TEST_TMPDIR}/dev/proj/pwned" ] \
        || { echo "P2-AK-16: Datei 'pwned' im Projektverzeichnis entstanden — Injection!"; false; }
    [ ! -f "pwned" ] \
        || { echo "P2-AK-16: Datei 'pwned' im cwd entstanden — Injection!"; false; }
    # README.md enthaelt mindestens 'quote' (Teil des Literal-Strings)
    local proj="${BATS_TEST_TMPDIR}/dev/proj"
    [ -f "${proj}/README.md" ] \
        || { echo "P2-AK-16: README.md fehlt in ${proj}"; false; }
    grep -q 'quote' "${proj}/README.md" \
        || { echo "P2-AK-16: 'quote' nicht in README.md — Beschreibung nicht gespeichert. Inhalt:"; cat "${proj}/README.md"; false; }
}

# P2-AK-17: set-e-Naht — mode_wizard MUSS bei EOF (prompt_project_name -> err)
# abbrechen, BEVOR mode_tatara erreicht wird. Faengt die Maskierung, die ein
# kombiniertes 'local name="$(...)"' verursachen wuerde (Subshell-Exit verschluckt).
@test "P2-AK-17: mode_wizard bricht bei EOF vor mode_tatara ab (set-e-Naht)" {
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        # mode_tatara durch Marker ersetzen — darf bei EOF NICHT erreicht werden
        mode_tatara() { printf 'MODE_TATARA_ERREICHT name=[%s]\n' \"\$1\"; }
        set -euo pipefail   # set -e aktiv, um die Maskierung real zu testen
        mode_wizard </dev/null
    "
    [ "$status" -ne 0 ] \
        || { echo "P2-AK-17: mode_wizard sollte bei EOF abbrechen. status=$status, output=$output"; false; }
    [[ "$output" != *"MODE_TATARA_ERREICHT"* ]] \
        || { echo "P2-AK-17: mode_tatara trotz EOF erreicht — set-e-Maskierung! Output: $output"; false; }
}
