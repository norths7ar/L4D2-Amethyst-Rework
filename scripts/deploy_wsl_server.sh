#!/usr/bin/env bash
set -euo pipefail

source_root='/mnt/e/l4d2_configs_merge/repos/L4D2-Amethyst-Rework'
integration_root='/home/l4d2/integration'
game_root='/home/l4d2/server/left4dead2'

install -d "$integration_root" "$game_root"
cp -a \
    "$source_root/addons" \
    "$source_root/cfg" \
    "$source_root/scripts" \
    "$integration_root/"
cp -a \
    "$integration_root/addons" \
    "$integration_root/cfg" \
    "$integration_root/scripts" \
    "$game_root/"

legacy_paths=(
    "$integration_root/addons/amethyst.vpk"
    "$integration_root/addons/sourcemod/plugins/optional/amethyst"
    "$integration_root/cfg/cfgogl/astmod/amethyst.cfg"
    "$integration_root/cfg/stripper/amethyst"
    "$integration_root/scripts/vscripts/amethyst.nut"
    "$integration_root/host.txt"
    "$integration_root/motd.txt"
    "$integration_root/myhost.txt"
    "$integration_root/mymotd.txt"
    "$game_root/addons/amethyst.vpk"
    "$game_root/addons/sourcemod/plugins/optional/amethyst"
    "$game_root/cfg/cfgogl/astmod/amethyst.cfg"
    "$game_root/cfg/stripper/amethyst"
    "$game_root/scripts/vscripts/amethyst.nut"
    "$game_root/host.txt"
    "$game_root/motd.txt"
    "$game_root/myhost.txt"
    "$game_root/mymotd.txt"
)

for legacy_path in "${legacy_paths[@]}"; do
    case "$legacy_path" in
        "$integration_root"/*|"$game_root"/*) rm -rf -- "$legacy_path" ;;
        *) echo "Refusing to remove unexpected path: $legacy_path" >&2; exit 1 ;;
    esac
done

test -x /home/l4d2/server/srcds_linux
test -f "$game_root/addons/sourcemod/configs/matchmodes.txt"
test -f "$game_root/cfg/cfgogl/astmod/confogl_plugins.cfg"
test -f "$game_root/addons/astmod.vpk"

echo 'AstMod integration deployed to the WSL2 server.'
