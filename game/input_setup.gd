class_name InputSetup
extends RefCounted

## 用代码注册按键，而不是在"项目设置 → 输入映射"里点。
##
## 为什么？因为写在代码里你一眼就能看全，改起来也方便。
## 等按键多起来（技能栏、快捷键）再搬到项目设置里也不迟 ——
## 那时把 ensure() 删掉就行。

## 幂等：重复调用不会重复注册
static func ensure() -> void:
	_bind(&"move_left",  [KEY_A, KEY_LEFT])
	_bind(&"move_right", [KEY_D, KEY_RIGHT])
	_bind(&"move_up",    [KEY_W, KEY_UP])
	_bind(&"move_down",  [KEY_S, KEY_DOWN])
	_bind(&"cast",       [KEY_SPACE], [MOUSE_BUTTON_LEFT])
	_bind(&"toggle_debug", [KEY_TAB])
	_bind(&"restart",    [KEY_R])
	_bind(&"switch_skill", [KEY_Q])


static func _bind(action: StringName, keys: Array, buttons: Array = []) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		# 用 physical_keycode：这样换成非 QWERTY 键盘布局也是同一个物理位置
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var mb := InputEventMouseButton.new()
		mb.button_index = b
		InputMap.action_add_event(action, mb)
