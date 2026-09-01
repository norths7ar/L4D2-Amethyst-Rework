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

for unit in \
    /etc/systemd/system/l4d2.service \
    /etc/systemd/system/l4d2-maintenance.service \
    /etc/systemd/system/l4d2-maintenance.timer \
    /etc/systemd/system/l4d2-content-watch.service \
    /etc/systemd/system/l4d2-content-watch.timer; do
    assert_owned_unit "$unit"
done

# Stop the old desired-state publisher before changing any installed files.
systemctl disable --now l4d2-maintenance.timer 2>/dev/null || true
systemctl stop l4d2-maintenance.service 2>/dev/null || true

install -d -o root -g root -m 0755 "$LIBEXEC_DIR"
install -o root -g root -m 0755 "$SCRIPT_DIR/l4d2-restart-now" \
    /usr/local/sbin/l4d2-restart-now
install -o root -g root -m 0755 "$SCRIPT_DIR/l4d2-restart-if-needed" \
    /usr/local/sbin/l4d2-restart-if-needed
install -o root -g root -m 0755 "$SCRIPT_DIR/libexec/l4d2-console" \
    "$LIBEXEC_DIR/l4d2-console"
install -o root -g root -m 0755 "$SCRIPT_DIR/libexec/l4d2-run" \
    "$LIBEXEC_DIR/l4d2-run"
if [[ ! -e "$CONFIG_PATH" ]]; then
    install -o root -g l4d2 -m 0640 "$SCRIPT_DIR/l4d2-restart.conf.example" \
        "$CONFIG_PATH"
fi

# shellcheck source=/dev/null
source "$CONFIG_PATH"
chown root:"$SERVICE_GROUP" "$CONFIG_PATH"
chmod 0640 "$CONFIG_PATH"
install -d -o root -g "$SERVICE_GROUP" -m 2770 "$STATE_DIR"

# The SSH/SFTP owner and the game process intentionally share the whole install.
usermod -a -G "$SERVICE_GROUP" "$OWNER_USER"
chgrp -R "$SERVICE_GROUP" "$SERVER_ROOT"
chmod -R g+rwX "$SERVER_ROOT"
find "$SERVER_ROOT" -type d -exec chmod g+s {} +
chmod 0750 /home/l4d2

retire_identical_overlay() {
    local overlay=/home/l4d2/overlay
    [[ -d "$overlay" ]] || return 0
    [[ "$(realpath -e -- "$overlay")" == /home/l4d2/overlay ]] || {
        printf 'install.sh: refusing unexpected overlay path\n' >&2
        exit 1
    }
    if find "$overlay" -type l -print -quit | grep -q .; then
        printf 'install.sh: overlay contains a symlink; refusing automatic retirement\n' >&2
        exit 1
    fi
    local source relative destination
    while IFS= read -r -d '' source; do
        relative=${source#"$overlay"/}
        destination="$GAME_DIR/$relative"
        [[ -f "$destination" ]] && cmp -s "$source" "$destination" || {
            printf 'install.sh: overlay differs from game directory: %s\n' "$relative" >&2
            exit 1
        }
    done < <(find "$overlay" -type f -print0)
    rm -rf -- "$overlay"
    printf 'Retired identical /home/l4d2/overlay; the game directory is authoritative.\n'
}

retire_identical_overlay

install -o root -g root -m 0644 "$SCRIPT_DIR/systemd/l4d2.service" \
    /etc/systemd/system/l4d2.service
install -o root -g root -m 0644 "$SCRIPT_DIR/systemd/l4d2-content-watch.service" \
    /etc/systemd/system/l4d2-content-watch.service
install -o root -g root -m 0644 "$SCRIPT_DIR/systemd/l4d2-content-watch.timer" \
    /etc/systemd/system/l4d2-content-watch.timer
rm -f -- \
    /etc/systemd/system/l4d2-maintenance.service \
    /etc/systemd/system/l4d2-maintenance.timer

systemctl daemon-reload
systemctl enable l4d2.service
/usr/local/sbin/l4d2-restart-now --mark-start
systemctl enable --now l4d2-content-watch.timer

# Remove exact obsolete entrypoints. Generated releases/backups are left untouched.
rm -f -- /usr/local/sbin/l4d2-maintain /etc/l4d2-maintain.conf
rm -f -- \
    /usr/local/libexec/l4d2-maintain/l4d2-console \
    /usr/local/libexec/l4d2-maintain/l4d2-run \
    /usr/local/libexec/l4d2-maintain/l4d2-start-tmux \
    /usr/local/libexec/l4d2-maintain/vpk_campaigns.py
rmdir /usr/local/libexec/l4d2-maintain 2>/dev/null || true

printf 'Installed direct-owner L4D2 operations without restarting the game.\n'
printf 'Reconnect SSH/SFTP once so ecs-user receives the l4d2 group.\n'
