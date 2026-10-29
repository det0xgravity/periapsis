# pwn and rev

The `pwn` and `rev` modules, and how the tools fit together on an arm64 VM.
Install them with `./install.sh --only pwn,rev` (on arm64, also `x86`).

## What's installed

| Module | Tool | Command | Source |
|---|---|---|---|
| pwn | pwntools (system-wide: `from pwn import *` in any script) | `pwn` | Kali |
| pwn | GEF, loaded into gdb-multiarch by `pa-gdb` | `pa-gdb` | Kali |
| pwn | pwndbg (brings its own gdb) | `pwndbg`, `pa-gdb --pwndbg` | upstream .deb, digest-verified |
| pwn | ROPgadget, ropper | `ROPgadget`, `ropper` | Kali |
| pwn | one_gadget, seccomp-tools | `one_gadget`, `seccomp-tools` | RubyGems, in `~/.local/share/periapsis/gems` |
| pwn | checksec, patchelf, nasm | `checksec`, `patchelf`, `nasm` | Kali |
| pwn | pwninit | `pwninit` | amd64: upstream binary (digest-verified); arm64: compiled with cargo |
| rev | Ghidra (native arm64 decompiler) | `ghidra` | Kali |
| rev | radare2, Rizin, Cutter | `r2`, `rizin`, `cutter` | Kali |
| rev | ImHex (hex editor with patterns) | `imhex` | Kali |
| rev | ltrace, strace, valgrind, elfutils | | Kali |
| rev | UPX (unpacking), binwalk | `upx-ucl`, `binwalk` | Kali |
| rev | jadx, apktool (Java/Android) | `jadx`, `jadx-gui`, `apktool` | Kali |
| rev | pyinstxtractor, pycdc/pycdas (Python bytecode) | `pyinstxtractor`, `pycdc`, `pycdas` | Kali; pycdc compiled from source |
| rev | Z3 (constraint solving) | `z3`, `import z3` | Kali |

## gdb: `pa-gdb`

```bash
pa-gdb ./chall                   # gdb with the default front end (GEF)
pa-gdb --pwndbg ./chall          # or pwndbg, or --plain
pa-gdb default pwndbg            # change the default
```

Your own `~/.gdbinit` isn't touched; GEF is loaded on the command line.

## x86 binaries on arm64

```bash
pa-x86 check ./chall                 # what it is, whether it runs here
pa-x86 debug ./chall                 # terminal 1: runs under QEMU, waits for gdb
pa-x86 attach ./chall                # terminal 2: gdb connected (GEF via gef-remote --qemu-user)
pa-x86 attach ./chall --pwndbg       # …or with pwndbg
```

With pwntools, `process('./chall')` runs an x86 binary through QEMU
transparently. For `gdb.debug()`, pwntools starts foreign-architecture
binaries under QEMU's gdb stub itself; set `context.binary = ELF('./chall')`
first. If it can't open a terminal for gdb, set `context.terminal`, e.g.
`context.terminal = ['qterminal', '-e']` on Kali's XFCE.

### The challenge's own libc

When a challenge ships `libc.so.6` (and maybe `ld-linux-x86-64.so.2`), run the
binary against those, not the VM's: one_gadget offsets and symbol addresses
depend on the exact libc.

```bash
cd files/ && pwninit            # finds the loader, patches the binary, writes solve.py
one_gadget libc.so.6
```

## Known limits

- QEMU user emulation is slower than native, and some gdb features that read
  `/proc` (`vmmap` in GEF/pwndbg) show less under QEMU than on a native x86 host.
- Exploits that depend on exact heap or stack layout can behave differently
  under QEMU. If something works locally but not remotely (or the reverse),
  test against the remote service, or on an x86_64 machine.
- Not yet tried by hand on the VM: pwndbg's own gdb with an x86 target under
  QEMU, and pwntools `gdb.debug()` on arm64.
