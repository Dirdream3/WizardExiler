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

# ---- 局模式（RunSession.enabled 时才用）----
## 局内流程界面（挂在 HUD 上，这里存个引用方便接信号/测试）
var run_ui: RunUI
## 当前房间还活着几只怪。> 0 说明正在打
var room_enemies_left := 0
var _room_active := false
## 本步商店的货架 + 已卖掉的位置（货架由种子定，退出重进不变）
var _shop_stock: Array = []
var _shop_sold: Array = []

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
	# ★ 局状态要在生成玩家**之前**准备好 ★ —— Player._ready 里铺开局背包
	#   要问 RunSession 拿数据，顺序反了玩家就会拿到一个空局
	if RunSession.enabled:
		RunSession.prepare()
	_spawn_player()
	hud.bind_player(player)
	if RunSession.enabled:
		_setup_run()
	else:
		# 沙盒模式：老样子，开场三只怪 + 无限刷
		for i in 3:
			_spawn_enemy()


func _process(delta: float) -> void:
	# ★ 无限刷怪只属于沙盒模式 ★ 局模式一个房间就一波怪，打完即清
	if not RunSession.enabled:
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
		# ★ R = 重开一整局，不是重打当前房间 ★
		# 局模式必须先放弃这一局（删局存档），否则重载场景会续档回到当前步。
		# 沙盒模式没有"局"的概念，重载就够了（背包走 GemSave，照常保留）。
		if RunSession.enabled:
			RunSession.abandon()
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
	player.catalyst_triggered.connect(_on_catalyst_triggered)
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


## 刷一只怪。
##   stats —— 传了就用这份数值（局模式的按步成长怪 / Boss）；不传用默认骷髅
##   scale —— 体型倍率（Boss 画大一圈，碰撞体会跟着一起放大）
func _spawn_enemy(stats: CombatEntity = null, body_scale: float = 1.0) -> void:
	var e: Enemy = ENEMY_SCENE.instantiate()
	if stats != null:
		e.stats = stats            # ★ 要在 add_child 之前塞 ★ Enemy._ready 只在空时造默认怪
	e.scale = Vector2(body_scale, body_scale)

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
	var skill: SkillSpec = player.skill
	if skill == null:
		return   # 当前法杖是空的
	_launch_volley(ProjectileSpec.build(player.stats, skill), skill, from, dir)


## ★ 触媒触发的施法 ★ 没有施法动作，也没有"鼠标方向"——
## 朝最近的敌人打；场上没有敌人就朝玩家面朝的方向。
## pspec 由 Player 用被触发那根法杖的词缀算好了，这里直接用。
func _on_catalyst_triggered(skill: SkillSpec, pspec: ProjectileSpec, cat_name: String) -> void:
	var target := UIHelper.nearest_enemy(get_tree(), player)
	var dir := Vector2.LEFT if player.sprite.flip_h else Vector2.RIGHT
	if target != null:
		dir = (target.global_position - player.global_position).normalized()
	FloatingText.spawn(fx, player.global_position + Vector2(0.0, -26.0),
			"✧%s" % cat_name, Color(0.80, 0.60, 0.95))
	# ★ from_trigger = true：触发产物的击中/异常不喂触媒（防循环，ADR-026）★
	_launch_volley(pspec, skill, player.global_position + Vector2(0, -7), dir, true)


## 把一次施法的投射物全部射出去（手动施法和触媒触发共用这一段）。
## 一次施法可能射出好几发（电球术天生 4 发 / 多重投射支援），
## 每发各带一份**独立**的状态机 —— 共用一份的话，一发弹射了别的几发也会跟着扣次数。
##   from_trigger —— 这一轮是触媒触发的：整轮投射物（含分叉出来的）不给触媒攒进度
func _launch_volley(spec: ProjectileSpec, skill: SkillSpec, from: Vector2, dir: Vector2,
		from_trigger := false) -> void:
	# 传 _rng 进去，散射角才会带随机抖动（电球术每次施法的弹道都不一样）
	for a in spec.spread_angles(_rng):
		# 发射点也随机位移一下，多发才不会挤成一条线出生
		var origin := from
		if spec.spawn_jitter > 0.0:
			origin += Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * spec.spawn_jitter
		var st := ProjectileState.new(spec)
		st.from_trigger = from_trigger
		_spawn_projectile(origin, dir.rotated(a), st, skill, player.stats)


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
	# ★ 连击触媒数的是投射物的直接命中（DoT 跳伤不算）★
	# 挂在投射物自己的 hit_enemy 上而不是敌人的受击信号上，是因为要看
	# from_trigger：触媒触发出来的弹，命中不给触媒攒进度（防循环，ADR-026）
	p.hit_enemy.connect(func(_e: Enemy, _r: HitResult) -> void:
		if not state.from_trigger and player != null:
			player.notify_catalyst_event(CatalystGem.Trigger.HITS, 1.0))
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
		# ★ 施加异常的事件转给触媒计数 ★（buff_* 由 Projectile 在施加 Debuff 时上报）
		"buff_shock":
			player.notify_catalyst_event(CatalystGem.Trigger.SHOCK_APPLIED, 1.0)
		"buff_ignite":
			player.notify_catalyst_event(CatalystGem.Trigger.IGNITE_APPLIED, 1.0)
		"buff_chill":
			player.notify_catalyst_event(CatalystGem.Trigger.CHILL_APPLIED, 1.0)


# ------------------------------------------------------------------ 事件

func _on_enemy_died(who: Enemy) -> void:
	kills += 1
	FloatingText.spawn(fx, who.global_position + Vector2(0.0, -28.0), "击杀!",
			Color(0.62, 0.95, 0.50), true)
	if player != null and player.stats.is_alive():
		player.on_kill_reward()   # 上一层狂怒 + 回点血
	if RunSession.enabled:
		if _room_active:
			room_enemies_left -= 1
			if room_enemies_left <= 0:
				_on_room_cleared()
	else:
		_spawn_cd = minf(_spawn_cd, 1.0)


func _on_player_died() -> void:
	if RunSession.enabled:
		# 阵亡 = 整局结束。删掉局存档，按 R 就是全新的一局（新种子新图）。
		RunSession.state.fail()
		RunSession.clear_save()
		_room_active = false
		hud.show_message("你阵亡了（第 %d 层 · 第 %d 步）\n按 R 开新的一局" % [
			RunSession.state.floor_index + 1, RunSession.state.step + 1])
		return
	hud.show_message("你死了\n按 R 重开")


# ------------------------------------------------------------------ 局模式流程
#
# 整条链路：地图选房 → 打 / 逛 → 领奖三选一 → 回地图走下一步 → … → Boss。
# ★ 规则判断全在 RunState（纯逻辑，已单测）★ 这里只做三件事：
#   把状态画出来（run_ui.show_*）、刷怪、把玩家的点击翻译成 RunState 的方法调用。

func _setup_run() -> void:
	run_ui = hud.run_ui
	# ★ 全部用 CONNECT_DEFERRED ★ —— 回调里会重建面板按钮，
	#   立刻执行会把正在处理点击事件的按钮 free 掉（AGENTS.md 已知陷阱）
	run_ui.room_chosen.connect(_on_room_chosen, CONNECT_DEFERRED)
	run_ui.reward_chosen.connect(_on_reward_chosen, CONNECT_DEFERRED)
	run_ui.reward_skipped.connect(_on_reward_skipped, CONNECT_DEFERRED)
	run_ui.shop_buy.connect(_on_shop_buy, CONNECT_DEFERRED)
	run_ui.shop_left.connect(_on_shop_left, CONNECT_DEFERRED)
	run_ui.show_map(RunSession.state)


func _on_room_chosen(index: int) -> void:
	var st := RunSession.state
	if not st.enter_room(index):
		return
	run_ui.hide_all()
	run_ui.set_status(st)
	var room := st.current_room()
	if room.type == RunMap.RoomType.SHOP:
		_open_shop()
	else:
		_start_combat(room)


func _start_combat(room: RunMap.Room) -> void:
	_room_active = true
	var st := RunSession.state
	if room.type == RunMap.RoomType.BOSS:
		# 每层的 Boss 都走 make_boss(层数)：前三层是缩水的守关 Boss，第 4 层才是完全体
		room_enemies_left = 1
		_spawn_enemy(RunContent.make_boss(st.floor_index), 1.7)
	else:
		room_enemies_left = RunContent.enemies_for_step(st.step)
		for i in room_enemies_left:
			_spawn_enemy(RunContent.make_room_monster(st.step, st.floor_index))


func _on_room_cleared() -> void:
	_room_active = false
	var st := RunSession.state
	var room := st.current_room()
	# ★ 走出房间前回满状态 ★ —— 这一版没有药水/回血节点，
	#   不回满的话残血进下一间基本必死，难度曲线会失真
	player.stats.refill()
	st.complete_combat()
	if st.is_over():
		_finish_run()
		return
	# ★ 金币每个关卡都会掉落（没有专门的金币房）★
	#   普通战斗房一笔、守关 Boss 一笔更肥的；数额走 rng_for → 同一局同一处定死，
	#   读档重打也是同一笔，刷不了钱
	var gold_gain := 0
	if room.type == RunMap.RoomType.BOSS:
		gold_gain = RunContent.boss_gold(st.floor_index, st.rng_for("boss_gold"))
	else:
		gold_gain = RunContent.room_gold(st.step, st.rng_for("room_gold"), st.floor_index)
	st.add_gold(gold_gain)
	# 奖励三选一：候选用 rng_for("reward") 掷 → 同一局同一处永远同一批，读档回来也一样。
	# ★ owned 要用 owned_gems()：镶在法杖槽里的宝石也算"拥有"，升级奖励得能升到它 ★
	var options := RunRewards.roll_options(room.reward, st.rng_for("reward"),
			RunContent.reward_pools(player.grid.owned_gems()))
	run_ui.show_reward(room.reward, options, gold_gain)
	run_ui.set_status(st)


func _on_reward_chosen(option: Dictionary) -> void:
	match int(option.get("kind", -1)):
		RunMap.RewardKind.UPGRADE:
			player.change_level(option.get("gem"), 1)   # 会顺手 rebuild + 存盘
		_:
			# 宝石 / 装备 / 辅助：塞进背包空地。满了别吞玩家的选择 —— 留在界面上等腾地方
			if player.grid.place_anywhere(option.get("item")) == null:
				run_ui.flash_notice("背包放不下了！先在左边挪出空间，或点「放弃奖励」")
				return
			player.rebuild()
	_leave_step()


func _on_reward_skipped() -> void:
	_leave_step()


## 领完奖 / 逛完店，走向下一步，回到地图
func _leave_step() -> void:
	var st := RunSession.state
	st.advance()
	run_ui.show_map(st)
	RunSession.save(player)


# ---- 商店 ----

func _open_shop() -> void:
	var st := RunSession.state
	# 货架由种子 + 步数决定：读档回来、退出重进，货都一样，防"刷货架"
	_shop_stock = RunContent.shop_stock(st.rng_for("shop"))
	_shop_sold = []
	run_ui.show_shop(st, _shop_stock, _shop_sold)


func _on_shop_buy(index: int) -> void:
	var st := RunSession.state
	if index < 0 or index >= _shop_stock.size() or _shop_sold.has(index):
		return
	var thing = _shop_stock[index]
	var price := RunContent.price_of(thing)
	if not st.spend_gold(price):
		run_ui.flash_notice("金币不够")
		return
	if player.grid.place_anywhere(thing) == null:
		st.add_gold(price)   # ★ 放不下要退款 ★ 钱扣了东西没到手是最恶劣的 bug
		run_ui.flash_notice("背包放不下了！先在左边挪出空间")
		return
	player.rebuild()
	_shop_sold.append(index)
	run_ui.show_shop(st, _shop_stock, _shop_sold)


func _on_shop_left() -> void:
	_leave_step()


func _finish_run() -> void:
	# 通关：第 4 层的最终 Boss 已倒，RunState 已经是 DONE + victory。
	# 清掉存档，下次是新局。
	RunSession.clear_save()
	run_ui.hide_all()
	hud.show_message("通关！4 层打穿，骸骨领主已被击败\n按 R 开新的一局")
