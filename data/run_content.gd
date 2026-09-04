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
	&"ice_spear": 30, &"rolling_magma": 30, &"incinerate": 30, &"lightning_tendrils": 30,
	&"essence_drain": 30,
	&"crackling_lance": 30, &"eye_of_winter": 30, &"soulrend": 30, &"ethereal_knives": 30,
	&"ice_nova": 30, &"shock_nova": 30, &"storm_call": 30,
	&"firestorm": 30, &"vortex": 30, &"contagion": 30,
	&"heavy_strike": 25, &"cleave": 25, &"ground_slam": 28, &"double_strike": 25, &"cyclone": 30,
	&"infernal_blow": 28, &"glacial_hammer": 28, &"static_strike": 28, &"viper_strike": 25,
	&"spectral_throw": 28, &"glacial_cascade": 30,
	# 近战武器（技能载体，和法杖一档）
	&"iron_sword": 25, &"war_axe": 30, &"great_maul": 35, &"dagger": 22,
	# 崇高辅助：比普通辅助贵一倍（第 3 层起才上货架）
	&"sub_area": 45, &"sub_conc": 45, &"sub_less_duration": 45, &"sub_cascade": 45,
	&"apprentice_wand": 20,
	&"staff": 35, &"iron_helm": 30, &"traveller_boots": 25, &"ring_of_flame": 15,
	&"arcane_belt": 25, &"sapphire_amulet": 18,
	# 触媒（特殊辅助）：统一 28 —— 自动触发很值钱，比普通辅助贵一档
	&"cat_shock": 28, &"cat_ignite": 28, &"cat_chill": 28,
	&"cat_hits": 28, &"cat_move": 28, &"cat_timer": 28,
}
const DEFAULT_PRICE := 22

## 商店一次进多少货：1 颗技能石 + 2 颗辅助 + 2 件装备（+ 深层 1 颗崇高）
const SHOP_ACTIVES := 1
const SHOP_SUPPORTS := 2
const SHOP_EQUIPS := 2
const SHOP_SUBLIME := 1

## ★ 崇高辅助的门槛（ADR-031）★ 第 2 层（下标 1）起进奖励池、第 3 层（下标 2）起上货架。
## 第 1 层是孤杖孤石的开荒期，崇高的负面（更少伤害 / 更慢施法）在那时候只是坑。
const SUBLIME_REWARD_FLOOR := 1
const SUBLIME_SHOP_FLOOR := 2


# ---------------------------------------------------------------- 奖励池

## 交给 RunRewards.roll_options() 的候选池。
##   owned —— 背包里已有的宝石（升级奖励从这里挑），由调用方传（这里拿不到玩家）
##   floor_index —— 第几层（0 起）。第 SUBLIME_REWARD_FLOOR 层起辅助池混进崇高辅助
static func reward_pools(owned: Array, floor_index: int = 0) -> Dictionary:
	var supports: Array = GemLibrary.all_supports()
	if floor_index >= SUBLIME_REWARD_FLOOR:
		supports.append_array(GemLibrary.all_sublime())
	return {
		"gems": GemLibrary.all_actives(),
		"supports": supports,
		"equips": EquipLibrary.all_items(),
		"owned": owned,
	}


## 守关 Boss 必掉的血脉辅助：从还没拿到的里面抽一颗（owned_ids = 背包里已有的血脉 id）。
## 全拿齐了返回 null（一局 3 个守关 Boss、3 颗血脉，正常打法刚好一人一颗）。
## ★ rng 来自 RunState.rng_for("lineage") ★ → 同局同 Boss 掉同一颗，读档重打不能刷
static func boss_lineage(owned_ids: Array, rng: RandomNumberGenerator) -> SupportGem:
	var pool: Array = []
	for g in GemLibrary.all_lineage():
		if not owned_ids.has((g as SupportGem).id):
			pool.append(g)
	var picked := RunRewards.pick_distinct(pool, 1, rng)
	return null if picked.is_empty() else picked[0]


# ---------------------------------------------------------------- 商店

static func price_of(thing) -> int:
	return int(PRICES.get(thing.id, DEFAULT_PRICE))


## 进货。用调用方给的 rng（来自 RunState.rng_for("shop")）→
## 同一局同一步的商店，退出重进、读档重开，货架都一模一样。
##   floor_index —— 第 SUBLIME_SHOP_FLOOR 层起多进 SHOP_SUBLIME 颗崇高辅助
static func shop_stock(rng: RandomNumberGenerator, floor_index: int = 0) -> Array:
	var stock: Array = []
	stock.append_array(RunRewards.pick_distinct(GemLibrary.all_actives(), SHOP_ACTIVES, rng))
	stock.append_array(RunRewards.pick_distinct(GemLibrary.all_supports(), SHOP_SUPPORTS, rng))
	stock.append_array(RunRewards.pick_distinct(EquipLibrary.all_items(), SHOP_EQUIPS, rng))
	if floor_index >= SUBLIME_SHOP_FLOOR:
		stock.append_array(RunRewards.pick_distinct(GemLibrary.all_sublime(), SHOP_SUBLIME, rng))
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


# ---------------------------------------------------------------- 怪：一个房间的编制

## ★ 一个房间的怪分波上场（ADR-028）★
##   总数比以前多了一倍不止（第 1 层第 1 步 4 只 → 第 4 层第 6 步 16 只），
##   但同一时刻场上最多 max_alive_for_step 只：死一只、隔 World.reinforce_delay 秒补一只。
##   场地只有 400×400，16 只一起上是围殴不是战斗；分波上场才有"清完一波再来一波"的节奏。

## 第 floor_index 层、第 step 步（0 起）这一房**总共**要打几只怪（含精英，不含 Boss）。
static func enemies_for_step(step: int, floor_index: int = 0) -> int:
	return clampi(4 + 2 * step + 2 * floor_index, 4, 16)


## 同一时刻场上最多几只。超出的在队列里排队，死一只补一只。
static func max_alive_for_step(step: int, floor_index: int = 0) -> int:
	return clampi(4 + step / 2 + floor_index, 4, 8)


## 这一房里有几只是精英（算在 enemies_for_step 的总数里，排在队列**最后**上场 —— 压轴）。
## 第 1 层第 4 步起才有；第 4 层开局就是 2 只。
static func elites_for_step(step: int, floor_index: int = 0) -> int:
	return clampi((step + 2 * floor_index) / 3, 0, 4)


## 第 floor_index 层的精英身上挂几条词条：前两层 1 条，后两层 2 条。
static func affix_count_for_floor(floor_index: int) -> int:
	return 1 + floor_index / 2


## Boss 房跟着 Boss 一起上场的护卫数。Boss 不再是单挑 —— 得一边躲 Boss 一边清杂兵。
static func boss_escorts(floor_index: int) -> int:
	return 2 + floor_index


## 精英怪的底子：在同步同层普通怪的基础上再 +80% 生命 / +30% 伤害（INCREASED，
## 和步/层曲线相加），然后再叠词条。体型 ×1.25（词条「巨型」在这之上再乘）。
const ELITE_LIFE := 0.80
const ELITE_DAMAGE := 0.30
const ELITE_SCALE := 1.25


## 这一房的完整名单：先普通怪、后精英。World 按顺序从队头往外放。
## ★ rng 来自 RunState.rng_for("elite") ★ → 同一局同一房的精英词条是定死的，
##   读档重打还是那几只，不能靠退出重进刷"好打的词条"。
static func room_roster(step: int, floor_index: int, rng: RandomNumberGenerator) -> Array:
	var total := enemies_for_step(step, floor_index)
	var elites := mini(elites_for_step(step, floor_index), total)
	var out: Array = []
	for i in total - elites:
		out.append(make_room_monster(step, floor_index))
	for i in elites:
		out.append(make_elite(step, floor_index, rng))
	return out


## 第 floor_index 层、第 step 步的一只精英怪。
static func make_elite(step: int, floor_index: int, rng: RandomNumberGenerator) -> CombatEntity:
	return make_elite_from(make_room_monster(step, floor_index),
			affix_count_for_floor(floor_index), rng)


## 把一只已经配好数值的怪升格成精英：底子加成 + affix_count 条互不重复的随机词条。
## 沙盒模式也用它（拿基准骷髅 + 1 条词条）。
## ★ 叠完所有词条再统一 refill ★ —— 每条词条都可能抬生命上限，中途 refill 会出生不满血。
static func make_elite_from(m: CombatEntity, affix_count: int, rng: RandomNumberGenerator) -> CombatEntity:
	m.gear_mods 		.add(M.new(S.MAX_LIFE, M.Kind.INCREASED, ELITE_LIFE, T.NONE, &"elite")) 		.add(M.new(S.DAMAGE, M.Kind.INCREASED, ELITE_DAMAGE, T.NONE, &"elite"))
	for a in MonsterAffixes.roll(affix_count, rng):
		(a as MonsterAffix).apply_to(m)
	# 名字带上词条：「迅捷·坚韧 骷髅战士」—— 玩家看一眼就知道这只怎么打
	if m.is_elite():
		m.display_name = "%s %s" % [m.affix_title(), m.display_name]
	return m.refill()


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
