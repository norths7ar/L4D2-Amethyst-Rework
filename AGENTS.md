# Project Instructions

## Project Identity

- Purpose: maintain a complete L4D2 server configuration based on Competitive
  Rework, with the AstMod PVE family available as independent Confogl
  matchmodes.
- Custom mode identities:
  - `astmod`: the maintained personal Baseline, not a byte-for-byte AstMod
    2.7.1 archive;
  - `astredux`: the next priority, focused on auditing and rebuilding the
    rules-layer relationship between Versus behavior and Coop progression;
  - `astflex`: the lower-pressure derivative of AstRedux. Do not redesign it before AstRedux unless asked.
- Non-goals:
  - do not turn this repository into an untouched historical mirror of AstMod;
  - do not replace or broadly rewrite Competitive Rework core code without a
    concrete mode requirement and explicit review;
  - do not install, start, expose, or administer a public game server as part
    of an ordinary configuration/documentation task;
  - do not treat incomplete upstream SourcePawn coverage as a requirement to
    reconstruct every bundled binary before useful maintenance can proceed.
- Sources of truth:
  - `README.md` for project intent, mode positioning, current status, and
    roadmap;
  - `ASTMOD_INTEGRATION.md` for integration boundaries, known issues, and
    validation history;
  - `addons/sourcemod/configs/matchmodes.txt` for registered matchmode IDs;
  - `cfg/cfgogl/<mode>/` and active plugin-load cfgs for actual runtime
    behavior;
  - `tools/validate_astmod_integration.ps1` for the maintained static checks.
- Runtime-only data is outside this repository. Do not commit WSL2 dedicated
  server installs, SteamCMD depots, runtime logs, credentials, RCON passwords,
  crash dumps, or temporary deployment snapshots.

## Runtime and Commands

- Runtime: Left 4 Dead 2 Dedicated Server with the repository's MetaMod,
  SourceMod 1.12+, Left4DHooks, Confogl, extensions, plugins, cfgs, VScript,
  Stripper, and VPK assets. This is not a Python project.
- Primary static validation, run from the repository root:

  ```powershell
  pwsh -File tools/validate_astmod_integration.ps1
  ```

- WSL2 deployment and diagnostic helpers live under `scripts/`. Run them only
  when the user explicitly requests server deployment, startup, diagnosis, or
  runtime testing.
- Required validation before handoff:
  - documentation-only changes: inspect the rendered Markdown structure and
    run targeted searches for stale names or contradictory status claims;
  - cfg/plugin integration changes: run the static validator and inspect the
    focused Git diff;
  - gameplay or lifecycle changes: do not call them runtime-verified until the
    relevant server and connected-player flow has actually been exercised.

## Ownership and Delivery

- This is a single-maintainer repository.
- Do not commit or push unless the user explicitly asks.
- For accepted routine changes, commit directly to `main`; do not create a
  feature branch or pull request unless explicitly requested.
- Remote roles:
  - `origin`: `git@github.com:norths7ar/L4D2-Amethyst-Rework.git`, the public
    primary remote;
  - `gitea`: `ssh://git@100.106.66.21:2222/norths7ar/L4D2-Amethyst-Rework.git`,
    the private backup mirror;
  - `upstream-rework`: the official Competitive Rework repository, fetch-only.
- `main` may track only one remote branch. Keep `origin/main` as the normal
  tracking branch and explicitly push the same accepted commit to
  `gitea main` as the backup. When the user asks to commit and push without
  narrowing the destination, push both `origin main` and `gitea main`.
- For upstream updates, fetch `upstream-rework`, inspect the incoming commits
  and conflicts, then integrate deliberately. Do not blindly merge/rebase and
  do not enable pushes to the upstream remote.
- Preserve unrelated or user-created work. An untracked file is not disposable.

## Project-Specific Constraints

- Keep the naming boundary stable:
  - `amethyst` is the legacy internal mutation/asset name used by the VPK,
    VScript, Stripper path, and existing plugin assets;
  - `astmod`, `astredux`, and `astflex` are framework-facing matchmode IDs.
- Competitive Rework owns framework lifecycle. Do not place
  `sm plugins load_unlock`, `sm plugins unload_all`, `sm plugins load_lock`, or
  `sm plugins refresh` in custom mode cfgs. Do not hand-maintain 100+ unload
  lines when the framework lifecycle already supplies the correct path.
- Keep AstMod-only plugins under `addons/sourcemod/plugins/optional/amethyst/`.
  Do not copy `confogl_autoloader.smx` into the active runtime.
- Do not overwrite same-name Competitive Rework core files with the older
  AstMod runtime copies. Reuse Rework framework plugins and general fixes when
  their contracts match.
- The plugin-load cfg is intentionally split into `plugins_1.cfg`,
  `plugins_2.cfg`, and `plugins_3.cfg` because one large cfg exceeded the Source
  engine command buffer. Preserve the load order unless runtime evidence
  supports a change.
- Treat `addons/amethyst.vpk` as unresolved but currently required. Do not
  delete or replace it until its mutation and `gamemodes.txt` effects have been
  tested.
- Some bundled `.smx` files have no matching source in the supplied AstMod
  archive. Record that provenance honestly. Do not claim they were rebuilt or
  audited when they were not.
- Keep `clip_removal.smx` and `l4d2_smg_reload_tweak.smx` unloaded unless new
  source/runtime evidence justifies them. Preserve the shared SMG, pump/chrome
  shotgun, reload, and deterministic-spread alignment with Zonemod.
- Preserve AstMod custom SI spawning as a mode identity unless the user
  explicitly changes that decision.
- Third-party campaign compatibility is a first-class requirement. Avoid
  suppressing map-provided instructor hints, scripted bosses, mechanisms, or
  finale progression without a mode-specific reason and runtime test.
- AstRedux is a rules audit, not a predetermined “remove Versus at all costs”
  rewrite. Identify which behaviors truly require Versus and prefer a smaller,
  testable plugin replacement only where it is reliable.
- A future per-map route-Tank override must distinguish Director progress Tanks
  from scripted/plugin bosses and persist decisions in a readable, reversible,
  auditable store.
- Keep `README.md` and `ASTMOD_INTEGRATION.md` synchronized with changes to mode
  identity, lifecycle, copied assets, known risks, and validation status.
