# shellcheck shell=bash
# shellcheck disable=SC2034  # variables are used by install.sh and the modules
# =============================================================================
#  periapsis — shared installer library
#  Sourced by install.sh and every module. Bash 3.2 compatible.
# =============================================================================

PA_VERSION="0.2.0"

PA_HOME="${PA_HOME:-$HOME/.local/share/periapsis}"   # tools, venvs, sources
PA_BIN="$PA_HOME/bin"                                # all Periapsis binaries
PA_VENVS="$PA_HOME/venvs"                            # per-tool Python venvs
PA_SRC="$PA_HOME/src"                                # git checkouts
PA_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/periapsis"
PA_DATA="${PA_DATA:-$HOME/Periapsis}"                # user-facing output root
PA_UPDATE="${PA_UPDATE:-0}"                          # 1 = upgrade existing tools

export PATH="$PA_BIN:$PA_HOME/go/bin:$HOME/.local/bin:$HOME/go/bin:$PATH"

# --- output ------------------------------------------------------------------
if [ -t 1 ]; then
  C_B=$'\033[1m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_0=$'\033[0m'
else
  C_B=""; C_G=""; C_Y=""; C_R=""; C_0=""
fi
pa_info() { printf '    %s\n' "$*"; }
pa_warn() { printf '    %s[!]%s %s\n' "$C_Y" "$C_0" "$*"; }
pa_err()  { printf '%s[x]%s %s\n' "$C_R" "$C_0" "$*" >&2; }
pa_die()  { pa_err "$*"; exit 1; }
pa_has()  { command -v "$1" >/dev/null 2>&1; }
# pa_show_tail <file> — print the end of a failed command's output (into the log)
pa_show_tail() { tail -n 15 "$1" | sed 's/^/        | /'; }

PA_FAILED=()
pa_step() {
  local name="$1" t0 el; shift
  PA_STEP_I=$((PA_STEP_I + 1))
  if [ "$PA_STEP_N" -gt 0 ]; then
    printf '\n%s==>%s [%s/%s] %s %s%s%s\n' "$C_G" "$C_0" "$PA_STEP_I" "$PA_STEP_N" \
      "$(pa_bar $((PA_STEP_I - 1)) "$PA_STEP_N" 18)" "$C_B" "$name" "$C_0"
  else
    printf '\n%s==>%s %s%s%s\n' "$C_G" "$C_0" "$C_B" "$name" "$C_0"
  fi
  t0=$(date +%s)
  if "$@"; then
    el=$(( $(date +%s) - t0 ))
    printf '    %sok%s (%s)\n' "$C_G" "$C_0" "$(_pa_mmss "$el")"
  else
    printf '    %sFAILED%s: %s\n' "$C_R" "$C_0" "$name"
    PA_FAILED+=("$name")
  fi
}

# --- progress ---------------------------------------------------------------------
# install.sh sets PA_TTY=1 and keeps the terminal on fd 4 when it runs in a
# terminal. Status lines are drawn there only, so install.log stays readable.
PA_TTY="${PA_TTY:-0}"
PA_STEP_I=0; PA_STEP_N=0

# pa_bar <done> <total> <width>   a bar of filled and empty blocks
pa_bar() {
  local d="$1" t="$2" w="$3" f i=0 out=""
  [ "$t" -gt 0 ] 2>/dev/null || t=1
  f=$(( d * w / t )); [ "$f" -gt "$w" ] && f=$w
  while [ $i -lt "$w" ]; do
    if [ $i -lt $f ]; then out="$out█"; else out="$out░"; fi
    i=$((i+1))
  done
  printf '%s' "$out"
}

_pa_mmss() { printf '%02d:%02d' $(( $1 / 60 )) $(( $1 % 60 )); }

# pa_bg <log> <label> <command...>   Runs a long command with its output in
# <log>. In a terminal, a status line shows a spinner, the module counter, the
# elapsed time and the command's latest output line (or a bar for a percentage).
pa_bg() {
  local log="$1" label="$2" pid rc t0 el last pct n=0 cols spin='|/-\' detail room off
  shift 2
  [ ${#label} -gt 48 ] && label="${label:0:45}..."
  if [ "$PA_TTY" != 1 ]; then "$@" >>"$log" 2>&1; return $?; fi
  cols=$(tput cols 2>/dev/null || echo 100); [ "$cols" -gt 20 ] 2>/dev/null || cols=100
  off=1; [ -f "$log" ] && off=$(( $(wc -c < "$log") + 1 ))   # read only what this command writes
  "$@" >>"$log" 2>&1 </dev/null &
  pid=$!
  t0=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    el=$(( $(date +%s) - t0 ))
    last=$(tail -c +"$off" "$log" 2>/dev/null | tail -c 4000 | tr '\r' '\n' | LC_ALL=C sed $'s/\033\\[[0-9;?]*[A-Za-z]//g' | awk 'NF' | tail -n 1)
    pct=$(printf '%s' "$last" | sed -n -E 's/(^|.*[^0-9.])([0-9]{1,3})(\.[0-9]+)?%.*/\2/p')
    room=$(( cols - ${#label} - 24 ))
    if [ -n "$pct" ] && [ "$pct" -le 100 ] 2>/dev/null; then
      room=$(( room - 27 )); [ "$room" -gt 0 ] || room=0
      detail="$(pa_bar "$pct" 100 20) $(printf '%3d' "$pct")%"
    else
      [ "$room" -gt 0 ] || room=0
      detail="${last:0:$room}"
    fi
    printf '\r\033[K    %s [%s/%s] %s  %s  %s' "${spin:$((n % 4)):1}" "$PA_STEP_I" "$PA_STEP_N" "$label" \
      "$(_pa_mmss "$el")" "$detail" >&4
    n=$((n+1))
    sleep 1
  done
  wait "$pid"; rc=$?
  printf '\r\033[K' >&4
  return $rc
}

# pa_download <url> <file> [label]   curl with a progress bar in a terminal
pa_download() {
  local log
  log=$(mktemp)
  if pa_bg "$log" "${3:-download: ${1##*/}}" curl -fL --progress-bar "$1" -o "$2"; then rm -f "$log"; return 0; fi
  pa_show_tail "$log"; rm -f "$log"; return 1
}

# --- platform detection --------------------------------------------------------
# Sets PA_PLATFORM (kali|parrot), PA_ARCH (amd64|arm64), PA_DE (xfce|mate|gnome|kde|other|none).
# Kali and Parrot only: both package most security tools, so modules can rely on apt.
pa_detect_platform() {
  case "$(uname -m)" in
    x86_64|amd64)  PA_ARCH=amd64 ;;
    aarch64|arm64) PA_ARCH=arm64 ;;
    *) pa_die "Unsupported CPU architecture: $(uname -m)" ;;
  esac

  [ "$(uname -s)" = "Linux" ] || pa_die "Periapsis runs inside a Kali or Parrot VM, not on $(uname -s)."
  [ -r /etc/os-release ] || pa_die "Cannot read /etc/os-release."
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    kali)   PA_PLATFORM=kali ;;
    parrot) PA_PLATFORM=parrot ;;
    *) pa_die "Unsupported distribution: ${ID:-unknown}. Periapsis supports Kali Linux and Parrot OS." ;;
  esac
  pa_detect_desktop
}

pa_detect_desktop() {
  local d
  d=$(printf '%s' "${XDG_CURRENT_DESKTOP:-}${DESKTOP_SESSION:-}" | tr '[:upper:]' '[:lower:]')
  case "$d" in
    *xfce*)           PA_DE=xfce ;;
    *mate*)           PA_DE=mate ;;
    *gnome*)          PA_DE=gnome ;;
    *kde*|*plasma*)   PA_DE=kde ;;
    "")
      if   pa_has startxfce4;    then PA_DE=xfce
      elif pa_has mate-session;  then PA_DE=mate
      elif pa_has gnome-session; then PA_DE=gnome
      elif pa_has startplasma-x11; then PA_DE=kde
      else PA_DE=none; fi ;;
    *) PA_DE=other ;;
  esac
}

pa_is_arm64() { [ "$PA_ARCH" = "arm64" ]; }

# --- sudo ----------------------------------------------------------------------
pa_sudo_keepalive() {
  sudo -v || pa_die "sudo is required."
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
}

# --- package managers ----------------------------------------------------------
PA_APT_UPDATED=0
pa_apt_update() {
  [ "$PA_APT_UPDATED" = 1 ] && return 0
  pa_bg "${PA_LOG:-/dev/null}" "apt: updating package lists" sudo apt-get update -q && PA_APT_UPDATED=1
}

# Installs packages as a batch; if the batch fails, retries one by one so a
# single missing package (names differ between Kali and Parrot, and between
# arches) doesn't sink the rest.
pa_apt() {
  pa_apt_update || return 1
  pa_bg "${PA_LOG:-/dev/null}" "apt: $*" sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$@" && return 0
  local p rc=0
  for p in "$@"; do
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$p" >/dev/null 2>&1 \
      || { pa_warn "apt package unavailable: $p"; rc=1; }
  done
  return $rc
}

# pa_apt_has <package>   true when apt knows the package on this distro/arch
pa_apt_has() {
  apt-cache show "$1" >/dev/null 2>&1
}

# --- Python tools ----------------------------------------------------------------

# pa_pipx <command-it-provides> [pip spec]
# Presence is checked by command name because pipx package names and command
# names often differ. Upgrades happen in bulk via 'pipx upgrade-all' in the
# core module when --update is used.
pa_pipx() {
  local cmd="$1" spec="${2:-$1}"
  if [ -x "$HOME/.local/bin/$cmd" ] || pa_has "$cmd"; then
    pa_info "$cmd ✓"
    return 0
  fi
  local log
  log=$(mktemp)
  if pa_bg "$log" "pipx: $cmd" pipx install "$spec"; then
    pa_info "$cmd installed"
    rm -f "$log"
  else
    pa_warn "pipx failed: $cmd ($spec)"
    pa_show_tail "$log"; rm -f "$log"
    return 1
  fi
}

# pa_git_venv <name> <repo-url> <entry-script> [requirements-file] [cd]
# Clones a repo, builds a private venv and writes a wrapper into $PA_BIN.
# Pass "cd" as the 5th argument for tools that must run from their own folder.
pa_git_venv() {
  local name="$1" repo="$2" entry="$3" req="${4:-requirements.txt}" mode="${5:-}"
  local dir="$PA_SRC/$name" venv="$PA_VENVS/$name" log
  mkdir -p "$PA_SRC" "$PA_VENVS" "$PA_BIN"
  if [ -d "$dir/.git" ]; then
    pa_bg /dev/null "git: $name" git -C "$dir" pull -q --ff-only || pa_warn "$name: git pull failed, keeping current copy"
  else
    pa_bg /dev/null "git: $name" git clone -q --depth 1 "$repo" "$dir" || { pa_warn "$name: clone failed"; return 1; }
  fi
  [ -x "$venv/bin/python" ] || python3 -m venv "$venv" || return 1
  pa_bg /dev/null "pip: $name" "$venv/bin/pip" install -q --upgrade pip
  if [ -f "$dir/$req" ]; then
    log=$(mktemp)
    if ! pa_bg "$log" "pip: $name" "$venv/bin/pip" install -r "$dir/$req"; then
      pa_warn "$name: some requirements failed to install"
      pa_show_tail "$log"; rm -f "$log"
      return 1
    fi
    rm -f "$log"
  fi
  {
    echo '#!/usr/bin/env bash'
    echo "# Periapsis wrapper for $name"
    [ "$mode" = "cd" ] && echo "cd \"$dir\" || exit 1"
    echo "exec \"$venv/bin/python\" \"$dir/$entry\" \"\$@\""
  } > "$PA_BIN/$name"
  chmod +x "$PA_BIN/$name"
  pa_info "$name ✓"
}

# --- Go tools --------------------------------------------------------------------
# Use the system Go if it is new enough, otherwise fetch the current release
# (checksum-verified) into $PA_HOME/go.
pa_go_minor() {
  pa_has go || { echo 0; return; }
  go env GOVERSION 2>/dev/null | sed -E 's/^go1\.([0-9]+).*/\1/' | grep -E '^[0-9]+$' || echo 0
}

pa_sha256() { sha256sum "$1" | cut -d' ' -f1; }

pa_go_ensure() {
  [ "$(pa_go_minor)" -ge 22 ] && return 0
  local ver file sum tmp json
  json=$(curl -fsSL 'https://go.dev/dl/?mode=json') || return 1
  ver=$(printf '%s' "$json" | jq -r '.[0].version')
  file="${ver}.linux-${PA_ARCH}.tar.gz"
  sum=$(printf '%s' "$json" | jq -r --arg f "$file" '.[0].files[] | select(.filename == $f) | .sha256')
  [ -n "$sum" ] || { pa_warn "No checksum published for $file"; return 1; }
  pa_info "System Go is missing or too old — installing $ver to $PA_HOME/go"
  tmp=$(mktemp -d)
  pa_download "https://go.dev/dl/$file" "$tmp/go.tgz" "download: Go toolchain" || { rm -rf "$tmp"; return 1; }
  [ "$(pa_sha256 "$tmp/go.tgz")" = "$sum" ] || { pa_warn "Go download failed its checksum: not installed"; rm -rf "$tmp"; return 1; }
  tar -C "$tmp" -xzf "$tmp/go.tgz" || { rm -rf "$tmp"; return 1; }
  mkdir -p "$PA_HOME" && rm -rf "$PA_HOME/go" && mv "$tmp/go" "$PA_HOME/go"
  rm -rf "$tmp"
  hash -r
  [ "$(pa_go_minor)" -ge 22 ]
}

# pa_go <module@version>
pa_go() {
  local name log
  name=$(basename "${1%@*}")
  if [ "$PA_UPDATE" != 1 ] && [ -x "$PA_BIN/$name" ]; then pa_info "$name ✓"; return 0; fi
  log=$(mktemp)
  if pa_bg "$log" "go: $name" env GOBIN="$PA_BIN" go install "$1"; then
    pa_info "$name installed"
    rm -f "$log"
  else
    pa_warn "go install failed: $1"
    pa_show_tail "$log"; rm -f "$log"
    return 1
  fi
}

# --- GitHub release binaries ---------------------------------------------------------
# pa_gh_release <owner/repo> <binary-name> <asset-regex>
# Downloads the newest release asset matching the regex and installs the binary.
# When the release publishes a checksums file, the download must match it.
# Callers pick the regex per arch: pa_is_arm64 && rx='linux.*(arm64|aarch64)'.
pa_gh_release() {
  local repo="$1" bin="$2" rx="$3" json url sums tmp f name want
  if [ "$PA_UPDATE" != 1 ] && [ -x "$PA_BIN/$bin" ]; then pa_info "$bin ✓"; return 0; fi
  json=$(curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
         "https://api.github.com/repos/$repo/releases/latest") || { pa_warn "$bin: GitHub API unavailable (rate limit?)"; return 1; }
  url=$(printf '%s' "$json" | jq -r --arg rx "$rx" '.assets[] | select(.name | test($rx; "i")) | .browser_download_url' | head -1)
  sums=$(printf '%s' "$json" | jq -r '.assets[] | select(.name | test("(checksums?|sha256sums?)(\\.txt)?$"; "i")) | .browser_download_url' | head -1)
  [ -n "$url" ] || { pa_warn "$bin: no release asset matched /$rx/ (no $PA_ARCH build?)"; return 1; }
  tmp=$(mktemp -d)
  pa_download "$url" "$tmp/asset" "download: $bin" || { rm -rf "$tmp"; return 1; }
  if [ -n "$sums" ]; then
    name=${url##*/}
    want=$(curl -fsSL "$sums" | awk -v n="$name" '{ f=$2; sub(/^\*/, "", f) } f == n { print $1; exit }')
    if [ -z "$want" ] || [ "$(pa_sha256 "$tmp/asset")" != "$want" ]; then
      pa_warn "$bin: download doesn't match the release's published checksum — not installed"
      rm -rf "$tmp"; return 1
    fi
  fi
  case "$url" in
    *.zip)            (cd "$tmp" && unzip -q asset) ;;
    *.tar.gz|*.tgz)   tar -C "$tmp" -xzf "$tmp/asset" ;;
    *)                mv "$tmp/asset" "$tmp/$bin" ;;
  esac
  f=$(find "$tmp" -type f -name "$bin" | head -1)
  [ -n "$f" ] || { pa_warn "$bin: binary not found in archive"; rm -rf "$tmp"; return 1; }
  install -m 755 "$f" "$PA_BIN/$bin"
  rm -rf "$tmp"
  pa_info "$bin installed"
}

# --- shell PATH ------------------------------------------------------------------------
pa_path_setup() {
  local rc line='export PATH="$HOME/.local/share/periapsis/bin:$HOME/.local/share/periapsis/go/bin:$HOME/.local/bin:$PATH"  # periapsis'
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    [ -f "$rc" ] || continue
    grep -q '# periapsis$' "$rc" || printf '\n%s\n' "$line" >> "$rc"
  done
}

# --- module registry (indexed arrays: no associative arrays in bash 3.2) ---------
PA_MOD_NAMES=(); PA_MOD_DESCS=(); PA_MOD_ARCHES=(); PA_MOD_FUNCS=()

# pa_register <name> <description> <arches: "amd64 arm64"> <function>
pa_register() {
  PA_MOD_NAMES+=("$1"); PA_MOD_DESCS+=("$2"); PA_MOD_ARCHES+=("$3"); PA_MOD_FUNCS+=("$4")
}

pa_mod_supported() {  # pa_mod_supported <arches-string>
  case " $1 " in *" $PA_ARCH "*) return 0 ;; esac
  return 1
}
