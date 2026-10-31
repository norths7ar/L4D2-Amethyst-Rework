#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[[ $EUID -eq 0 && $# -eq 0 ]] || { printf 'Usage: sudo bash ops/linux/install-observe-extra.sh\n' >&2; exit 1; }
install -d -o root -g root -m 0755 /usr/local/libexec/l4d2
install -o root -g root -m 0755 "$SCRIPT_DIR/libexec/host-observe-extra.py" /usr/local/libexec/l4d2/host-observe-extra.py
install -o root -g root -m 0644 "$SCRIPT_DIR/systemd/l4d2-observe-extra.service" /etc/systemd/system/l4d2-observe-extra.service
if [[ ! -e /etc/l4d2-observe-extra.json ]]; then
    install -o root -g root -m 0640 "$SCRIPT_DIR/l4d2-observe-extra.json.example" /etc/l4d2-observe-extra.json
fi
systemctl daemon-reload
printf 'Installed without starting services. Configure /etc/l4d2-observe-extra.json, then enable --now l4d2-observe-extra.service.\n'
