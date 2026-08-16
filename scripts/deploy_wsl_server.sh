#!/usr/bin/env bash
set -euo pipefail

source_root='/mnt/e/l4d2_configs_merge/L4D2-Competitive-Rework-AstMod'
integration_root='/home/l4d2/integration'
game_root='/home/l4d2/server/left4dead2'

install -d "$integration_root" "$game_root"
cp -a "$source_root/." "$integration_root/"
cp -a \
    "$integration_root/addons" \
    "$integration_root/cfg" \
    "$integration_root/scripts" \
    "$game_root/"

for file_name in host.txt motd.txt myhost.txt mymotd.txt; do
    if [[ -f "$integration_root/$file_name" ]]; then
        cp -a "$integration_root/$file_name" "$game_root/"
    fi
done

test -x /home/l4d2/server/srcds_linux
test -f "$game_root/addons/sourcemod/configs/matchmodes.txt"
test -f "$game_root/cfg/cfgogl/astmod/confogl_plugins.cfg"
test -f "$game_root/addons/amethyst.vpk"

echo 'AstMod integration deployed to the WSL2 server.'
