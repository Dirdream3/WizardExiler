class_name GemGrid
extends RefCounted

## 背包网格（背包乱斗那种）。
##
## ★★ 这是这一版最重要的设计改动：连接关系不再是"插槽"，而是**摆放位置** ★★
##
##   辅助宝石身上有一个箭头，箭头指进哪颗主动技能石，就辅助哪颗。
##   所以「怎么摆」本身就是构筑的一部分：
##     · 想给电球术连 3 颗辅助 → 得在它周围腾出 3 个箭头位
##     · 一颗辅助只有一个箭头 → 不可能同时辅助两个技能
##     · 想换个技能吃这颗辅助 → 把宝石转个方向，或者把技能挪过去
##
##   这比"技能栏有 4 个插槽"有意思得多，而且规则全是几何的、纯逻辑的，能单测。
##
## ★ 这里没有一行画图代码 ★ 格子坐标是"第几列第几行"，不是像素。

const WIDTH := 8
const HEIGHT := 7


## 放在网格里的一件宝石
class Placed extends RefCounted:
	var gem                       ## SkillGem 或 SupportGem
	var shape: GemShape
	var origin := Vector2i.ZERO   ## 外接矩形左上角在网格里的位置
	var rot := 0                  ## 转了几个 90°

	func _init(p_gem = null, p_shape: GemShape = null, p_origin := Vector2i.ZERO, p_rot := 0) -> void:
		gem = p_gem
		shape = p_shape
		origin = p_origin
		rot = p_rot

	## 实际占住的格子（网格绝对坐标）
	func cells() -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for c in shape.cells_at(rot):
			out.append(origin + c)
		return out

	func facing() -> Vector2i:
		return shape.facing(rot)

	## 箭头射出的那一格（网格绝对坐标）
	func arrow_cell() -> Vector2i:
		return origin + shape.arrow_cell_at(rot)

	## 箭头**指向**的那一格（网格绝对坐标）。箭头格再往前走一步。
	func arrow_target() -> Vector2i:
		return arrow_cell() + facing()

	func is_support() -> bool:
		return gem is SupportGem

	func is_skill() -> bool:
		return gem is SkillGem

	func is_equip() -> bool:
		return gem is EquipItem


var items: Array = []   ## Array[Placed]


## 这件东西占什么形状。
##   主动技能石 / 辅助宝石 —— 都只占 1 格（辅助多一个箭头）
##   装备             —— 按它自己的 width × height，又大又占地方
static func shape_for(gem) -> GemShape:
	if gem is SupportGem:
		return GemShape.arrow_single()
	if gem is EquipItem:
		return GemShape.rect((gem as EquipItem).width, (gem as EquipItem).height)
	return GemShape.square(1)


# ---------------------------------------------------------------- 摆放

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < WIDTH and cell.y < HEIGHT


## 这一格上放着谁（没有就是 null）
func at(cell: Vector2i) -> Placed:
	for it in items:
		if (it as Placed).cells().has(cell):
			return it
	return null


## 能不能把 gem 以 rot 的朝向放到 origin。
##   ignore —— 忽略这一件（"把它拿起来再放回原处"时要用，否则它会挡自己）
func can_place(gem, origin: Vector2i, rot: int, ignore: Placed = null) -> bool:
	if gem == null:
		return false
	var shape := shape_for(gem)
	for c in shape.cells_at(rot):
		var cell: Vector2i = origin + c
		if not in_bounds(cell):
			return false
		var occupant := at(cell)
		if occupant != null and occupant != ignore:
			return false
	return true


## 放不下的原因（给 UI 提示用）。放得下返回 ""。
func reject_reason(gem, origin: Vector2i, rot: int, ignore: Placed = null) -> String:
	if gem == null:
		return "没有东西可以放"
	var shape := shape_for(gem)
	for c in shape.cells_at(rot):
		var cell: Vector2i = origin + c
		if not in_bounds(cell):
			return "放不下：超出背包边界"
		var occupant := at(cell)
		if occupant != null and occupant != ignore:
			return "放不下：那里已经有「%s」了" % occupant.gem.display_name
	return ""


## 放一件进去。放不下返回 null。
func place(gem, origin: Vector2i, rot: int) -> Placed:
	if not can_place(gem, origin, rot):
		return null
	var p := Placed.new(gem, shape_for(gem), origin, rot)
	items.append(p)
	return p


## 找个空地放进去（开局铺初始宝石、以及"实在放不下就随便找个地方"时用）。
func place_anywhere(gem, rot: int = 0) -> Placed:
	for y in HEIGHT:
		for x in WIDTH:
			var p := place(gem, Vector2i(x, y), rot)
			if p != null:
				return p
	return null


func remove(p: Placed) -> void:
	items.erase(p)


## 把某一格上的东西整件拿走并返回它
func remove_at(cell: Vector2i) -> Placed:
	var p := at(cell)
	if p != null:
		items.erase(p)
	return p


# ---------------------------------------------------------------- 连接关系

## 网格里所有的主动技能石，按位置排序（Q 循环切换要一个稳定的顺序）
func skill_items() -> Array:
	var out: Array = []
	for it in items:
		if (it as Placed).is_skill():
			out.append(it)
	out.sort_custom(func(a: Placed, b: Placed) -> bool:
		if a.origin.y != b.origin.y:
			return a.origin.y < b.origin.y
		return a.origin.x < b.origin.x)
	return out


## 背包里所有的装备。★ 只要在背包里就生效，不需要连箭头 ★
func equip_items() -> Array:
	var out: Array = []
	for it in items:
		if (it as Placed).is_equip():
			out.append(it)
	return out


## 背包里所有装备提供的词缀合在一起（Player 会把它塞进 stats.equip_mods）
func equip_mods() -> Array:
	var out: Array = []
	for it in equip_items():
		out.append_array(((it as Placed).gem as EquipItem).build_mods())
	return out


## 箭头指着 p、**并且标签也对得上**的辅助宝石 —— 这些才是真的在辅助它。
func supports_for(p: Placed) -> Array:
	var out: Array = []
	if p == null or not p.is_skill():
		return out
	var target_cells := p.cells()
	for it in items:
		var s := it as Placed
		if not s.is_support():
			continue
		if not target_cells.has(s.arrow_target()):
			continue
		if (s.gem as SupportGem).can_support((p.gem as SkillGem).tags):
			out.append(s)
	return out


## 箭头指着 p、但标签对不上的（UI 把箭头画成红色，提示玩家"连了个寂寞"）
func blocked_for(p: Placed) -> Array:
	var out: Array = []
	if p == null or not p.is_skill():
		return out
	var target_cells := p.cells()
	for it in items:
		var s := it as Placed
		if not s.is_support():
			continue
		if not target_cells.has(s.arrow_target()):
			continue
		if not (s.gem as SupportGem).can_support((p.gem as SkillGem).tags):
			out.append(s)
	return out


## 一颗辅助宝石现在是什么状态。UI 靠它决定箭头画什么颜色。
##   "linked"  箭头指着一颗吃得下它的技能石
##   "blocked" 指着技能石，但标签不匹配
##   "idle"    没指着任何技能石
func arrow_state(s: Placed) -> String:
	if s == null or not s.is_support():
		return "idle"
	var target := at(s.arrow_target())
	if target == null or not target.is_skill():
		return "idle"
	if (s.gem as SupportGem).can_support((target.gem as SkillGem).tags):
		return "linked"
	return "blocked"


# ---------------------------------------------------------------- 存档

## 把整张网格变成纯数据（存盘用）。
## ★ 这里只产出 Dictionary，不碰文件 ★ —— 读写文件是 game/gem_save.gd 的事，
## 这样序列化本身也能脱离引擎跑单元测试。
func to_data() -> Array:
	var out: Array = []
	for it in items:
		var p := it as Placed
		out.append({
			"id": String(p.gem.id),
			"x": p.origin.x,
			"y": p.origin.y,
			"rot": p.rot,
			"level": p.gem.level,
		})
	return out


## 从存档数据还原。
##   resolve —— 传进来一个 `func(id: StringName) -> 宝石` 的回调。
##              网格自己不认识 GemLibrary（combat/ 不该依赖 data/），所以由外面告诉它。
##
## ★ 这个函数要能容忍**旧存档** ★ 玩家还在改宝石表，存档一定会和代码对不上：
##   · 存档里有已经删掉的宝石 → 跳过，不要让整个存档作废
##   · 位置冲突或越界（网格改小了、形状改大了）→ 别把宝石弄丢，随便找个空地放
## 返回成功放进去几件。
func from_data(data: Array, resolve: Callable) -> int:
	items.clear()
	var loaded := 0
	for d in data:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var gem = resolve.call(StringName(str(d.get("id", ""))))
		if gem == null:
			continue
		gem.level = gem.clamp_level(int(d.get("level", 1)))
		var origin := Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
		var rot: int = posmod(int(d.get("rot", 0)), 4)
		if place(gem, origin, rot) == null and place_anywhere(gem, rot) == null:
			continue
		loaded += 1
	return loaded


## 这颗 id 的宝石在不在网格里
func has_gem(id: StringName) -> bool:
	for it in items:
		if (it as Placed).gem.id == id:
			return true
	return false


## 把"这颗技能石 + 正在辅助它的宝石"打包成一个 GemLink 交给战斗系统
func link_for(p: Placed) -> GemLink:
	if p == null or not p.is_skill():
		return GemLink.new()
	var sups: Array = []
	for s in supports_for(p):
		sups.append((s as Placed).gem)
	return GemLink.new(p.gem as SkillGem, sups)
