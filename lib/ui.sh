# shellcheck shell=bash
# =============================================================================
#  periapsis — runtime library for the menu tools
#  Dialogs use zenity. Bash 3.2 compatible, like the installer.
# =============================================================================

PA_HOME="${PA_HOME:-$HOME/.local/share/periapsis}"
PA_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/periapsis"
PA_DATA="${PA_DATA:-$HOME/Periapsis}"
PA_TITLE="Periapsis"
export PATH="$PA_HOME/bin:$PA_HOME/go/bin:$HOME/.local/bin:$HOME/go/bin:$PATH"

pa_cmd() { command -v "$1" >/dev/null 2>&1; }

# --- dialogs -------------------------------------------------------------------
# ui_list "Prompt" "Option 1" "Option 2" ...   -> prints the chosen option
ui_list() {
  local prompt="$1" r h; shift
  h=$((170 + 30 * $#)); [ $h -gt 640 ] && h=640
  r=$(zenity --list --title="$PA_TITLE" --text="$prompt" --column="Option" \
        --width=560 --height=$h "$@" 2>/dev/null) || return 1
  [ -n "$r" ] || return 1
  printf '%s\n' "$r"
}

# ui_entry "Prompt" ["default"]   -> prints the text entered (fails on cancel/empty;
#                                    with PA_ALLOW_EMPTY=1 only cancel fails)
ui_entry() {
  local r
  r=$(zenity --entry --title="$PA_TITLE" --width=460 --text="$1" --entry-text="${2:-}" 2>/dev/null) || return 1
  r=$(printf '%s' "$r" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  [ -n "$r" ] || [ -n "${PA_ALLOW_EMPTY:-}" ] || return 1
  printf '%s\n' "$r"
}

ui_info()  { zenity --info  --no-markup --title="$PA_TITLE" --width=480 --text="$1" 2>/dev/null; }
ui_error() { zenity --error --no-markup --title="$PA_TITLE" --width=440 --text="$1" 2>/dev/null; }
ui_question() {   # returns 0 for Yes
  zenity --question --no-markup --title="$PA_TITLE" --width=440 --text="$1" 2>/dev/null
}

# ui_text "Title" <file>   a read-only scrollable text window
ui_text() {
  zenity --text-info --title="$PA_TITLE — $1" --width=760 --height=520 \
    --font=monospace --filename="$2" 2>/dev/null
  return 0
}

# --- browser, clipboard, files -------------------------------------------------------
# _ui_detach CMD...  Starts a GUI program in its own session, so it survives
# the menu's terminal closing (which would otherwise kill it with SIGHUP).
_ui_detach() {
  setsid -f "$@" >/dev/null 2>&1 </dev/null
}

ui_open() {
  local u
  for u in "$@"; do _ui_detach xdg-open "$u"; done
}

# Clipboard helpers can block when nothing takes the selection, so cap each
# attempt at 3 seconds. xclip works under X11 (Kali/Parrot default) and XWayland.
ui_clip() {
  if [ -n "${DISPLAY:-}" ] && pa_cmd xclip; then
    printf '%s' "$1" | timeout 3 xclip -selection clipboard >/dev/null 2>&1
  elif [ -n "${WAYLAND_DISPLAY:-}" ] && pa_cmd wl-copy; then
    printf '%s' "$1" | timeout 3 wl-copy >/dev/null 2>&1
  fi
  return 0
}

ui_notify() {
  pa_cmd notify-send && notify-send -a "$PA_TITLE" "$PA_TITLE" "$1" >/dev/null 2>&1
  return 0
}

ui_reveal() { _ui_detach xdg-open "$1"; }

# --- helpers ---------------------------------------------------------------------
pa_slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-' | sed 's/--*/-/g; s/^-//; s/-$//' | cut -c1-60; }

# --- events & audit trail --------------------------------------------------------------
# Each CTF lives in ~/Periapsis/Events/<event>/ with its challenges, notes and an
# audit.log of every command run through Periapsis.
pa_cur_event() {
  local e
  e=$(cat "$PA_CONF/active_event" 2>/dev/null)
  printf '%s\n' "${e:-scratch}"
}

# Event folders are private (700): challenge files and flags stay yours
pa_cur_dir() {
  local d
  d="$PA_DATA/Events/$(pa_cur_event)"
  ( umask 077; mkdir -p "$d" )
  chmod 700 "$PA_DATA" "$PA_DATA/Events" "$d" 2>/dev/null
  printf '%s\n' "$d"
}

pa_set_event() {
  ( umask 077; mkdir -p "$PA_CONF" )
  pa_slug "$1" > "$PA_CONF/active_event"
}

pa_hash_str() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }

_pa_field() { printf '%s' "$1" | tr '\t\n\r' '   '; }      # one TSV field: no tabs/newlines

# pa_audit <tool> <target> <detail>
# Appends: UTC time, event, tool, target, detail, operator, chain hash. The hash
# is SHA-256(previous line + this line's other fields), so editing, inserting or
# deleting a line breaks every hash after it (pa_event audit-verify checks it).
# lib/pa_event.py writes the same format: keep the two in step.
pa_audit() {
  local log body prev
  log="$(pa_cur_dir)/audit.log"
  body=$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(pa_cur_event)" \
    "$(_pa_field "$1")" "$(_pa_field "$2")" "$(_pa_field "$3")" "$(id -un)")
  prev=""
  [ -s "$log" ] && prev=$(tail -n 1 "$log")
  printf '%s\t%s\n' "$body" "$(pa_hash_str "$prev$body")" >> "$log"
}

# pa_run <dir> <command> [args...]
# Runs a command inside <dir>, echoes it, logs it and keeps the console output.
pa_run() {
  local out="$1"; shift
  if ! pa_cmd "$1"; then
    printf '  [skip] %s is not installed\n' "$1" | tee -a "$out/console.log"
    return 127
  fi
  printf '\n\033[1m▶ %s\033[0m\n' "$*"
  printf '▶ %s\n' "$*" >> "$out/console.log"
  pa_audit "$1" "$(basename "$out")" "$*"
  ( cd "$out" && "$@" ) 2>&1 | tee -a "$out/console.log"
  return "${PIPESTATUS[0]}"
}

# pa_pause — keeps a terminal opened by a launcher on screen until Enter
pa_pause() {
  [ "${PA_FROM_MAIN:-0}" = 1 ] && return 0
  [ -t 0 ] || return 0
  printf '\nPress Enter to close… '
  read -r _
}

# --- scripted dialogs (tests and CI) ---------------------------------------------------
# PA_UI=script PA_UI_ANSWERS=<file>: every dialog takes the next line of the file
# (an empty line cancels; "<default>" accepts an entry's pre-filled value)
# instead of asking. ui_list picks the first option starting with that line;
# ui_question takes y/yes as yes; a missing line cancels. Browser, clipboard,
# notification and folder actions are logged to stderr and not performed.
if [ "${PA_UI:-}" = script ]; then
  _ui_next() {
    local n line
    n=$(cat "$PA_UI_ANSWERS.pos" 2>/dev/null || echo 1)
    line=$(sed -n "${n}p" "$PA_UI_ANSWERS")
    echo $((n + 1)) > "$PA_UI_ANSWERS.pos"
    [ -n "$line" ] || return 1
    printf '%s\n' "$line"
  }
  ui_list() {
    local want o; shift
    want=$(_ui_next) || return 1
    for o in "$@"; do case "$o" in "$want"*) printf '%s\n' "$o"; return 0 ;; esac; done
    return 1
  }
  ui_entry()    { local a; a=$(_ui_next) || return 1; [ "$a" = "<default>" ] && a="${2:-}"; [ "$a" = "<empty>" ] && a=""; printf '%s\n' "$a"; }
  ui_question() { case "$(_ui_next)" in y|Y|yes|Yes) return 0 ;; esac; return 1; }
  ui_info()     { printf '[ui_info] %s\n' "$1" >&2; }
  ui_error()    { printf '[ui_error] %s\n' "$1" >&2; }
  ui_text()     { printf '[ui_text] %s\n' "$1" >&2; cat "$2" >&2; }
  ui_open()     { printf '[ui_open] %s\n' "$@" >&2; }
  ui_clip()     { printf '[ui_clip] %s\n' "$1" >&2; }
  ui_notify()   { printf '[ui_notify] %s\n' "$1" >&2; }
  ui_reveal()   { printf '[ui_reveal] %s\n' "$1" >&2; }
fi
