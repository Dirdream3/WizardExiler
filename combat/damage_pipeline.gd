class_name DamagePipeline
extends RefCounted

## 伤害结算管线 —— 固定五步，顺序不能变。
##
##   ① 技能基础伤害
##   ② 攻方词缀四段式：(base + flat) × (1 + Σ提高) × Π(1 + 更多)
##   ③ 暴击
##   ④ 守方减免：护甲（物理）/ 抗性（元素、混沌）
##   ⑤ 守方「承受伤害」词缀
##
## 把顺序写死在一个地方，是为了保证战斗、DoT、伤害面板、离线计算器
## 用的是**同一套算法**。有第二处实现，数值就一定会对不上。


## 结算一次命中。
##   rng 传 null 表示不掷骰（用于伤害面板显示"非暴击伤害"）
static func compute_hit(
	attacker: CombatEntity,
	defender: CombatEntity,
	skill: SkillSpec,
	rng: RandomNumberGenerator = null
) -> HitResult:
	var r := HitResult.new()
	r.tags = skill.hit_tags()
	r.base = skill.base_damage
	r.steps.append("① 基础伤害 %.1f  【%s】" % [r.base, CombatTags.describe(r.tags)])

	# ② 攻方词缀
	var bd := attacker.stat_breakdown(CombatStat.DAMAGE, r.tags, r.base)
	r.after_mods = bd["total"]
	r.steps.append("② 词缀 " + StatSet.format_breakdown(bd))
	for m in bd["mods"]:
		r.steps.append("      · " + (m as Modifier).describe())

	# ③ 暴击
	var chance := clampf(attacker.get_stat(CombatStat.CRIT_CHANCE, r.tags, skill.base_crit_chance), 0.0, 1.0)
	r.crit_multi = attacker.get_stat(CombatStat.CRIT_MULTI, r.tags, skill.base_crit_multi)
	r.is_crit = rng != null and rng.randf() < chance
	r.after_crit = r.after_mods * (r.crit_multi if r.is_crit else 1.0)
	if r.is_crit:
		r.steps.append("③ 暴击！ ×%.2f → %.1f" % [r.crit_multi, r.after_crit])
	else:
		r.steps.append("③ 未暴击（%.1f%% 几率，暴伤 ×%.2f）" % [chance * 100.0, r.crit_multi])

	# ④ 守方减免
	r.mitigation = mitigation_against(defender, r.tags, r.after_crit)
	r.after_defence = r.after_crit * (1.0 - r.mitigation)
	r.steps.append("④ 减免 %.1f%% → %.1f" % [r.mitigation * 100.0, r.after_defence])

	# ⑤ 守方「承受伤害」词缀（也走四段式，所以「受到的伤害降低 20%」写成 INCREASED -0.2）
	var taken := defender.stat_breakdown(CombatStat.DAMAGE_TAKEN, r.tags, r.after_defence)
	r.total = maxf(0.0, taken["total"])
	r.steps.append("⑤ 承受伤害词缀 → 最终 %.1f" % r.total)

	return r


## 防守方对某类伤害的总减免比例（0~1）。
##   物理 → 护甲，PoE 公式：armour / (armour + 5 × 伤害)
##          注意它跟**这一击的大小**有关：护甲挡小刀很有效，挡大招几乎无效
##   元素/混沌 → 对应抗性，上限 75%
static func mitigation_against(defender: CombatEntity, tags: int, incoming: float) -> float:
	if tags & CombatTags.PHYSICAL:
		var armour := defender.get_stat(CombatStat.ARMOUR, tags)
		if armour <= 0.0 or incoming <= 0.0:
			return 0.0
		var red := armour / (armour + 5.0 * incoming)
		return minf(red, CombatStat.ARMOUR_REDUCTION_CAP)
	return defender.resist_for(tags)


## 期望伤害（不掷骰，把暴击按几率摊进去）。
## 做 DPS 面板和"Path of Building"式计算器时用这个，不要用随机结果去平均。
static func average_hit(attacker: CombatEntity, defender: CombatEntity, skill: SkillSpec) -> float:
	var r := compute_hit(attacker, defender, skill, null)
	var chance := clampf(attacker.get_stat(CombatStat.CRIT_CHANCE, r.tags, skill.base_crit_chance), 0.0, 1.0)
	var crit_factor := 1.0 + chance * (r.crit_multi - 1.0)
	# 抗性是固定比例，所以暴击倍率可以直接乘回来。
	# 护甲不是（减免率跟这一击的大小有关），物理技能这里会略微高估，
	# 要精确的话得对暴击/非暴击分别跑一次 compute_hit 再加权。
	return r.total * crit_factor


## 每秒能出手几次 = 速度倍率 ÷ 基础施放/攻击时间。
## 「提高施法速度」是缩短施放时间，所以是除法。
static func actions_per_second(attacker: CombatEntity, skill: SkillSpec) -> float:
	var speed_stat := CombatStat.CAST_SPEED if (skill.tags & CombatTags.SPELL) else CombatStat.ATTACK_SPEED
	var speed := attacker.get_stat(speed_stat, skill.hit_tags())
	if speed <= 0.0 or skill.cast_time <= 0.0:
		return 0.0
	return speed / skill.cast_time


## 每秒伤害。
##
## ★ 注意这是「单发」DPS，和 PoE 面板一样 ★
##   电球术一次射 4 发，但面板不会把 DPS ×4 —— 因为 4 发不一定都能命中。
##   要看"理论满命中"就自己乘 ProjectileSpec.shot_count()。
static func dps(attacker: CombatEntity, defender: CombatEntity, skill: SkillSpec) -> float:
	var rate := actions_per_second(attacker, skill)
	if rate <= 0.0:
		return 0.0
	return average_hit(attacker, defender, skill) * rate


## 推进一个单位的 Buff 计时，并结算本帧到期的 DoT。
## 返回 [{buff: StringName, raw: float, damage: float}, ...]
static func resolve_dots(entity: CombatEntity, delta: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for inst in entity.tick_buffs(delta):
		var raw := inst.tick_damage()
		var tags := inst.def.dot_tags | CombatTags.DOT
		# DoT 不吃护甲（护甲只减命中），但吃抗性
		var mit := 0.0
		if not (tags & CombatTags.PHYSICAL):
			mit = entity.resist_for(tags)
		var after := raw * (1.0 - mit)
		var dmg: float = maxf(0.0, entity.stat_breakdown(CombatStat.DAMAGE_TAKEN, tags, after)["total"])
		entity.take_damage(dmg)
		events.append({"buff": inst.def.id, "raw": raw, "damage": dmg})
	return events
