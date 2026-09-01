class_name GemLibrary
extends RefCounted

## 宝石图鉴：所有主动技能石 + 辅助宝石的**数据**。
##
## 这里没有一行战斗逻辑。真实项目里这些应该来自 Excel/CSV 导表，
## 但结构和这里一模一样：一颗宝石 = 一堆基础值 + 一排标签 + 一条成长曲线。
##
## ★ 电球术（Spark）是这个系统的样板技能 ★
##   它把「技能石」该有的东西全用上了：多标签（法术/闪电/投射物/持续时间）、
##   等级成长、魔力消耗、施放时间、投射物速度、点伤、单次发射数量、投射物持续时间。
##
## 「电球术」就是 PoE 的 Spark 在中文版里的译名。

const M = preload("res://combat/modifier.gd")
const T = preload("res://combat/combat_tags.gd")
const S = preload("res://combat/combat_stat.gd")
const Demo = preload("res://data/demo_content.gd")


# ============================================================ 主动技能石

## ★★ 电球术（Spark）—— 标准技能石样板 ★★
##
## PoE 里电球术的手感是这样的：
##   施法 → 一次射出**一大把**电球 → 每颗都在乱窜 → 撞到墙壁弹回来 → 时间到了消失
##
## 所以它的伤害 = 单发点伤 × 发数 × 每发在场上活着的时间。
## 这带来两条和"单发大伤害"技能完全不同的构筑思路：
##   · 「投射物数量」  → 一次射更多发                        ← 所以它带【投射物】标签
##   · 「技能持续时间」→ 每发活得更久 → 弹得更久 → 打得更多  ← 所以它带【持续时间】标签
##
## ★ 它是标准样板，因为用户要求的属性它一条不落 ★
##   Tag / 等级 / 消耗 / 施放时间 / 投射物速度 / 点伤 / 单次发射数量 / 投射物持续时间
static func gem_spark() -> SkillGem:
	var g := SkillGem.new(&"spark", "电球术",
			T.LIGHTNING | T.SPELL | T.PROJECTILE | T.DURATION)
	g.short_name = "电"
	g.description = "一次射出 4 发乱窜的电球，撞墙会反弹。单发很弱、发数极多，吃「投射物数量」和「持续时间」的收益远大于吃单发伤害。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(10.0) \
		.with_cast_time(0.65) \
		.with_on_hit(Demo.buff_shock(), 1.0) \
		.with_projectile(150.0, 0, 0, 0) \
		.with_count(3) \
		.with_spread(ProjectileSpec.SpreadMode.FAN, 90.0, 20.0) \
		.with_wander(26.0, 0.09) \
		.with_bounce(5) \
		.with_duration(2.4, 5.0)
	g.base.base_damage = 55.0          # 1 级点伤（单发）

	g.damage_per_level = 6.0
	g.mana_per_level = 0.8
	return g


static func gem_fireball() -> SkillGem:
	var g := SkillGem.new(&"fireball", "火球术",
			T.FIRE | T.SPELL | T.PROJECTILE | T.AREA)
	g.short_name = "火"
	g.description = "一发直线飞行的火球，命中后点燃目标。单发伤害高，靠穿透/分叉/弹射打多目标。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(20.0) \
		.with_cast_time(0.85) \
		.with_on_hit(Demo.buff_ignite(), 1.0) \
		.with_projectile(240.0, 0, 0, 0)
	g.base.base_damage = 200.0     # 1 级点伤

	g.damage_per_level = 22.0
	g.mana_per_level = 2.0
	return g


## 全部主动技能石（背包初始化 / UI 列表用）。
## ★ 顺序 = 技能栏顺序，电球术是样板技能所以排第一格 ★
static func all_actives() -> Array:
	return [gem_spark(), gem_fireball()]


# ============================================================ 辅助宝石

static func all_supports() -> Array:
	return [
		support_pierce(),
		support_fork(),
		support_chain(),
		support_bounce(),
		support_multi(),
		support_faster_cast(),
		support_duration(),
		support_crit(),
		support_lightning(),
	]


static func support_pierce() -> SupportGem:
	return _sup(&"sup_pierce", "穿透支援", "穿", T.PROJECTILE, 1.15,
		"命中后继续往前飞，不改变方向。",
		[
			M.new(S.PIERCE_COUNT, M.Kind.FLAT, 2.0, T.PROJECTILE),
			M.new(S.DAMAGE, M.Kind.MORE, -0.15, T.PROJECTILE),
		],
		[0.0, 0.0025])


static func support_fork() -> SupportGem:
	return _sup(&"sup_fork", "分叉支援", "叉", T.PROJECTILE, 1.30,
		"命中后裂成 2 发，各偏 30°。分叉出来的不能再分叉。",
		[
			M.new(S.FORK_COUNT, M.Kind.FLAT, 1.0, T.PROJECTILE),
			M.new(S.DAMAGE, M.Kind.MORE, -0.20, T.PROJECTILE),
		],
		[0.0, 0.0025])


static func support_chain() -> SupportGem:
	return _sup(&"sup_chain", "弹射支援", "弹", T.PROJECTILE, 1.50,
		"命中后转向下一个敌人。两只怪来回弹是单体伤害的主要来源。",
		[
			M.new(S.CHAIN_COUNT, M.Kind.FLAT, 2.0, T.PROJECTILE),
			M.new(S.DAMAGE, M.Kind.MORE, -0.25, T.PROJECTILE),
		],
		[0.0, 0.0025])


static func support_bounce() -> SupportGem:
	return _sup(&"sup_bounce", "反弹支援", "反", T.PROJECTILE, 1.20,
		"撞到墙壁镜面弹开。★ 不消耗任何命中次数 ★，房间越小越强。",
		[
			M.new(S.BOUNCE_COUNT, M.Kind.FLAT, 3.0, T.PROJECTILE),
			M.new(S.DAMAGE, M.Kind.MORE, -0.15, T.PROJECTILE),
		],
		[0.0, 0.0025])


static func support_multi() -> SupportGem:
	return _sup(&"sup_multi", "多重投射", "多", T.PROJECTILE, 1.40,
		"额外发射 2 发。扇面不变，只是排得更密。",
		[
			M.new(S.PROJECTILE_COUNT, M.Kind.FLAT, 2.0, T.PROJECTILE),
			M.new(S.DAMAGE, M.Kind.MORE, -0.30, T.PROJECTILE),
		],
		[0.0, 0.0025])


static func support_faster_cast() -> SupportGem:
	return _sup(&"sup_faster_cast", "迅捷施法", "速", T.SPELL, 1.20,
		"施法更快 = 单位时间放出更多投射物。对电球术来说等于场上同时存在更多颗球。",
		[M.new(S.CAST_SPEED, M.Kind.INCREASED, 0.30, T.SPELL)],
		[0.01])


## ★ 这一颗就是【持续时间】标签存在的意义 ★
## 电球术带 DURATION 标签 → 连得上；火球术没有 → 连不上。
static func support_duration() -> SupportGem:
	return _sup(&"sup_duration", "延长持续", "久", T.DURATION, 1.20,
		"技能持续时间更长。电球术的每一发都活得更久 → 在房间里弹得更久 → 打到更多次。",
		[M.new(S.DURATION, M.Kind.INCREASED, 0.45, T.DURATION)],
		[0.01])


static func support_crit() -> SupportGem:
	return _sup(&"sup_crit", "暴击几率", "暴", T.NONE, 1.15,
		"大幅提高暴击率。任何技能都能连。",
		[M.new(S.CRIT_CHANCE, M.Kind.INCREASED, 0.90, T.NONE)],
		[0.03])


static func support_lightning() -> SupportGem:
	return _sup(&"sup_lightning", "闪电增强", "闪", T.LIGHTNING, 1.25,
		"更多闪电伤害。这是「更多」乘区，和装备上的「提高」是分开连乘的。",
		[M.new(S.DAMAGE, M.Kind.MORE, 0.25, T.LIGHTNING)],
		[0.005])


# ============================================================ 查找

## 图鉴里的全部宝石（主动 + 辅助）。每次调用都是**新的实例**。
static func all_gems() -> Array:
	var out: Array = []
	out.append_array(all_actives())
	out.append_array(all_supports())
	return out


## 按 id 造一颗新宝石。读存档时用（存档里只存 id + 等级 + 位置）。
## 找不到就返回 null —— 存档里有已经删掉的宝石时，读档方负责跳过它。
static func make_gem(id: StringName):
	for g in all_gems():
		if g.id == id:
			return g
	return null


# ---------------------------------------------------------------- 内部

static func _sup(id: StringName, name: String, short_name: String, required: int,
		mana_mult: float, desc: String, mods: Array, growth: Array = []) -> SupportGem:
	var g := SupportGem.new(id, name, required)
	g.short_name = short_name
	g.description = desc
	g.tags = required
	g.mana_multiplier = mana_mult
	# ★ 词缀的 source 由 SupportGem.build_mods() 统一填 ★
	#   这里写的是"模板"，拔宝石时靠 source 整组移除，所以不能各写各的
	g.mods = mods
	g.mod_growth = growth
	return g
