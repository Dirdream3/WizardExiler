class_name Modifier
extends RefCounted

## 一条词缀
##
## ★★ 这是整个项目最重要的一个概念，务必看懂 ★★
##
## PoE 的伤害公式是固定的四段式：
##
##     最终值 = (基础值 + Σ增加点数) × (1 + Σ提高%) × Π(1 + 更多%)
##              └── FLAT ──┘         └─ INCREASED ─┘  └──── MORE ────┘
##
## 三种 Kind 的区别（新手最容易搞错的地方）：
##
##   FLAT「增加 20 点火焰伤害」
##       直接加到基础值上，最先结算，后面的百分比都会放大它。
##
##   INCREASED「提高 50% 火焰伤害」
##       **所有 INCREASED 加在一起算一个乘区**。
##       两条 +50% = ×(1 + 0.5 + 0.5) = ×2.0
##
##   MORE「更多 50% 火焰伤害」
##       **每一条独立连乘**。
##       两条 +50% = ×1.5 × 1.5 = ×2.25
##
## 为什么必须分开？因为这决定了整个装备构筑的深度：
## INCREASED 是廉价、随处可得、边际收益递减的；MORE 是稀有、乘算、越叠越强的。
## 大部分 PoE-like 项目返工，都是因为一开始把这两个混成了一个 float。

enum Kind {
	FLAT,      ## 增加 N 点
	INCREASED, ## 提高 N%  —— 同类相加，共用一个乘区
	MORE,      ## 更多 N%  —— 每条独立连乘
}

## 影响哪条属性（CombatStat 里的枚举值）
var stat: int = CombatStat.DAMAGE
## 属于哪个乘区
var kind: int = Kind.INCREASED
## 数值。INCREASED / MORE 用小数：0.4 表示 40%
var value: float = 0.0
## 生效条件：目标标签必须**包含全部**这些标签。0 = 无条件生效
var required_tags: int = CombatTags.NONE
## 来源标识，用于整组移除（脱装备、光环关闭等）
var source: StringName = &""


func _init(
	p_stat: int = CombatStat.DAMAGE,
	p_kind: int = Kind.INCREASED,
	p_value: float = 0.0,
	p_required_tags: int = CombatTags.NONE,
	p_source: StringName = &""
) -> void:
	stat = p_stat
	kind = p_kind
	value = p_value
	required_tags = p_required_tags
	source = p_source


## 这条词缀对带有 tags 标签的目标是否生效。
func applies_to(tags: int) -> bool:
	return CombatTags.has_all(tags, required_tags)


## 按层数放大，用于 STACK_COUNT 类型的 Buff。
func scaled(factor: float) -> Modifier:
	return Modifier.new(stat, kind, value * factor, required_tags, source)


## 生成 PoE 风格的词缀文本，直接可以显示在装备/技能面板上。
func describe() -> String:
	var cond := ""
	if required_tags != CombatTags.NONE:
		cond = CombatTags.describe(required_tags).replace(", ", "")
	match kind:
		Kind.FLAT:
			return "增加 %s 点%s%s" % [_num(value), cond, CombatStat.stat_name(stat)]
		Kind.INCREASED:
			var verb := "提高" if value >= 0.0 else "降低"
			return "%s %.0f%% %s%s" % [verb, absf(value) * 100.0, cond, CombatStat.stat_name(stat)]
		Kind.MORE:
			var verb2 := "更多" if value >= 0.0 else "更少"
			return "%s %.0f%% %s%s" % [verb2, absf(value) * 100.0, cond, CombatStat.stat_name(stat)]
	return "?"


func _num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return "%d" % int(roundf(v))
	return "%.2f" % v
