class_name GemSave
extends RefCounted

## 背包存档：把网格摆法 + 宝石等级写进 `user://`，下次进游戏原样恢复。
##
## ★ 为什么必须有 ★ 加了网格背包之后，"怎么摆"就是构筑本身。
##   不存盘的话每次按 R 重开、每次关掉游戏，辛辛苦苦摆的一套就全没了。
##
## 存的是 **JSON**，不是二进制：
##   · 你可以直接打开看、手改、出问题时一眼知道哪不对
##   · 文件在 `%APPDATA%\Godot\app_userdata\PoE-like ARPG\backpack.json`
##
## ★ 分工 ★ 序列化在 `GemGrid.to_data() / from_data()`（纯逻辑，能单测），
##   这个文件只负责读写文件 + 把 id 翻译成宝石（要用 GemLibrary）。

## 存档路径。★ 是 static var 不是 const ★ —— 冒烟测试要把它指到别的文件上，
## 免得跑一次测试就把玩家真正的背包覆盖了。
static var path := "user://backpack.json"
## 存档格式版本。以后格式变了，靠它决定是升级还是直接丢弃重来。
## 版本 2：法杖成了技能载体（技能石住进法杖槽），旧存档直接退回默认摆法。
const VERSION := 2

## ★ 测试用的总开关 ★ 冒烟测试大部分时间会把它关掉。
static var autosave := true


static func has_save() -> bool:
	return FileAccess.file_exists(path)


static func clear() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 把玩家当前的背包写进存档。autosave 关掉时什么也不做。
static func save(player: Player) -> bool:
	if not autosave or player == null:
		return false
	# ★ 存的是"当前技能是哪颗宝石"，不是下标 ★
	#   skill_index 是 skill_items() 里的位置，而那个列表是**按摆放位置排序**的 ——
	#   挪一下法杖、或者补进一根新的，同一个下标就指到别人身上去了。
	#   active_item 是法杖，真正的技能宝石在它的槽里（skill_gem()）。
	var active := player.active_item()
	var active_gem: SkillGem = active.skill_gem() if active != null else null
	var data := {
		"version": VERSION,
		"skill_id": String(active_gem.id) if active_gem != null else "",
		"items": player.grid.to_data(),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("背包存档写不进去：%s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


## 把存档读进玩家的背包。没有存档 / 读不出来 / 版本对不上 → 返回 false，
## 调用方（Player）就会退回去铺默认摆法。
static func load_into(player: Player) -> bool:
	if player == null or not has_save():
		return false

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var raw := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("背包存档读不懂，按默认摆法重来")
		return false
	if int(parsed.get("version", 0)) != VERSION:
		push_warning("背包存档是旧版本的，按默认摆法重来")
		return false

	var items = parsed.get("items", [])
	if typeof(items) != TYPE_ARRAY:
		return false

	var loaded := player.grid.from_data(items, resolve)
	if loaded == 0:
		return false      # 一件都没还原出来，等于没存档

	# ★ 存档之后新加的宝石要自动补进来 ★
	#   你在 gem_library.gd 里加了一颗新辅助，不该因为老存档里没有就永远见不到它。
	fill_missing(player.grid)

	# 按 id 找回"上次在用哪颗技能"（找不到就用第一颗）。
	# skill_items() 是"镶着宝石的法杖"，比对的是槽里宝石的 id。
	player.skill_index = 0
	var want := StringName(str(parsed.get("skill_id", "")))
	if want != &"":
		var skills := player.grid.skill_items()
		for i in skills.size():
			var sg := (skills[i] as GemGrid.Placed).skill_gem()
			if sg != null and sg.id == want:
				player.skill_index = i
				break
	return true


## 存档里只有 id，按 id 造回实物。宝石和装备都要找。
static func resolve(id: StringName):
	var g = GemLibrary.make_gem(id)
	if g != null:
		return g
	return EquipLibrary.make_item(id)


## 图鉴里所有能放进背包的东西（宝石 + 装备）
static func everything() -> Array:
	var out: Array = []
	out.append_array(GemLibrary.all_gems())
	out.append_array(EquipLibrary.all_items())
	return out


## 把图鉴里有、但网格里还没有的东西补进空地。
static func fill_missing(grid: GemGrid) -> int:
	var added := 0
	for thing in everything():
		if grid.has_gem(thing.id):
			continue
		if grid.place_anywhere(thing) != null:
			added += 1
	return added
