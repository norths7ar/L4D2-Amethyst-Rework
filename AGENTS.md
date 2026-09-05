# Project Instructions

## Project Identity

* Maintain this repository as an L4D2 server configuration built on L4D2 Competitive Rework.
* AstRedux is the actively maintained Coop/PVE mainline. AstMod is retained for legacy compatibility/reference. AstFlex is frozen unless explicitly reopened by the maintainer.
* Read `README.md` for current project positioning and priorities. Do not duplicate the roadmap or current implementation inventory here.
* Do not broadly rewrite Competitive Rework core without a concrete project need and review.

## Sources of Truth

* `README.md`: project intent, mode positioning, and high-level design.
* `author/CONFIG_GUIDE.md`: configuration layers, runtime ownership, and where to make gameplay/config changes.
* `author/SERVER_OPERATIONS.md`: deployment and server operations.
* `PLUGIN_SOURCE_INVENTORY.md`: uncertain SMX provenance and rebuild status.
* Actual cfgs, SourcePawn, VScript, Stripper, and plugin-load files: runtime behavior.
* `tools/validate_astmod_integration.ps1`: maintained static validation.

Keep each document in its own lane. AGENTS contains durable Agent maintenance rules, not a second copy of those documents.

## Maintenance Rules

* Reuse before invention. Before implementing common framework or gameplay infrastructure, inspect relevant mature implementations already available in the project's reference repositories.
* Use reference code to understand established lifecycle, interaction, compatibility, and engine-specific behavior before designing a replacement.
* Refactors should preserve established observable behavior unless changing that behavior is part of the task. Do not silently bundle behavior redesign into structural cleanup.
* Prefer fixing ownership or lifecycle mistakes over accumulating ad-hoc timers, conditions, wrappers, or compatibility glue.
* Generic reusable components should use component-oriented naming and ownership rather than being named after the mode that currently loads them.
* Keep component responsibilities narrow. A manager observing a state change does not automatically own all gameplay policy related to that state.
* Treat upstream author comments that explain intent, engine quirks, compatibility, or deliberately disabled behavior as maintenance evidence. Move or update them with the code rather than deleting them for brevity.
* Third-party campaign compatibility is first-class; do not suppress map-authored behavior without a specific reason and runtime verification.

## AstFlex Freeze

* AstFlex is out of scope.
* Do not modify, repair, migrate, rename, shim, or otherwise maintain AstFlex unless the maintainer explicitly reopens it.
* If unrelated work breaks AstFlex, report that consequence and leave it unresolved.
* AstFlex must not influence current architecture decisions while frozen.

## Player-Facing Text

* Internal code, comments, documentation, and Agent discussion may use English or mixed Chinese/English.
* Player-facing text should normally use natural Simplified Chinese and familiar L4D2 terminology.
* Do not expose internal engineering-state wording to players.
* Treat newly generated player-facing copy as provisional; the maintainer is the final wording owner.

## Runtime and Validation

* Use the repository's existing tooling; do not introduce unrelated project infrastructure.
* Primary static validation: `pwsh -File tools/validate_astmod_integration.ps1`.
* Inspect focused diffs and search for stale references after moves, renames, or API changes.
* Compilation/static validation is not runtime verification.
* For gameplay or lifecycle changes, prefer reproducing and testing locally in the maintainer's WSL2 server environment when practical.
* Run deployment or remote diagnostics only when explicitly requested.

## Scope and Delivery

* When the maintainer asks for research, inspection, comparison, or report-only work, do not edit files or implement fixes.
* Do not commit or push unless explicitly requested.
* Preserve unrelated and user-created work; untracked files are not disposable.

## Final Principle

Do not optimize for making every historical path keep working somehow.

Prefer:

1. understanding existing implementations before replacing them;
2. making only the requested change;
3. clear component ownership;
4. minimal compatibility debt;
5. validation of real runtime behavior.
