#!/usr/bin/env bash
set -Eeuo pipefail
umask 0022

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_PATH=/etc/l4d2-restart.conf
LIBEXEC_DIR=/usr/local/libexec/l4d2

[[ $# -eq 0 ]] || {
    printf 'Usage: sudo ./ops/linux/install.sh\n' >&2
    exit 2
}
[[ $EUID -eq 0 ]] || {
    printf 'install.sh: run through sudo\n' >&2
    exit 1
}
id l4d2 >/dev/null 2>&1 || {
    printf 'install.sh: service account l4d2 does not exist\n' >&2
    exit 1
}

assert_owned_unit() {
    local path=$1
    if [[ -e "$path" ]] \
        && ! grep -Fq '# Managed by L4D2-Amethyst-Rework ops/install.sh' "$path"; then
        printf 'install.sh: refusing to overwrite unowned unit %s\n' "$path" >&2
        exit 1
    fi
}

assert_owned_unit /etc/systemd/system/l4d2.service

if [[ ! -e "$CONFIG_PATH" ]]; then
    install -o root -g l4d2 -m 0640 "$SCRIPT_DIR/l4d2-restart.conf.example" \
        "$CONFIG_PATH"
fi

# shellcheck source=/dev/null
source "$CONFIG_PATH"
CHECKOUT_ROOT=${CHECKOUT_ROOT:-/home/l4d2/integration}
CODE_OWNER=${CHECKOUT_OWNER:-$OWNER_USER}
[[ "$CODE_OWNER" != "$SERVICE_USER" ]] && id "$CODE_OWNER" >/dev/null 2>&1 || {
    printf "Checkout must be maintained by an account other than the game service.\n" >&2
    exit 1
}
[[ "$(realpath -- "$SCRIPT_DIR/../..")" == "$(realpath -- "$CHECKOUT_ROOT")" ]] || {
    printf 'install.sh: run from the configured CHECKOUT_ROOT: %s\n' "$CHECKOUT_ROOT" >&2
    exit 1
}
# Root entry points must not execute game-user-writable code.
chown root:"$SERVICE_GROUP" /home/l4d2
chown "$CODE_OWNER:$SERVICE_GROUP" "$CHECKOUT_ROOT"
chmod go-w /home/l4d2 "$CHECKOUT_ROOT"
chown -R "$CODE_OWNER" "$CHECKOUT_ROOT/.git"
chmod -R go-w "$CHECKOUT_ROOT/.git"
chown -R "$CODE_OWNER:$SERVICE_GROUP" "$CHECKOUT_ROOT/ops"
chmod -R u+rwX,g+rX,go-w "$CHECKOUT_ROOT/ops"
find "$CHECKOUT_ROOT/ops" -type d -exec chmod g+s {} +
install -d -o root -g root -m 0755 "$LIBEXEC_DIR"
install_entry() {
    local target=$1 relative=$2 interpreter=$3
    printf '#!/usr/bin/env bash\nexec %q %q "$@"\n' "$interpreter" "$CHECKOUT_ROOT/ops/linux/$relative" > "$target"
    chown root:root "$target"
    chmod 0755 "$target"
}
for command in l4d2-restart-now l4d2-content-apply l4d2-update-and-restart; do
    install_entry "/usr/local/sbin/$command" "$command" /bin/bash
done
for command in l4d2-console l4d2-run; do
    install_entry "$LIBEXEC_DIR/$command" "libexec/$command" /bin/bash
done
for command in vpk_campaigns.py map_rules_merge.py; do
    install_entry "$LIBEXEC_DIR/$command" "libexec/$command" /usr/bin/python3
done
id "$OWNER_USER" >/dev/null 2>&1 || {
    printf 'install.sh: owner account %s does not exist\n' "$OWNER_USER" >&2
    exit 1
}
chown root:"$SERVICE_GROUP" "$CONFIG_PATH"
chmod 0640 "$CONFIG_PATH"

if [[ ${SRCDS_DEBUG:-1} == 1 ]] && ! command -v gdb >/dev/null 2>&1; then
    printf 'install.sh: SRCDS_DEBUG=1 requires gdb; install it or set SRCDS_DEBUG=0\n' >&2
    exit 1
fi

# Root maintains files; the game keeps its existing runtime write access.
chown "$OWNER_USER:$SERVICE_GROUP" "$SERVER_ROOT" "$GAME_DIR"
chmod 2775 "$SERVER_ROOT" "$GAME_DIR"
chmod 0750 /home/l4d2

install -o root -g root -m 0644 "$SCRIPT_DIR/systemd/l4d2.service" \
    /etc/systemd/system/l4d2.service

systemctl daemon-reload
systemctl enable l4d2.service

printf 'Installed direct-owner L4D2 operations with explicit content apply.\n'
printf 'The update helper requires git, rsync, flock, and sudo on the host.\n'
printf 'Upload VPKs with read access (normally 0644); content apply also grants VPK read access.\n'
