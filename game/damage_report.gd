class_name DamageReport
extends RefCounted

## 伤害计算详情面板的文本生成（游戏里按 Tab 打开）。
##
## 这份报告完全由 combat/ 里的纯逻辑算出来，和画面没有任何关系 ——
## 把它抽出去就是一个 Path of Building 式的离线计算器。

const S = preload("res://combat/combat_stat.gd")
const T = preload("res://combat/combat_tags.gd")


static func build(attacker: CombatEntity, defender: CombatEntity, skill: SkillSpec) -> String:
	var lines := PackedStringArray()

	lines.append(_h("天赋 / 被动"))
	_list_mods(lines, attacker.gear_mods)

	lines.append(_h("装备（背包里放着就生效）"))
	_list_mods(lines, attacker.equip_mods)

	lines.append(_h("辅助宝石（箭头连着当前技能的）"))
	_list_mods(lines, attacker.skill_mods)

	lines.append(_h("增益 / 减益"))
	var any := false
	for inst in attacker.buffs.active():
		lines.append("  · [color=#8fd45a]%s[/color]" % (inst as BuffInstance).describe())
		for m in (inst as BuffInstance).effective_mods():
			lines.append("      %s" % (m as Modifier).describe())
		any = true
	if defender != null:
		for inst in defender.buffs.active():
			lines.append("  · [color=#e07070]目标身上: %s[/color]" % (inst as BuffInstance).describe())
			any = true
	if not any:
		lines.append("  （无）")

	if skill.is_area():
		lines.append(_h("范围"))
		var asp := AreaSpec.build(attacker, skill)
		var area_bd := attacker.stat_breakdown(CombatStat.AREA_OF_EFFECT, skill.hit_tags(), 1.0)
		lines.append("  半径 %.0f（基础 %.0f × √%.2f）    %s    %s" % [
			asp.radius, skill.area_radius, area_bd["total"],
			"指哪打哪，射程 %.0f" % asp.range if asp.origin == AreaSpec.Origin.TARGET else "以自己为中心",
			"延迟 %.2fs" % asp.delay if asp.delay > 0.0 else "瞬发"])
		lines.append("  [color=#7a7a8c]圈里的敌人各吃一次完整的五步命中；「范围效果」放大的是面积，半径按平方根走[/color]")

	if skill.is_projectile():
		lines.append(_h("投射物"))
		var ps := ProjectileSpec.build(attacker, skill)
		lines.append("  发射数量 %d    速度 %.0f    存活 %.1fs" % [
			ps.shot_count(), ps.speed, ps.duration])
		var spread_text :="扇面 %.0f°（均分）" % ps.spread_arc_deg \
			if ps.spread_mode == ProjectileSpec.SpreadMode.FAN \
			else "相邻夹角 %.0f°" % ps.spread_deg
		lines.append("  散射：%s    随机抖动 ±%.0f°    发射点位移 %.0f" % [
			spread_text, ps.jitter_deg, ps.spawn_jitter])
		if ps.wander_deg > 0.0:
			lines.append("  飞行漂移：每 %.2fs 转 ±%.0f°  [color=#7a7a8c](电球术乱窜的来源)[/color]" % [
				ps.wander_interval, ps.wander_deg])
		lines.append("  穿透 %d 次%s    分叉 %d 次    连锁 %d 次（不回头、+500%% 速度）    弹射 %d 次（半径 %.0f）    撞墙反弹 %d 次" % [
			ps.pierce_count,
			("" if ps.pierce_chance <= 0.0 else "（+%.0f%% 几率）" % (ps.pierce_chance * 100.0)),
			ps.fork_count, ps.link_count, ps.chain_count, ps.chain_range, ps.bounce_count])
		lines.append("  [color=#7a7a8c]命中优先级：穿透 > 分叉 > 连锁 > 弹射；撞墙反弹是独立次数，不占命中[/color]")

	if defender == null:
		lines.append(_h("附近没有敌人"))
		return "\n".join(lines)

	lines.append(_h("%s → %s" % [skill.display_name, defender.display_name]))
	var r := DamagePipeline.compute_hit(attacker, defender, skill, null)
	for step in r.steps:
		lines.append("  " + step)
	lines.append("  [color=#ff9a55][b]→ 非暴击伤害 %.0f[/b][/color]" % r.total)

	lines.append(_h("DPS"))
	var chance: float = clampf(attacker.get_stat(S.CRIT_CHANCE, r.tags, skill.base_crit_chance), 0.0, 1.0)
	lines.append("  暴击 %.1f%%  暴伤 ×%.2f" % [chance * 100.0, r.crit_multi])
	lines.append("  期望单次伤害 [b]%.0f[/b]" % DamagePipeline.average_hit(attacker, defender, skill))
	lines.append("  施放时间 %.2fs  ×施法速度 %.2f  →  %.2f 次/秒" % [
		skill.cast_time,
		attacker.get_stat(S.CAST_SPEED, r.tags),
		DamagePipeline.actions_per_second(attacker, skill)])
	lines.append("  [color=#ffd35a][b]DPS = %.0f[/b][/color]  [color=#7a7a8c](单发；电球术一次射多发，全中就是它的倍数)[/color]"
			% DamagePipeline.dps(attacker, defender, skill))

	lines.append(_h("目标防御"))
	lines.append("  生命 %.0f / %.0f" % [defender.life, defender.max_life()])
	lines.append("  火 %.0f%%  冰 %.0f%%  电 %.0f%%  混沌 %.0f%%" % [
		defender.get_stat(S.FIRE_RESIST) * 100.0,
		defender.get_stat(S.COLD_RESIST) * 100.0,
		defender.get_stat(S.LIGHTNING_RESIST) * 100.0,
		defender.get_stat(S.CHAOS_RESIST) * 100.0,
	])
	lines.append("  护甲 %.0f  [color=#7a7a8c](挡 100 点物理 → %.0f%%；挡 1000 点 → %.0f%%)[/color]" % [
		defender.get_stat(S.ARMOUR),
		DamagePipeline.mitigation_against(defender, T.PHYSICAL, 100.0) * 100.0,
		DamagePipeline.mitigation_against(defender, T.PHYSICAL, 1000.0) * 100.0,
	])

	return "\n".join(lines)


static func _list_mods(lines: PackedStringArray, set: StatSet) -> void:
	if set == null or set.size() == 0:
		lines.append("  （无）")
		return
	for m in set.all():
		lines.append("  · %s   [color=#7a7a8c](%s)[/color]" % [
			(m as Modifier).describe(), (m as Modifier).source])


static func _h(title: String) -> String:
	return "\n[color=#6cc6f0][b]— %s —[/b][/color]" % title
