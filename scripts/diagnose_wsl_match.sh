#!/usr/bin/env bash
set -u

echo 'Relevant server log entries:'
grep -nE \
    'sm_forcematch|Confogl|Match|match config|pred_|versus_coop_mode|Unknown command' \
    /home/l4d2/logs/srcds.log 2>/dev/null |
    tail -n 180 || true

echo 'SourceMod errors:'
find /home/l4d2/server/left4dead2/addons/sourcemod/logs \
    -maxdepth 1 \
    -type f \
    -name 'errors_*.log' \
    -print0 2>/dev/null |
    xargs -0 -r tail -n 160
