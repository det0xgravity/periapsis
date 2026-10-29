# Periapsis

**A modular, open-source CTF workstation builder for Kali Linux and Parrot OS, built for arm64 VMs on Apple Silicon.**

*Periapsis: the point in an orbit closest to the body it circles.*

Periapsis turns a fresh Kali or Parrot install into an organised CTF machine:
a folder per event and per challenge, flags checked against the event's
format, a progress board, writeups built from your notes, and a
tamper-evident log of what you ran. Tool modules (web, crypto, pwn, rev,
forensics…) are added one at a time, each marked for the architectures it supports.

![Lint](https://github.com/det0xgravity/periapsis/actions/workflows/lint.yml/badge.svg)
![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue)

## Why

- **Modular**: install everything, or just the pieces you want (`--only`, `--skip`).
- **Idempotent**: re-running skips what's already there; `--update` upgrades in place.
- **Isolated**: Python tools go into pipx or private venvs; Debian's `EXTERNALLY-MANAGED` safeguard stays.
- **Honest about failures**: every module reports success or failure, and the summary lists anything that needs attention.
- **arm64-aware**: modules say which architectures they support, and `pa-doctor` reports what's missing.

## Supported platforms

| Platform | Status |
|---|---|
| Kali Linux (rolling), arm64 in UTM | Primary target |
| Parrot OS (Security), arm64 in UTM | Supported |
| Kali / Parrot amd64 | Supported |

Setting up the VM: [docs/UTM.md](docs/UTM.md).

## Quick start

```bash
git clone https://github.com/det0xgravity/periapsis.git
cd periapsis
./install.sh
```

Run it **as your normal user**: it asks for your sudo password once. Then open a new terminal:

```bash
pa-doctor                                        # check the install
pa-event new "picoCTF 2027" --flag-format 'picoCTF\{.+\}'
cd "$(pa-chal add web "Cookie Monster" --points 100)"
#   …put the handout in files/, your scripts in solve/, notes in notes.md…
pa-chal flag cookie-monster 'picoCTF{...}'
pa-event board
pa-event writeup                                 # Writeup.md, flags left out
```

Or run `periapsis` for the point-and-click menu.

## Modules

| Module | What it adds |
|---|---|
| `core` | Base packages, pipx, Go, the Periapsis runtime and menus *(always installed)* |
| `vm` | QEMU guest agent and SPICE agent (UTM clipboard, display resize), open-vm-tools on VMware, UTM shared folder at `~/utm-share` |

```bash
./install.sh --list            # show modules
./install.sh --skip vm         # everything except vm
pa-update                      # pull the latest version and upgrade everything
```

## Events

```
~/Periapsis/Events/<event>/          # private: only your account can read it
├── event.json                       # name, platform, flag format, live/finished
├── audit.log                        # time  event  tool  target  command  user  hash
├── Writeup.md
└── <category>/<challenge>/
    ├── challenge.json               # points, status, flag
    ├── notes.md                     # becomes this challenge's writeup section
    ├── files/                       # handout
    └── solve/                       # your scripts
```

A standing `scratch` event is created for practice and one-off challenges.

| Command | |
|---|---|
| `pa-event new "<name>" [--platform P] [--url U] [--flag-format REGEX]` | create an event and switch to it |
| `pa-event use <event>` · `list` · `current` · `dir` | switch, list, show |
| `pa-event board` | solved / total by category, points |
| `pa-event writeup [--flags]` | build `Writeup.md` from every challenge's notes |
| `pa-event finish` | mark the event finished |
| `pa-chal add <category> "<name>" [--points N]` | create a challenge folder (prints its path) |
| `pa-chal list` · `path <chal>` · `status <chal> <state>` | |
| `pa-chal flag <chal> <flag> [--force]` | record a flag (rejected if it doesn't match the event's format) |

**Writeups and live events.** Most CTFs forbid sharing solutions while the
event is running. Writeups of a live event carry a warning banner, flags are
left out unless you pass `--flags`, and flags are never written to `audit.log`.

## Roadmap

1. Tool modules by category, starting with the `x86` layer (running x86_64 handouts on arm64).
2. Lab platforms (HTB, TryHackMe, OffSec Proving Grounds): VPN handling, a per-box target and notes.
3. Certification prep (OSCP, CEH): an **exam mode** that warns before tools the exam rules restrict, from a list you check against the current exam guide.

## Legal and ethical use

Use Periapsis on CTFs, your own labs, and systems you are explicitly
authorised to test. Follow each event's rules, including those on sharing
solutions.

## License

Copyright (C) 2026 det0xgravity

Periapsis is free software under the [GNU General Public License](LICENSE),
version 3 or later. The tools it installs are third-party projects under their
own licenses; Periapsis installs them from their official sources and doesn't
redistribute them.
