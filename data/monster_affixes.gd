class_name MonsterAffixes
extends RefCounted

## 精英怪词条池：全是**数据**，规则在 combat/monster_affix.gd。
##
## ★ 每条词条只做一件事，名字一眼能看懂它会怎么打你 ★
##   头顶写着「迅捷·灼热之爪」的怪 = 追得快 + 挨一下会着火。
##   玩家不看面板也该知道该躲哪只、先杀哪只 —— 这是精英怪存在的意义。
##
## 所有数值都走属性系统（Modifier），一行战斗逻辑都没有：
##   · 抗性类是 FLAT（0.40 → 0.70），到 75% 上限自动截断（CombatStat.RESIST_CAP）
##   · 生命/伤害是 INCREASED，和 RunContent 的步/层成长曲线**相加**，不是连乘
##   · ★ 狂暴用的是 FLAT 攻速 ★ —— 普通怪从没设过 ATTACK_SPEED 基础值（是 0），
##     "提高 30%" 在 0 上还是 0（AGENTS.md 里的恒真数据陷阱）；FLAT +0.3 才真的变快

const M = preload("res://combat/modifier.gd")
const T = preload("res://combat/combat_tags.gd")
const S = preload("res://combat/combat_stat.gd")
const Demo = preload("res://data/demo_content.gd")


## 全部词条。每次调用都是**新的实例**（和 GemLibrary 一个规矩，免得词缀被两只怪共用）。
static func all_affixes() -> Array:
	return [
		swift(), sturdy(), brutal(), frenzied(), stoneskin(), giant(),
		fire_ward(), cold_ward(), lightning_ward(),
		scorching_claw(), frost_claw(), shock_claw(),
	]


## 按 id 找一条（存档 / 测试用）。找不到返回 null。
static func by_id(id: StringName) -> MonsterAffix:
	for a in all_affixes():
		if (a as MonsterAffix).id == id:
			return a
	return null


## 无放回地抽 count 条互不重复的词条。
## ★ 用调用方给的 rng（局模式来自 RunState.rng_for("elite")）★
##   → 同一局同一房的精英词条是定死的，读档重打还是同一批，不能靠重进刷"好打的词条"。
static func roll(count: int, rng: RandomNumberGenerator) -> Array:
	return RunRewards.pick_distinct(all_affixes(), count, rng)


# ---------------------------------------------------------------- 移动 / 生存

static func swift() -> MonsterAffix:
	return MonsterAffix.new(&"swift", "迅捷") \
		.with_desc("追击速度快得多。走位躲不掉它，先杀它。") \
		.with_mod(M.new(S.MOVE_SPEED, M.Kind.INCREASED, 0.45))


static func sturdy() -> MonsterAffix:
	return MonsterAffix.new(&"sturdy", "坚韧") \
		.with_desc("生命上限大幅提高。") \
		.with_mod(M.new(S.MAX_LIFE, M.Kind.INCREASED, 0.60))


## 石肤：承受的伤害更少。走 DAMAGE_TAKEN 的 INCREASED 负值 —— 和感电（正值）在同一个乘区相加，
## 所以感电能"抵消"它一部分，这是 PoE 式的反制关系。
static func stoneskin() -> MonsterAffix:
	return MonsterAffix.new(&"stoneskin", "石肤") \
		.with_desc("受到的伤害降低 25%。感电能抵消一部分。") \
		.with_mod(M.new(S.DAMAGE_TAKEN, M.Kind.INCREASED, -0.25, T.NONE))


## 巨型：血厚、体型大、走得慢。体型倍率只是一个数字，画多大由 Enemy 决定。
static func giant() -> MonsterAffix:
	return MonsterAffix.new(&"giant", "巨型") \
		.with_desc("血量翻倍、体型放大，但走得慢一点。") \
		.with_mod(M.new(S.MAX_LIFE, M.Kind.INCREASED, 1.00)) \
		.with_mod(M.new(S.MOVE_SPEED, M.Kind.INCREASED, -0.15)) \
		.with_scale(1.35)


# ---------------------------------------------------------------- 攻击

static func brutal() -> MonsterAffix:
	return MonsterAffix.new(&"brutal", "暴虐") \
		.with_desc("每一下都更疼。") \
		.with_mod(M.new(S.DAMAGE, M.Kind.INCREASED, 0.50))


## ★ FLAT 攻速 ★ 普通怪基础攻速是 0（等于 10 秒砍一刀），+0.3 → 约 3.3 秒一刀，快 3 倍
static func frenzied() -> MonsterAffix:
	return MonsterAffix.new(&"frenzied", "狂暴") \
		.with_desc("攻击频率是普通怪的 3 倍。别站着挨打。") \
		.with_mod(M.new(S.ATTACK_SPEED, M.Kind.FLAT, 0.30))


# ---------------------------------------------------------------- 抗性（克制某一系构筑）

static func fire_ward() -> MonsterAffix:
	return MonsterAffix.new(&"fire_ward", "抗火") \
		.with_desc("火焰抗性 +30%。火球 / 焚烧打它很吃亏，换一系或者靠感电放大。") \
		.with_mod(M.new(S.FIRE_RESIST, M.Kind.FLAT, 0.30))


static func cold_ward() -> MonsterAffix:
	return MonsterAffix.new(&"cold_ward", "抗冰") \
		.with_desc("冰霜抗性 +35%。") \
		.with_mod(M.new(S.COLD_RESIST, M.Kind.FLAT, 0.35))


static func lightning_ward() -> MonsterAffix:
	return MonsterAffix.new(&"lightning_ward", "抗电") \
		.with_desc("闪电抗性 +35%。") \
		.with_mod(M.new(S.LIGHTNING_RESIST, M.Kind.FLAT, 0.35))


# ---------------------------------------------------------------- 爪类（近战附带异常）

## 灼热之爪：挨一下会着火。用的是给怪专配的、比玩家点燃温和的 DoT（见 DemoContent）
static func scorching_claw() -> MonsterAffix:
	return MonsterAffix.new(&"scorching_claw", "灼热之爪") \
		.with_desc("近战命中让你着火，持续掉血 3 秒。") \
		.with_on_hit(Demo.buff_scorching_claw())


## 霜爪：挨一下移速 -30%（复用玩家打怪的那条冰缓，规则一模一样）
static func frost_claw() -> MonsterAffix:
	return MonsterAffix.new(&"frost_claw", "霜爪") \
		.with_desc("近战命中让你冰缓（移动速度 -30%），走位会变慢。") \
		.with_on_hit(Demo.buff_chill())


## 雷爪：挨一下感电（受到的伤害 +8%/层，最多 3 层）—— 被围住时越打越疼
static func shock_claw() -> MonsterAffix:
	return MonsterAffix.new(&"shock_claw", "雷爪") \
		.with_desc("近战命中让你感电，之后受到的所有伤害更高（可叠 3 层）。") \
		.with_on_hit(Demo.buff_shock())
