class_name GemGridView
extends Control

## 背包网格的**画法和点击**（背包乱斗那种）。
##
## ★ 这里没有任何规则 ★ 能不能放、箭头连没连上，全问 GemGrid（纯逻辑，能单测）。
## 这个文件只干三件事：画格子、画宝石和箭头、把点击翻译成"第几列第几行"。
##
## 整块网格是**一个** Control 自己 _draw() 出来的，不是 56 个 Button ——
## 因为一颗宝石会跨好几个格子，还要画箭头和拖拽预览，用按钮拼不出来。

const CELL := 24.0          ## 一格多少像素
const GAP := 1.0            ## 格子之间的缝

signal cell_pressed(cell: Vector2i)   ## 左键点了某一格
signal rotate_pressed                 ## 右键：转手上的宝石
signal gem_hovered(gem)               ## 鼠标停到某颗宝石上（null = 空格）

var player: Player
## 拿在手上的宝石（只用来画预览，真正的状态在 InventoryUI 里）
var held = null
var held_rot := 0

var _hover := Vector2i(-1, -1)


func _ready() -> void:
	custom_minimum_size = Vector2(GemGrid.WIDTH * CELL, GemGrid.HEIGHT * CELL)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 贴着边缘的宝石，箭头会探到网格外面去 —— 裁掉，别糊到别的控件上
	clip_contents = true


func refresh() -> void:
	queue_redraw()


## 手上拿着的东西放到当前悬停位置的话，左上角应该落在哪一格。
##
## ★ 用"外接矩形的中心对准鼠标"而不是"左上角对准鼠标" ★
##   否则拿起一块 2×2 的技能石时，方块会整个歪在鼠标右下方，很难对准。
func ghost_origin() -> Vector2i:
	if held == null:
		return _hover
	var size := GemGrid.shape_for(held).size_at(held_rot)
	return _hover - Vector2i((size.x - 1) / 2, (size.y - 1) / 2)


# ------------------------------------------------------------------ 输入

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var c := _cell_at((event as InputEventMouseMotion).position)
		if c != _hover:
			_hover = c
			var p := player.grid.at(c) if player != null else null
			gem_hovered.emit(p.gem if p != null else null)
			queue_redraw()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			cell_pressed.emit(_cell_at(mb.position))
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			rotate_pressed.emit()
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = Vector2i(-1, -1)
		queue_redraw()


func _cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))


# ------------------------------------------------------------------ 画

func _draw() -> void:
	if player == null:
		return

	# ① 空格子
	for y in GemGrid.HEIGHT:
		for x in GemGrid.WIDTH:
			draw_rect(_cell_rect(Vector2i(x, y)), Color(0.11, 0.11, 0.16), true)

	# ② 已经放好的宝石
	var active := player.active_item()
	for it in player.grid.items:
		_draw_item(it as GemGrid.Placed, it == active)

	# ③ 拖拽预览
	if held != null and _hover.x >= 0:
		_draw_ghost()


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * CELL + Vector2(GAP, GAP),
			Vector2(CELL - GAP * 2.0, CELL - GAP * 2.0))


func _draw_item(p: GemGrid.Placed, is_active: bool) -> void:
	var col := UIHelper.gem_color(p.gem)

	# 宝石本体：占的每一格都铺一块
	for cell in p.cells():
		draw_rect(_cell_rect(cell), col, true)
	# 当前在用的那颗技能石描一圈亮边
	if is_active:
		for cell in p.cells():
			draw_rect(_cell_rect(cell), Color(1.0, 0.93, 0.55), false, 1.0)

	# 名字写在左上角那一格里
	var font := get_theme_default_font()
	var fs := 11 if p.is_skill() else 9
	var text := UIHelper.gem_short(p.gem)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := _cell_rect(p.cells()[0])
	draw_string(font, box.position + Vector2((box.size.x - w) * 0.5, box.size.y * 0.72),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.06, 0.06, 0.09))

	# 等级缩在右下角。★ 宝石只占 1 格了，和名字挤在同一格里 ★
	# 所以名字往上提一点、等级右下角小字，别糊成一团。
	if p.is_skill():
		var lv := "%d" % p.gem.level
		var lw := font.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
		draw_string(font, box.position + Vector2(box.size.x - lw - 1.0, box.size.y - 1.0),
				lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.10, 0.10, 0.14, 0.9))

	# 箭头
	if p.is_support():
		_draw_arrow(p)


## 箭头画在"箭头格"朝外的那条边上，颜色说明它连没连上：
##   绿 = 连上了   红 = 指着技能石但标签不匹配   灰 = 没指着任何技能石
func _draw_arrow(p: GemGrid.Placed) -> void:
	var state := player.grid.arrow_state(p)
	var col := Color(0.45, 0.45, 0.52)
	if state == "linked":
		col = Color(0.42, 1.0, 0.45)
	elif state == "blocked":
		col = Color(1.0, 0.36, 0.36)

	_draw_arrow_at(p.arrow_cell(), p.facing(), col)


## ★ 箭头要**探出宝石外面**画 ★
##   画在自己身上的话，绿色辅助宝石配绿色箭头根本看不见 ——
##   探到它指的那一格上，既看得清，又能一眼看出"它指的是这一颗"。
##   再垫一层深色描边，压在任何底色上都清楚。
func _draw_arrow_at(cell: Vector2i, facing: Vector2i, col: Color) -> void:
	var centre := _cell_rect(cell).get_center()
	var dir := Vector2(facing)
	# ★ 只探出去一点点 ★ 宝石现在都只占 1 格，箭头指的那一格就是技能石本身 ——
	#   探太深会把技能石上的字整个盖住（试过，三个箭头一夹就什么都看不见了）。
	#   所以尖端只越过格子边界一点点：格边在 0.5，尖端 0.60。
	var base := centre + dir * (CELL * 0.26)
	var tip := centre + dir * (CELL * 0.60)
	var side := Vector2(-dir.y, dir.x) * (CELL * 0.19)
	draw_colored_polygon(PackedVector2Array([
			tip + dir * 1.5, base + side * 1.7 - dir, base - side * 1.7 - dir]),
			Color(0.04, 0.04, 0.07, 0.95))
	draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), col)


func _draw_ghost() -> void:
	var origin := ghost_origin()
	var ok := player.grid.can_place(held, origin, held_rot)
	var col := Color(0.40, 0.95, 0.45, 0.45) if ok else Color(1.0, 0.35, 0.35, 0.40)

	var shape := GemGrid.shape_for(held)
	for c in shape.cells_at(held_rot):
		var cell: Vector2i = origin + c
		if player.grid.in_bounds(cell):
			draw_rect(_cell_rect(cell), col, true)

	# 预览也把箭头画出来，这样右键转方向时一眼能看到会指到哪
	if shape.has_arrow:
		_draw_arrow_at(origin + shape.arrow_cell_at(held_rot), shape.facing(held_rot),
				Color(1.0, 1.0, 1.0, 0.85))
