# tatara

> **tatara** — where your new AI project begins.
> *Damit beginnt dein neues KI-Projekt.*

A *tatara* is the traditional Japanese smelting furnace that turns sand into
tamahagane steel. This script is that furnace for software projects: one command
scaffolds a fresh project with Git, [Beads](https://github.com/gastownhall/beads)
issue tracking and a ready-to-use Claude Code workflow — then hands off to an
interactive Claude session that turns your idea into a concept and a plan.

The script speaks **English and German** and picks the language from your locale.

**[English](#english) · [Deutsch](#deutsch)**

---

## English

### What it does

Run `tatara` with no arguments for an interactive wizard, or `tatara <name>` to
scaffold straight away. tatara creates `~/Development/<name>/` and sets it up
with:

```
<name>/
  .git/                          Git repo (default branch: main)
  .beads/                        local Beads issue DB (stealth, git-ignored)
  .claude/
    settings.json                PostToolUse hook -> post-commit-verify.sh
    hooks/post-commit-verify.sh  prints `git show HEAD --stat` after each commit
    skills/kickoff/SKILL.md      kickoff routine, launched via claude /kickoff
  CLAUDE.md                      project guidance with build/stack placeholders
  README.md                      minimal, name + description
  .gitignore                     macOS / IDE / secrets defaults
```

It is **Claude Code-centric**: it writes `CLAUDE.md` plus the `.claude/`
machinery and relies on the six global subagents in `~/.claude/agents/`.
Along the way it:

- **self-heals** — missing global `~/.claude/*` files are bootstrapped on the fly,
  so `tatara <name>` works even on a fresh setup;
- **right-sizes the architect model** per account — it uses Claude Fable 5 if your
  account has access, otherwise Opus (override with `TATARA_ARCHITECT_MODEL`);
- **prepares Claude Code** — if `claude` is missing it offers to install it
  (official installer, with a y/N prompt); if you are not logged in it points you
  to `claude auth login`. This is non-blocking: the scaffold is built either way;
- **kicks off** — after the scaffold it offers to launch `claude /kickoff`, an
  interactive routine that interviews you about the project idea, drafts a
  technical concept, estimates the effort and moves it into the workflow.

### Install

```bash
git clone https://github.com/alfhellmund/tatara.git
ln -s "$(pwd)/tatara/tatara" ~/.local/bin/tatara   # make sure ~/.local/bin is on $PATH
tatara --bootstrap-globals                          # one-time: create missing ~/.claude/* files
```

You can also just run `tatara <name>` right away — missing globals are created
automatically.

### Usage

```
tatara                        interactive wizard (on a terminal); otherwise help
tatara <NAME> [DESCRIPTION]   create a new project under ~/Development/<NAME>
tatara --check                check prerequisites, Claude status, model + language
tatara --bootstrap-globals    create missing global ~/.claude/* files
tatara --snapshot-globals     write the current ~/.claude/* files back into the script
tatara -h | --help            help
```

### Environment variables

```
TATARA_ARCHITECT_MODEL   force architect model: fable | opus   (default: auto-detect)
TATARA_INTERACTIVE       1 forces the wizard, 0 disables prompts (default: auto via TTY)
TATARA_LANG              force language: de | en               (default: auto via locale)
PROJECTS_ROOT            base directory for new projects       (default: ~/Development)
```

### Language

tatara detects the language from your locale (`LC_ALL` / `LC_MESSAGES` / `LANG`):
a German locale gives German output, everything else defaults to English. Both
languages are embedded in the single script — no extra files, works offline.
Force it with `TATARA_LANG=de` or `TATARA_LANG=en`.

### Requirements

Runs on **macOS** and **Linux** (bash 3.2+). Windows is supported via **WSL**
(no native port). Missing `git` and `bd` are installed on demand (with a y/N
prompt) via Homebrew (macOS) or `apt` / `dnf` / `pacman` / `zypper` (Linux); on
Linux without Homebrew, `bd` uses the official Beads install script. The only
prerequisite you install yourself is a package manager (macOS: Homebrew).

Claude Code is the intended environment: if `claude` is missing, tatara offers
to install it; logging in stays manual (`claude auth login`, browser OAuth).
`tatara --check` reports the status of `claude` plus the optional CLIs `gemini`
and `codex` — it never installs `gemini`/`codex`.

### Author & License

Made by **Alf Hellmund**. MIT — see [LICENSE](LICENSE).

---

## Deutsch

### Was es macht

`tatara` ohne Argumente startet einen interaktiven Assistenten, `tatara <name>`
legt direkt an. tatara erstellt `~/Development/<name>/` und richtet es ein mit:

```
<name>/
  .git/                          Git-Repo (Default-Branch: main)
  .beads/                        lokale Beads-Issue-DB (stealth, git-ignoriert)
  .claude/
    settings.json                PostToolUse-Hook -> post-commit-verify.sh
    hooks/post-commit-verify.sh  zeigt `git show HEAD --stat` nach jedem Commit
    skills/kickoff/SKILL.md      Kickoff-Routine, Start via claude /kickoff
  CLAUDE.md                      Projekt-Leitfaden mit Build-/Stack-Platzhaltern
  README.md                      minimal, Name + Beschreibung
  .gitignore                     macOS- / IDE- / Secrets-Standard
```

Das Skript ist **auf Claude Code zugeschnitten**: Es schreibt `CLAUDE.md` und die
`.claude/`-Maschinerie und nutzt die sechs globalen Subagenten in
`~/.claude/agents/`. Dabei:

- **heilt es sich selbst** — fehlende globale `~/.claude/*`-Dateien werden bei
  Bedarf angelegt, sodass `tatara <name>` auch frisch funktioniert;
- **wählt es das Architekt-Modell passend zum Account** — Claude Fable 5, falls
  dein Account Zugriff hat, sonst Opus (überschreibbar mit
  `TATARA_ARCHITECT_MODEL`);
- **bereitet es Claude Code vor** — fehlt `claude`, bietet es die Installation an
  (offizieller Installer, mit y/N-Rückfrage); bist du nicht eingeloggt, weist es
  auf `claude auth login` hin. Das blockiert nicht — das Gerüst entsteht so oder so;
- **gibt es den Startschuss** — nach dem Gerüst bietet es `claude /kickoff` an,
  eine interaktive Routine, die dich zur Projektidee befragt, ein technisches
  Konzept entwirft, den Aufwand schätzt und in den Workflow überführt.

### Installation

```bash
git clone https://github.com/alfhellmund/tatara.git
ln -s "$(pwd)/tatara/tatara" ~/.local/bin/tatara   # ~/.local/bin muss im $PATH sein
tatara --bootstrap-globals                          # einmalig: fehlende ~/.claude/*-Dateien anlegen
```

Du kannst auch direkt `tatara <name>` ausführen — fehlende Globals werden
automatisch angelegt.

### Nutzung

```
tatara                         interaktiver Assistent (am Terminal); sonst Hilfe
tatara <NAME> [BESCHREIBUNG]   neues Projekt unter ~/Development/<NAME> anlegen
tatara --check                 Voraussetzungen, Claude-Status, Modell + Sprache
tatara --bootstrap-globals     fehlende globale ~/.claude/*-Dateien anlegen
tatara --snapshot-globals      aktuelle ~/.claude/*-Dateien zurück ins Skript schreiben
tatara -h | --help             Hilfe
```

### Umgebungsvariablen

```
TATARA_ARCHITECT_MODEL   Architekt-Modell erzwingen: fable | opus  (Default: Auto-Erkennung)
TATARA_INTERACTIVE       1 erzwingt den Assistenten, 0 unterbindet Prompts (Default: Auto via TTY)
TATARA_LANG              Sprache erzwingen: de | en                (Default: Auto via Locale)
PROJECTS_ROOT            Basisverzeichnis fuer neue Projekte        (Default: ~/Development)
```

### Sprache

tatara erkennt die Sprache aus der Locale (`LC_ALL` / `LC_MESSAGES` / `LANG`):
eine deutsche Locale ergibt deutsche Ausgabe, alles andere ist standardmäßig
Englisch. Beide Sprachen sind im einen Skript eingebettet — keine Zusatzdateien,
funktioniert offline. Erzwingen mit `TATARA_LANG=de` oder `TATARA_LANG=en`.

### Voraussetzungen

Läuft auf **macOS** und **Linux** (bash 3.2+). Windows wird über **WSL**
unterstützt (kein nativer Port). Fehlende Tools `git` und `bd` werden bei Bedarf
(mit y/N-Rückfrage) installiert — via Homebrew (macOS) oder `apt` / `dnf` /
`pacman` / `zypper` (Linux); auf Linux ohne Homebrew zieht `bd` das offizielle
Beads-Install-Skript. Einzige selbst zu installierende Voraussetzung ist ein
Paketmanager (macOS: Homebrew).

Claude Code ist die vorgesehene Umgebung: fehlt `claude`, bietet tatara die
Installation an; der Login bleibt manuell (`claude auth login`, Browser-OAuth).
`tatara --check` meldet den Status von `claude` sowie der optionalen CLIs
`gemini` und `codex` — `gemini`/`codex` werden nie installiert.

### Autor & Lizenz

Von **Alf Hellmund**. MIT — siehe [LICENSE](LICENSE).
