# AstMod integration

This directory is an independent integration build based on
L4D2-Competitive-Rework. The two extracted upstream directories next to it are
kept unchanged.

## Naming

- Competitive Rework matchmode ID: `astmod`
- Player-facing name: `AstMod - 进阶战役`
- Original L4D2 mutation and asset name: `amethyst`

The framework-facing name is deliberately consistent. The original mutation
name remains unchanged because it is referenced by the VPK, VScript, Stripper
configuration, and gameplay configuration.

## Integration decisions

- Competitive Rework owns SourceMod, MetaMod, Confogl, Left4DHooks, extensions,
  general fixes, and the base administrative plugins.
- AstMod-specific root plugins were moved under
  `addons/sourcemod/plugins/optional/amethyst/` so they do not autoload outside
  this matchmode.
- `confogl_autoloader.smx` was not copied. Matchmode entry and exit are owned by
  Competitive Rework through `!match`, `!chmatch`, and `!rmatch`.
- `confoglcompmod.smx` and `match_vote.smx` are loaded from Competitive Rework
  at the end of the AstMod plugin configuration, matching the other Rework
  modes.
- Mode shutdown uses `pred_unload_plugins`; AstMod configuration files do not
  manage plugin locking or call `unload_all` themselves.
- The Rework build of `optional/l4d2_skill_detect.smx` is used instead of the
  older AstMod copy. Their translation format contracts differ, so mixing the
  AstMod binary with Rework translations would be unsafe across mode switches.
- The legacy mode-switching section was removed from AstMod's `cfgs.txt`.
  AstMod's `!vote` remains available for its other actions and ACS continues to
  read the campaign entries from that file.
- ACS and `!vote` keep the full third-party campaign catalog in `cfgs.txt`, but
  hide entries whose first map is not installed. Installing a listed campaign
  makes it available without another configuration edit.

## Gameplay variants

### `astmod`

This is the original hard-core AstMod profile. It keeps AstMod's custom SI wave
spawning and enables Hard SI AI by default.

### `astflex`

This is the lighter profile shown as `AstFlex - 休闲药役` in `!match`:

- the game difficulty is fixed to Advanced (`z_difficulty hard`);
- AstMod's custom SI wave spawning remains enabled;
- Hard SI AI defaults to off and can be changed by vote;
- AstMod's high-tier weapon and resource removals remain active;
- the harsher damage, fast-action, automatic health, and automatic ammo
  modifiers default to off;
- separate `_lite` wave profiles scale the SI limit and spawn interval with the
  survivor count without changing the real game difficulty.

The existing `/tz` menu is also available as `!settings`. Its second page now
contains a majority vote for the `ai_hardsi_enable` master switch. AstMod sets
that switch back to on whenever the original `astmod` profile loads.

The shared Uzi, silenced SMG, pump shotgun, chrome shotgun, and deterministic
shotgun-spread values are synchronized with Zonemod in both profiles. AstMod's
weapon replacement rules, bolt-action sniper path, and PVE reserve-ammo limits
remain mode-specific. Both profiles load Zonemod's current
`optional/l4d2_weapon_attributes.smx` and
`optional/l4d2_static_shotgun_spread.smx`; the older isolated binaries remain
unused because AstMod's weapon-attributes build does not support the
`reloadduration` attribute. The separate `l4d2_smg_reload_tweak.smx` load and
its DAS cvars are disabled so player-count profiles cannot override the
synchronized reload behavior. AstMod's legacy `sm_melee ... damageflags`
commands are also disabled because the current Zonemod plugin no longer
exposes that old interface; DAS melee-versus-Tank multipliers continue to use
the supported `sm_weapon melee tankdamagemult` command.

`clip_removal.smx` is retained as an upstream artifact but is not loaded by
either profile. Its source is absent, its behavior could not be confirmed, and
the AstMod author could not identify its purpose; Zonemod does not use it.

The bundled `amethyst.nut` also guards its second `update_diff` callback during
mode initialization. The original called into `g_ModeScript` before that table
always contained the callback, producing a transient Squirrel exception during
direct matchmode changes.

## Stripper synchronization

The 57 official-map files matching `cXmY*.cfg` in Zonemod are mirrored into
`cfg/stripper/amethyst/maps/`. Global filters and third-party map files are not
overwritten. The validator compares the official-map hashes so later Zonemod
updates cannot silently drift from the AstMod copy.

## Files brought in from AstMod 2.7.1

- `cfg/cfgogl/amethyst/` as `cfg/cfgogl/astmod/`
- `cfg/stripper/amethyst/`
- `cfg/sourcemod/difficulty_adjustment_system/`
- `scripts/vscripts/amethyst.nut`
- `addons/amethyst.vpk`
- `addons/sourcemod/plugins/optional/amethyst/`
- `vote.smx`, `all4dead2.smx`, `server.smx`, `hostname.smx`, and
  `sceneprocessor.smx`, relocated into `optional/amethyst/`
- `addons/sourcemod/configs/cfgs.txt`
- `addons/sourcemod/configs/hostname/`
- AstMod-specific data, gamedata, and translation files required by the
  included plugins
- integration source for the modified `ACS`, `vote`, `challenge`, and
  `AI_HardSI` plugins, including the local compiler dependencies

AstMod's SourceMod/MetaMod core files and extensions were intentionally not
copied. Same-name Competitive Rework core files were not overwritten.

## Open issues

### `amethyst.vpk`

The VPK currently remains because it supplies the `amethyst` and `hunter`
entries in `scripts/gamemodes.txt`, and the mode sets
`mp_gamemode "amethyst"`. It also contains a full 2023-era copy of
`gamemodes.txt`, so its effect on current vanilla and competitive modes must be
tested. Removal or replacement is deferred.

### Missing `wave_spawner.smx`

The upstream Amethyst plugin configuration references
`optional/amethyst/wave_spawner.smx`, but neither the AstMod 2.7.1 runtime
package nor the supplied source archive contains it. The load line is retained
as a disabled comment until the missing component or intended replacement is
identified.

### Remaining runtime validation

Most active AstMod plugins do not have matching source files in the supplied
source archive. Core Linux loading, mode switching, campaign filtering, the Hard
SI AI switch, and resource restrictions have been exercised. The in-game vote
menus, normal chapter completion, and finale campaign switch still need a
connected-player play test.

### `server.smx`

This AstMod plugin is isolated to the mode, but it can change level when the
server becomes empty and exposes an administrator restart command implemented
through `sv_crash`. Decide whether that behavior is wanted after runtime
testing.

## Static validation

Run from this directory:

```powershell
pwsh -File tools/validate_astmod_integration.ps1
```

The validator checks required assets, 206 active plugin loads across both
profiles, forbidden lifecycle commands, matchmode registration, map filtering,
Hard SI AI wiring, the 57 official Stripper hashes, and basic KeyValues brace
balance.

## WSL2 test checklist

The local test deployment uses:

- WSL distribution: `Ubuntu-22.04`
- Service account: `l4d2` (locked password)
- SteamCMD: `/home/l4d2/steamcmd`
- Dedicated server: `/home/l4d2/server`
- Reviewable integration snapshot: `/home/l4d2/integration`
- Local test overrides: `cfg/astmod_test.cfg`

AstMod's 100+ plugin loads are split across `plugins_1.cfg`,
`plugins_2.cfg`, and `plugins_3.cfg`. A single cfg exceeded the Source engine
command buffer after `generalfixes.cfg` and silently stopped before the
framework plugins. The difficulty manager loads last because its generated
cfg temporarily manages SourceMod's loading lock.

As of 2026-07-29, a fresh anonymous Linux install of App 222860 returns
`Invalid platform`. The verified anonymous workaround is to run
`app_update 222860 validate` first with
`@sSteamCmdForcePlatformType windows`, then run it again against the same
install directory with `@sSteamCmdForcePlatformType linux`. The first pass
installs shared content; the second replaces/adds the Linux platform layer.

Runtime verification checklist:

1. [x] Cold start without an active matchmode.
2. [ ] Load AstMod through the in-game `!match` menu (console
   `sm_forcematch astmod` is verified).
3. [x] Inspect `sm plugins list`, SourceMod errors, missing natives, and
   gamedata failures.
4. [x] Verify the core AstMod and AstFlex cvars and plugin state.
5. Complete a normal chapter and a finale.
6. Verify ACS `!mapvote`, `!vote`, `/tz`, and campaign switching with a player.
7. Exit through `!rmatch` and confirm every AstMod-specific plugin is gone.
8. [x] Switch directly from AstMod to Zonemod with a connected client and confirm
   `versus_coop_mode.smx`, ACS, AstMod AI, and AstMod voting plugins are gone.
9. Switch back to AstMod.
10. Repeat the cycle at least three times and inspect residual cvars, duplicate
    commands, plugin load failures, and crashes.
