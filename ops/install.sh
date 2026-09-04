#!/usr/bin/env bash
set -Eeuo pipefail
umask 0022

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_PATH=/etc/l4d2-restart.conf
LIBEXEC_DIR=/usr/local/libexec/l4d2

[[ $# -eq 0 ]] || {
    printf 'Usage: sudo ./ops/install.sh\n' >&2
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
id ecs-user >/dev/null 2>&1 || {
    printf 'install.sh: owner account ecs-user does not exist\n' >&2
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
assert_owned_unit /etc/systemd/system/l4d2-observe.service

install -d -o root -g root -m 0755 "$LIBEXEC_DIR"
install -o root -g root -m 0755 "$SCRIPT_DIR/l4d2-restart-now" \
    /usr/local/sbin/l4d2-restart-now
install -o root -g root -m 0755 "$SCRIPT_DIR/l4d2-content-apply" \
    /usr/local/sbin/l4d2-content-apply
install -o root -g root -m 0755 "$SCRIPT_DIR/l4d2-update-and-restart" \
    /usr/local/sbin/l4d2-update-and-restart
install -o root -g root -m 0755 "$SCRIPT_DIR/libexec/l4d2-console" \
    "$LIBEXEC_DIR/l4d2-console"
install -o root -g root -m 0755 "$SCRIPT_DIR/libexec/l4d2-run" \
    "$LIBEXEC_DIR/l4d2-run"
install -o root -g root -m 0755 "$SCRIPT_DIR/libexec/l4d2-observe" \
    "$LIBEXEC_DIR/l4d2-observe"
install -o root -g root -m 0755 "$SCRIPT_DIR/libexec/vpk_campaigns.py" \
    "$LIBEXEC_DIR/vpk_campaigns.py"
if [[ ! -e "$CONFIG_PATH" ]]; then
    install -o root -g l4d2 -m 0640 "$SCRIPT_DIR/l4d2-restart.conf.example" \
        "$CONFIG_PATH"
fi

# shellcheck source=/dev/null
source "$CONFIG_PATH"
chown root:"$SERVICE_GROUP" "$CONFIG_PATH"
chmod 0640 "$CONFIG_PATH"

if [[ ${SRCDS_DEBUG:-1} == 1 ]] && ! command -v gdb >/dev/null 2>&1; then
    printf 'install.sh: SRCDS_DEBUG=1 requires gdb; install it or set SRCDS_DEBUG=0\n' >&2
    exit 1
fi

# The SSH/SFTP owner and the game process intentionally share the whole install.
usermod -a -G "$SERVICE_GROUP" "$OWNER_USER"
chown "$OWNER_USER:$SERVICE_GROUP" "$SERVER_ROOT" "$GAME_DIR"
chmod 2775 "$SERVER_ROOT" "$GAME_DIR"
chmod 0750 /home/l4d2

install -o root -g root -m 0644 "$SCRIPT_DIR/systemd/l4d2.service" \
    /etc/systemd/system/l4d2.service
install -o root -g root -m 0644 "$SCRIPT_DIR/systemd/l4d2-observe.service" \
    /etc/systemd/system/l4d2-observe.service

systemctl daemon-reload
systemctl enable l4d2.service
systemctl enable l4d2-observe.service

printf 'Installed direct-owner L4D2 operations with explicit content apply.\n'
printf 'The update helper requires git, rsync, flock, and sudo on the host.\n'
printf 'Reconnect SSH/SFTP once so ecs-user receives the l4d2 group.\n'
