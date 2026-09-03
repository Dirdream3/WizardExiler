class_name ProjectileState
extends RefCounted

## 一发投射物的**运行时状态**：还剩几次穿透/分叉/弹射、打过谁、下一次漂移还有多久。
##
## ★★ 这个类不依赖任何 Godot 节点，所以"命中之后该干嘛""弹射该选谁"
##    这些最容易写错的判定，全都可以直接写单元测试。★★
##
## 表现层（Projectile 节点）只做两件事：把场景里的信息喂进来、照着返回值执行。

enum Action {
	PIERCE,  ## 穿透：方向不变，继续飞
	FORK,    ## 分叉：裂成两发，原来那发消失
	CHAIN,   ## 弹射：转向另一个敌人
	EXPIRE,  ## 没招了，消失
}

var spec: ProjectileSpec

var pierces_left: int = 0
var forks_left: int = 0
var chains_left: int = 0
var bounces_left: int = 0

var pierces_done: int = 0
var forks_done: int = 0
var chains_done: int = 0
var bounces_done: int = 0

## 打过的所有目标（instance id）。弹射选目标时"没打过的优先"要用它
var hit_ids: Array[int] = []
## **刚刚**打过的那个。规则见 can_hit()
var last_hit_id: int = -1

## ★ 这一发是不是触媒触发出来的（ADR-026 补充）★
## 触发产物的击中 / 施加异常**不再给任何触媒攒进度** ——
## 否则"感电触媒 → 电球 → 施加感电 → 又触发"就闭环了，没法平衡。
## PoE 的同款规则：被触发的技能不能再触发别的触发。分叉出来的子弹也继承这个标记。
var from_trigger := false

var _wander_timer: float = 0.0


func _init(p_spec: ProjectileSpec = null) -> void:
	spec = p_spec if p_spec != null else ProjectileSpec.new()
	pierces_left = spec.pierce_count
	forks_left = spec.fork_count
	chains_left = spec.chain_count
	bounces_left = spec.bounce_count


## 打过这个目标没有（历史记录，弹射选目标时用）
func has_hit(id: int) -> bool:
	return hit_ids.has(id)


## 现在能不能命中这个目标。
##
## 规则是「不能**连续**命中同一个」，注意是连续，不是永远不能：
##   · 穿透时投射物还压在目标身上 → 挡掉重复结算
##   · 分叉出来的两发继承了 last_hit_id → 不会立刻回头打刚才那个
##   · 但弹射到别人身上之后**可以**再弹回来 —— PoE 就是这个行为，
##     两只怪来回弹是弹射流派单体伤害的主要来源，写成"永不重复"会砍掉一半伤害。
func can_hit(id: int) -> bool:
	return id != last_hit_id


## ★ 核心：命中一个目标之后该干嘛 ★
##
## PoE / PoE2 的优先级是**写死的**：穿透 > 分叉 > 弹射。
## 也就是说只要还能穿透，这一次命中就绝不会分叉或弹射 ——
## 这也是为什么「穿透」和「分叉/弹射」通常不会配在同一套装备上。
func decide_on_hit(target_id: int, rng: RandomNumberGenerator = null) -> int:
	if not hit_ids.has(target_id):
		hit_ids.append(target_id)
	last_hit_id = target_id

	# ① 穿透：先用固定次数，用完再看几率
	if pierces_left > 0:
		pierces_left -= 1
		pierces_done += 1
		return Action.PIERCE
	if spec.pierce_chance > 0.0 and rng != null and rng.randf() < spec.pierce_chance:
		pierces_done += 1
		return Action.PIERCE

	# ② 分叉
	if forks_left > 0:
		forks_left -= 1
		forks_done += 1
		return Action.FORK

	# ③ 弹射
	if chains_left > 0:
		chains_left -= 1
		chains_done += 1
		return Action.CHAIN

	return Action.EXPIRE


## 弹射该转向谁。
##
## candidates 是表现层从场景里收集来的 [{"id": int, "dist": float}, ...]，
## 这样"挑谁"的规则就能脱离引擎写测试 —— 它是整个弹射里最容易写错的一步。
##
## 规则（按优先级）：
##   ① 排除刚打过的那个（不能原地来回弹）
##   ② 排除超出弹射半径的
##   ③ 没打过的 > 打过的
##   ④ 同等条件下取最近的
##
## 返回目标 id；没有合适的目标返回 -1（这时投射物直飞出去消失，弹射次数白费）。
func pick_chain_target(candidates: Array) -> int:
	var best_id := -1
	var best_fresh := false
	var best_dist := INF

	for c in candidates:
		var id := int(c["id"])
		var dist := float(c["dist"])
		if id == last_hit_id:
			continue
		if dist > spec.chain_range:
			continue

		var fresh := not has_hit(id)
		var better := false
		if best_id == -1:
			better = true
		elif fresh != best_fresh:
			better = fresh              # 没打过的一律优先
		else:
			better = dist < best_dist   # 同等新鲜度，比距离

		if better:
			best_id = id
			best_fresh = fresh
			best_dist = dist

	return best_id


## 撞到墙了，还能弹开吗？
##
## 反弹和「穿透/分叉/弹射」是两套完全独立的次数 —— 撞墙不消耗任何命中次数，
## 命中敌人也不消耗反弹次数。电球术可以「0 穿透 + 6 反弹」在房间里弹半天。
##
## 返回 true = 弹开（表现层负责算镜面反射方向），false = 次数用完，该消失了。
func try_bounce() -> bool:
	if bounces_left <= 0:
		return false
	bounces_left -= 1
	bounces_done += 1
	# 弹墙之后掉头回来，理应能再打一次刚才那个目标 —— 所以把"刚打过的"清掉。
	# （can_hit 挡的是"同一次穿身而过被结算两次"，不是"永远不能再打"）
	last_hit_id = -1
	return true


## 飞行中的随机漂移（电球术到处乱窜的来源）。
## 每 wander_interval 秒转一个 ±wander_deg 以内的随机角度。
## 返回本帧要转的**弧度**，0 = 这一帧不转。
func wander_angle(delta: float, rng: RandomNumberGenerator) -> float:
	if spec.wander_deg <= 0.0 or rng == null:
		return 0.0
	_wander_timer -= delta
	if _wander_timer > 0.0:
		return 0.0
	_wander_timer += spec.wander_interval
	# delta 比间隔还大（卡帧）时别让计时器一路欠成负数，直接重置
	if _wander_timer <= 0.0:
		_wander_timer = spec.wander_interval
	return deg_to_rad(rng.randf_range(-spec.wander_deg, spec.wander_deg))


## 分叉出来的两发的状态。
##
## PoE 规则：分叉产生的投射物**不能再分叉**（除非有额外的分叉次数），
## 但穿透和弹射次数是继承下去的。last_hit_id 也要继承，
## 否则两发子弹会立刻回头打刚才那个目标。
func clone_for_fork() -> ProjectileState:
	var c := ProjectileState.new(spec)
	c.pierces_left = pierces_left
	c.forks_left = forks_left        # decide_on_hit 里已经扣过 1 了
	c.chains_left = chains_left
	c.bounces_left = bounces_left    # 反弹次数也继承：分叉出来的两发照样会弹墙
	c.pierces_done = pierces_done
	c.forks_done = forks_done
	c.chains_done = chains_done
	c.bounces_done = bounces_done
	c.hit_ids = hit_ids.duplicate()
	c.last_hit_id = last_hit_id
	c.from_trigger = from_trigger   # 触发产物分叉出来的还是触发产物，不喂触媒
	return c


func describe() -> String:
	return "穿透 %d  分叉 %d  连锁 %d  反弹 %d" % [pierces_left, forks_left, chains_left, bounces_left]
