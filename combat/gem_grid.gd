class_name GemGrid
extends RefCounted

## 背包网格（背包乱斗那种）。
##
## ★★ 连接关系 = 摆放位置 + 法杖载体（ADR-006 / ADR-020）★★
##
##   · 法杖是**技能的载体**：每根法杖带一个镶嵌槽位，技能宝石镶进去才能施放。
##     裸放在网格里的技能宝石只是库存，不能施放、也吃不到辅助。
##   · 辅助宝石身上有一个箭头，**箭头指着法杖的哪一格都行** ——
##     指着法杖 = 辅助它槽里镶着的那颗技能宝石。
##   · 法杖占多格（1×2 / 1×3）→ 周身的箭头位比 1 格的宝石多得多，
##     更长的法杖 = 更多"连线面积"，这就是换法杖的意义。
##
##   规则全是几何的、纯逻辑的，能单测。
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

	## 裸放在网格里的技能宝石（只是库存，不能施放）
	func is_skill() -> bool:
		return gem is SkillGem

	func is_equip() -> bool:
		return gem is EquipItem

	## 带镶嵌槽的法杖（技能的载体）
	func is_wand() -> bool:
		return gem is EquipItem and (gem as EquipItem).has_socket()

	## 这一件"现在能施放的技能宝石"：法杖返回槽里镶着的那颗，其它返回 null。
	## 存档记"当前技能"、UI 画等级角标都走这里，别到处 as 来 as 去。
	func skill_gem() -> SkillGem:
		if is_wand():
			return (gem as EquipItem).socketed
		return null


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


# ---------------------------------------------------------------- 合成

## ★ 合成：把手上的宝石叠到一颗**同 id** 的宝石上 → 手上的被吃掉，那颗升 1 级 ★
## 返回能合成的目标；不构成合成（不同 id / 是装备 / 目标满级）返回 null。
##   · 只有宝石能合 —— 装备 max_level = 1，没有"升级"可言
##   · 为什么放在这里而不是 UI：能不能合是背包规则，和"能不能放"一样要能单测
func merge_target(gem, origin: Vector2i) -> Placed:
	if gem == null or gem is EquipItem:
		return null
	var p := at(origin)
	if p == null or p.gem == gem or p.is_equip():
		return null
	if p.gem.id != gem.id:
		return null
	if p.gem.level >= p.gem.max_level:
		return null
	return p


## 同 id 但合不了时给 UI 的原因。返回 "" 表示这里不构成合成场景
## （不同 id / 空格子），调用方接着走普通的放置判定。
func merge_reject_reason(gem, origin: Vector2i) -> String:
	if gem == null or gem is EquipItem:
		return ""
	var p := at(origin)
	if p == null or p.gem == gem or p.is_equip() or p.gem.id != gem.id:
		return ""
	# max_level = 1 的东西（辅助宝石）压根没有等级概念，不给"满级"的说法 ——
	# 走普通放置判定报"那里已经有东西了"就够了
	if p.gem.max_level <= 1:
		return ""
	if p.gem.level >= p.gem.max_level:
		return "「%s」已经满级，合成不了" % p.gem.display_name
	return ""


## 执行合成：目标升到 max(两边等级) + 1，封顶在 max_level。
##   取 max 而不是相加 —— 吃掉低级的不亏、吃掉同级的稳赚 1 级，
##   但堆一把 1 级宝石不能直接堆出满级（相加就成刷级机器了）。
## ★ 手上那颗就此消失，调用方负责别再把它放回网格 ★
func merge(gem, target: Placed) -> void:
	target.gem.level = target.gem.clamp_level(maxi(int(target.gem.level), int(gem.level)) + 1)


# ---------------------------------------------------------------- 镶嵌

## ★ 镶嵌：把手上的技能宝石点到一根法杖上 = 镶进它的槽位 ★
## 返回那根法杖的 Placed；不构成镶嵌（手上不是技能宝石 / 那里不是法杖）返回 null。
## 为什么放在这里而不是 UI：能不能镶和能不能放一样是背包规则，必须能单测。
func socket_target(gem, origin: Vector2i) -> Placed:
	if not (gem is SkillGem):
		return null
	var p := at(origin)
	if p == null or not p.is_wand():
		return null
	return p


## 构成镶嵌场景但镶不进去时给 UI 的原因。返回 "" 表示可以镶（含合成 / 交换）。
func socket_reject_reason(gem, origin: Vector2i) -> String:
	var p := socket_target(gem, origin)
	if p == null:
		return ""
	var item := p.gem as EquipItem
	# ★ 槽的类型要对（ADR-032）★ 法术镶法杖、攻击镶武器 —— 载体决定技能类型
	if not item.accepts_gem(gem as SkillGem):
		return "「%s」的槽只收%s，「%s」镶不进去" % [item.display_name, item.socket_kind_name(), gem.display_name]
	var cur := item.socketed
	if cur != null and cur.id == gem.id and cur.level >= cur.max_level:
		return "「%s」已经满级，合成不了" % cur.display_name
	return ""


## 执行镶嵌。三种结果：
##   · 槽是空的        → 镶进去，返回 null（手上的宝石就此住进法杖）
##   · 槽里是同款宝石  → 合成升级（规则同网格叠放：max 两边等级 +1），返回 null
##   · 槽里是别的宝石  → 交换，返回被换出来的旧宝石（调用方把它放回手上）
func socket(gem, wand: Placed):
	var item := wand.gem as EquipItem
	var cur := item.socketed
	if cur != null and cur.id == gem.id:
		cur.level = cur.clamp_level(maxi(int(cur.level), int(gem.level)) + 1)
		return null
	item.socketed = gem
	return cur


# ---------------------------------------------------------------- 连接关系

## ★ 网格里所有「镶着技能宝石的法杖」——它们就是现在能施放的技能 ★
## 按位置排序（Q 循环切换要一个稳定的顺序）。裸放的技能宝石不算：它没有载体。
func skill_items() -> Array:
	var out: Array = []
	for it in items:
		var p := it as Placed
		if p.is_wand() and p.skill_gem() != null:
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


## 背包里所有**普通装备**提供的词缀合在一起（Player 会把它塞进 stats.equip_mods）。
## ★ 法杖不在这层（ADR-023）★ —— 法杖的词缀只对槽里镶着的技能生效，
##   由 link_for() 连同辅助宝石一起塞进 skill_mods，Q 切法杖时整层跟着换。
func equip_mods() -> Array:
	var out: Array = []
	for it in equip_items():
		var p := it as Placed
		if p.is_wand():
			continue
		out.append_array((p.gem as EquipItem).build_mods())
	return out


## 箭头指着法杖 p、**并且标签也对得上**槽里技能的辅助宝石 —— 这些才是真的在辅助它。
## ★ 指着法杖的任意一格都算 ★ 法杖越长，能围上来的箭头越多。
func supports_for(p: Placed) -> Array:
	var out: Array = []
	if p == null or not p.is_wand():
		return out
	var sg := p.skill_gem()
	if sg == null:
		return out
	var target_cells := p.cells()
	for it in items:
		var s := it as Placed
		if not s.is_support():
			continue
		if not target_cells.has(s.arrow_target()):
			continue
		if (s.gem as SupportGem).can_support(sg.tags):
			out.append(s)
	return out


## 箭头指着法杖 p、但标签对不上槽里技能的（UI 画红箭头，提示玩家"连了个寂寞"）
func blocked_for(p: Placed) -> Array:
	var out: Array = []
	if p == null or not p.is_wand():
		return out
	var sg := p.skill_gem()
	if sg == null:
		return out
	var target_cells := p.cells()
	for it in items:
		var s := it as Placed
		if not s.is_support():
			continue
		if not target_cells.has(s.arrow_target()):
			continue
		if not (s.gem as SupportGem).can_support(sg.tags):
			out.append(s)
	return out


## 一颗辅助宝石现在是什么状态。UI 靠它决定箭头画什么颜色。
##   "linked"  箭头指着一根法杖，槽里的技能吃得下它
##   "blocked" 指着法杖，但槽里技能的标签不匹配
##   "idle"    没指着法杖，或法杖的槽还空着（镶上宝石会自动连上）
## ★ 裸放的技能宝石不参与连线 ★ —— 它没有载体，指着它和指着空地一样。
func arrow_state(s: Placed) -> String:
	if s == null or not s.is_support():
		return "idle"
	var target := at(s.arrow_target())
	if target == null or not target.is_wand():
		return "idle"
	var sg := target.skill_gem()
	if sg == null:
		return "idle"
	if (s.gem as SupportGem).can_support(sg.tags):
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
		var entry := {
			"id": String(p.gem.id),
			"x": p.origin.x,
			"y": p.origin.y,
			"rot": p.rot,
			"level": p.gem.level,
		}
		# 法杖槽里镶着的宝石跟着法杖一起存（它不占网格格子，只存在装备身上）
		var sg := p.skill_gem()
		if sg != null:
			entry["socket"] = {"id": String(sg.id), "level": sg.level}
		out.append(entry)
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
		# 法杖槽里的宝石：镶回去。宝石表改了、id 不认识 → 槽空着，法杖照常还原
		if gem is EquipItem and (gem as EquipItem).has_socket() \
				and typeof(d.get("socket")) == TYPE_DICTIONARY:
			var sd: Dictionary = d.get("socket")
			var sub = resolve.call(StringName(str(sd.get("id", ""))))
			if sub is SkillGem:
				sub.level = sub.clamp_level(int(sd.get("level", 1)))
				(gem as EquipItem).socketed = sub
		var origin := Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
		var rot: int = posmod(int(d.get("rot", 0)), 4)
		if place(gem, origin, rot) == null and place_anywhere(gem, rot) == null:
			continue
		loaded += 1
	return loaded


## 这颗 id 的宝石在不在网格里。★ 镶在法杖槽里的也算 ★
## （GemSave 的"图鉴自动补齐"靠它判重，漏了槽里的会每次读档都多补一颗）
func has_gem(id: StringName) -> bool:
	for it in items:
		var p := it as Placed
		if p.gem.id == id:
			return true
		var sg := p.skill_gem()
		if sg != null and sg.id == id:
			return true
	return false


## 玩家"拥有"的全部宝石：裸放的 + 镶在法杖里的（不含装备本身）。
## 局模式的升级奖励从这里挑候选 —— 镶进法杖的宝石也得能升级。
func owned_gems() -> Array:
	var out: Array = []
	for it in items:
		var p := it as Placed
		if p.is_equip():
			var sg := p.skill_gem()
			if sg != null:
				out.append(sg)
		else:
			out.append(p.gem)
	return out


## 把"法杖槽里的技能宝石 + 法杖本身 + 正在辅助它的宝石"打包成一个 GemLink。
## 法杖也进来，因为它的词缀只对槽里的技能生效（走 skill_mods，见 ADR-023）。
func link_for(p: Placed) -> GemLink:
	if p == null or not p.is_wand():
		return GemLink.new()
	var sg := p.skill_gem()
	if sg == null:
		return GemLink.new()
	var sups: Array = []
	for s in supports_for(p):
		sups.append((s as Placed).gem)
	return GemLink.new(sg, sups, p.gem as EquipItem)
