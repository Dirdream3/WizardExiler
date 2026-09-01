class_name SupportGem
extends RefCounted

## 辅助宝石（PoE 的「支援宝石」）。
##
## ★ 辅助宝石本身不是一段代码，它就是「一组带代价的词缀」★
##   连上去 = 把这组词缀塞进 CombatEntity.skill_mods
##   拔下来 = 清掉
## 所以「增加 1 次弹射，仅限闪电技能」这种辅助，是纯数据，一行逻辑都不用写。
##
## 它和主动技能石的区别只有两点：
##   ① 有 required_tags：只能连到带这些标签的技能上（多重投射连不上近战技能）
##   ② 有 mana_multiplier：连得越多，技能的魔力消耗越贵 —— PoE 的主要平衡手段

var id: StringName = &""
var display_name: String = ""
## UI 格子里显示的 1 个字
var short_name: String = "?"
var description: String = ""

## 辅助宝石自己的标签（显示用，比如「投射物, 混合」）
var tags: int = CombatTags.NONE
## ★ 只能连到**同时带有**这些标签的技能上 ★（0 = 什么技能都能连）
var required_tags: int = CombatTags.NONE
## 连上后给技能**补**的标签。默认 0
var added_tags: int = CombatTags.NONE

var level: int = 1
var max_level: int = 20

## 魔力消耗倍率。1.4 = 技能变贵 40%
var mana_multiplier: float = 1.0

## 1 级时提供的词缀模板
var mods: Array = []
## 每升 1 级，对应 mods[i].value 的增量（可以不填，默认 0 = 不随等级变化）
var mod_growth: Array = []


func _init(p_id: StringName = &"", p_name: String = "", p_required: int = CombatTags.NONE) -> void:
	id = p_id
	display_name = p_name
	required_tags = p_required


## 这颗辅助能连到这组技能标签上吗
func can_support(skill_tags: int) -> bool:
	return CombatTags.has_all(CombatTags.normalize(skill_tags), required_tags)


## 移除时用的来源标识。同一颗宝石的所有词缀共用一个 source，方便整组拔掉。
func source_key() -> StringName:
	return StringName("gem_%s" % id)


## 按当前等级生成实际生效的词缀。
func build_mods() -> Array:
	var out: Array = []
	for i in mods.size():
		var m := mods[i] as Modifier
		var growth: float = float(mod_growth[i]) if i < mod_growth.size() else 0.0
		out.append(Modifier.new(
			m.stat, m.kind,
			m.value + growth * float(level - 1),
			m.required_tags,
			source_key()))
	return out


func clamp_level(lv: int) -> int:
	return clampi(lv, 1, max_level)


func tooltip() -> String:
	var l := PackedStringArray()
	l.append("[b][color=#8fd45a]%s[/color][/b]  [color=#9a9aac]等级 %d/%d[/color]" % [
		display_name, level, max_level])
	if required_tags != CombatTags.NONE:
		l.append("[color=#c8a24a]只能连：【%s】技能[/color]" % CombatTags.describe(required_tags))
	else:
		l.append("[color=#c8a24a]任何技能都能连[/color]")
	if description != "":
		l.append("[color=#8a8a9c]%s[/color]" % description)
	l.append("[color=#7a7a8c]────────────[/color]")
	l.append("魔力消耗倍率 [b]×%.2f[/b]" % mana_multiplier)
	for m in build_mods():
		l.append("  · %s" % (m as Modifier).describe())
	return "\n".join(l)
