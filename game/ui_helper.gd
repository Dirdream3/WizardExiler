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


## 格子的颜色：装备金褐色，辅助宝石绿色，主动技能石按元素分色。
## ★ 颜色从类型和标签算出来，而不是写在数据里 ★ —— combat/ 那边不该关心怎么画。
static func gem_color(gem) -> Color:
	if gem == null:
		return Color(0.13, 0.13, 0.18)
	if gem is EquipItem:
		return Color(0.72, 0.60, 0.36)
	if gem is SupportGem:
		return Color(0.46, 0.72, 0.40)
	var tags: int = gem.tags
	if tags & CombatTags.FIRE:
		return Color(0.90, 0.55, 0.26)
	if tags & CombatTags.LIGHTNING:
		return Color(0.52, 0.66, 0.96)
	if tags & CombatTags.COLD:
		return Color(0.48, 0.80, 0.90)
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
