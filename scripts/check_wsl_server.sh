#!/usr/bin/env bash
set -u

printf 'OS: '
grep '^PRETTY_NAME=' /etc/os-release || true

printf 'Server binary: '
if [[ -x /home/l4d2/server/srcds_linux ]]; then
    echo 'OK'
else
    echo 'MISSING'
fi

printf 'Integration copy: '
if [[ -f /home/l4d2/integration/ASTMOD_INTEGRATION.md ]]; then
    echo 'OK'
else
    echo 'MISSING'
fi

printf 'Deployed matchmodes: '
if [[ -f /home/l4d2/server/left4dead2/addons/sourcemod/configs/matchmodes.txt ]]; then
    echo 'OK'
else
    echo 'MISSING'
fi

echo 'Running process:'
pgrep -af srcds || true

echo 'Port 27015:'
ss -lntup 2>/dev/null | grep '27015' || true

echo 'Disk usage:'
du -sh /home/l4d2/server /home/l4d2/integration 2>/dev/null || true
