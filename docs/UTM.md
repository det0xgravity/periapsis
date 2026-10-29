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

Most `pwn` and `rev` handout binaries are built for x86_64, and an arm64 VM
can't run them natively. A future `x86` module will set up QEMU user
emulation so `./chall` runs, with multi-architecture debugging. Until then,
`pa-doctor` reports whether x86_64 emulation is available.
