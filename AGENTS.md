# Project Instructions

## Project Identity

* Maintain this repository as an L4D2 server configuration built on L4D2 Competitive Rework.
* AstRedux is the actively maintained Coop/PVE mainline. AstMod is retained for legacy compatibility/reference. AstFlex is frozen unless explicitly reopened by the maintainer.
* Read `README.md` for current project positioning and priorities. Do not duplicate the roadmap or current implementation inventory here.
* Do not broadly rewrite Competitive Rework core without a concrete project need and review.

## Sources of Truth

* `README.md`: project intent, mode positioning, and current AstRedux implementation.
* `docs/ROADMAP.md`: planned work; `docs/CHANGELOG.md`: completed repository changes and version history.
* `docs/architecture.md`: configuration layers, runtime ownership, and where to make gameplay/config changes.
* `docs/server-operations.md`: deployment and server operations.
* `docs/plugin-sources.md`: uncertain SMX provenance and rebuild status.
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
* Commit only when explicitly requested or approved by the maintainer; completing work or passing checks does not authorize a commit. Push only when explicitly requested or approved, and deploy only when separately requested.
* `origin` is the primary GitHub remote and `gitea` is the Gitea backup; when pushing, push the requested branches or tags to both and report any failure; commit-only requests do not authorize pushing.
* Preserve unrelated and user-created work; untracked files are not disposable.

* 随代码变更及时更新 `docs/ROADMAP.md` 和 `docs/CHANGELOG.md`：前者记录后续计划，完成事项归入后者的未发布部分；两者记录仓库状态，不作为试玩验收清单。

## 版本发布

* 使用 `vX.Y.Z` 附注标签标记整套配置版本，各插件保留独立版本号；发布前核对相关源码与编译产物，并完成必要检查和维护者试玩确认。
* 日常值得记录的变更积累在 `docs/CHANGELOG.md` 的“未发布”部分；发布时归入对应版本和日期，GitHub Release 正文复用该版本记录。
* 打标签及创建 Release 须经维护者明确批准或指令；分支与标签按既有远端规则同步，Release 发布到 GitHub `origin`。
* 凭据、运行时数据、缓存、日志及备份保留在 Git 之外。

## Final Principle

Do not optimize for making every historical path keep working somehow.

Prefer:

1. understanding existing implementations before replacing them;
2. making only the requested change;
3. clear component ownership;
4. minimal compatibility debt;
5. validation of real runtime behavior.
