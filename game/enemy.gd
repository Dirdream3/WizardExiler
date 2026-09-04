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
## 精英怪的金色调（受击闪白会从这个色回落，不然闪一下就变回普通怪的白）
const ELITE_TINT := Color(1.0, 0.86, 0.48)

var stats: CombatEntity
var melee: SkillSpec
var target: Player

var _attack_cd := 0.0
var _hit_flash := 0.0
var _rng := RandomNumberGenerator.new()
## 没在闪白时精灵该是什么颜色：普通怪白色，精英金色
var _base_tint := Color(1, 1, 1)
## 精英头顶的词条名（普通怪没有这个节点）
var _title: Label = null

@onready var sprite: Sprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow
@onready var bar: HealthBar = $Bar


func _ready() -> void:
	_rng.randomize()
	# Boss 用巫妖的图，其它都是骷髅（精英靠金色调和体型区分）
	Art.char_setup(sprite, Art.boss() if (stats != null and stats.id == &"bone_lord") else Art.skeleton())
	shadow.texture = Art.shadow()
	if stats == null:
		stats = Demo.make_monster()
	melee = Demo.skill_bone_slash()
	add_to_group(&"enemy")
	bar.set_ratio(1.0)
	if stats.is_elite():
		_apply_elite_look()


## ★ 精英怪的外观 ★（ADR-028）：金色调 + 体型放大 + 头顶写词条名 + 更宽的血条。
## 数值早在 RunContent.make_elite 里配好了，这里只管"让人一眼认出它是精英"。
func _apply_elite_look() -> void:
	_base_tint = ELITE_TINT
	sprite.modulate = _base_tint
	# 体型：精英底子 ×1.25，「巨型」词条再 ×1.35。World 可能已经给过 scale（Boss 1.7），在其上乘
	scale *= RunContent.ELITE_SCALE * stats.affix_scale()
	bar.width = 24.0
	bar.queue_redraw()
	_title = UIHelper.label(stats.affix_title(), 6, ELITE_TINT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.custom_minimum_size = Vector2(80, 0)
	# Label 宽 80 居中 → 左移一半正好对准头顶；放在血条再往上一点
	_title.position = Vector2(-40.0, -34.0)
	_title.z_index = 50
	add_child(_title)


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
			# ★ 追击速度走属性系统，基础值仍是 CHASE_SPEED 常量 ★
			#   这样「冰缓」（移动速度 -30%）才真的能让怪追不上你；
			#   没有任何词缀/Debuff 时，结果和直接用常量一模一样。
			velocity = to_target.normalized() * stats.get_stat(S.MOVE_SPEED, 0, CHASE_SPEED)
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
		sprite.modulate = _base_tint.lerp(Color(3.0, 1.6, 1.6), _hit_flash / 0.12)


func _attack() -> void:
	# 攻击间隔来自属性系统，怪物身上挂「提高攻击速度」的 Buff 就会变快
	var aps := maxf(0.1, stats.get_stat(S.ATTACK_SPEED, melee.hit_tags()))
	_attack_cd = 1.0 / aps

	var r := DamagePipeline.compute_hit(stats, target.stats, melee, _rng)
	target.take_hit(r)
	# ★ 爪类词条：近战命中把异常挂到玩家身上 ★（灼热之爪 = 火 DoT、霜爪 = 冰缓、雷爪 = 感电）
	#   施加者传 stats → DoT 会快照这只怪的伤害加成（精英 +30% 也会算进去）
	for b in stats.affix_on_hit_buffs():
		target.receive_buff(b as BuffDef, stats)
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
