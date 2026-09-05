# Project Instructions

## Project Identity

- Maintain a complete L4D2 server configuration on top of L4D2 Competitive Rework. AstRedux is the formal current Coop/PVE gameplay mainline; AstMod remains a legacy compatibility mode, and AstFlex is paused with no maintenance unless separately authorized. Read `README.md` for current priorities rather than duplicating a roadmap here.
- Do not broadly rewrite Competitive Rework core without a concrete mode need and review.

## Sources of truth

- `README.md`: project intent and current mode positioning.
- `PLUGIN_SOURCE_INVENTORY.md`: bundled SMX provenance, source leads, and rebuild boundaries.
- `addons/sourcemod/configs/matchmodes.txt`: registered matchmode IDs.
- `cfg/cfgogl/<mode>/`, SourceMod configs, and active plugin-load cfgs: actual runtime behavior and gameplay values.
- `tools/validate_astmod_integration.ps1`: maintained static checks.

Keep these in their own lane. AGENTS records durable maintenance invariants, not current gameplay values or a second copy of project status. README explains intent and meaningful design differences but should link to authoritative configs instead of duplicating frequently changing numeric tables. Use PLUGIN_SOURCE_INVENTORY for binary provenance.

## Runtime and validation

- Runtime: L4D2 Dedicated Server with the repository's MetaMod, SourceMod 1.12+, Left4DHooks, Confogl, extensions, plugins, cfgs, VScript, Stripper, and VPK assets. This is a SourceMod and server-configuration repository; use the existing PowerShell tooling and do not introduce Python project infrastructure unless a task specifically requires it.
- Primary static validation from the repository root: `pwsh -File tools/validate_astmod_integration.ps1`.
- `scripts/` contains maintainer-specific deployment and diagnostic helpers. Inspect them before use and do not assume they are portable. Run deployment or remote diagnostics only when explicitly requested.
- Per-change validation floor: docs-only → check the rendered Markdown and search for stale names or contradictory status; cfg/plugin → run the static validator and inspect the focused Git diff; gameplay/lifecycle → not "runtime-verified" until the relevant server and connected-player flow has actually been exercised.
- Keep server installations, SteamCMD downloads, logs, credentials, crash dumps, and generated deployment output out of Git.

## Ownership and delivery

- Collaborative repository. The user is the primary maintainer and final decision owner for this fork. Do not commit or push unless the user asks.
- Changes developed directly with the maintainer may commit to `main` once accepted; use a branch or PR when requested. Review collaborator contributions through GitHub pull requests and do not rewrite contributor branches. Preserve unrelated or user-created work; an untracked file is not disposable.
- Honor the maintainer's configured SSH commit signing. If a sandbox cannot access the signing key, rerun the commit in the correct user context; never disable signing locally or globally as a workaround.
- Remotes: `origin` = public primary; `gitea` = private backup mirror; `upstream-rework` = official Competitive Rework, fetch-only. `main` tracks `origin/main`; push the same accepted commit to `gitea main` as backup unless the user narrows the destination. For upstream updates, fetch `upstream-rework`, inspect incoming commits and conflicts, then integrate deliberately — no blind merge/rebase and no push to the upstream remote.

## Hard constraints

- Naming boundary: `astredux` is the current Coop/PVE matchmode, mutation, cfg, VScript, and identity namespace. `astmod` is the legacy compatibility mode; `astflex` is paused and receives no maintenance unless separately authorized. Generic shared components must not be named for either mode. The old `amethyst` namespace may appear only in historical/upstream provenance.
- Shared-plugin boundary: `cfg/generalfixes.cfg` must remain mode-neutral. Human-PvP policy belongs in `cfg/competitive_shared.cfg`. AstMod alone loads the legacy `optional/astmod/jointeam.smx` and `pause_coop.smx`; AstRedux loads the Coop `player_manager`, `ready_pause`, `survivor_loadout`, and `admin_tools` components and must not also load legacy Jointeam, Competitive pause, or `playermanagement.smx`. AstFlex is paused; its current configuration is intentionally outside this cleanup boundary.
- Competitive Rework owns framework lifecycle. Never place `sm plugins load_unlock`, `unload_all`, `load_lock`, or `refresh` in custom mode cfgs. Custom modes must follow the current Rework lifecycle instead of managing plugin locking or full teardown themselves.
- Plugin directories follow the runtime ecology: `optional/` root for cross-mode components, `optional/competitive/` for Human Survivor-vs-Infected PVP, `optional/coop/` for Coop/PVE and shared Coop components, `optional/astmod/` for AstMod legacy-specific implementations, `optional/astmod/disabled/` for unloaded AstMod binaries, and `plugins/disabled/` for other unloaded non-AstMod-specific binaries. Do not create `legacy/` or `versus/` namespaces, and do not reintroduce `confogl_autoloader.smx`.
- Challenge implementations are kept separately as `optional/coop/challenge.smx` and `optional/astmod/challenge.smx`; shared code duplication is acceptable to keep either implementation from depending on the other mode.
- The `astredux_rules` behavior is split into the Coop components `tank_health`, `tank_melee_damage`, `witch_control`, and `smg_reload_control`.
- Do not overwrite same-name Competitive Rework core files with older AstMod copies. The plugin-load cfg split (`plugins_1/2/3.cfg`) preserves staged load order. Plugin-list cfgs may contain only plugin lifecycle commands and `exec` calls to other plugin lists; gameplay CVars and unrelated commands belong in the mode or shared runtime cfg that owns them. Changing cross-stage load order, collapsing the split, or moving dependency-sensitive plugins requires dependency analysis and runtime validation.
- Use `confogl_addcvar` for match-scoped values that should remain fixed during play. Use `sm_cvar` for values that plugins intentionally change at runtime so Confogl does not report expected changes as tracked-CVar violations.
- Treat existing author and upstream comments as maintenance evidence, especially comments that explain design intent, game-engine quirks, compatibility constraints, provenance, or deliberately disabled behavior. Refactors must move or update those comments with the code instead of deleting them merely for brevity or style. Before removing substantial comments or commented reference code, compare with `AstSrc` or the relevant upstream; remove it only when it is demonstrably stale, incorrect, or valueless debug residue, and preserve the rationale in a replacement comment when the behavior remains.
- `astmod.vpk` is rebuilt from `assets/astmod_vpk/` by `tools/build_astmod_vpk.ps1`. Recheck its `gamemodes.txt` after game updates and when combining addons that ship the same path. Missing source or a reproducible build for some bundled SMX files does not block unrelated configuration and integration maintenance. State provenance honestly: do not claim bundled `.smx` files were rebuilt, source-matched, or audited when they were not.
- Third-party campaign compatibility is first-class. Do not suppress map instructor hints, scripted bosses, mechanisms, or finale progression without a mode-specific reason and a runtime test. Preserve AstMod custom SI spawning as mode identity unless the user explicitly changes that decision.
- `cfg/stripper/astredux/` is the authoritative Stripper directory shared by AstRedux and the legacy AstMod (and paused AstFlex) modes; it must not be described as AstMod-owned. AstRedux does not load Jockey Skeet.
