class_name EquipLibrary
extends RefCounted

## 装备图鉴。和宝石一样，全是**数据**，没有一行逻辑。
##
## ★ 装备的定位：占地方，但给全局属性 ★
##   宝石都只占 1 格，装备占 1×3 / 2×2 / 2×3 ——
##   背包就这么大，装备摆得越舒服，留给"技能石 + 四面箭头"的空间就越少。
##   这就是这套背包的核心取舍。
##
## ★ 「橡木法杖」和「烈焰戒指」的 id 不是随便起的 ★
##   以前这两组词缀是硬写在 `DemoContent.make_player()` 里的（source 就叫
##   staff / ring_of_flame）。现在把它们做成了真正的装备，id 保持不变 ——
##   这样角色的总加成一点没变（老的伤害测试全部照样过），
##   但它们终于有实物了：你能在背包里看见、拿起来、挪走。

const M = preload("res://combat/modifier.gd")
const T = preload("res://combat/combat_tags.gd")
const S = preload("res://combat/combat_stat.gd")


## 见习法杖 1×2 —— ★ 开局那根 ★ 没有任何词缀，它的全部价值就是那个镶嵌槽。
## 短 = 周身箭头位少（6 个邻格）→ 换成 1×3 的橡木法杖本身就是一次升级。
static func apprentice_wand() -> EquipItem:
	var e := _make(&"apprentice_wand", "见习法杖", "杖", 1, 2,
		"最朴素的法杖。没有词缀，但有一个镶嵌槽 —— 技能宝石镶进去才能施放。",
		[])
	e.socket_count = 1
	e.socket_tags = T.SPELL   # 法杖只收法术（ADR-032）
	return e


## 橡木法杖 1×3 —— 法术流的核心，又长又难摆
static func staff() -> EquipItem:
	var e := _make(&"staff", "橡木法杖", "杖", 1, 3,
		"细长的法杖，竖着占三格。法术伤害的主要来源。",
		[
			M.new(S.DAMAGE, M.Kind.MORE, 0.30, T.SPELL),
			M.new(S.CAST_SPEED, M.Kind.INCREASED, 0.25, T.NONE),
		])
	e.socket_count = 1
	e.socket_tags = T.SPELL
	return e


# ---------------------------------------------------------------- 近战武器（ADR-032）
#
# ★ 武器 = 攻击技能的载体 ★ 和法杖一模一样的槽，只是只收【攻击】技能。
# 攻击技能自己的点伤很低，大头是武器上的「增加 N 点攻击伤害」（FLAT，要求 ATTACK 标签）——
# 走 skill_mods 只加给槽里那颗技能：换武器 = 换这个技能的伤害底子（PoE 的"武器伤害"就是这个意思）。
# 所有词缀都要求 ATTACK：放在背包里对法术零影响，基准角色（make_player）也不带它们。

## 铁剑 1×3 —— 均衡：中等伤害、稍快
static func iron_sword() -> EquipItem:
	var e := _make(&"iron_sword", "铁剑", "剑", 1, 3,
		"最普通的剑。攻击伤害 +70、攻速 +10%。攻击技能镶进来才能挥。",
		[
			M.new(S.DAMAGE, M.Kind.FLAT, 70.0, T.ATTACK),
			M.new(S.ATTACK_SPEED, M.Kind.INCREASED, 0.10, T.ATTACK),
		])
	e.socket_count = 1
	e.socket_tags = T.ATTACK
	return e


## 战斧 2×2 —— 重：近战伤害提高，攻速慢一点
static func war_axe() -> EquipItem:
	var e := _make(&"war_axe", "战斧", "斧", 2, 2,
		"占 2×2 的大斧。攻击伤害 +110、近战伤害提高 15%，但攻速 −10%。",
		[
			M.new(S.DAMAGE, M.Kind.FLAT, 110.0, T.ATTACK),
			M.new(S.DAMAGE, M.Kind.INCREASED, 0.15, T.ATTACK | T.MELEE),
			M.new(S.ATTACK_SPEED, M.Kind.INCREASED, -0.10, T.ATTACK),
		])
	e.socket_count = 1
	e.socket_tags = T.ATTACK
	return e


## 巨锤 2×3 —— 最重：伤害最高、挥砍范围更大，攻速最慢
static func great_maul() -> EquipItem:
	var e := _make(&"great_maul", "巨锤", "锤", 2, 3,
		"占 2×3 的巨锤。攻击伤害 +170、攻击的范围 +30%，但攻速 −20%。横扫 / 重锤猛击的最佳搭档。",
		[
			M.new(S.DAMAGE, M.Kind.FLAT, 170.0, T.ATTACK),
			M.new(S.AREA_OF_EFFECT, M.Kind.INCREASED, 0.30, T.ATTACK),
			M.new(S.ATTACK_SPEED, M.Kind.INCREASED, -0.20, T.ATTACK),
		])
	e.socket_count = 1
	e.socket_tags = T.ATTACK
	return e


## 匕首 1×2 —— 快而准：伤害低、攻速和暴击高。毒蛇打击 / 双重打击的搭档
static func dagger() -> EquipItem:
	var e := _make(&"dagger", "匕首", "匕", 1, 2,
		"只占两格的匕首。攻击伤害 +45，攻速 +25%、攻击暴击率提高 60%。堆出手次数的武器。",
		[
			M.new(S.DAMAGE, M.Kind.FLAT, 45.0, T.ATTACK),
			M.new(S.ATTACK_SPEED, M.Kind.INCREASED, 0.25, T.ATTACK),
			M.new(S.CRIT_CHANCE, M.Kind.INCREASED, 0.60, T.ATTACK),
		])
	e.socket_count = 1
	e.socket_tags = T.ATTACK
	return e


## 烈焰戒指 1×1 —— 很小，但只对火焰技能有用
static func ring_of_flame() -> EquipItem:
	return _make(&"ring_of_flame", "烈焰戒指", "戒", 1, 1,
		"只占一格。★ 只加火焰伤害 ★ —— 用电球术的时候它一点用都没有。",
		[
			M.new(S.DAMAGE, M.Kind.FLAT, 15.0, T.FIRE),
			M.new(S.DAMAGE, M.Kind.INCREASED, 1.20, T.FIRE),
		])


## 铁头盔 2×2 —— 纯防御，占一大块
static func iron_helm() -> EquipItem:
	return _make(&"iron_helm", "铁头盔", "头", 2, 2,
		"占 2×2 的一大块。换来生命和护甲。",
		[
			M.new(S.MAX_LIFE, M.Kind.FLAT, 200.0, T.NONE),
			M.new(S.ARMOUR, M.Kind.FLAT, 150.0, T.NONE),
		])


## 旅者之靴 2×2 —— 跑得快，在小场地里比看起来有用
static func traveller_boots() -> EquipItem:
	return _make(&"traveller_boots", "旅者之靴", "靴", 2, 2,
		"提高移动速度。场地只有 400×400，跑得快就是躲得掉。",
		[M.new(S.MOVE_SPEED, M.Kind.INCREASED, 0.20, T.NONE)])


## 秘法腰带 3×1 —— 回蓝的大头：横着占一条，换来稳定的蓝耗续航
static func arcane_belt() -> EquipItem:
	return _make(&"arcane_belt", "秘法腰带", "带", 3, 1,
		"横着占一条的宽腰带。魔力回复 +8/秒，外加一截魔力上限 —— 连了一堆辅助之后蓝不够用，靠它续。",
		[
			M.new(S.MANA_REGEN, M.Kind.FLAT, 8.0, T.NONE),
			M.new(S.MAX_MANA, M.Kind.FLAT, 60.0, T.NONE),
		])


## 蓝玉护符 1×1 —— 只占一格的回蓝倍率件，和腰带的 FLAT 是不同乘区
static func sapphire_amulet() -> EquipItem:
	return _make(&"sapphire_amulet", "蓝玉护符", "珀", 1, 1,
		"只占一格。提高 50% 魔力回复 —— 是「提高」乘区，和腰带的 +8/秒 相乘生效。",
		[M.new(S.MANA_REGEN, M.Kind.INCREASED, 0.50, T.NONE)])


## 全部装备。每次调用都是**新的实例**。
## ★ 见习法杖也在池子里 ★ —— 多一根法杖 = 多一个能同时携带的技能（Q 切换）。
## 近战武器（ADR-032）也在：拿到武器 + 攻击技能才能打近战。
static func all_items() -> Array:
	return [apprentice_wand(), staff(), ring_of_flame(), iron_helm(), traveller_boots(),
			arcane_belt(), sapphire_amulet(),
			iron_sword(), war_axe(), great_maul(), dagger()]


## 全部近战武器
static func all_weapons() -> Array:
	return [iron_sword(), war_axe(), great_maul(), dagger()]


## 按 id 造一件新装备。读存档时用。找不到返回 null。
static func make_item(id: StringName):
	for e in all_items():
		if (e as EquipItem).id == id:
			return e
	return null


## 开局身上带的这一套（`DemoContent.make_player()` 会把它的词缀装上）。
## ★ 故意不含近战武器 ★ —— 基准角色是老的那 7 件，所有老的伤害断言都建立在它上面；
##   武器的词缀全要求 ATTACK 标签，就算装上也不影响法术，但没必要动基准。
static func default_loadout() -> Array:
	return [apprentice_wand(), staff(), ring_of_flame(), iron_helm(), traveller_boots(),
			arcane_belt(), sapphire_amulet()]


# ---------------------------------------------------------------- 内部

static func _make(id: StringName, name: String, short_name: String,
		w: int, h: int, desc: String, mods: Array) -> EquipItem:
	var e := EquipItem.new(id, name, w, h)
	e.short_name = short_name
	e.description = desc
	e.mods = mods
	return e
