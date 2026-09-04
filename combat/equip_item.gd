class_name EquipItem
extends RefCounted

## 一件装备（法杖、头盔、戒指……）。
##
## ★ 装备就是"一组词缀 + 一个占地方的形状"★
##   和辅助宝石一样，它本身没有任何逻辑，只是一堆 Modifier。
##   区别只有两点：
##     ① 它不需要连线 —— **只要放在背包里就生效**（背包乱斗那套）
##     ② 它又大又占地方 —— 宝石都只占 1 格，装备占 1×3 / 2×2 / 2×3
##
## 所以摆放的取舍全在装备身上：
##   背包就这么大，装备摆得越舒服，留给"技能石 + 四面箭头"的空间就越少。

var id: StringName = &""
var display_name: String = ""
## UI 格子里显示的 1 个字
var short_name: String = "?"
var description: String = ""

## 占几格
var width: int = 1
var height: int = 1

## 提供的词缀模板。★ source 由 build_mods() 统一填成装备 id ★
## 这样脱下来时 `remove_by_source(id)` 就能整组摘掉
var mods: Array = []

## ★ 镶嵌槽位数：法杖 = 1，其它装备 = 0 ★
## 法杖是**技能的载体**：技能宝石必须镶进法杖才能施放，
## 辅助宝石的箭头指着法杖，就对里面镶着的技能宝石生效。
var socket_count: int = 0
## ★ 这个槽只收带这些标签的技能宝石（ADR-032）★ 法杖 = SPELL，近战武器 = ATTACK。
## 0 = 什么都收。火球镶不进铁剑、重击镶不进法杖 —— 载体决定了技能的类型。
var socket_tags: int = CombatTags.NONE
## 镶在槽里的技能宝石（socket_count > 0 时才有意义）。
## ★ 宝石住在装备身上，不占网格格子 ★ —— 拿起法杖时宝石跟着一起走。
var socketed: SkillGem = null

# 装备暂时不随等级成长（max_level = 1），但要留着这两个成员 ——
# 界面上的 [-] [+] 是对"当前显示的东西"操作的，不区分宝石还是装备。
var level: int = 1
var max_level: int = 1


func _init(p_id: StringName = &"", p_name: String = "", p_w: int = 1, p_h: int = 1) -> void:
	id = p_id
	display_name = p_name
	width = maxi(1, p_w)
	height = maxi(1, p_h)


func clamp_level(lv: int) -> int:
	return clampi(lv, 1, max_level)


## 这件装备是不是"技能载体"（带镶嵌槽的法杖 / 武器）
func has_socket() -> bool:
	return socket_count > 0


## 是近战武器吗（槽只收攻击技能）
func is_weapon() -> bool:
	return has_socket() and (socket_tags & CombatTags.ATTACK) != 0


## 这颗技能宝石能不能镶进这个槽（标签必须全包含 socket_tags）
func accepts_gem(gem: SkillGem) -> bool:
	if not has_socket() or gem == null:
		return false
	return CombatTags.has_all(gem.tags, socket_tags)


## 槽的类型名（给拒绝提示 / 面板用）
func socket_kind_name() -> String:
	if (socket_tags & CombatTags.ATTACK) != 0:
		return "攻击技能"
	if (socket_tags & CombatTags.SPELL) != 0:
		return "法术技能"
	return "技能"


## 按 id 打上 source 之后的实际词缀
func build_mods() -> Array:
	var out: Array = []
	for m in mods:
		var mod := m as Modifier
		out.append(Modifier.new(mod.stat, mod.kind, mod.value, mod.required_tags, id))
	return out


func tooltip() -> String:
	var l := PackedStringArray()
	l.append("[b][color=#e0b874]%s[/color][/b]  [color=#9a9aac]装备 %d×%d[/color]" % [
		display_name, width, height])
	if description != "":
		l.append("[color=#8a8a9c]%s[/color]" % description)
	l.append("[color=#7a7a8c]────────────[/color]")
	for m in build_mods():
		l.append("  · %s" % (m as Modifier).describe())
	if has_socket():
		if socketed != null:
			l.append("[color=#8fd0ff]◈ 镶嵌中：「%s」Lv%d[/color]" % [socketed.display_name, socketed.level])
		else:
			l.append("[color=#9a9aac]◈ 槽位是空的 —— 拿一颗技能宝石点上来镶入[/color]")
		l.append("[color=#9a9aac]◈ 这个槽只收：%s[/color]" % socket_kind_name())
		if not mods.is_empty():
			l.append("[color=#7a7a8c]★ 载体的词缀只对槽里镶着的技能生效 ★[/color]")
		l.append("[color=#7a7a8c]辅助宝石的箭头指着它，就对镶着的技能生效[/color]")
	else:
		l.append("[color=#7a7a8c]放在背包里就生效，不需要连箭头[/color]")
	return "\n".join(l)
