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
