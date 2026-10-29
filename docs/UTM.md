# Periapsis in UTM on Apple Silicon

The main setup Periapsis is built and tested for: a Kali or Parrot **arm64** VM
in [UTM](https://mac.getutm.app) on an Apple Silicon Mac.

## 1. Create the VM

1. Download the **arm64** installer ISO from the official site:
   [Kali](https://www.kali.org/get-kali/#kali-installer-images) or
   [Parrot](https://parrotsec.org/download/). Check its SHA-256 against the
   one published on the download page.
2. In UTM: **Create a New Virtual Machine → Virtualize → Linux**.
3. Leave **Use Apple Virtualization** unticked. The QEMU backend is the tested
   one: it gives you the SPICE clipboard and the QEMU guest agent.
4. Suggested resources:

   | | Minimum | Comfortable |
   |---|---|---|
   | CPU cores | 4 | 6–8 |
   | Memory | 6 GB | 8–12 GB |
   | Disk | 64 GB | 100 GB |

5. Optional: under **Shared Directory**, pick a folder on the Mac to share.
   The `vm` module mounts it at `~/utm-share` (VirtFS).
6. Install the OS with a **normal user account** (not root).

## 2. Install Periapsis

In the VM:

```bash
git clone https://github.com/det0xgravity/periapsis.git
cd periapsis
./install.sh
```

Then open a new terminal and run `pa-doctor`.

## 3. VM settings worth checking

- **Clipboard**: needs `spice-vdagent` (installed by the `vm` module) and a
  log out/in afterwards. If copy/paste still doesn't work, check that the VM's
  display is a SPICE one (UTM's default `virtio-ramfb-gl` / `virtio-gpu-gl-pci`).
- **QEMU guest agent**: lets UTM shut the VM down cleanly. `pa-doctor` warns
  if it isn't running.
- **Snapshots**: before big changes (a new module, an `apt full-upgrade`),
  clone the VM in UTM or use `qemu-img snapshot` on the disk while it's off.
- **Networking**: UTM's default **Shared Network** works for CTF platforms
  and their VPNs (OpenVPN/WireGuard inside the VM).

## arm64 and x86_64 challenges

Most `pwn` and `rev` handout binaries are built for x86_64 (some for 32-bit
i386), and an arm64 VM can't run them natively. The `x86` module (arm64 only)
sets up:

- **QEMU user emulation** registered with binfmt_misc, so `./chall` just runs.
- **x86 C libraries** (`libc6:amd64`, `libc6:i386`, via dpkg multiarch), so
  dynamically linked binaries find their loader.
- **gdb-multiarch**, x86_64 binutils (`x86_64-linux-gnu-objdump`) and gcc
  (`x86_64-linux-gnu-gcc`).

It ends with a self-test: it builds a small dynamically linked x86_64 program
and runs it.

```bash
pa-x86 check ./chall          # architecture, linking, whether it runs here
pa-x86 run ./chall            # same as ./chall once binfmt is set up
pa-x86 debug ./chall          # starts it under QEMU's gdb stub, waiting…
pa-x86 attach ./chall         # …then in a second terminal: gdb connected to it
```

Things to know:

- Emulation is much slower than native, which can matter for brute-force or
  timing challenges.
- If a challenge ships its own `libc.so.6` and loader, run the binary against
  them (e.g. with `patchelf`), not the VM's libc. Offsets in exploits depend on it.
- Under QEMU, gdb sees the emulated program's memory and registers, but
  `info proc mappings` and similar commands that read `/proc` don't work the
  same way.
