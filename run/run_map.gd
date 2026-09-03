class_name RunMap
extends RefCounted

## **一层**的地图：玩家从第 1 步走到第 7 步，每步在 2~3 个房间里选一个进。
##
## ★ 一局 = FLOORS 层，每层一张这样的图 ★（层与层的流转在 RunState）
##   每层最后一步是这一层的守关 Boss；最后一层的才是最终 Boss。
##   层数越深怪越硬（数值在 RunContent.make_room_monster / make_boss）。
##
## ★ 这个文件是纯逻辑，规矩和 combat/ 完全一样：不许出现任何 Godot 场景依赖 ★
##   地图只是"数据 + 生成规则"，这样才能在 headless 下断言：
##   同一个种子必须生成同一张图、商店不会出现在开局、最后一步必是 Boss……
##
## ★ 整张图由一个种子决定 ★（杀戮尖塔的做法）
##   存档只需要存种子，不用存整张图 —— 读档时重新 generate 一遍就是原图。
##   玩家报 bug 时拿到种子也能复现整局。

## 一局一共几层。每往下一层，怪和 Boss 都更硬。
const FLOORS := 4

## 一层走几步。第 1~6 步是战斗/商店，第 7 步固定是这一层的 Boss。
const STEPS := 7

## 每一步给几个房间选（下限/上限）
const MIN_ROOMS := 2
const MAX_ROOMS := 3

## 整张图固定放几个商店。
## 开局没钱，商店放太早毫无意义 → 只允许出现在第 SHOP_EARLIEST+1 步以后。
const SHOP_COUNT := 2
const SHOP_EARLIEST := 2   ## 商店最早出现在下标 2（= 玩家的第 3 步）

enum RoomType { COMBAT, SHOP, BOSS }

## 战斗房间打完的奖励类型。★ 外显在节点上 ★ —— 玩家选路时就能看到打赢给什么。
## ★ 没有「金币」这一种 ★ —— 金币不占奖励位，每清一个战斗房自动进账
##   （数额在 RunContent.room_gold）。金币房当年的问题：选它 = 这一步白走，
##   构筑不变强，下一步的怪却更硬了。
enum RewardKind { GEM, EQUIP, SUPPORT, UPGRADE }


## 一个房间。只是数据，没有行为。
class Room extends RefCounted:
	var type: int = RoomType.COMBAT
	## 打赢后三选一的奖励类型。★ 守关 Boss 也有 ★（打赢层 Boss 同样领奖励）；
	## 只有最终 Boss 没有 —— 打赢它整局就结束了。
	var reward: int = RewardKind.GEM
	## 这是不是整局最后的那个 Boss（第 FLOORS 层的）
	var is_final_boss := false

	func _init(p_type: int = RoomType.COMBAT, p_reward: int = RewardKind.GEM) -> void:
		type = p_type
		reward = p_reward

	## 地图节点上显示的字（表现层直接拿去用，免得 UI 里再写一遍 match）
	func label() -> String:
		match type:
			RoomType.SHOP:
				return "商店"
			RoomType.BOSS:
				if is_final_boss:
					return "最终 BOSS"
				return "守关 BOSS · 奖励：%s" % RunMap.reward_name(reward)
			_:
				return "战斗 · 奖励：%s" % RunMap.reward_name(reward)


var seed_value: int = 0
## 这张图是第几层的（0 起，0..FLOORS-1）。generate() 时传进来。
var floor_index: int = 0
## steps[i] = 第 i 步的房间列表（Array[Room]）。steps[6] 恒为 [一个 Boss 房]。
var steps: Array = []


static func reward_name(kind: int) -> String:
	match kind:
		RewardKind.GEM:     return "技能宝石"
		RewardKind.EQUIP:   return "装备"
		RewardKind.SUPPORT: return "辅助宝石"
		RewardKind.UPGRADE: return "升级宝石"
	return "?"


## ★ 生成一层的图。同一个 seed 必须得到同一张图 ★
## 所有随机都走这里 new 出来的 rng，绝不碰全局随机数 —— 碰了确定性就没了。
##   p_floor —— 这是第几层（0 起）。只影响 Boss 房：最后一层是最终 Boss，
##              其余层是带奖励外显的守关 Boss。
static func generate(p_seed: int, p_floor: int = 0) -> RunMap:
	var map := RunMap.new()
	map.seed_value = p_seed
	map.floor_index = p_floor
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed

	# --- 先决定商店在哪几步 ---
	# 从允许的步数（下标 SHOP_EARLIEST .. STEPS-2）里洗牌取前 SHOP_COUNT 个。
	var shop_steps := _shuffled(range(SHOP_EARLIEST, STEPS - 1), rng).slice(0, SHOP_COUNT)

	# --- 逐步生成 ---
	for i in STEPS - 1:
		var count := rng.randi_range(MIN_ROOMS, MAX_ROOMS)
		var rooms: Array = []

		# 每一步把 4 种奖励洗一遍牌、按序分给各房间 →
		# ★ 同一步里的奖励类型天然互不重复 ★，选哪个房间才是有意义的决策
		var kinds := _shuffled([RewardKind.GEM, RewardKind.EQUIP, RewardKind.SUPPORT,
				RewardKind.UPGRADE], rng)
		for k in count:
			rooms.append(Room.new(RoomType.COMBAT, kinds[k]))

		# 这一步该有商店 → 随机把其中一个房间换成商店
		if shop_steps.has(i):
			rooms[rng.randi_range(0, rooms.size() - 1)] = Room.new(RoomType.SHOP)

		map.steps.append(rooms)

	# 最后一步固定是 Boss，只有一个房间 —— 没有别的路可以绕。
	# 守关 Boss（非最后一层）也带奖励外显：打赢层 Boss 同样领三选一。
	var boss := Room.new(RoomType.BOSS,
			_shuffled([RewardKind.GEM, RewardKind.EQUIP, RewardKind.SUPPORT,
					RewardKind.UPGRADE], rng)[0])
	boss.is_final_boss = p_floor >= FLOORS - 1
	map.steps.append([boss])

	map._ensure_guarantees()
	return map


## 第 i 步的房间列表
func rooms_at(step: int) -> Array:
	if step < 0 or step >= steps.size():
		return []
	return steps[step]


## 整张图一共有几个商店（测试断言用）
func shop_count() -> int:
	var n := 0
	for row in steps:
		for r in row:
			if (r as Room).type == RoomType.SHOP:
				n += 1
	return n


## 把整张图压成一个字符串（测试比较"同种子同图"用，顺便给日志看）
func describe() -> String:
	var lines := PackedStringArray()
	for i in steps.size():
		var names := PackedStringArray()
		for r in steps[i]:
			names.append((r as Room).label())
		lines.append("第%d步: %s" % [i + 1, " | ".join(names)])
	return "\n".join(lines)


# ---------------------------------------------------------------- 内部

## ★ 兜底保证 ★ 纯随机可能整张图都刷不出某种奖励，构筑就断粮了：
##   · 开局背包只有一颗技能石 → 第 1 步必须给"能变强的东西"（宝石/装备/辅助），
##     全是金币/升级的话，第 1 步打完手里还是只有一颗光杆宝石
##   · 整张图必须至少各出现一次：辅助宝石、装备、技能宝石
## 修正只依赖已生成的内容，不再掷骰子 → 不破坏"同种子同图"。
func _ensure_guarantees() -> void:
	# 第 1 步至少一个"实物"奖励
	var first: Array = steps[0]
	var has_item := false
	for r in first:
		var room := r as Room
		if room.type == RoomType.COMBAT and room.reward in [RewardKind.GEM, RewardKind.EQUIP, RewardKind.SUPPORT]:
			has_item = true
	if not has_item:
		(first[0] as Room).reward = RewardKind.SUPPORT

	# 全图至少各出现一次：辅助 / 装备 / 技能宝石
	for need in [RewardKind.SUPPORT, RewardKind.EQUIP, RewardKind.GEM]:
		if _has_reward(need):
			continue
		# 找一个「升级」的战斗房换掉 —— 它是纯甜点（不给新东西），换掉最不伤
		var patched := false
		for row in steps:
			if patched:
				break
			for r in row:
				var room := r as Room
				if room.type == RoomType.COMBAT and room.reward == RewardKind.UPGRADE:
					room.reward = need
					patched = true
					break


func _has_reward(kind: int) -> bool:
	for row in steps:
		for r in row:
			var room := r as Room
			if room.type == RoomType.COMBAT and room.reward == kind:
				return true
	return false


## 用指定 rng 做 Fisher-Yates 洗牌。
## ★ 不用 Array.shuffle() ★ —— 它走全局随机数，"同种子同图"就废了。
static func _shuffled(src: Array, rng: RandomNumberGenerator) -> Array:
	var arr := src.duplicate()
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr
