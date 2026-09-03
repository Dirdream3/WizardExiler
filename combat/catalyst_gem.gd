class_name CatalystGem
extends SupportGem

## 触媒 —— ★ 特殊的辅助宝石（ADR-026）★
##
## 和普通辅助一样住在网格里、靠箭头连到法杖上；区别是它不给词缀，
## 而是**满足条件时自动触发**那根法杖槽里的技能：
##   · 触发没有施法动作（不占玩家的手、不吃施法间隔）
##   · 但正常消耗魔力 —— ★ 蓝不够就不触发 ★，进度保持在门槛上，回蓝后自动补
##
## 分层：这里只有**计数规则**（涨进度 / 到没到门槛 / 消耗进度），能单测。
## "事件从哪来"（命中、施加异常、移动、计时）由 game/ 喂进来；
## "触发后怎么放技能"在 Player._try_trigger / World（表现层）。

## 触发条件的种类
enum Trigger {
	SHOCK_APPLIED,    ## 施加感电 N 次
	IGNITE_APPLIED,   ## 施加点燃 N 次
	CHILL_APPLIED,    ## 施加冰缓 N 次（本项目的冰系异常是冰缓，没有"冰冻"状态）
	HITS,             ## 投射物击中敌人 N 次
	MOVE_DISTANCE,    ## 玩家移动 N 像素（「格」按 16px 一块地砖换算）
	INTERVAL,         ## 每 N 秒
}

## 「移动 N 格」的一格 = 一块 16×16 的地砖（pixel_art.floor_tile 的尺寸）
const PIXELS_PER_TILE := 16.0

var trigger_kind: int = Trigger.HITS
## 触发门槛。计数类 = 次数；MOVE_DISTANCE = 像素；INTERVAL = 秒
var threshold: float = 5.0
## 当前进度（次 / 像素 / 秒）。每颗触媒实例各自计数
var progress: float = 0.0


## 喂一个事件进来。种类对不上就无视。
## ★ 进度封顶在门槛上 ★ —— 蓝不够时不许把进度攒成好几次触发，
##   否则回一口蓝就连环爆发，触媒的"节奏感"就没了。
func advance(kind: int, amount: float = 1.0) -> void:
	if kind != trigger_kind:
		return
	progress = minf(progress + amount, threshold)


## 进度到门槛了吗（到了就该尝试触发；触发失败进度不清，下次再试）
func ready_to_fire() -> bool:
	return progress >= threshold


## 触发成功后调：清掉进度，重新攒
func consume() -> void:
	progress = 0.0


## 触发条件的人话（面板 / 飘字用）
func trigger_text() -> String:
	match trigger_kind:
		Trigger.SHOCK_APPLIED:  return "施加感电 %d 次" % int(threshold)
		Trigger.IGNITE_APPLIED: return "施加点燃 %d 次" % int(threshold)
		Trigger.CHILL_APPLIED:  return "施加冰缓 %d 次" % int(threshold)
		Trigger.HITS:           return "击中敌人 %d 次" % int(threshold)
		Trigger.MOVE_DISTANCE:  return "移动 %d 格" % int(threshold / PIXELS_PER_TILE)
		Trigger.INTERVAL:       return "每 %.0f 秒" % threshold
	return "?"


## 当前进度的人话（面板用）
func progress_text() -> String:
	match trigger_kind:
		Trigger.MOVE_DISTANCE:
			return "%.0f / %.0f 格" % [progress / PIXELS_PER_TILE, threshold / PIXELS_PER_TILE]
		Trigger.INTERVAL:
			return "%.1f / %.0f 秒" % [progress, threshold]
	return "%d / %d 次" % [int(progress), int(threshold)]


func tooltip() -> String:
	var l := PackedStringArray()
	l.append("[b][color=#c08fe0]%s[/color][/b]  [color=#9a9aac]触媒[/color]" % display_name)
	l.append("[color=#c8a24a]触发条件：%s[/color]" % trigger_text())
	if description != "":
		l.append("[color=#8a8a9c]%s[/color]" % description)
	l.append("[color=#7a7a8c]────────────[/color]")
	l.append("魔力消耗倍率 [b]×%.2f[/b]" % mana_multiplier)
	l.append("当前进度：[b]%s[/b]" % progress_text())
	l.append("[color=#7a7a8c]箭头指着法杖 → 条件达成时自动触发槽里的技能。")
	l.append("触发没有施法动作，但正常消耗魔力；蓝不够就不触发。[/color]")
	return "\n".join(l)
