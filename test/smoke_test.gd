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

const SETUP_AT := 2        # 物理帧。此时场景已经 _ready 完
const PICK_AT := 20
const FIRE_AT := 30
const FIRE_EVERY := 70
const PHASE_B_AT := 280    # 切换到「分叉支援」
const PHASE_C_AT := 420    # 切换到「电球术」，看散射 / 乱窜 / 撞墙反弹
const PHASE_D_AT := 560    # 用**真实按键**施法一次
const CAST_FRAMES := 60    # 按住施法键多久
const PHASE_E_AT := 660    # 用**真实按键**切技能
const CHECK_AT := 760

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
var _next_fire := FIRE_AT
var _failed := 0


func _initialize() -> void:
	print("\n=========== 集成冒烟测试 ===========\n")
	# ★ 必须在场景 _ready 之前关掉存盘 ★
	#   测试会把背包摆得乱七八糟，存下去就把玩家真正的背包覆盖了。
	GemSave.autosave = false
	var packed: PackedScene = load("res://main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	_world = scene as GameWorld
	# 注意：此刻场景还没 _ready，_world.player 还是 null，
	# 装宝石那些事要等到 SETUP_AT 那一帧再做。


func _process(_delta: float) -> bool:
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
		# 网格里得有两颗主动技能石，Q 才有得切（只有一颗时 posmod(1,1)=0，切了等于没切）
		if _world.player.grid.skill_items().size() < 2:
			_world.player.grid.place_anywhere(GemLibrary.gem_fireball())
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

	if now >= CHECK_AT:
		_report()
		return true
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

	# 电球术：4 发扇形乱窜，2.4 秒内必然有几发撞到场地边缘并弹回来
	var bounces := int(total.get("bounce", 0)) - int(_fork_counts.get("bounce", 0))
	_check("切到电球术后，投射物撞墙反弹了", bounces > 0, "本段反弹 %d 次" % bounces)
	_check("电球术命中并挂上了【感电】", _saw_shock)

	# 全程都没连穿透支援，所以一次穿透都不该发生。
	# （加个前置判断：带窗口跑的时候有可能被真实按键改了宝石配置）
	if not _support_linked(&"sup_pierce"):
		_check("没连穿透支援 → 一次穿透都没发生", int(total["pierce"]) == 0)

	_check_inventory_ui()

	print("\n===================================")
	if _failed == 0:
		print("冒烟测试全部通过")
	else:
		print("失败 %d 项" % _failed)
	print("===================================\n")
	quit(0 if _failed == 0 else 1)


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

	# 摆一个干净的局面：电球术在 (3,2)，延长持续在 (1,4) 谁也没指着
	p.grid = GemGrid.new()
	var spark: SkillGem = GemLibrary.gem_spark()
	var dur: SupportGem = GemLibrary.support_duration()
	p.grid.place(spark, Vector2i(3, 2), 0)
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

	# --- 放到技能石左边、箭头朝右 → 应该连上 ---
	inv._grid_view._hover = Vector2i(2, 2)     # 模拟鼠标悬停在 (2,2)，技能石左边
	inv._on_cell_pressed(Vector2i(2, 2))
	_check("放下了（手上空了）", inv._held == null, inv._notice)
	var sk: GemGrid.Placed = p.grid.skill_items()[0]
	_check("★ 箭头指进技能石 → 连上了 ★", p.grid.supports_for(sk).size() == 1)
	_check("★ 魔力消耗变贵了（辅助宝石的倍率）★", p.skill.mana_cost > cost_before,
			"%.1f → %.1f" % [cost_before, p.skill.mana_cost])
	_check("★ 电球术的投射物持续时间变长了 ★",
			ProjectileSpec.build(p.stats, p.skill).duration > dur_before,
			"%.2fs → %.2fs" % [dur_before, ProjectileSpec.build(p.stats, p.skill).duration])

	# --- 放到别人身上要被拒绝，而且宝石不能凭空消失 ---
	inv._on_cell_pressed(Vector2i(2, 2))       # 再拿起来
	inv._grid_view._hover = Vector2i(3, 2)     # 压在技能石身上
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

	# --- 标签不匹配：箭头指到了，但连不上，而且界面要说得清楚 ---
	p.grid = GemGrid.new()
	p.grid.place(GemLibrary.gem_fireball(), Vector2i(3, 2), 0)   # 没有【持续时间】标签
	var dur2: SupportGem = GemLibrary.support_duration()
	var placed := p.grid.place(dur2, Vector2i(2, 2), 0)          # 箭头指进火球术
	p.set_skill(0)
	_check("★ 火球术没有【持续时间】标签 → 箭头是红的 ★",
			p.grid.arrow_state(placed) == "blocked", p.grid.arrow_state(placed))
	_check("所以它不算辅助", p.grid.supports_for(p.grid.skill_items()[0]).is_empty())
	inv._detail = dur2
	_check("详情面板会写明连不上的原因", inv._detail_bbcode().contains("连不上"))

	# --- 面板文本能生成（格式化字符串写错只有跑到才炸）---
	inv._detail = p.grid.skill_items()[0].gem
	_check("主动技能石的详情文本正常", inv._detail_bbcode().length() > 0)
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

	# 摆一个认得出来的局面：电球术 15 级，一颗辅助从右边朝左连上
	p.grid = GemGrid.new()
	var spark: SkillGem = GemLibrary.gem_spark()
	spark.level = 15
	p.grid.place(spark, Vector2i(3, 1), 0)
	p.grid.place(GemLibrary.support_duration(), Vector2i(4, 1), 2)
	p.set_skill(0)

	_check("存盘成功", GemSave.save(p))
	_check("存档文件真的生成了", GemSave.has_save())

	# 把背包砸烂，再从存档读回来
	p.grid = GemGrid.new()
	p.skill_index = 0
	_check("★ 读档成功 ★", GemSave.load_into(p))

	# 按 id 找回那颗电球术（不能按下标找：读档时会把图鉴里缺的宝石补进来，
	# 而 skill_items() 是按摆放位置排序的，下标会变）
	var sk: GemGrid.Placed = null
	for it in p.grid.items:
		if (it as GemGrid.Placed).gem.id == &"spark":
			sk = it
	_check("电球术回来了", sk != null)
	if sk != null:
		_check("★ 等级记住了（15 级）★", (sk.gem as SkillGem).level == 15,
				"实际 %d 级" % (sk.gem as SkillGem).level)
		_check("★ 位置记住了 ★", sk.origin == Vector2i(3, 1), str(sk.origin))
		_check("★ 朝向记住了 → 箭头还连着 ★", p.grid.supports_for(sk).size() == 1,
				"实际连着 %d 颗" % p.grid.supports_for(sk).size())
		_check("★ 当前用的还是电球术（存的是 id 不是下标）★",
				p.active_item() != null and p.active_item().gem.id == &"spark",
				"实际是 %s" % (p.active_item().gem.display_name if p.active_item() else "无"))
	# 老存档里没有的宝石要自动补齐
	_check("图鉴里的宝石和装备一件不少", p.grid.items.size() == GemSave.everything().size(),
			"网格里 %d 件，图鉴 %d 件" % [p.grid.items.size(), GemSave.everything().size()])

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


## 把背包重新摆一遍：中间放一颗主动技能石，左边放一颗辅助、箭头朝右指进去。
## sup_id 传 "" 就只放技能石，不连任何辅助。
##
## ★ 这就是新背包的用法 ★ 没有 socket()，只有"摆在哪、朝哪边"。
func _rebuild_grid(skill_id: StringName, sup_id: StringName) -> void:
	var p: Player = _world.player
	p.grid = GemGrid.new()

	for g in GemLibrary.all_actives():
		if (g as SkillGem).id == skill_id:
			p.grid.place(g, Vector2i(3, 2), 0)      # 占 (3,2)-(4,3)
	if sup_id != &"":
		for s in GemLibrary.all_supports():
			if (s as SupportGem).id == sup_id:
				p.grid.place(s, Vector2i(2, 2), 0)  # 箭头 → 指进 (3,2)
	p.set_skill(0)


## 往主视口丢一个鼠标移动事件（视口坐标）。
## 走的是完整的一条链路：主视口 → SubViewportContainer → SubViewport → 玩家。
func _send_mouse_to(viewport_pos: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = viewport_pos
	mm.global_position = viewport_pos
	Input.parse_input_event(mm)


## 场上现在有几发投射物
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
