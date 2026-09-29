# 插件源码

此处只包括 AstRedux 的插件，包括随模式加载的共享插件和基础依赖。

## 目录对应

以 `addons/sourcemod/` 为基准，`scripting/` 的插件入口尽量与 `plugins/` 使用相同相对路径；跨模式共用源码可放在 `scripting/optional/`。`include/` 和插件私有模块目录不对应独立 SMX。

当前维护入口使用 `<name>.sp`；历史副本使用 `<name>.<version>.sp`，分支副本使用 `<name>.<来源>-ver.sp`。

## 源码例外

`enhancedsprays.smx` 缺源码。本插件的功能是允许无CD、随时随地、远近皆可喷漆，无其他效果。

## 已知差异与特殊依赖

- `l4d_reload_fix` 修复修改弹夹容量后的换弹动画。
- `l4d2_reload_fix` 修复拿取同种武器跳过装填的问题。
- `l4d_swimming` 依赖 `ready_pause` 提供的 `readyup` 接口，仅准备阶段可启用；倒计时结束、正式开局前关闭并清理游泳状态。

## 原生扩展

`custom_fakelag` 扩展源码未放在本仓库，修改扩展需使用 [上游源码](https://github.com/ProdigySim/custom_fakelag)。本地命令包装层是 `scripting/optional/coop/player_fakelag.sp`。
