#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || {
    printf 'Run this test as root.\n' >&2
    exit 1
}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HELPER=$(cd -- "$SCRIPT_DIR/.." && pwd)/l4d2-update-and-restart
TEST_ROOT=$(mktemp -d /tmp/l4d2-update-test.XXXXXX)
cleanup() {
    [[ "$TEST_ROOT" == /tmp/l4d2-update-test.* ]] && rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

remote="$TEST_ROOT/remote.git"
publisher="$TEST_ROOT/publisher"
checkout="$TEST_ROOT/checkout"
game_dir="$TEST_ROOT/game"
config="$TEST_ROOT/l4d2-restart.conf"
apply_tool="$TEST_ROOT/apply"
marker="$TEST_ROOT/last-deployed-revision"
apply_log="$TEST_ROOT/apply.log"

git init --bare --initial-branch=main "$remote" >/dev/null
git clone "$remote" "$publisher" >/dev/null 2>&1
git -C "$publisher" config user.name 'Ops Test'
git -C "$publisher" config user.email 'ops-test@example.invalid'
mkdir -p "$publisher/addons" "$publisher/cfg" "$publisher/scripts"
printf 'old\n' >"$publisher/addons/old.smx"
printf 'old cfg\n' >"$publisher/cfg/server.cfg"
printf 'old script\n' >"$publisher/scripts/runtime.nut"
git -C "$publisher" add addons cfg scripts
git -C "$publisher" commit -m initial >/dev/null
git -C "$publisher" push origin main >/dev/null 2>&1

git clone "$remote" "$checkout" >/dev/null 2>&1
mkdir -p "$game_dir"
cp -a "$checkout/addons" "$checkout/cfg" "$checkout/scripts" "$game_dir/"
printf 'local content\n' >"$game_dir/addons/local.vpk"

rm "$publisher/addons/old.smx"
printf 'new\n' >"$publisher/addons/new.smx"
printf 'new cfg\n' >"$publisher/cfg/server.cfg"
git -C "$publisher" add -A addons cfg scripts
git -C "$publisher" commit -m update >/dev/null
git -C "$publisher" push origin main >/dev/null 2>&1
expected_rev=$(git -C "$publisher" rev-parse HEAD)

cat >"$config" <<EOF
OWNER_USER=root
SERVICE_GROUP=root
GAME_DIR=$game_dir
CHECKOUT_ROOT=$checkout
CHECKOUT_BRANCH=main
CHECKOUT_REMOTE=origin
EOF
cat >"$apply_tool" <<EOF
#!/usr/bin/env bash
printf 'called\\n' >>'$apply_log'
EOF
chmod 0755 "$apply_tool"

L4D2_RESTART_CONFIG="$config" \
L4D2_CONTENT_APPLY_TOOL="$apply_tool" \
L4D2_DEPLOY_MARKER="$marker" \
    "$HELPER" >/dev/null

[[ $(git -C "$checkout" rev-parse HEAD) == "$expected_rev" ]]
[[ $(<"$marker") == "$expected_rev" ]]
[[ -f "$game_dir/addons/new.smx" ]]
[[ ! -e "$game_dir/addons/old.smx" ]]
[[ -f "$game_dir/addons/local.vpk" ]]
[[ $(<"$game_dir/cfg/server.cfg") == 'new cfg' ]]
[[ $(wc -l <"$apply_log") -eq 1 ]]

printf 'dirty\n' >"$checkout/untracked-local-file"
if L4D2_RESTART_CONFIG="$config" \
    L4D2_CONTENT_APPLY_TOOL="$apply_tool" \
    L4D2_DEPLOY_MARKER="$marker" \
        "$HELPER" >/dev/null 2>&1; then
    printf 'Dirty checkout unexpectedly deployed.\n' >&2
    exit 1
fi
[[ $(wc -l <"$apply_log") -eq 1 ]]
[[ $(<"$marker") == "$expected_rev" ]]

printf 'l4d2-update-and-restart integration test passed.\n'
