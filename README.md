# Han VM Cross Fix

适用于 CS:S [HanWeaponSystem](https://github.com/H-AN/H-AN-CSS-HanWeaponSystem) 的通用第一人称武器动画修复插件。

武器系统使用 VM0 和 VM1 两个视图模型显示武器。跨 VM 切换时可能出现拔枪、挥刀等动画丢失，Han VM Cross Fix 专门修复这类问题，是武器系统的核心配套修复插件。

**无需安装快速近战插件即可使用。** 如果同时安装了 QuickMelee，本插件会自动兼容，一并修复快速近战跨 VM 切换时的刀动画丢失。

## 功能

- 修复武器在 VM0 → VM1、VM1 → VM0 切换时的动画丢失，适用于武器系统中的跨 VM 切换场景，不限定某种武器。
- 修复期间暂时隐藏第一人称模型，恢复目标动画后立即显示，避免临时修复序列闪现。
- 自动兼容 QuickMelee，修复快速近战挥刀及切回武器过程中的跨 VM 动画问题。
- 同时处理特定模型组合的切换问题，包括自定义 M3 / XM1014 模板武器与自定义消音 USP 模板武器之间的双向快切。

普通同 VM 切换不额外插入修复序列；上述已修复的特殊组合单独处理。

## 依赖

| 组件 | 要求 |
| --- | --- |
| SourceMod / SDKTools | 必需 |
| [HanWeaponSystem v8.2](https://github.com/H-AN/H-AN-CSS-HanWeaponSystem) | 必需，提供武器和视图模型 API |
| [QuickMelee（quickseries）](https://github.com/Ducheese/quickseries) | 可选，安装后自动启用快速近战兼容 |

仅安装武器系统与本插件，即可使用武器切换动画修复。QuickMelee 不属于必需前置。

## 安装

1. 安装 HanWeaponSystem。
2. 将 `HanVMCrossFix.smx` 放入 `addons/sourcemod/plugins/`，加载插件或重启服务器。
3. 默认配置即可使用；如需调整，将下方 CVar 写入 `server.cfg` 或其他服务器配置。本插件不自动生成配置文件。

### QuickMelee 兼容

同时安装 QuickMelee 时，本插件会在每回合开始自动将 `sm_quickmelee_fix_viewmodel` 设为 `1`，由 QuickMelee 正确处理近战时的模型显示。

该回合设置独立于动画修复开关；关闭 `han_crossfix_enable` 或卸载本插件不会自动还原此 CVar。未安装 QuickMelee 时不执行这项设置。

## CVar

| CVar | 默认值 | 说明 |
| --- | --- | --- |
| `han_crossfix_enable` | `1` | 动画修复开关：0 关闭，1 开启 |
| `han_crossfix_hide` | `1` | 修复期间隐藏第一人称模型，避免临时序列闪现：0 关闭，1 开启 |
| `han_crossfix_draw_ticks` | `2` | 武器切换动画修复持续的 tick 数，范围 1–8 |
| `han_crossfix_melee_ticks` | `3` | 快速近战动画修复持续的 tick 数，范围 1–8，仅 QuickMelee 兼容流程使用 |
| `han_crossfix_log` | `0` | 动画修复诊断日志：0 关闭，1 开启 |

```cfg
han_crossfix_enable 1
han_crossfix_hide 1
han_crossfix_draw_ticks 2
han_crossfix_melee_ticks 3
han_crossfix_log 0
```

Tick 是服务器运行步长，不是客户端画面帧数。建议使用默认值；调大修复 tick 数也会延长修复期间的模型隐藏时间。

## 自行编译

使用 SourceMod 编译器，准备标准的 `sourcemod.inc`、`sdktools.inc` 和武器系统 v8.2 的 `HanWeaponSystem.inc`，编译 `HanVMCrossFix.sp`。

