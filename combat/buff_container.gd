class_name BuffContainer
extends RefCounted

## 挂在一个角色身上的所有 Buff/Debuff。
##
## 职责：
##   1. 按 StackRule 处理施加逻辑
##   2. 推进计时、移除过期、报告周期结算
##   3. 把所有生效的词缀汇总成一个 StatSet（带脏标记缓存）
##
## 注意这里**没有引用任何 Godot 节点**，纯逻辑，可以脱离游戏跑测试。

var _instances: Array[BuffInstance] = []
var _cache: StatSet = null
var _uid_counter: int = 0


## 施加一个 Buff。
## snapshot_damage < 0 时使用 def.dot_damage 原值（不快照施法者加成）。
func apply(def: BuffDef, source: StringName = &"", snapshot_damage: float = -1.0) -> BuffInstance:
	var snap := def.dot_damage if snapshot_damage < 0.0 else snapshot_damage

	match def.stack_rule:
		BuffDef.StackRule.INDEPENDENT:
			# 每次都是新实例，各自计时
			return _add_new(def, source, snap)

		BuffDef.StackRule.REFRESH:
			var e := find(def.id, source)
			if e != null:
				e.remaining = def.duration
				e.snapshot_dot_damage = snap
				return e
			return _add_new(def, source, snap)

		BuffDef.StackRule.STACK_COUNT:
			var e2 := find(def.id, source)
			if e2 != null:
				e2.stacks = mini(e2.stacks + 1, maxi(1, def.max_stacks))
				e2.remaining = def.duration
				e2.snapshot_dot_damage = snap
				_dirty()   # 层数变了，词缀强度也变了
				return e2
			return _add_new(def, source, snap)

		BuffDef.StackRule.HIGHEST:
			# 跨来源比较：全场只保留最强的那一个
			var cur := find_by_id(def.id)
			if cur != null:
				if def.power() > cur.def.power():
					_instances.erase(cur)
					return _add_new(def, source, snap)
				# 新的更弱：保留旧的，只刷新时长
				cur.remaining = cur.def.duration
				return cur
			return _add_new(def, source, snap)

	return _add_new(def, source, snap)


## 推进计时。返回本次**触发了周期结算**的实例（DoT 由外部的
## DamagePipeline 负责结算伤害，这样这一层不依赖伤害管线，避免循环引用）。
func tick(delta: float) -> Array[BuffInstance]:
	var ticked: Array[BuffInstance] = []
	var changed := false

	# 倒序遍历，边遍历边删除才安全
	for i in range(_instances.size() - 1, -1, -1):
		var inst := _instances[i]

		if inst.def.period > 0.0:
			inst._period_timer += delta
			# while 而不是 if：delta 很大时（低帧率/快进）要补齐多次结算
			while inst._period_timer >= inst.def.period:
				inst._period_timer -= inst.def.period
				ticked.append(inst)

		if inst.def.duration > 0.0:
			inst.remaining -= delta
			if inst.remaining <= 0.0:
				_instances.remove_at(i)
				changed = true

	if changed:
		_dirty()
	return ticked


## 按 id 查找（忽略来源）。用于 HIGHEST 和 UI 显示。
func find_by_id(id: StringName) -> BuffInstance:
	for inst in _instances:
		if inst.def.id == id:
			return inst
	return null


## 按 id + 来源查找。REFRESH / STACK_COUNT 用这个，
## 所以"两个不同玩家施加的同名 Debuff"是各自独立的。
func find(id: StringName, source: StringName) -> BuffInstance:
	for inst in _instances:
		if inst.def.id == id and inst.source == source:
			return inst
	return null


func has(id: StringName) -> bool:
	return find_by_id(id) != null


## 某个 Buff 的总层数（INDEPENDENT 时是实例个数之和）
func stacks_of(id: StringName) -> int:
	var n := 0
	for inst in _instances:
		if inst.def.id == id:
			n += inst.stacks
	return n


func count_of(id: StringName) -> int:
	var n := 0
	for inst in _instances:
		if inst.def.id == id:
			n += 1
	return n


func remove(id: StringName) -> void:
	var kept: Array[BuffInstance] = []
	for inst in _instances:
		if inst.def.id != id:
			kept.append(inst)
	if kept.size() != _instances.size():
		_instances = kept
		_dirty()


func remove_from_source(source: StringName) -> void:
	var kept: Array[BuffInstance] = []
	for inst in _instances:
		if inst.source != source:
			kept.append(inst)
	if kept.size() != _instances.size():
		_instances = kept
		_dirty()


func clear() -> void:
	_instances.clear()
	_dirty()


func active() -> Array[BuffInstance]:
	return _instances


## 所有 Buff 词缀汇总。懒重建 + 脏标记：
## 只有 Buff 增删或层数变化时才重算，每帧查询属性是不花钱的。
func stat_set() -> StatSet:
	if _cache == null:
		_cache = StatSet.new()
		for inst in _instances:
			_cache.add_all(inst.effective_mods())
	return _cache


func _add_new(def: BuffDef, source: StringName, snap: float) -> BuffInstance:
	_uid_counter += 1
	var inst := BuffInstance.new(def, source, _uid_counter, snap)
	_instances.append(inst)
	_dirty()
	return inst


func _dirty() -> void:
	_cache = null
