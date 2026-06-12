#!/usr/bin/env bats
# Tests fuer Phase 3 — Claude-Praesenz + Auth:
# check_claude / claude_logged_in / ensure_claude
#
# Alle Blackbox-Tests laufen mit:
#   HOME=$BATS_TEST_TMPDIR/home
#   PROJECTS_ROOT=$BATS_TEST_TMPDIR/dev
#   Stub-PATH (mit oder ohne claude, je nach Testfall)
#   stdin IMMER explizit gesetzt
#   CLAUDECODE IMMER explizit gesetzt oder ungesetzt
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

    CLAUDE_STUB_LOG="$BATS_TEST_TMPDIR/claude_calls.log"
    CURL_STUB_LOG="$BATS_TEST_TMPDIR/curl_calls.log"
    export CLAUDE_STUB_LOG
    export CURL_STUB_LOG
    export HOME
    export PROJECTS_ROOT

    # Standard-PATH: alle Stubs (claude, git, bd, curl) vorgelagert
    STUB_PATH="${STUBS_DIR}:${PATH}"

    # Sicherheitsnetz: curl-Stub immer erreichbar (auch wenn andere Stubs fehlen)
    # CURL_STUB_INSTALL_SRC: der claude-Stub dient als "installiertes" claude
    export CURL_STUB_INSTALL_SRC="${STUBS_DIR}/claude"
}

# ---------------------------------------------------------------------------
# Hilfs-Funktionen
# ---------------------------------------------------------------------------

# Volles ~/.claude-Verzeichnis anlegen (8 Dateien)
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

# PATH ohne claude: Temp-Verzeichnis mit git, bd, curl (NICHT claude).
# System-PATH wird so gefiltert, dass kein echtes claude erreichbar ist.
# Zudem ein instbin/-Verzeichnis als CURL_STUB_INSTALL_DST, damit nach
# "Installation" ein ausfuehrbares claude im PATH ist.
_path_no_claude() {
    local nodir="$BATS_TEST_TMPDIR/noclaudebin_$$"
    local instbin="$BATS_TEST_TMPDIR/instbin_$$"
    mkdir -p "$nodir" "$instbin"
    cp "$STUBS_DIR/git"  "$nodir/git"
    cp "$STUBS_DIR/bd"   "$nodir/bd"
    cp "$STUBS_DIR/curl" "$nodir/curl"
    # uname-Stub fuer OS-Detection
    printf '%s\n' '#!/usr/bin/env bash' 'printf "Darwin\n"' > "$nodir/uname"
    chmod +x "$nodir/uname"
    # System-PATH beibehalten, aber Verzeichnisse mit claude herausfiltern
    local clean="" dir
    local IFS=':'
    for dir in $PATH; do
        [ -n "$dir" ] && [ -x "$dir/claude" ] && continue
        clean="${clean:+$clean:}$dir"
    done
    # instbin am Ende: nach "Installation" ist claude dort erreichbar
    export CURL_STUB_INSTALL_DST="${instbin}/claude"
    printf '%s' "${nodir}:${instbin}:${clean}"
}

# Bereitet einen PATH ohne claude vor und setzt Variablen direkt in der bats-Shell.
# MUSS als normale Funktion aufgerufen werden (NICHT in $(...)), damit die
# gesetzten Variablen in der bats-Shell sichtbar bleiben.
# Nach dem Aufruf enthaelt $_NC_PATH den PATH-String und $_NC_INSTBIN_DST den
# Zielpfad des Installers (innerhalb von _NC_PATH, damit check_claude TRUE wird).
_setup_no_claude_env() {
    local nodir="$BATS_TEST_TMPDIR/noclaudebin2_$$"
    local instbin="$BATS_TEST_TMPDIR/instbin2_$$"
    mkdir -p "$nodir" "$instbin"
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
    # instbin ist im PATH: nach Install landet das claude-Binary dort -> check_claude TRUE
    _NC_PATH="${nodir}:${instbin}:${clean}"
    _NC_INSTBIN_DST="${instbin}/claude"
}

# PATH ohne bd: git + claude + curl da, bd NICHT.
# Gibt den PATH-String aus.
_path_no_bd() {
    local nodir="$BATS_TEST_TMPDIR/nobdbin_$$"
    mkdir -p "$nodir"
    cp "$STUBS_DIR/git"    "$nodir/git"
    cp "$STUBS_DIR/claude" "$nodir/claude"
    cp "$STUBS_DIR/curl"   "$nodir/curl"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "Darwin\n"' > "$nodir/uname"
    chmod +x "$nodir/uname"
    local clean="" dir
    local IFS=':'
    for dir in $PATH; do
        [ -n "$dir" ] && [ -x "$dir/bd" ] && continue
        clean="${clean:+$clean:}$dir"
    done
    printf '%s' "${nodir}:${clean}"
}

# ==============================================================================
# P3-AK-1 — claude fehlt, interaktiv, stdin y, CURL_STUB_MODE=ok ->
#             curl-Call mit Install-URL, Output-Hinweis, Projekt angelegt
# ==============================================================================

@test "P3-AK-1: claude fehlt, TATARA_INTERACTIVE=1, stdin y, CURL_MODE=ok -> if-Zweig: 'claude installiert (' + Versions-String, curl-Log hat install.sh-URL, Projekt angelegt, Exit 0" {
    # P3-AK-1: ensure_claude soll bei fehlendem claude + Ja-Antwort den Installer
    # via curl|bash ausfuehren. Nach erfolgreichem Install ist check_claude TRUE
    # (claude-Binary landet im PATH via _INSTBIN_DST), daher laeuft der if-Zweig:
    #   ok "claude installiert ($(claude --version))"
    # Nachweis: Output enthaelt 'claude installiert (' + Versions-String des claude-Stubs;
    # CURL_STUB_LOG enthaelt die Install-URL; Projekt wird angelegt.
    # Gegenprobe: Eine Mutation des if-Zweig-Strings wuerde diesen Test rot machen.
    _setup_full_globals
    # _setup_no_claude_env direkt aufrufen (NICHT in $(...)), damit $_NC_PATH
    # und $_NC_INSTBIN_DST in der bats-Shell sichtbar sind
    _setup_no_claude_env

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${_NC_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CURL_STUB_LOG='${CURL_STUB_LOG}'
        export CURL_STUB_INSTALL_SRC='${STUBS_DIR}/claude'
        export CURL_STUB_INSTALL_DST='${_NC_INSTBIN_DST}'
        export CURL_STUB_MODE=ok
        export TATARA_INTERACTIVE=1
        unset CLAUDECODE
        printf 'y\n' | bash '${TATARA}' proj 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P3-AK-1: Exit-Code $status erwartet 0. Output: $output"; false; }
    # CURL_STUB_LOG muss die Install-URL enthalten
    [ -f "$CURL_STUB_LOG" ] \
        || { echo "P3-AK-1: CURL_STUB_LOG nicht erzeugt — curl wurde nicht aufgerufen. Output: $output"; false; }
    grep -q 'https://claude.ai/install.sh' "$CURL_STUB_LOG" \
        || { echo "P3-AK-1: CURL_STUB_LOG enthaelt keine install.sh-URL. Log:"; cat "$CURL_STUB_LOG"; echo "Output: $output"; false; }
    # Output muss den curl-Befehl enthalten
    [[ "$output" == *"curl -fsSL https://claude.ai/install.sh"* ]] \
        || { echo "P3-AK-1: curl-Befehl nicht im Output sichtbar. Output: $output"; false; }
    # if-Zweig: Output muss 'claude installiert (' + Versions-String enthalten
    # (beweist: check_claude ist nach Install TRUE, der if-Zweig wurde genommen)
    [[ "$output" == *"claude installiert ("* ]] \
        || { echo "P3-AK-1: 'claude installiert (' (if-Zweig) nicht im Output — entweder Binary nicht installiert oder else-Zweig genommen. Output: $output"; false; }
    [[ "$output" == *"claude stub"* ]] \
        || { echo "P3-AK-1: Versions-String 'claude stub' (aus claude --version) nicht im Output — if-Zweig nicht durchlaufen. Output: $output"; false; }
    # Projekt muss angelegt sein
    [ -d "${BATS_TEST_TMPDIR}/dev/proj" ] \
        || { echo "P3-AK-1: Projekt 'proj' nicht angelegt. dev-Inhalt:"; ls "${BATS_TEST_TMPDIR}/dev" 2>/dev/null; false; }
}

# ==============================================================================
# P3-AK-1b — Install-else-Zweig: Binary landet NICHT im PATH -> 'noch nicht im PATH'
# ==============================================================================

@test "P3-AK-1b: claude fehlt, TATARA_INTERACTIVE=1, stdin y, CURL_MODE=ok, DST ausserhalb PATH -> else-Zweig: 'claude installiert' + 'noch nicht im PATH', Projekt angelegt, Exit 0" {
    # P3-AK-1b: Wenn der Installer erfolgreich laeuft, aber das Binary ausserhalb des
    # PATH landet (DST-Verzeichnis nicht im PATH), bleibt check_claude FALSE.
    # Dann laeuft der else-Zweig:
    #   ok "claude installiert"
    #   warn "claude noch nicht im PATH..."
    # Nachweis: Output enthaelt 'claude installiert' UND 'noch nicht im PATH'.
    # Die Abwesenheit von 'claude installiert (' (if-Zweig) belegt, dass der else-Zweig aktiv ist.
    _setup_full_globals
    local no_claude_path
    no_claude_path="$(_path_no_claude)"
    # DST zeigt auf ein Verzeichnis, das NICHT im PATH ist
    local outside_dir="${BATS_TEST_TMPDIR}/outside_$$"
    mkdir -p "$outside_dir"
    local outside_dst="${outside_dir}/claude"

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${no_claude_path}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CURL_STUB_LOG='${CURL_STUB_LOG}'
        export CURL_STUB_INSTALL_SRC='${STUBS_DIR}/claude'
        export CURL_STUB_INSTALL_DST='${outside_dst}'
        export CURL_STUB_MODE=ok
        export TATARA_INTERACTIVE=1
        unset CLAUDECODE
        printf 'y\n' | bash '${TATARA}' proj 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P3-AK-1b: Exit-Code $status erwartet 0. Output: $output"; false; }
    # else-Zweig: 'claude installiert' ohne Klammer + 'noch nicht im PATH'
    [[ "$output" == *"claude installiert"* ]] \
        || { echo "P3-AK-1b: 'claude installiert' nicht im Output. Output: $output"; false; }
    [[ "$output" == *"noch nicht im PATH"* ]] \
        || { echo "P3-AK-1b: 'noch nicht im PATH' (else-Zweig) nicht im Output. Output: $output"; false; }
    # Explizit: if-Zweig darf NICHT aktiv sein (kein Versions-String)
    [[ "$output" != *"claude installiert ("* ]] \
        || { echo "P3-AK-1b: 'claude installiert (' im Output — if-Zweig statt else-Zweig aktiv (DST-Setup fehlerhaft?). Output: $output"; false; }
    # Projekt muss angelegt sein
    [ -d "${BATS_TEST_TMPDIR}/dev/proj" ] \
        || { echo "P3-AK-1b: Projekt 'proj' nicht angelegt. dev-Inhalt:"; ls "${BATS_TEST_TMPDIR}/dev" 2>/dev/null; false; }
}

# ==============================================================================
# P3-AK-2 — claude fehlt, interaktiv, stdin n -> kein curl, manueller Hinweis, Projekt angelegt
# ==============================================================================

@test "P3-AK-2: claude fehlt, TATARA_INTERACTIVE=1, stdin n -> curl-Log leer/fehlt, Output enthaelt brew/npm-Hinweis, Projekt angelegt, Exit 0" {
    # P3-AK-2: Benutzer lehnt Installation ab -> kein curl-Call; Output zeigt
    # manuellen Hinweis (brew install --cask claude-code ODER npm install);
    # tatara laeuft weiter und legt das Projekt an.
    _setup_full_globals
    local no_claude_path
    no_claude_path="$(_path_no_claude)"

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${no_claude_path}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CURL_STUB_LOG='${CURL_STUB_LOG}'
        export CURL_STUB_MODE=ok
        export TATARA_INTERACTIVE=1
        unset CLAUDECODE
        printf 'n\n' | bash '${TATARA}' proj 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P3-AK-2: Exit-Code $status erwartet 0. Output: $output"; false; }
    # curl-Log muss leer oder nicht vorhanden sein
    if [[ -f "$CURL_STUB_LOG" ]] && [[ -s "$CURL_STUB_LOG" ]]; then
        echo "P3-AK-2: CURL_STUB_LOG hat Eintraege obwohl stdin=n (kein curl erwartet):"
        cat "$CURL_STUB_LOG"
        echo "Output: $output"
        false
    fi
    # Output muss manuellen Hinweis enthalten
    local found_hint=0
    [[ "$output" == *"brew install --cask claude-code"* ]] && found_hint=1
    [[ "$output" == *"npm install"* ]]                     && found_hint=1
    [ "$found_hint" -eq 1 ] \
        || { echo "P3-AK-2: Manueller Hinweis (brew install --cask claude-code / npm install) nicht im Output. Output: $output"; false; }
    # Projekt muss trotzdem angelegt sein
    [ -d "${BATS_TEST_TMPDIR}/dev/proj" ] \
        || { echo "P3-AK-2: Projekt 'proj' nicht angelegt. dev-Inhalt:"; ls "${BATS_TEST_TMPDIR}/dev" 2>/dev/null; false; }
}

# ==============================================================================
# P3-AK-3 — claude fehlt, TATARA_INTERACTIVE=0, stdin y -> kein curl, Hinweis 'nicht-interaktiv'
# ==============================================================================

@test "P3-AK-3: claude fehlt, TATARA_INTERACTIVE=0, stdin y -> curl-Log leer, Output enthaelt 'nicht-interaktiv', Projekt angelegt, Exit 0" {
    # P3-AK-3: Non-interaktiv + fehlendes claude -> confirm schlaegt fehl (kein prompt);
    # Output zeigt nicht-interaktiv-Hinweis; kein curl-Call; Projekt angelegt.
    _setup_full_globals
    local no_claude_path
    no_claude_path="$(_path_no_claude)"

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${no_claude_path}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CURL_STUB_LOG='${CURL_STUB_LOG}'
        export CURL_STUB_MODE=ok
        export TATARA_INTERACTIVE=0
        unset CLAUDECODE
        printf 'y\n' | bash '${TATARA}' proj 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P3-AK-3: Exit-Code $status erwartet 0. Output: $output"; false; }
    # curl-Log muss leer oder nicht vorhanden sein
    if [[ -f "$CURL_STUB_LOG" ]] && [[ -s "$CURL_STUB_LOG" ]]; then
        echo "P3-AK-3: CURL_STUB_LOG hat Eintraege obwohl TATARA_INTERACTIVE=0 (kein curl erwartet):"
        cat "$CURL_STUB_LOG"
        echo "Output: $output"
        false
    fi
    # Output muss 'nicht-interaktiv' (oder Variante) enthalten
    [[ "$output" == *"nicht-interaktiv"* ]] || [[ "$output" == *"nicht interaktiv"* ]] \
        || { echo "P3-AK-3: 'nicht-interaktiv' nicht im Output. Output: $output"; false; }
    # Projekt muss angelegt sein
    [ -d "${BATS_TEST_TMPDIR}/dev/proj" ] \
        || { echo "P3-AK-3: Projekt 'proj' nicht angelegt. dev-Inhalt:"; ls "${BATS_TEST_TMPDIR}/dev" 2>/dev/null; false; }
}

# ==============================================================================
# P3-AK-4 — claude fehlt, stdin y, CURL_STUB_MODE=fail -> set-e ueberlebt,
#             Output enthaelt 'fehlgeschlagen' + Alternativen, Projekt angelegt
# ==============================================================================

@test "P3-AK-4: claude fehlt, stdin y, CURL_MODE=fail -> Output 'fehlgeschlagen'+Alternativen, Exit 0, Projekt angelegt" {
    # P3-AK-4: ensure_claude schlaegt beim curl|bash fehl -> set -e darf NICHT
    # abbrechen (ensure_claude returnt immer 0); Output zeigt Fehlertext + Alternativen;
    # Projekt wird danach noch angelegt.
    _setup_full_globals
    local no_claude_path
    no_claude_path="$(_path_no_claude)"

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${no_claude_path}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CURL_STUB_LOG='${CURL_STUB_LOG}'
        export CURL_STUB_MODE=fail
        export TATARA_INTERACTIVE=1
        unset CLAUDECODE
        printf 'y\n' | bash '${TATARA}' proj 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P3-AK-4: Exit-Code $status erwartet 0 (ensure_claude non-blocking). Output: $output"; false; }
    # Output muss 'fehlgeschlagen' enthalten
    [[ "$output" == *"fehlgeschlagen"* ]] \
        || { echo "P3-AK-4: 'fehlgeschlagen' nicht im Output. Output: $output"; false; }
    # Output muss Alternativen nennen (brew oder npm)
    local found_alt=0
    [[ "$output" == *"brew install --cask claude-code"* ]] && found_alt=1
    [[ "$output" == *"npm install"* ]]                     && found_alt=1
    [ "$found_alt" -eq 1 ] \
        || { echo "P3-AK-4: Keine Installations-Alternativen (brew/npm) nach Fehler im Output. Output: $output"; false; }
    # Projekt muss trotzdem angelegt sein
    [ -d "${BATS_TEST_TMPDIR}/dev/proj" ] \
        || { echo "P3-AK-4: Projekt 'proj' nicht angelegt nach curl-Fehler. dev-Inhalt:"; ls "${BATS_TEST_TMPDIR}/dev" 2>/dev/null; false; }
}

# ==============================================================================
# P3-AK-5 — claude da, NICHT eingeloggt -> Reparatur-Anleitung im Output,
#             keine Privacy-Marker, Projekt angelegt, kein curl-Call
# ==============================================================================

@test "P3-AK-5: claude da, CLAUDE_STUB_LOGGED_IN=0 -> Output enthaelt 'claude auth login' + Reparatur-Anleitung, keine Privacy-Marker, Projekt angelegt, Exit 0, kein curl" {
    # P3-AK-5: ensure_claude erkennt 'claude vorhanden aber nicht eingeloggt' ->
    # Warn-Ausgabe mit 'claude auth login' UND H-2-Reparatur-Anleitung
    # (tatara --bootstrap-globals + rm + architect); keine Auth-Daten geleakt;
    # Projekt wird angelegt; kein curl-Aufruf.
    _setup_full_globals

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CURL_STUB_LOG='${CURL_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=0
        unset CLAUDECODE
        bash '${TATARA}' proj </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P3-AK-5: Exit-Code $status erwartet 0. Output: $output"; false; }
    # Output muss 'claude auth login' enthalten
    [[ "$output" == *"claude auth login"* ]] \
        || { echo "P3-AK-5: 'claude auth login' nicht im Output. Output: $output"; false; }
    # Output muss Reparatur-Anleitung enthalten (tatara --bootstrap-globals + rm/architect)
    [[ "$output" == *"--bootstrap-globals"* ]] \
        || { echo "P3-AK-5: '--bootstrap-globals' (Reparatur-Anleitung) nicht im Output. Output: $output"; false; }
    local found_rm=0
    [[ "$output" == *"architect"* ]] && found_rm=1
    [ "$found_rm" -eq 1 ] \
        || { echo "P3-AK-5: 'architect' (rm-Hinweis H-2) nicht im Output. Output: $output"; false; }
    # Keine Privacy-Marker
    [[ "$output" != *"ORG-SECRET"* ]] \
        || { echo "P3-AK-5: Privacy-Marker 'ORG-SECRET' im Output (Leak!). Output: $output"; false; }
    [[ "$output" != *"x@y.z"* ]] \
        || { echo "P3-AK-5: Privacy-Marker 'x@y.z' im Output (Leak!). Output: $output"; false; }
    [[ "$output" != *"subscriptionType"* ]] \
        || { echo "P3-AK-5: Privacy-Marker 'subscriptionType' im Output (Leak!). Output: $output"; false; }
    # Projekt muss angelegt sein
    [ -d "${BATS_TEST_TMPDIR}/dev/proj" ] \
        || { echo "P3-AK-5: Projekt 'proj' nicht angelegt. dev-Inhalt:"; ls "${BATS_TEST_TMPDIR}/dev" 2>/dev/null; false; }
    # Kein curl-Aufruf
    if [[ -f "$CURL_STUB_LOG" ]] && [[ -s "$CURL_STUB_LOG" ]]; then
        echo "P3-AK-5: CURL_STUB_LOG hat Eintraege obwohl claude da (kein curl erwartet):"
        cat "$CURL_STUB_LOG"
        false
    fi
}

# ==============================================================================
# P3-AK-6 — claude da + eingeloggt -> stiller Durchlauf, kein Install-Prompt
# ==============================================================================

@test "P3-AK-6: claude da, CLAUDE_STUB_LOGGED_IN=1 -> kein 'claude auth login', kein Install-Prompt, kein curl, Exit 0" {
    # P3-AK-6: claude vorhanden + eingeloggt -> ensure_claude ist eine No-op;
    # kein Prompt, keine Warnung, kein curl-Call.
    _setup_full_globals

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CURL_STUB_LOG='${CURL_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        unset CLAUDECODE
        bash '${TATARA}' proj </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P3-AK-6: Exit-Code $status erwartet 0. Output: $output"; false; }
    # Kein Login-Prompt, kein Install-Hinweis, kein curl-Call
    [[ "$output" != *"claude auth login"* ]] \
        || { echo "P3-AK-6: 'claude auth login' im Output obwohl eingeloggt. Output: $output"; false; }
    [[ "$output" != *"installieren"* ]] \
        || { echo "P3-AK-6: Install-Frage im Output obwohl claude da+eingeloggt. Output: $output"; false; }
    if [[ -f "$CURL_STUB_LOG" ]] && [[ -s "$CURL_STUB_LOG" ]]; then
        echo "P3-AK-6: CURL_STUB_LOG hat Eintraege obwohl eingeloggt:"
        cat "$CURL_STUB_LOG"
        false
    fi
}

# ==============================================================================
# P3-AK-7 — CLAUDECODE=1, claude NICHT im PATH -> kein claude-Check, Projekt angelegt
# ==============================================================================

@test "P3-AK-7: CLAUDECODE=1, claude nicht im PATH, volle Globals -> keine claude-Warnung/Install/curl, Projekt angelegt, Exit 0" {
    # P3-AK-7: CLAUDECODE-Session-Guard -> ensure_claude springt sofort raus (return 0),
    # KEINE Ausgabe, kein curl. Projekt wird normal angelegt.
    _setup_full_globals
    local no_claude_path
    no_claude_path="$(_path_no_claude)"

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${no_claude_path}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CURL_STUB_LOG='${CURL_STUB_LOG}'
        export CLAUDECODE=1
        bash '${TATARA}' proj </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P3-AK-7: Exit-Code $status erwartet 0. Output: $output"; false; }
    # Kein claude-Warn-/Install-Text
    [[ "$output" != *"claude auth login"* ]] \
        || { echo "P3-AK-7: 'claude auth login' im Output obwohl CLAUDECODE=1. Output: $output"; false; }
    [[ "$output" != *"installieren"* ]] \
        || { echo "P3-AK-7: Install-Prompt im Output obwohl CLAUDECODE=1 (soll keine Ausgabe erzeugen). Output: $output"; false; }
    # Kein curl-Aufruf
    if [[ -f "$CURL_STUB_LOG" ]] && [[ -s "$CURL_STUB_LOG" ]]; then
        echo "P3-AK-7: CURL_STUB_LOG hat Eintraege obwohl CLAUDECODE=1 (ensure_claude soll sofort return 0):"
        cat "$CURL_STUB_LOG"
        false
    fi
    # Projekt muss angelegt sein
    [ -d "${BATS_TEST_TMPDIR}/dev/proj" ] \
        || { echo "P3-AK-7: Projekt 'proj' nicht angelegt. dev-Inhalt:"; ls "${BATS_TEST_TMPDIR}/dev" 2>/dev/null; false; }
}

# ==============================================================================
# P3-AK-8 — --check 4 Subfaelle: eingeloggt / nicht eingeloggt / claude fehlt / CLAUDECODE
# ==============================================================================

@test "P3-AK-8a: --check, claude da + eingeloggt -> Output 'installiert' + 'eingeloggt', Exit 0" {
    # P3-AK-8a: mode_check zeigt claude-Statusblock; Subfall eingeloggt.
    _setup_full_globals

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CURL_STUB_LOG='${CURL_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        unset CLAUDECODE
        bash '${TATARA}' --check 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P3-AK-8a: Exit-Code $status erwartet 0. Output: $output"; false; }
    # Output muss claude + installiert erwaehnen
    local found_inst=0
    [[ "$output" == *"installiert"* ]] && found_inst=1
    [ "$found_inst" -eq 1 ] \
        || { echo "P3-AK-8a: 'installiert' nicht im Output. Output: $output"; false; }
    # Output muss eingeloggt erwaehnen
    [[ "$output" == *"eingeloggt"* ]] \
        || { echo "P3-AK-8a: 'eingeloggt' nicht im Output. Output: $output"; false; }
}

@test "P3-AK-8b: --check, claude da + nicht eingeloggt -> Output 'claude auth login', Exit 0" {
    # P3-AK-8b: mode_check zeigt claude-Statusblock; Subfall nicht eingeloggt.
    _setup_full_globals

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CURL_STUB_LOG='${CURL_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=0
        unset CLAUDECODE
        bash '${TATARA}' --check 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P3-AK-8b: Exit-Code $status erwartet 0. Output: $output"; false; }
    [[ "$output" == *"claude auth login"* ]] \
        || { echo "P3-AK-8b: 'claude auth login' nicht im Output. Output: $output"; false; }
}

@test "P3-AK-8c: --check, claude fehlt -> Output 'nicht gefunden', Exit 0" {
    # P3-AK-8c: mode_check zeigt claude-Statusblock; Subfall claude fehlt.
    _setup_full_globals
    local no_claude_path
    no_claude_path="$(_path_no_claude)"

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${no_claude_path}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CURL_STUB_LOG='${CURL_STUB_LOG}'
        unset CLAUDECODE
        bash '${TATARA}' --check 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P3-AK-8c: Exit-Code $status erwartet 0. Output: $output"; false; }
    [[ "$output" == *"nicht gefunden"* ]] \
        || { echo "P3-AK-8c: 'nicht gefunden' nicht im Output. Output: $output"; false; }
}

@test "P3-AK-8d: --check, CLAUDECODE=1 -> Output nennt Claude-Code-Session, Exit 0" {
    # P3-AK-8d: mode_check zeigt claude-Statusblock; Subfall CLAUDECODE=1.
    _setup_full_globals

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CURL_STUB_LOG='${CURL_STUB_LOG}'
        export CLAUDECODE=1
        bash '${TATARA}' --check 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P3-AK-8d: Exit-Code $status erwartet 0. Output: $output"; false; }
    # Output muss CLAUDECODE oder Claude-Code-Session erwaehnen
    local found_cc=0
    [[ "$output" == *"CLAUDECODE"* ]]      && found_cc=1
    [[ "$output" == *"Claude Code"* ]]     && found_cc=1
    [[ "$output" == *"claude-code"* ]]     && found_cc=1
    [[ "$output" == *"Claude-Code"* ]]     && found_cc=1
    [ "$found_cc" -eq 1 ] \
        || { echo "P3-AK-8d: Kein Claude-Code-Session-Hinweis in --check Output. Output: $output"; false; }
}

# ==============================================================================
# P3-AK-9 — --check + claude fehlt + interaktiv + stdin y -> kein curl, kein [y/N]-Prompt
# ==============================================================================

@test "P3-AK-9: --check, claude fehlt, TATARA_INTERACTIVE=1, stdin y -> curl-Log leer, Output enthaelt kein '[y/N]', Exit 0" {
    # P3-AK-9: --check darf NIEMALS installieren oder fragen. Auch wenn interaktiv + y gegeben.
    _setup_full_globals
    local no_claude_path
    no_claude_path="$(_path_no_claude)"

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${no_claude_path}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CURL_STUB_LOG='${CURL_STUB_LOG}'
        export CURL_STUB_MODE=ok
        export TATARA_INTERACTIVE=1
        unset CLAUDECODE
        printf 'y\n' | bash '${TATARA}' --check 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P3-AK-9: Exit-Code $status erwartet 0. Output: $output"; false; }
    # curl-Log muss leer oder nicht vorhanden sein
    if [[ -f "$CURL_STUB_LOG" ]] && [[ -s "$CURL_STUB_LOG" ]]; then
        echo "P3-AK-9: CURL_STUB_LOG hat Eintraege obwohl --check nie installieren darf:"
        cat "$CURL_STUB_LOG"
        echo "Output: $output"
        false
    fi
    # Output darf kein [y/N]-Prompt enthalten (kein Fragen bei --check)
    [[ "$output" != *"[y/N]"* ]] \
        || { echo "P3-AK-9: '[y/N]' im --check Output — --check darf nie installieren/fragen. Output: $output"; false; }
}

# ==============================================================================
# P3-AK-10 — --bootstrap-globals, claude fehlt, non-interaktiv ->
#              claude-Hinweis VOR erster 'geschrieben:'-Zeile
# ==============================================================================

@test "P3-AK-10: --bootstrap-globals, claude fehlt, non-interaktiv, leeres ~/.claude -> claude-Hinweis erscheint VOR 'geschrieben:', Exit 0" {
    # P3-AK-10: ensure_claude laeuft VOR ensure_globals in mode_bootstrap_globals.
    # Der spezifische claude-Warn-Hinweis aus ensure_claude (enthaelt 'claude' UND
    # eine der Schluesselvokabeln: 'nicht gefunden'/'fehlt'/'installieren'/'nicht-interaktiv')
    # muss im Output vor der ersten 'geschrieben:'-Zeile erscheinen.
    # Damit wird geprueft, dass ensure_claude() VOR ensure_globals() aufgerufen wird.
    # Die Assertion ist absichtlich stark: der Hinweis-Text muss spezifisch genug sein,
    # dass er von normalen Bootstrapping-Zeilen unterschieden werden kann.
    local no_claude_path
    no_claude_path="$(_path_no_claude)"

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${no_claude_path}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CURL_STUB_LOG='${CURL_STUB_LOG}'
        export CURL_STUB_MODE=ok
        export TATARA_INTERACTIVE=0
        unset CLAUDECODE
        bash '${TATARA}' --bootstrap-globals </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P3-AK-10: Exit-Code $status erwartet 0. Output: $output"; false; }
    # Spezifischen claude-Warn-Hinweis aus ensure_claude suchen:
    # Muss 'claude' UND eines der Schluesselwoerter 'nicht gefunden'/'fehlt'/'installieren'/'nicht-interaktiv' enthalten.
    # Dieser Text stammt aus ensure_claude (warn-Ausgabe), nicht aus Titel-/Bootstrapping-Zeilen.
    local claude_warn_line=0 geschrieben_line=0 lnum=0
    while IFS= read -r line; do
        lnum=$((lnum + 1))
        if [[ $claude_warn_line -eq 0 ]] \
           && [[ "$line" == *"claude"* ]] \
           && { [[ "$line" == *"nicht gefunden"* ]] || [[ "$line" == *"fehlt"* ]] \
                || [[ "$line" == *"installieren"* ]] || [[ "$line" == *"nicht-interaktiv"* ]]; }; then
            claude_warn_line=$lnum
        fi
        if [[ $geschrieben_line -eq 0 ]] && [[ "$line" == *"geschrieben:"* ]]; then
            geschrieben_line=$lnum
        fi
    done <<< "$output"
    [ "$claude_warn_line" -gt 0 ] \
        || { echo "P3-AK-10: Kein spezifischer claude-Warn-Hinweis aus ensure_claude gefunden (erwartet Zeile mit 'claude' + 'nicht gefunden'/'fehlt'/'installieren'/'nicht-interaktiv'). Output: $output"; false; }
    [ "$geschrieben_line" -gt 0 ] \
        || { echo "P3-AK-10: Keine 'geschrieben:'-Zeile gefunden (Globals nicht geschrieben?). Output: $output"; false; }
    [ "$claude_warn_line" -lt "$geschrieben_line" ] \
        || { echo "P3-AK-10: claude-Warn-Hinweis (Zeile $claude_warn_line) erscheint NACH 'geschrieben:' (Zeile $geschrieben_line) — Reihenfolge falsch. Output: $output"; false; }
}

# ==============================================================================
# P3-AK-11 — Unit: claude_logged_in RC + stdout-Stille
# ==============================================================================

@test "P3-AK-11: claude_logged_in Unit: LOGGED_IN=1->RC 0; =0->RC 1; kein claude->RC 1; stdout immer leer" {
    # P3-AK-11: claude_logged_in gibt NIEMALS etwas auf stdout aus (Privacy).
    # RC: 0 = eingeloggt, 1 = nicht eingeloggt oder kein claude.

    # Subtest 1: eingeloggt -> RC 0, stdout leer
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        out=\$(claude_logged_in 2>/dev/null)
        rc=\$?
        printf 'RC:%d\n' \"\$rc\"
        printf 'STDOUT:[%s]\n' \"\$out\"
    "
    [[ "$output" == *"RC:0"* ]] \
        || { echo "P3-AK-11 Sub1: LOGGED_IN=1 -> erwartet RC:0. Output: $output"; false; }
    [[ "$output" == *"STDOUT:[]"* ]] \
        || { echo "P3-AK-11 Sub1: stdout nicht leer (Privacy-Verletzung). Output: $output"; false; }

    # Subtest 2: nicht eingeloggt -> RC 1, stdout leer
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=0
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        out=\$(claude_logged_in 2>/dev/null)
        rc=\$?
        printf 'RC:%d\n' \"\$rc\"
        printf 'STDOUT:[%s]\n' \"\$out\"
    "
    [[ "$output" == *"RC:1"* ]] \
        || { echo "P3-AK-11 Sub2: LOGGED_IN=0 -> erwartet RC:1. Output: $output"; false; }
    [[ "$output" == *"STDOUT:[]"* ]] \
        || { echo "P3-AK-11 Sub2: stdout nicht leer (Privacy-Verletzung). Output: $output"; false; }

    # Subtest 3: kein claude im PATH -> RC 1, stdout leer
    local no_claude_path
    no_claude_path="$(_path_no_claude)"
    run bash -c "
        set +euo pipefail
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${no_claude_path}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        main() { :; }
        source '${TATARA}' >/dev/null 2>&1 || true
        set +euo pipefail
        out=\$(claude_logged_in 2>/dev/null)
        rc=\$?
        printf 'RC:%d\n' \"\$rc\"
        printf 'STDOUT:[%s]\n' \"\$out\"
    "
    [[ "$output" == *"RC:1"* ]] \
        || { echo "P3-AK-11 Sub3: kein claude -> erwartet RC:1. Output: $output"; false; }
    [[ "$output" == *"STDOUT:[]"* ]] \
        || { echo "P3-AK-11 Sub3: stdout nicht leer (Privacy-Verletzung). Output: $output"; false; }
}

# ==============================================================================
# P3-AK-12 — tatara -h enthaelt 'claude auth login'
# ==============================================================================

@test "P3-AK-12: tatara -h enthaelt 'claude auth login'" {
    # P3-AK-12: Die Hilfetextausgabe muss 'claude auth login' als Referenz enthalten,
    # damit Nutzer wissen wie sie sich einloggen koennen.
    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PATH='${STUB_PATH}'
        bash '${TATARA}' -h 2>&1
    "
    [[ "$output" == *"claude auth login"* ]] \
        || { echo "P3-AK-12: 'claude auth login' nicht in -h Output. Output: $output"; false; }
}

# ==============================================================================
# P3-AK-13 — mode_tatara Reihenfolge + Wizard
# ==============================================================================

@test "P3-AK-13a: mode_tatara, bd fehlt, non-interaktiv -> bd-Fehler + Exit!=0, KEIN claude-Hinweis (beweist: ensure_claude laeuft NACH ensure_bd)" {
    # P3-AK-13a: Beweis der Reihenfolge ensure_bd VOR ensure_claude in mode_tatara.
    # Methode: Wenn bd fehlt und tatara non-interaktiv laeuft, bricht ensure_bd
    # via err() ab (Exit 1), BEVOR ensure_claude aufgerufen wird.
    # Nachweis:
    #   - Exit != 0 (ensure_bd hat abgebrochen)
    #   - Output enthaelt bd-Fehlermeldung ('bd' + 'fehlt'/'benoetigt'/'Homebrew')
    #   - Output enthaelt KEINEN claude-Hinweis ('claude auth login' oder Install-Frage)
    #     das beweist: ensure_claude wurde nie aufgerufen.
    _setup_full_globals
    local no_bd_path
    no_bd_path="$(_path_no_bd)"

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${no_bd_path}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CURL_STUB_LOG='${CURL_STUB_LOG}'
        export TATARA_INTERACTIVE=0
        unset CLAUDECODE
        bash '${TATARA}' proj </dev/null 2>&1
    "
    # ensure_bd bricht via err() ab -> Exit != 0
    [ "$status" -ne 0 ] \
        || { echo "P3-AK-13a: Exit-Code 0 erwartet != 0 (ensure_bd muss abbrechen wenn bd fehlt + non-interaktiv). Output: $output"; false; }
    # bd-Fehlermeldung muss im Output sein
    local found_bd_err=0
    [[ "$output" == *"bd fehlt"* ]]          && found_bd_err=1
    [[ "$output" == *"bd wird benoetigt"* ]]  && found_bd_err=1
    [[ "$output" == *"Homebrew"* ]]           && found_bd_err=1
    [ "$found_bd_err" -eq 1 ] \
        || { echo "P3-AK-13a: Kein bd-Fehlermeldung im Output (erwartet 'bd fehlt'/'bd wird benoetigt'/'Homebrew'). Output: $output"; false; }
    # KEIN claude-Hinweis: ensure_claude wurde nie aufgerufen.
    # Spezifische claude-Meldungen aus ensure_claude pruefen (nicht allgemeine Wrter wie 'installiert').
    [[ "$output" != *"claude auth login"* ]] \
        || { echo "P3-AK-13a: 'claude auth login' im Output — ensure_claude wurde aufgerufen obwohl ensure_bd abgebrochen hat (Reihenfolge falsch!). Output: $output"; false; }
    # "claude (Claude Code) ist nicht installiert." — aus ensure_claude warn-Zeile
    [[ "$output" != *"claude (Claude Code) ist nicht installiert"* ]] \
        || { echo "P3-AK-13a: claude-Install-Warnung im Output — ensure_claude wurde aufgerufen obwohl ensure_bd abgebrochen hat (Reihenfolge falsch!). Output: $output"; false; }
    # "claude via offizielles Skript installieren" — aus ensure_claude confirm-Frage
    [[ "$output" != *"claude via offizielles Skript"* ]] \
        || { echo "P3-AK-13a: claude-Install-Frage im Output — ensure_claude wurde aufgerufen obwohl ensure_bd abgebrochen hat (Reihenfolge falsch!). Output: $output"; false; }
}

# ==============================================================================
# P3-AK-13c — mode_tatara: ensure_claude VOR ensure_globals (claude-Hinweis vor 'geschrieben:')
# ==============================================================================

@test "P3-AK-13c: mode_tatara, claude fehlt, git+bd da, Globals unvollstaendig, non-interaktiv -> claude-Hinweis VOR 'geschrieben:' (ensure_claude vor ensure_globals)" {
    # P3-AK-13c: Beweis der Reihenfolge ensure_claude VOR ensure_globals in mode_tatara.
    # Methode analog P3-AK-10: claude fehlt (non-interaktiv) -> ensure_claude erzeugt
    # claude-Warn-Hinweis; danach ensure_globals schreibt fehlende Dateien ('geschrieben:').
    # Der claude-Hinweis muss im Output VOR der ersten 'geschrieben:'-Zeile erscheinen.
    # Globals unvollstaendig: eine Agenten-Datei fehlt, damit ensure_globals aktiv wird.
    local claude_dir="${BATS_TEST_TMPDIR}/home/.claude"
    local agents_dir="${claude_dir}/agents"
    mkdir -p "$agents_dir"
    printf 'dummy\n' > "${claude_dir}/CLAUDE.md"
    printf 'dummy\n' > "${claude_dir}/software-development-workflow.md"
    # Nur 5 von 6 Agenten-Dateien anlegen (architect.md fehlt -> Globals unvollstaendig)
    for agent in architect-reviewer developer qa-reviewer security-reviewer test-writer; do
        printf 'dummy\n' > "${agents_dir}/${agent}.md"
    done
    local no_claude_path
    no_claude_path="$(_path_no_claude)"

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${no_claude_path}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CURL_STUB_LOG='${CURL_STUB_LOG}'
        export TATARA_INTERACTIVE=0
        unset CLAUDECODE
        bash '${TATARA}' proj </dev/null 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P3-AK-13c: Exit-Code $status erwartet 0. Output: $output"; false; }
    # claude-Warn-Hinweis (ensure_claude) und 'geschrieben:' (ensure_globals) suchen
    local claude_warn_line=0 geschrieben_line=0 lnum=0
    while IFS= read -r line; do
        lnum=$((lnum + 1))
        if [[ $claude_warn_line -eq 0 ]] \
           && [[ "$line" == *"claude"* ]] \
           && { [[ "$line" == *"nicht gefunden"* ]] || [[ "$line" == *"fehlt"* ]] \
                || [[ "$line" == *"installieren"* ]] || [[ "$line" == *"nicht-interaktiv"* ]]; }; then
            claude_warn_line=$lnum
        fi
        if [[ $geschrieben_line -eq 0 ]] && [[ "$line" == *"geschrieben:"* ]]; then
            geschrieben_line=$lnum
        fi
    done <<< "$output"
    [ "$claude_warn_line" -gt 0 ] \
        || { echo "P3-AK-13c: Kein claude-Warn-Hinweis aus ensure_claude gefunden. Output: $output"; false; }
    [ "$geschrieben_line" -gt 0 ] \
        || { echo "P3-AK-13c: Keine 'geschrieben:'-Zeile gefunden (Globals nicht gebootstrappt?). Output: $output"; false; }
    [ "$claude_warn_line" -lt "$geschrieben_line" ] \
        || { echo "P3-AK-13c: claude-Warn-Hinweis (Z.$claude_warn_line) erscheint NACH 'geschrieben:' (Z.$geschrieben_line) — ensure_claude laeuft nicht vor ensure_globals. Output: $output"; false; }
}

@test "P3-AK-13b: Wizard, claude da+eingeloggt, stdin 'proj\\n\\n' -> Projekt angelegt, Exit 0, kein claude-Prompt der stdin stoert" {
    # P3-AK-13b: claude eingeloggt = ensure_claude ist still (kein Prompt).
    # Der Wizard-stdin-Fluss darf nicht durch einen claude-Prompt unterbrochen werden.
    # Test: TATARA_INTERACTIVE=1, stdin 'proj\n\n' -> Wizard laedt Name + Beschreibung,
    # Projekt wird angelegt.
    _setup_full_globals

    run bash -c "
        export HOME='${BATS_TEST_TMPDIR}/home'
        export PROJECTS_ROOT='${BATS_TEST_TMPDIR}/dev'
        export PATH='${STUB_PATH}'
        export CLAUDE_STUB_LOG='${CLAUDE_STUB_LOG}'
        export CURL_STUB_LOG='${CURL_STUB_LOG}'
        export CLAUDE_STUB_LOGGED_IN=1
        export TATARA_INTERACTIVE=1
        unset CLAUDECODE
        printf 'proj\n\n' | bash '${TATARA}' 2>&1
    "
    [ "$status" -eq 0 ] \
        || { echo "P3-AK-13b: Exit-Code $status erwartet 0. Output: $output"; false; }
    [ -d "${BATS_TEST_TMPDIR}/dev/proj" ] \
        || { echo "P3-AK-13b: Projekt 'proj' nicht angelegt. dev-Inhalt:"; ls "${BATS_TEST_TMPDIR}/dev" 2>/dev/null; false; }
    # Kein Install-Prompt stört Wizard-stdin: prüfe auf den install-spezifischen Anker
    # (nicht auf "[y/N]" allgemein, da das neue Kickoff-confirm ebenfalls [y/N] ausgibt)
    [[ "$output" != *"claude via offizielles Skript"* ]] \
        || { echo "P3-AK-13b: claude-Install-Frage 'claude via offizielles Skript' im Output — stoert Wizard-stdin. Output: $output"; false; }
}
