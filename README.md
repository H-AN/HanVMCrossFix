独立跨VM动画修复插件

CVAR
```
han_crossfix_enable 1 //是否开启修复 默认 1
han_crossfix_hide 1 //在中间 Tick 期间隐藏第一人称视图模型渲染(视觉不突兀)；继续进行网络同步。 默认 1
han_crossfix_draw_ticks 2 //两个 VM 切换修复的绘制中间tick时间 默认 2
han_crossfix_melee_ticks 3 // 快速近战刀切换修复的的绘制中间tick时间 默认 3
han_crossfix_log 0 // 是否控制台打印修复logger 默认 0
```
实现通过玩家m_bDrawViewmodel关闭第一人称模型绘制，继续发送VM的中间sequence；
恢复目标sequence时恢复绘制。


工作方式：
- Han_GetClientViewModelMode / GetClientViewModel：确认实际显示的VM。
- QuickMelee_IsCombat：识别快速近战流程。
- Han_OnKnifeAttack：仅记录真实刀攻击发生，等OnPlayerRunCmdPost再读取最终攻击序列。
- OnPlayerRunCmdPost：检测跨VM、保持中间序列、恢复动画；覆盖0→1和1→0。
- 单用WeaponSwitch不够：QuickMelee直接改m_hActiveWeapon，跳过正常Deploy。

安装方式：

必须前置条件 ：
使用武器系统（![HanWeaponSystem](https://github.com/H-AN/H-AN-CSS-HanWeaponSystem)）、
快速近战（quickseries by Ducheese ）

使用 HanWeaponSystem 配合快速近战时 快速近战插件cvar sm_quickmelee_fix_viewmodel 必须设置为 1 或者 2
在将本插件放置使用

draw两方向均默认2 tick，沿用用户确认合适的值。快速近战攻击默认3 tick。
han_crossfix_enable 0 关闭外部修补；使用此cvar进行 测试，可以有效的看到修复效果

满足测试四种方向：
1. VM1枪→VM0刀快速近战→VM1枪。 - √完美修复，动画无缺失
2. VM1自定义刀→VM0原版枪，检查原版枪draw。√完美修复，动画无缺失
3. 普通0→1、1→0切枪。√完美修复，动画无缺失
4. 0→0、1→1不触发修补；切回后立即开火、换弹应能中断旧动画。

注意事项：
此插件原为修复 HanWeaponSystem 与  quickseries 的兼容插件
所以本插件必须同时安装 HanWeaponSystem 与  quickseries 用了两者的API进行外部修复
但是所用的修复原理可以用与其他情况下 v0与v1 切换导致丢失动画的问题
其他插件可参考此修复原理，自行寻找v0和v1 然后根据源码逻辑原理进行动画修复

