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

signal cast_requested(from: Vector2, dir: Vector2)
signal damaged(amount: float, is_crit: bool)
signal healed(amount: float)
## 技能石 / 辅助宝石 / 等级有任何变化（背包 UI 和 HUD 靠它刷新）
signal gems_changed
signal died

## 魔力每秒回复
const MANA_REGEN := 12.0

var stats: CombatEntity

## ★ 背包网格：所有宝石都住在这里面（背包乱斗那种）★
##   辅助宝石的箭头指进哪颗主动技能石，就辅助哪颗 —— 所以「怎么摆」就是构筑。
##   没有"技能栏"和"背包"之分，摆放位置本身就是一切。
var grid := GemGrid.new()

## 当前在用的是第几颗主动技能石（`grid.skill_items()` 里的下标，Q 键循环）
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

@onready var sprite: Sprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow


func _ready() -> void:
	InputSetup.ensure()
	sprite.texture = Art.player()
	shadow.texture = Art.shadow()

	stats = Demo.make_player()
	stats.apply_buff(Demo.buff_elemental_aura(0.25))   # 开局自带光环，方便看 Buff 生效
	_setup_gems()

	add_to_group(&"player")


## 开局：有存档就照存档摆，没有就铺默认摆法。
func _setup_gems() -> void:
	# ★ 加载期间不许存盘 ★ 否则会拿一个还没填完的网格覆盖掉存档
	_suppress_save = true
	grid = GemGrid.new()
	if not GemSave.load_into(self):
		_default_layout()
	_suppress_save = false
	set_skill(skill_index)   # 会顺手 rebuild + 存一次盘（把格式规整一遍）


## 把背包恢复成出厂摆法（界面上的「重置背包」按钮）。
## 加了存档之后，摆乱了光靠重开是回不去的 —— 所以必须留一个后路。
func reset_backpack() -> void:
	_suppress_save = true
	grid = GemGrid.new()
	_default_layout()
	skill_index = 0
	_suppress_save = false
	rebuild()


## 默认摆法。
##
## 故意摆成"电球术已经连了 3 颗辅助、剩下的堆在下面"——
## 这样第一次进游戏就能看到箭头是怎么连的，而不是面对一堆散件不知道从哪下手。
func _default_layout() -> void:
	# 开局摆成这样（宝石都是 1 格，装备占大块）：
	#
	#   col   0    1    2    3    4    5    6    7
	#   row0  杖   头   头   .    .    .    靴   靴
	#   row1  杖   头   头   .    .    .    靴   靴
	#   row2  杖   .    .    .    .    .    .    .
	#   row3  .    多▶  电  ◀久   .    .    戒   .
	#   row4  .    .    闪▲  .    .    .    .    .
	#   row5  火   .    .    .    .    .    .    .
	#   row6  穿   叉   弹   反   速   暴   .    .
	#
	# ★ 电球术被三个方向的箭头指着 ★ 一进游戏就能看懂"箭头 = 连接"这件事。
	# 技能石只占 1 格 → 四面最多 4 个箭头位，天然就是 PoE 的「4 连」。
	var layout := {
		# 装备（不用连箭头，放着就生效）
		&"staff":            [Vector2i(0, 0), 0],
		&"iron_helm":        [Vector2i(1, 0), 0],
		&"traveller_boots":  [Vector2i(6, 0), 0],
		&"ring_of_flame":    [Vector2i(6, 3), 0],
		# 主动技能石。★ skill_items() 按 y 再按 x 排序，靠上的那颗是开局的当前技能 ★
		&"spark":            [Vector2i(2, 3), 0],
		&"fireball":         [Vector2i(0, 5), 0],
		# 三颗箭头指进电球术：左、右、下各一个方向
		&"sup_multi":        [Vector2i(1, 3), 0],   # ▶ 指到 (2,3)
		&"sup_duration":     [Vector2i(3, 3), 2],   # ◀ 指到 (2,3)
		&"sup_lightning":    [Vector2i(2, 4), 3],   # ▲ 指到 (2,3)
		# 剩下的排在最后一行，箭头都指着邻居（不是技能石 → 灰色），等你自己去摆
		&"sup_pierce":       [Vector2i(0, 6), 0],
		&"sup_fork":         [Vector2i(1, 6), 0],
		&"sup_chain":        [Vector2i(2, 6), 0],
		&"sup_bounce":       [Vector2i(3, 6), 0],
		&"sup_faster_cast":  [Vector2i(4, 6), 0],
		&"sup_crit":         [Vector2i(5, 6), 0],
	}

	var everything: Array = []
	everything.append_array(EquipLibrary.all_items())
	everything.append_array(Gems.all_gems())
	for thing in everything:
		var id: StringName = thing.id
		if id == &"spark":
			(thing as SkillGem).level = 8        # 主打技能，给个能玩的等级
		var placed: GemGrid.Placed = null
		if layout.has(id):
			placed = grid.place(thing, layout[id][0], layout[id][1])
		if placed == null:
			grid.place_anywhere(thing)   # 位置表写错了也不至于把东西弄丢

	skill_index = 0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"switch_skill"):
		set_skill(skill_index + 1)
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ 宝石

## 当前在用的那颗主动技能石（在网格里的那一件）
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
##   ① 把当前这一格的技能重新展开成 SkillSpec（等级变了、辅助变了都要重算）
##   ② 把当前这一格辅助宝石的词缀整层换进 stats.skill_mods
##
## ②就是"辅助宝石只对它连着的技能生效"的实现 —— 换一格，整层直接换掉，
## 不用一条条 remove_by_source，也不会串味。
func rebuild() -> void:
	var link := active_link()
	skill = link.skill()
	stats.skill_mods.clear()
	stats.skill_mods.add_all(link.mods())

	# ★ 装备：只要在背包里就生效，不用连箭头 ★ 和 skill_mods 一样整层重建
	stats.equip_mods.clear()
	stats.equip_mods.add_all(grid.equip_mods())
	# 把头盔挪出去 → 生命上限掉下来 → 当前血不能还挂在旧上限上
	stats.life = minf(stats.life, stats.max_life())
	stats.mana = minf(stats.mana, stats.max_mana())

	gems_changed.emit()
	# 背包一有变动就存盘。文件很小（十几件宝石的 JSON），
	# 而且变动只在拿起/放下/升级/切技能时发生，不是每帧，所以随手存就行。
	if not _suppress_save:
		GemSave.save(self)


## 切到第 index 颗主动技能石（会自动绕回来，所以可以一直 +1）。
func set_skill(index: int) -> void:
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
func place_gem(gem, origin: Vector2i, rot: int) -> String:
	var why := grid.reject_reason(gem, origin, rot)
	if why != "":
		return why
	grid.place(gem, origin, rot)
	rebuild()
	return ""


## 升 / 降一颗宝石的等级（+1 / -1）。
## 主动石升级 = 点伤和魔力消耗一起涨；辅助石升级 = 它给的词缀数值涨。
func change_level(gem, delta: int) -> void:
	if gem == null:
		return
	gem.level = gem.clamp_level(gem.level + delta)
	rebuild()


## 当前技能这一发的投射物参数（HUD / Tab 面板显示用）
func projectile_spec() -> ProjectileSpec:
	if skill == null:
		return null
	return ProjectileSpec.build(stats, skill)


func _physics_process(delta: float) -> void:
	# 一行推进所有 Buff 计时 + DoT 结算
	DamagePipeline.resolve_dots(stats, delta)
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
	stats.mana = minf(stats.max_mana(), stats.mana + MANA_REGEN * delta)

	# --- 施法 ---
	if Input.is_action_pressed(&"cast") and _cast_cd <= 0.0 and can_aim:
		_try_cast()

	# --- 受击闪白 ---
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
		sprite.modulate = Color(1, 1, 1).lerp(Color(2.5, 1.2, 1.2), _hit_flash / 0.12)


func _try_cast() -> void:
	if skill == null or stats.mana < skill.mana_cost:
		return
	var dir := get_global_mouse_position() - global_position
	if dir.length_squared() < 1.0:
		dir = Vector2.RIGHT
	dir = dir.normalized()

	stats.mana -= skill.mana_cost
	# ★ 施法间隔 = 技能石上的「施放时间」÷ 施法速度倍率 ★
	#   电球术 0.65 秒 ÷ 施法速度 1.25 = 0.52 秒一发。
	#   装备/辅助宝石上的「提高施法速度」会自动缩短它，不用改任何代码。
	var speed := maxf(0.1, stats.get_stat(S.CAST_SPEED, skill.hit_tags()))
	_cast_cd = maxf(0.05, skill.cast_time / speed)

	sprite.flip_h = dir.x < 0.0
	cast_requested.emit(global_position + Vector2(0, -7), dir)


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
