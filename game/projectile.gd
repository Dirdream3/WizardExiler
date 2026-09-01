class_name Projectile
extends Area2D

## 投射物的**表现层**（火球术 / 电球术都是它）。
##
## ★ 这个文件里没有任何"规则"，只有"怎么演" ★
##   打不打得到、命中后穿透还是分叉、弹射该选谁、撞墙还能不能弹、
##   这一帧要不要漂移 —— 全部问 ProjectileState（纯逻辑，能单测）。
##   这里只负责：把场景里的信息喂进去，然后照着返回值改方向 / 生成新的 / 消失。

const Art = preload("res://game/pixel_art.gd")
const T = preload("res://combat/combat_tags.gd")

signal hit_enemy(enemy: Enemy, result: HitResult)
## 分叉时请求生成新的投射物（由 World 接手，因为它才知道该挂到哪、连哪些信号）。
## 技能和施法者要一起传过去 —— 分叉出来的两发得用**放这一发时**的技能算伤害，
## 而不是玩家此刻手上拿的那个技能。
signal spawn_requested(pos: Vector2, dir: Vector2, state: ProjectileState,
		skill: SkillSpec, src: CombatEntity)
## 触发了某种行为，World 拿去飘字 / 计数
signal behaviour(kind: String, pos: Vector2)

const TRAIL_POINTS := 10

var direction := Vector2.RIGHT
var lifetime := 2.0

## 谁放的（伤害要用施法者的属性算）
var source: CombatEntity
var skill: SkillSpec
## 穿透/分叉/弹射/反弹的状态机。World 生成时塞进来
var state: ProjectileState

## 撞墙反弹用的场地范围。size 为 0 = 不做反弹判定。
##
## 为什么不用物理碰撞去撞墙？因为 Area2D 的 body_entered **不给法线**，
## 拿不到法线就没法算镜面反射。场地是个矩形，直接跟矩形比大小反而又准又省。
## 以后换成 TileMap 地形时，把这里换成 ShapeCast2D 取 get_collision_normal() 即可，
## 上层的 state.try_bounce() 一行都不用改。
var bounds := Rect2()

var _rng := RandomNumberGenerator.new()

@onready var sprite: Sprite2D = $Sprite
@onready var trail: Line2D = $Trail


func _ready() -> void:
	_rng.randomize()
	if state == null:
		state = ProjectileState.new(ProjectileSpec.new())

	# 外观按技能标签选：闪电系用电球贴图 + 紫色拖尾，其它用火球
	if skill != null and (skill.tags & T.LIGHTNING) != 0:
		sprite.texture = Art.spark()
		trail.default_color = Color(0.78, 0.62, 1.0, 0.5)
	else:
		sprite.texture = Art.fireball()

	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	# ① 随机漂移：电球术"到处乱窜"的来源。转多少度由纯逻辑层决定
	var turn := state.wander_angle(delta, _rng)
	if not is_zero_approx(turn):
		direction = direction.rotated(turn)

	# ② 飞
	position += direction * state.spec.speed * delta

	# ③ 撞墙反弹
	_handle_bounds()

	# ④ 表现：电球术指向飞行方向（乱窜时看着才对劲），火球自旋
	if skill != null and (skill.tags & T.LIGHTNING) != 0:
		sprite.rotation = direction.angle()
	else:
		sprite.rotation += delta * 12.0

	# 拖尾：记录最近几个位置。分叉/弹射/反弹的转折在这里看得最清楚
	trail.add_point(global_position)
	while trail.get_point_count() > TRAIL_POINTS:
		trail.remove_point(0)

	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


# ------------------------------------------------------------------ 撞墙

func _handle_bounds() -> void:
	if bounds.size == Vector2.ZERO:
		return

	# 出界了没？出界的那一边就是墙面法线的方向
	var p := global_position
	var normal := Vector2.ZERO
	if p.x < bounds.position.x:
		normal.x = 1.0
	elif p.x > bounds.end.x:
		normal.x = -1.0
	if p.y < bounds.position.y:
		normal.y = 1.0
	elif p.y > bounds.end.y:
		normal.y = -1.0
	if normal == Vector2.ZERO:
		return

	# 还能弹吗？次数用完就消失（火球没有反弹次数 → 撞墙即灭）
	if not state.try_bounce():
		queue_free()
		return

	# 先塞回场地内，再做镜面反射，否则下一帧还在界外会连着弹好几次
	global_position = p.clamp(bounds.position, bounds.end)
	direction = direction.bounce(normal.normalized())
	behaviour.emit("bounce", global_position)
	trail.clear_points()


# ------------------------------------------------------------------ 命中

func _on_body_entered(body: Node2D) -> void:
	if not (body is Enemy):
		return
	var e := body as Enemy
	if not e.stats.is_alive():
		return

	var id := e.get_instance_id()
	# 「不能连续命中同一个」：穿透时投射物还压在目标身上，别重复结算；
	# 分叉出来的两发也靠这个避免立刻回头打刚才那个目标。
	if not state.can_hit(id):
		return

	# ---------- ① 结算伤害 ----------
	var r := DamagePipeline.compute_hit(source, e.stats, skill, _rng)
	e.take_hit(r)

	# ---------- ② 附加技能自带的 Debuff（火球术 → 点燃，电球术 → 感电）----------
	if _rng.randf() <= skill.on_hit_chance:
		for b in skill.on_hit_buffs:
			e.stats.apply_buff(b, source)

	hit_enemy.emit(e, r)

	# ---------- ③ 决定接下来干嘛（穿透 > 分叉 > 弹射）----------
	match state.decide_on_hit(id, _rng):
		ProjectileState.Action.PIERCE:
			behaviour.emit("pierce", global_position)
			# 方向不变，什么都不用做

		ProjectileState.Action.FORK:
			behaviour.emit("fork", global_position)
			_do_fork()

		ProjectileState.Action.CHAIN:
			_do_chain()

		_:
			queue_free()


## 分叉：向两侧各偏 fork_angle_deg 生成一发，自己消失。
func _do_fork() -> void:
	var half := deg_to_rad(state.spec.fork_angle_deg)
	for s in [-1.0, 1.0]:
		spawn_requested.emit(
			global_position,
			direction.rotated(half * s),
			state.clone_for_fork(),
			skill,
			source)
	queue_free()


## 弹射（连锁）：转向下一个目标。
##
## "挑谁"的规则在 ProjectileState.pick_chain_target 里（纯逻辑，能单测），
## 这里只负责把场景里的敌人整理成 [{id, dist}] 喂进去。
func _do_chain() -> void:
	var candidates: Array = []
	for n in get_tree().get_nodes_in_group(&"enemy"):
		if not is_instance_valid(n):
			continue
		var e := n as Enemy
		if e == null or e.stats == null or not e.stats.is_alive():
			continue
		candidates.append({
			"id": e.get_instance_id(),
			"dist": global_position.distance_to(e.global_position),
		})

	var next_id := state.pick_chain_target(candidates)
	if next_id == -1:
		# PoE 的行为：找不到目标就直飞出去消失，弹射次数白费
		behaviour.emit("chain_fail", global_position)
		queue_free()
		return

	var target := instance_from_id(next_id) as Enemy
	if target == null or not is_instance_valid(target):
		queue_free()
		return

	behaviour.emit("chain", global_position)
	direction = (target.global_position - global_position).normalized()
	# 给它足够的时间飞到下一个目标
	lifetime = maxf(lifetime, 1.2)
	# 转向时把拖尾清掉，折线才干净
	trail.clear_points()
