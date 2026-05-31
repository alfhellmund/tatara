# tatara

**Tatara – damit beginnt dein neues KI-Projekt.**

Der *Tatara* ist der traditionelle japanische Schmelzofen, in dem aus Sand der
legendäre Tamahagane-Stahl entsteht. Dieses Skript ist der Ofen für neue
Projekte: Es legt ein frisches Projekt mit Git, Beads und dem Claude-Workflow an.

## Nutzung

```
tatara <NAME> [BESCHREIBUNG]   Neues Projekt unter ~/Development/<NAME> anlegen
tatara --check                 Globale Voraussetzungen prüfen
tatara --bootstrap-globals     Fehlende globale ~/.claude/* Dateien anlegen
tatara --snapshot-globals      Aktuelle ~/.claude/* Dateien als Templates sichern
tatara -h | --help             Hilfe
```

## Plattform & Voraussetzungen

Läuft auf **macOS** und **Linux**. Windows wird über **WSL** unterstützt (kein nativer Port).

Fehlende Tools installiert `tatara` bei Bedarf selbst (mit y/N-Rückfrage):

| | macOS | Linux |
|---|---|---|
| **Shell** | zsh (Standard) | zsh muss vorhanden sein (`sudo apt install zsh` o. ä.) |
| **Paketmanager** | Homebrew | apt / dnf / pacman / zypper (oder brew) |
| **git** | `brew install git` | via System-Paketmanager |
| **bd** (Beads) | `brew install beads` | brew falls vorhanden, sonst offizielles [Beads-Install-Skript](https://github.com/gastownhall/beads) |

Einzige nicht automatisierbare Voraussetzung: ein Paketmanager (macOS: Homebrew) bzw. zsh auf Linux.
