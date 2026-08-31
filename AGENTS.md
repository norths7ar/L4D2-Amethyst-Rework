# Project Instructions

## Project Identity

- Maintain a complete L4D2 server configuration on top of L4D2 Competitive Rework, with the AstMod PVE family exposed as independent Confogl matchmodes.
- Mode roles: `astmod` = maintained personal Baseline rather than a byte-for-byte historical archive; `astredux` = runnable parallel development mode that reuses unchanged AstMod assets while replacing rules with Redux-owned components; `astflex` = paused low-pressure preview retained until Redux or another viable Coop-native base exists. Read `README.md` for current priorities rather than duplicating the roadmap here.
- Do not broadly rewrite Competitive Rework core without a concrete mode need and review.

## Sources of truth

- `README.md`: project intent, mode positioning, AstMod → AstRedux differences, Redux status, and roadmap.
- `ASTMOD_INTEGRATION.md`: how the AstMod Baseline is integrated into Competitive Rework, including copied assets, lifecycle boundaries, known issues, and AstMod validation history.
- `PLUGIN_SOURCE_INVENTORY.md`: bundled SMX provenance, source leads, and rebuild boundaries.
- `addons/sourcemod/configs/matchmodes.txt`: registered matchmode IDs.
- `cfg/cfgogl/<mode>/`, SourceMod configs, and active plugin-load cfgs: actual runtime behavior and gameplay values.
- `tools/validate_astmod_integration.ps1`: maintained static checks.

Keep these in their own lane. AGENTS records durable maintenance invariants, not current gameplay values or a second copy of project status. README explains intent and meaningful design differences but should link to authoritative configs instead of duplicating frequently changing numeric tables. Use ASTMOD_INTEGRATION for Baseline integration facts and PLUGIN_SOURCE_INVENTORY for binary provenance.

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

- Naming boundary: the stable Baseline uses `astmod`; the parallel development mode owns the `astredux` matchmode, mutation, cfg, VScript, and replacement-plugin names while reusing AstMod assets that it has not replaced. The old `amethyst` namespace may appear only in historical/upstream provenance. Keep Redux changes isolated until deliberately backported. AstFlex development is paused.
- Shared-plugin boundary: `cfg/generalfixes.cfg` must remain mode-neutral. Human-PvP policy belongs in `cfg/competitive_shared.cfg`; Ast modes load `jointeam.smx` and must not also load `playermanagement.smx`.
- Competitive Rework owns framework lifecycle. Never place `sm plugins load_unlock`, `unload_all`, `load_lock`, or `refresh` in custom mode cfgs. Custom modes must follow the current Rework lifecycle instead of managing plugin locking or full teardown themselves.
- AstMod-only plugins and unchanged implementations reused by Ast modes stay under `addons/sourcemod/plugins/optional/astmod/`; Redux-owned replacements stay under `addons/sourcemod/plugins/optional/astredux/`. Do not reintroduce `confogl_autoloader.smx`.
- Do not overwrite same-name Competitive Rework core files with older AstMod copies. The plugin-load cfg split (`plugins_1/2/3.cfg`) preserves staged load order. Plugin-list cfgs may contain only plugin lifecycle commands and `exec` calls to other plugin lists; gameplay CVars and unrelated commands belong in the mode or shared runtime cfg that owns them. Changing cross-stage load order, collapsing the split, or moving dependency-sensitive plugins requires dependency analysis and runtime validation.
- Use `confogl_addcvar` for match-scoped values that should remain fixed during play. Use `sm_cvar` for values that plugins intentionally change at runtime so Confogl does not report expected changes as tracked-CVar violations.
- Treat existing author and upstream comments as maintenance evidence, especially comments that explain design intent, game-engine quirks, compatibility constraints, provenance, or deliberately disabled behavior. Refactors must move or update those comments with the code instead of deleting them merely for brevity or style. Before removing substantial comments or commented reference code, compare with `AstSrc` or the relevant upstream; remove it only when it is demonstrably stale, incorrect, or valueless debug residue, and preserve the rationale in a replacement comment when the behavior remains.
- `astmod.vpk` is rebuilt from `assets/astmod_vpk/` by `tools/build_astmod_vpk.ps1`. Recheck its `gamemodes.txt` after game updates and when combining addons that ship the same path. Missing source or a reproducible build for some bundled SMX files does not block unrelated configuration and integration maintenance. State provenance honestly: do not claim bundled `.smx` files were rebuilt, source-matched, or audited when they were not.
- Third-party campaign compatibility is first-class. Do not suppress map instructor hints, scripted bosses, mechanisms, or finale progression without a mode-specific reason and a runtime test. Preserve AstMod custom SI spawning as mode identity unless the user explicitly changes that decision.
- `astredux` is a parallel rules experiment focused on a Coop-native base and third-party campaign compatibility. Preserve AstMod as the stable Versus-backed Baseline while Redux evolves independently.
