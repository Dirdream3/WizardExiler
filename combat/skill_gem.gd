class_name SkillGem
extends RefCounted

## 主动技能石（PoE 的「技能宝石」）。
##
## ★ 为什么在 SkillSpec 之上还要多这一层？★
##
##   SkillSpec = 「这一次施法用什么参数」，它没有等级、不能被玩家拿在手上。
##   SkillGem  = 「玩家背包里那颗石头」：有等级、会成长、能插进插槽、能连辅助宝石。
##
## build() 就是把「当前等级的宝石」展开成一次施法要用的 SkillSpec。
## 这样等级、辅助宝石的魔力倍率这些只属于宝石的概念，不会污染战斗管线。
##
## ★ 宝石上印的那一排 Tag 同时决定两件事 ★
##   ① 角色身上哪些词缀吃得到 —— 「提高投射物伤害」要求 PROJECTILE
##   ② 哪些辅助宝石连得上   —— 「多重投射」只能连带 PROJECTILE 的技能
## 所以 Tag 填错了，一个技能的整条构筑路线就跟着错了。

var id: StringName = &""
var display_name: String = ""
## UI 格子里显示的 1 个字（背包空间很小，塞不下全名）
var short_name: String = "?"
## 一句话说明这个技能怎么打
var description: String = ""

## ★ 宝石标签 ★（法术 / 投射物 / 闪电 / 范围 / 持续时间 …）
var tags: int = CombatTags.NONE

var level: int = 1
var max_level: int = 20

## 1 级时的技能参数模板。★ 不要直接拿去用 ★ —— build() 会复制一份再按等级加成
var base: SkillSpec = null

# ---------------- 等级成长 ----------------
# PoE 的技能石升 1 级，伤害和魔力消耗一起涨。这里用最简单的线性成长；
# 以后要做成"每级一张表"（PoE 真实做法），只要改 damage_at / mana_at 两个函数。

## 每升 1 级 +N 点基础伤害
var damage_per_level: float = 0.0
## 每升 1 级 +N 点魔力消耗
var mana_per_level: float = 0.0


func _init(p_id: StringName = &"", p_name: String = "", p_tags: int = CombatTags.NONE) -> void:
	id = p_id
	display_name = p_name
	tags = p_tags
	base = SkillSpec.new()


# ---------------------------------------------------------------- 构建

## 展开成一次施法用的 SkillSpec。
##   supports —— 连在这颗主石上的辅助宝石（只用来算魔力倍率和补标签，
##               它们提供的**词缀**走 CombatEntity.skill_mods，不在这里叠）
func build(supports: Array = []) -> SkillSpec:
	var s := base.duplicate()
	s.id = id
	s.display_name = display_name
	s.tags = tags
	s.base_damage = damage_at(level)
	s.mana_cost = mana_at(level, supports)
	# 辅助宝石可以给技能补标签（比如「爆裂箭」让一个纯投射物技能也算范围技能）
	for sup in supports:
		s.tags |= (sup as SupportGem).added_tags
	return s


## 第 lv 级的点伤（技能石面板上那个「基础伤害」）
func damage_at(lv: int) -> float:
	return maxf(0.0, base.base_damage + damage_per_level * float(lv - 1))


## 第 lv 级的魔力消耗。辅助宝石的倍率是**连乘**的，
## 这就是 PoE 里"连的辅助越多，蓝越不够用"的来源。
func mana_at(lv: int, supports: Array = []) -> float:
	var cost := maxf(0.0, base.mana_cost + mana_per_level * float(lv - 1))
	for sup in supports:
		cost *= (sup as SupportGem).mana_multiplier
	return cost


func clamp_level(lv: int) -> int:
	return clampi(lv, 1, max_level)


# ---------------------------------------------------------------- 面板文本

## 技能石的属性面板（BBCode）。用户要求的那几项全在这里：
## Tag / 等级 / 消耗 / 施放时间 / 投射物速度 / 点伤 / 单次发射数量 / 投射物持续时间
func tooltip(supports: Array = []) -> String:
	# ★ 用 build() 出来的那份，而不是 base ★
	#   base 只是"1 级模板"，它身上没有标签（标签在宝石上），
	#   直接问 base.is_projectile() 会永远是 false。
	var s := build(supports)

	var l := PackedStringArray()
	l.append("[b][color=#8fd0ff]%s[/color][/b]  [color=#9a9aac]等级 %d/%d[/color]" % [
		display_name, level, max_level])
	l.append("[color=#c8a24a]【%s】[/color]" % CombatTags.describe(s.tags))
	if description != "":
		l.append("[color=#8a8a9c]%s[/color]" % description)

	l.append("[color=#7a7a8c]────────────[/color]")
	l.append("消耗 [b]%.0f[/b] 魔力    施放时间 [b]%.2f[/b] 秒" % [s.mana_cost, s.cast_time])
	l.append("点伤 [b]%.1f[/b]    暴击 %.1f%% ×%.2f" % [
		s.base_damage, s.base_crit_chance * 100.0, s.base_crit_multi])

	if s.is_projectile():
		l.append("单次发射 [b]%d[/b] 发投射物" % (1 + s.base_extra_projectiles))
		l.append("投射物速度 [b]%.0f[/b]    投射物持续时间 [b]%.2f[/b] 秒" % [
			s.projectile_speed, s.base_duration])
		if s.wander_deg > 0.0:
			l.append("飞行漂移 每 %.2f 秒 ±%.0f°" % [s.wander_interval, s.wander_deg])
		var extra := PackedStringArray()
		if s.base_pierce > 0: extra.append("穿透 %d" % s.base_pierce)
		if s.base_fork > 0:   extra.append("分叉 %d" % s.base_fork)
		if s.base_chain > 0:  extra.append("弹射 %d" % s.base_chain)
		if s.base_bounce > 0: extra.append("撞墙反弹 %d" % s.base_bounce)
		if not extra.is_empty():
			l.append("自带：" + "  ".join(extra))

	for b in s.on_hit_buffs:
		l.append("[color=#8fd45a]命中后附加：%s[/color]" % (b as BuffDef).display_name)

	# 下一级预览，让"升级"这个动作有反馈
	if level < max_level:
		l.append("[color=#7a7a8c]升到 %d 级：点伤 %.1f，消耗 %.0f[/color]" % [
			level + 1, damage_at(level + 1), mana_at(level + 1, supports)])
	return "\n".join(l)
