class_name RunUI
extends Control

## 局内流程的界面：地图选房 / 奖励三选一 / 商店。盖在右边战斗画面上。
##
## ★ 这里只画和转发，不做任何流程判断 ★
##   规则在 run/run_state.gd（能不能进、金币够不够）—— 这边按钮被点了
##   只是发信号，World 问过 RunState 之后再回来叫我们刷新画面。
##
## ★ 已知陷阱：不要在按钮回调里立刻重建 UI ★（会把正在处理事件的按钮 free 掉）
##   World 连这些信号时全部用 CONNECT_DEFERRED，等这一帧的事件走完再刷新。

signal room_chosen(index: int)
signal reward_chosen(option: Dictionary)
signal reward_skipped
signal shop_buy(index: int)
signal shop_left

## 面板压暗底色，战斗画面隐约可见，玩家知道自己还"在场地里"
const DIM := Color(0.05, 0.05, 0.08, 0.90)

var _dim: ColorRect
var _panel: PanelContainer
var _box: VBoxContainer
var _status: Label


func _ready() -> void:
	# 只盖住右边 400×400 的战斗画面，别挡住左边背包面板 —— 领了奖励要立刻能摆
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = InventoryUI.PANEL_W
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_dim = ColorRect.new()
	_dim.color = DIM
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP   # 面板开着时点击别漏进战斗画面
	_dim.visible = false
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(380, 0)   # 战斗画面 400 宽，留 10px 边
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.13, 0.98)
	style.border_color = Color(0.36, 0.40, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.visible = false
	add_child(_panel)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	_panel.add_child(_box)

	# 常驻状态条（第几步 / 金币），贴在战斗画面**底下** —— 放顶上会和居中弹出的奖励面板标题叠在一起
	_status = UIHelper.label("", 11, Color(0.92, 0.86, 0.60))
	_status.position = Vector2(8, 378)
	add_child(_status)


## 顶部状态条。战斗中也一直显示，商店定价才有参照。
func set_status(state: RunState) -> void:
	if state == null:
		_status.text = ""
		return
	_status.text = "第 %d / %d 层 · 第 %d / %d 步    金币 %d" % [
		state.floor_index + 1, RunMap.FLOORS, state.step + 1, RunMap.STEPS, state.gold]


func hide_all() -> void:
	_dim.visible = false
	_panel.visible = false


## 是否有面板开着（冒烟测试断言用）
func is_open() -> bool:
	return _panel.visible


# ---------------------------------------------------------------- 三个界面

## 地图：这一步的 2~3 个房间，各一个按钮。奖励类型直接写在按钮上（外显）。
func show_map(state: RunState) -> void:
	_open("第 %d 层 · 选择下一个房间（第 %d / %d 步）" % [
		state.floor_index + 1, state.step + 1, RunMap.STEPS])
	if state.step == 0 and state.floor_index > 0:
		_line("★ 进入第 %d 层 —— 这一层的怪更硬了 ★" % (state.floor_index + 1),
				Color(0.95, 0.75, 0.45))
	var rooms := state.rooms()
	for i in rooms.size():
		var room := rooms[i] as RunMap.Room
		var icon := "⚔"
		if room.type == RunMap.RoomType.SHOP:
			icon = "🛒"
		elif room.type == RunMap.RoomType.BOSS:
			icon = "👑"
		var idx := i   # ★ 闭包要抓拷贝 ★ 直接用 i 的话所有按钮都是最后一个值
		_button("%s  %s" % [icon, room.label()], func() -> void: room_chosen.emit(idx))
	set_status(state)


## 奖励三选一。options 来自 RunRewards.roll_options()。
## gold_gain —— 清房自动进账的金币（0 = 不显示这一行）
func show_reward(kind: int, options: Array, gold_gain: int = 0) -> void:
	_open("战斗胜利！选一个奖励：%s" % RunMap.reward_name(kind))
	if gold_gain > 0:
		_line("✦ 拾获金币 ×%d（清房自动获得）" % gold_gain, Color(0.95, 0.84, 0.45))
	if options.is_empty():
		# 升级奖励可能一个候选都没有（全满级）—— 别让玩家卡死在这个界面
		_line("（没有可用的奖励）", Color(0.75, 0.70, 0.70))
	for opt in options:
		var o: Dictionary = opt
		var text := str(o.get("label", "?"))
		var icon: Texture2D = null
		if o.has("item"):
			text += "\n    " + _short_desc(o["item"])
			icon = UIHelper.gem_icon(o["item"])
		_button(text, func() -> void: reward_chosen.emit(o), Color(0.88, 0.88, 0.95), icon)
	_button("放弃奖励", func() -> void: reward_skipped.emit(), Color(0.62, 0.56, 0.56))


## 商店。stock 是货架上的实物，sold_out 标已卖掉的位置。
func show_shop(state: RunState, stock: Array, sold: Array) -> void:
	_open("商店（金币 %d）" % state.gold)
	for i in stock.size():
		var idx := i
		if sold.has(i):
			_line("（已售出）", Color(0.5, 0.5, 0.55))
			continue
		var thing = stock[i]
		var price := RunContent.price_of(thing)
		var b := _button("%s  —  %d 金\n    %s" % [thing.display_name, price, _short_desc(thing)],
				func() -> void: shop_buy.emit(idx),
				Color(0.88, 0.88, 0.95), UIHelper.gem_icon(thing))
		b.disabled = price > state.gold   # 买不起的直接灰掉，比点了再报错友好
	_button("离开商店，继续赶路", func() -> void: shop_left.emit(), Color(0.62, 0.72, 0.62))
	set_status(state)


## 放不下、买不起之类的即时提示，直接接在面板最底下
func flash_notice(text: String) -> void:
	_line(text, Color(1.0, 0.55, 0.45))


## 好消息（Boss 掉了血脉辅助之类），粉红色
func note(text: String) -> void:
	_line(text, Color(0.95, 0.55, 0.65))


# ---------------------------------------------------------------- 内部

func _open(title: String) -> void:
	for c in _box.get_children():
		c.queue_free()
	_dim.visible = true
	_panel.visible = true
	var t := UIHelper.label(title, 13, Color(0.95, 0.92, 0.80))
	_box.add_child(t)


func _button(text: String, on_press: Callable, color := Color(0.88, 0.88, 0.95),
		icon: Texture2D = null) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# 说明文字太长会把面板撑出战斗画面（截图里"和腰带的…"被切在屏幕外）→ 超出就省略号
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", color)
	if icon != null:
		# ★ 不用 expand_icon ★ —— 它把图标缩到一行字的高度（约 14px），原有的宝石图四周还有透明边，
		#   缩完只剩几个像素，看起来像"没有图"（项目主人截图指出）。固定最大 40px、按钮至少 46 高
		#   （icon_max_width 只限宽不限高，竖长的法杖图会撑到几百像素高 —— 所以还是 expand_icon，
		#   但把按钮撑到 50 高，图标就按 ~40px 等比缩，不会再缩成一粒）
		b.icon = icon
		b.expand_icon = true
		b.add_theme_constant_override("h_separation", 8)
		b.custom_minimum_size.y = 50
	b.pressed.connect(on_press)
	_box.add_child(b)
	return b


func _line(text: String, color: Color) -> void:
	_box.add_child(UIHelper.label(text, 10, color))


## 一件东西的一句话说明（按钮上放不下整段描述，截短）
func _short_desc(thing) -> String:
	var d := str(thing.description)
	if d.length() > 34:
		d = d.substr(0, 33) + "…"
	if thing is EquipItem:
		return "装备 %d×%d  %s" % [thing.width, thing.height, d]
	if thing is SupportGem:
		return "辅助  %s" % d
	return d
