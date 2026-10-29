# shellcheck shell=bash
# core — base packages, Python/Go toolchains, the Periapsis runtime and menus.
# Always runs; every other module depends on it.

pa_register core "Base packages, pipx, Go, Periapsis runtime" "amd64 arm64" mod_core

mod_core() {
  local rc=0 t

  pa_apt git curl wget jq unzip p7zip-full ca-certificates file xxd \
         python3 python3-venv python3-pip pipx golang-go build-essential \
         zenity xclip wl-clipboard libnotify-bin xdg-utils || rc=1

  pipx ensurepath >/dev/null 2>&1 || true
  if [ "$PA_UPDATE" = 1 ]; then
    pa_info "Upgrading system packages and pipx-managed tools…"
    pa_apt_update && pa_bg "$PA_LOG" "apt: upgrade" sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q upgrade \
      || pa_warn "apt upgrade had problems (see the log)"
    pipx upgrade-all >/dev/null 2>&1 || pa_warn "some pipx upgrades failed"
  fi
  pa_go_ensure || { pa_warn "Go toolchain unavailable — Go-based tools will be skipped"; rc=1; }

  # Runtime: shared UI library, engine and menu tools
  mkdir -p "$PA_BIN" "$PA_HOME/lib" "$PA_CONF" "$HOME/.local/bin"
  install -m 644 "$PA_REPO/lib/ui.sh" "$PA_HOME/lib/ui.sh"
  # Engines run as commands, so audit.log shows "pa_event …"
  install -m 755 "$PA_REPO/lib/pa_event.py" "$PA_BIN/pa_event"
  for t in "$PA_REPO"/tools/*; do
    install -m 755 "$t" "$PA_BIN/$(basename "$t")"
    ln -sf "$PA_BIN/$(basename "$t")" "$HOME/.local/bin/$(basename "$t")"
  done

  printf '%s\n' "$PA_REPO" > "$PA_CONF/repo_path"
  printf '%s\n' "$PA_VERSION" > "$PA_HOME/VERSION"

  # A standing "scratch" event for practice and one-off challenges, so there's
  # always somewhere for work to go
  ( umask 077; mkdir -p "$PA_DATA/Events" ); chmod 700 "$PA_DATA" "$PA_DATA/Events"
  [ -f "$PA_DATA/Events/scratch/event.json" ] \
    || PA_DATA="$PA_DATA" "$PA_BIN/pa_event" new scratch --platform practice >/dev/null || rc=1
  [ -s "$PA_CONF/active_event" ] || echo scratch > "$PA_CONF/active_event"

  pa_path_setup
  pa_info "Runtime installed to $PA_HOME"
  return $rc
}
