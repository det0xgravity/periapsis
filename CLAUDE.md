# CLAUDE.md — periapsis

Context for Claude Code sessions working on this repository.

## What this is

A modular, GPL-3.0-or-later CTF workstation builder for Kali Linux and Parrot
OS, amd64 and arm64. The main target is an arm64 Kali/Parrot VM in UTM on the
maintainer's Apple Silicon (M4 Pro) Mac. Sister project of
[True Bearing OSINT](https://github.com/det0xgravity/truebearing-osint) (local
checkout `../northstar-osint`), and built the same way: when a helper exists
there, port it rather than reinventing it. Focus for now is CTFs; lab
platforms (HTB/THM/PG) and OSCP/CEH exam prep come later.

Original work only: never copy code, notes or assets from courses, books or
paid products, and don't add references to them.

## Layout

- `install.sh`: entry point. Parses flags, sources every `modules/*.sh`
  (`--list` works before platform detection, so it runs anywhere), detects the
  platform, runs the selected modules through `pa_step`.
- `lib/common.sh`: installer helpers (`pa_apt`, `pa_apt_has`, `pa_pipx`,
  `pa_go`, `pa_go_ensure`, `pa_git_venv`, `pa_gh_release`, `pa_register`,
  platform detection: `PA_PLATFORM` kali|parrot, `PA_ARCH` amd64|arm64).
- `lib/ui.sh`: runtime library for the menu tools (`ui_*` zenity dialogs,
  `pa_cur_event`/`pa_cur_dir`, `pa_audit`, `pa_run`, scripted dialogs for tests).
- `lib/pa_event.py`: the engine behind events and challenges, installed as the
  command `pa_event`. Don't name a shell function `pa_event`: the tools call the
  engine by that name (that clash happened once).
- `modules/NN-name.sh`: one module each; it registers with
  `pa_register name "desc" "amd64 arm64" mod_name`. List only the arches the
  module really works on.
- `tools/`: menu/CLI tools installed to `~/.local/share/periapsis/bin` and
  linked into `~/.local/bin`.
- `docs/`: user documentation. Keep it in sync with behaviour changes.

## Hard rules

- **Bash 3.2 compatible** (kept from True Bearing so the tests run on the Mac):
  no `declare -A`, `mapfile`/`readarray`, `${var,,}`/`${var^^}`, `&>>`. Guard
  empty-array expansion under `set -u`.
- Module functions **return** non-zero on failure and never `exit`. One broken
  tool must not stop the install.
- Never remove Debian's `EXTERNALLY-MANAGED` file. Python tools go through pipx
  or private venvs (`pa_git_venv`).
- Prefer the distro's apt package (Kali and Parrot package most tools), then
  official upstream releases (checksum-verified). Don't vendor binaries.
- Check arm64 availability before relying on a package; fall back or mark the
  module amd64-only, and say so in the docs.
- Menu tools log through `pa_run`/`pa_audit`. **Flags never go into
  `audit.log`** (only a short hash), so the log can be shared.
- `lib/ui.sh` `pa_audit` and `lib/pa_event.py` `audit()` write the same
  hash chain; change both together (`tests/run.sh` checks they interoperate).
- The installer must run as a normal user; it calls sudo itself.

## Checks to run before committing

```bash
shellcheck -x -S warning install.sh lib/common.sh lib/ui.sh modules/*.sh tools/* tests/run.sh
for f in install.sh lib/*.sh modules/*.sh tools/* tests/run.sh; do bash -n "$f"; done
grep -nE 'declare -A|local -A|mapfile|readarray|\$\{[A-Za-z_]+(,,|\^\^)|&>>' install.sh lib/*.sh modules/*.sh tools/*
python3 -m py_compile lib/*.py
bash tests/run.sh          # offline functional tests (also run in CI); passes on macOS Bash 3.2
./install.sh --list
```

## Status

0.1.0 (2026-10-28): installer framework, `core` and `vm` modules, events and
challenges, `pa-doctor`. The test suite passes on macOS; **not yet run on a
real Kali or Parrot VM**, and shellcheck hasn't been run locally (CI runs it).

## Next steps

1. First real install in the maintainer's UTM VM (Kali arm64); fix what breaks.
2. `x86` module: QEMU user emulation (binfmt) so x86_64 handouts run on arm64,
   x86_64 libc for dynamically linked binaries, gdb-multiarch.
3. Category modules (web, crypto, pwn, rev, forensics/stego, network), each
   checked on arm64.
4. Clone-safe VM identity and a `pa-seal` step (from True Bearing's vm module).
5. Later: lab platforms (VPN, per-box notes), OSCP/CEH exam mode (warn on
   restricted tools; the list must be checked against the current exam guide).

## Publishing

- Repo (planned): https://github.com/det0xgravity/periapsis.
- Commit as `det0xgravity <170262817+det0xgravity@users.noreply.github.com>`
  (set in this repo's local git config), never a personal address.
