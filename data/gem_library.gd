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
		.with_cost(6.0) \
		.with_cast_time(0.65) \
		.with_on_hit(Demo.buff_shock(), 1.0) \
		.with_projectile(150.0, 0, 0, 0) \
		.with_count(3) \
		.with_spread(ProjectileSpec.SpreadMode.FAN, 90.0, 20.0) \
		.with_wander(26.0, 0.09) \
		.with_bounce(5) \
		.with_duration(2.4, 5.0)
	g.base.base_damage = 55.0          # 1 级点伤（单发）

	# ★ 等级只有 1~5（ADR-024），每级成长≈PoE 的 4~5 级，升一级要有明显手感 ★
	# ★ 消耗的成长故意配得平（每级 +2）★ —— 伤害涨得猛、消耗涨得缓，
	#   升级才是纯粹的奖励；蓝的压力主要来自辅助宝石的倍率连乘，不该来自等级
	g.damage_per_level = 28.0          # 5 级 = 167（≈老曲线 20 级的 169）
	g.mana_per_level = 2.0             # 5 级 = 14
	return g


static func gem_fireball() -> SkillGem:
	var g := SkillGem.new(&"fireball", "火球术",
			T.FIRE | T.SPELL | T.PROJECTILE | T.AREA)
	g.short_name = "火"
	g.description = "一发直线飞行的火球，命中后点燃目标。单发伤害高，靠穿透/分叉/弹射打多目标。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(13.0) \
		.with_cast_time(0.85) \
		.with_on_hit(Demo.buff_ignite(), 1.0) \
		.with_projectile(240.0, 0, 0, 0)
	g.base.base_damage = 200.0     # 1 级点伤

	g.damage_per_level = 100.0     # 5 级 = 600（等级 1~5，每级都是一大步）
	g.mana_per_level = 4.0         # 5 级 = 29
	return g


## 电弧（Arc）—— 弹射专精的闪电法术。
## ★ PoE 里它不是投射物，是瞬发的连锁闪电；这个项目里所有"打到人"的手段
##   都走投射物管线，所以用「高速直线弹 + 天生弹射 3 次」来还原那个手感 ★
## 怪站得越密它越强 —— 这和火球（单发大伤害）、电球（铺场）是三条不同的构筑路。
static func gem_arc() -> SkillGem:
	var g := SkillGem.new(&"arc", "电弧",
			T.LIGHTNING | T.SPELL | T.PROJECTILE)
	g.short_name = "弧"
	g.description = "一道电光射向敌人，命中后自动弹射到附近的怪，天生弹射 3 次。怪越密集越强，必定附加感电。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(9.0) \
		.with_cast_time(0.70) \
		.with_on_hit(Demo.buff_shock(), 1.0) \
		.with_projectile(300.0, 0, 0, 3)
	g.base.chain_range = 170.0     # 比默认 150 稍大：电弧的定位就是"跳得远"
	g.base.base_damage = 130.0     # 1 级点伤（每一跳都是全额，4 个目标 = ×4）

	g.damage_per_level = 65.0      # 5 级 = 390
	g.mana_per_level = 3.0         # 5 级 = 21
	return g


## 寒冰弹（Frostbolt）—— 慢速穿透弹，冰系的"铺弹幕"入口。
## 飞得慢 = 同屏存在时间长，配「多重投射」能在场上铺出一片缓慢推进的冰墙。
static func gem_frostbolt() -> SkillGem:
	var g := SkillGem.new(&"frostbolt", "寒冰弹",
			T.COLD | T.SPELL | T.PROJECTILE)
	g.short_name = "寒"
	g.description = "一发缓慢飞行的寒冰弹，自带穿透 2 次，命中附加冰缓（移速 -30%）。飞得慢所以同屏弹数多，配「多重投射」铺弹幕。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(8.0) \
		.with_cast_time(0.75) \
		.with_on_hit(Demo.buff_chill(), 1.0) \
		.with_projectile(110.0, 2, 0, 0) \
		.with_duration(4.0)            # 飞得慢，活得久才穿得完整条路径
	g.base.base_damage = 150.0

	g.damage_per_level = 75.0      # 5 级 = 450
	g.mana_per_level = 3.0         # 5 级 = 20
	return g


## 冰霜脉冲（Freezing Pulse）—— 贴脸冰锥：极快、极短命、穿透一切。
## ★ 短射程就是它的身份 ★ 所以它故意**不带**【持续时间】标签 ——
##   要是能用「延长持续」把射程拉满，它就变成一个更强的寒冰弹了。
static func gem_freezing_pulse() -> SkillGem:
	var g := SkillGem.new(&"freezing_pulse", "冰霜脉冲",
			T.COLD | T.SPELL | T.PROJECTILE)
	g.short_name = "冰"
	g.description = "贴脸的冰锥：射程只有 150 像素左右，但穿透路径上的一切敌人。伤害高、消耗低、施放快 —— 敢贴脸就是赚。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(5.0) \
		.with_cast_time(0.55) \
		.with_on_hit(Demo.buff_chill(), 1.0) \
		.with_projectile(380.0, 99, 0, 0) \
		.with_duration(0.4)            # 380 × 0.4 ≈ 150 像素 —— 射程写在这两个数里
	g.base.base_damage = 190.0

	g.damage_per_level = 95.0      # 5 级 = 570
	g.mana_per_level = 2.0         # 5 级 = 13
	return g


## 全部主动技能石（背包初始化 / UI 列表用）。
## ★ 顺序 = 技能栏顺序，电球术是样板技能所以排第一格 ★
static func all_actives() -> Array:
	return [gem_spark(), gem_fireball(), gem_arc(), gem_frostbolt(), gem_freezing_pulse()]


# ============================================================ 辅助宝石

## 全部辅助宝石。★ 触媒也是（特殊的）辅助宝石 ★ —— 它们一起进奖励池和商店。
static func all_supports() -> Array:
	var out: Array = [
		support_pierce(),
		support_fork(),
		support_chain(),
		support_bounce(),
		support_multi(),
		support_faster_cast(),
		support_duration(),
		support_crit(),
		support_lightning(),
		support_cold(),
		support_inspiration(),
		support_ele_focus(),
		support_fast_proj(),
		support_slow_proj(),
		support_crit_damage(),
	]
	out.append_array(all_catalysts())
	return out


static func support_pierce() -> SupportGem:
	return _sup(&"sup_pierce", "穿透支援", "穿", T.PROJECTILE, 1.15,
		"命中后继续往前飞，不改变方向。",
		[
			M.new(S.PIERCE_COUNT, M.Kind.FLAT, 2.0, T.PROJECTILE),
			M.new(S.DAMAGE, M.Kind.MORE, -0.15, T.PROJECTILE),
		])


static func support_fork() -> SupportGem:
	return _sup(&"sup_fork", "分叉支援", "叉", T.PROJECTILE, 1.30,
		"命中后裂成 2 发，各偏 30°。分叉出来的不能再分叉。",
		[
			M.new(S.FORK_COUNT, M.Kind.FLAT, 1.0, T.PROJECTILE),
			M.new(S.DAMAGE, M.Kind.MORE, -0.20, T.PROJECTILE),
		])


static func support_chain() -> SupportGem:
	return _sup(&"sup_chain", "弹射支援", "弹", T.PROJECTILE, 1.50,
		"命中后转向下一个敌人。两只怪来回弹是单体伤害的主要来源。",
		[
			M.new(S.CHAIN_COUNT, M.Kind.FLAT, 2.0, T.PROJECTILE),
			M.new(S.DAMAGE, M.Kind.MORE, -0.25, T.PROJECTILE),
		])


static func support_bounce() -> SupportGem:
	return _sup(&"sup_bounce", "反弹支援", "反", T.PROJECTILE, 1.20,
		"撞到墙壁镜面弹开。★ 不消耗任何命中次数 ★，房间越小越强。",
		[
			M.new(S.BOUNCE_COUNT, M.Kind.FLAT, 3.0, T.PROJECTILE),
			M.new(S.DAMAGE, M.Kind.MORE, -0.15, T.PROJECTILE),
		])


static func support_multi() -> SupportGem:
	return _sup(&"sup_multi", "多重投射", "多", T.PROJECTILE, 1.40,
		"额外发射 2 发。扇面不变，只是排得更密。",
		[
			M.new(S.PROJECTILE_COUNT, M.Kind.FLAT, 2.0, T.PROJECTILE),
			M.new(S.DAMAGE, M.Kind.MORE, -0.30, T.PROJECTILE),
		])


static func support_faster_cast() -> SupportGem:
	return _sup(&"sup_faster_cast", "迅捷施法", "速", T.SPELL, 1.20,
		"施法更快 = 单位时间放出更多投射物。对电球术来说等于场上同时存在更多颗球。",
		[M.new(S.CAST_SPEED, M.Kind.INCREASED, 0.30, T.SPELL)])


## ★ 这一颗就是【持续时间】标签存在的意义 ★
## 电球术带 DURATION 标签 → 连得上；火球术没有 → 连不上。
static func support_duration() -> SupportGem:
	return _sup(&"sup_duration", "延长持续", "久", T.DURATION, 1.20,
		"技能持续时间更长。电球术的每一发都活得更久 → 在房间里弹得更久 → 打到更多次。",
		[M.new(S.DURATION, M.Kind.INCREASED, 0.45, T.DURATION)])


static func support_crit() -> SupportGem:
	return _sup(&"sup_crit", "暴击几率", "暴", T.NONE, 1.15,
		"大幅提高暴击率。任何技能都能连。",
		[M.new(S.CRIT_CHANCE, M.Kind.INCREASED, 0.90, T.NONE)])


static func support_lightning() -> SupportGem:
	return _sup(&"sup_lightning", "闪电增强", "闪", T.LIGHTNING, 1.25,
		"更多闪电伤害。这是「更多」乘区，和装备上的「提高」是分开连乘的。",
		[M.new(S.DAMAGE, M.Kind.MORE, 0.25, T.LIGHTNING)])


## 「闪电增强」的冰系镜像 —— 寒冰弹 / 冰霜脉冲吃它，电球 / 火球连不上。
static func support_cold() -> SupportGem:
	return _sup(&"sup_cold", "冰霜增强", "霜", T.COLD, 1.25,
		"更多冰霜伤害。和「闪电增强」同理，是独立连乘的「更多」乘区。",
		[M.new(S.DAMAGE, M.Kind.MORE, 0.25, T.COLD)])


## ★ 法术节魔（PoE 的「节省魔力」）—— 唯一一颗倍率**小于 1** 的辅助 ★
## 它不给任何词缀：省下来的蓝就是它的全部价值。
## 连一堆昂贵辅助之后蓝崩了，拿一个箭头位换 35% 的消耗，是构筑里的"续航税"。
static func support_inspiration() -> SupportGem:
	return _sup(&"sup_inspiration", "法术节魔", "节", T.SPELL, 0.65,
		"法术的魔力消耗大幅降低。不加伤害 —— 占一个箭头位换续航。",
		[])


## 元素集中（PoE 的 Elemental Focus）—— 吃派生标签的样板：
## 要求【元素】，而火/冰/电技能会被 normalize 自动补上元素标签 → 三系都连得上。
static func support_ele_focus() -> SupportGem:
	return _sup(&"sup_ele_focus", "元素集中", "元", T.ELEMENTAL, 1.30,
		"更多元素伤害。火焰 / 冰霜 / 闪电技能都连得上，物理技能不行。",
		[M.new(S.DAMAGE, M.Kind.MORE, 0.30, T.ELEMENTAL)])


## 快速投射（PoE 的 Faster Projectiles）—— 弹道更快 = 更快命中、飞得更远
static func support_fast_proj() -> SupportGem:
	return _sup(&"sup_fast_proj", "快速投射", "疾", T.PROJECTILE, 1.15,
		"投射物飞得更快。同样的存活时间飞得更远 —— 电球术的实际射程也会变长。",
		[M.new(S.PROJECTILE_SPEED, M.Kind.INCREASED, 0.50, T.PROJECTILE)])


## 缓速投射（PoE 的 Slower Projectiles）—— 「快速投射」的反面：
## 弹道更慢但更疼。慢弹 = 同屏存在更久，对电球术/寒冰弹这类"铺场"技能是纯赚。
static func support_slow_proj() -> SupportGem:
	return _sup(&"sup_slow_proj", "缓速投射", "缓", T.PROJECTILE, 1.25,
		"投射物更慢、但造成更多伤害。慢弹在场上飘得久，铺场流的最爱。",
		[
			M.new(S.PROJECTILE_SPEED, M.Kind.INCREASED, -0.30, T.PROJECTILE),
			M.new(S.DAMAGE, M.Kind.MORE, 0.20, T.PROJECTILE),
		])


## 暴击伤害（PoE 的 Increased Critical Damage）—— 和「暴击几率」凑一对
static func support_crit_damage() -> SupportGem:
	return _sup(&"sup_crit_damage", "暴击伤害", "爆", T.NONE, 1.20,
		"暴击时的伤害倍率 +50%（基础 ×1.5 → ×2.0）。配「暴击几率」食用最佳。",
		[M.new(S.CRIT_MULTI, M.Kind.FLAT, 0.50, T.NONE)])


# ============================================================ 触媒（特殊辅助宝石，ADR-026）

## 6 颗触媒：条件达成 → 自动触发箭头连着的法杖里的技能。
## 计数规则在 combat/catalyst_gem.gd；这里只填数据（条件种类 / 门槛 / 倍率）。
static func all_catalysts() -> Array:
	return [cat_shock(), cat_ignite(), cat_chill(), cat_hits(), cat_move(), cat_timer()]


static func cat_shock() -> CatalystGem:
	return _cat(&"cat_shock", "感电触媒", "雷", CatalystGem.Trigger.SHOCK_APPLIED, 3.0, 1.20,
		"每施加 3 次感电，触发一次连接的技能。配电球术/电弧这种感电机器最合拍。")


static func cat_ignite() -> CatalystGem:
	return _cat(&"cat_ignite", "点燃触媒", "炎", CatalystGem.Trigger.IGNITE_APPLIED, 3.0, 1.20,
		"每施加 3 次点燃，触发一次连接的技能。火球术点火，触媒补刀。")


## ★ 门槛只有 1 次，所以魔力倍率最贵 ★（冰系异常是「冰缓」，本项目没有冰冻状态）
static func cat_chill() -> CatalystGem:
	return _cat(&"cat_chill", "冰冻触媒", "凝", CatalystGem.Trigger.CHILL_APPLIED, 1.0, 1.35,
		"每施加 1 次冰缓就触发连接的技能 —— 门槛最低，代价是更贵的魔力倍率。")


static func cat_hits() -> CatalystGem:
	return _cat(&"cat_hits", "连击触媒", "连", CatalystGem.Trigger.HITS, 5.0, 1.20,
		"每击中敌人 5 次，触发一次连接的技能。多发/弹射技能攒得飞快。")


static func cat_move() -> CatalystGem:
	return _cat(&"cat_move", "疾行触媒", "行", CatalystGem.Trigger.MOVE_DISTANCE,
		20.0 * CatalystGem.PIXELS_PER_TILE, 1.20,
		"每移动 20 格（一格 = 一块地砖），触发一次连接的技能。边跑边打的走 A 流。")


static func cat_timer() -> CatalystGem:
	return _cat(&"cat_timer", "时钟触媒", "钟", CatalystGem.Trigger.INTERVAL, 5.0, 1.20,
		"每 5 秒自动触发一次连接的技能。最稳定，也最不挑构筑。")


static func _cat(id: StringName, name: String, short_name: String,
		kind: int, threshold: float, mana_mult: float, desc: String) -> CatalystGem:
	var g := CatalystGem.new(id, name, T.NONE)   # 触媒不挑技能：任何技能都能被触发
	g.short_name = short_name
	g.description = desc
	g.trigger_kind = kind
	g.threshold = threshold
	g.mana_multiplier = mana_mult
	return g


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
		mana_mult: float, desc: String, mods: Array) -> SupportGem:
	var g := SupportGem.new(id, name, required)
	g.short_name = short_name
	g.description = desc
	g.tags = required
	g.mana_multiplier = mana_mult
	# ★ 词缀的 source 由 SupportGem.build_mods() 统一填 ★
	#   这里写的是"模板"，拔宝石时靠 source 整组移除，所以不能各写各的。
	#   辅助宝石没有等级（ADR-024），数值就是这里写的数值。
	g.mods = mods
	return g
