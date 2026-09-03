class_name RunRewards
extends RefCounted

## 奖励三选一的**掷骰规则**。纯逻辑、零 Godot 场景依赖。
##
## ★ 这里不认识 GemLibrary / EquipLibrary ★ —— 候选池由调用方传进来。
##   run/ 只依赖 combat/，不依赖 data/（依赖方向：game → data → run → combat）。
##   好处：单测时传几个假对象进来就能验规则，不用把整个图鉴拖下水。
##
## 一个"奖励选项"统一用 Dictionary 表示（跨层传数据用字典最省事）：
##   { "kind": RunMap.RewardKind, "item": 宝石或装备(可无), "gem": 要升级的宝石(可无), "label": 给按钮显示的字 }
##
## ★ 金币不在这里 ★ —— 金币不是三选一奖励，每清一个战斗房自动进账
##   （数额见 RunContent.room_gold）。


## 按房间外显的奖励类型掷出三选一。
##   kind    —— RunMap.RewardKind
##   rng     —— 调用方用 RunState.rng_for() 拿到的确定性随机源
##   pools   —— { "gems": [...], "supports": [...], "equips": [...], "owned": [背包里已有的宝石...] }
## 返回最多 3 个选项；池子不够 3 个就有几个给几个（升级奖励常见：开局只有一颗宝石）。
static func roll_options(kind: int, rng: RandomNumberGenerator, pools: Dictionary) -> Array:
	match kind:
		RunMap.RewardKind.GEM:
			return _item_options(kind, pick_distinct(pools.get("gems", []), 3, rng))
		RunMap.RewardKind.SUPPORT:
			return _item_options(kind, pick_distinct(pools.get("supports", []), 3, rng))
		RunMap.RewardKind.EQUIP:
			return _item_options(kind, pick_distinct(pools.get("equips", []), 3, rng))
		RunMap.RewardKind.UPGRADE:
			var out: Array = []
			# 只有还没满级的宝石才配出现在升级列表里 —— 满级的升了也没变化，是恒真选项
			var can_up: Array = []
			for g in pools.get("owned", []):
				if g.level < g.max_level:
					can_up.append(g)
			for g in pick_distinct(can_up, 3, rng):
				out.append({
					"kind": kind, "gem": g,
					"label": "升级：%s  Lv%d → Lv%d" % [g.display_name, g.level, g.level + 1],
				})
			return out
	return []


## 从池子里无放回地抽 count 个。池子不够就全给。
## ★ 用传进来的 rng，不碰全局随机 ★ —— 否则"读档回来奖励变了"。
static func pick_distinct(pool: Array, count: int, rng: RandomNumberGenerator) -> Array:
	var arr := pool.duplicate()
	var out: Array = []
	while out.size() < count and not arr.is_empty():
		out.append(arr.pop_at(rng.randi_range(0, arr.size() - 1)))
	return out


static func _item_options(kind: int, items: Array) -> Array:
	var out: Array = []
	for it in items:
		out.append({"kind": kind, "item": it, "label": it.display_name})
	return out
