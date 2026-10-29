# shellcheck shell=bash
# x86 — run and debug x86_64 and i386 challenge binaries on an arm64 VM.
# QEMU user emulation registered with binfmt_misc (so ./chall just runs),
# amd64/i386 C libraries through dpkg multiarch (so dynamically linked
# binaries find their loader), gdb-multiarch, and x86 cross binutils/gcc.

pa_register x86 "Run and debug x86_64/i386 binaries on arm64 (QEMU user, multiarch libc)" "arm64" mod_x86

# pa_x86_selftest — build a dynamic x86_64 binary and run it through binfmt
pa_x86_selftest() {
  local tmp out
  pa_has x86_64-linux-gnu-gcc || return 1
  tmp=$(mktemp -d)
  printf '#include <stdio.h>\nint main(void){puts("periapsis-x86-ok");return 0;}\n' > "$tmp/t.c"
  x86_64-linux-gnu-gcc -o "$tmp/t" "$tmp/t.c" >/dev/null 2>&1 || { rm -rf "$tmp"; return 1; }
  out=$("$tmp/t" 2>/dev/null)
  rm -rf "$tmp"
  [ "$out" = periapsis-x86-ok ]
}

mod_x86() {
  local rc=0 a

  # QEMU user emulation. Debian 13 (Kali's base) ships it as qemu-user plus
  # qemu-user-binfmt; older bases use qemu-user-static with binfmt-support.
  if pa_apt_has qemu-user-binfmt; then
    pa_apt qemu-user qemu-user-binfmt || rc=1
  else
    pa_apt qemu-user-static binfmt-support || rc=1
  fi
  sudo systemctl restart systemd-binfmt >/dev/null 2>&1 || true

  # Foreign architectures for the x86 C libraries (amd64 for x86_64, i386 for 32-bit)
  for a in amd64 i386; do
    if ! dpkg --print-foreign-architectures | grep -qx "$a"; then
      sudo dpkg --add-architecture "$a" && pa_info "Added dpkg architecture: $a"
      # shellcheck disable=SC2034  # read by pa_apt_update: re-read the lists for the new arch
      PA_APT_UPDATED=0
    fi
  done
  pa_apt libc6:amd64 libstdc++6:amd64 libc6:i386 libstdc++6:i386 || rc=1

  # Debugging and building
  pa_apt gdb-multiarch binutils-x86-64-linux-gnu gcc-x86-64-linux-gnu || rc=1

  for a in x86_64 i386; do
    if [ -e "/proc/sys/fs/binfmt_misc/qemu-$a" ]; then
      pa_info "binfmt: qemu-$a registered ✓"
    else
      pa_warn "binfmt: qemu-$a isn't registered (try a reboot)"; rc=1
    fi
  done
  if pa_x86_selftest; then
    pa_info "Self-test: a dynamically linked x86_64 binary ran ✓"
  else
    pa_warn "Self-test failed: x86_64 binaries don't run yet (see pa-doctor)"; rc=1
  fi
  return $rc
}
