class_name FloatingText
extends RefCounted

## 伤害飘字。纯代码生成，不需要场景文件。

static var _settings_cache: Dictionary = {}


## 在 parent 下的 world_pos 处飘一个字，向上飘同时淡出。
static func spawn(parent: Node, world_pos: Vector2, text: String, color: Color, big: bool = false) -> void:
	var lbl := Label.new()
	lbl.text = text
	# 字号偏小是故意的：飘字在世界坐标里，会跟着摄像机 zoom 一起放大
	lbl.label_settings = _settings(color, 9 if big else 7)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(60, 0)
	# Label 是 Control，宽 60 居中对齐 → 左移一半就正好落在目标点正上方
	lbl.position = world_pos - Vector2(30, 0)
	lbl.z_index = 100
	parent.add_child(lbl)

	# 稍微左右抖一点，同一帧的多个飘字才不会完全重叠
	var drift := randf_range(-6.0, 6.0)
	var t := lbl.create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "position", lbl.position + Vector2(drift, -20.0), 0.75) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(lbl, "modulate:a", 0.0, 0.4).set_delay(0.35)
	t.set_parallel(false)
	t.tween_callback(lbl.queue_free)


static func _settings(color: Color, size: int) -> LabelSettings:
	var key := "%s_%d" % [color.to_html(), size]
	if not _settings_cache.has(key):
		var ls := LabelSettings.new()
		ls.font_size = size
		ls.font_color = color
		ls.outline_size = 2
		ls.outline_color = Color(0.05, 0.04, 0.07, 0.9)
		_settings_cache[key] = ls
	return _settings_cache[key]
