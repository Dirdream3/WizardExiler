class_name DemoContent
extends RefCounted

## 示例内容：Buff、怪物技能、角色。
##
## 注意这里全是**数据**，没有一行战斗逻辑。真实项目里这些应该来自
## Excel/CSV 导出的表，或者 Godot 的 .tres 资源文件 —— 一旦词缀上千条，
## 手写就不现实了。但结构跟这里是一模一样的。
##
## ★ 玩家能用的技能石和辅助宝石在 data/gem_library.gd ★
##   分开是为了不产生循环依赖：gem_library 要用这里的 Buff（点燃/感电），
##   所以这个文件反过来**不能**引用 gem_library。

# 用 preload 起短别名，填数据时少敲一半的字
const M = preload("res://combat/modifier.gd")
const T = preload("res://combat/combat_tags.gd")
const S = preload("res://combat/combat_stat.gd")


# =============== Buff ===============

static func buff_frenzy() -> BuffDef:
	# 刷新型增益：重复施加只续时间，不叠强度
	return BuffDef.new(&"frenzy", "狂怒") \
		.with_duration(4.0) \
		.with_stacking(BuffDef.StackRule.REFRESH) \
		.with_mod(M.new(S.ATTACK_SPEED, M.Kind.INCREASED, 0.20)) \
		.with_mod(M.new(S.MOVE_SPEED, M.Kind.INCREASED, 0.15))


static func buff_elemental_aura(power: float = 0.25) -> BuffDef:
	# 光环：永久 + 取最强。队友重复上不会叠加
	var d := BuffDef.new(&"aura_elemental", "元素祝福") \
		.with_duration(-1.0) \
		.with_stacking(BuffDef.StackRule.HIGHEST) \
		.with_mod(M.new(S.DAMAGE, M.Kind.MORE, power, T.ELEMENTAL))
	return d


static func buff_scorch() -> BuffDef:
	# 叠层型减益：效果 × 层数，封顶 5 层
	return BuffDef.new(&"scorch", "灼烧") \
		.as_debuff() \
		.with_duration(6.0) \
		.with_stacking(BuffDef.StackRule.STACK_COUNT, 5) \
		.with_mod(M.new(S.DAMAGE_TAKEN, M.Kind.INCREASED, 0.10, T.FIRE))


static func buff_shock() -> BuffDef:
	# 感电：PoE 里闪电伤害的标志性异常状态 —— 提高目标承受的**所有**伤害。
	# 注意 required_tags 是 NONE（不是 LIGHTNING）：感电放大的是全部伤害，
	# 不只是闪电伤害。这一个参数填错，感电流派的收益就全错了。
	return BuffDef.new(&"shock", "感电") \
		.as_debuff() \
		.with_duration(3.0) \
		.with_stacking(BuffDef.StackRule.STACK_COUNT, 3) \
		.with_mod(M.new(S.DAMAGE_TAKEN, M.Kind.INCREASED, 0.08, T.NONE))


static func buff_chill() -> BuffDef:
	# 冰缓：PoE 冰霜伤害的标志性异常状态 —— 减慢目标的行动。
	# ★ 挂在「移动速度」上，而不是攻击速度 ★
	#   普通怪从没设过 ATTACK_SPEED 基础值（是 0），在 0 上"降低 30%"还是 0，
	#   等于一条恒真数据；而追击速度走属性系统后，减移速是真的能让怪追不上你。
	# REFRESH：重复命中只续时间不叠层（PoE 的冰缓也不叠层，只取最强）。
	return BuffDef.new(&"chill", "冰缓") \
		.as_debuff() \
		.with_duration(2.5) \
		.with_stacking(BuffDef.StackRule.REFRESH) \
		.with_mod(M.new(S.MOVE_SPEED, M.Kind.INCREASED, -0.30))


static func buff_ignite() -> BuffDef:
	# 独立计时的 DoT：每个来源各上一份，全部同时结算
	return BuffDef.new(&"ignite", "点燃") \
		.as_debuff() \
		.with_duration(4.0) \
		.with_stacking(BuffDef.StackRule.INDEPENDENT) \
		.with_dot(40.0, 0.5, T.FIRE | T.AILMENT)

static func buff_essence_drain() -> BuffDef:
	# 精髓吸取（Essence Drain）的混沌 DoT —— 这颗技能的伤害大头。
	# ★ REFRESH 不叠层 ★：PoE 里精髓吸取重复命中同一目标只刷新，不叠加；
	#   要是 INDEPENDENT，配「多重投射」一发 3 颗全中就是 3 倍 DoT，数值直接崩。
	# 伤害在施加瞬间快照施法者的混沌 / 持续伤害加成（apply_buff 里做的）。
	# 标签只有 CHAOS：它不是"异常状态"（不像点燃），所以不带 AILMENT。
	return BuffDef.new(&"essence_drain", "精髓吸取") 		.as_debuff() 		.with_duration(4.0) 		.with_stacking(BuffDef.StackRule.REFRESH) 		.with_dot(45.0, 0.5, T.CHAOS)


static func buff_soulrend() -> BuffDef:
	# 灵魂撕裂（Soulrend）的混沌 DoT：比精髓吸取轻（25 vs 45 / 半秒、3 秒 vs 4 秒），
	# 因为它的弹穿透一切、一发能挂一整排 —— 单体重、群体轻，两颗混沌技能才各有分工。
	# ★ 和精髓吸取是两个 id ★ → 两者能同时挂在同一只怪身上（不同 id 互不刷新）。
	return BuffDef.new(&"soulrend", "灵魂撕裂") \
		.as_debuff() \
		.with_duration(3.0) \
		.with_stacking(BuffDef.StackRule.REFRESH) \
		.with_dot(25.0, 0.5, T.CHAOS)


static func buff_contagion() -> BuffDef:
	# 瘟疫（Contagion）的混沌 DoT：范围技能一次挂一片。比精髓吸取轻（30 vs 45），
	# 因为它是"圈里每个人一份"；和另外两个混沌 DoT 都是不同 id，能叠着挂。
	return BuffDef.new(&"contagion", "瘟疫") \
		.as_debuff() \
		.with_duration(4.0) \
		.with_stacking(BuffDef.StackRule.REFRESH) \
		.with_dot(30.0, 0.5, T.CHAOS)


static func buff_poison() -> BuffDef:
	# 中毒（毒蛇打击）：★ INDEPENDENT 独立叠加 ★ —— PoE 的中毒就是每一击各上一份、全部同时结算。
	# 单份很轻（10/半秒、2 秒），靠出手频率堆：攻速越快毒越多，这是它和精髓吸取（REFRESH）的分工。
	return BuffDef.new(&"poison", "中毒") \
		.as_debuff() \
		.with_duration(2.0) \
		.with_stacking(BuffDef.StackRule.INDEPENDENT) \
		.with_dot(10.0, 0.5, T.CHAOS | T.AILMENT)


static func buff_incinerate_ramp() -> BuffDef:
	# 焚烧的蓄力（ADR-036）：引导每放一段叠 1 层，每层火焰法术伤害 +12%、最多 8 层（+96%）；
	# 0.6 秒不续就掉 —— 松手 / 没蓝 = 蓄力归零。这是 PoE 焚烧"越烧越疼"的手感。
	return BuffDef.new(&"incinerate_ramp", "焚烧蓄力") \
		.with_duration(0.6) \
		.with_stacking(BuffDef.StackRule.STACK_COUNT, 8) \
		.with_mod(M.new(S.DAMAGE, M.Kind.INCREASED, 0.12, T.FIRE | T.SPELL))


static func buff_scorching_claw() -> BuffDef:
	# ★ 精英怪「灼热之爪」挂在玩家身上的火 DoT ★ —— 故意不复用 buff_ignite：
	#   玩家的点燃是 40/半秒、独立叠加，那是打怪用的量级；
	#   怪打玩家的版本要温和（20/半秒、REFRESH 不叠）—— 被两只爪怪围住不该一秒蒸发。
	#   分开两条定义，将来调玩家的点燃也不会连带改动精英怪的强度。
	return BuffDef.new(&"scorching_claw", "灼热") 		.as_debuff() 		.with_duration(3.0) 		.with_stacking(BuffDef.StackRule.REFRESH) 		.with_dot(20.0, 0.5, T.FIRE | T.AILMENT)


# =============== 技能 ===============
#
# 玩家的技能（电球术 / 火球术）已经搬去 data/gem_library.gd 做成技能石了。
# 这里只留怪物和测试用的、没有宝石概念的技能。

static func skill_heavy_strike() -> SkillSpec:
	return SkillSpec.new(&"heavy_strike", "重击", 300.0,
			T.PHYSICAL | T.ATTACK | T.MELEE) \
		.with_crit(0.05, 1.5)


## 怪物的近战攻击
static func skill_bone_slash() -> SkillSpec:
	return SkillSpec.new(&"bone_slash", "骨爪", 140.0,
			T.PHYSICAL | T.ATTACK | T.MELEE) \
		.with_crit(0.05, 1.5)


# =============== 角色 ===============

static func make_player() -> CombatEntity:
	var p := CombatEntity.new(&"player", "玩家")
	p.set_base(S.MAX_LIFE, 1000.0)
	p.set_base(S.MAX_MANA, 200.0)
	p.set_base(S.ATTACK_SPEED, 1.0)
	p.set_base(S.CAST_SPEED, 1.0)
	p.set_base(S.MOVE_SPEED, 92.0)      # 像素/秒
	p.set_base(S.ARMOUR, 400.0)

	# 天赋 / 被动树。★ 这一层不随背包变化 ★
	p.gear_mods \
		.add(M.new(S.DAMAGE, M.Kind.INCREASED, 0.40, T.PROJECTILE, &"passive_tree")) \
		.add(M.new(S.CRIT_CHANCE, M.Kind.INCREASED, 2.00, T.NONE, &"passive_tree"))

	# 开局身上带的那套装备。
	# ★ 这里装一遍是为了让"不带背包的纯数值场景"（单元测试、离线 DPS 计算器）
	#   也能拿到一个装备齐全的角色 ★
	# ★ 注意口径（ADR-023）★：游戏里法杖的词缀走 skill_mods、只对槽里的技能生效；
	#   这个基准角色把橡木法杖的词缀也放进 equip_mods，等价于"正在用橡木法杖里的
	#   技能"的总加成 —— 老的伤害断言全部原样成立；只是拿它算"别根法杖里的
	#   技能"时会比游戏内偏高，写新断言时留意。
	for e in EquipLibrary.default_loadout():
		p.equip_mods.add_all((e as EquipItem).build_mods())

	return p.refill()


static func make_monster() -> CombatEntity:
	var m := CombatEntity.new(&"skeleton", "骷髅战士")
	m.set_base(S.MAX_LIFE, 1500.0)
	m.set_base(S.ARMOUR, 2000.0)
	m.set_base(S.FIRE_RESIST, 0.40)
	m.set_base(S.COLD_RESIST, 0.20)
	m.set_base(S.LIGHTNING_RESIST, 0.20)
	m.set_base(S.CHAOS_RESIST, -0.30)   # 负抗性 = 额外承伤
	return m.refill()
