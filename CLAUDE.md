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

First real install passed on 2026-10-28: Kali 2026.3 arm64, XFCE, in UTM
(QEMU backend), user `kali`; `core` and `vm` clean, `pa-doctor` 0 fail (the
VM had ~3 GB RAM, advised to raise to 8 GB). 0.2.0 adds the `x86` module and
`pa-x86`: **not yet run on the VM**. Parrot is untested. shellcheck runs in CI
only (not installed on the maintainer's Mac).

## Next steps

1. Run the `x86` module on the VM (`pa-update`); confirm the package names
   (`qemu-user-binfmt` on Kali's Debian 13 base), binfmt registration and the
   self-test.
2. Category modules (web, crypto, pwn, rev, forensics/stego, network), each
   checked on arm64.
3. Clone-safe VM identity and a `pa-seal` step (from True Bearing's vm module).
4. Later: lab platforms (VPN, per-box notes), OSCP/CEH exam mode (warn on
   restricted tools; the list must be checked against the current exam guide).

## Publishing

- Repo (planned): https://github.com/det0xgravity/periapsis.
- Commit as `det0xgravity <170262817+det0xgravity@users.noreply.github.com>`
  (set in this repo's local git config), never a personal address.
