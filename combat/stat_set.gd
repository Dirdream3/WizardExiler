class_name StatSet
extends RefCounted

## 一组词缀的容器，以及四段式计算的唯一实现处。
##
## 一个角色身上会有好几个 StatSet：装备的、天赋的、Buff 的……
## 查询时把它们"叠"在一起算（compute_layered），而不是提前合并 ——
## 这样 Buff 变化时不用重建装备的那份。

var _mods: Array[Modifier] = []


func add(m: Modifier) -> StatSet:
	_mods.append(m)
	return self


func add_all(ms: Array) -> StatSet:
	for m in ms:
		_mods.append(m)
	return self


## 移除某个来源的全部词缀（脱装备、关光环）
func remove_by_source(src: StringName) -> void:
	var kept: Array[Modifier] = []
	for m in _mods:
		if m.source != src:
			kept.append(m)
	_mods = kept


func clear() -> void:
	_mods.clear()


func size() -> int:
	return _mods.size()


func all() -> Array[Modifier]:
	return _mods


func compute(stat: int, tags: int, base: float) -> float:
	return compute_layered([self], stat, tags, base)


func breakdown(stat: int, tags: int, base: float) -> Dictionary:
	return breakdown_layered([self], stat, tags, base)


## ★ 核心公式 ★
##     最终值 = (基础值 + Σflat) × (1 + Σincreased) × Π(1 + more_i)
##
## 返回完整分解，而不只是一个数字 —— 这样伤害面板、词缀 tooltip、
## 以及将来做 Path of Building 那样的计算器都能直接复用。
static func breakdown_layered(sets: Array, stat: int, tags: int, base: float) -> Dictionary:
	# 补齐派生标签（火焰伤害自动也是元素伤害）
	var t := CombatTags.normalize(tags)

	var flat := 0.0
	var increased := 0.0
	var more := 1.0
	var used: Array[Modifier] = []

	for s in sets:
		if s == null:
			continue
		for m in (s as StatSet).all():
			if m.stat != stat:
				continue
			if not m.applies_to(t):
				continue
			used.append(m)
			match m.kind:
				Modifier.Kind.FLAT:
					flat += m.value
				Modifier.Kind.INCREASED:
					increased += m.value       # 相加，共用一个乘区
				Modifier.Kind.MORE:
					more *= (1.0 + m.value)    # 连乘，各自独立

	return {
		"base": base,
		"flat": flat,
		"increased": increased,
		"more": more,
		"total": (base + flat) * (1.0 + increased) * more,
		"mods": used,
	}


static func compute_layered(sets: Array, stat: int, tags: int, base: float) -> float:
	return breakdown_layered(sets, stat, tags, base)["total"]


## 把分解结果转成一行可读文本，方便调试。
static func format_breakdown(bd: Dictionary) -> String:
	return "(%.1f + %.1f) × (1 + %.0f%%) × %.3f = %.1f" % [
		bd["base"], bd["flat"], bd["increased"] * 100.0, bd["more"], bd["total"],
	]
