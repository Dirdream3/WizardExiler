class_name BuffDef
extends RefCounted

## Buff / Debuff 的**定义**（模板，全局只有一份）
##
## 关键认知：**Buff 本质就是"一个带生命周期的 Modifier 容器"**。
## 你不需要为每个 Buff 写代码，只需要填数据。
##
## 叠加规则（StackRule）必须在设计期就定死，后补会非常痛苦，
## 因为它决定了 UI 怎么显示、数值怎么平衡、DoT 怎么结算。

enum StackRule {
	## 重复施加只刷新持续时间，效果不叠加。
	## 用于：绝大多数增益（狂怒、坚定、加速药剂）
	REFRESH,

	## 每次施加都产生独立实例，各自计时、效果全部叠加。
	## 用于：多个来源的中毒、流血
	INDEPENDENT,

	## 只保留最强的一个（按 power() 比较），弱的直接被忽略。
	## 用于：同名不同等级的光环、队友重复上的增益
	HIGHEST,

	## 单个实例叠层，效果 × 层数，每次施加刷新时间。
	## 用于：充能、灼烧层数、连击点数
	STACK_COUNT,
}

var id: StringName = &""
var display_name: String = ""
var description: String = ""

## 持续时间（秒）。<= 0 表示永久（光环、被动、装备提供的常驻效果）
var duration: float = 5.0

var stack_rule: int = StackRule.REFRESH
var max_stacks: int = 1

## 这个 Buff 提供的词缀。STACK_COUNT 规则下会按层数放大。
var mods: Array[Modifier] = []

var is_debuff: bool = false

# --- 周期性结算（DoT）---
## 每隔多少秒结算一次。<= 0 表示不做周期结算
var period: float = 0.0
## 每次结算的基础伤害。实际伤害在**施加瞬间**由施法者属性快照决定
## （PoE 的点燃/中毒就是这样：脱掉装备后已经上身的 DoT 不会变弱）
var dot_damage: float = 0.0
## DoT 的伤害标签，决定防守方用哪条抗性来减免
var dot_tags: int = CombatTags.NONE


func _init(p_id: StringName = &"", p_name: String = "") -> void:
	id = p_id
	display_name = p_name


# --- 链式构造，填数据时更顺手 ---

func with_duration(v: float) -> BuffDef:
	duration = v
	return self


func with_stacking(rule: int, p_max_stacks: int = 1) -> BuffDef:
	stack_rule = rule
	max_stacks = maxi(1, p_max_stacks)
	return self


func with_mod(m: Modifier) -> BuffDef:
	m.source = id
	mods.append(m)
	return self


func with_dot(damage: float, p_period: float, tags: int) -> BuffDef:
	dot_damage = damage
	period = p_period
	dot_tags = tags
	return self


func as_debuff() -> BuffDef:
	is_debuff = true
	return self


## HIGHEST 规则用来比较强度的简单启发式。
## 真实项目里通常会改成显式的 `power_level` 字段，避免歧义。
func power() -> float:
	var p := dot_damage
	for m in mods:
		p += absf(m.value)
	return p


func describe() -> String:
	var lines := PackedStringArray()
	lines.append("%s（%s）" % [display_name, _rule_name()])
	if duration > 0.0:
		lines.append("  持续 %.1f 秒" % duration)
	else:
		lines.append("  永久")
	for m in mods:
		lines.append("  · " + m.describe())
	if period > 0.0:
		lines.append("  · 每 %.1f 秒造成 %.1f 点%s伤害" % [period, dot_damage, CombatTags.describe(dot_tags)])
	return "\n".join(lines)


func _rule_name() -> String:
	match stack_rule:
		StackRule.REFRESH:     return "刷新时长"
		StackRule.INDEPENDENT: return "独立计时"
		StackRule.HIGHEST:     return "取最强"
		StackRule.STACK_COUNT: return "最多 %d 层" % max_stacks
	return "?"
