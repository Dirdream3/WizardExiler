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
	g.description = "一发直线飞行的火球，命中后点燃目标并在命中点炸开（半径 45），炸到周围的其他敌人。单发重、自带溅射。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(13.0) \
		.with_cast_time(0.85) \
		.with_on_hit(Demo.buff_ignite(), 1.0) \
		.with_projectile(240.0, 0, 0, 0) \
		.with_explosion(45.0)             # ★ 命中爆炸（ADR-036）：AREA 标签终于有实际意义
	g.base.base_damage = 200.0     # 1 级点伤

	g.damage_per_level = 100.0     # 5 级 = 600（等级 1~5，每级都是一大步）
	g.mana_per_level = 4.0         # 5 级 = 29
	return g


## 电弧（Arc）—— ★ 连锁专精 ★（ADR-035）。
## PoE 里它是瞬发的连锁闪电：跳向**没打过**的敌人、永不回头。本项目用「高速弹 + 天生连锁 3 次」还原：
## 第一段正常飞，命中后每一跳都 +500% 速度（几乎瞬移）、只挑没打过的。
## 和「弹射」（翻滚岩浆 / 弹射支援：可以两只怪来回弹）是两套规则。怪站得越密它越强。
static func gem_arc() -> SkillGem:
	var g := SkillGem.new(&"arc", "电弧",
			T.LIGHTNING | T.SPELL | T.PROJECTILE)
	g.short_name = "弧"
	g.description = "一道电光射向敌人，命中后连锁跳向附近没打过的怪（天生连锁 3 次，跳跃几乎瞬间、永不回头）。怪越密集越强，必定附加感电。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(9.0) \
		.with_cast_time(0.70) \
		.with_on_hit(Demo.buff_shock(), 1.0) \
		.with_projectile(300.0, 0, 0, 0) \
		.with_link(3)
	g.base.chain_range = 170.0     # 比默认 150 稍大：电弧的定位就是"跳得远"（连锁和弹射共用这个半径）
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


## 冰矛（Ice Spear）—— 暴击专精的冰系快弹。
## PoE 里冰矛飞出一段距离后会"变形"成暴击率暴涨的第二形态；本项目没有变形机制，
## 直接把它做成**天生高暴击**（20%，是别的技能的 3 倍多）的高速穿透弹 ——
## 配「暴击几率」+「暴击伤害」两颗辅助，是和"多发铺场""弹射打群"并列的第三条路：单发爆头。
static func gem_ice_spear() -> SkillGem:
	var g := SkillGem.new(&"ice_spear", "冰矛",
			T.COLD | T.SPELL | T.PROJECTILE)
	g.short_name = "矛"
	g.description = "冰矛飞出 70 像素后变形：速度翻倍、暴击率 ×3（20% → 60%）。近处平平无奇，远处一矛爆头。自带穿透 1、冰缓。"

	g.base 		.with_crit(0.20, 1.5) 		.with_cost(9.0) 		.with_cast_time(0.70) 		.with_on_hit(Demo.buff_chill(), 1.0) 		.with_projectile(300.0, 1, 0, 0) \
		.with_transform(70.0, 2.0, 3.0)   # ★ 飞 70 像素后变形（ADR-036）：速度 ×2、暴击率 ×3（20% → 60%）
	g.base.base_damage = 140.0

	g.damage_per_level = 70.0      # 5 级 = 420
	g.mana_per_level = 3.0         # 5 级 = 21
	return g


## 翻滚岩浆（Rolling Magma）—— 沿地面"弹跳"前进的火球。
## PoE 里它落地后会连着弹跳好几次；本项目用「慢速弹 + 天生弹射 2 次」还原：
## 每命中一只就转向下一只，所以它是**火系里的打群技能**（火球是单发直线、焚烧是贴脸）。
static func gem_rolling_magma() -> SkillGem:
	var g := SkillGem.new(&"rolling_magma", "翻滚岩浆",
			T.FIRE | T.SPELL | T.PROJECTILE | T.AREA)
	g.short_name = "岩"
	g.description = "一团缓慢滚动的岩浆，命中后弹向附近的敌人（天生弹射 2 次），每一跳都点燃、都在落点炸一圈（半径 40）。火系里打群用它。"

	g.base 		.with_crit(0.06, 1.5) 		.with_cost(12.0) 		.with_cast_time(0.80) 		.with_on_hit(Demo.buff_ignite(), 1.0) 		.with_projectile(140.0, 0, 0, 2) 		.with_duration(3.0) \
		.with_explosion(40.0)            # 每一跳都炸一圈（ADR-036）：弹射 + 溅射 = 火系打群
	g.base.chain_range = 120.0     # 弹跳距离短：岩浆是"滚"过去的，不是电弧那种隔空跳
	g.base.base_damage = 210.0

	g.damage_per_level = 105.0     # 5 级 = 630
	g.mana_per_level = 4.0         # 5 级 = 28
	return g


## 焚烧（Incinerate）—— 喷火器：★ 引导的扇形范围技能（ADR-033 / 034）★ 按住就是一条火舌：
## 以自己为中心、朝鼠标方向张开 40°、长 110 像素的扇形，每 0.22 秒一段、扇形里全中、每段扣 3 蓝。
## PoE 3.3 之后它就不是投射物了（Spell, AoE, Fire, Channelling）—— 之前用"短命穿透弹"冒充，现在照原样。
## 单发很弱，靠出手频率堆点燃 —— 配「点燃触媒」（每 3 次点燃触发一次）是它最自然的搭档。
static func gem_incinerate() -> SkillGem:
	var g := SkillGem.new(&"incinerate", "焚烧",
			T.FIRE | T.SPELL | T.AREA)
	g.short_name = "焚"
	g.description = "按住就是一条火舌（30° 扇形、长 130），每 0.22 秒一段、每段 3 蓝。★ 越烧越疼 ★：每放一段叠一层蓄力（+12% 火焰法术伤害，最多 8 层），松手就归零。"

	g.base \
		.with_crit(0.05, 1.5) \
		.with_cost(3.0) \
		.with_cast_time(0.22) \
		.with_channel() \
		.with_on_hit(Demo.buff_ignite(), 0.35) \
		.with_area(130.0, AreaSpec.Origin.SELF) \
		.with_arc(30.0) \
		.with_ramp(Demo.buff_incinerate_ramp())   # ★ 蓄力（ADR-036）：每段 +12% 火焰法术伤害，最多 8 层
	g.base.base_damage = 48.0

	g.damage_per_level = 21.0      # 5 级 = 132（≥ 1 级的 40%，升级有手感）
	g.mana_per_level = 1.0         # 5 级 = 7
	return g


## 闪电之触（Lightning Tendrils）—— 贴脸的电弧扇：★ 引导的扇形范围技能（ADR-033 / 034）★
## 以自己为中心、60° 扇形、长 120 像素，每 0.4 秒一段、扇形里全部感电。PoE 里它就是 Spell, AoE, Lightning,
## Channelling，不是投射物。和焚烧同是贴脸引导，但它扇面更宽、每段更重 → 打一群怪时感电叠得飞快。
static func gem_lightning_tendrils() -> SkillGem:
	var g := SkillGem.new(&"lightning_tendrils", "闪电之触",
			T.LIGHTNING | T.SPELL | T.AREA)
	g.short_name = "触"
	g.description = "从指尖放出一大片电光（100° 的宽扇形、长 90），每 0.4 秒一段、每段 4 蓝，扇形里全部感电。和焚烧相反：宽而短，贴脸围殴时用。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(4.0) \
		.with_cast_time(0.40) \
		.with_channel() \
		.with_on_hit(Demo.buff_shock(), 1.0) \
		.with_area(90.0, AreaSpec.Origin.SELF) \
		.with_arc(100.0)
	g.base.base_damage = 85.0

	g.damage_per_level = 38.0      # 5 级 = 237
	g.mana_per_level = 1.0         # 5 级 = 8
	return g


## 精髓吸取（Essence Drain）—— 混沌 DoT 弹：命中一下不疼，疼的是之后 4 秒。
## 它开的是第五条路：**混沌**。骷髅的混沌抗性是 -30%（负抗性 = 额外承伤），
## 而火/冰/电三系的辅助（闪电增强 / 冰霜增强 / 元素集中）它一颗都连不上 ——
## 只吃「虚空操纵」和通用辅助，是一条和元素流完全分开的构筑。
## ★ 故意不带【持续时间】标签 ★ —— 本项目的 DURATION 属性只延长投射物存活，
##   不改 Buff 时长；带了标签「延长持续」连上去会变成"拉长弹的飞行时间"，误导人。
static func gem_essence_drain() -> SkillGem:
	var g := SkillGem.new(&"essence_drain", "精髓吸取",
			T.CHAOS | T.SPELL | T.PROJECTILE)
	g.short_name = "髓"
	g.description = "一发混沌弹，命中本身不疼，但目标会在 4 秒里持续掉血（每半秒 45 点，快照你的混沌伤害加成）。重复命中只刷新不叠加。骷髅的混沌抗性是负的，打它格外疼。"

	g.base 		.with_crit(0.05, 1.5) 		.with_cost(11.0) 		.with_cast_time(0.75) 		.with_on_hit(Demo.buff_essence_drain(), 1.0) 		.with_projectile(200.0, 0, 0, 0) 		.with_duration(2.5)
	g.base.base_damage = 90.0

	g.damage_per_level = 45.0      # 5 级 = 270（命中部分；DoT 部分吃混沌伤害加成）
	g.mana_per_level = 3.0         # 5 级 = 23
	return g


## 裂雷之矛（Crackling Lance）—— 一道贯穿全场的雷矛：★ 光束型范围技能（ADR-034）★
## 以自己为中心、14° 的细扇形、长 320 像素 —— 就是一条线。线上的全中、必定感电。
## PoE 里它是 Spell, AoE, Lightning（不是投射物），之前用"穿透一切的高速弹"冒充，现在照原样。
## 单发极重、施放慢、贵：把怪引成一列再放。它没有"充能强度"机制，直接给大单发。
static func gem_crackling_lance() -> SkillGem:
	var g := SkillGem.new(&"crackling_lance", "裂雷之矛",
			T.LIGHTNING | T.SPELL | T.AREA)
	g.short_name = "雷"
	g.description = "朝鼠标方向劈出一道 320 像素长的雷矛（14° 的细扇形，就是一条线），线上的全中、必定感电。单发极重但施放慢、消耗高 —— 把怪引成一列再放。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(14.0) \
		.with_cast_time(0.85) \
		.with_on_hit(Demo.buff_shock(), 1.0) \
		.with_area(320.0, AreaSpec.Origin.SELF) \
		.with_arc(14.0)
	g.base.base_damage = 260.0

	g.damage_per_level = 130.0     # 5 级 = 780
	g.mana_per_level = 4.0         # 5 级 = 30
	return g


## 寒冬之眼（Eye of Winter）—— 天生分叉的冰弹：命中后裂成两片继续穿。
## PoE 里它飞行途中会朝四周放冰片；本项目用「穿透 2 + 天生分叉 1」还原"越打越散"的手感。
## 它是唯一天生带分叉的技能 —— 配「分叉支援」再叠一次 = 一发变四发。
static func gem_eye_of_winter() -> SkillGem:
	var g := SkillGem.new(&"eye_of_winter", "寒冬之眼",
			T.COLD | T.SPELL | T.PROJECTILE)
	g.short_name = "眼"
	g.description = "一颗冰眼，命中后裂成两片各偏 30° 继续飞（天生分叉 1 次），每片还能穿透 2 次，全部附加冰缓。唯一天生分叉的技能。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(10.0) \
		.with_cast_time(0.75) \
		.with_on_hit(Demo.buff_chill(), 1.0) \
		.with_projectile(190.0, 2, 1, 0) \
		.with_duration(2.5)
	g.base.base_damage = 160.0

	g.damage_per_level = 80.0      # 5 级 = 480
	g.mana_per_level = 3.0         # 5 级 = 22
	return g


## 灵魂撕裂（Soulrend）—— 混沌系的第二颗：穿透一切的慢弹，沿途给每个人挂一份轻 DoT。
## 和精髓吸取分工：精髓 = 单体一份重 DoT；灵魂撕裂 = 一排人各一份轻 DoT。
## 两个 DoT 是不同 id，能同时挂在同一只怪身上叠着掉血。
static func gem_soulrend() -> SkillGem:
	var g := SkillGem.new(&"soulrend", "灵魂撕裂",
			T.CHAOS | T.SPELL | T.PROJECTILE | T.AREA)   # 随行光环是范围：增大范围放大它
	g.short_name = "魂"
	g.description = "一团缓慢飘行的怨魂：周围 45 像素内的敌人每 0.3 秒挨一次、挂一份混沌 DoT（3 秒）—— 不用撞到人，飘过去就行。和精髓吸取的 DoT 能同时生效。"

	g.base \
		.with_crit(0.05, 1.5) \
		.with_cost(12.0) \
		.with_cast_time(0.80) \
		.with_on_hit(Demo.buff_soulrend(), 1.0) \
		.with_projectile(170.0, 99, 0, 0) \
		.with_duration(2.2) \
		.with_aura(45.0, 0.3)          # ★ 随行光环（ADR-036）：飘过的地方每 0.3 秒结算一次，不用撞到人
	g.base.base_damage = 120.0

	g.damage_per_level = 60.0      # 5 级 = 360
	g.mana_per_level = 3.0         # 5 级 = 24
	return g


## 虚空匕首（Ethereal Knives）—— 唯一的**物理**法术：一次甩出 5 把飞刀的扇面。
## ★ 物理伤害的账和元素完全不同 ★：不吃任何抗性（骷髅火抗 40% 对它无效），
##   但吃**护甲**，而护甲对小刀特别有效（PoE 公式：armour / (armour + 5×伤害)）——
##   所以它单刀伤害配得很高：刀越重，护甲减免越低。
##   这也是「石肤」「感电」这类改承伤的词条对它特别关键的原因（那是护甲之后的乘区）。
static func gem_ethereal_knives() -> SkillGem:
	var g := SkillGem.new(&"ethereal_knives", "虚空匕首",
			T.PHYSICAL | T.SPELL | T.PROJECTILE)
	g.short_name = "刃"
	g.description = "一次甩出 5 把飞刀（60° 扇面）。物理伤害：不吃任何抗性，但吃护甲 —— 护甲对小刀减免大，所以单刀配得很重。感电能绕过护甲放大它。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(12.0) \
		.with_cast_time(0.70) \
		.with_projectile(320.0, 0, 0, 0) \
		.with_count(4) \
		.with_spread(ProjectileSpec.SpreadMode.FAN, 60.0, 0.0) \
		.with_duration(1.0)
	g.base.base_damage = 170.0

	g.damage_per_level = 85.0      # 5 级 = 510
	g.mana_per_level = 3.0         # 5 级 = 24
	return g


## ★ 冰霜新星（Ice Nova）—— 真正的范围技能（ADR-030）★
## 不带【投射物】标签、不走投射物管线：以自己为中心画一个半径 90 的圈，圈里的敌人**同时**各吃一次命中。
## 不用瞄准，被围住时按一下就是一整圈冰缓 —— 保命 / 清杂。
## 「增大范围」= 圈更大（半径按面积的平方根放大）、「集中效应」= 圈更小但更疼；
## 「多重投射」「穿透」这些投射物辅助**连不上**它，这才对：它根本不是弹。
static func gem_ice_nova() -> SkillGem:
	var g := SkillGem.new(&"ice_nova", "冰霜新星",
			T.COLD | T.SPELL | T.AREA)
	g.short_name = "星"
	g.description = "以自己为中心炸开一圈冰霜（半径 90 像素），圈里的敌人全部同时命中并冰缓。不用瞄准，被围住时用。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(13.0) \
		.with_cast_time(0.70) \
		.with_on_hit(Demo.buff_chill(), 1.0) \
		.with_area(90.0, AreaSpec.Origin.SELF)
	g.base.base_damage = 150.0

	g.damage_per_level = 75.0      # 5 级 = 450
	g.mana_per_level = 4.0         # 5 级 = 29
	return g


## 电击新星（Shock Nova）—— 冰霜新星的闪电镜像：圈稍大、更疼、全部感电。
## 圈里几只怪就叠几份感电，配「感电触媒」是最稳的触发源。
static func gem_shock_nova() -> SkillGem:
	var g := SkillGem.new(&"shock_nova", "电击新星",
			T.LIGHTNING | T.SPELL | T.AREA)
	g.short_name = "环"
	g.description = "以自己为中心炸开一个电环（45~120 像素的环带），环上的敌人全部感电 —— 贴身的打不到、中距离的全中。和冰霜新星（实心圆）正好互补。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(12.0) \
		.with_cast_time(0.70) \
		.with_on_hit(Demo.buff_shock(), 1.0) \
		.with_area(120.0, AreaSpec.Origin.SELF) \
		.with_inner(45.0)              # ★ 环（ADR-036）：45~120 之间才中，贴身的打不到（PoE 的电击新星就是一个环）
	g.base.base_damage = 200.0

	g.damage_per_level = 100.0     # 5 级 = 600
	g.mana_per_level = 4.0         # 5 级 = 28
	return g


## 风暴呼唤（Storm Call）—— 指哪打哪的延迟落雷：在鼠标点上放一个预警圈，1.2 秒后雷劈下来。
## 单发比新星重得多（要预判走位才打得中，这是代价）。
## ★ 带【持续时间】标签，延迟就是它的"持续时间" ★ —— 「延长持续」连上去落雷更慢（PoE 的真实行为，
##   玩家反而要找"缩短持续"）。这不是恒真数据，是一条会让你掂量的连接。
static func gem_storm_call() -> SkillGem:
	var g := SkillGem.new(&"storm_call", "风暴呼唤",
			T.LIGHTNING | T.SPELL | T.AREA | T.DURATION)
	g.short_name = "唤"
	g.description = "在鼠标点上标记一个圈（半径 70，射程 180），1.2 秒后雷劈下来，圈里全部命中并感电。单发极重，但要预判怪的走位。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(15.0) \
		.with_cast_time(0.60) \
		.with_on_hit(Demo.buff_shock(), 1.0) \
		.with_area(70.0, AreaSpec.Origin.TARGET, 1.2, 180.0)
	g.base.base_damage = 420.0

	g.damage_per_level = 210.0     # 5 级 = 1260
	g.mana_per_level = 5.0         # 5 级 = 35
	return g


## 烈焰风暴（Firestorm）—— 指哪打哪的持续火雨：标记点上 0.4 秒后开始落火，
## 每 0.35 秒炸一次、连炸 6 次（ADR-031 的脉冲机制）。单次不疼、站在里面很疼。
## ★ 带【持续时间】：延长持续 = 多落几次（6 × 1.45 ≈ 9 次），缩短持续 = 少几次但开始得快 ★
static func gem_firestorm() -> SkillGem:
	var g := SkillGem.new(&"firestorm", "烈焰风暴",
			T.FIRE | T.SPELL | T.AREA | T.DURATION)
	g.short_name = "暴"
	g.description = "在鼠标点上召来火雨（半径 60，射程 180）：0.4 秒后开始，每 0.35 秒炸一次、连炸 6 次，每次 40% 几率点燃。持续时间越长落得越多。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(16.0) \
		.with_cast_time(0.80) \
		.with_on_hit(Demo.buff_ignite(), 0.40) \
		.with_area(60.0, AreaSpec.Origin.TARGET, 0.4, 180.0) \
		.with_pulses(6, 0.35)
	g.base.base_damage = 85.0        # 每次脉冲的点伤（6 次全吃 = 510）

	g.damage_per_level = 43.0      # 5 级 = 257 / 次
	g.mana_per_level = 4.0         # 5 级 = 32
	return g


## 漩涡（Vortex）—— 以自己为中心的冰霜漩涡：立刻炸一次，然后每 0.5 秒再炸、共 4 次，全部冰缓。
## 和冰霜新星的分工：新星一下更疼，漩涡站住不动就是一片持续的减速区。
static func gem_vortex() -> SkillGem:
	var g := SkillGem.new(&"vortex", "漩涡",
			T.COLD | T.SPELL | T.AREA | T.DURATION)
	g.short_name = "涡"
	g.description = "以自己为中心卷起冰霜漩涡（半径 75）：立刻炸一次，之后每 0.5 秒再炸、共 4 次，圈里全部冰缓。站住不动就是一片减速区。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(14.0) \
		.with_cast_time(0.70) \
		.with_on_hit(Demo.buff_chill(), 1.0) \
		.with_area(75.0, AreaSpec.Origin.SELF) \
		.with_pulses(4, 0.5)
	g.base.base_damage = 120.0

	g.damage_per_level = 60.0      # 5 级 = 360 / 次
	g.mana_per_level = 4.0         # 5 级 = 30
	return g


## 瘟疫（Contagion）—— 混沌系的范围技能：指哪打哪、瞬发，圈里每个人挂一份混沌 DoT。
## 命中本身很轻，DoT 才是它的全部。三个混沌 DoT（精髓吸取 / 灵魂撕裂 / 瘟疫）是三个 id，能叠着挂。
## ★ 故意不带【持续时间】★ —— 本项目 DURATION 不改 Buff 时长，带了就是空标签（同精髓吸取）。
static func gem_contagion() -> SkillGem:
	var g := SkillGem.new(&"contagion", "瘟疫",
			T.CHAOS | T.SPELL | T.AREA)
	g.short_name = "疫"
	g.description = "在鼠标点上炸开一团瘟疫（半径 60，射程 180，瞬发），圈里每个敌人都挂上 4 秒混沌持续伤害。命中不疼，DoT 才是它。"

	g.base \
		.with_crit(0.05, 1.5) \
		.with_cost(10.0) \
		.with_cast_time(0.60) \
		.with_on_hit(Demo.buff_contagion(), 1.0) \
		.with_area(60.0, AreaSpec.Origin.TARGET, 0.0, 180.0)
	g.base.base_damage = 70.0

	g.damage_per_level = 35.0      # 5 级 = 210
	g.mana_per_level = 3.0         # 5 级 = 22
	return g


# ============================================================ 攻击技能（ADR-032）
#
# ★ 攻击技能要镶进近战武器，出手间隔走「攻击速度」★（法术走施法速度，镶法杖）
# 自己的点伤很低（40~95），大头是武器的「增加 N 点攻击伤害」（FLAT，加在点伤上再乘四段式）。
# 近战 = 范围管线的 FRONT 模式：面前 reach 像素处的一个圈。★ 凡是打一个圈的技能都带【范围】标签 ★
# （ADR-037）：重击的圈再小也是圈，「增大范围」照样放大它 —— 玩家看到圈就该能连范围辅助。

## 重击（Heavy Strike）—— 最朴素的一下：慢、重、单体
static func gem_heavy_strike() -> SkillGem:
	var g := SkillGem.new(&"heavy_strike", "重击",
			T.PHYSICAL | T.ATTACK | T.MELEE | T.AREA)
	g.short_name = "击"
	g.description = "抡一下面前的敌人（半径 26 的小圈），慢但重。点伤最高的单体近战。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(5.0) \
		.with_cast_time(1.00) \
		.with_area(26.0, AreaSpec.Origin.FRONT, 0.0, 22.0)
	g.base.base_damage = 90.0

	g.damage_per_level = 45.0      # 5 级 = 270（+ 武器）
	g.mana_per_level = 1.0
	return g


## 横扫（Cleave）—— 面前一大片：近战里的打群入口
static func gem_cleave() -> SkillGem:
	var g := SkillGem.new(&"cleave", "横扫",
			T.PHYSICAL | T.ATTACK | T.MELEE | T.AREA)
	g.short_name = "扫"
	g.description = "横着扫一片（面前半径 45 的圈），圈里全中。单下不重，打群用。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(6.0) \
		.with_cast_time(0.80) \
		.with_area(45.0, AreaSpec.Origin.FRONT, 0.0, 30.0)
	g.base.base_damage = 55.0

	g.damage_per_level = 28.0
	g.mana_per_level = 1.0
	return g


## 重锤猛击（Ground Slam）—— 比横扫更远更大更慢的一锤（译名按记忆取的，没查证）
static func gem_ground_slam() -> SkillGem:
	var g := SkillGem.new(&"ground_slam", "重锤猛击",
			T.PHYSICAL | T.ATTACK | T.MELEE | T.AREA)
	g.short_name = "锤"
	g.description = "往前砸一锤，震波沿地面扩成 100° 的宽锥、长 95 像素。比横扫远一倍、慢一截。配巨锤。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(8.0) \
		.with_cast_time(1.05) \
		.with_area(95.0, AreaSpec.Origin.SELF) \
		.with_arc(100.0)               # ★ 从脚下往前的 100° 宽锥、长 95（ADR-036）：比横扫远一倍
	g.base.base_damage = 75.0

	g.damage_per_level = 38.0
	g.mana_per_level = 1.0
	return g


## 双重打击（Double Strike）—— 一个动作砍两下（两次脉冲、间隔 0.15 秒）：每一下都吃武器伤害
static func gem_double_strike() -> SkillGem:
	var g := SkillGem.new(&"double_strike", "双重打击",
			T.PHYSICAL | T.ATTACK | T.MELEE | T.AREA)
	g.short_name = "双"
	g.description = "一个动作连砍两下（间隔 0.15 秒），每一下都是完整的一次命中、都吃武器伤害。配匕首堆出手。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(6.0) \
		.with_cast_time(0.90) \
		.with_area(26.0, AreaSpec.Origin.FRONT, 0.0, 22.0) \
		.with_pulses(2, 0.15) \
		.with_follow()                 # 第二刀跟着人：转身 / 挪步之后砍的还是面前
	g.base.base_damage = 50.0

	g.damage_per_level = 25.0
	g.mana_per_level = 1.0
	return g


## 旋风斩（Cyclone）—— ★ 引导技能（ADR-033）★ 按住就一直转：每 0.25 秒一圈（半径 50、以自己为中心、
## 跟着人走），每圈扣 4 蓝（= 16 蓝/秒，比回蓝还快一截，蓝就是它的计时器），松手 / 没蓝就停；
## 引导中不能切技能。代价换来的是近战里最高的持续伤害：每圈 55 点 + 武器伤害，圈里全中。
static func gem_cyclone() -> SkillGem:
	var g := SkillGem.new(&"cyclone", "旋风斩",
			T.PHYSICAL | T.ATTACK | T.MELEE | T.AREA)
	g.short_name = "旋"
	g.description = "按住就一直转（半径 50，每 0.25 秒一圈、每圈 4 蓝），圈跟着你走、圈里全中。松手或没蓝就停，转的时候不能切技能。近战里最高的持续伤害。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(4.0) \
		.with_cast_time(0.25) \
		.with_channel() \
		.with_area(50.0, AreaSpec.Origin.SELF) \
		.with_follow()                 # ★ 边转边走：圈钉在施放点上就不是旋风斩了 ★
	g.base.base_damage = 55.0

	g.damage_per_level = 28.0
	g.mana_per_level = 1.0
	return g


## 炼狱之击（Infernal Blow）—— 火焰近战，必定点燃，圈稍大
static func gem_infernal_blow() -> SkillGem:
	var g := SkillGem.new(&"infernal_blow", "炼狱之击",
			T.FIRE | T.ATTACK | T.MELEE | T.AREA)
	g.short_name = "狱"
	g.description = "一记烧着火的重拳（面前半径 40），命中必定点燃。武器的物理伤害也按火焰结算（本项目不做转化，整下都是火）。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(7.0) \
		.with_cast_time(0.95) \
		.with_on_hit(Demo.buff_ignite(), 1.0) \
		.with_area(40.0, AreaSpec.Origin.FRONT, 0.0, 28.0)
	g.base.base_damage = 70.0

	g.damage_per_level = 35.0
	g.mana_per_level = 1.0
	return g


## 冰霜之锤（Glacial Hammer）—— 冰霜近战单体，冰缓。PoE 里会冰冻，本项目冰系异常是冰缓
static func gem_glacial_hammer() -> SkillGem:
	var g := SkillGem.new(&"glacial_hammer", "冰霜之锤",
			T.COLD | T.ATTACK | T.MELEE | T.AREA)
	g.short_name = "霜锤"
	g.description = "一记冰锤：面前 70° 的短锥（长 48），锥里全部冰缓。比重击宽一些、轻一些 —— 追不上的怪一锤就追得上了。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(7.0) \
		.with_cast_time(1.00) \
		.with_on_hit(Demo.buff_chill(), 1.0) \
		.with_area(48.0, AreaSpec.Origin.SELF) \
		.with_arc(70.0)                # 70° 的短锥（ADR-036）：比重击宽，一锤能冰缓一小片
	g.base.base_damage = 80.0

	g.damage_per_level = 40.0
	g.mana_per_level = 1.0
	return g


## 静电之击（Static Strike）—— 砍一下之后原地留一团静电，再放电 2 次（脉冲 3 × 0.4 秒），每次感电
static func gem_static_strike() -> SkillGem:
	var g := SkillGem.new(&"static_strike", "静电之击",
			T.LIGHTNING | T.ATTACK | T.MELEE | T.AREA | T.DURATION)
	g.short_name = "静"
	g.description = "砍一下（面前半径 30），落点留一团静电再放电 2 次（共 3 次脉冲），每次感电。站桩打感电层数的近战。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(7.0) \
		.with_cast_time(0.90) \
		.with_on_hit(Demo.buff_shock(), 1.0) \
		.with_area(30.0, AreaSpec.Origin.FRONT, 0.0, 22.0) \
		.with_pulses(3, 0.40)
	g.base.base_damage = 45.0

	g.damage_per_level = 23.0
	g.mana_per_level = 1.0
	return g


## 毒蛇打击（Viper Strike）—— 混沌近战：每一下上一份**独立叠加**的中毒。攻速就是毒量
static func gem_viper_strike() -> SkillGem:
	var g := SkillGem.new(&"viper_strike", "毒蛇打击",
			T.CHAOS | T.ATTACK | T.MELEE | T.AREA)
	g.short_name = "蛇"
	g.description = "快速的一刺（面前半径 26），每一下都上一份中毒，中毒可以无限叠加（各自 2 秒）。配匕首：攻速就是毒量。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(6.0) \
		.with_cast_time(0.75) \
		.with_on_hit(Demo.buff_poison(), 1.0) \
		.with_area(26.0, AreaSpec.Origin.FRONT, 0.0, 22.0)
	g.base.base_damage = 40.0

	g.damage_per_level = 20.0
	g.mana_per_level = 1.0
	return g


## 灵体投掷（Spectral Throw）—— ★ 攻击也可以是投射物 ★：把武器的幻影甩出去，穿透一切。
## PoE 里它会飞回来；本项目没有回旋，用慢速 + 长存活还原"在场上飘很久"的手感。
static func gem_spectral_throw() -> SkillGem:
	var g := SkillGem.new(&"spectral_throw", "灵体投掷",
			T.PHYSICAL | T.ATTACK | T.PROJECTILE)
	g.short_name = "掷"
	g.description = "把武器的幻影甩出去，穿透一切，飞到一半掉头飞回你手里 —— 回程再打一遍路上的每个敌人。攻击技能里唯一的投射物，吃武器伤害也吃投射物辅助。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(8.0) \
		.with_cast_time(0.80) \
		.with_projectile(210.0, 99, 0, 0) \
		.with_duration(1.6) \
		.with_return()                 # ★ 回旋（ADR-036）：飞到一半掉头飞回来，回程再打一遍
	g.base.base_damage = 60.0

	g.damage_per_level = 30.0
	g.mana_per_level = 2.0
	return g


## 冰川之刺（Glacial Cascade）—— 从脚下往前依次炸出一排冰刺：天生连环 2（三个圈排成一条线）
static func gem_glacial_cascade() -> SkillGem:
	var g := SkillGem.new(&"glacial_cascade", "冰川之刺",
			T.COLD | T.SPELL | T.AREA)
	g.short_name = "刺"
	g.description = "朝鼠标方向从近到远依次炸出一排冰刺（三个半径 34 的圈排成一线、天生连环 2），全部冰缓。连环范围能把它加到 5 个圈。"

	g.base \
		.with_crit(0.06, 1.5) \
		.with_cost(12.0) \
		.with_cast_time(0.70) \
		.with_on_hit(Demo.buff_chill(), 1.0) \
		.with_area(34.0, AreaSpec.Origin.FRONT, 0.0, 90.0) \
		.with_cascade(2)
	g.base.base_damage = 130.0

	g.damage_per_level = 65.0
	g.mana_per_level = 4.0
	return g


## 全部攻击技能（要镶进近战武器的那些）
static func all_attacks() -> Array:
	var out: Array = []
	for g in all_actives():
		if ((g as SkillGem).tags & T.ATTACK) != 0:
			out.append(g)
	return out


## 全部主动技能石（背包初始化 / UI 列表用）。
## ★ 顺序 = 技能栏顺序，电球术是样板技能所以排第一格 ★
## 31 颗分几条路：铺场（电球）/ 单发（火球、冰矛、裂雷之矛）/ 打群（电弧、翻滚岩浆、寒冬之眼）/
## 贴脸（冰霜脉冲、焚烧、闪电之触）/ 弹幕（寒冰弹）/ 混沌 DoT（精髓吸取、灵魂撕裂）/
## 物理（虚空匕首）/ ★ 范围（新星 ×2、风暴呼唤、烈焰风暴、漩涡、瘟疫、冰川之刺；扇形 / 光束：焚烧、闪电之触、裂雷之矛 —— 不走投射物管线，ADR-030/031/034）★
## / ★ 攻击（ADR-032，镶武器、走攻速）：近战 9 颗 + 灵体投掷（攻击投射物）★
static func all_actives() -> Array:
	return [gem_spark(), gem_fireball(), gem_arc(), gem_frostbolt(), gem_freezing_pulse(),
			gem_ice_spear(), gem_rolling_magma(), gem_incinerate(), gem_lightning_tendrils(),
			gem_essence_drain(),
			gem_crackling_lance(), gem_eye_of_winter(), gem_soulrend(), gem_ethereal_knives(),
			gem_ice_nova(), gem_shock_nova(), gem_storm_call(),
			gem_firestorm(), gem_vortex(), gem_contagion(),
			gem_heavy_strike(), gem_cleave(), gem_ground_slam(), gem_double_strike(), gem_cyclone(),
			gem_infernal_blow(), gem_glacial_hammer(), gem_static_strike(), gem_viper_strike(),
			gem_spectral_throw(), gem_glacial_cascade()]


# ============================================================ 辅助宝石

## 全部辅助宝石。★ 触媒也是（特殊的）辅助宝石 ★ —— 它们一起进奖励池和商店。
static func all_supports() -> Array:
	var out: Array = [
		support_pierce(),
		support_fork(),
		support_chain(),
		support_link(),
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
		support_void(),
		support_area(),
		support_conc(),
		support_less_duration(),
		support_cascade(),
	]
	out.append_array(all_catalysts())
	return out


## ★ 崇高辅助（ADR-031，参考火炬之光的崇高/华贵）★ 普通款的加强版，效果翻倍、各带一条负面。
## 不在 all_supports() 里：第 2 层起才进奖励池、第 3 层起才上货架（RunContent 负责挑）。
static func all_sublime() -> Array:
	return [sublime_area(), sublime_conc(), sublime_less_duration(), sublime_cascade()]


## ★ 血脉辅助（ADR-031，参考 PoE2 的血脉宝石）★ 具名、独一份、不进任何池子：
## 只有守关 Boss 必掉一颗（RunContent.boss_lineage）。魔力倍率 ×1.0，代价写在词缀里。
## 名字是本项目自己起的，不是 PoE2 的原名。
static func all_lineage() -> Array:
	return [lineage_grim(), lineage_aira(), lineage_seros()]


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


## ★ 连锁支援（ADR-035）★ 和「弹射支援」是两回事：连锁跳向**没打过**的敌人、跳跃 +500% 速度、永不回头；
## 弹射可以两只怪来回弹。连锁打群更快更稳，弹射打单体（来回弹）更狠 —— 两条路。
static func support_link() -> SupportGem:
	return _sup(&"sup_link", "连锁支援", "锁", T.PROJECTILE, 1.40,
		"命中后连锁跳向附近没打过的敌人 2 次（跳跃几乎瞬间、永不回头）。和弹射不同：不能来回弹同一只。",
		[
			M.new(S.LINK_COUNT, M.Kind.FLAT, 2.0, T.PROJECTILE),
			M.new(S.DAMAGE, M.Kind.MORE, -0.20, T.PROJECTILE),
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


## 虚空操纵（PoE 的 Void Manipulation）—— 混沌系的「更多」乘区，
## 和闪电增强 / 冰霜增强是同一个模子。要求【混沌】：只有精髓吸取连得上。
## 它对精髓吸取的 DoT 也生效 —— DoT 快照的是 CHAOS|DOT 标签下的伤害加成，这条 MORE 只看 CHAOS。
static func support_void() -> SupportGem:
	return _sup(&"sup_void", "虚空操纵", "虚", T.CHAOS, 1.25,
		"更多混沌伤害（命中和持续伤害都吃）。只有混沌技能连得上。",
		[M.new(S.DAMAGE, M.Kind.MORE, 0.25, T.CHAOS)])


## 增大范围（PoE 的 Increased Area of Effect）—— ADR-011 删过一次（那时它只放大脉冲半径，
## 脉冲没了它就是空宝石）。现在有真正的范围管线了（ADR-030），它终于有事可干：
## 「范围效果 +50%」→ 半径 ×√1.5 ≈ ×1.22（AreaSpec 按面积的平方根放大半径）。
static func support_area() -> SupportGem:
	return _sup(&"sup_area", "增大范围", "广", T.AREA, 1.30,
		"范围技能的面积 +50%（半径约 ×1.22）。只有范围技能连得上。",
		[M.new(S.AREA_OF_EFFECT, M.Kind.INCREASED, 0.50, T.AREA)])


## 集中效应（PoE 的 Concentrated Effect）—— 「增大范围」的反面：圈更小、但更疼。
## 范围是 MORE −30%（半径 ×√0.7 ≈ ×0.84），伤害是 MORE +40%（独立乘区）。
## 新星配它 = 贴身圈更小，但一圈下去伤害翻倍级 —— 要不要，看你敢不敢贴脸。
static func support_conc() -> SupportGem:
	return _sup(&"sup_conc", "集中效应", "集", T.AREA, 1.40,
		"范围技能更多 40% 伤害，但范围更少 30%（半径约 ×0.84）。圈更小更疼。",
		[
			M.new(S.AREA_OF_EFFECT, M.Kind.MORE, -0.30, T.AREA),
			M.new(S.DAMAGE, M.Kind.MORE, 0.40, T.AREA),
		])


## 缩短持续（PoE 的 Less Duration）—— 「延长持续」的反面：持续时间更少 40%、伤害更多 10%。
## 对风暴呼唤 = 落雷更快（1.2 → 0.72 秒）；对烈焰风暴 = 少落几次但开始得快；对电球术 = 每发活得短。
static func support_less_duration() -> SupportGem:
	return _sup(&"sup_less_duration", "缩短持续", "短", T.DURATION, 1.15,
		"持续时间更少 40%，伤害更多 10%。风暴呼唤落雷更快，烈焰风暴少落几次。",
		[
			M.new(S.DURATION, M.Kind.MORE, -0.40, T.DURATION),
			M.new(S.DAMAGE, M.Kind.MORE, 0.10, T.DURATION),
		])


## 连环范围（参考 PoE 的 Spell Cascade，名字是本项目自己起的）—— 沿施法方向前后各多一个圈。
## 新星 = 三个圈排成一条线；风暴呼唤 = 三道雷。代价：更少 20% 伤害、蓝 ×1.40。
static func support_cascade() -> SupportGem:
	return _sup(&"sup_cascade", "连环范围", "环", T.AREA, 1.40,
		"范围技能沿施法方向前后各多一个圈（共 3 个），伤害更少 20%。只有范围技能连得上。",
		[
			M.new(S.AREA_CASCADE, M.Kind.FLAT, 2.0, T.AREA),
			M.new(S.DAMAGE, M.Kind.MORE, -0.20, T.AREA),
		])


# ============================================================ 崇高辅助（ADR-031）

static func sublime_area() -> SupportGem:
	return _sup_tier(SupportGem.Tier.SUBLIME, &"sub_area", "崇高·增大范围", "广", T.AREA, 1.35,
		"范围技能的面积 +100%（半径 ×1.41），但伤害更少 15%。",
		[
			M.new(S.AREA_OF_EFFECT, M.Kind.INCREASED, 1.00, T.AREA),
			M.new(S.DAMAGE, M.Kind.MORE, -0.15, T.AREA),
		])


static func sublime_conc() -> SupportGem:
	return _sup_tier(SupportGem.Tier.SUBLIME, &"sub_conc", "崇高·集中效应", "集", T.AREA, 1.50,
		"范围技能更多 65% 伤害，但范围更少 50%（半径 ×0.71）。贴脸才有用。",
		[
			M.new(S.AREA_OF_EFFECT, M.Kind.MORE, -0.50, T.AREA),
			M.new(S.DAMAGE, M.Kind.MORE, 0.65, T.AREA),
		])


static func sublime_less_duration() -> SupportGem:
	return _sup_tier(SupportGem.Tier.SUBLIME, &"sub_less_duration", "崇高·缩短持续", "短", T.DURATION, 1.30,
		"持续时间更少 70%，伤害更多 25%。风暴呼唤几乎瞬发；烈焰风暴只剩 2 次。",
		[
			M.new(S.DURATION, M.Kind.MORE, -0.70, T.DURATION),
			M.new(S.DAMAGE, M.Kind.MORE, 0.25, T.DURATION),
		])


static func sublime_cascade() -> SupportGem:
	return _sup_tier(SupportGem.Tier.SUBLIME, &"sub_cascade", "崇高·连环范围", "环", T.AREA, 1.60,
		"范围技能沿施法方向多 4 个圈（共 5 个），伤害更少 35%。",
		[
			M.new(S.AREA_CASCADE, M.Kind.FLAT, 4.0, T.AREA),
			M.new(S.DAMAGE, M.Kind.MORE, -0.35, T.AREA),
		])


# ============================================================ 血脉辅助（ADR-031）

## 格里姆之震：又大又疼，但施法变慢
static func lineage_grim() -> SupportGem:
	return _sup_tier(SupportGem.Tier.LINEAGE, &"lin_grim", "格里姆之震", "震", T.AREA, 1.0,
		"范围技能的面积 +60%、伤害更多 20%，但施法速度降低 25%。",
		[
			M.new(S.AREA_OF_EFFECT, M.Kind.INCREASED, 0.60, T.AREA),
			M.new(S.DAMAGE, M.Kind.MORE, 0.20, T.AREA),
			M.new(S.CAST_SPEED, M.Kind.INCREASED, -0.25, T.AREA),
		])


## 艾拉之脉动：所有范围技能多炸 2 次（新星变成三连炸），代价是圈小一圈
static func lineage_aira() -> SupportGem:
	return _sup_tier(SupportGem.Tier.LINEAGE, &"lin_aira", "艾拉之脉动", "脉", T.AREA, 1.0,
		"范围技能额外脉冲 2 次（新星变成三连炸、烈焰风暴 8 次），但范围更少 25%。",
		[
			M.new(S.AREA_PULSES, M.Kind.FLAT, 2.0, T.AREA),
			M.new(S.AREA_OF_EFFECT, M.Kind.MORE, -0.25, T.AREA),
		])


## 塞洛斯之瞬：有延迟的范围技能几乎瞬发（风暴呼唤 0.3 秒落雷），代价是圈小一点
static func lineage_seros() -> SupportGem:
	return _sup_tier(SupportGem.Tier.LINEAGE, &"lin_seros", "塞洛斯之瞬", "瞬", T.AREA | T.DURATION, 1.0,
		"带持续时间的范围技能，延迟更少 75%（风暴呼唤 1.2 → 0.3 秒），但范围更少 20%。",
		[
			M.new(S.DURATION, M.Kind.MORE, -0.75, T.AREA | T.DURATION),
			M.new(S.AREA_OF_EFFECT, M.Kind.MORE, -0.20, T.AREA | T.DURATION),
		])


static func _sup_tier(tier: int, id: StringName, name: String, short_name: String, required: int,
		mana_mult: float, desc: String, mods: Array) -> SupportGem:
	var g := _sup(id, name, short_name, required, mana_mult, desc, mods)
	g.tier = tier
	return g


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

## 图鉴里的全部宝石（主动 + 辅助 + 崇高 + 血脉）。每次调用都是**新的实例**。
## ★ make_gem / 存档 / 控制台走这里，所以崇高和血脉也在 ★ —— 奖励池和商店**不**走这里
static func all_gems() -> Array:
	var out: Array = []
	out.append_array(all_actives())
	out.append_array(all_supports())
	out.append_array(all_sublime())
	out.append_array(all_lineage())
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
