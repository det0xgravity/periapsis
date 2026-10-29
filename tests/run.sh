#!/usr/bin/env bash
# tests/run.sh — offline functional tests for periapsis.
# No network, no sudo, nothing installed: everything happens in a temporary
# folder, with menus driven by PA_UI=script.
# Usage: bash tests/run.sh

R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"
         [ -n "${CI:-}" ] && [ -f "$W/out.txt" ] && sed 's/^/        | /' "$W/out.txt" | tail -15; return 0; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "$2"; fi; }
section() { printf '\n== %s\n' "$1"; }

# A throwaway Periapsis home with the engine and tools on PATH, and scripted dialogs
H="$W/home"; mkdir -p "$H/lib" "$H/bin"
cp "$R/lib/ui.sh" "$H/lib/"
ln -s "$R/lib/pa_event.py" "$H/bin/pa_event"
for t in "$R"/tools/*; do ln -s "$t" "$H/bin/$(basename "$t")"; done
mkdir -p "$W/userhome"
export HOME="$W/userhome" PA_HOME="$H" PA_DATA="$W/data" XDG_CONFIG_HOME="$W/xdg" \
       PA_UI=script PA_UI_ANSWERS="$W/answers" PATH="$H/bin:$PATH"
answers() { printf '%s\n' "$@" > "$PA_UI_ANSWERS"; rm -f "$PA_UI_ANSWERS.pos"; }
menu() { local t="$1"; shift; answers "$@"; bash "$R/tools/$t" < /dev/null > "$W/out.txt" 2>&1; }
EV="$W/data/Events"

section "Installer"
check "--list shows core and vm" "bash '$R/install.sh' --list | grep -q '^core ' && bash '$R/install.sh' --list | grep -q '^vm '"
check "--version prints the version" "bash '$R/install.sh' --version | grep -q '^periapsis [0-9]'"

section "Events (CLI)"
pa-event new "Test CTF 2027" --platform CTFd --flag-format 'flag\{[^}]+\}' > "$W/out.txt" 2>&1
check "new event created" "[ -f '$EV/test-ctf-2027/event.json' ]"
check "new event becomes active" "[ \"\$(pa-event current)\" = test-ctf-2027 ]"
check "event folders are private (700)" "[ \"\$(stat -c %a '$EV/test-ctf-2027' 2>/dev/null || stat -f %Lp '$EV/test-ctf-2027')\" = 700 ]"
check "duplicate event refused" "! pa_event new 'Test CTF 2027' 2>/dev/null"
check "bad flag regex refused" "! pa_event new 'Other' --flag-format 'flag{(' 2>/dev/null"
check "unknown event can't be used" "! pa-event use nope 2>/dev/null"

section "Challenges (CLI)"
d=$(pa-chal add web "Cookie Monster" --points 100)
check "challenge folder created" "[ -d '$d/files' ] && [ -d '$d/solve' ] && [ -f '$d/notes.md' ]"
check "adding again returns the same folder" "[ \"\$(pa-chal add web 'Cookie Monster')\" = '$d' ]"
pa-chal add pwn "Baby ROP" --points 200 > /dev/null
check "path by unique name" "[ \"\$(pa-chal path 'Cookie Monster')\" = '$d' ]"
check "path by category/slug" "[ \"\$(pa-chal path web/cookie-monster)\" = '$d' ]"
pa-chal flag cookie-monster 'wrong{x}' > "$W/out.txt" 2>&1; rc=$?
check "flag in the wrong format is rejected (exit 2)" "[ $rc = 2 ]"
check "rejected flag isn't recorded" "! grep -q 'wrong' '$d/challenge.json'"
check "matching flag recorded" "pa-chal flag cookie-monster 'flag{c00kies}' > /dev/null && grep -q '\"status\": \"solved\"' '$d/challenge.json'"
check "--force records an odd flag" "pa-chal flag baby-rop 'FLAG-odd' --force > /dev/null"
check "audit log never holds the flag" "! grep -q 'c00kies' '$EV/test-ctf-2027/audit.log'"
check "board shows progress" "pa-event board | grep -q 'Solved 2/2 · 300 points'"

section "Writeup"
w=$(pa-event writeup)
check "writeup built" "[ -f '$w' ] && grep -q '## Cookie Monster' '$w'"
check "live event gets the don't-publish banner" "grep -q 'Event still live' '$w'"
check "flags left out by default" "! grep -q 'c00kies' '$w'"
pa-event writeup --flags > /dev/null
check "--flags includes them" "grep -q 'flag{c00kies}' '$w'"
pa-event finish > /dev/null
pa-event writeup > /dev/null
check "finished event: no banner" "! grep -q 'Event still live' '$w'"

section "Audit chain"
LOG="$EV/test-ctf-2027/audit.log"
check "chain written by Python verifies" "pa_event audit-verify '$LOG' > /dev/null"
# Bash (lib/ui.sh) and Python must write the same chain
( . "$H/lib/ui.sh"; pa_audit testtool target "detail with	tab" )
pa_event audit test-ctf-2027 pytool target2 detail2
check "mixed Bash and Python lines verify" "pa_event audit-verify '$LOG' > /dev/null"
cp "$LOG" "$W/audit.bak"
sed 's/testtool/TESTTOOL/' "$W/audit.bak" > "$LOG"
check "an edited line is detected" "! pa_event audit-verify '$LOG' > /dev/null"
sed '2d' "$W/audit.bak" > "$LOG"
check "a deleted line is detected" "! pa_event audit-verify '$LOG' > /dev/null"
cp "$W/audit.bak" "$LOG"

section "Menus (scripted)"
menu pa-event "New event" "Menu CTF" "<empty>" "<empty>"
check "menu creates an event" "[ -f '$EV/menu-ctf/event.json' ] && [ \"\$(pa-event current)\" = menu-ctf ]"
menu pa-chal "Add a challenge" "crypto" "RSA Warmup" "50" "n"
check "menu adds a challenge" "[ -f '$EV/menu-ctf/crypto/rsa-warmup/challenge.json' ]"
menu pa-chal "Record a flag" "crypto/rsa-warmup" "anything{1}"
check "menu records a flag (no format set)" "grep -q 'anything{1}' '$EV/menu-ctf/crypto/rsa-warmup/challenge.json'"
menu pa-event "Switch event" "test-ctf-2027"
check "menu switches events" "[ \"\$(pa-event current)\" = test-ctf-2027 ]"
check "pa-chal without an event fails cleanly" "echo nope > '$XDG_CONFIG_HOME/periapsis/active_event' && ! pa-chal list 2>/dev/null"

section "pa-x86"
# Minimal ELF headers: enough for file(1) to name the machine (0x3e x86-64, 0x03 i386)
elf64() { printf '\177ELF\002\001\001\000\000\000\000\000\000\000\000\000\002\000\076\000\001\000\000\000' > "$1"; head -c 40 /dev/zero >> "$1"; }
elf32() { printf '\177ELF\001\001\001\000\000\000\000\000\000\000\000\000\002\000\003\000\001\000\000\000' > "$1"; head -c 28 /dev/zero >> "$1"; }
elf64 "$W/chall64"; elf32 "$W/chall32"; echo 'not a binary' > "$W/notes.txt"
check "x86_64 handout recognised" "pa-x86 check '$W/chall64' 2>&1 | grep -q 'x86-64'"
check "i386 handout recognised" "pa-x86 check '$W/chall32' 2>&1 | grep -q '80386'"
check "a non-ELF file is refused" "! pa-x86 check '$W/notes.txt' > /dev/null 2>&1"
check "run refuses a file without +x" "pa-x86 run '$W/chall64' 2>&1 | grep -q 'chmod +x'"
check "unknown subcommand fails" "! pa-x86 frobnicate 2>/dev/null"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
