class_name GameHUD
extends CanvasLayer

## 界面外壳。
##
## ★ 绝大部分 UI 都在左边那块常驻面板里（game/inventory_ui.gd）★
##   这个文件只剩两样**盖在战斗画面上**的东西：
##     · 屏幕中央的大字提示（死亡）
##     · Tab 打开的伤害计算详情面板
##   其余（血条 / 数值 / Buff / 技能栏 / 背包 / 宝石详情 / 操作提示）
##   全部搬去了左侧面板，战斗画面里干干净净只有游戏。

var player: Player

var _center_msg: Label
var _debug_panel: PanelContainer
var _debug_text: RichTextLabel
var _debug_cd := 0.0
var _panel: InventoryUI


func _ready() -> void:
	InputSetup.ensure()
	_build_ui()


## World 在生成玩家之后调它（HUD 的 _ready 比 World 的早，那时候玩家还不存在）
func bind_player(p: Player) -> void:
	player = p
	_panel.bind(p)


## 左侧常驻面板（冒烟测试要拿它做点击模拟）
func inventory() -> InventoryUI:
	return _panel


func _process(delta: float) -> void:
	if player == null or player.stats == null:
		return
	if _debug_panel.visible:
		_debug_cd -= delta
		if _debug_cd <= 0.0:
			_debug_cd = 0.2   # 每秒刷 5 次就够了，不用每帧重算
			_debug_text.text = _report_text()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug"):
		_debug_panel.visible = not _debug_panel.visible
		_debug_cd = 0.0
		get_viewport().set_input_as_handled()


func show_message(text: String) -> void:
	_center_msg.text = text
	_center_msg.visible = text != ""


# ------------------------------------------------------------------ 内部

func _report_text() -> String:
	if player.skill == null:
		return "[color=#e07070]当前技能栏这一格没有插技能石。在左边的背包里插一颗。[/color]"
	var target := UIHelper.nearest_enemy(get_tree(), player)
	return DamageReport.build(
		player.stats,
		target.stats if target != null else null,
		player.skill)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- 屏幕中央提示（死亡等）。只盖在右边的战斗画面上 ---
	_center_msg = UIHelper.label("", 16, Color(1.0, 0.55, 0.5))
	_center_msg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center_msg.offset_left = InventoryUI.PANEL_W
	_center_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_msg.visible = false
	root.add_child(_center_msg)

	# --- Tab 打开的伤害详情面板（盖满整屏，字多，挤在方形画面里看不清）---
	_debug_panel = PanelContainer.new()
	_debug_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_debug_panel.offset_left = 16
	_debug_panel.offset_top = 12
	_debug_panel.offset_right = -16
	_debug_panel.offset_bottom = -12
	_debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.09, 0.96)
	style.border_color = Color(0.30, 0.34, 0.46)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(8)
	_debug_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_debug_panel)

	var scroll := ScrollContainer.new()
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_panel.add_child(scroll)

	_debug_text = RichTextLabel.new()
	_debug_text.bbcode_enabled = true
	_debug_text.fit_content = true
	_debug_text.scroll_active = false
	_debug_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_debug_text.add_theme_font_size_override("normal_font_size", 10)
	_debug_text.add_theme_font_size_override("bold_font_size", 10)
	_debug_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_debug_text)

	# --- 左侧常驻面板 ---
	# ★ 放在最后 add_child ★ 它要吃鼠标点击，必须画在最上层
	_panel = InventoryUI.new()
	root.add_child(_panel)
