# shellcheck shell=bash
# pwn — binary exploitation: pwntools, GEF and pwndbg for gdb, ROP gadget
# finders, one_gadget, seccomp-tools, checksec, patchelf and pwninit.
# On arm64 the x86 module makes x86 targets run and debuggable; pwntools then
# runs them through binfmt and debugs them through QEMU's gdb stub.

pa_register pwn "Binary exploitation: pwntools, GEF/pwndbg, ROPgadget, ropper, one_gadget, pwninit" "amd64 arm64" mod_pwn

mod_pwn() {
  local rc=0 deb

  # From Kali's repo (all available on arm64, checked Oct 2026). python3-pwntools
  # goes system-wide so `python3 solve.py` can `from pwn import *` anywhere.
  pa_apt python3-pwntools gef ropper python3-ropgadget checksec patchelf nasm \
         ruby ruby-dev || rc=1

  # pwndbg: the project's own .deb for this arch (Kali doesn't package it).
  # It brings its own gdb, started with the `pwndbg` command.
  case "$PA_ARCH" in arm64) deb='^pwndbg_[0-9.]+_arm64\.deb$' ;; *) deb='^pwndbg_[0-9.]+_amd64\.deb$' ;; esac
  pa_gh_deb pwndbg/pwndbg pwndbg "$deb" || rc=1

  # Ruby tools, in Periapsis's own gem folder
  pa_gem one_gadget one_gadget || rc=1
  pa_gem seccomp-tools seccomp-tools || rc=1

  # pwninit: upstream publishes an x86_64 binary only, so arm64 compiles it
  if pa_is_arm64; then
    pa_apt cargo pkg-config libssl-dev liblzma-dev || rc=1
    pa_cargo pwninit pwninit || rc=1
  else
    pa_gh_release io12/pwninit pwninit '^pwninit$' || rc=1
  fi

  # Which gdb front end pa-gdb starts by default (gef | pwndbg | plain); kept if set
  [ -s "$PA_CONF/gdb" ] || echo gef > "$PA_CONF/gdb"

  if python3 -c 'import pwn' >/dev/null 2>&1; then pa_info "pwntools importable from python3 ✓"
  else pa_warn "python3 can't import pwntools"; rc=1; fi
  return $rc
}
