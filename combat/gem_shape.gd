class_name GemShape
extends RefCounted

## 宝石在背包网格里占的**形状 + 朝向**（背包乱斗那种）。
##
## ★ 这里的 Vector2i 是"第几列第几行"，不是屏幕像素 ★
##   所以它仍然是纯逻辑，能脱离引擎跑单元测试 —— 别把它当成场景坐标用。
##
## 坐标系和屏幕一致：x 向右，y 向下。所以"顺时针转 90°"是 (x, y) → (-y, x)：
##   右(1,0) → 下(0,1) → 左(-1,0) → 上(0,-1)

## 旋转档位对应的朝向：0=右 1=下 2=左 3=上
const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

## 未旋转时占的格子（相对左上角）
var cells: Array[Vector2i] = []
## 有没有箭头。辅助宝石有，主动技能石没有
var has_arrow: bool = false
## 未旋转时箭头从哪一格射出
var arrow_cell: Vector2i = Vector2i.ZERO


## w×h 的矩形，没有箭头。装备用这个（法杖 1×3、头盔 2×2……）。
static func rect(w: int, h: int) -> GemShape:
	var s := GemShape.new()
	for y in maxi(1, h):
		for x in maxi(1, w):
			s.cells.append(Vector2i(x, y))
	return s


## n×n 的方块，没有箭头。
static func square(n: int) -> GemShape:
	return rect(n, n)


## 一格 + 一个朝右的箭头。辅助宝石用这个。
##
## ★ 只占一格，所以旋转**只改朝向、不改占位** ★
##   取舍不在宝石身上，而在装备身上 —— 装备又大又占地方，
##   想给技能石留出四面的箭头位，就得把装备摆得刁钻一点。
static func arrow_single() -> GemShape:
	var s := GemShape.new()
	s.cells.append(Vector2i(0, 0))
	s.has_arrow = true
	s.arrow_cell = Vector2i(0, 0)
	return s


## 转 rot 次 90°（顺时针）之后占的格子，已经归一化到左上角为 (0,0)。
func cells_at(rot: int) -> Array[Vector2i]:
	var rotated := _rotate_all(rot)
	var corner := _min_corner(rotated)
	var out: Array[Vector2i] = []
	for c in rotated:
		out.append(c - corner)
	return out


## 转 rot 次之后，箭头从哪一格射出（同样归一化过）。
func arrow_cell_at(rot: int) -> Vector2i:
	var corner := _min_corner(_rotate_all(rot))
	return rotate_cell(arrow_cell, rot) - corner


## 转 rot 次之后箭头指向哪个方向。
func facing(rot: int) -> Vector2i:
	return DIRS[posmod(rot, DIRS.size())]


## 外接矩形有多大（UI 画预览要用）
func size_at(rot: int) -> Vector2i:
	var maxc := Vector2i.ZERO
	for c in cells_at(rot):
		maxc.x = maxi(maxc.x, c.x)
		maxc.y = maxi(maxc.y, c.y)
	return maxc + Vector2i.ONE


## 把一个格子转 rot 次 90°（顺时针）。
static func rotate_cell(c: Vector2i, rot: int) -> Vector2i:
	var v := c
	for i in posmod(rot, 4):
		v = Vector2i(-v.y, v.x)
	return v


# ---------------------------------------------------------------- 内部

func _rotate_all(rot: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		out.append(rotate_cell(c, rot))
	return out


static func _min_corner(list: Array[Vector2i]) -> Vector2i:
	if list.is_empty():
		return Vector2i.ZERO
	var m := list[0]
	for c in list:
		m.x = mini(m.x, c.x)
		m.y = mini(m.y, c.y)
	return m
