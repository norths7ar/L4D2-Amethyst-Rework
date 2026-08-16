#!/usr/bin/env bash
set -euo pipefail

install -d /home/l4d2/logs

if tmux has-session -t l4d2test 2>/dev/null; then
    echo 'The l4d2test tmux session is already running.'
    exit 0
fi

tmux new-session -d -s l4d2test \
    'bash /home/l4d2/integration/scripts/run_wsl_test.sh > /home/l4d2/logs/srcds.log 2>&1'

echo 'Started l4d2test in tmux.'
