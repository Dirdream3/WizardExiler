class_name RunSession
extends RefCounted

## 当前这一局的"全局插座" + 局存档。
##
## ★ 为什么用 static var 而不是 autoload ★
##   World 和 Player 在两棵不同的节点树时序里初始化（Player._ready 在
##   _spawn_player 里被触发），谁先谁后不好把握。class_name 的 static var
##   不依赖场景树，谁都随时拿得到，而且冒烟测试能在加载场景**之前**改它。
##
## ★ 分工和 GemSave 一模一样 ★
##   序列化在 RunState.to_data() / GemGrid.to_data()（纯逻辑，已单测），
##   这个文件只负责拼 JSON、读写文件、把 id 翻译回实物。
##
## 局存档和沙盒背包存档（backpack.json）是**两个文件**：
##   局模式下背包内容属于这一局，不该和沙盒模式的背包互相污染。

## 总开关：true = 游戏按"7 步地图"的局模式跑；false = 老的沙盒模式。
## 冒烟测试的前半段测沙盒行为，会把它关掉。
static var enabled := true

## 测试用：>= 0 时新开局固定用这个种子（可复现），< 0 用随机种子
static var force_seed := -1

static var autosave := true
static var path := "user://run.json"
## 版本 2：法杖成了技能载体（背包里的技能石搬进了法杖槽）+ 局分 4 层。
## 旧存档的裸技能石在新规则下放不出技能，直接判旧版、开新局。
const VERSION := 2

## 当前这一局。World._ready 里 prepare() 之后保证非 null（局模式下）。
static var state: RunState = null

## 读档暂存：Player._ready 比 World 拿到 player 引用更早，
## 所以背包数据先存这里，等 Player._setup_gems 自己来取。
static var _pending_items: Array = []
static var _pending_skill := ""


# ---------------------------------------------------------------- 开局

## 进场景时调：有存档就续上局，没有就开新局。
static func prepare() -> void:
	state = null
	_pending_items = []
	_pending_skill = ""
	if _load_file():
		return
	_new_run()


## 开一局全新的（清掉旧存档）。死亡/通关后按 R 重开走的就是这条。
static func _new_run() -> void:
	# 用毫秒时间戳当随机种子（& 0x7FFFFFFF 保证非负）。
	# ★ 不写 abs() ★ —— 它返回 Variant，:= 推断类型会被当警告转错误
	var seed_v: int = force_seed if force_seed >= 0 else (int(Time.get_unix_time_from_system() * 1000.0) & 0x7FFFFFFF)
	state = RunState.start(seed_v)
	_pending_items = []
	_pending_skill = ""


## 给玩家铺开局背包。
## ★ 局模式下不走 GemSave：没有默认摆法、没有"图鉴自动补齐"★ ——
##   开局就是一根法杖 + 镶在里面的一颗技能石，其它一切靠地图上打出来 / 买回来。
##   （法杖是技能载体，光给宝石放不出技能 —— 所以必须成对给，见 ADR-020）
static func setup_backpack(player: Player) -> void:
	if not _pending_items.is_empty():
		var loaded := player.grid.from_data(_pending_items, GemSave.resolve)
		if loaded > 0:
			_restore_skill(player)
			return
	# 没有存档（或存档全坏）→ 初始背包：一根见习法杖，槽里镶着开局宝石
	var wand = EquipLibrary.make_item(RunContent.STARTING_WAND)
	var gem = GemLibrary.make_gem(RunContent.STARTING_GEM)
	if gem != null:
		gem.level = gem.clamp_level(RunContent.STARTING_LEVEL)
	if wand != null:
		(wand as EquipItem).socketed = gem
		if player.grid.place(wand, Vector2i(GemGrid.WIDTH / 2, GemGrid.HEIGHT / 2 - 1), 0) == null:
			player.grid.place_anywhere(wand)
	player.skill_index = 0


# ---------------------------------------------------------------- 存档

## 把"这一局的进度 + 背包"一起写盘。背包一变、每走一步都会被调。
static func save(player: Player) -> bool:
	if not autosave or state == null or player == null:
		return false
	# ★ 存的是"当前用的那颗技能宝石"的 id ★（active_item 是法杖，宝石在槽里）
	var active := player.active_item()
	var active_gem: SkillGem = active.skill_gem() if active != null else null
	var data := {
		"version": VERSION,
		"run": state.to_data(),
		"skill_id": String(active_gem.id) if active_gem != null else "",
		"items": player.grid.to_data(),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("局存档写不进去：%s" % error_string(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


## 整局结束（胜利或阵亡）→ 删掉局存档，下次按 R 就是新的一局。
static func clear_save() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## ★ 放弃当前局（R 键重开走这条）★
## 删掉局存档、清掉内存里的局状态 —— 之后 prepare() 找不到存档，必然开全新的一局。
## 光 reload 场景是不够的：局有自动存档，重载后会续档回到当前步，
## 那只是"重打这一步"，不是玩家要的"重开一整局"。
static func abandon() -> void:
	clear_save()
	state = null
	_pending_items = []
	_pending_skill = ""


static func _load_file() -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var raw := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("局存档读不懂，开新的一局")
		return false
	if int(parsed.get("version", 0)) != VERSION:
		push_warning("局存档是旧版本的，开新的一局")
		return false
	if typeof(parsed.get("run")) != TYPE_DICTIONARY:
		return false

	var s := RunState.from_data(parsed.get("run"))
	if s == null or s.is_over():
		return false    # 上一局已经结束了还留着存档 → 当没有

	state = s
	var items = parsed.get("items", [])
	_pending_items = items if typeof(items) == TYPE_ARRAY else []
	_pending_skill = str(parsed.get("skill_id", ""))
	return true


static func _restore_skill(player: Player) -> void:
	player.skill_index = 0
	var want := StringName(_pending_skill)
	if want == &"":
		return
	# skill_items() 是"镶着宝石的法杖"，按槽里宝石的 id 找回上次在用哪根
	var skills := player.grid.skill_items()
	for i in skills.size():
		var sg := (skills[i] as GemGrid.Placed).skill_gem()
		if sg != null and sg.id == want:
			player.skill_index = i
			break
