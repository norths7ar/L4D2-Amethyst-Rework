#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_PATH=/etc/l4d2-maintain.conf
LIBEXEC_DIR=/usr/local/libexec/l4d2-maintain
MAINTAIN_BIN=/usr/local/sbin/l4d2-maintain
ACTIVATE=0

if [[ ${1:-} == --activate ]]; then
    ACTIVATE=1
elif [[ $# -ne 0 ]]; then
    printf 'Usage: sudo ./ops/install.sh [--activate]\n' >&2
    exit 2
fi

[[ $EUID -eq 0 ]] || {
    printf 'install.sh: run through sudo\n' >&2
    exit 1
}
id l4d2 >/dev/null 2>&1 || {
    printf 'install.sh: service account l4d2 does not exist\n' >&2
    exit 1
}
id ecs-user >/dev/null 2>&1 || {
    printf 'install.sh: maintenance account ecs-user does not exist\n' >&2
    exit 1
}

assert_unit_ownership() {
    local destination=$1
    if [[ -e "$destination" ]] \
        && ! grep -Fq '# Managed by L4D2-Amethyst-Rework ops/install.sh' "$destination"; then
        printf 'install.sh: refusing to overwrite unowned unit %s\n' "$destination" >&2
        exit 1
    fi
}

assert_unit_ownership /etc/systemd/system/l4d2.service
assert_unit_ownership /etc/systemd/system/l4d2-maintenance.service
assert_unit_ownership /etc/systemd/system/l4d2-maintenance.timer

install -d -o root -g root -m 0755 "$LIBEXEC_DIR"
install -o root -g root -m 0755 "$SCRIPT_DIR/l4d2-maintain" "$MAINTAIN_BIN"
install -o root -g root -m 0755 "$SCRIPT_DIR/libexec/l4d2-console" "$LIBEXEC_DIR/l4d2-console"
install -o root -g root -m 0755 "$SCRIPT_DIR/libexec/l4d2-run" "$LIBEXEC_DIR/l4d2-run"
install -o root -g root -m 0755 "$SCRIPT_DIR/libexec/l4d2-start-tmux" "$LIBEXEC_DIR/l4d2-start-tmux"
install -o root -g root -m 0755 "$SCRIPT_DIR/libexec/vpk_campaigns.py" "$LIBEXEC_DIR/vpk_campaigns.py"
if [[ ! -e "$CONFIG_PATH" ]]; then
    install -o root -g l4d2 -m 0640 "$SCRIPT_DIR/l4d2-maintain.conf.example" "$CONFIG_PATH"
fi
install -o root -g root -m 0644 "$SCRIPT_DIR/systemd/l4d2.service" /etc/systemd/system/l4d2.service
install -o root -g root -m 0644 "$SCRIPT_DIR/systemd/l4d2-maintenance.service" /etc/systemd/system/l4d2-maintenance.service
install -o root -g root -m 0644 "$SCRIPT_DIR/systemd/l4d2-maintenance.timer" /etc/systemd/system/l4d2-maintenance.timer

# shellcheck source=/dev/null
source "$CONFIG_PATH"
chown root:"$SERVICE_USER" "$CONFIG_PATH"
chmod 0640 "$CONFIG_PATH"
install -d -o "$SERVICE_USER" -g "$SERVICE_USER" -m 0750 \
    "$RELEASES_DIR" "$OVERLAY_DIR" "$CONTENT_DIR" "$RETIRING_DIR" "$BACKUP_DIR"
install -d -o root -g "$SERVICE_USER" -m 0750 "$STATE_DIR"
install -d -o "$TMUX_USER" -g "$SERVICE_USER" -m 0750 "$UPLOAD_DIR"

seed_overlay_file() {
    local relative=$1
    local source="$GAME_DIR/$relative"
    local destination="$OVERLAY_DIR/$relative"
    if [[ -f "$source" && ! -e "$destination" ]]; then
        install -d -o "$SERVICE_USER" -g "$SERVICE_USER" -m 0750 "$(dirname "$destination")"
        install -o "$SERVICE_USER" -g "$SERVICE_USER" -m 0640 "$source" "$destination"
    fi
}

# Preserve known server-private files before the first Git-managed deployment.
seed_overlay_file addons/sourcemod/configs/admins_simple.ini
seed_overlay_file cfg/server.cfg
systemctl daemon-reload

restore_tmux_runtime() {
    if ! runuser -u "$TMUX_USER" -- tmux new-session -d -s "$TMUX_SESSION" \
        "sudo -n $LIBEXEC_DIR/l4d2-start-tmux"; then
        printf 'install.sh: failed to create fallback tmux session\n' >&2
        return 1
    fi
    for _ in {1..60}; do
        if "$LIBEXEC_DIR/l4d2-console" status >/dev/null 2>&1; then
            printf 'install.sh: tmux runtime restored and queryable\n' >&2
            return 0
        fi
        sleep 1
    done
    printf 'install.sh: fallback tmux runtime is not queryable\n' >&2
    return 1
}

if ((ACTIVATE == 0)); then
    printf 'Installed without changing the running game process.\n'
    printf 'Run sudo %s preflight, then rerun this installer with --activate during an empty window.\n' "$MAINTAIN_BIN"
    exit 0
fi

gate_closed=0
reopen_activation_gate_on_exit() {
    local exit_code=$?
    trap - EXIT
    if ((gate_closed)); then
        if [[ "$("$LIBEXEC_DIR/l4d2-console" runtime 2>/dev/null || true)" != stopped ]]; then
            "$LIBEXEC_DIR/l4d2-console" gate-open >/dev/null 2>&1 \
                || printf 'install.sh: WARNING: failed to reopen the join gate\n' >&2
        fi
    fi
    exit "$exit_code"
}
trap reopen_activation_gate_on_exit EXIT

"$MAINTAIN_BIN" preflight
runtime=$("$LIBEXEC_DIR/l4d2-console" runtime)
if [[ "$runtime" == stopped ]]; then
    humans=0
else
    status_output=$("$LIBEXEC_DIR/l4d2-console" status)
    humans=$(sed -nE 's/^players[[:space:]]*:[[:space:]]*([0-9]+) humans.*/\1/p' <<<"$status_output" | tail -n 1)
fi
[[ "$humans" == 0 ]] || {
    printf 'install.sh: server is not confirmed empty (%s humans)\n' "${humans:-unknown}" >&2
    exit 1
}
if [[ "$runtime" != stopped ]]; then
    gate_closed=1
    "$LIBEXEC_DIR/l4d2-console" gate-close
fi
sleep 2
if [[ "$("$LIBEXEC_DIR/l4d2-console" runtime)" == stopped ]]; then
    humans=0
else
    status_output=$("$LIBEXEC_DIR/l4d2-console" status)
    humans=$(sed -nE 's/^players[[:space:]]*:[[:space:]]*([0-9]+) humans.*/\1/p' <<<"$status_output" | tail -n 1)
fi
[[ "$humans" == 0 ]] || {
    "$LIBEXEC_DIR/l4d2-console" gate-open || true
    printf 'install.sh: server stopped being empty during activation\n' >&2
    exit 1
}

runtime=$("$LIBEXEC_DIR/l4d2-console" runtime)
if [[ "$runtime" == tmux ]]; then
    "$LIBEXEC_DIR/l4d2-console" quit || true
    for _ in {1..30}; do
        if ! pgrep -f '[s]rcds_linux' >/dev/null; then
            break
        fi
        sleep 1
    done
    if pgrep -f '[s]rcds_linux' >/dev/null; then
        "$LIBEXEC_DIR/l4d2-console" gate-open || true
    fi
    runuser -u "$TMUX_USER" -- tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
fi
if pgrep -f '[s]rcds_linux' >/dev/null; then
    "$LIBEXEC_DIR/l4d2-console" gate-open || true
    printf 'install.sh: old srcds process did not stop; refusing a second instance\n' >&2
    exit 1
fi
gate_closed=0

if ! systemctl enable --now l4d2.service || ! "$MAINTAIN_BIN" health; then
    printf 'install.sh: systemd startup failed; restoring tmux runtime\n' >&2
    systemctl disable --now l4d2.service || true
    restore_tmux_runtime || true
    exit 1
fi
systemctl enable --now l4d2-maintenance.timer
trap - EXIT
printf 'Activated l4d2.service and l4d2-maintenance.timer.\n'
