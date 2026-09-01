class_name HitResult
extends RefCounted

## 一次伤害结算的完整记录。
##
## 不只返回一个数字，而是把每一步都记下来 —— 这在调平衡的时候能救命，
## 也是伤害面板 / 战斗日志 / DPS 计算器的直接数据源。

var tags: int = CombatTags.NONE

var base: float = 0.0            ## ① 技能基础伤害
var after_mods: float = 0.0      ## ② 过完四段式词缀
var is_crit: bool = false
var crit_multi: float = 1.0
var after_crit: float = 0.0      ## ③ 过完暴击
var mitigation: float = 0.0      ## 防守方减免比例（0~1）
var after_defence: float = 0.0   ## ④ 过完护甲/抗性
var total: float = 0.0           ## ⑤ 最终伤害（过完承受伤害词缀）

var steps := PackedStringArray()


func log_text() -> String:
	return "\n".join(steps)
