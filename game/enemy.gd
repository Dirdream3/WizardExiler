class_name Enemy
extends CharacterBody2D

## 骷髅战士。追着玩家跑，进入近战距离就砍。
##
## 和 Player 一样：这里只有"怎么动、怎么演"，
## 所有伤害计算都走 DamagePipeline。

const Demo = preload("res://data/demo_content.gd")
const Art = preload("res://game/pixel_art.gd")
const S = preload("res://combat/combat_stat.gd")

signal damaged(amount: float, is_crit: bool, source: String)
signal died(who: Enemy)
signal attacked(result: HitResult)

const ATTACK_RANGE := 20.0
const CHASE_SPEED := 42.0

var stats: CombatEntity
var melee: SkillSpec
var target: Player

var _attack_cd := 0.0
var _hit_flash := 0.0
var _rng := RandomNumberGenerator.new()

@onready var sprite: Sprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow
@onready var bar: HealthBar = $Bar


func _ready() -> void:
	_rng.randomize()
	sprite.texture = Art.skeleton()
	shadow.texture = Art.shadow()
	if stats == null:
		stats = Demo.make_monster()
	melee = Demo.skill_bone_slash()
	add_to_group(&"enemy")
	bar.set_ratio(1.0)


func _physics_process(delta: float) -> void:
	# --- DoT 结算（点燃就是在这里掉血的）---
	for ev in DamagePipeline.resolve_dots(stats, delta):
		damaged.emit(ev["damage"], false, "dot")

	bar.set_ratio(stats.life / maxf(1.0, stats.max_life()))

	if not stats.is_alive():
		_die()
		return

	# --- 追击 / 攻击 ---
	_attack_cd = maxf(0.0, _attack_cd - delta)
	if target != null and target.stats.is_alive():
		var to_target := target.global_position - global_position
		var dist := to_target.length()
		if dist > ATTACK_RANGE:
			velocity = to_target.normalized() * CHASE_SPEED
		else:
			velocity = velocity.lerp(Vector2.ZERO, 0.3)
			if _attack_cd <= 0.0:
				_attack()
		if not is_zero_approx(to_target.x):
			sprite.flip_h = to_target.x < 0.0
	else:
		velocity = velocity.lerp(Vector2.ZERO, 0.2)

	move_and_slide()

	# --- 受击闪白 ---
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
		sprite.modulate = Color(1, 1, 1).lerp(Color(3.0, 1.6, 1.6), _hit_flash / 0.12)


func _attack() -> void:
	# 攻击间隔来自属性系统，怪物身上挂「提高攻击速度」的 Buff 就会变快
	var aps := maxf(0.1, stats.get_stat(S.ATTACK_SPEED, melee.hit_tags()))
	_attack_cd = 1.0 / aps

	var r := DamagePipeline.compute_hit(stats, target.stats, melee, _rng)
	target.take_hit(r)
	attacked.emit(r)

	# 一点点前冲，让攻击有反馈
	var dir := (target.global_position - global_position).normalized()
	velocity = dir * 90.0


## 中了一次命中。
func take_hit(result: HitResult) -> void:
	if not stats.is_alive():
		return
	stats.take_damage(result.total)
	_hit_flash = 0.12
	damaged.emit(result.total, result.is_crit, "hit")
	# 受击后退
	velocity += (global_position - (target.global_position if target else global_position)).normalized() * 40.0
	if not stats.is_alive():
		_die()


func _die() -> void:
	if not is_queued_for_deletion():
		died.emit(self)
		queue_free()
