class_name GameWorld
extends Node2D

## 主场景：搭场地、刷怪、把各方的信号接起来。
##
## 这一层只做"调度"：谁打谁、飘什么字、怪从哪来。
## 具体打多少伤害，一律问 DamagePipeline。
##
## ★ 画面布局：左边 300px 常驻面板，右边 400×400 正方形战斗画面 ★
##
## 战斗画面是一个真正的 **SubViewport**，不是"拿面板盖住左半边"：
##   · 它自己有一份 World2D，所有场地/角色/投射物都活在里面
##   · 所以画面边界是硬的 —— 怪物和投射物**不可能**跑到面板上面去
##   · 摄像机的 limit 也只对这 400×400 生效，天然就是方的
## 代价是这个文件里所有 add_child 都要挂到 `view` 底下，而不是挂给自己。

const PLAYER_SCENE := preload("res://game/player.tscn")
const ENEMY_SCENE := preload("res://game/enemy.tscn")
const PROJECTILE_SCENE := preload("res://game/projectile.tscn")
const Art = preload("res://game/pixel_art.gd")

## 场地半宽半高 → 实际 400×400。
##
## ★ 注意画面里看到的**不是** 400×400 ★
##   摄像机 zoom = 2（player.tscn 里），所以 400×400 的画面只显示 200×200 的世界，
##   摄像机会跟着玩家滚动，limit 卡在场地边界上（`_spawn_player` 里设）。
##   要让整张场地一眼看全，把 ARENA 改成 (100, 100) 或者把 zoom 改成 1。
const ARENA := Vector2(200, 200)
const MAX_ENEMIES := 5
const RESPAWN_DELAY := 2.2

var player: Player
var kills := 0

## 投射物各种行为发生了多少次（HUD 调试 / 冒烟测试用）
var behaviour_counts := {"pierce": 0, "fork": 0, "chain": 0, "chain_fail": 0, "bounce": 0}

var _spawn_cd := 0.0
var _rng := RandomNumberGenerator.new()

## 右侧那个正方形战斗画面（Control，用来判断鼠标在不在战斗区里）
@onready var battle: SubViewportContainer = $Layout/Root/Battle
## 战斗画面的 SubViewport。★ 场地里的一切都要挂在它底下 ★
@onready var view: SubViewport = $Layout/Root/Battle/View
@onready var floor_sprite: Sprite2D = $Layout/Root/Battle/View/Floor
@onready var entities: Node2D = $Layout/Root/Battle/View/Entities
@onready var fx: Node2D = $Layout/Root/Battle/View/FX
@onready var hud: GameHUD = $HUD


func _enter_tree() -> void:
	# 父节点的 _enter_tree 早于所有子节点的 _ready，按键在这里注册最保险
	InputSetup.ensure()


func _ready() -> void:
	_rng.randomize()
	_setup_floor()
	_setup_walls()
	_spawn_player()
	for i in 3:
		_spawn_enemy()
	hud.bind_player(player)


func _process(delta: float) -> void:
	_spawn_cd -= delta
	if _spawn_cd <= 0.0 and get_tree().get_node_count_in_group(&"enemy") < MAX_ENEMIES:
		_spawn_cd = RESPAWN_DELAY
		_spawn_enemy()

	# ★ 鼠标跑到左边面板上时不许施法 ★
	#   玩家在 SubViewport 里，拿不到"主窗口的鼠标在哪"，所以由这里告诉它。
	#   直接用矩形判断，不去问 gui_get_hovered_control —— 鼠标移出战斗区之后
	#   SubViewport 的鼠标坐标不会再更新，问它会得到过期的位置。
	if player != null:
		player.can_aim = is_in_battle_view(battle.get_global_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"restart"):
		get_tree().reload_current_scene()


# ------------------------------------------------------------------ 场地

func _setup_floor() -> void:
	# 一张 16×16 的地砖，靠 texture_repeat 平铺满整个场地
	floor_sprite.texture = Art.floor_tile()
	floor_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	floor_sprite.region_enabled = true
	floor_sprite.region_rect = Rect2(0, 0, ARENA.x * 2.0, ARENA.y * 2.0)
	floor_sprite.centered = true


func _setup_walls() -> void:
	# 四面看不见的墙，别让玩家跑出场地
	var t := 16.0
	var defs := [
		[Vector2(0.0, -ARENA.y - t * 0.5), Vector2(ARENA.x + t, t * 0.5)],
		[Vector2(0.0,  ARENA.y + t * 0.5), Vector2(ARENA.x + t, t * 0.5)],
		[Vector2(-ARENA.x - t * 0.5, 0.0), Vector2(t * 0.5, ARENA.y + t)],
		[Vector2( ARENA.x + t * 0.5, 0.0), Vector2(t * 0.5, ARENA.y + t)],
	]
	for d in defs:
		var body := StaticBody2D.new()
		body.collision_layer = 8   # 第 4 层 = 墙
		body.collision_mask = 0
		body.position = d[0]
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = (d[1] as Vector2) * 2.0
		cs.shape = shape
		body.add_child(cs)
		view.add_child(body)   # ★ 挂进 SubViewport，否则和角色不在同一个物理世界里 ★


# ------------------------------------------------------------------ 生成

func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.position = Vector2.ZERO
	entities.add_child(player)

	player.cast_requested.connect(_on_cast_requested)
	player.died.connect(_on_player_died)
	player.damaged.connect(func(amount: float, crit: bool) -> void:
		FloatingText.spawn(fx, player.global_position + Vector2(0.0, -18.0),
				"-%d" % roundi(amount), Color(1.0, 0.42, 0.42), crit))
	player.healed.connect(func(amount: float) -> void:
		if amount >= 1.0:
			FloatingText.spawn(fx, player.global_position + Vector2(0.0, -24.0),
					"+%d" % roundi(amount), Color(0.55, 0.92, 0.45)))

	# 摄像机别拍到场地外面
	var cam := player.get_node("Camera") as Camera2D
	cam.limit_left = int(-ARENA.x)
	cam.limit_right = int(ARENA.x)
	cam.limit_top = int(-ARENA.y)
	cam.limit_bottom = int(ARENA.y)


func _spawn_enemy() -> void:
	var e: Enemy = ENEMY_SCENE.instantiate()

	# 找一个离玩家足够远的落点
	var pos := Vector2.ZERO
	for attempt in 20:
		pos = Vector2(
			_rng.randf_range(-ARENA.x + 24.0, ARENA.x - 24.0),
			_rng.randf_range(-ARENA.y + 24.0, ARENA.y - 24.0))
		if player == null or pos.distance_to(player.global_position) > 110.0:
			break
	e.position = pos
	e.target = player

	e.damaged.connect(func(amount: float, crit: bool, kind: String) -> void:
		if not is_instance_valid(e):
			return
		var col := Color(1.0, 0.84, 0.36)
		var txt := "%d" % roundi(amount)
		if kind == "dot":
			col = Color(1.0, 0.52, 0.22)          # 点燃跳伤用橙色
		elif crit:
			col = Color(1.0, 0.96, 0.62)
			txt += " 暴击!"
		FloatingText.spawn(fx, e.global_position + Vector2(0.0, -22.0), txt, col, crit))

	e.died.connect(_on_enemy_died)
	entities.add_child(e)


## 主画面坐标下的这个点，落在右边的战斗画面里吗？
##
## ★ 两个矩形/坐标一定要**同一个坐标系** ★
##   `get_rect()` 是父节点坐标里的（x 从 300 开始），
##   `get_local_mouse_position()` 是控件自己坐标里的（x 从 0 开始）——
##   这两个混着比，结果就是只有最右边 100px 能施法。
##   所以这里统一用 global：`get_global_rect()` 配 `get_global_mouse_position()`。
func is_in_battle_view(global_pos: Vector2) -> bool:
	return battle.get_global_rect().has_point(global_pos)


## 投射物撞墙反弹用的范围。比场地稍微放大一点点，
## 免得贴着墙施法时投射物一出生就在界外（发射点还带随机位移）。
func projectile_bounds() -> Rect2:
	var pad := Vector2(4.0, 4.0)
	return Rect2(-ARENA - pad, (ARENA + pad) * 2.0)


func _on_cast_requested(from: Vector2, dir: Vector2) -> void:
	# 一次施法可能射出好几发（电球术天生 4 发 / 多重投射支援），
	# 每发各带一份**独立**的状态机 —— 共用一份的话，一发弹射了别的几发也会跟着扣次数。
	var skill: SkillSpec = player.skill
	if skill == null:
		return   # 技能栏这一格没插技能石
	var spec := ProjectileSpec.build(player.stats, skill)

	# 传 _rng 进去，散射角才会带随机抖动（电球术每次施法的弹道都不一样）
	for a in spec.spread_angles(_rng):
		# 发射点也随机位移一下，多发才不会挤成一条线出生
		var origin := from
		if spec.spawn_jitter > 0.0:
			origin += Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * spec.spawn_jitter
		_spawn_projectile(origin, dir.rotated(a), ProjectileState.new(spec), skill, player.stats)


## 生成一发投射物。分叉时投射物会回调这个方法再生成两发，所以是递归的。
##
## skill / src 要跟着一起传：投射物飞在半空时玩家可能已经切了技能，
## 拿"玩家当前技能"去算伤害就错了。
func _spawn_projectile(pos: Vector2, dir: Vector2, state: ProjectileState,
		skill: SkillSpec, src: CombatEntity) -> void:
	var bounds := projectile_bounds()
	var p: Projectile = PROJECTILE_SCENE.instantiate()
	p.position = pos.clamp(bounds.position, bounds.end)
	p.direction = dir
	p.source = src              # 伤害用施法者的属性算
	p.skill = skill
	p.state = state
	p.bounds = bounds
	p.lifetime = state.spec.duration
	p.spawn_requested.connect(_spawn_projectile)
	p.behaviour.connect(_on_projectile_behaviour)
	# ★ 必须延迟一帧加入场景树 ★
	#   分叉是在 body_entered 里触发的，那是物理查询的回调窗口，
	#   此时直接 add_child 一个带碰撞体的节点，Godot 会报
	#   "Can't change this state while flushing queries"。
	entities.add_child.call_deferred(p)


func _on_projectile_behaviour(kind: String, pos: Vector2) -> void:
	behaviour_counts[kind] = int(behaviour_counts.get(kind, 0)) + 1
	var at := pos + Vector2(0.0, -12.0)
	match kind:
		"pierce":
			FloatingText.spawn(fx, at, "穿透", Color(0.55, 0.85, 1.0))
		"fork":
			FloatingText.spawn(fx, at, "分叉", Color(0.72, 1.0, 0.52))
		"chain":
			FloatingText.spawn(fx, at, "弹射", Color(0.95, 0.72, 1.0))


# ------------------------------------------------------------------ 事件

func _on_enemy_died(who: Enemy) -> void:
	kills += 1
	FloatingText.spawn(fx, who.global_position + Vector2(0.0, -28.0), "击杀!",
			Color(0.62, 0.95, 0.50), true)
	if player != null and player.stats.is_alive():
		player.on_kill_reward()   # 上一层狂怒 + 回点血
	_spawn_cd = minf(_spawn_cd, 1.0)


func _on_player_died() -> void:
	hud.show_message("你死了\n按 R 重开")
