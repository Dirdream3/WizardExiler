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
static func all_items() -> Array:
	return [apprentice_wand(), staff(), ring_of_flame(), iron_helm(), traveller_boots(),
			arcane_belt(), sapphire_amulet()]


## 按 id 造一件新装备。读存档时用。找不到返回 null。
static func make_item(id: StringName):
	for e in all_items():
		if (e as EquipItem).id == id:
			return e
	return null


## 开局身上带的这一套（`DemoContent.make_player()` 会把它的词缀装上）
static func default_loadout() -> Array:
	return all_items()


# ---------------------------------------------------------------- 内部

static func _make(id: StringName, name: String, short_name: String,
		w: int, h: int, desc: String, mods: Array) -> EquipItem:
	var e := EquipItem.new(id, name, w, h)
	e.short_name = short_name
	e.description = desc
	e.mods = mods
	return e
