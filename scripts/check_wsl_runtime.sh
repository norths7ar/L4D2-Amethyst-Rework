#!/usr/bin/env bash
set -u

echo 'Process:'
pgrep -af 'srcds_(run|linux)' || true

echo 'Port 27015:'
ss -lunpt 2>/dev/null | grep '27015' || true

echo 'Server log tail:'
tail -n 100 /home/l4d2/logs/srcds.log 2>/dev/null || true

echo 'SourceMod error log tail:'
find /home/l4d2/server/left4dead2/addons/sourcemod/logs \
    -maxdepth 1 \
    -type f \
    -name 'errors_*.log' \
    -print0 2>/dev/null |
    xargs -0 -r tail -n 80
