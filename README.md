# tatara

> **tatara** — where your new AI project begins.
> *Damit beginnt dein neues KI-Projekt.*

A *tatara* is the traditional Japanese smelting furnace that turns sand into
tamahagane steel. This script is that furnace for software projects: one command
scaffolds a fresh project with Git, [Beads](https://github.com/gastownhall/beads)
issue tracking and a ready-to-use Claude Code workflow.

**[English](#english) · [Deutsch](#deutsch)**

---

## English

### What it does

`tatara <name>` creates `~/Development/<name>/` and sets it up with:

```
<name>/
  .git/                          Git repo (default branch: main)
  .beads/                        local Beads issue DB (stealth, git-ignored)
  .claude/
    settings.json                PostToolUse hook -> post-commit-verify.sh
    hooks/post-commit-verify.sh  prints `git show HEAD --stat` after each commit
  CLAUDE.md                      project guidance with build/stack placeholders
  README.md                      minimal, name + description
  .gitignore                     macOS / IDE / secrets defaults
```

It is **Claude Code-centric**: it writes `CLAUDE.md` plus the `.claude/` machinery
and relies on the six global subagents in `~/.claude/agents/`.

### Install

```bash
git clone https://github.com/alfhellmund/tatara.git
ln -s "$(pwd)/tatara/tatara" ~/.local/bin/tatara   # make sure ~/.local/bin is on $PATH
tatara --bootstrap-globals                          # one-time: create missing ~/.claude/* files
```

### Usage

```
tatara <NAME> [DESCRIPTION]   create a new project under ~/Development/<NAME>
tatara --check                check prerequisites + optional AI CLIs
tatara --bootstrap-globals    create missing global ~/.claude/* files
tatara --snapshot-globals     write the current ~/.claude/* files back into the script
tatara -h | --help            help
```

Override the project root with `PROJECTS_ROOT=/path tatara <name>`. To pin the architect model, set `TATARA_ARCHITECT_MODEL=fable` or `TATARA_ARCHITECT_MODEL=opus`; the default is auto-detection.

### Requirements

Runs on **macOS** and **Linux** (bash 3.2+). Windows is supported via **WSL**
(no native port). Missing `git` and `bd` are installed on demand (with a y/N
prompt) via Homebrew (macOS) or `apt` / `dnf` / `pacman` / `zypper` (Linux); on
Linux without Homebrew, `bd` uses the official Beads install script. The only
prerequisite you install yourself is a package manager (macOS: Homebrew).

`tatara --check` also reports whether the optional AI CLIs `claude`, `gemini` and
`codex` are on your `PATH` — purely informational, it never installs them.

### Author & License

Made by **Alf Hellmund**. MIT — see [LICENSE](LICENSE).

---

## Deutsch

### Was es macht

`tatara <name>` legt `~/Development/<name>/` an und richtet es ein mit:

```
<name>/
  .git/                          Git-Repo (Default-Branch: main)
  .beads/                        lokale Beads-Issue-DB (stealth, git-ignoriert)
  .claude/
    settings.json                PostToolUse-Hook -> post-commit-verify.sh
    hooks/post-commit-verify.sh  zeigt `git show HEAD --stat` nach jedem Commit
  CLAUDE.md                      Projekt-Leitfaden mit Build-/Stack-Platzhaltern
  README.md                      minimal, Name + Beschreibung
  .gitignore                     macOS- / IDE- / Secrets-Standard
```

Das Skript ist **auf Claude Code zugeschnitten**: Es schreibt `CLAUDE.md` und die
`.claude/`-Maschinerie und nutzt die sechs globalen Subagenten in
`~/.claude/agents/`.

### Installation

```bash
git clone https://github.com/alfhellmund/tatara.git
ln -s "$(pwd)/tatara/tatara" ~/.local/bin/tatara   # ~/.local/bin muss im $PATH sein
tatara --bootstrap-globals                          # einmalig: fehlende ~/.claude/*-Dateien anlegen
```

### Nutzung

```
tatara <NAME> [BESCHREIBUNG]   neues Projekt unter ~/Development/<NAME> anlegen
tatara --check                 Voraussetzungen + optionale KI-CLIs prüfen
tatara --bootstrap-globals     fehlende globale ~/.claude/*-Dateien anlegen
tatara --snapshot-globals      aktuelle ~/.claude/*-Dateien zurück ins Skript schreiben
tatara -h | --help             Hilfe
```

Projekt-Wurzel überschreiben mit `PROJECTS_ROOT=/pfad tatara <name>`. Das Architekt-Modell kann mit `TATARA_ARCHITECT_MODEL=fable` oder `TATARA_ARCHITECT_MODEL=opus` fixiert werden; Standard ist Auto-Erkennung.

### Voraussetzungen

Läuft auf **macOS** und **Linux** (bash 3.2+). Windows wird über **WSL**
unterstützt (kein nativer Port). Fehlende Tools `git` und `bd` werden bei Bedarf
(mit y/N-Rückfrage) installiert — via Homebrew (macOS) oder `apt` / `dnf` /
`pacman` / `zypper` (Linux); auf Linux ohne Homebrew zieht `bd` das offizielle
Beads-Install-Skript. Einzige selbst zu installierende Voraussetzung ist ein
Paketmanager (macOS: Homebrew).

`tatara --check` meldet zusätzlich, ob die optionalen KI-CLIs `claude`, `gemini`
und `codex` im `PATH` sind — rein informativ, es installiert sie nie.

### Autor & Lizenz

Von **Alf Hellmund**. MIT — siehe [LICENSE](LICENSE).
