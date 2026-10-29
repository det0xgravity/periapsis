# Changelog

## 0.2.0 — 2026-10-28

- **x86** module (arm64 only): QEMU user emulation registered with binfmt, so
  x86_64 and i386 handouts run as `./chall`; `libc6`/`libstdc++6` for amd64 and
  i386 through dpkg multiarch; gdb-multiarch; x86_64 binutils and gcc. Ends
  with a self-test that builds and runs a dynamically linked x86_64 program.
- `pa-x86`: `check` (architecture, linking, whether it runs here), `run`,
  `debug` (QEMU gdb stub, waiting) and `attach` (gdb-multiarch, second terminal).
- `pa-doctor` checks binfmt for x86_64 and i386, the x86 C libraries and gdb-multiarch.
- First real install confirmed: Kali 2026.3 arm64 in UTM (QEMU), core and vm modules.

## 0.1.0 — 2026-10-28

First version: the installer framework and the event workflow, no tool modules yet.

- `install.sh` for Kali Linux and Parrot OS, amd64 and arm64: modules, `--only`/`--skip`,
  `--update`, a summary of anything that failed, and remembered module choices.
- **core** module: base packages, pipx, Go, the Periapsis runtime.
- **vm** module: QEMU guest agent and SPICE agent for UTM (clipboard, display
  resizing), open-vm-tools for VMware, and UTM's shared folder at `~/utm-share`.
- Events: `pa-event` and `pa-chal` (command line, or menus with no arguments).
  A folder per CTF and per challenge (`files/`, `solve/`, `notes.md`), flags
  checked against the event's flag format, a progress board, and `Writeup.md`
  built from the notes (flags left out unless asked; a warning while the event is live).
- A hash-chained `audit.log` per event; flags are never written to it.
- `periapsis` main menu, `pa-doctor` health check, `pa-update`.
