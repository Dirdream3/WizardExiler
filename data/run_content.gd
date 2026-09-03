class_name RunContent
extends RefCounted

## 局内流程要用的**内容数据**：奖励池、商店货架、每一步的怪、最终 Boss。
##
## 和 gem_library / equip_library 一样：这里只有数据和"从图鉴里挑东西"，
## 没有流程逻辑 —— 流程规则在 run/（纯逻辑，可单测），这里只是填池子、定价格。

const M = preload("res://combat/modifier.gd")
const T = preload("res://combat/combat_tags.gd")
const S = preload("res://combat/combat_stat.gd")

## ★ 开局 = 一根法杖 + 镶在里面的一颗技能石 ★
## 法杖是技能的载体（ADR-020）——光有宝石没有法杖是放不出技能的，
## 所以开局必须成对给。见习法杖没有词缀，它的全部价值就是那个槽。
const STARTING_WAND := &"apprentice_wand"
const STARTING_GEM := &"spark"
## 开局宝石的等级。等级上限是 5（ADR-024）、每级成长很大：
## 1 级太肉搏（电球单发 55），2 级（83）手感刚好能开荒，还留 3 次升级空间。
const STARTING_LEVEL := 2

## 商店定价（按 id）。没写进表里的按 DEFAULT_PRICE 卖。
## 价格故意压在"一个金币房（18~44 金）能买 1~2 件"的水平，金币奖励才有意义。
const PRICES := {
	&"spark": 30, &"fireball": 30, &"arc": 30, &"frostbolt": 30, &"freezing_pulse": 30,
	&"apprentice_wand": 20,
	&"staff": 35, &"iron_helm": 30, &"traveller_boots": 25, &"ring_of_flame": 15,
	&"arcane_belt": 25, &"sapphire_amulet": 18,
	# 触媒（特殊辅助）：统一 28 —— 自动触发很值钱，比普通辅助贵一档
	&"cat_shock": 28, &"cat_ignite": 28, &"cat_chill": 28,
	&"cat_hits": 28, &"cat_move": 28, &"cat_timer": 28,
}
const DEFAULT_PRICE := 22

## 商店一次进多少货：1 颗技能石 + 2 颗辅助 + 2 件装备
const SHOP_ACTIVES := 1
const SHOP_SUPPORTS := 2
const SHOP_EQUIPS := 2


# ---------------------------------------------------------------- 奖励池

## 交给 RunRewards.roll_options() 的候选池。
##   owned —— 背包里已有的宝石（升级奖励从这里挑），由调用方传（这里拿不到玩家）
static func reward_pools(owned: Array) -> Dictionary:
	return {
		"gems": GemLibrary.all_actives(),
		"supports": GemLibrary.all_supports(),
		"equips": EquipLibrary.all_items(),
		"owned": owned,
	}


# ---------------------------------------------------------------- 商店

static func price_of(thing) -> int:
	return int(PRICES.get(thing.id, DEFAULT_PRICE))


## 进货。用调用方给的 rng（来自 RunState.rng_for("shop")）→
## 同一局同一步的商店，退出重进、读档重开，货架都一模一样。
static func shop_stock(rng: RandomNumberGenerator) -> Array:
	var stock: Array = []
	stock.append_array(RunRewards.pick_distinct(GemLibrary.all_actives(), SHOP_ACTIVES, rng))
	stock.append_array(RunRewards.pick_distinct(GemLibrary.all_supports(), SHOP_SUPPORTS, rng))
	stock.append_array(RunRewards.pick_distinct(EquipLibrary.all_items(), SHOP_EQUIPS, rng))
	return stock


# ---------------------------------------------------------------- 清房金币

## ★ 金币每个关卡都会掉落 ★（没有专门的金币房，见 ADR-019）
## 每清一个战斗房自动给的金币区间（第 1 层第 1 步的基础值）：
##   每往后一步 +ROOM_GOLD_PER_STEP，每深一层 +ROOM_GOLD_PER_FLOOR。
## 第 1 层 8~29 / 步，第 4 层 32~53 / 步 —— 深层商店照旧定价，钱多是应得的。
const ROOM_GOLD_MIN := 8
const ROOM_GOLD_MAX := 14
const ROOM_GOLD_PER_STEP := 3
const ROOM_GOLD_PER_FLOOR := 8

## 守关 Boss 也掉金币（它也是一个关卡），比普通房肥一截
const BOSS_GOLD_MIN := 25
const BOSS_GOLD_MAX := 35
const BOSS_GOLD_PER_FLOOR := 12


## 第 floor_index 层、第 step 步清房给多少金币。
## ★ 用调用方给的 rng（来自 RunState.rng_for("room_gold")）★
##   → 同一局同一处的数额是定死的，读档重打拿到的也是同一笔，刷不了钱。
static func room_gold(step: int, rng: RandomNumberGenerator, floor_index: int = 0) -> int:
	return rng.randi_range(ROOM_GOLD_MIN, ROOM_GOLD_MAX) \
			+ ROOM_GOLD_PER_STEP * step + ROOM_GOLD_PER_FLOOR * floor_index


## 打赢第 floor_index 层的守关 Boss 给多少金币（规矩同上，rng 来自 rng_for）
static func boss_gold(floor_index: int, rng: RandomNumberGenerator) -> int:
	return rng.randi_range(BOSS_GOLD_MIN, BOSS_GOLD_MAX) + BOSS_GOLD_PER_FLOOR * floor_index


# ---------------------------------------------------------------- 怪

## 第 step 步（0 起）刷几只怪。越走越多，Boss 步不走这里。
static func enemies_for_step(step: int) -> int:
	return clampi(2 + step, 2, 6)


## 第 floor_index 层、第 step 步的一只普通怪。
## ★ 不改 DemoContent.make_monster() 的基础数值 ★ —— 那是单元测试的基准怪。
##   这里在它身上叠一层带 source 的词缀做成长曲线：
##   · 步内曲线：第 1 步比基准怪弱一半（开局只有孤杖孤石），第 6 步已经更硬
##   · ★ 层间曲线：每深一层整体再抬一截 ★ —— 这就是"每层难度递增"
static func make_room_monster(step: int, floor_index: int = 0) -> CombatEntity:
	var m := DemoContent.make_monster()
	var f := float(floor_index)
	var life_scale := -0.5 + 0.22 * float(step) + 0.50 * f   # 每层 +50% 生命
	var dmg_scale := -0.35 + 0.18 * float(step) + 0.35 * f   # 每层 +35% 伤害
	m.gear_mods \
		.add(M.new(S.MAX_LIFE, M.Kind.INCREASED, life_scale, T.NONE, &"run_step")) \
		.add(M.new(S.DAMAGE, M.Kind.INCREASED, dmg_scale, T.NONE, &"run_step"))
	return m.refill()


## 每层 Boss 的名字。前三层是守关 Boss，第 4 层才是最终 Boss「骸骨领主」。
const BOSS_NAMES: Array = ["骸骨队长", "骸骨男爵", "骸骨将军", "骸骨领主"]


## 第 floor_index 层的 Boss。就是一只被词缀堆到超规格的骷髅 ——
## 复用整套怪物管线，不用为 Boss 单写任何战斗逻辑。
## ★ 模板按最终 Boss 配，低层用负 INCREASED 往下调 ★
##   （第 1 层 ~3600 血 → 第 4 层 9000 血；伤害同理逐层放开）
static func make_boss(floor_index: int = RunMap.FLOORS - 1) -> CombatEntity:
	var f := clampi(floor_index, 0, RunMap.FLOORS - 1)
	var b := CombatEntity.new(&"bone_lord", str(BOSS_NAMES[f]))
	b.set_base(S.MAX_LIFE, 9000.0)
	b.set_base(S.ARMOUR, 2500.0)
	b.set_base(S.FIRE_RESIST, 0.40)
	b.set_base(S.COLD_RESIST, 0.30)
	b.set_base(S.LIGHTNING_RESIST, 0.30)
	b.set_base(S.CHAOS_RESIST, 0.0)
	# ★ 攻速要 set_base，不能用 INCREASED 词缀 ★ —— 普通怪从没设过 ATTACK_SPEED
	#   基础值（是 0），在 0 上"提高 30%"还是 0，是恒真数据。
	#   移动速度现在走属性系统了（冰缓要减速怪），但 Boss 故意不加移速 ——
	#   场地就 400×400，Boss 追得快玩家就没有走位空间了。
	b.set_base(S.ATTACK_SPEED, 0.5)   # 每 2 秒砍一刀（普通怪没设，是 10 秒一刀）
	b.gear_mods.add(M.new(S.DAMAGE, M.Kind.INCREASED, 0.80, T.NONE, &"boss"))
	# 低层的守关 Boss 往下调：每差一层 -20% 生命、-15% 伤害（INCREASED 区，和上面相加）
	var behind := RunMap.FLOORS - 1 - f
	if behind > 0:
		b.gear_mods \
			.add(M.new(S.MAX_LIFE, M.Kind.INCREASED, -0.20 * float(behind), T.NONE, &"floor_scale")) \
			.add(M.new(S.DAMAGE, M.Kind.INCREASED, -0.15 * float(behind), T.NONE, &"floor_scale"))
	return b.refill()
