class_name GemLink
extends RefCounted

## 「一颗主动技能石 + 现在正在辅助它的那些辅助宝石」。
##
## ★ 这不是一个你手动去插拔的东西 ★
##   它是 `GemGrid` 按**摆放位置**算出来的结果：辅助宝石的箭头指着谁就辅助谁。
##   所以你不会看到 socket() / unsocket() —— 想改连接就去背包里挪宝石。
##
## 它存在的意义只有一个：把"技能石 + 辅助"这一组打包交给战斗系统，
## 让 SkillGem.build() 和词缀汇总有个统一的入口。

var skill_gem: SkillGem = null
## Array[SupportGem]
var supports: Array = []
## 装着这颗技能石的法杖。★ 法杖的词缀只对槽里的技能生效（ADR-023）★
## 所以它的词缀和辅助宝石一起走 mods() → skill_mods，不走全局的 equip_mods。
var wand: EquipItem = null


func _init(p_skill: SkillGem = null, p_supports: Array = [], p_wand: EquipItem = null) -> void:
	skill_gem = p_skill
	supports = p_supports
	wand = p_wand


func is_empty() -> bool:
	return skill_gem == null


## 这一组当前实际使用的技能参数（等级、辅助的魔力倍率都算进去了）
func skill() -> SkillSpec:
	if skill_gem == null:
		return null
	return skill_gem.build(supports)


## 这一组的全部词缀：法杖自己的 + 辅助宝石的（Player 会把它塞进 stats.skill_mods）。
## 法杖词缀混在这层的意义：Q 切到别的法杖时整层换掉 —— 橡木法杖的
## 「更多 30% 法术伤害」就自动只属于它槽里的那颗技能。
func mods() -> Array:
	var out: Array = []
	if wand != null:
		out.append_array(wand.build_mods())
	for s in supports:
		out.append_array((s as SupportGem).build_mods())
	return out


func describe() -> String:
	if skill_gem == null:
		return "（空）"
	var names := PackedStringArray()
	for s in supports:
		names.append((s as SupportGem).display_name)
	if names.is_empty():
		return "%s Lv%d" % [skill_gem.display_name, skill_gem.level]
	return "%s Lv%d + %s" % [skill_gem.display_name, skill_gem.level, "/".join(names)]
