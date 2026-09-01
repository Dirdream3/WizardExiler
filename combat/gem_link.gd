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


func _init(p_skill: SkillGem = null, p_supports: Array = []) -> void:
	skill_gem = p_skill
	supports = p_supports


func is_empty() -> bool:
	return skill_gem == null


## 这一组当前实际使用的技能参数（等级、辅助的魔力倍率都算进去了）
func skill() -> SkillSpec:
	if skill_gem == null:
		return null
	return skill_gem.build(supports)


## 这一组所有辅助宝石提供的词缀（Player 会把它塞进 stats.skill_mods）
func mods() -> Array:
	var out: Array = []
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
