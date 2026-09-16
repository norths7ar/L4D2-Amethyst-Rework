# 配置架构笔记

面向维护者，记录基于 Competitive Rework 的配置分层、组件职责与设计原则。具体模式的实现说明见项目 [README](../README.md)。

## 配置调用链

```text
configs/matchmodes.txt：注册模式 ID 和显示名
  → cfg/cfgogl/<mode>/
      → shared_cvars.cfg：模式身份、mutation、Stripper 与共同规则
      → confogl_plugins.cfg：插件加载清单或有序 exec 子清单
      → confogl.cfg / confogl_off.cfg：进入与退出模式
      → mapinfo.txt：地图例外
```

插件加载清单可以直接加载，也可以按命令缓冲限制拆分为有序子清单。清单只负责插件生命周期命令与 `exec`；玩法 CVar 放在规则配置中。

## 分层与权威位置

| 层 | 负责什么 | 典型入口 |
| --- | --- | --- |
| 服务器相关 | 不随模式改变的网络、日志与服务器设置 | `cfg/server.cfg` |
| 通用修复 | 无关模式的引擎修复 | `cfg/generalfixes.cfg` |
| 模式注册 | 模式 ID 与显示名 | `configs/matchmodes.txt` |
| 模式规则 | mutation、插件组合、参数与退出收尾 | `cfg/cfgogl/<mode>/` |
| 地图例外 | 地图配置与实体调整 | `mapinfo.txt`、Stripper |
| 运行时调整 | 有生命周期的临时覆盖 | 对应组件 |

修改规则前先确定权威来源，避免同一参数被多层隐式覆盖。配置（如有）声明目标值，控制器选择和下发参数，执行组件负责实际行为；配置选择不应顺带混入无关的插件重载和状态变化。

## 生命周期与组件职责

Competitive Rework 管理插件锁定、模式切换与逆序卸载；自定义模式沿用框架入口。`load_unlock`、`unload_all`、`load_lock`、`refresh` 由框架生命周期统一安排。

## 修改时的阅读顺序

1. 从模式注册和加载链确认组件是否实际生效。
2. 确定配置权威位置，再阅读组件的事件、状态与退出路径。
3. 地图问题同时检查地图配置、Stripper 和地图自身脚本。
4. 新增或替换插件时核对 `configs`、`data`、`gamedata`、`translations`、VScript 与模型等配套资产。
5. 切换后残留先查退出和卸载职责，不先堆补救定时器。

源码入口与二进制对应关系见 [插件源码](plugin-sources.md)。编译检查源码依赖，配置变更核对实际引用；插件加载、玩法和生命周期效果需结合服务器日志与实际运行判断。
