class_name UIHelper
extends RefCounted

## 左侧面板和 HUD 都要用的几个小工具，放一起免得两边各抄一份。


## 带描边的小号文字标签。像素背景上不描边会糊成一团。
static func label(text: String, size: int, color: Color, outline: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = color
	if outline:
		ls.outline_size = 3
		ls.outline_color = Color(0.04, 0.04, 0.06, 0.85)
	l.label_settings = ls
	return l


## 宝石在格子里显示的那 1 个字
static func gem_short(gem) -> String:
	return "?" if gem == null else String(gem.short_name)


## 图标资源路径的缓存：id → Texture2D 或 null（null 也要记住，别每帧都去查文件）
static var _icon_cache: Dictionary = {}


## 宝石/装备的图标文件路径。没有对应文件时返回 ""。
## ★ 图标按 id 找（assets/icons/<id>.webp），和颜色一样是 UI 层的映射 ★
##   —— combat/ 和 data/ 里不放任何资源路径，加一件新内容只要丢一张同名图进目录。
static func icon_path(gem) -> String:
	if gem == null:
		return ""
	var path := "res://assets/icons/%s.webp" % String(gem.id)
	return path if ResourceLoader.exists(path, "Texture2D") else ""


## 宝石/装备的图标贴图。没有图标返回 null，调用方退回文字短名 ——
## 新加的内容还没画图时，格子上至少有个字，不会变成无名色块。
static func gem_icon(gem) -> Texture2D:
	if gem == null:
		return null
	var id := String(gem.id)
	if not _icon_cache.has(id):
		var path := icon_path(gem)
		_icon_cache[id] = load(path) if path != "" else null
	return _icon_cache[id]


## 格子的颜色：装备金褐色，辅助宝石绿色，主动技能石按元素分色。
## ★ 颜色从类型和标签算出来，而不是写在数据里 ★ —— combat/ 那边不该关心怎么画。
static func gem_color(gem) -> Color:
	if gem == null:
		return Color(0.13, 0.13, 0.18)
	if gem is EquipItem:
		if (gem as EquipItem).is_weapon():
			return Color(0.62, 0.62, 0.72)   # 近战武器：铁灰，和法杖 / 防具的金褐分开
		return Color(0.72, 0.60, 0.36)
	if gem is CatalystGem:
		return Color(0.62, 0.45, 0.78)   # 触媒：紫色，和普通辅助的绿区分开
	if gem is SupportGem:
		match (gem as SupportGem).tier:
			SupportGem.Tier.SUBLIME:
				return Color(0.82, 0.68, 0.30)   # 崇高：金色（ADR-031）
			SupportGem.Tier.LINEAGE:
				return Color(0.80, 0.34, 0.46)   # 血脉：绯红
		return Color(0.46, 0.72, 0.40)
	var tags: int = gem.tags
	if tags & CombatTags.FIRE:
		return Color(0.90, 0.55, 0.26)
	if tags & CombatTags.LIGHTNING:
		return Color(0.52, 0.66, 0.96)
	if tags & CombatTags.COLD:
		return Color(0.48, 0.80, 0.90)
	if tags & CombatTags.CHAOS:
		return Color(0.62, 0.78, 0.36)   # 混沌：病绿（PoE 的混沌配色），和辅助的草绿略偏黄区分
	return Color(0.70, 0.70, 0.78)


## 离玩家最近的活着的敌人（DPS 面板要拿它当"打谁"的样本）。
static func nearest_enemy(tree: SceneTree, player: Player) -> Enemy:
	if tree == null or player == null:
		return null
	var best: Enemy = null
	var best_d := INF
	for n in tree.get_nodes_in_group(&"enemy"):
		if not is_instance_valid(n):
			continue
		var e := n as Enemy
		if e == null or e.stats == null or not e.stats.is_alive():
			continue
		var d := e.global_position.distance_squared_to(player.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best
