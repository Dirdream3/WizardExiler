class_name BuffInstance
extends RefCounted

## Buff 的**运行时实例**（挂在某个角色身上的那一份）
##
## BuffDef 是模板（"点燃"这个概念），BuffInstance 是具体某只怪身上
## 那个还剩 2.3 秒、由玩家施加的点燃。

var def: BuffDef
## 谁施加的。用于分来源结算和"移除某人施加的全部 Debuff"
var source: StringName = &""
## 唯一编号，INDEPENDENT 规则下用来区分同名实例
var uid: int = 0

var remaining: float = 0.0
var stacks: int = 1

## 施加瞬间快照下来的每跳伤害（已经算过施法者的加成）
var snapshot_dot_damage: float = 0.0

var _period_timer: float = 0.0


func _init(p_def: BuffDef = null, p_source: StringName = &"", p_uid: int = 0, p_snapshot: float = 0.0) -> void:
	def = p_def
	source = p_source
	uid = p_uid
	if def != null:
		remaining = def.duration
	snapshot_dot_damage = p_snapshot


## 考虑层数之后实际生效的词缀。
## 1 层时直接返回模板数组，避免每次查询都创建对象。
func effective_mods() -> Array[Modifier]:
	if def == null:
		return []
	if stacks <= 1:
		return def.mods
	var out: Array[Modifier] = []
	for m in def.mods:
		out.append(m.scaled(float(stacks)))
	return out


## 一次周期结算的伤害（未经防守方减免）
func tick_damage() -> float:
	return snapshot_dot_damage * float(stacks)


func is_permanent() -> bool:
	return def != null and def.duration <= 0.0


func describe() -> String:
	var s := def.display_name
	if stacks > 1:
		s += " ×%d" % stacks
	if not is_permanent():
		s += "  (%.1fs)" % remaining
	return s
