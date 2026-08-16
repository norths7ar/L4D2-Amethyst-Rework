# Project Instructions

## Project Identity

- Maintain a complete L4D2 server configuration on top of L4D2 Competitive Rework, with the AstMod PVE family exposed as independent Confogl matchmodes.
- Mode roles: `astmod` = maintained personal Baseline (not a byte-for-byte 2.7.1 archive); `astredux` = current development direction and a future parallel Coop-native experimental ruleset; `astflex` = paused low-pressure preview whose existing config is retained until Redux or another viable Coop-native base exists. Read `README.md` for current priorities rather than duplicating the roadmap here.
- Non-goals: do not make this an untouched AstMod mirror; do not broadly rewrite Competitive Rework core without a concrete mode need and review; do not stand up or administer a public server as part of a config/docs task; do not treat bundled binaries as blocked on full source recompilation before useful maintenance can proceed.

## Sources of truth

- `README.md`: project intent, mode positioning, status, roadmap.
- `ASTMOD_INTEGRATION.md`: integration boundaries, copied assets, known issues, validation history — the single source for implementation facts.
- `addons/sourcemod/configs/matchmodes.txt`: registered matchmode IDs.
- `cfg/cfgogl/<mode>/` and active plugin-load cfgs: actual runtime behavior.
- `tools/validate_astmod_integration.ps1`: maintained static checks.

Keep these in their own lane. Do not duplicate implementation facts in AGENTS; reference ASTMOD_INTEGRATION instead.

## Runtime and validation

- Runtime: L4D2 Dedicated Server with the repository's MetaMod, SourceMod 1.12+, Left4DHooks, Confogl, extensions, plugins, cfgs, VScript, Stripper, and VPK assets. This is not a Python project.
- Primary static validation from the repository root: `pwsh -File tools/validate_astmod_integration.ps1`.
- Deployment/diagnostic helpers live under `scripts/` (WSL2 desktop today; a rented Ubuntu VPS is planned). Run them only when the user explicitly requests server deployment, startup, diagnosis, or runtime testing.
- Per-change validation floor: docs-only → check the rendered Markdown and search for stale names or contradictory status; cfg/plugin → run the static validator and inspect the focused Git diff; gameplay/lifecycle → not "runtime-verified" until the relevant server and connected-player flow has actually been exercised.
- Do not commit runtime-only data: WSL2/VPS server installs, SteamCMD depots, logs, credentials, RCON passwords, crash dumps, or deployment snapshots.

## Ownership and delivery

- Single-maintainer repository. Do not commit or push unless the user asks.
- Accepted routine changes commit directly to `main`; do not create a feature branch or PR unless explicitly requested. Preserve unrelated or user-created work; an untracked file is not disposable.
- Honor the maintainer's configured SSH commit signing. If a sandbox cannot access the signing key, rerun the commit in the correct user context; never disable signing locally or globally as a workaround.
- Remotes: `origin` = public primary; `gitea` = private backup mirror; `upstream-rework` = official Competitive Rework, fetch-only. `main` tracks `origin/main`; push the same accepted commit to `gitea main` as backup unless the user narrows the destination. For upstream updates, fetch `upstream-rework`, inspect incoming commits and conflicts, then integrate deliberately — no blind merge/rebase and no push to the upstream remote.

## Hard constraints

- Naming boundary: active runtime assets use `astmod` consistently, including the mutation, VPK, VScript, Stripper path, main cfg, and isolated plugin namespace. The old namespace may appear only in historical/upstream provenance. `astredux` remains a separate future ruleset; do not implement it as a thin AstMod overlay. AstFlex development is paused.
- Competitive Rework owns framework lifecycle. Never place `sm plugins load_unlock`, `unload_all`, `load_lock`, or `refresh` in custom mode cfgs. Custom modes must follow the current Rework lifecycle instead of managing plugin locking or full teardown themselves.
- AstMod-only plugins stay under `addons/sourcemod/plugins/optional/astmod/`. Do not reintroduce `confogl_autoloader.smx`.
- Do not overwrite same-name Competitive Rework core files with older AstMod copies. The plugin-load cfg split (`plugins_1/2/3.cfg`) preserves load order; change it only with runtime evidence.
- `astmod.vpk` is rebuilt from `assets/astmod_vpk/` by `tools/build_astmod_vpk.ps1`. Its `gamemodes.txt` matches the locally installed App 222860 update version except for appended `astmod` and legacy `hunter` entries; recheck this after game updates and when combining addons that ship the same path. `clip_removal.smx` and `l4d2_smg_reload_tweak.smx` remain present but are not loaded by default. State provenance honestly — do not claim bundled `.smx` were rebuilt or audited when they were not.
- Third-party campaign compatibility is first-class. Do not suppress map instructor hints, scripted bosses, mechanisms, or finale progression without a mode-specific reason and a runtime test. Preserve AstMod custom SI spawning as mode identity unless the user explicitly changes that decision.
- `astredux` is a parallel rules experiment focused on a Coop-native base and third-party campaign compatibility. Preserve AstMod as the stable Versus-backed Baseline while Redux evolves independently.
