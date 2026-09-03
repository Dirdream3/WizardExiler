class_name ConsoleUI
extends Control

## 调试控制台：把图鉴里的任何东西直接生成进背包。
##
## ★ 这是给项目主人调试/试构筑用的作弊面板 ★ —— 按 ` 或 F1 开关。
## 盖在右边战斗画面上（开着时挡住点击，不会误施法）；左边背包面板照常可用，
## 生成完立刻就能去摆。
##
## 结构照抄 RunUI：这里只画和转发，"能不能放进背包"仍由 GemGrid 说了算
## （放不下就提示，不硬塞）。筛选只是对图鉴列表按类型过滤，纯显示逻辑。

## 筛选档位 → 按钮文字。all 之外按"东西的类型"分。
const FILTERS := {
	"all": "全部",
	"skill": "技能宝石",
	"support": "辅助宝石",
	"catalyst": "触媒",
	"equip": "装备",
}

var player: Player

var _filter := "all"
var _dim: ColorRect
var _panel: PanelContainer
var _box: VBoxContainer
var _list: VBoxContainer
var _notice: Label


func _ready() -> void:
	InputSetup.ensure()
	# 只盖右边的战斗画面，别挡左边的背包面板 —— 生成完要立刻能摆
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = InventoryUI.PANEL_W
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_dim = ColorRect.new()
	_dim.color = Color(0.05, 0.05, 0.08, 0.85)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP   # 开着时点击别漏进战斗画面
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(340, 360)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.13, 0.98)
	style.border_color = Color(0.62, 0.45, 0.78)   # 紫边：一眼认出这是作弊面板
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	_panel.add_child(_box)

	_box.add_child(UIHelper.label("控制台 · 点一件放进背包（` / F1 关闭）", 12,
			Color(0.85, 0.70, 0.98)))

	# ---- 筛选行 ----
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	_box.add_child(row)
	for key in FILTERS:
		var k := str(key)
		var b := Button.new()
		b.text = FILTERS[key]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 10)
		b.pressed.connect(func() -> void: set_filter(k))
		row.add_child(b)

	# ---- 物品列表 ----
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(320, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)

	_notice = UIHelper.label("", 10, Color(0.95, 0.84, 0.45), false)
	_box.add_child(_notice)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_console"):
		set_open(not visible)
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 对外接口
# （方法拆出来是给冒烟测试用的：开关 / 筛选 / 生成都能不经过鼠标直接验）

func set_open(open: bool) -> void:
	visible = open
	if open:
		_notice.text = ""
		_refresh_list()


func set_filter(f: String) -> void:
	if FILTERS.has(f):
		_filter = f
	_refresh_list()


## 当前筛选档位下的图鉴内容（每次都是新实例，直接就能放进背包）
func filtered_things() -> Array:
	var out: Array = []
	for thing in GemSave.everything():
		if _matches(thing):
			out.append(thing)
	return out


## 生成一件到背包。成功 true；背包放不下 false（提示，不硬塞）。
func spawn(id: StringName) -> bool:
	if player == null:
		return false
	var thing = GemSave.resolve(id)
	if thing == null:
		return false
	if player.grid.place_anywhere(thing) == null:
		_notice.text = "✕ 背包放不下了！先在左边腾地方"
		return false
	player.rebuild()   # 顺手存盘 + 刷新左边面板
	_notice.text = "✦ 已放入「%s」" % thing.display_name
	return true


# ---------------------------------------------------------------- 内部

func _matches(thing) -> bool:
	match _filter:
		"skill":
			return thing is SkillGem
		"support":
			# 普通辅助：触媒单独一档，别混在一起
			return thing is SupportGem and not (thing is CatalystGem)
		"catalyst":
			return thing is CatalystGem
		"equip":
			return thing is EquipItem
	return true


func _refresh_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	for thing in filtered_things():
		var id: StringName = thing.id
		var b := Button.new()
		b.text = "%s   %s" % [thing.display_name, _kind_text(thing)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 10)
		var icon := UIHelper.gem_icon(thing)
		if icon != null:
			b.icon = icon
			b.expand_icon = true
		b.custom_minimum_size = Vector2(0, 22)
		# ★ 闭包抓的是 id 的拷贝 ★ 点的时候再 resolve 一颗新实例
		b.pressed.connect(func() -> void: spawn(id))
		_list.add_child(b)


func _kind_text(thing) -> String:
	if thing is CatalystGem:
		return "触媒 · %s" % (thing as CatalystGem).trigger_text()
	if thing is SupportGem:
		return "辅助"
	if thing is EquipItem:
		var e := thing as EquipItem
		return "装备 %d×%d" % [e.width, e.height]
	return "技能"
