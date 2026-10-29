#!/usr/bin/env bash
# =============================================================================
#  periapsis installer
#  https://github.com/det0xgravity/periapsis
#
#  Builds a CTF workstation on Kali Linux or Parrot OS (amd64 or arm64).
#  Modular, idempotent and safe to re-run.
#
#  Usage:  ./install.sh [--list] [--only a,b] [--skip a,b] [--update] [--yes]
#  Run as your normal user. It asks for sudo only when needed.
# =============================================================================

set -uo pipefail

PA_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$PA_REPO/lib/common.sh"

usage() {
  cat <<EOF
periapsis $PA_VERSION

Usage: ./install.sh [options]

  --list           List modules and exit
  --only a,b,c     Install only these modules (core always runs)
  --skip a,b,c     Install everything except these modules
  --update         Upgrade tools that are already installed
  --yes            Don't ask for confirmation
  --version        Print the version and exit
  -h, --help       Show this help

Examples:
  ./install.sh                  # everything supported on this machine
  ./install.sh --only vm        # core plus the vm module
  ./install.sh --update --yes   # unattended upgrade (used by pa-update)
EOF
}

ONLY=""; SKIP=""; ASSUME_YES=0; LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --list)    LIST=1 ;;
    --only)    ONLY="${2:-}"; shift ;;
    --only=*)  ONLY="${1#*=}" ;;
    --skip)    SKIP="${2:-}"; shift ;;
    --skip=*)  SKIP="${1#*=}" ;;
    --update)  PA_UPDATE=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    --version)
      printf 'periapsis %s%s\n' "$PA_VERSION" "$(git -C "$PA_REPO" describe --always --dirty 2>/dev/null | sed 's/^/ (/; s/$/)/')"
      exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) pa_err "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done
export PA_UPDATE

# Load modules in filename order; each one calls pa_register.
for m in "$PA_REPO"/modules/*.sh; do
  # shellcheck disable=SC1090
  . "$m"
done

# --list works anywhere (CI, the Mac), so it runs before platform detection
if [ "$LIST" = 1 ]; then
  printf '%-12s %-14s %s\n' MODULE ARCHES DESCRIPTION
  i=0
  while [ $i -lt ${#PA_MOD_NAMES[@]} ]; do
    printf '%-12s %-14s %s\n' "${PA_MOD_NAMES[$i]}" "${PA_MOD_ARCHES[$i]}" "${PA_MOD_DESCS[$i]}"
    i=$((i+1))
  done
  exit 0
fi

pa_detect_platform

[ "$(id -u)" -eq 0 ] && pa_die "Run as your normal user, not root or sudo. You'll be asked for sudo when needed."

in_csv() { case ",$2," in *",$1,"*) return 0 ;; esac; return 1; }

is_module() {
  local m
  for m in "${PA_MOD_NAMES[@]}"; do [ "$m" = "$1" ] && return 0; done
  return 1
}

# Validate module names given to --only / --skip
for n in $(printf '%s' "$ONLY,$SKIP" | tr ',' ' '); do
  is_module "$n" || pa_die "Unknown module: $n (see --list)"
done

# The installer records the modules the user chose NOT to install. Updates run
# everything else, so modules added in a new release get installed too.
SKIPPED_FILE="$PA_CONF/skipped"
HAVE_STATE=0; SAVED_SKIP=""
if [ -f "$SKIPPED_FILE" ]; then
  HAVE_STATE=1
  for n in $(tr ',' ' ' < "$SKIPPED_FILE"); do
    is_module "$n" && SAVED_SKIP="${SAVED_SKIP:+$SAVED_SKIP,}$n"   # drop modules that no longer exist
  done
fi
if [ "$PA_UPDATE" = 1 ] && [ -z "$ONLY" ] && [ -z "$SKIP" ]; then
  SKIP="$SAVED_SKIP"
fi

# Build the run list
RUN_IDX=()
i=0
while [ $i -lt ${#PA_MOD_NAMES[@]} ]; do
  n="${PA_MOD_NAMES[$i]}"
  if pa_mod_supported "${PA_MOD_ARCHES[$i]}"; then
    if [ "$n" = "core" ]; then
      RUN_IDX+=("$i")
    elif [ -n "$ONLY" ]; then
      in_csv "$n" "$ONLY" && RUN_IDX+=("$i")
    elif ! in_csv "$n" "$SKIP"; then
      RUN_IDX+=("$i")
    fi
  fi
  i=$((i+1))
done

echo "${C_B}periapsis $PA_VERSION${C_0}"
echo "  Platform : $PA_PLATFORM ($PA_ARCH)${PA_DE:+, desktop: $PA_DE}"
echo "  Mode     : $([ "$PA_UPDATE" = 1 ] && echo update || echo install)"
printf '  Modules  :'
for i in "${RUN_IDX[@]}"; do printf ' %s' "${PA_MOD_NAMES[$i]}"; done
echo

if [ "$ASSUME_YES" != 1 ]; then
  printf '\nContinue? [Y/n] '
  read -r ans
  case "$ans" in [Nn]*) exit 0 ;; esac
fi

mkdir -p "$PA_CONF" "$PA_HOME" "$PA_DATA"
LOG="$PA_CONF/install.log"
# Status lines (lib/common.sh: pa_bg) are drawn on the terminal itself, fd 4,
# so they never clutter install.log
if [ -t 1 ]; then PA_TTY=1; exec 4>&1; fi
PA_LOG="$LOG"
PA_STEP_N=${#RUN_IDX[@]}
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date) — Periapsis $PA_VERSION on $PA_PLATFORM ($PA_ARCH) ==="

pa_sudo_keepalive

for i in "${RUN_IDX[@]}"; do
  pa_step "${PA_MOD_NAMES[$i]}: ${PA_MOD_DESCS[$i]}" "${PA_MOD_FUNCS[$i]}"
done

# Remember which modules the user chose not to install. A module counts as
# skipped when it didn't run and: this is the first install (--only/--skip
# picked the set), it was skipped before, or --skip named it outside an update.
new_skip=""
i=0
while [ $i -lt ${#PA_MOD_NAMES[@]} ]; do
  n="${PA_MOD_NAMES[$i]}"
  ran=0
  for j in "${RUN_IDX[@]}"; do [ "$j" = "$i" ] && ran=1; done
  if [ $ran = 0 ] && [ "$n" != core ] && pa_mod_supported "${PA_MOD_ARCHES[$i]}"; then
    if [ $HAVE_STATE = 0 ] || in_csv "$n" "$SAVED_SKIP" \
       || { [ "$PA_UPDATE" != 1 ] && in_csv "$n" "$SKIP"; }; then
      new_skip="${new_skip:+$new_skip,}$n"
    fi
  fi
  i=$((i+1))
done
printf '%s\n' "$new_skip" > "$SKIPPED_FILE"

echo
echo "============================================================"
if [ ${#PA_FAILED[@]} -eq 0 ]; then
  echo " ${C_G}All modules completed.${C_0}"
else
  echo " ${C_Y}Completed with problems in:${C_0}"
  for f in "${PA_FAILED[@]}"; do echo "   - $f"; done
  echo " Full log: $LOG"
  echo " Re-running is safe; pa-doctor shows what is missing."
fi
echo
echo " Open a new terminal (to pick up PATH), then run:  periapsis"
echo " Check the install any time with:                  pa-doctor"
echo "============================================================"
[ ${#PA_FAILED[@]} -eq 0 ]
