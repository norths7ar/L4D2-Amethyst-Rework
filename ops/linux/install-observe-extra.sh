#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[[ $EUID -eq 0 && $# -eq 0 ]] || { printf 'Usage: sudo bash ops/linux/install-observe-extra.sh\n' >&2; exit 1; }
source /etc/l4d2-restart.conf
CHECKOUT_ROOT=${CHECKOUT_ROOT:-/home/l4d2/integration}
CODE_OWNER=${CHECKOUT_OWNER:-$OWNER_USER}
[[ "$CODE_OWNER" != "$SERVICE_USER" ]] && id "$CODE_OWNER" >/dev/null 2>&1 || {
    printf "Checkout must be maintained by an account other than the game service.\n" >&2
    exit 1
}
[[ "$(realpath -- "$SCRIPT_DIR/../..")" == "$(realpath -- "$CHECKOUT_ROOT")" ]] || {
    printf 'install-observe-extra.sh: run from CHECKOUT_ROOT: %s\n' "$CHECKOUT_ROOT" >&2
    exit 1
}
chown root:"$SERVICE_GROUP" /home/l4d2
chown "$CODE_OWNER:$SERVICE_GROUP" "$CHECKOUT_ROOT"
chmod go-w /home/l4d2 "$CHECKOUT_ROOT"
chown -R "$CODE_OWNER" "$CHECKOUT_ROOT/.git"
chmod -R go-w "$CHECKOUT_ROOT/.git"
chown -R "$CODE_OWNER:$SERVICE_GROUP" "$CHECKOUT_ROOT/ops"
chmod -R u+rwX,g+rX,go-w "$CHECKOUT_ROOT/ops"
find "$CHECKOUT_ROOT/ops" -type d -exec chmod g+s {} +
install -d -o root -g root -m 0755 /usr/local/libexec/l4d2
ln -sfnT "$CHECKOUT_ROOT/ops/linux/libexec/host-observe-extra.py" /usr/local/libexec/l4d2/host-observe-extra.py
install -o root -g root -m 0644 "$SCRIPT_DIR/systemd/l4d2-observe-extra.service" /etc/systemd/system/l4d2-observe-extra.service
if [[ ! -e /etc/l4d2-observe-extra.json ]]; then
    install -o root -g root -m 0640 "$SCRIPT_DIR/l4d2-observe-extra.json.example" /etc/l4d2-observe-extra.json
fi
systemctl daemon-reload
printf 'Installed without starting services. Configure /etc/l4d2-observe-extra.json, then enable --now l4d2-observe-extra.service.\n'
