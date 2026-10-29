# shellcheck shell=bash
# rev — reverse engineering: Ghidra, radare2, Rizin and Cutter, ImHex, tracing,
# unpacking, Java/Android decompilers and Python bytecode tools.

pa_register rev "Reverse engineering: Ghidra, radare2, Cutter, ImHex, jadx, pycdc, ltrace/strace" "amd64 arm64" mod_rev

# pycdc (Python bytecode decompiler): no release builds, so compile it
pa_rev_pycdc() {
  local dir="$PA_SRC/pycdc" log
  if [ "$PA_UPDATE" != 1 ] && [ -x "$PA_BIN/pycdc" ]; then pa_info "pycdc ✓"; return 0; fi
  mkdir -p "$PA_SRC" "$PA_BIN"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull -q --ff-only || pa_warn "pycdc: git pull failed, building the current copy"
  else
    git clone -q --depth 1 https://github.com/zrax/pycdc.git "$dir" || { pa_warn "pycdc: clone failed"; return 1; }
  fi
  log=$(mktemp)
  if pa_bg "$log" "build: pycdc" sh -c "cmake -S '$dir' -B '$dir/build' -DCMAKE_BUILD_TYPE=Release && cmake --build '$dir/build' -j\"\$(nproc)\""; then
    install -m 755 "$dir/build/pycdc" "$dir/build/pycdas" "$PA_BIN/"
    rm -f "$log"
    pa_info "pycdc, pycdas installed"
  else
    pa_warn "pycdc: build failed"; pa_show_tail "$log"; rm -f "$log"; return 1
  fi
}

mod_rev() {
  local rc=0

  # Kali's Ghidra is built per arch, so its decompiler runs natively on arm64.
  # It pulls in a JDK (~1 GB with Ghidra itself).
  pa_apt ghidra || rc=1
  pa_apt radare2 rizin rizin-cutter imhex \
         ltrace strace valgrind elfutils upx-ucl binwalk \
         jadx apktool pyinstxtractor \
         z3 python3-z3 cmake || rc=1
  pa_rev_pycdc || rc=1
  return $rc
}
