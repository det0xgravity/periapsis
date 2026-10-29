# Changelog

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
