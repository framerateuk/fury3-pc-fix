#!/bin/bash
# Fury3 (Terminal Reality / Microsoft, 1995) Steam Deck / Proton launch wrapper.
#
# Keep it beside game/ (build.py puts it there). With the folder at /home/deck/Games/Fury3:
#   Shortcut target: /home/deck/Games/Fury3/game/FURY3.EXE, Start In: .../game/
#   Steam > Fury3 > Properties > Launch Options:
#     /home/deck/Games/Fury3/fury3_launch.sh %command%
#
# FURY3.EXE is the disc's FURY3\FURY3.EXE patched (patch_exe.py): full screen (the 320x200 picture 4:3 with black bars
# through GDI), the pad through XInput as the game's joystick, at most 60 frames a second, no busy waits, no pointer,
# no menu bar. It reads everything from its own folder (it makes it the current one): SYSTEM\FURY3.INI (settings),
# SYSTEM\*.POD (data), SYSTEM\STORY\*.AVI (movies, Cinepak through Wine's MCI), and writes data\ (saved games, scores).
# No DLL overrides: no wrapper (GDI, Wine's own), no CD music (the game plays MOD music from its data).
# The script only logs (launch.log), and switches on Proton's own log when a file PROTON_LOG sits beside it.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$HERE/launch.log"
log() { echo "[$(date '+%H:%M:%S')] $*" >>"$LOG"; }
: >"$LOG"
log "args: $*"
log "cwd: $(pwd)"
log "STEAM_COMPAT_DATA_PATH=${STEAM_COMPAT_DATA_PATH:-unset}"

# Debugging: if a file named PROTON_LOG exists beside this script, Proton writes steam-<appid>.log here. A file
# WINEDEBUG beside it adds Wine debug channels (e.g. +mci,+mciavi,+xinput,+seh). Create / delete them from Desktop Mode.
if [ -e "$HERE/PROTON_LOG" ]; then
  export PROTON_LOG=1 PROTON_LOG_DIR="$HERE"
  log "PROTON_LOG on -> $HERE/steam-*.log"
  if [ -s "$HERE/WINEDEBUG" ]; then
    export WINEDEBUG="+timestamp,+tid,+seh,+loaddll,$(tr -d ' \n' < "$HERE/WINEDEBUG")"
    log "WINEDEBUG=$WINEDEBUG"
  fi
fi

for f in FURY3.EXE SYSTEM/FURY3.INI SYSTEM/FURY3.POD SYSTEM/STARTUP.POD SYSTEM/STORY/FURY.AVI; do
  [ -e "$HERE/game/$f" ] || log "WARNING: game/$f missing"
done

# Testing another Proton without touching Steam's settings: a file PROTON_VERSION beside this script holding a folder
# name from steamapps/common (e.g. "Proton 11.0") replaces the Proton in Steam's command line.
if [ -s "$HERE/PROTON_VERSION" ]; then
  want="$(head -1 "$HERE/PROTON_VERSION")"; args=()
  for a in "$@"; do
    case "$a" in */steamapps/common/*/proton) a="${a%/steamapps/common/*}/steamapps/common/$want/proton";; esac
    args+=("$a")
  done
  set -- "${args[@]}"
  log "PROTON_VERSION=$want"
fi

log "exec: $*"
exec "$@"
