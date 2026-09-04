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

## ★ 连锁的目标 ★（ADR-036 修正）：连锁中每帧朝它飞、一步能到就直接贴上去。
## 以前只是"转向它然后 6 倍速直飞"—— 每物理帧飞 30 像素、怪的碰撞圈只有几像素，大多数时候从中间穿过去了
var _link_target: Enemy = null
## 回旋要飞回去的那个人（World 生成时塞进来）
var caster: Node2D = null

@onready var sprite: Sprite2D = $Sprite
@onready var trail: Line2D = $Trail


func _ready() -> void:
	_rng.randomize()
	if state == null:
		state = ProjectileState.new(ProjectileSpec.new())

	# 外观按技能标签选：闪电系用电球贴图 + 紫色拖尾，冰系用冰晶 + 冰蓝拖尾，其它用火球
	var tex: Texture2D = Art.fireball()
	if skill != null and (skill.tags & T.LIGHTNING) != 0:
		tex = Art.spark()
		trail.default_color = Color(0.95, 0.90, 0.45, 0.55)
	elif skill != null and (skill.tags & T.COLD) != 0:
		tex = Art.frostbolt()
		trail.default_color = Color(0.60, 0.85, 1.0, 0.55)
	elif skill != null and (skill.tags & T.CHAOS) != 0:
		tex = Art.chaos_orb()
		trail.default_color = Color(0.62, 0.90, 0.40, 0.55)
	elif skill != null and (skill.tags & T.PHYSICAL) != 0:
		tex = Art.knife()
		trail.default_color = Color(0.85, 0.85, 0.90, 0.40)
	Art.projectile_setup(sprite, tex)   # 32 像素能量弹缩到 16、线性过滤（ADR-037 补充）

	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	# ① 随机漂移：电球术"到处乱窜"的来源。转多少度由纯逻辑层决定
	var turn := state.wander_angle(delta, _rng)
	if not is_zero_approx(turn):
		direction = direction.rotated(turn)

	# ② 飞。★ 连锁中 +500% 速度 ★（ADR-035）—— 电弧跳向下一个目标几乎是瞬间的
	var step := state.spec.speed * state.speed_multiplier() * delta
	if _link_target != null and is_instance_valid(_link_target) and _link_target.stats.is_alive():
		# 连锁追踪：朝目标此刻的位置飞；一步之内能到就直接贴上去（不然高速会穿过怪的碰撞圈）
		var to_t := _link_target.global_position - global_position
		if to_t.length() <= step + 2.0:
			global_position = _link_target.global_position
			_link_target = null
			step = 0.0
		else:
			direction = to_t.normalized()
	elif state.returning and caster != null and is_instance_valid(caster):
		# 回旋：朝施法者飞，到了就消失
		var to_c := caster.global_position - global_position
		if to_c.length() <= step + 4.0:
			queue_free()
			return
		direction = to_c.normalized()
	position += direction * step
	state.add_travel(step)
	# 回旋：存活过半掉头（命中记录清空，回程能再打一遍）
	if state.should_return(lifetime):
		state.start_return()
		trail.clear_points()
	# 变形（冰矛第二形态）：亮一点、大一点，让玩家看得出"它变了"
	if state.is_transformed() and sprite.scale.x < 1.4:
		sprite.scale = Vector2(1.45, 1.45)
		sprite.modulate = Color(1.3, 1.3, 1.6)

	# ③ 撞墙反弹
	_handle_bounds()

	# ④ 表现：能量弹都是圆的，统一慢慢自旋就行（闪电 / 飞刀转向飞行方向是老字符画时代的事，
	#    32 像素能量弹转向反而会抖）
	sprite.rotation += delta * 6.0

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
	# 变形后的冰矛暴击率翻倍：拿一份技能副本改暴击率再算（不动模板）
	var hit_skill := skill
	if not is_equal_approx(state.crit_multiplier(), 1.0):
		hit_skill = skill.duplicate()
		hit_skill.base_crit_chance = skill.base_crit_chance * state.crit_multiplier()
	var r := DamagePipeline.compute_hit(source, e.stats, hit_skill, _rng)
	e.take_hit(r)

	# ---------- ② 附加技能自带的 Debuff（火球术 → 点燃，电球术 → 感电）----------
	if _rng.randf() <= skill.on_hit_chance:
		for b in skill.on_hit_buffs:
			e.stats.apply_buff(b, source)
			# ★ 触媒要数"施加了几次异常" ★ 用 behaviour 通道报给 World
			#（顺便进 behaviour_counts，冒烟测试也靠它验"事件真的上报了"）。
			# ★ 触媒触发出来的弹不上报 ★ —— 触发产物再喂触媒就闭环了（ADR-026）
			if not state.from_trigger:
				behaviour.emit("buff_%s" % b.id, global_position)

	hit_enemy.emit(e, r)

	# ---------- ③ 决定接下来干嘛（穿透 > 分叉 > 弹射）----------
	match state.decide_on_hit(id, _rng):
		ProjectileState.Action.PIERCE:
			behaviour.emit("pierce", global_position)
			# 方向不变，什么都不用做

		ProjectileState.Action.FORK:
			behaviour.emit("fork", global_position)
			_do_fork()

		ProjectileState.Action.LINK:
			_do_link()

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


## 场景里活着的敌人 → [{id, dist}]（弹射 / 连锁挑目标共用）
func _enemy_candidates() -> Array:
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
	return candidates


## ★ 连锁（ADR-035）★：跳向一个**没打过**的目标，速度 +500%（speed_multiplier 在飞行里乘）。
## 没有新目标 = 连锁到此为止，直接消失（不像弹射那样"白费次数直飞出去"—— 连锁的意义就是必有目标）。
func _do_link() -> void:
	var next_id := state.pick_link_target(_enemy_candidates())
	if next_id == -1:
		behaviour.emit("link_fail", global_position)
		queue_free()
		return
	var target := instance_from_id(next_id) as Enemy
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	behaviour.emit("link", global_position)
	_link_target = target             # 之后每帧追它（见 _physics_process）
	direction = (target.global_position - global_position).normalized()
	lifetime = maxf(lifetime, 1.2)
	trail.clear_points()


## 弹射：转向下一个目标（可以弹回打过的）。
##
## "挑谁"的规则在 ProjectileState.pick_chain_target 里（纯逻辑，能单测），
## 这里只负责把场景里的敌人整理成 [{id, dist}] 喂进去。
func _do_chain() -> void:
	var next_id := state.pick_chain_target(_enemy_candidates())
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
