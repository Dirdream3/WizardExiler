class_name Player
extends CharacterBody2D

## 玩家的**表现层**。
##
## ★ 注意这里是 `var stats: CombatEntity`，不是 `extends CombatEntity`。★
## 表现层"持有"数据模型，两者随时可以拆开：
##   · 战斗数值能脱离游戏跑单元测试
##   · 将来联机，同一份 CombatEntity 可以搬到服务器做验算
## 这个文件里不应该出现任何伤害公式，全部交给 DamagePipeline。

const Demo = preload("res://data/demo_content.gd")
const Gems = preload("res://data/gem_library.gd")
const Art = preload("res://game/pixel_art.gd")
const S = preload("res://combat/combat_stat.gd")
const T = preload("res://combat/combat_tags.gd")

## 玩家要施法：from = 发射点，dir = 朝向（单位向量），aim = 鼠标在世界里指的点
## （范围技能「指哪打哪」要用 aim；投射物只看 dir）
signal cast_requested(from: Vector2, dir: Vector2, aim: Vector2)
## 触媒触发了一次施法（World 负责选方向、生成投射物 / 画圈、飘字）。
## pspec / aspec 已经用**被触发那根法杖**的词缀算好了 —— World 直接用，别再 build 一遍。
## 投射物技能 pspec 非空、aspec 为 null；范围技能反过来（ADR-030）
signal catalyst_triggered(skill: SkillSpec, pspec: ProjectileSpec, aspec: AreaSpec, cat_name: String)
signal damaged(amount: float, is_crit: bool)
signal healed(amount: float)
## 身上被挂了一个减益（精英怪的爪类词条）。World 拿去飘字
signal debuffed(buff_name: String)
## 技能石 / 辅助宝石 / 等级有任何变化（背包 UI 和 HUD 靠它刷新）
signal gems_changed
signal died

## 魔力每秒回复的**基础值**。实际回复走属性系统（S.MANA_REGEN）——
## 装备上的「+N 魔力回复」「提高 N% 魔力回复」都能在这上面加成（照抄怪物追击速度的做法）。
const MANA_REGEN := 12.0

var stats: CombatEntity

## ★ 背包网格：所有宝石都住在这里面（背包乱斗那种）★
##   法杖是技能的载体：技能宝石镶进法杖槽才能施放；
##   辅助宝石的箭头指着哪根法杖，就辅助它槽里的技能 —— 「怎么摆」就是构筑。
var grid := GemGrid.new()

## 当前在用的是第几根"镶着宝石的法杖"（`grid.skill_items()` 里的下标，Q 键循环）
var skill_index := 0

## 读存档 / 重置的过程中把存盘关掉，免得拿一个半成品网格覆盖存档
var _suppress_save := false

## 当前这一格算出来的技能参数（HUD / World 都读这个）。
## 这是缓存值 —— 每次宝石有变动才重算，不要每帧 build()。
var skill: SkillSpec

## 鼠标在不在右边那块战斗画面里。★ 由 World 每帧告诉我们 ★
##   玩家住在战斗画面的 SubViewport 里，问不到"主窗口的鼠标在哪"，
##   所以不能自己判断；鼠标跑到左边面板上时这里会变成 false，就不施法了
##   —— 否则点一下宝石会顺手放一发。
var can_aim := true

var _cast_cd := 0.0
var _hit_flash := 0.0
## ★ 正在引导 ★（ADR-033）：按住引导技能、且上一段成功放出去了。引导中 Q 无效
var _channeling := false

## 触媒缓存：网格里所有「箭头连着某根法杖的触媒」。rebuild() 时重扫，
## 免得每帧去跑 supports_for。元素是 { "wand": GemGrid.Placed, "cat": CatalystGem }
var _catalysts: Array = []
## 上一物理帧的位置（疾行触媒按实际位移计数，撞墙蹭着走不算满速）
var _last_pos := Vector2.INF

@onready var sprite: Sprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow


func _ready() -> void:
	InputSetup.ensure()
	Art.char_setup(sprite, Art.player())
	shadow.texture = Art.shadow()

	stats = Demo.make_player()
	stats.apply_buff(Demo.buff_elemental_aura(0.25))   # 开局自带光环，方便看 Buff 生效
	_setup_gems()

	add_to_group(&"player")


## 开局：局模式问 RunSession 要背包（一颗孤石或局存档）；
## 沙盒模式走老路：有存档照存档摆，没有铺默认摆法。
func _setup_gems() -> void:
	# ★ 加载期间不许存盘 ★ 否则会拿一个还没填完的网格覆盖掉存档
	_suppress_save = true
	grid = GemGrid.new()
	if RunSession.enabled:
		# ★ 局模式不走 GemSave ★ —— 它会"把图鉴里缺的自动补进背包"，
		#   而局模式的全部意义就是从一颗孤石开始，什么都要靠打
		RunSession.setup_backpack(self)
	elif not GemSave.load_into(self):
		_default_layout()
	_suppress_save = false
	set_skill(skill_index)   # 会顺手 rebuild + 存一次盘（把格式规整一遍）


## 把背包恢复成出厂摆法（界面上的「重置背包」按钮）。
## 加了存档之后，摆乱了光靠重开是回不去的 —— 所以必须留一个后路。
## ★ 局模式下是禁用的 ★ —— 出厂摆法带全套装备，等于一键作弊。
func reset_backpack() -> void:
	if RunSession.enabled:
		return
	_suppress_save = true
	grid = GemGrid.new()
	_default_layout()
	skill_index = 0
	_suppress_save = false
	rebuild()


## 默认摆法。
##
## 故意摆成"橡木法杖里镶着电球术、三颗辅助的箭头指着法杖"——
## 这样第一次进游戏就能看懂两件事：宝石要镶进法杖、箭头指着法杖才生效。
func _default_layout() -> void:
	# 开局摆成这样（法杖 1×3 竖着，◈ 表示槽里镶着宝石）：
	#
	#   col   0     1    2    3    4    5    6    7
	#   row0  杖◈  ◀多   .    杖'   珀   戒   头   头
	#   row1  杖   ◀闪   .    杖'   .    .    头   头
	#   row2  杖   ◀久   .    .    .    .    靴   靴
	#   row3  .    .     带   带   带   .    靴   靴
	#   row4  弧   寒    冰   节   元   疾   缓   爆
	#   row5  穿   叉    弹   反   速   暴   霜   .
	#   row6  雷   炎    凝   连   行   钟   .    .   ← 触媒（紫色，条件触发）
	#
	# ★ 橡木法杖（杖）镶着电球术，三颗辅助从右侧一列箭头朝左指进法杖 ★
	# ★ 见习法杖（杖'）镶着火球术 —— Q 在两根法杖之间切换 ★
	# 法杖占 3 格 → 周身最多 8 个箭头位，比单格宝石天然的 4 连上限更高。
	var layout := {
		# 装备。法杖是技能载体；其它装备不用连箭头，放着就生效
		&"staff":            [Vector2i(0, 0), 0],
		&"apprentice_wand":  [Vector2i(3, 0), 0],
		&"sapphire_amulet":  [Vector2i(4, 0), 0],
		&"ring_of_flame":    [Vector2i(5, 0), 0],
		&"iron_helm":        [Vector2i(6, 0), 0],
		&"traveller_boots":  [Vector2i(6, 2), 0],
		&"arcane_belt":      [Vector2i(2, 3), 0],
		# 没镶进法杖的技能宝石只是库存（不能施放），排在 row4 等你换着玩
		&"arc":              [Vector2i(0, 4), 0],
		&"frostbolt":        [Vector2i(1, 4), 0],
		&"freezing_pulse":   [Vector2i(2, 4), 0],
		# 三颗辅助箭头朝左（rot2），各指进橡木法杖的一格
		&"sup_multi":        [Vector2i(1, 0), 2],   # ◀ 指到 (0,0)
		&"sup_lightning":    [Vector2i(1, 1), 2],   # ◀ 指到 (0,1)
		&"sup_duration":     [Vector2i(1, 2), 2],   # ◀ 指到 (0,2)
		# 剩下的排在最后几行，箭头都指着邻居（不是法杖 → 灰色），等你自己去摆
		&"sup_inspiration":  [Vector2i(3, 4), 0],
		&"sup_ele_focus":    [Vector2i(4, 4), 0],
		&"sup_fast_proj":    [Vector2i(5, 4), 0],
		&"sup_slow_proj":    [Vector2i(6, 4), 0],
		&"sup_crit_damage":  [Vector2i(7, 4), 0],
		&"sup_pierce":       [Vector2i(0, 5), 0],
		&"sup_fork":         [Vector2i(1, 5), 0],
		&"sup_chain":        [Vector2i(2, 5), 0],
		&"sup_bounce":       [Vector2i(3, 5), 0],
		&"sup_faster_cast":  [Vector2i(4, 5), 0],
		&"sup_crit":         [Vector2i(5, 5), 0],
		&"sup_cold":         [Vector2i(6, 5), 0],
		# 触媒（特殊辅助）：先摆成不指法杖的灰箭头，想用哪颗自己挪
		&"cat_shock":        [Vector2i(0, 6), 0],
		&"cat_ignite":       [Vector2i(1, 6), 0],
		&"cat_chill":        [Vector2i(2, 6), 0],
		&"cat_hits":         [Vector2i(3, 6), 0],
		&"cat_move":         [Vector2i(4, 6), 0],
		&"cat_timer":        [Vector2i(5, 6), 0],
	}
	# 哪颗宝石开局就镶在哪根法杖里（这两颗不进网格，它们住在法杖身上）
	var socket_plan := {
		&"staff": &"spark",
		&"apprentice_wand": &"fireball",
	}

	var everything: Array = []
	everything.append_array(EquipLibrary.all_items())
	everything.append_array(Gems.all_gems())
	for thing in everything:
		var id: StringName = thing.id
		if thing is EquipItem and socket_plan.has(id):
			var gem = Gems.make_gem(socket_plan[id])
			if gem != null:
				if gem.id == &"spark":
					(gem as SkillGem).level = 4   # 主打技能，给个能玩的等级（上限 5）
				(thing as EquipItem).socketed = gem
		elif thing is SkillGem and socket_plan.values().has(id):
			continue   # 已经镶进法杖了，别再往网格里放一颗重复的
		var placed: GemGrid.Placed = null
		if layout.has(id):
			placed = grid.place(thing, layout[id][0], layout[id][1])
		if placed == null:
			grid.place_anywhere(thing)   # 位置表写错了也不至于把东西弄丢

	skill_index = 0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"switch_skill"):
		# ★ 引导中不能切技能 ★（ADR-033）—— 松手再切
		if not _channeling:
			set_skill(skill_index + 1)
		get_viewport().set_input_as_handled()


## 现在正在引导吗（HUD 显示 / 测试用）
func is_channeling() -> bool:
	return _channeling


# ------------------------------------------------------------------ 宝石

## 当前在用的那根法杖（在网格里的那一件；技能宝石在它的槽里 skill_gem()）
func active_item() -> GemGrid.Placed:
	var skills := grid.skill_items()
	if skills.is_empty():
		return null
	return skills[posmod(skill_index, skills.size())]


## 当前技能 + 正在辅助它的宝石
func active_link() -> GemLink:
	return grid.link_for(active_item())


## ★ 宝石有任何变动都要调它 ★
##
## 做两件事：
##   ① 把当前法杖槽里的技能重新展开成 SkillSpec（等级变了、辅助变了都要重算）
##   ② 把「当前法杖自己的词缀 + 指着它的辅助宝石」整层换进 stats.skill_mods
##
## ②就是"法杖和辅助宝石都只对这根法杖里的技能生效"的实现（ADR-023）——
## Q 切法杖时整层直接换掉，不用一条条 remove_by_source，也不会串味。
func rebuild() -> void:
	var link := active_link()
	skill = link.skill()
	stats.skill_mods.clear()
	stats.skill_mods.add_all(link.mods())

	# ★ 普通装备：只要在背包里就生效，不用连箭头 ★ 和 skill_mods 一样整层重建。
	# 法杖不在这层 —— 它的词缀在上面的 link.mods() 里，只跟着自己槽里的技能走
	stats.equip_mods.clear()
	stats.equip_mods.add_all(grid.equip_mods())

	# ★ 触媒缓存也整套重扫 ★ —— 背包一变，谁连着谁就可能变了。
	#   注意扫的是**所有**镶着宝石的法杖，不只是当前那根：触媒的意义就是
	#   "副法杖挂条件自动打"，主手照常手动施法
	_catalysts.clear()
	for it in grid.skill_items():
		for s in grid.supports_for(it):
			var cg = (s as GemGrid.Placed).gem
			if cg is CatalystGem:
				_catalysts.append({"wand": it, "cat": cg})
	# 把头盔挪出去 → 生命上限掉下来 → 当前血不能还挂在旧上限上
	stats.life = minf(stats.life, stats.max_life())
	stats.mana = minf(stats.mana, stats.max_mana())

	gems_changed.emit()
	# 背包一有变动就存盘。文件很小（十几件宝石的 JSON），
	# 而且变动只在拿起/放下/升级/切技能时发生，不是每帧，所以随手存就行。
	# 局模式存进局存档（背包属于这一局），沙盒模式存老的 backpack.json。
	if not _suppress_save:
		if RunSession.enabled:
			RunSession.save(self)
		else:
			GemSave.save(self)


## 切到第 index 颗主动技能石（会自动绕回来，所以可以一直 +1）。
func set_skill(index: int) -> void:
	_channeling = false   # 换了技能，引导自然断掉
	var skills := grid.skill_items()
	if skills.is_empty():
		skill_index = 0
	else:
		skill_index = posmod(index, skills.size())
	rebuild()


## 把某一格上的宝石整件拿起来（连它的朝向一起）。拿不到返回 null。
func pick_up_at(cell: Vector2i) -> GemGrid.Placed:
	var p := grid.remove_at(cell)
	if p != null:
		# 拿走的可能正好是当前在用的那颗，下标要夹回去
		set_skill(skill_index)
	return p


## 往网格里放一件。放下了返回 ""，放不下返回原因。
## ★ 同款宝石叠放 = 合成升级 ★ 优先于普通的放置判定。
func place_gem(gem, origin: Vector2i, rot: int) -> String:
	var target := grid.merge_target(gem, origin)
	if target != null:
		grid.merge(gem, target)   # 手上那颗被吃掉，不再进网格
		rebuild()
		return ""
	var merge_why := grid.merge_reject_reason(gem, origin)
	if merge_why != "":
		return merge_why          # 同款但满级：说清原因，别报"那里已经有东西了"
	var why := grid.reject_reason(gem, origin, rot)
	if why != "":
		return why
	grid.place(gem, origin, rot)
	rebuild()
	return ""


## 把手上的技能宝石镶进一根法杖。规则在 GemGrid.socket()：
##   空槽 = 镶入；槽里同款 = 合成升级；槽里别的 = 交换。
## 返回被换出来的旧宝石（镶入/合成时是 null），调用方把它放回手上。
func socket_gem(gem: SkillGem, wand: GemGrid.Placed):
	var old = grid.socket(gem, wand)
	set_skill(skill_index)   # 多了一根能用的法杖，下标要重新夹；顺手 rebuild + 存盘
	return old


## 把一根法杖槽里的宝石取出来并返回（槽是空的返回 null）。
func unsocket_gem(wand: EquipItem) -> SkillGem:
	var gem := wand.socketed
	wand.socketed = null
	set_skill(skill_index)   # 少了一根能用的法杖，下标要重新夹；顺手 rebuild + 存盘
	return gem


## 升 / 降一颗宝石的等级（+1 / -1）。
## 主动石升级 = 点伤和魔力消耗一起涨；辅助石升级 = 它给的词缀数值涨。
func change_level(gem, delta: int) -> void:
	if gem == null:
		return
	gem.level = gem.clamp_level(gem.level + delta)
	rebuild()


## 当前技能这一发的投射物参数（HUD / Tab 面板显示用）。范围技能返回 null —— 它没有弹
func projectile_spec() -> ProjectileSpec:
	if skill == null or not skill.is_projectile():
		return null
	return ProjectileSpec.build(stats, skill)


## 当前技能的范围参数（范围技能才有，其它返回 null）
func area_spec() -> AreaSpec:
	if skill == null or not skill.is_area():
		return null
	return AreaSpec.build(stats, skill)


func _physics_process(delta: float) -> void:
	# 一行推进所有 Buff 计时 + DoT 结算。
	# ★ DoT 也能把玩家烧死 ★（精英怪的「灼热之爪」）—— 以前没有怪能给玩家上 DoT，
	#   这里从没处理过"被 DoT 打死"：血归零了却不发 died，World 永远不知道你死了。
	var was_alive := stats.is_alive()
	for ev in DamagePipeline.resolve_dots(stats, delta):
		damaged.emit(ev["damage"], false)
	if was_alive and not stats.is_alive():
		died.emit()
	if not stats.is_alive():
		return

	# --- 移动 ---
	var dir := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = dir * stats.get_stat(S.MOVE_SPEED)
	move_and_slide()
	if not is_zero_approx(dir.x):
		sprite.flip_h = dir.x < 0.0

	# --- 资源与冷却 ---
	_cast_cd = maxf(0.0, _cast_cd - delta)
	stats.mana = minf(stats.max_mana(),
			stats.mana + stats.get_stat(S.MANA_REGEN, T.NONE, MANA_REGEN) * delta)

	# --- 施法 ---
	# 引导技能和普通技能走同一条路：按住 → 冷却到了就再放一段。区别只在"引导状态"：
	#   按住且上一段放出去了 = 正在引导（Q 被封）；松手 / 蓝不够放不出 = 引导结束
	var holding := Input.is_action_pressed(&"cast") and can_aim
	if holding and _cast_cd <= 0.0:
		var fired := _try_cast()
		if skill != null and skill.is_channel():
			_channeling = fired    # 蓝不够 → 这一段没放出去 → 引导中断
	if not holding or skill == null or not skill.is_channel():
		_channeling = false

	# --- 触媒：移动 / 计时事件由自己产生，然后统一泵一遍触发 ---
	if _last_pos == Vector2.INF:
		_last_pos = global_position
	var moved := global_position.distance_to(_last_pos)
	_last_pos = global_position
	if moved > 0.01:
		notify_catalyst_event(CatalystGem.Trigger.MOVE_DISTANCE, moved)
	notify_catalyst_event(CatalystGem.Trigger.INTERVAL, delta)
	_pump_catalysts()

	# --- 受击闪白 ---
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
		sprite.modulate = Color(1, 1, 1).lerp(Color(2.5, 1.2, 1.2), _hit_flash / 0.12)


## 放一次（引导技能 = 放一段）。返回 true = 真的放出去了；false = 没技能 / 蓝不够
func _try_cast() -> bool:
	if skill == null or stats.mana < skill.mana_cost:
		return false
	var dir := get_global_mouse_position() - global_position
	if dir.length_squared() < 1.0:
		dir = Vector2.RIGHT
	dir = dir.normalized()

	stats.mana -= skill.mana_cost
	# ★ 引导蓄力（ADR-036，焚烧）★ 每放一段给自己叠一层；松手后 Buff 自己过期，蓄力归零
	if skill.channel_ramp != null:
		stats.apply_buff(skill.channel_ramp)
	# ★ 施法间隔 = 技能石上的「施放时间」÷ 施法速度倍率 ★
	#   电球术 0.65 秒 ÷ 施法速度 1.25 = 0.52 秒一发。
	#   装备/辅助宝石上的「提高施法速度」会自动缩短它，不用改任何代码。
	#   ★ 攻击技能走「攻击速度」（ADR-032）★ 武器上的攻速词缀在这里生效，施法速度对它无效
	var speed_stat := S.ATTACK_SPEED if skill.is_attack() else S.CAST_SPEED
	var speed := maxf(0.1, stats.get_stat(speed_stat, skill.hit_tags()))
	_cast_cd = maxf(0.05, skill.cast_time / speed)

	sprite.flip_h = dir.x < 0.0
	cast_requested.emit(global_position + Vector2(0, -7), dir, get_global_mouse_position())
	return true


# ------------------------------------------------------------------ 触媒

## 网格里有没有连着法杖的触媒（GemGridView 靠它决定要不要为进度条定期重画）
func has_catalysts() -> bool:
	return not _catalysts.is_empty()


## 场上发生了触媒关心的事件（击中 / 施加异常由 World 喂进来；移动 / 计时自己产）。
## ★ 这里只涨进度 ★ 真正的触发尝试在 _pump_catalysts（每物理帧一次）——
## 这样"到门槛但蓝不够"的触媒在回蓝之后也能自动补上，不用等下一个事件。
func notify_catalyst_event(kind: int, amount: float = 1.0) -> void:
	for c in _catalysts:
		(c["cat"] as CatalystGem).advance(kind, amount)


## 把进度到门槛的触媒挨个尝试触发。成功才清进度（蓝不够就留着，回头再试）。
func _pump_catalysts() -> void:
	for c in _catalysts:
		var cat := c["cat"] as CatalystGem
		if not cat.ready_to_fire():
			continue
		if _try_trigger(c["wand"] as GemGrid.Placed, cat):
			cat.consume()


## 触发一次：无施法动作（不占 _cast_cd、不转身），但正常扣蓝。
## 返回 false = 这次没触发成（蓝不够 / 法杖空了）。
func _try_trigger(wand: GemGrid.Placed, cat: CatalystGem) -> bool:
	var link := grid.link_for(wand)
	var tskill := link.skill()
	if tskill == null:
		return false
	if stats.mana < tskill.mana_cost:
		return false   # ★ 蓝不够不触发 ★ 进度保持在门槛上
	stats.mana -= tskill.mana_cost

	# ★ 被触发的可能不是当前法杖 ★ 投射物参数得用**它那套**词缀
	# （法杖自己的 + 指着它的辅助）算，算完立刻把 skill_mods 换回当前法杖的。
	# 投射物飞行途中命中时用的仍是"彼时的当前词缀"——和手动切技能同一个已知误差。
	stats.skill_mods.clear()
	stats.skill_mods.add_all(link.mods())
	var pspec: ProjectileSpec = ProjectileSpec.build(stats, tskill) if tskill.is_projectile() else null
	var aspec: AreaSpec = AreaSpec.build(stats, tskill) if tskill.is_area() else null
	stats.skill_mods.clear()
	stats.skill_mods.add_all(active_link().mods())

	catalyst_triggered.emit(tskill, pspec, aspec, cat.display_name)
	return true


## 被怪挂了一个减益（精英怪的爪类词条）。规则全在 CombatEntity.apply_buff，
## 这里只多发一个信号让 World 飘字 —— 不然只看到血在掉 / 人变慢，不知道为什么。
func receive_buff(def: BuffDef, from: CombatEntity = null) -> void:
	if not stats.is_alive():
		return
	stats.apply_buff(def, from)
	debuffed.emit(def.display_name)


## 挨打。伤害已经由 DamagePipeline 算好了，这里只负责扣血和表现。
func take_hit(result: HitResult) -> void:
	if not stats.is_alive():
		return
	stats.take_damage(result.total)
	_hit_flash = 0.12
	damaged.emit(result.total, result.is_crit)
	if not stats.is_alive():
		died.emit()


func on_kill_reward() -> void:
	# 击杀奖励：上一层狂怒（REFRESH 规则，重复击杀只续时间）
	stats.apply_buff(Demo.buff_frenzy())
	var before := stats.life
	stats.heal(40.0)
	healed.emit(stats.life - before)
