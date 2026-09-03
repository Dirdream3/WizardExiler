class_name InventoryUI
extends Control

## 左侧的**常驻**面板：英雄状态 + 背包网格 + 宝石详情。
##
## 背包做成了**背包乱斗那种网格**：所有宝石都摆在同一张网格里，
## 辅助宝石身上有箭头，箭头指进哪颗主动技能石就辅助哪颗。
## 所以「怎么摆」本身就是构筑 —— 没有插槽，只有摆放。
##
## ★ 这个文件里没有任何规则 ★
##   能不能放、箭头连没连上，全问 GemGrid（纯逻辑，能单测）。
##   画格子的事交给 GemGridView，这里只管把它们串起来。
##
## 交互（和背包乱斗一样）：
##   · 左键点一颗宝石 → 拿起来（连它的朝向一起；拿法杖时槽里的宝石跟着走）
##   · 手上有东西时左键点格子 → 放下；放不下会写明原因
##   · ★ 手上是技能宝石、点一根法杖 → 镶进槽位 ★（同款=合成，占着=交换）
##   · ★ 右键 → 把手上的宝石转 90° ★（箭头跟着转，预览里能直接看到指哪）
##   · 鼠标停在宝石上 → 下面显示它的完整属性；`[-] [+]` 升降级；「取出」拆宝石

const S = preload("res://combat/combat_stat.gd")

## 面板宽度。★ 战斗画面就是从这里开始的 ★（main.tscn 里 Battle 的 offset_left）
const PANEL_W := 300.0
const BAR_H := 8.0

var player: Player

## 拿在手上的宝石 + 它的朝向
var _held = null
var _held_rot := 0
## 丢弃的两段确认：第一次点「丢弃」把手上的东西记在这里，第二次点才真的销毁。
## 任何点击（放下/拿起/右键）都会清掉它 —— 改了主意就要重新确认，不能"一点就没"。
var _discard_arm = null
## 详情面板当前显示的宝石
var _detail = null
## 上一次操作的提示（放不下的原因等）
var _notice := ""

var _life_fill: ColorRect
var _mana_fill: ColorRect
var _vital_label: Label
var _gold_label: Label
var _combat_label: Label
var _buff_label: Label
var _skill_label: Label
var _grid_view: GemGridView
var _held_label: Label
var _detail_text: RichTextLabel
var _dps_cd := 0.0
var _dps := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_LEFT_WIDE)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = PANEL_W
	offset_bottom = 0.0
	# ★ STOP：点在面板上的鼠标事件到此为止，不会漏给游戏世界 ★
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func bind(p: Player) -> void:
	player = p
	_grid_view.player = p
	player.gems_changed.connect(func() -> void: refresh.call_deferred())
	if _detail == null and player.active_item() != null:
		_detail = player.active_item().gem
	refresh()


# ------------------------------------------------------------------ 每帧刷新

## 只更新会变的数字，不重画网格。网格的重画走 refresh()。
func _process(delta: float) -> void:
	if player == null or player.stats == null:
		return
	var st := player.stats
	var inner := PANEL_W - 14.0
	_life_fill.size.x = inner * clampf(st.life / maxf(1.0, st.max_life()), 0.0, 1.0)
	_mana_fill.size.x = inner * clampf(st.mana / maxf(1.0, st.max_mana()), 0.0, 1.0)

	_vital_label.text = "生命 %d/%d    魔力 %d/%d" % [
		roundi(st.life), roundi(st.max_life()), roundi(st.mana), roundi(st.max_mana())]

	# ★ 金币常驻显示（只在局模式下有意义，沙盒没有金币概念）★
	if RunSession.enabled and RunSession.state != null:
		_gold_label.visible = true
		_gold_label.text = "✦ 金币 %d" % RunSession.state.gold
	else:
		_gold_label.visible = false

	# DPS 要跑一遍完整的伤害管线，没必要每帧算
	_dps_cd -= delta
	if _dps_cd <= 0.0:
		_dps_cd = 0.2
		var target := UIHelper.nearest_enemy(get_tree(), player)
		_dps = 0.0
		if target != null and target.stats != null and player.skill != null:
			_dps = DamagePipeline.dps(st, target.stats, player.skill)
		# ★ 详情停在触媒上时，进度文本要活着 ★ —— 否则战斗中盯着面板看，
		# 进度纹丝不动，像是"施加异常没被计数"（其实一直在走）
		if _detail is CatalystGem:
			_detail_text.text = _detail_bbcode()

	_combat_label.text = "单发 DPS %d    场上敌人 %d" % [
		roundi(_dps), get_tree().get_node_count_in_group(&"enemy")]
	_buff_label.text = "增益: " + _buff_text(st)
	_skill_label.text = _skill_text()


func _buff_text(st: CombatEntity) -> String:
	var parts := PackedStringArray()
	for inst in st.buffs.active():
		parts.append((inst as BuffInstance).describe())
	return "无" if parts.is_empty() else "  ".join(parts)


## 当前技能这一发的实际参数（含装备词缀 + 箭头连上的辅助）
func _skill_text() -> String:
	if player.skill == null:
		return "[Q] 没有能用的技能 —— 把技能宝石镶进一根法杖"
	var ps := player.projectile_spec()
	var head := "[Q] %s  消耗%d" % [player.skill.display_name, roundi(player.skill.mana_cost)]
	if ps == null:
		return head
	return "%s  %s" % [head, ps.describe()]


# ------------------------------------------------------------------ 交互

func _on_cell_pressed(cell: Vector2i) -> void:
	_discard_arm = null   # 点了格子 = 改主意了，丢弃要重新走两段确认
	if _held == null:
		# 空手 → 把这一格上的东西整件拿起来
		var p := player.pick_up_at(cell)
		if p != null:
			_held = p.gem
			_held_rot = p.rot
			_detail = p.gem
			_notice = ""
		player.rebuild()
		return

	# 手上有东西 → 放到预览的位置去
	var origin := _grid_view.ghost_origin()

	# ★ 手上是技能宝石、点在法杖上 = 镶嵌 ★ 优先于普通放置
	var wand := player.grid.socket_target(_held, origin)
	if wand != null:
		var socket_why := player.grid.socket_reject_reason(_held, origin)
		if socket_why != "":
			_notice = "✕ " + socket_why
			refresh.call_deferred()
			return
		var wand_gem := wand.gem as EquipItem
		var had := wand_gem.socketed
		var out = player.socket_gem(_held, wand)
		_held = out          # 交换时旧宝石回到手上；镶入/合成时手空了
		_held_rot = 0
		_detail = wand_gem
		if out != null:
			_notice = "✦ 换下「%s」，拿在手上了" % out.display_name
		elif had != null:
			_notice = "✦ 合成！槽里的「%s」升到 %d 级" % [had.display_name, had.level]
		else:
			_notice = "✦ 已镶入「%s」" % wand_gem.display_name
		refresh.call_deferred()
		return

	# 先看是不是叠在同款上（合成）——成功后要报"升到几级"，得提前记住目标
	var target := player.grid.merge_target(_held, origin)
	var why := player.place_gem(_held, origin, _held_rot)
	if why == "":
		_held = null
		_held_rot = 0
		if target != null:
			_notice = "✦ 合成！「%s」升到 %d 级" % [target.gem.display_name, target.gem.level]
			_detail = target.gem
		else:
			_notice = ""
		player.rebuild()
	else:
		_notice = "✕ " + why
		refresh.call_deferred()


## ★ 拿在手上的宝石不能跟着场景一起没了 ★
##   按 R 重开、或者直接关游戏时，手上那颗还没落地 —— 网格里没有它，存档里自然也没有。
##   所以退场前先把它塞回网格再存一次盘。
func _exit_tree() -> void:
	if _held != null and player != null:
		player.grid.place_anywhere(_held, _held_rot)
		_held = null
		GemSave.save(player)


## 右键：手上有宝石 → 转 90°；★ 空手右键点法杖 → 取出槽里的宝石 ★
## 为什么用右键取出：靠"悬停详情 + 按钮"取宝石不可靠 ——
## 鼠标挪去按钮的路上会扫过别的宝石，详情就被顶掉了。右键直接点在法杖上，没有中间状态。
func _on_rotate_pressed() -> void:
	_discard_arm = null
	if _held == null:
		var p := player.grid.at(_grid_view.hover_cell())
		if p != null and p.is_wand() and p.skill_gem() != null:
			_held = player.unsocket_gem(p.gem as EquipItem)
			_held_rot = 0
			_detail = _held
			_notice = "✦ 取出了「%s」，拿在手上" % _held.display_name
		else:
			_notice = "手上有宝石时右键 = 转方向；空手右键点法杖 = 取出槽里的宝石"
	else:
		_held_rot = (_held_rot + 1) % 4
		_notice = ""
	refresh.call_deferred()


func _on_gem_hovered(gem) -> void:
	if gem != null:
		_detail = gem
		_detail_text.text = _detail_bbcode()


func _change_detail_level(delta: int) -> void:
	if _detail == null:
		return
	# 详情停在法杖上时，[-]/[+] 操作的是槽里的技能宝石（法杖本身没有等级）
	var target = _detail
	if _detail is EquipItem and (_detail as EquipItem).socketed != null:
		target = (_detail as EquipItem).socketed
	target.level = target.clamp_level(target.level + delta)
	player.rebuild()


## 「取出宝石」按钮：把详情面板当前这根法杖槽里的宝石拆出来、放到手上。
func _unsocket_detail() -> void:
	if not (_detail is EquipItem) or (_detail as EquipItem).socketed == null:
		# 鼠标挪过来的路上详情常被别的宝石顶掉 → 直接教更稳的手势
		_notice = "✕ 详情不是镶着宝石的法杖 —— 直接空手右键点法杖就能取出"
		refresh.call_deferred()
		return
	if _held != null:
		_notice = "✕ 手上有东西，先放下再取"
		refresh.call_deferred()
		return
	_held = player.unsocket_gem(_detail as EquipItem)
	_held_rot = 0
	_notice = "✦ 取出了「%s」，拿在手上" % _held.display_name
	refresh.call_deferred()


## 「丢弃」按钮：把手上的东西**销毁**。
## ★ 两段确认 ★ 销毁不可逆（背包空间就是靠丢东西腾的，但误触不能原谅）：
##   第一次点只发警告并记住"要丢的是哪一件"，第二次点同一件才真的丢。
func _discard_held() -> void:
	if _held == null:
		_notice = "✕ 先把要丢的东西拿在手上（左键点它），再点「丢弃」"
		refresh.call_deferred()
		return
	if _discard_arm != _held:
		_discard_arm = _held
		var extra := ""
		if _held is EquipItem and (_held as EquipItem).socketed != null:
			extra = "，槽里的「%s」会一起丢掉" % (_held as EquipItem).socketed.display_name
		_notice = "⚠ 再点一次「丢弃」就扔掉「%s」%s（不可恢复）" % [_gem_name(_held), extra]
		refresh.call_deferred()
		return
	# 手上的东西本来就不在网格里，放掉引用它就没了；rebuild 顺手把"没有它"的背包存盘
	var gone := _gem_name(_held)
	_held = null
	_held_rot = 0
	_discard_arm = null
	_notice = "✦ 已丢弃「%s」" % gone
	player.rebuild()
	refresh.call_deferred()


# ------------------------------------------------------------------ 构建界面

func _build() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.055, 0.085, 1.0)
	style.border_color = Color(0.28, 0.32, 0.44)
	style.border_width_right = 1
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	# ---------------- 英雄状态 ----------------
	var life := _make_bar(Color(0.83, 0.26, 0.28))
	_life_fill = life[1]
	box.add_child(life[0])

	var mana := _make_bar(Color(0.32, 0.52, 0.88))
	_mana_fill = mana[1]
	box.add_child(mana[0])

	_vital_label = UIHelper.label("", 9, Color(0.90, 0.90, 0.95), false)
	box.add_child(_vital_label)
	# 金币行：局模式常驻显示，沙盒模式隐藏（_process 里控制）
	_gold_label = UIHelper.label("", 10, Color(0.95, 0.84, 0.45), false)
	_gold_label.visible = false
	box.add_child(_gold_label)
	_combat_label = UIHelper.label("", 9, Color(0.98, 0.80, 0.42), false)
	box.add_child(_combat_label)
	_buff_label = UIHelper.label("", 9, Color(0.62, 0.86, 0.48), false)
	box.add_child(_buff_label)

	_skill_label = UIHelper.label("", 8, Color(0.68, 0.80, 0.96), false)
	_skill_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skill_label.custom_minimum_size = Vector2(PANEL_W - 14.0, 0)
	box.add_child(_skill_label)

	# ---------------- 背包网格 ----------------
	box.add_child(_title("背包  左键拿/放  右键转向  宝石点法杖=镶嵌  空手右键法杖=取出"))

	_grid_view = GemGridView.new()
	_grid_view.cell_pressed.connect(_on_cell_pressed)
	_grid_view.rotate_pressed.connect(_on_rotate_pressed)
	_grid_view.gem_hovered.connect(_on_gem_hovered)
	box.add_child(_grid_view)

	_held_label = UIHelper.label("", 8, Color(0.98, 0.86, 0.45), false)
	_held_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_held_label.custom_minimum_size = Vector2(PANEL_W - 14.0, 0)
	box.add_child(_held_label)

	# ---------------- 详情 ----------------
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 3)
	box.add_child(level_row)
	level_row.add_child(_small_button("-", func() -> void: _change_detail_level(-1)))
	level_row.add_child(_small_button("+", func() -> void: _change_detail_level(1)))
	level_row.add_child(UIHelper.label(" 升降级 ", 8, Color(0.55, 0.55, 0.65), false))
	# 镶进法杖的宝石不占格子、点不到 → 必须有一个专门的"拆下来"入口
	var unsocket := _small_button("取出宝石", func() -> void: _unsocket_detail())
	unsocket.custom_minimum_size = Vector2(56, 14)
	level_row.add_child(unsocket)
	# 丢弃手上的东西（两段确认）。背包空间有限，打到不要的装备/宝石靠它腾地方
	var discard := _small_button("丢弃", func() -> void: _discard_held())
	discard.custom_minimum_size = Vector2(40, 14)
	level_row.add_child(discard)
	# ★ 有了存档就必须有这个按钮 ★ 摆乱了之后光靠重开是回不去的
	var reset := _small_button("重置背包", func() -> void:
		_held = null
		_held_rot = 0
		_notice = "背包已经恢复成默认摆法"
		player.reset_backpack())
	reset.custom_minimum_size = Vector2(56, 14)
	level_row.add_child(reset)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	_detail_text = RichTextLabel.new()
	_detail_text.bbcode_enabled = true
	_detail_text.fit_content = true
	_detail_text.scroll_active = false
	_detail_text.custom_minimum_size = Vector2(PANEL_W - 22.0, 0)
	_detail_text.add_theme_font_size_override("normal_font_size", 8)
	_detail_text.add_theme_font_size_override("bold_font_size", 8)
	scroll.add_child(_detail_text)

	# ---------------- 底部操作提示 ----------------
	var hint := UIHelper.label(
		"WASD 移动   左键/空格 施法   Q 切技能   Tab 伤害详情   R 重开一整局",
		8, Color(0.55, 0.55, 0.65), false)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(PANEL_W - 14.0, 0)
	box.add_child(hint)


func refresh() -> void:
	if player == null or not is_inside_tree():
		return

	_grid_view.held = _held
	_grid_view.held_rot = _held_rot
	_grid_view.refresh()

	if _held != null:
		if _held is SkillGem:
			_held_label.text = "手上：%s（点法杖=镶入 / 点格子放下 / 叠同款=合成）" % _gem_name(_held)
		else:
			_held_label.text = "手上：%s（点格子放下 / 右键转方向 / 叠同款=合成）" % _gem_name(_held)
	elif _notice != "":
		# ✕ / ✦ 前缀由设置提示的那一方自己带（拒绝原因带 ✕，合成成功带 ✦）
		_held_label.text = _notice
	else:
		_held_label.text = "技能宝石要镶进法杖才能施放；箭头指着法杖的辅助才生效"

	_detail_text.text = _detail_bbcode()


# ------------------------------------------------------------------ 小部件

func _make_bar(color: Color) -> Array:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(PANEL_W - 14.0, BAR_H)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.09, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bg)

	var fill := ColorRect.new()
	fill.color = color
	fill.position = Vector2(1, 1)
	fill.size = Vector2(PANEL_W - 16.0, BAR_H - 2.0)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fill)

	return [holder, fill]


func _small_button(text: String, on_click: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(16, 14)
	b.add_theme_font_size_override("font_size", 10)
	b.pressed.connect(on_click)
	return b


func _title(text: String) -> Label:
	return UIHelper.label(text, 9, Color(0.55, 0.78, 0.96), false)


# ------------------------------------------------------------------ 显示文本

func _gem_name(gem) -> String:
	# 辅助宝石和装备没有等级（max_level = 1），别显示一个永远是 Lv1 的假等级
	if int(gem.max_level) <= 1:
		return String(gem.display_name)
	return "%s Lv%d" % [gem.display_name, gem.level]


func _detail_bbcode() -> String:
	if _detail == null:
		return "[color=#7a7a8c]把鼠标停在一颗宝石上看它的属性。[/color]"

	# 面板顶上放一张大图标（有图才放；BBCode 的 [img] 直接吃资源路径）
	var head := ""
	var ipath := UIHelper.icon_path(_detail)
	if ipath != "":
		head = "[img=34]%s[/img]\n" % ipath

	if _detail is EquipItem:
		var eq := _detail as EquipItem
		var etext := head + eq.tooltip()
		# 法杖：把槽里技能宝石的完整面板也接在下面（宝石不占格子、悬停不到）
		if eq.socketed != null:
			var wand_placed := _find_placed(eq)
			var sups: Array = []
			if wand_placed != null:
				for s in player.grid.supports_for(wand_placed):
					sups.append((s as GemGrid.Placed).gem)
			etext += "\n[color=#7a7a8c]──── 槽里的宝石 ────[/color]\n"
			etext += eq.socketed.tooltip(sups)
			etext += "\n[color=#9a9aac]空手右键点这根法杖，就能把它取出来[/color]"
		return etext

	if _detail is SkillGem:
		# 裸放的技能宝石：没有载体，吃不到任何辅助 —— 提醒玩家镶进法杖
		return head + (_detail as SkillGem).tooltip() \
				+ "\n[color=#9a9aac]拿起来点到一根法杖上镶入，才能施放[/color]"

	var out := head + (_detail as SupportGem).tooltip()
	# 这颗辅助现在连到哪了？直接告诉玩家，省得对着箭头猜
	var placed := _find_placed(_detail)
	if placed != null:
		var state := player.grid.arrow_state(placed)
		var target := player.grid.at(placed.arrow_target())
		match state:
			"linked":
				out += "\n[color=#6be06b]★ 箭头连到「%s」，辅助着槽里的「%s」★[/color]" % [
					target.gem.display_name, target.skill_gem().display_name]
			"blocked":
				out += "\n[color=#e07070]箭头指着「%s」，但槽里的「%s」没有【%s】标签，连不上[/color]" % [
					target.gem.display_name, target.skill_gem().display_name,
					CombatTags.describe(_detail.required_tags)]
			_:
				out += "\n[color=#9a9aac]箭头没指着法杖 —— 把它挪到法杖旁边，箭头对准法杖[/color]"
	return out


func _find_placed(gem) -> GemGrid.Placed:
	for it in player.grid.items:
		if (it as GemGrid.Placed).gem == gem:
			return it
	return null
