class_name CombatEntity
extends RefCounted

## 一个战斗单位的**纯数据模型**（玩家、怪物、召唤物都用它）
##
## ★ 注意：这里没有 Node、没有 Sprite、没有位置坐标。★
## 表现层（一个 CharacterBody2D）应该**持有**一个 CombatEntity，而不是继承它。
## 这样整个战斗数值系统可以脱离引擎跑单元测试，将来也能直接搬到服务器做验算。

var id: StringName = &"entity"
var display_name: String = ""

## 基础属性（未经任何词缀）。key = CombatStat 枚举值
var base_stats: Dictionary = {}

## 角色**自带**的长期词缀：天赋、被动树。不随背包变化
var gear_mods := StatSet.new()

## ★ 背包里的装备提供的词缀 ★
##
## 和 skill_mods 一样是"整层重建"的：背包一变，Player 就把这一层清空重填。
## source 填的是装备 id，所以也能单独 remove_by_source(装备id) 模拟脱一件。
var equip_mods := StatSet.new()

## ★ 当前正在用的那组技能石带来的词缀（辅助宝石）★
##
## 为什么要和 gear_mods 分开？因为辅助宝石**只对它连着的那个技能生效** ——
## 「多重投射」连在电球上，不该让你的火球也变成多发。
## 切技能时把这一层整个换掉就行，不用一条条 remove_by_source。
var skill_mods := StatSet.new()

## 临时词缀：Buff / Debuff
var buffs := BuffContainer.new()

var life: float = 0.0
var mana: float = 0.0


func _init(p_id: StringName = &"entity", p_name: String = "") -> void:
	id = p_id
	display_name = p_name if p_name != "" else String(p_id)


func set_base(stat: int, value: float) -> CombatEntity:
	base_stats[stat] = value
	return self


func base_of(stat: int) -> float:
	return float(base_stats.get(stat, 0.0))


## 查询某条属性的最终值。
##   tags —— 查询上下文标签，决定哪些条件词缀生效
##   base —— 显式基础值（技能伤害之类）。不传则用角色自己的 base_stats
func get_stat(stat: int, tags: int = CombatTags.NONE, base: float = NAN) -> float:
	var b: float = base_of(stat) if is_nan(base) else base
	return StatSet.compute_layered(_layers(), stat, tags, b)


## 同上，但返回完整的四段式分解（面板、tooltip、调试用）
func stat_breakdown(stat: int, tags: int = CombatTags.NONE, base: float = NAN) -> Dictionary:
	var b: float = base_of(stat) if is_nan(base) else base
	return StatSet.breakdown_layered(_layers(), stat, tags, b)


func max_life() -> float:
	return get_stat(CombatStat.MAX_LIFE)


func max_mana() -> float:
	return get_stat(CombatStat.MAX_MANA)


## 按当前上限把生命/魔力充满。装备变化后记得调。
func refill() -> CombatEntity:
	life = max_life()
	mana = max_mana()
	return self


func is_alive() -> bool:
	return life > 0.0


func take_damage(amount: float) -> void:
	life = maxf(0.0, life - amount)


func heal(amount: float) -> void:
	life = minf(max_life(), life + amount)


## 对应伤害标签的抗性，已经按 75% 上限截断（负抗性不截断）
func resist_for(tags: int) -> float:
	var rs := CombatStat.resist_stat_for_tags(tags)
	if rs < 0:
		return 0.0
	return minf(get_stat(rs, tags), CombatStat.RESIST_CAP)


## 施加一个 Buff。
##   from —— 施加者。传了的话，DoT 伤害会在此刻**快照**施加者的加成
##           （PoE 的点燃/中毒就是这个行为：上身之后不再受施加者属性变化影响）
func apply_buff(def: BuffDef, from: CombatEntity = null, source: StringName = &"") -> BuffInstance:
	var snap := -1.0
	if from != null and def.dot_damage > 0.0:
		snap = from.get_stat(CombatStat.DAMAGE, def.dot_tags | CombatTags.DOT, def.dot_damage)

	var src := source
	if src == &"":
		src = from.id if from != null else &""
	return buffs.apply(def, src, snap)


## 推进 Buff 计时。返回本帧触发周期结算的实例，
## 由 DamagePipeline.resolve_dots() 负责把它们变成实际伤害。
func tick_buffs(delta: float) -> Array[BuffInstance]:
	return buffs.tick(delta)


func _layers() -> Array:
	return [gear_mods, equip_mods, skill_mods, buffs.stat_set()]
