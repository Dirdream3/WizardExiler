class_name RunState
extends RefCounted

## 一局游戏的状态机：走到第几步、多少金币、当前在哪个阶段。
##
## ★ 纯逻辑，零 Godot 场景依赖 ★ —— 整条"选房 → 打 → 领奖 → 下一步"的
##   流转规则都在这里，能脱离游戏单测。表现层（world / run_ui）只负责
##   把这里的状态画出来、把玩家的点击翻译成这里的方法调用。
##
## 阶段流转（唯一合法的路径）：
##
##   CHOOSE 选房间 ──enter_room()──▶ ROOM 房间里
##      ▲                              │
##      │                    战斗房打赢 complete_combat() ─▶ REWARD 三选一
##      │                              │（商店房逛完除外：ROOM 直接 advance）
##      └────── advance() ◀────────────┘
##              下一步，步数 +1；★ 守关 Boss 领完奖 → 下一层，步数归零 ★
##
##   最终 Boss（第 FLOORS 层的）打赢 → DONE（victory = true）
##   玩家阵亡 → fail() → DONE（false）

enum Phase { CHOOSE, ROOM, REWARD, DONE }

var map: RunMap = null
var seed_value: int = 0
## 当前在第几层（0 起，0..RunMap.FLOORS-1）。每层一张新图，越深怪越硬。
## ★ 不叫 floor ★ —— 会遮蔽全局函数 floor()，警告会被当错误。
var floor_index: int = 0
## 当前走到这一层的第几步（0 起，0..6）。每层共 RunMap.STEPS 步。
var step: int = 0
var gold: int = 0
var phase: int = Phase.CHOOSE
## 当前步选进了哪个房间（CHOOSE 阶段是 -1）
var room_index: int = -1
var victory := false


## 开一局新的。地图由种子生成，同种子必然同图。
static func start(p_seed: int) -> RunState:
	var s := RunState.new()
	s.seed_value = p_seed
	s.map = RunMap.generate(_floor_seed(p_seed, 0), 0)
	return s


## 第 f 层地图用的种子。★ 从局种子推导，不另掷骰 ★ ——
## 拿到局种子就能复现整局 4 层的图，存档也只用存一个种子。
static func _floor_seed(p_seed: int, f: int) -> int:
	return hash([p_seed, "floor", f])


# ---------------------------------------------------------------- 查询

## 当前这一步可选的房间
func rooms() -> Array:
	return map.rooms_at(step)


## 当前进的那个房间（不在房间里返回 null）
func current_room() -> RunMap.Room:
	if room_index < 0:
		return null
	var list := rooms()
	if room_index >= list.size():
		return null
	return list[room_index]


func is_over() -> bool:
	return phase == Phase.DONE


## 给某个用途要一个**确定性**的随机源。
## ★ 同一局、同一层、同一步、同一个用途 → 永远同一串随机数 ★
##   奖励三选一、商店进货都走这里 —— 存档只存种子和进度，
##   读档回来重掷一次，结果和存档前一模一样，不会"读档刷奖励"。
func rng_for(purpose: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, floor_index, step, purpose])
	return rng


## 现在在最后一层吗（这一层的 Boss 就是最终 Boss）
func is_final_floor() -> bool:
	return floor_index >= RunMap.FLOORS - 1


# ---------------------------------------------------------------- 流转

## 选进第 i 个房间。只有 CHOOSE 阶段能进，下标越界不进。
func enter_room(i: int) -> bool:
	if phase != Phase.CHOOSE:
		return false
	if i < 0 or i >= rooms().size():
		return false
	room_index = i
	phase = Phase.ROOM
	return true


## 战斗房打赢了。
##   普通战斗 / 守关 Boss → 进 REWARD 等三选一（守关 Boss 也掉奖励）
##   最终 Boss（最后一层的）→ 整局胜利
func complete_combat() -> void:
	if phase != Phase.ROOM:
		return
	var room := current_room()
	if room != null and room.type == RunMap.RoomType.BOSS and is_final_floor():
		victory = true
		phase = Phase.DONE
		return
	phase = Phase.REWARD


## 领完奖励 / 逛完商店，走向下一步。
## ★ 商店从 ROOM 直接走，战斗从 REWARD 走 ★ —— 别的阶段调它一律无效。
## 刚打完的是守关 Boss → 上到下一层：步数归零、按层种子重新生成一张更硬的图。
func advance() -> void:
	var room := current_room()
	var from_shop := phase == Phase.ROOM and room != null and room.type == RunMap.RoomType.SHOP
	if not from_shop and phase != Phase.REWARD:
		return
	room_index = -1
	# 守关 Boss 领完奖 → 下一层（最终 Boss 不会走到这：complete_combat 已 DONE）
	if room != null and room.type == RunMap.RoomType.BOSS:
		_enter_floor(floor_index + 1)
		return
	step += 1
	# 走完最后一步还没 DONE 是不可能的（最后一步是 Boss，打赢走的是上面那条），
	# 但防御一下：步数越界当成层打完了，别让 rooms() 越界。
	if step >= RunMap.STEPS:
		_enter_floor(floor_index + 1)
		return
	phase = Phase.CHOOSE


## 进入第 f 层（0 起）。越过最后一层 = 整局胜利（防御分支，正常打不到）。
func _enter_floor(f: int) -> void:
	if f >= RunMap.FLOORS:
		victory = true
		phase = Phase.DONE
		return
	floor_index = f
	step = 0
	map = RunMap.generate(_floor_seed(seed_value, f), f)
	phase = Phase.CHOOSE


## 玩家阵亡，整局结束。
func fail() -> void:
	victory = false
	phase = Phase.DONE


# ---------------------------------------------------------------- 金币

func add_gold(amount: int) -> void:
	gold += maxi(0, amount)


## 花钱。不够花返回 false，一分不扣。
func spend_gold(amount: int) -> bool:
	if amount < 0 or amount > gold:
		return false
	gold -= amount
	return true


# ---------------------------------------------------------------- 存档

## ★ 只存种子 + 进度，不存整张图 ★ 图由种子重新生成，天然一致。
## 存档时不管玩家正在房间里还是奖励界面，读回来一律回到**这一步的选房阶段** ——
## 打到一半退游戏 = 这一步重打，简单、无歧义、也防不了什么都不防的"逃课"。
func to_data() -> Dictionary:
	return {
		"seed": seed_value,
		"floor": floor_index,
		"step": step,
		"gold": gold,
	}


static func from_data(data: Dictionary) -> RunState:
	if typeof(data.get("seed")) not in [TYPE_INT, TYPE_FLOAT]:
		return null
	var s := start(int(data.get("seed")))
	var f := clampi(int(data.get("floor", 0)), 0, RunMap.FLOORS - 1)
	if f > 0:
		s._enter_floor(f)   # 顺便把这一层的图生成出来
	s.step = clampi(int(data.get("step", 0)), 0, RunMap.STEPS - 1)
	s.gold = maxi(0, int(data.get("gold", 0)))
	return s
