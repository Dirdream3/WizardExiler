extends SceneTree

## 集成冒烟测试：真的把游戏跑起来，确认整条链路通：
##   放火球 → 命中掉血 → 上点燃 → DoT 持续掉血 → 弹射 → 分叉
##
## 运行：
##     godot --headless --path . --script res://test/smoke_test.gd
##
## run_tests.gd 测的是纯数值逻辑；这个测的是逻辑层和表现层接得上。
## 两个都要有 —— 单元测试过了不代表游戏里能跑。
##
## ★ 计时用 Engine.get_physics_frames()，不要用 _process 的调用次数 ★
##   headless 下主循环跑得比物理快得多，用 _process 计数时序会飘。
##   投射物是在 _physics_process 里移动的，所以物理帧才是它的时钟。
##
## 弹射和分叉分两段测：两个支援同时装上时，分叉出来的两发是朝**外侧**飞的，
## 大概率什么都撞不到，弹射分支就永远走不到。所以先只装弹射，再只装分叉。

const Demo = preload("res://data/demo_content.gd")
const S = preload("res://combat/combat_stat.gd")

const SETUP_AT := 2        # 物理帧。此时场景已经 _ready 完
const PICK_AT := 20
const FIRE_AT := 30
const FIRE_EVERY := 70
const PHASE_B_AT := 280    # 切换到「分叉支援」
const PHASE_C_AT := 420    # 切换到「电球术」，看散射 / 乱窜 / 撞墙反弹
const PHASE_D_AT := 560    # 用**真实按键**施法一次
const CAST_FRAMES := 60    # 按住施法键多久
const PHASE_E_AT := 660    # 用**真实按键**切技能
const PHASE_ARC_AT := 675  # 电弧连锁：不回头 + 瞬移（ADR-035）
const PHASE_F_AT := 700    # 范围技能：新星瞬发 → 风暴呼唤延迟落雷（ADR-030）
const STORM_DELAY_FRAMES := 72   # 1.2 秒 × 60 物理帧
const FIRESTORM_FRAMES := 24 + 5 * 21 + 12   # 0.4 秒延迟 + 5 个 0.35 秒间隔 + 余量
const CHECK_AT := 1070

## 往战斗画面里丢鼠标事件用的视口坐标（x 落在 300~700 之间才会被容器转发进去）
const AIM_PROBE_VIEWPORT := Vector2(500.0, 100.0)


var _world: GameWorld
var _watch: Enemy          # 盯着看点燃/DoT 的那只
var _life_when_ignited := -1.0
var _saw_hit := false
var _saw_ignite := false
var _saw_shock := false

var _chain_counts := {}
var _fork_counts := {}
var _base_frame := -1
var _did_setup := false
var _did_pick := false
var _did_phase_b := false
var _did_phase_c := false
var _did_phase_d := false
var _cast_done := false
var _cast_max_projectiles := 0
var _mouse_before := Vector2.INF   # 注入前 SubViewport 记的鼠标位置
var _mouse_after := Vector2.INF    # 注入后
var _did_switch := false
var _link_before_switch := -1
var _link_after_switch := -1
# ---- 火球爆炸 + 瘟疫扩散（ADR-036）----
var _did_diff := false
var _diff_at := 0
var _diff_b: Enemy = null
var _diff_stage := 0
var _explode_before := 0
# ---- 电弧连锁 ----
var _did_arc := false
var _arc_link_before := 0
var _arc_a: Enemy = null
var _arc_b: Enemy = null
# ---- 第七段（范围技能）----
var _did_area := false
var _area_target: Enemy = null
var _area_hits_before := 0
var _nova_checked := false
var _did_storm := false
var _storm_life_before := -1.0
var _storm_hits_before := 0
var _storm_early_checked := false
var _storm_checked := false
var _did_firestorm := false
var _firestorm_area_before := 0
var _firestorm_checked := false
var _firestorm_at := 0
# ---- 近战（ADR-032）----
var _melee_at := 0
var _melee_front: Enemy = null
var _melee_back: Enemy = null
var _melee_checked := false
var _cyclone_at := 0
var _cyclone_burst: AreaBurst = null
var _cyclone_checked := false
var _channel_at := 0
var _channel_stage := 0
var _channel_index := -1
var _channel_mana := 0.0
var _next_fire := FIRE_AT
var _failed := 0

# ---- 第八段（局模式）的状态 ----
const RUN_SEED := 12345        ## 固定种子，整段流程可复现
var _legacy_done := false      ## 沙盒段跑完了，_process 改走局模式逻辑
var _run_world: GameWorld
var _run_base := -1
var _run_stage := 0
var _expected_enemies := 0
var _grid_before := 0
var _gold_before := 0
var _level_before := 0
var _reward_taken := {}


func _initialize() -> void:
	print("\n=========== 集成冒烟测试 ===========\n")
	# ★ 必须在场景 _ready 之前关掉存盘 ★
	#   测试会把背包摆得乱七八糟，存下去就把玩家真正的背包覆盖了。
	GemSave.autosave = false
	# 前半段测的是老的沙盒模式（默认摆法 / 无限刷怪）→ 先把局模式关掉，
	# 第八段再打开它专测局流程。局存档也要指到测试文件上，别碰玩家的真档。
	RunSession.enabled = false
	RunSession.autosave = false
	RunSession.path = "user://run_smoketest.json"
	var packed: PackedScene = load("res://main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	_world = scene as GameWorld
	# 注意：此刻场景还没 _ready，_world.player 还是 null，
	# 装宝石那些事要等到 SETUP_AT 那一帧再做。


func _process(_delta: float) -> bool:
	# 沙盒段结束后，这个函数整个让位给局模式的驱动逻辑
	if _legacy_done:
		return _run_process()
	if _base_frame < 0:
		_base_frame = int(Engine.get_physics_frames())
	var now := int(Engine.get_physics_frames()) - _base_frame

	# ---------- 第一段：火球术 + 只连「弹射支援」 ----------
	# 在网格里"摆"出这个构筑：把火球术挪到中间，弹射支援放它左边、箭头朝右指进去。
	if not _did_setup and now >= SETUP_AT:
		_did_setup = true
		_rebuild_grid(&"fireball", &"sup_chain")
		print("[第一段] 火球术+弹射    投射物参数: %s" % _spec_text())

	if not _did_pick and now >= PICK_AT:
		_did_pick = true
		_watch = _nearest_enemy()
		if _watch == null:
			_fail("场景里没有敌人")
			return true
		print("观察目标: %s  生命 %.0f  距离 %.0f" % [
			_watch.stats.display_name, _watch.stats.life,
			_watch.global_position.distance_to(_world.player.global_position)])

	# ---------- 第二段：换成「分叉支援」 ----------
	if not _did_phase_b and now >= PHASE_B_AT:
		_did_phase_b = true
		_chain_counts = _world.behaviour_counts.duplicate()
		_rebuild_grid(&"fireball", &"sup_fork")
		print("[第二段] 分叉    投射物参数: %s" % _spec_text())

	# ---------- 第三段：切到「电球术」，不连任何辅助 ----------
	# 电球术自带 4 发散射 + 乱窜 + 撞墙反弹，正好验证这三条在真实场景里跑得通。
	if not _did_phase_c and now >= PHASE_C_AT:
		_did_phase_c = true
		_fork_counts = _world.behaviour_counts.duplicate()
		_rebuild_grid(&"spark", &"")
		print("[第三段] 电球术    投射物参数: %s" % _spec_text())

	# ---------- 第四段：用**真实按键**施法 ----------
	# ★ 前面三段都是直接调 _on_cast_requested()，绕过了 Player._try_cast() ★
	#   而"能不能施法"的判断（魔力 / 冷却 / 鼠标在不在战斗区里）全在那里面 ——
	#   之前 can_aim 的坐标系写错导致"点了没反应"，测试一条都没红，就是因为这里没覆盖。
	if not _did_phase_d and now >= PHASE_D_AT:
		_did_phase_d = true
		_next_fire = 1 << 30                # 停掉手动开火，免得把投射物数混在一起
		# headless 下鼠标停在 (0,0)，World 每帧会把 can_aim 判成 false。
		# 把 World 的 _process 关掉再手动置 true —— "鼠标在不在战斗区里"这件事
		# 由 _report() 里的 is_in_battle_view 断言单独覆盖，这里只测按键→放技能这条链路。
		_world.set_process(false)
		_world.player.can_aim = true
		_world.player.stats.mana = _world.player.stats.max_mana()
		_mouse_before = _world.view.get_mouse_position()
		_send_mouse_to(AIM_PROBE_VIEWPORT)
		Input.action_press(&"cast")
		print("[第四段] 按住施法键")

	# 隔几帧再读，让鼠标事件走完一轮转发
	if _did_phase_d and _mouse_after == Vector2.INF and now >= PHASE_D_AT + 3:
		_mouse_after = _world.view.get_mouse_position()
		print("SubViewport 记的鼠标：注入前 %s → 注入后 %s" % [_mouse_before, _mouse_after])

	if _did_phase_d and not _cast_done:
		_cast_max_projectiles = maxi(_cast_max_projectiles, _count_projectiles())
		if now >= PHASE_D_AT + CAST_FRAMES:
			_cast_done = true
			Input.action_release(&"cast")
			_world.set_process(true)
			print("第 %d 物理帧：松开施法键，期间场上最多有 %d 发投射物" % [
				now, _cast_max_projectiles])

	# ---------- 第五段：用**真实按键**切技能 ----------
	# Q 和 1~5 走的是 Player._unhandled_input()，而玩家住在战斗画面的 SubViewport 里 ——
	# 输入到底转不转发得进去，只有真的丢一个事件进去才知道。
	if not _did_switch and now >= PHASE_E_AT:
		_did_switch = true
		# 网格里得有两根"镶着宝石的法杖"，Q 才有得切（只有一根时 posmod(1,1)=0，切了等于没切）
		if _world.player.grid.skill_items().size() < 2:
			var wand2 := EquipLibrary.staff()
			wand2.socketed = GemLibrary.gem_fireball()
			_world.player.grid.place_anywhere(wand2)
			_world.player.set_skill(0)
		_link_before_switch = _world.player.skill_index
		var ev := InputEventAction.new()
		ev.action = &"switch_skill"
		ev.pressed = true
		Input.parse_input_event(ev)
		print("[第五段] 按 Q 切技能")

	if _did_switch and _link_after_switch < 0 and now >= PHASE_E_AT + 4:
		_link_after_switch = _world.player.skill_index

	# 朝最近的活敌人开火（等价于玩家瞄准点鼠标）
	if _did_pick and now >= _next_fire:
		_next_fire += FIRE_EVERY
		var t := _nearest_enemy()
		if t != null:
			var dir := (t.global_position - _world.player.global_position).normalized()
			_world._on_cast_requested(_world.player.global_position + Vector2(0, -7), dir)

	# 电球术的感电：盯着全场所有怪，因为它是乱窜的，打中谁不一定
	if _did_phase_c and not _saw_shock:
		for n in root.get_tree().get_nodes_in_group(&"enemy"):
			var e := n as Enemy
			if e != null and e.stats != null and e.stats.buffs.has(&"shock"):
				_saw_shock = true
				print("第 %d 物理帧：电球术命中，目标身上出现【感电】" % now)
				break

	# 观察目标的命中 / 点燃
	if is_instance_valid(_watch) and _watch.stats != null:
		if not _saw_hit and _watch.stats.life < _watch.stats.max_life():
			_saw_hit = true
			print("第 %d 物理帧：命中，生命 %.0f" % [now, _watch.stats.life])
		if not _saw_ignite and _watch.stats.buffs.has(&"ignite"):
			_saw_ignite = true
			_life_when_ignited = _watch.stats.life
			print("第 %d 物理帧：目标身上出现【点燃】" % now)

	# ---------- 差异化（ADR-036）：火球命中爆炸打到旁边的怪；带瘟疫的怪死掉传给身边的 ----------
	if not _did_diff and now >= PHASE_ARC_AT - 20:
		_did_diff = true
		_rebuild_grid(&"fireball", &"")
		var pl := _world.player
		var es: Array = []
		for n in root.get_tree().get_nodes_in_group(&"enemy"):
			var e := n as Enemy
			if e != null and e.stats != null and e.stats.is_alive():
				es.append(e)
		if es.size() >= 3:
			var a := es[0] as Enemy
			_diff_b = es[1]
			a.global_position = pl.global_position + Vector2(40.0, 0.0)          # 火球直接命中它
			_diff_b.global_position = pl.global_position + Vector2(40.0, 30.0)  # 在爆炸半径 45 内、不在弹道上
			for e in es:
				(e as Enemy).stats.buffs.clear()
				if e != a and e != _diff_b:
					(e as Enemy).global_position = pl.global_position + Vector2(-160.0, 160.0)
			a.stats.life = a.stats.max_life()
			_diff_b.stats.life = _diff_b.stats.max_life()
			_explode_before = int(_world.behaviour_counts.get("explode_hits", 0))
			_world._on_cast_requested(pl.global_position, Vector2.RIGHT)
			_diff_at = now
			_diff_stage = 1

	if _diff_stage == 1 and now >= _diff_at + 12 and is_instance_valid(_diff_b):
		_diff_stage = 2
		_check("★ 火球命中爆炸：弹道外 30 像素的怪也掉血了（explode_hits +1）★",
				int(_world.behaviour_counts.get("explode_hits", 0)) > _explode_before
				and _diff_b.stats.life < _diff_b.stats.max_life(),
				"explode_hits %d → %d，B 生命 %.0f" % [_explode_before, int(_world.behaviour_counts.get("explode_hits", 0)), _diff_b.stats.life])
		# 瘟疫扩散：给 B 挂上瘟疫，把 A 移到它旁边、杀掉 B → A 该染上
		var pl := _world.player
		var a: Enemy = null
		for n in root.get_tree().get_nodes_in_group(&"enemy"):
			var e := n as Enemy
			if e != null and e != _diff_b and e.stats != null and e.stats.is_alive():
				a = e
				break
		if a != null:
			a.global_position = _diff_b.global_position + Vector2(30.0, 0.0)
			a.stats.buffs.clear()
			_diff_b.stats.apply_buff(Demo.buff_contagion(), pl.stats)
			_check("B 身上有瘟疫、A 没有", _diff_b.stats.buffs.has(&"contagion") and not a.stats.buffs.has(&"contagion"))
			_diff_b.stats.take_damage(9.0e9)
			_diff_b = a   # 下一步看 A
	if _diff_stage == 2 and now >= _diff_at + 16 and is_instance_valid(_diff_b):
		_diff_stage = 3
		_check("★ 带瘟疫的怪死掉 → 身边的怪染上瘟疫 ★", _diff_b.stats.buffs.has(&"contagion")
				and int(_world.behaviour_counts.get("contagion_spread", 0)) >= 1,
				"spread %d" % int(_world.behaviour_counts.get("contagion_spread", 0)))

	# ---------- 电弧连锁（ADR-035）：两只怪排成一列，一发电弧要连锁到第二只 ----------
	if not _did_arc and now >= PHASE_ARC_AT:
		_did_arc = true
		_rebuild_grid(&"arc", &"")
		var pl := _world.player
		var es: Array = []
		for n in root.get_tree().get_nodes_in_group(&"enemy"):
			var e := n as Enemy
			if e != null and e.stats != null and e.stats.is_alive():
				es.append(e)
		if es.size() >= 2:
			_arc_a = es[0]
			_arc_b = es[1]
			_arc_a.global_position = pl.global_position + Vector2(40.0, 0.0)
			_arc_b.global_position = pl.global_position + Vector2(100.0, 0.0)
			for e in es:
				(e as Enemy).stats.buffs.clear()
				# ★ 其它怪全赶到远处 ★ —— 它们正围着玩家贴身站，电弧一出生就先撞上它们、
				#   连锁也跳向它们，A / B 反而一根毛没掉（真的发生过）
				if e != _arc_a and e != _arc_b:
					(e as Enemy).global_position = pl.global_position + Vector2(-160.0, -160.0)
			_arc_a.stats.life = _arc_a.stats.max_life()
			_arc_b.stats.life = _arc_b.stats.max_life()
			_arc_link_before = int(_world.behaviour_counts.get("link", 0))
			_world._on_cast_requested(pl.global_position, Vector2.RIGHT)
			print("[电弧] 投射物参数: %s" % _spec_text())

	if _did_arc and now >= PHASE_ARC_AT + 20 and now < PHASE_ARC_AT + 21 and is_instance_valid(_arc_a) and is_instance_valid(_arc_b):
		_check("★ 电弧命中第一只后连锁到了第二只（behaviour link +1）★",
				int(_world.behaviour_counts.get("link", 0)) > _arc_link_before,
				"link %d → %d" % [_arc_link_before, int(_world.behaviour_counts.get("link", 0))])
		_check("两只都掉血了", _arc_a.stats.life < _arc_a.stats.max_life() and _arc_b.stats.life < _arc_b.stats.max_life(),
				"A %.0f / B %.0f" % [_arc_a.stats.life, _arc_b.stats.life])
		_check("电弧的投射物没有弹射次数", ProjectileSpec.build(_world.player.stats, _world.player.skill).chain_count == 0)

	# ---------- 第七段：范围技能不走投射物（ADR-030）----------
	# 新星：把一只怪挪到身边 60 像素处（圈半径 90），放一次 → 它得立刻挨打 + 冰缓，
	# 而且场上不该多出任何投射物。风暴呼唤：指着它放，1.2 秒内不掉血，到点才劈。
	if not _did_area and now >= PHASE_F_AT:
		_did_area = true
		_rebuild_grid(&"ice_nova", &"")
		_area_target = _nearest_enemy()
		if _area_target != null:
			_area_target.global_position = _world.player.global_position + Vector2(60.0, 0.0)
			_area_target.stats.buffs.remove(&"chill")
			_area_target.stats.life = _area_target.stats.max_life()
			_area_hits_before = int(_world.behaviour_counts.get("area_hits", 0))
			var projectiles_before := _count_projectiles()
			_world._on_cast_requested(_world.player.global_position, Vector2.RIGHT)
			_check("★ 新星是范围技能：场上没有多出投射物 ★", _count_projectiles() == projectiles_before,
					"放之前 %d 发，放之后 %d 发" % [projectiles_before, _count_projectiles()])
		print("[第七段] 冰霜新星    参数: %s" % _world.player.area_spec().describe())

	if _did_area and not _nova_checked and now >= PHASE_F_AT + 3 and is_instance_valid(_area_target):
		_nova_checked = true
		_check("★ 新星瞬发：圈里的怪立刻掉血 ★", _area_target.stats.life < _area_target.stats.max_life(),
				"生命 %.0f / %.0f" % [_area_target.stats.life, _area_target.stats.max_life()])
		_check("新星命中附加了冰缓", _area_target.stats.buffs.has(&"chill"))
		_check("范围命中计入了 behaviour_counts.area_hits",
				int(_world.behaviour_counts.get("area_hits", 0)) > _area_hits_before)
		_check("范围施法计入了 behaviour_counts.area", int(_world.behaviour_counts.get("area", 0)) >= 1)
		_check("场上出现了 AreaBurst 特效节点", _count_bursts() >= 1)
		# --- 风暴呼唤：指着这只怪放，延迟 1.2 秒 ---
		_did_storm = true
		_rebuild_grid(&"storm_call", &"")
		_area_target.stats.life = _area_target.stats.max_life()
		_storm_life_before = _area_target.stats.life
		_storm_hits_before = int(_world.behaviour_counts.get("area_hits", 0))
		var from := _world.player.global_position
		_world._on_cast_requested(from, (_area_target.global_position - from).normalized(),
				_area_target.global_position)
		print("[第七段] 风暴呼唤    参数: %s" % _world.player.area_spec().describe())

	if _did_storm and not _storm_early_checked and now >= PHASE_F_AT + 3 + 20 and is_instance_valid(_area_target):
		_storm_early_checked = true
		_check("★ 风暴呼唤有延迟：0.3 秒时圈里的怪还没掉血 ★",
				is_equal_approx(_area_target.stats.life, _storm_life_before)
				and int(_world.behaviour_counts.get("area_hits", 0)) == _storm_hits_before,
				"生命 %.0f（放之前 %.0f）" % [_area_target.stats.life, _storm_life_before])
		_check("预警圈在场上（AreaBurst 还活着）", _count_bursts() >= 1)

	if _did_storm and not _storm_checked and now >= PHASE_F_AT + 3 + STORM_DELAY_FRAMES + 12 and is_instance_valid(_area_target):
		_storm_checked = true
		_check("★ 1.2 秒后雷劈下来：圈里的怪掉血了 ★", _area_target.stats.life < _storm_life_before,
				"生命 %.0f（放之前 %.0f）" % [_area_target.stats.life, _storm_life_before])
		_check("落雷计入 area_hits", int(_world.behaviour_counts.get("area_hits", 0)) > _storm_hits_before)
		_check("落雷附加感电", _area_target.stats.buffs.has(&"shock"))
		# --- 烈焰风暴：一个圈炸 6 次（ADR-031 的脉冲）---
		_did_firestorm = true
		_rebuild_grid(&"firestorm", &"")
		_firestorm_area_before = int(_world.behaviour_counts.get("area", 0))
		_firestorm_at = now
		var from := _world.player.global_position
		_world._on_cast_requested(from, (_area_target.global_position - from).normalized(),
				_area_target.global_position)
		print("[第七段] 烈焰风暴    参数: %s" % _world.player.area_spec().describe())

	if _did_firestorm and not _firestorm_checked and now >= _firestorm_at + FIRESTORM_FRAMES:
		_firestorm_checked = true
		var pulses := int(_world.behaviour_counts.get("area", 0)) - _firestorm_area_before
		_check("★ 烈焰风暴一个圈炸了 6 次 ★（每次都是一轮完整结算）", pulses == 6, "实际 %d 次" % pulses)
		# --- 近战：铁剑 + 横扫。面前的怪挨打，背后的不挨；出手间隔走攻速 ---
		_rebuild_melee_grid(&"cleave")
		var pl := _world.player
		var enemies: Array = []
		for n in root.get_tree().get_nodes_in_group(&"enemy"):
			var e := n as Enemy
			if e != null and e.stats != null and e.stats.is_alive():
				enemies.append(e)
		if enemies.size() >= 2:
			# ① 真实按键链路先走：_try_cast 的冷却要按**攻击速度**算（铁剑 +10%、击杀的狂怒 +20%），
			#    要是错走了施法速度（此刻是 1.0）就会红。★ 先做这个 ★ —— headless 下鼠标在 (0,0)，
			#    _try_cast 会朝左挥一下，放在摆怪之后会误伤"背后的怪"
			pl.can_aim = true
			pl.stats.mana = pl.stats.max_mana()
			pl._cast_cd = 0.0
			# ★ 先读攻速再挥 ★ —— 这一挥可能击杀 → 狂怒（攻速 +20%）立刻上身，挥完再读就对不上了（真的抖过）
			var cleave_tags := pl.skill.hit_tags()
			var aps := pl.stats.get_stat(S.ATTACK_SPEED, cleave_tags)
			var cps := pl.stats.get_stat(S.CAST_SPEED, cleave_tags)
			pl._try_cast()
			_check("攻速和施速此刻不同（否则下面这条是恒真）", not is_equal_approx(aps, cps),
					"攻速 %.2f / 施速 %.2f" % [aps, cps])
			_check("★ 攻击技能的出手间隔走攻击速度 ★（0.8 ÷ %.2f）" % aps,
					is_equal_approx(pl._cast_cd, 0.80 / aps), "实际 %.3f 秒" % pl._cast_cd)
			# ② 摆怪：一只面前、一只背后，朝右挥一下
			_melee_front = enemies[0]
			_melee_back = enemies[1]
			_melee_front.global_position = pl.global_position + Vector2(40.0, 0.0)    # 面前（朝右挥）
			_melee_back.global_position = pl.global_position + Vector2(-70.0, 0.0)    # 背后
			# ★ 先把身上的点燃 / 中毒清掉 ★ —— 刚才的烈焰风暴大概率把它们点着了，
			#   DoT 会在"背后的怪没挨到"这条断言上冒出几十点掉血，误判成挥砍打到了它
			_melee_front.stats.buffs.clear()
			_melee_back.stats.buffs.clear()
			_melee_front.stats.life = _melee_front.stats.max_life()
			_melee_back.stats.life = _melee_back.stats.max_life()
			var projectiles_before := _count_projectiles()
			_world._on_cast_requested(pl.global_position, Vector2.RIGHT, pl.global_position + Vector2(100, 0))
			_check("★ 近战不产生投射物 ★", _count_projectiles() == projectiles_before)
			print("[第七段] 横扫（铁剑）    参数: %s" % pl.area_spec().describe())
		_melee_at = now

	if _melee_at > 0 and not _melee_checked and now >= _melee_at + 4:
		_melee_checked = true
		if is_instance_valid(_melee_front) and is_instance_valid(_melee_back):
			_check("★ 面前的怪挨了横扫 ★", _melee_front.stats.life < _melee_front.stats.max_life(),
					"生命 %.0f / %.0f" % [_melee_front.stats.life, _melee_front.stats.max_life()])
			_check("★ 背后的怪没挨到 ★", is_equal_approx(_melee_back.stats.life, _melee_back.stats.max_life()),
					"生命 %.0f / %.0f" % [_melee_back.stats.life, _melee_back.stats.max_life()])
		# --- 旋风斩：圈要跟着玩家走（用户反馈：以前钉在施放点上）---
		_rebuild_melee_grid(&"cyclone")
		var pl := _world.player
		_world._on_cast_requested(pl.global_position, Vector2.RIGHT, pl.global_position + Vector2(100, 0))
		for c in _world.fx.get_children():
			if c is AreaBurst and not c.is_queued_for_deletion():
				_cyclone_burst = c
		_check("旋风斩放出了一个圈", _cyclone_burst != null)
		# 把玩家挪走 60 像素（等价于按住方向键跑了一段），圈下一帧就该跟过来
		pl.global_position += Vector2(60.0, 0.0)
		_cyclone_at = now

	if _cyclone_at > 0 and not _cyclone_checked and now >= _cyclone_at + 3:
		_cyclone_checked = true
		var pl := _world.player
		if is_instance_valid(_cyclone_burst):
			_check("★ 旋风斩的圈跟着玩家走 ★（挪了 60 像素，圈就在脚下）",
					_cyclone_burst.global_position.distance_to(pl.global_position) < 2.0,
					"圈在 %s，人在 %s" % [_cyclone_burst.global_position, pl.global_position])
		else:
			_check("旋风斩的圈 3 帧后还该活着（冲击波 0.28 秒）", false)
		# --- 引导（ADR-033）：按住 = 一直转、一直扣蓝；引导中 Q 无效；松手就停 ---
		# 网格里再放一根镶着电球术的法杖，Q 才有得切（切成功 = 引导没封住 Q）
		var wand := EquipLibrary.apprentice_wand()
		wand.socketed = GemLibrary.gem_spark()
		pl.grid.place_anywhere(wand)
		for i in pl.grid.skill_items().size():
			if (pl.grid.skill_items()[i] as GemGrid.Placed).gem.id == &"iron_sword":
				pl.set_skill(i)
		_channel_index = pl.skill_index
		_check("当前是旋风斩（铁剑里的）", pl.skill != null and pl.skill.id == &"cyclone")
		_world.set_process(false)    # headless 鼠标在 (0,0)，别让 World 每帧把 can_aim 判成 false
		pl.can_aim = true
		pl.stats.mana = pl.stats.max_mana()
		_channel_mana = pl.stats.mana
		pl._cast_cd = 0.0
		Input.action_press(&"cast")
		_channel_at = now
		_channel_stage = 1

	if _channel_stage == 1 and now >= _channel_at + 3:
		_channel_stage = 2
		var pl := _world.player
		_check("★ 按住 3 帧：正在引导、蓝已经扣了 ★", pl.is_channeling() and pl.stats.mana < _channel_mana,
				"channeling=%s mana %.0f → %.0f" % [str(pl.is_channeling()), _channel_mana, pl.stats.mana])
		_channel_mana = pl.stats.mana
		var ev := InputEventAction.new()
		ev.action = &"switch_skill"
		ev.pressed = true
		Input.parse_input_event(ev)
	if _channel_stage == 2 and now >= _channel_at + 6:
		_channel_stage = 3
		var pl := _world.player
		_check("★ 引导中按 Q：技能没切走 ★", pl.skill_index == _channel_index and pl.skill.id == &"cyclone",
				"index %d → %d" % [_channel_index, pl.skill_index])
		_check("还在引导", pl.is_channeling())
	if _channel_stage == 3 and now >= _channel_at + 3 + 16:
		_channel_stage = 4
		var pl := _world.player
		_check("★ 按住 0.25 秒以上：又扣了一段蓝（持续消耗）★", pl.stats.mana < _channel_mana,
				"mana %.0f → %.0f" % [_channel_mana, pl.stats.mana])
		Input.action_release(&"cast")
	if _channel_stage == 4 and now >= _channel_at + 3 + 16 + 3:
		_channel_stage = 5
		var pl := _world.player
		_check("★ 松手：引导结束 ★", not pl.is_channeling())
		var ev := InputEventAction.new()
		ev.action = &"switch_skill"
		ev.pressed = true
		Input.parse_input_event(ev)
	if _channel_stage == 5 and now >= _channel_at + 3 + 16 + 6:
		_channel_stage = 6
		var pl := _world.player
		_check("松手之后 Q 又能切了", pl.skill_index != _channel_index, "index %d" % pl.skill_index)
		# 蓝不够 → 引导放不出来 → 不算引导中
		for i in pl.grid.skill_items().size():
			if (pl.grid.skill_items()[i] as GemGrid.Placed).gem.id == &"iron_sword":
				pl.set_skill(i)
		pl.stats.mana = 0.0
		pl._cast_cd = 0.0
		Input.action_press(&"cast")
	if _channel_stage == 6 and now >= _channel_at + 3 + 16 + 9:
		_channel_stage = 7
		var pl := _world.player
		_check("★ 没蓝：按住也引导不起来 ★", not pl.is_channeling())
		Input.action_release(&"cast")
		_world.set_process(true)

	if now >= CHECK_AT:
		_report()
		_start_run_phase()   # 沙盒段结束 → 接着测局模式（不退出）
	return false


func _report() -> void:
	_check("火球命中并造成伤害", _saw_hit)
	_check("命中后附加了【点燃】", _saw_ignite)

	if is_instance_valid(_watch):
		_check("点燃持续掉血", _watch.stats.life < _life_when_ignited,
				"点燃时 %.0f，现在 %.0f" % [_life_when_ignited, _watch.stats.life])
	else:
		print("   PASS  目标已被打死（说明伤害链路是通的）")

	_check("玩家还活着或已正确判定死亡", _world.player.stats.life >= 0.0)
	_check("敌人会补刷", _world.get_tree().get_node_count_in_group(&"enemy") > 0)

	# ---------- 布局：右边是 400×400 的正方形战斗画面 ----------
	_check("战斗画面是正方形", is_equal_approx(_world.battle.size.x, _world.battle.size.y),
			"%.0f × %.0f" % [_world.battle.size.x, _world.battle.size.y])
	_check("战斗画面在右侧（左边留给常驻面板）",
			is_equal_approx(_world.battle.position.x, InventoryUI.PANEL_W),
			"x = %.0f" % _world.battle.position.x)
	# 摄像机 zoom=2，所以画面里看到的世界是 400/2 = 200×200，比场地小 → 会跟着玩家滚动。
	# limit 必须卡在场地边界上，否则会拍到场地外面的黑边。
	var cam := _world.player.get_node("Camera") as Camera2D
	_check("摄像机的边界卡在场地上",
			cam.limit_left == int(-GameWorld.ARENA.x) and cam.limit_right == int(GameWorld.ARENA.x)
			and cam.limit_top == int(-GameWorld.ARENA.y) and cam.limit_bottom == int(GameWorld.ARENA.y))
	_check("画面比场地小 → 摄像机会跟着玩家滚",
			_world.battle.size.x / cam.zoom.x < GameWorld.ARENA.x * 2.0,
			"可见 %.0f，场地 %.0f" % [_world.battle.size.x / cam.zoom.x, GameWorld.ARENA.x * 2.0])
	# ★ 一切都活在 SubViewport 里，所以怪物不可能跑到左边的面板上去 ★
	_check("玩家在战斗画面的 SubViewport 里", _world.player.get_viewport() == _world.view)
	_check("敌人也在同一个 SubViewport 里",
			_nearest_enemy() == null or _nearest_enemy().get_viewport() == _world.view)

	# ---------- 「能不能施法」的区域判断 ----------
	# ★ 这里踩过一次坑 ★ get_rect()（父坐标）和 get_local_mouse_position()（自身坐标）
	# 混着比，结果只有最右边 100px 能施法。所以把整块区域挨个角落都验一遍。
	var w: float = InventoryUI.PANEL_W          # 300：战斗画面的左边界
	var e: float = w + _world.battle.size.x     # 700：右边界
	var h: float = _world.battle.size.y         # 400
	_check("战斗画面左边缘内侧能施法", _world.is_in_battle_view(Vector2(w + 1.0, h * 0.5)))
	_check("战斗画面正中间能施法", _world.is_in_battle_view(Vector2((w + e) * 0.5, h * 0.5)))
	_check("战斗画面右边缘内侧能施法", _world.is_in_battle_view(Vector2(e - 1.0, h * 0.5)))
	_check("战斗画面上下边缘内侧能施法",
			_world.is_in_battle_view(Vector2((w + e) * 0.5, 1.0))
			and _world.is_in_battle_view(Vector2((w + e) * 0.5, h - 1.0)))
	_check("★ 左边面板上不能施法 ★", not _world.is_in_battle_view(Vector2(w * 0.5, h * 0.5)))
	_check("面板最右边一格也不能施法", not _world.is_in_battle_view(Vector2(w - 1.0, h * 0.5)))

	# ★★ 按住施法键真的能放出东西来（走的是完整的 Player._try_cast 链路）★★
	_check("★ 按住施法键能放出投射物 ★", _cast_max_projectiles > 0,
			"期间场上最多 %d 发" % _cast_max_projectiles)

	# ★★ 鼠标位置跟得上吗 ★★
	# 玩家靠 get_global_mouse_position() 决定往哪放技能，跟不上就会永远朝同一个方向打。
	#
	# 只断言"值变了"。本来还想断言 view.mouse == 主视口鼠标 - 容器左上角，
	# 但实测发现这条**恒真** —— SubViewport 的鼠标位置是引擎按容器位置实时推算的，
	# 不是自己存一份，所以它不可能和容器错位，写了也测不出任何东西。
	_check("★ 鼠标位置跟得上（瞄准方向才是对的）★",
			_mouse_after != _mouse_before,
			"注入前 %s，注入后 %s" % [_mouse_before, _mouse_after])

	# ★★ 按键事件转发进 SubViewport 了吗（Q 切技能 / 1~5 换辅助都靠它）★★
	_check("★ 按 Q 能切技能（按键转发进了 SubViewport）★",
			_link_after_switch >= 0 and _link_after_switch != _link_before_switch,
			"切换前 %d，切换后 %d" % [_link_before_switch, _link_after_switch])

	var total: Dictionary = _world.behaviour_counts
	print("第一段（弹射）行为统计: ", _chain_counts)
	print("全程行为统计: ", total)

	# 弹射：可能找不到下一个目标，那也算走到了弹射分支
	var chain_hits := int(_chain_counts.get("chain", 0)) + int(_chain_counts.get("chain_fail", 0))
	_check("装弹射支援后，命中进入了弹射判定", chain_hits > 0,
			"chain=%d chain_fail=%d" % [
				int(_chain_counts.get("chain", 0)), int(_chain_counts.get("chain_fail", 0))])

	# 分叉：只要命中就必然发生
	_check("装分叉支援后，命中触发了分叉", int(total["fork"]) > 0)

	# ★ 触媒靠"施加异常"的上报计数 ★ —— 火球命中点燃时投射物会发 buff_ignite 事件，
	# 走真实链路进 behaviour_counts。这条红了 = 触媒的点燃/感电计数断了粮
	_check("★ 施加点燃的事件被上报（触媒靠它计数）★",
			int(total.get("buff_ignite", 0)) > 0, str(total))

	# 电球术：4 发扇形乱窜，2.4 秒内必然有几发撞到场地边缘并弹回来
	var bounces := int(total.get("bounce", 0)) - int(_fork_counts.get("bounce", 0))
	_check("切到电球术后，投射物撞墙反弹了", bounces > 0, "本段反弹 %d 次" % bounces)
	_check("电球术命中并挂上了【感电】", _saw_shock)

	# 全程都没连穿透支援，所以一次穿透都不该发生。
	# （加个前置判断：带窗口跑的时候有可能被真实按键改了宝石配置）
	if not _support_linked(&"sup_pierce"):
		_check("没连穿透支援 → 一次穿透都没发生", int(total["pierce"]) == 0)

	_check_icons()
	_check_inventory_ui()
	# ★ 这里不再 quit ★ —— 后面还有第七段（局模式），总结和退出在 _finish_all()


## ---------- 图标资源 ----------
##
## 每一件宝石/装备在 assets/icons/ 下都要有同名 .webp，而且真的能被引擎加载。
## 这条会红的方式很多：文件改名对不上 id、忘了跑 --import、文件格式是坏的
## （出过一次真事：19 张图全是 WebP 却顶着 .png 的扩展名，导入器直接失败）。
## UI 那边加载失败只会安静地退回文字短名，不靠测试根本发现不了。
func _check_icons() -> void:
	print("\n[图标] 每件宝石/装备都要有能加载的图标")
	var all: Array = []
	all.append_array(GemLibrary.all_gems())
	all.append_array(EquipLibrary.all_items())
	var missing := PackedStringArray()
	for thing in all:
		var tex := UIHelper.gem_icon(thing)
		if tex == null or tex.get_size().x <= 0.0:
			missing.append(String(thing.id))
	_check("全部 %d 件都有图标且加载成功" % all.size(), missing.is_empty(),
			"缺：" + ", ".join(missing))


## ---------- 第六段：背包网格的交互 ----------
##
## 直接调 InventoryUI 里那几个"点击/右键会跑的方法"，等价于用鼠标操作。
## 这样"拿起 → 转方向 → 放下 → 箭头连上"整条链路都在真实场景里跑过一遍 ——
## 光靠单元测试测不到 Control 那一层。
func _check_inventory_ui() -> void:
	print("\n[第六段] 背包网格的交互")
	var hud: GameHUD = _world.hud
	var p: Player = _world.player
	var inv: InventoryUI = hud.inventory()

	# ★ 左侧面板是常驻的 ★ 没有开关键，它一直在
	_check("★ 左侧面板常驻显示 ★", inv.visible)
	_check("面板占住左边 300px", is_equal_approx(inv.size.x, InventoryUI.PANEL_W),
			"实际宽 %.0f" % inv.size.x)

	# 摆一个干净的局面：见习法杖镶着电球术在 (3,2)-(3,3)，延长持续在 (0,4) 谁也没指着
	p.grid = GemGrid.new()
	var spark: SkillGem = GemLibrary.gem_spark()
	var wand: EquipItem = EquipLibrary.apprentice_wand()
	wand.socketed = spark
	var dur: SupportGem = GemLibrary.support_duration()
	p.grid.place(wand, Vector2i(3, 2), 0)
	p.grid.place(dur, Vector2i(0, 4), 0)      # 箭头 → 指到 (1,4)，那里是空的
	p.set_skill(0)
	inv.refresh()

	_check("一开始「延长持续」没连上", p.grid.supports_for(p.grid.skill_items()[0]).is_empty())
	var cost_before := p.skill.mana_cost
	var dur_before := ProjectileSpec.build(p.stats, p.skill).duration

	# --- 拿起来 ---
	inv._on_cell_pressed(Vector2i(0, 4))
	_check("★ 点一下就把宝石拿起来了 ★",
			inv._held != null and (inv._held as SupportGem).id == &"sup_duration")
	_check("网格里少了一件", p.grid.at(Vector2i(0, 4)) == null)

	# --- 右键转方向 ---
	var rot_before := inv._held_rot
	inv._on_rotate_pressed()
	_check("★ 右键能转方向 ★", inv._held_rot != rot_before,
			"%d → %d" % [rot_before, inv._held_rot])
	inv._on_rotate_pressed()
	inv._on_rotate_pressed()
	inv._on_rotate_pressed()
	_check("转 4 次回到原来的方向", inv._held_rot == rot_before)

	# --- 放到法杖左边、箭头朝右指进法杖 → 应该连上（辅助的是槽里的电球术）---
	inv._grid_view._hover = Vector2i(2, 2)     # 模拟鼠标悬停在 (2,2)，法杖左边
	inv._on_cell_pressed(Vector2i(2, 2))
	_check("放下了（手上空了）", inv._held == null, inv._notice)
	var sk: GemGrid.Placed = p.grid.skill_items()[0]
	_check("★ 箭头指进法杖 → 连上了 ★", p.grid.supports_for(sk).size() == 1)
	_check("★ 魔力消耗变贵了（辅助宝石的倍率）★", p.skill.mana_cost > cost_before,
			"%.1f → %.1f" % [cost_before, p.skill.mana_cost])
	_check("★ 电球术的投射物持续时间变长了 ★",
			ProjectileSpec.build(p.stats, p.skill).duration > dur_before,
			"%.2fs → %.2fs" % [dur_before, ProjectileSpec.build(p.stats, p.skill).duration])

	# --- 辅助宝石压在法杖身上要被拒绝（只有技能宝石才能镶），宝石不能凭空消失 ---
	inv._on_cell_pressed(Vector2i(2, 2))       # 再拿起来
	inv._grid_view._hover = Vector2i(3, 2)     # 压在法杖身上
	inv._on_cell_pressed(Vector2i(3, 2))
	_check("★ 压在别人身上 → 放不下 ★", inv._held != null)
	_check("界面给出了拒绝原因", inv._notice != "", inv._notice)

	# --- 转个方向就能塞进别的空当（这就是网格背包的乐趣）---
	inv._grid_view._hover = Vector2i(6, 6)
	inv._on_cell_pressed(Vector2i(6, 6))
	_check("换个空地就放得下了", inv._held == null, inv._notice)

	# --- 升级 ---
	var lv := spark.level
	var dmg := p.skill.base_damage
	inv._detail = spark
	inv._change_detail_level(1)
	_check("点 [+] 能升级", spark.level == lv + 1, "%d → %d" % [lv, spark.level])
	_check("升级后点伤变高", p.skill.base_damage > dmg,
			"%.1f → %.1f" % [dmg, p.skill.base_damage])
	inv._change_detail_level(-1)
	_check("点 [-] 能降级", spark.level == lv)

	# --- ★ 镶嵌：拿一颗技能宝石点到法杖上（走的是真实的点击链路）★ ---
	p.grid = GemGrid.new()
	var wand2: EquipItem = EquipLibrary.apprentice_wand()        # 空槽
	p.grid.place(wand2, Vector2i(3, 2), 0)
	var loose: SkillGem = GemLibrary.gem_arc()
	p.grid.place(loose, Vector2i(0, 0), 0)
	p.set_skill(0)
	_check("空法杖 + 裸宝石：没有能施放的技能", p.skill == null)
	inv._held = null
	inv._on_cell_pressed(Vector2i(0, 0))          # 拿起裸宝石
	_check("拿起了技能宝石", inv._held == loose)
	inv._grid_view._hover = Vector2i(3, 3)        # 点在法杖的第二格上
	inv._on_cell_pressed(Vector2i(3, 3))
	_check("★ 点法杖 = 镶进槽位，手上空了 ★", inv._held == null, inv._notice)
	_check("★ 槽里现在是它，技能可以施放了 ★",
			wand2.socketed == loose and p.skill != null and p.skill.id == &"arc")
	_check("界面提示了镶入", inv._notice.contains("镶入"), inv._notice)

	# --- ★ 取出宝石：详情面板的「取出」按钮 ★ ---
	inv._detail = wand2
	inv._unsocket_detail()
	_check("★ 取出后宝石回到手上 ★", inv._held == loose and wand2.socketed == null,
			inv._notice)
	_check("没有载体了 → 技能又没了", p.skill == null)
	inv._grid_view._hover = Vector2i(3, 2)        # 再点回法杖，镶回去
	inv._on_cell_pressed(Vector2i(3, 2))
	_check("再点法杖又镶回去了", wand2.socketed == loose and inv._held == null)

	# --- ★ 空手右键点法杖 = 取出宝石 ★（比按钮可靠：不依赖悬停详情）---
	inv._grid_view._hover = Vector2i(3, 3)        # 右键点在法杖的另一格上
	inv._on_rotate_pressed()
	_check("★ 空手右键点法杖 → 宝石取出到手上 ★",
			inv._held == loose and wand2.socketed == null, inv._notice)
	inv._grid_view._hover = Vector2i(3, 2)        # 镶回去，别影响后面的段落
	inv._on_cell_pressed(Vector2i(3, 2))
	# 空手右键点空地：不该炸，也不该动到任何东西
	inv._grid_view._hover = Vector2i(7, 6)
	inv._on_rotate_pressed()
	_check("空手右键点空地：无事发生", inv._held == null and wand2.socketed == loose)

	# --- 合成：同款宝石叠上去 = 升级（走的是真实的点击链路）---
	p.grid = GemGrid.new()
	var m1: SkillGem = GemLibrary.gem_spark()
	m1.level = 4
	var m2: SkillGem = GemLibrary.gem_spark()
	m2.level = 4
	p.grid.place(m1, Vector2i(3, 2), 0)
	p.grid.place(m2, Vector2i(5, 4), 0)
	p.set_skill(0)
	inv._held = null
	inv._on_cell_pressed(Vector2i(5, 4))          # 拿起第二颗
	_check("拿起了要合的那颗", inv._held == m2)
	inv._grid_view._hover = Vector2i(3, 2)
	inv._on_cell_pressed(Vector2i(3, 2))          # 叠到第一颗上
	_check("★ 同款叠放 = 合成，手上空了 ★", inv._held == null, inv._notice)
	_check("★ 4 级 + 4 级 → 5 级 ★", m1.level == 5, "实际 %d 级" % m1.level)
	_check("被吃掉的那颗没回网格", p.grid.items.size() == 1,
			"实际 %d 件" % p.grid.items.size())
	_check("界面提示了合成", inv._notice.contains("合成"), inv._notice)

	# --- ★ 丢弃：两段确认，第一次只警告、第二次才真的扔 ★ ---
	p.grid = GemGrid.new()
	var junk: SupportGem = GemLibrary.support_crit()
	p.grid.place(junk, Vector2i(2, 2), 0)
	p.set_skill(0)
	inv._held = null
	inv._on_cell_pressed(Vector2i(2, 2))          # 拿起要丢的东西
	_check("拿起了要丢的东西", inv._held == junk)
	inv._discard_held()
	_check("★ 第一次点「丢弃」只是确认提示，东西还在手上 ★",
			inv._held == junk and inv._notice.contains("再点一次"), inv._notice)
	inv._discard_held()
	_check("★ 第二次点才真的丢掉：手空了、网格里也没有 ★",
			inv._held == null and p.grid.items.is_empty(), inv._notice)
	inv._discard_held()
	_check("空手点「丢弃」只给提示、不炸", inv._held == null
			and inv._notice.contains("拿在手上"), inv._notice)

	# 改主意的路径：确认到一半把东西放回去，再拿起来 → 必须重新确认，不能"一点就没"
	var junk2: SupportGem = GemLibrary.support_pierce()
	p.grid.place(junk2, Vector2i(3, 3), 0)
	inv._on_cell_pressed(Vector2i(3, 3))          # 拿起
	inv._discard_held()                           # 第一次确认
	inv._grid_view._hover = Vector2i(4, 4)
	inv._on_cell_pressed(Vector2i(4, 4))          # 改主意，放下（清掉确认状态）
	inv._on_cell_pressed(Vector2i(4, 4))          # 再拿起来
	inv._discard_held()
	_check("★ 放下再拿起后，丢弃要重新确认 ★",
			inv._held == junk2 and inv._notice.contains("再点一次"), inv._notice)
	inv._grid_view._hover = Vector2i(4, 4)
	inv._on_cell_pressed(Vector2i(4, 4))          # 放回去，别影响后面的段落

	# --- ★ 触媒：条件达成 → 自动触发（无施法动作、正常扣蓝、蓝不够不触发）★ ---
	p.grid = GemGrid.new()
	var twand: EquipItem = EquipLibrary.apprentice_wand()
	twand.socketed = GemLibrary.gem_spark()
	p.grid.place(twand, Vector2i(3, 2), 0)
	var tcat: CatalystGem = GemLibrary.cat_hits()      # 击中 5 次触发
	p.grid.place(tcat, Vector2i(2, 2), 0)              # 箭头 → 指进法杖
	p.set_skill(0)                                     # rebuild → 触媒缓存重扫
	var fired: Array = []
	var on_fire := func(_sk: SkillSpec, _ps: ProjectileSpec, _as: AreaSpec, cat_name: String) -> void:
		fired.append(cat_name)
	p.catalyst_triggered.connect(on_fire)
	p.stats.mana = p.stats.max_mana()
	for i in 5:
		p.notify_catalyst_event(CatalystGem.Trigger.HITS, 1.0)
	var mana_before := p.stats.mana
	p._pump_catalysts()
	_check("★ 击中 5 次 → 触媒触发了一次 ★", fired.size() == 1, "实际 %d 次" % fired.size())
	_check("★ 触发正常扣蓝 ★", p.stats.mana < mana_before,
			"%.0f → %.0f" % [mana_before, p.stats.mana])
	_check("触发后进度清零", is_zero_approx(tcat.progress))
	# 蓝不够 → 不触发，进度留在门槛上；回蓝后泵一次就补上
	p.stats.mana = 0.0
	for i in 5:
		p.notify_catalyst_event(CatalystGem.Trigger.HITS, 1.0)
	p._pump_catalysts()
	_check("★ 蓝不够不触发 ★", fired.size() == 1)
	_check("进度留在门槛上等回蓝", tcat.ready_to_fire())
	p.stats.mana = p.stats.max_mana()
	p._pump_catalysts()
	_check("★ 回蓝后自动补触发 ★", fired.size() == 2, "实际 %d 次" % fired.size())
	p.catalyst_triggered.disconnect(on_fire)

	# --- ★ 结算口径回归：满足施加条件 = 计一次，目标叠满层也照样计数 ★ ---
	# 走真实的投射物命中链路（_on_body_entered → apply_buff → behaviour → World → 触媒）：
	# 目标感电先叠满 3 层（封顶），再挨 2 发必附感电的电弧 → 施加事件必须 +2。
	p.grid = GemGrid.new()
	var rwand: EquipItem = EquipLibrary.apprentice_wand()
	rwand.socketed = GemLibrary.gem_spark()
	p.grid.place(rwand, Vector2i(3, 2), 0)
	var rcat: CatalystGem = GemLibrary.cat_shock()      # 施加感电 3 次触发
	p.grid.place(rcat, Vector2i(2, 2), 0)
	p.set_skill(0)
	var victim := _nearest_enemy()
	if victim == null:
		_fail("场上没有敌人，验不了施加计数")
	else:
		# 血堆到打不死：第二发命中前目标必须还活着
		victim.stats.set_base(preload("res://combat/combat_stat.gd").MAX_LIFE, 9.9e9)
		victim.stats.refill()
		for i in 3:
			victim.stats.apply_buff(DemoContent.buff_shock(), p.stats)
		_check("目标感电已叠满 3 层", victim.stats.buffs.stacks_of(&"shock") == 3)
		var arcskill := GemLibrary.gem_arc().build()
		var ev_before := int(_world.behaviour_counts.get("buff_shock", 0))
		for i in 2:
			var pr: Projectile = (load("res://game/projectile.tscn") as PackedScene).instantiate()
			pr.source = p.stats
			pr.skill = arcskill
			pr.state = ProjectileState.new(ProjectileSpec.build(p.stats, arcskill))
			pr.behaviour.connect(_world._on_projectile_behaviour)
			pr.position = Vector2(-190, -190)   # 摆远点，别在这帧里物理撞到别的怪
			_world.entities.add_child(pr)
			pr._on_body_entered(victim)          # 手动判一次命中（同步，结果立刻能验）
			pr.queue_free()
		var gained := int(_world.behaviour_counts.get("buff_shock", 0)) - ev_before
		_check("★ 叠满层的目标再被施加 2 次 → 事件 +2 ★（层数封顶 ≠ 施加不计数）",
				gained == 2, "实际 +%d" % gained)
		_check("目标层数仍封顶在 3", victim.stats.buffs.stacks_of(&"shock") == 3)
		_check("★ 触媒吃到了这 2 次进度 ★", is_equal_approx(rcat.progress, 2.0),
				"实际 %.1f" % rcat.progress)

		# --- ★ 防循环：触媒触发出来的弹，施加异常/命中都不喂触媒 ★（ADR-026 补充）---
		var ev_mid := int(_world.behaviour_counts.get("buff_shock", 0))
		var tpr: Projectile = (load("res://game/projectile.tscn") as PackedScene).instantiate()
		tpr.source = p.stats
		tpr.skill = arcskill
		tpr.state = ProjectileState.new(ProjectileSpec.build(p.stats, arcskill))
		tpr.state.from_trigger = true            # 标记成触发产物
		tpr.behaviour.connect(_world._on_projectile_behaviour)
		tpr.position = Vector2(-190, -190)
		_world.entities.add_child(tpr)
		tpr._on_body_entered(victim)
		tpr.queue_free()
		_check("★ 触发产物命中：不上报施加事件（防循环）★",
				int(_world.behaviour_counts.get("buff_shock", 0)) == ev_mid)
		_check("触媒进度也没被它推进", is_equal_approx(rcat.progress, 2.0),
				"实际 %.1f" % rcat.progress)
		_check("但异常照样施加到目标身上（只是不计数）",
				victim.stats.buffs.has(&"shock"))

	# --- 控制台：开关 / 筛选 / 生成进背包 ---
	var console: ConsoleUI = hud.console
	_check("控制台默认关着", not console.visible)
	console.set_open(true)
	_check("控制台能打开", console.visible)
	console.set_filter("equip")
	_check("筛选「装备」= 图鉴装备数",
			console.filtered_things().size() == EquipLibrary.all_items().size())
	console.set_filter("catalyst")
	_check("筛选「触媒」= 6 颗", console.filtered_things().size() == 6)
	console.set_filter("support")
	_check("筛选「辅助宝石」= 21 颗（不含触媒、不含崇高/血脉）", console.filtered_things().size() == 21)
	console.set_filter("rare")
	_check("筛选「崇高/血脉」= 7 颗", console.filtered_things().size() == 7)
	console.set_filter("skill")
	_check("筛选「技能宝石」= 31 颗", console.filtered_things().size() == 31)
	console.set_filter("all")
	_check("筛选「全部」= 图鉴全量",
			console.filtered_things().size() == GemSave.everything().size())
	var grid_n := p.grid.items.size()
	_check("★ 点一件 → 真的进了背包 ★",
			console.spawn(&"iron_helm") and p.grid.items.size() == grid_n + 1)
	console.set_open(false)
	_check("控制台能关上", not console.visible)

	# --- 标签不匹配：箭头指到了法杖，但槽里的技能吃不下，界面要说得清楚 ---
	p.grid = GemGrid.new()
	var wand3: EquipItem = EquipLibrary.apprentice_wand()
	wand3.socketed = GemLibrary.gem_fireball()   # 火球术没有【持续时间】标签
	p.grid.place(wand3, Vector2i(3, 2), 0)
	var dur2: SupportGem = GemLibrary.support_duration()
	var placed := p.grid.place(dur2, Vector2i(2, 2), 0)          # 箭头指进法杖
	p.set_skill(0)
	_check("★ 槽里的火球术没有【持续时间】标签 → 箭头是红的 ★",
			p.grid.arrow_state(placed) == "blocked", p.grid.arrow_state(placed))
	_check("所以它不算辅助", p.grid.supports_for(p.grid.skill_items()[0]).is_empty())
	inv._detail = dur2
	_check("详情面板会写明连不上的原因", inv._detail_bbcode().contains("连不上"))

	# --- 面板文本能生成（格式化字符串写错只有跑到才炸）---
	inv._detail = p.grid.skill_items()[0].gem    # 法杖（连槽里宝石的面板一起生成）
	_check("法杖的详情文本正常（含槽里的宝石）", inv._detail_bbcode().contains("槽里"))
	inv.refresh()

	_check_save_roundtrip()


## ---------- 第七段：背包存档真的能落盘再读回来 ----------
##
## 单元测试只测了序列化（to_data / from_data），文件那一层测不到 ——
## 路径写错、JSON 存不进去、版本号对不上，都得真的读写一次文件才知道。
##
## ★ 存到另一个文件上 ★ 不能碰玩家真正的 user://backpack.json。
func _check_save_roundtrip() -> void:
	print("\n[第七段] 背包存档")
	var p: Player = _world.player
	var real_path := GemSave.path
	GemSave.path = "user://backpack_smoketest.json"
	GemSave.clear()
	GemSave.autosave = true

	# 摆一个认得出来的局面：法杖里镶着 15 级电球术，一颗辅助从右边朝左连上
	p.grid = GemGrid.new()
	var spark: SkillGem = GemLibrary.gem_spark()
	spark.level = 4
	var wand: EquipItem = EquipLibrary.apprentice_wand()
	wand.socketed = spark
	p.grid.place(wand, Vector2i(3, 1), 0)                      # (3,1)-(3,2)
	p.grid.place(GemLibrary.support_duration(), Vector2i(4, 1), 2)
	p.set_skill(0)

	_check("存盘成功", GemSave.save(p))
	_check("存档文件真的生成了", GemSave.has_save())

	# 把背包砸烂，再从存档读回来
	p.grid = GemGrid.new()
	p.skill_index = 0
	_check("★ 读档成功 ★", GemSave.load_into(p))

	# 按 id 找回那根法杖（不能按下标找：读档时会把图鉴里缺的宝石补进来，
	# 而 skill_items() 是按摆放位置排序的，下标会变）
	var sk: GemGrid.Placed = null
	for it in p.grid.items:
		if (it as GemGrid.Placed).gem.id == &"apprentice_wand":
			sk = it
	_check("法杖回来了", sk != null)
	if sk != null:
		_check("★ 槽里还镶着电球术 ★", sk.skill_gem() != null and sk.skill_gem().id == &"spark")
		_check("★ 槽里宝石的等级记住了（4 级）★",
				sk.skill_gem() != null and sk.skill_gem().level == 4,
				"实际 %d 级" % (sk.skill_gem().level if sk.skill_gem() != null else -1))
		_check("★ 位置记住了 ★", sk.origin == Vector2i(3, 1), str(sk.origin))
		# ★ 按 id 验，不数数量 ★ —— 读档会把图鉴里缺的宝石自动补进背包，
		#   补位的落点跟着图鉴大小变，可能恰好有别的辅助也指着它；
		#   这条要验的只是"存档里那颗延长持续的朝向还在 → 箭头还连着"。
		var linked_ids: Array = []
		# supports_for 返回的是 Placed（网格里的摆放记录），宝石本体在 .gem 里
		for sup in p.grid.supports_for(sk):
			linked_ids.append(((sup as GemGrid.Placed).gem as SupportGem).id)
		_check("★ 朝向记住了 → 箭头还连着 ★", linked_ids.has(&"sup_duration"),
				"连着的是 %s" % str(linked_ids))
		_check("★ 当前用的还是电球术（存的是槽里宝石的 id 不是下标）★",
				p.active_item() != null and p.active_item().skill_gem() != null
				and p.active_item().skill_gem().id == &"spark",
				"实际是 %s" % (p.active_item().gem.display_name if p.active_item() else "无"))
	# 老存档里没有的宝石要自动补齐。★ 按 id 验，不数 items 数量 ★ ——
	# 镶在槽里的电球术不占一件，数数量是恒错的
	var missing := PackedStringArray()
	for thing in GemSave.everything():
		if not p.grid.has_gem(thing.id):
			missing.append(String(thing.id))
	# ★ 图鉴（48 件 = 59 格）已经比背包（56 格）大了（ADR-030）★ —— 补不全是数学上注定的，
	#   规则改成"补到真的塞不下为止"：要么一件不少，要么连一颗 1×1 都放不进去了。
	#   探针放在副本上，别把玩家的网格弄脏。
	var probe := GemGrid.new()
	probe.from_data(p.grid.to_data(), GemSave.resolve)
	var truly_full := probe.place_anywhere(GemLibrary.gem_spark()) == null
	_check("图鉴里的宝石和装备补到背包真的塞满为止（缺的都是塞不下的）",
			missing.is_empty() or truly_full,
			"缺：%s（1×1 还放得下：%s）" % [", ".join(missing), str(not truly_full)])
	# 大件先放 → 缺的只能是 1×1 的宝石，不该有装备被挤出去
	var missing_big := PackedStringArray()
	for id in missing:
		var thing = GemSave.resolve(StringName(id))
		if thing is EquipItem and ((thing as EquipItem).width * (thing as EquipItem).height) > 1:
			missing_big.append(id)
	_check("缺的全是 1×1 宝石（大件先放，装备一件不少）", missing_big.is_empty(), "缺的大件：" + ", ".join(missing_big))
	_check("★ 补齐时不会再塞一颗重复的电球术 ★（has_gem 认得槽里的）",
			_count_id(p.grid, &"spark") == 1, "实际 %d 颗" % _count_id(p.grid, &"spark"))

	# 版本号对不上的存档要被拒掉（而不是读出一堆垃圾）
	var f := FileAccess.open(GemSave.path, FileAccess.WRITE)
	f.store_string('{"version": 999, "items": []}')
	f.close()
	_check("旧版本存档会被拒绝（退回默认摆法）", not GemSave.load_into(p))

	# 文件内容坏掉也不能炸
	f = FileAccess.open(GemSave.path, FileAccess.WRITE)
	f.store_string("这不是 JSON {{{")
	f.close()
	_check("存档文件坏了也不炸", not GemSave.load_into(p))

	# 收尾：删掉测试存档，把开关和路径还原，别影响玩家
	GemSave.clear()
	_check("清档之后就没有存档了", not GemSave.has_save())
	GemSave.autosave = false
	GemSave.path = real_path


## 把背包重新摆一遍：中间放一根法杖、槽里镶上指定的技能宝石，
## 左边放一颗辅助、箭头朝右指进法杖。sup_id 传 "" 就不连任何辅助。
##
## ★ 这就是新背包的用法（ADR-020）★ 技能宝石必须镶进法杖；箭头指着法杖生效。
## 用见习法杖（没有词缀）——测的是行为链路，别让法杖词缀掺进数值。
## 近战版：铁剑里镶一颗攻击技能（走真实的镶嵌规则，不是直接塞 socketed）
func _rebuild_melee_grid(skill_id: StringName) -> void:
	var p: Player = _world.player
	p.grid = GemGrid.new()
	var sword := EquipLibrary.iron_sword()
	var sp := p.grid.place(sword, Vector2i(3, 2), 0)
	var gem: SkillGem = GemLibrary.make_gem(skill_id)
	_check("铁剑收下「%s」（镶嵌规则放行）" % gem.display_name, p.grid.socket_reject_reason(gem, Vector2i(3, 2)) == "")
	p.grid.socket(gem, sp)
	p.set_skill(0)


func _rebuild_grid(skill_id: StringName, sup_id: StringName) -> void:
	var p: Player = _world.player
	p.grid = GemGrid.new()

	var wand := EquipLibrary.apprentice_wand()
	for g in GemLibrary.all_actives():
		if (g as SkillGem).id == skill_id:
			wand.socketed = g
	p.grid.place(wand, Vector2i(3, 2), 0)           # 占 (3,2)-(3,3)
	if sup_id != &"":
		for s in GemLibrary.all_supports():
			if (s as SupportGem).id == sup_id:
				p.grid.place(s, Vector2i(2, 2), 0)  # 箭头 → 指进法杖的 (3,2)
	p.set_skill(0)


## 往主视口丢一个鼠标移动事件（视口坐标）。
## 走的是完整的一条链路：主视口 → SubViewportContainer → SubViewport → 玩家。
func _send_mouse_to(viewport_pos: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = viewport_pos
	mm.global_position = viewport_pos
	Input.parse_input_event(mm)


## 场上现在有几发投射物
## 场上活着的范围特效节点（新星冲击波 / 风暴呼唤预警圈）
func _count_bursts() -> int:
	var n := 0
	for c in _world.fx.get_children():
		if c is AreaBurst and not c.is_queued_for_deletion():
			n += 1
	return n


func _count_projectiles() -> int:
	var n := 0
	for c in _world.entities.get_children():
		if c is Projectile:
			n += 1
	return n


func _spec_text() -> String:
	var p := _world.player
	if p.skill == null:
		return "（背包里没有主动技能石）"
	return "%s | %s" % [p.skill.display_name,
			ProjectileSpec.build(p.stats, p.skill).describe()]


## 这颗 id 的宝石在网格里出现了几次（裸放的 + 镶在法杖槽里的）
func _count_id(grid: GemGrid, id: StringName) -> int:
	var n := 0
	for it in grid.items:
		var pl := it as GemGrid.Placed
		if pl.gem.id == id:
			n += 1
		if pl.skill_gem() != null and pl.skill_gem().id == id:
			n += 1
	return n


## 当前技能上现在连着这颗辅助宝石吗（箭头指着它、标签也对得上）
func _support_linked(id: StringName) -> bool:
	for s in _world.player.active_link().supports:
		if (s as SupportGem).id == id:
			return true
	return false


func _nearest_enemy() -> Enemy:
	var best: Enemy = null
	var best_d := INF
	for n in root.get_tree().get_nodes_in_group(&"enemy"):
		if not is_instance_valid(n):
			continue
		var e := n as Enemy
		if e == null or e.stats == null or not e.stats.is_alive():
			continue
		var d := e.global_position.distance_squared_to(_world.player.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("   PASS  ", name)
	else:
		_failed += 1
		print("   FAIL  ", name, "   ", detail)


func _fail(msg: String) -> void:
	_failed += 1
	print("   FAIL  ", msg)


# ================================================================ 第八段：局模式
#
# 真实场景里跑一遍局流程的头两步：
#   开新局（孤石背包 + 地图面板）→ 选战斗房 → 刷出整波怪 → 全杀
#   → 弹奖励三选一 → 领第一个 → 回到地图、步数 +1
# 完整的 7 步状态机在 run_tests.gd 里已经单测过，这里只验"接进游戏后真的能转"。

func _start_run_phase() -> void:
	print("\n[第八段] 局模式：孤石开局 → 选房 → 清房 → 三选一 → 回地图")
	_legacy_done = true
	_world.queue_free()
	# ★ 开一局全新的、种子固定的局 ★ autosave 已关、path 已指向测试文件，
	#   再把可能存在的测试残档清掉，保证每次跑到的都是同一局
	RunSession.enabled = true
	RunSession.force_seed = RUN_SEED
	RunSession.clear_save()
	var packed: PackedScene = load("res://main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	_run_world = scene as GameWorld
	_run_base = -1
	_run_stage = 0


func _run_process() -> bool:
	if _run_base < 0:
		_run_base = int(Engine.get_physics_frames())
	var now := int(Engine.get_physics_frames()) - _run_base

	match _run_stage:
		0:
			# 场景 _ready 完之后：验开局状态，然后选进第一个房间
			if now >= 4:
				_run_stage = 1
				var p := _run_world.player
				_check("★ 开局背包只有一件东西 ★（不是沙盒的全家桶）",
						p.grid.items.size() == 1, "实际 %d 件" % p.grid.items.size())
				if p.grid.items.size() >= 1:
					var first := p.grid.items[0] as GemGrid.Placed
					_check("★ 那一件是开局法杖（技能的载体）★",
							first.gem.id == RunContent.STARTING_WAND, str(first.gem.id))
					_check("★ 槽里镶着开局技能石，直接能打 ★",
							first.skill_gem() != null
							and first.skill_gem().id == RunContent.STARTING_GEM
							and p.skill != null)
				_check("开局弹出了地图选房面板", _run_world.run_ui.is_open())
				_check("状态机在选房阶段", RunSession.state.phase == RunState.Phase.CHOOSE)
				_check("★ 开局在第 1 层 ★（一局共 %d 层）" % RunMap.FLOORS,
						RunSession.state.floor_index == 0)
				_check("用的是测试指定的种子", RunSession.state.seed_value == RUN_SEED)
				# 第 1 层第 1 步：总数 == 同时在场上限，一波全放（波次逻辑在第九段专测）
				_expected_enemies = mini(RunContent.enemies_for_step(0, 0),
						RunContent.max_alive_for_step(0, 0))
				# 第 1 步全是战斗房（商店最早出现在第 3 步），选第 0 个
				_run_world._on_room_chosen(0)
		1:
			if now >= 10:
				_run_stage = 2
				var alive := root.get_tree().get_nodes_in_group(&"enemy").size()
				_check("选房后刷出了这一步应有的一整波怪", alive == _expected_enemies,
						"应刷 %d 只，场上 %d 只" % [_expected_enemies, alive])
				_check("进房后地图面板收起来了", not _run_world.run_ui.is_open())
				# 秒杀全场 → 下一物理帧它们的 _physics_process 会走 _die()
				for n in root.get_tree().get_nodes_in_group(&"enemy"):
					(n as Enemy).stats.take_damage(9.0e9)
		2:
			if now >= 20:
				_run_stage = 3
				_check("★ 清房后弹出奖励三选一 ★", _run_world.run_ui.is_open())
				_check("状态机在奖励阶段", RunSession.state.phase == RunState.Phase.REWARD)
				# 金币不再是奖励房型：清完第一个房，钱应该已经自动进账了
				_check("★ 清房自动进账金币 ★", RunSession.state.gold > 0,
						"金币 %d" % RunSession.state.gold)
				# 候选是种子定的 → 用和 World 一模一样的方式重掷，拿到同一批。
				# ★ owned 用 owned_gems()：镶在法杖槽里的开局宝石也算"拥有" ★
				var st := RunSession.state
				var room := st.current_room()
				var options := RunRewards.roll_options(room.reward, st.rng_for("reward"),
						RunContent.reward_pools(_run_world.player.grid.owned_gems()))
				_check("三选一有候选可领", not options.is_empty())
				if options.is_empty():
					_finish_all()
					return true
				_reward_taken = options[0]
				_grid_before = _run_world.player.grid.items.size()
				_gold_before = st.gold
				if _reward_taken.has("gem"):
					_level_before = _reward_taken["gem"].level
				_run_world._on_reward_chosen(_reward_taken)
		3:
			if now >= 26:
				var st := RunSession.state
				_check("★ 领完奖走到第 2 步、回到选房 ★",
						st.step == 1 and st.phase == RunState.Phase.CHOOSE,
						"step=%d phase=%d" % [st.step, st.phase])
				_check("地图面板重新打开", _run_world.run_ui.is_open())
				_check("★ 奖励真的到账了 ★", _reward_applied(),
						"领的是 %s" % str(_reward_taken.get("label", "?")))
				# 商店界面走一遍渲染（买卖规则在单元测试里已覆盖）
				_run_world.run_ui.show_shop(st,
						RunContent.shop_stock(st.rng_for("shop")), [])
				_check("商店界面能打开", _run_world.run_ui.is_open())

				# ---- ★ R 重开 = 放弃整局，不是重打当前房间 ★（world 的 R 键走 abandon）----
				# 此刻打到第 2 步、身上有金币。先落一次盘证明"有档可续"，
				# 再走 abandon → prepare：必须是全新的一局，而不是续档回到第 2 步。
				RunSession.autosave = true
				RunSession.save(_run_world.player)
				RunSession.autosave = false
				_check("放弃前局存档在（不删档的话重载会续档）",
						FileAccess.file_exists(RunSession.path))
				RunSession.abandon()
				_check("★ 放弃后局存档被删掉 ★", not FileAccess.file_exists(RunSession.path))
				RunSession.prepare()
				_check("★ 重开后是全新的一局：第 1 层第 1 步、金币归零 ★",
						RunSession.state.floor_index == 0 and RunSession.state.step == 0
						and RunSession.state.gold == 0,
						"floor=%d step=%d gold=%d" % [RunSession.state.floor_index,
							RunSession.state.step, RunSession.state.gold])
				_start_boss_phase(now)
				_run_stage = 10
		# ---------- 第十段：守关 Boss 必掉血脉辅助（ADR-031）----------
		10:
			if now >= _boss_base + 6:
				_run_stage = 11
				var alive := _run_world.alive_enemies()
				_check("Boss 房：Boss + %d 只护卫一次到场" % RunContent.boss_escorts(0),
						alive == 1 + RunContent.boss_escorts(0), "场上 %d 只" % alive)
				_check("进 Boss 房前背包里没有血脉辅助", _lineage_owned() == 0)
				for n in root.get_tree().get_nodes_in_group(&"enemy"):
					(n as Enemy).stats.take_damage(9.0e9)
		11:
			if now >= _boss_base + 6 + 10:
				_run_stage = 4
				_check("守关 Boss 打赢 → 奖励面板", _run_world.run_ui.is_open()
						and RunSession.state.phase == RunState.Phase.REWARD)
				_check("★ Boss 必掉一颗血脉辅助，已进背包 ★", _lineage_owned() == 1, "背包里 %d 颗" % _lineage_owned())
				var st := RunSession.state
				var want := RunContent.boss_lineage([], st.rng_for("lineage"))
				_check("掉的正是种子定的那颗（读档重打刷不了）",
						want != null and _run_world.player.grid.has_gem(want.id))
				# 放弃三选一 → 领完奖走人 → 下一层
				_run_world._on_reward_skipped()
				_check("★ 守关 Boss 打完进第 2 层 ★", st.floor_index == 1 and st.step == 0,
						"floor=%d step=%d" % [st.floor_index, st.step])
				_start_wave_phase(now)
		# ---------- 第九段：波次刷怪 + 精英怪（ADR-028）----------
		4:
			# 第一波刚放出来：场上 = 同时在场上限，其余在队列里排队
			if now >= _wave_base + 4:
				_run_stage = 5
				var alive := _run_world.alive_enemies()
				_check("★ 深层房间第一波只放到上限，不是一口气全放 ★（16 只里先上 %d 只）" % _wave_cap,
						alive == _wave_cap and _wave_cap < _wave_total,
						"场上 %d / 上限 %d / 总数 %d" % [alive, _wave_cap, _wave_total])
				_check("剩下的在队列里等", _run_world.room_enemies_left == _wave_total)
				_check("第一波全是普通怪（精英压轴，还没上场）", _count_elites() == 0,
						"精英 %d 只" % _count_elites())
				_wave_first_ids = _enemy_ids()
				# 全杀 → 增援该顶上来（reinforce_delay 已设为 0，一帧补一只）
				for n in root.get_tree().get_nodes_in_group(&"enemy"):
					(n as Enemy).stats.take_damage(9.0e9)
		5:
			# 等增援补满：第一波 8 只死光后，队列里的 8 只要一只只顶上来
			if now >= _wave_base + 4 + 16:
				_run_stage = 6
				var alive := _run_world.alive_enemies()
				_check("★ 死一只补一只：增援把场上重新补到上限 ★", alive == _wave_cap,
						"场上 %d / 上限 %d" % [alive, _wave_cap])
				_check("队列放空了（16 只全上过场）", _run_world.room_enemies_left == _wave_total - _wave_cap)
				var reused := false
				for id in _enemy_ids():
					if _wave_first_ids.has(id):
						reused = true
				_check("增援是新刷出来的怪，不是第一波的尸体", not reused)
				_check("房间没被误判为清空（还有一半怪没死）", not _run_world.run_ui.is_open()
						and RunSession.state.phase == RunState.Phase.ROOM)
				# 精英压轴：第二波里应该出现 elites_for_step 只精英，且长得像精英
				var elites := _count_elites()
				_check("★ 第二波里有 %d 只精英 ★" % _wave_elites, elites == _wave_elites,
						"实际 %d 只" % elites)
				var e := _first_elite()
				if e != null:
					_check("精英头顶挂了词条名标签", e._title != null and e._title.text != ""
							and e._title.text == e.stats.affix_title(),
							"标签 " + (e._title.text if e._title != null else "<无>"))
					_check("精英体型比普通怪大", e.scale.x > 1.0, "scale %.2f" % e.scale.x)
					_check("精英是金色调（没在闪白时）", e.sprite.modulate.is_equal_approx(Enemy.ELITE_TINT)
							or e._base_tint.is_equal_approx(Enemy.ELITE_TINT))
					_check("精英名字带词条", e.stats.display_name.begins_with(e.stats.affix_title()))
					_check("第 4 层精英挂 2 条词条", e.stats.affixes.size() == 2)
					print("精英样本：%s（生命 %.0f）" % [e.stats.display_name, e.stats.max_life()])
				for n in root.get_tree().get_nodes_in_group(&"enemy"):
					(n as Enemy).stats.take_damage(9.0e9)
		6:
			if now >= _wave_base + 4 + 16 + 10:
				_run_stage = 7
				_check("★ 16 只全清才算清房：弹出奖励面板 ★", _run_world.run_ui.is_open()
						and RunSession.state.phase == RunState.Phase.REWARD
						and _run_world.room_enemies_left == 0,
						"phase=%d left=%d" % [RunSession.state.phase, _run_world.room_enemies_left])
				# ---- 爪类词条：精英近战给玩家挂 DoT，DoT 能把玩家烧死并正确触发死亡 ----
				# 以前没有怪能给玩家上 DoT，"被 DoT 打死" 这条路从没走过（血归零不发 died）
				var pl := _run_world.player
				pl.stats.life = 5.0
				_saw_debuff = false
				pl.debuffed.connect(func(_n: String) -> void: _saw_debuff = true)
				pl.receive_buff(Demo.buff_scorching_claw(), RunContent.make_elite_from(Demo.make_monster(), 0, _run_world._rng))
				_check("挂上减益时发了 debuffed 信号（World 靠它飘字）", _saw_debuff)
				_check("玩家身上有【灼热】", pl.stats.buffs.has(&"scorching_claw"))
		7:
			# 灼热每 0.5 秒一跳 = 30 物理帧；5 点血一跳必死
			if now >= _wave_base + 4 + 16 + 10 + 40:
				var pl := _run_world.player
				_check("★ DoT 把玩家烧死了，而且 World 收到了 died（死亡大字亮了）★",
						not pl.stats.is_alive() and _run_world.hud._center_msg.visible,
						"life=%.1f msg=%s" % [pl.stats.life, str(_run_world.hud._center_msg.visible)])
				_check("阵亡 = 整局结束（局存档被删）", not FileAccess.file_exists(RunSession.path))
				_finish_all()
				return true
	return false


# ---- 第十段：Boss + 血脉 ----
var _boss_base := 0


## 把这一局拨到第 1 层最后一步（守关 Boss 房），像玩家一样点进去
func _start_boss_phase(now: int) -> void:
	print("\n[第十段] 守关 Boss 必掉血脉辅助")
	var st := RunSession.state
	st.step = RunMap.STEPS - 1
	_check("最后一步是 Boss 房", (st.rooms()[0] as RunMap.Room).type == RunMap.RoomType.BOSS)
	_run_world._on_room_chosen(0)
	_boss_base = now


## 背包里有几颗血脉辅助
func _lineage_owned() -> int:
	var n := 0
	for g in GemLibrary.all_lineage():
		if _run_world.player.grid.has_gem((g as SupportGem).id):
			n += 1
	return n


# ---- 第九段：波次 + 精英 ----
var _wave_base := 0
var _wave_total := 0
var _wave_cap := 0
var _wave_elites := 0
var _wave_first_ids: Array = []
var _saw_debuff := false


## 把这一局直接拨到第 4 层第 6 步（最深的普通房），开一间战斗房。
## reinforce_delay 设 0：队列一帧放一只，不然 8 只增援要等 7 秒多。
func _start_wave_phase(now: int) -> void:
	print("\n[第九段] 波次刷怪 + 精英怪：第 4 层第 6 步的战斗房")
	# ★ 走真实的选房链路 ★：先把局拨到第 4 层（会按层种子生成那层的图）、第 6 步，
	#   再像玩家一样点进那一步的一个战斗房 —— _on_room_chosen 会收面板、配名单、放第一波
	var st := RunSession.state
	st._enter_floor(RunMap.FLOORS - 1)
	st.step = RunMap.STEPS - 2
	var idx := -1
	for i in st.rooms().size():
		if (st.rooms()[i] as RunMap.Room).type == RunMap.RoomType.COMBAT:
			idx = i
			break
	_check("第 4 层第 6 步有战斗房可选", idx >= 0)
	_wave_total = RunContent.enemies_for_step(st.step, st.floor_index)
	_wave_cap = RunContent.max_alive_for_step(st.step, st.floor_index)
	_wave_elites = RunContent.elites_for_step(st.step, st.floor_index)
	_run_world.reinforce_delay = 0.0
	_run_world._on_room_chosen(idx)
	_wave_base = now


func _count_elites() -> int:
	var n := 0
	for node in root.get_tree().get_nodes_in_group(&"enemy"):
		var e := node as Enemy
		if e != null and e.stats != null and e.stats.is_alive() and e.stats.is_elite():
			n += 1
	return n


func _first_elite() -> Enemy:
	for node in root.get_tree().get_nodes_in_group(&"enemy"):
		var e := node as Enemy
		if e != null and e.stats != null and e.stats.is_alive() and e.stats.is_elite():
			return e
	return null


func _enemy_ids() -> Array:
	var out: Array = []
	for node in root.get_tree().get_nodes_in_group(&"enemy"):
		var e := node as Enemy
		if e != null and e.stats != null and e.stats.is_alive():
			out.append(e.get_instance_id())
	return out


## 领的奖励落没落地，按类型各查各的
func _reward_applied() -> bool:
	match int(_reward_taken.get("kind", -1)):
		RunMap.RewardKind.UPGRADE:
			return _reward_taken["gem"].level == _level_before + 1
		_:
			return _run_world.player.grid.items.size() == _grid_before + 1


func _finish_all() -> void:
	RunSession.clear_save()
	print("\n===================================")
	if _failed == 0:
		print("冒烟测试全部通过")
	else:
		print("失败 %d 项" % _failed)
	print("===================================\n")
	quit(0 if _failed == 0 else 1)
