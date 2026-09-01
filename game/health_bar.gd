class_name HealthBar
extends Node2D

## 怪物头顶的血条。用 _draw() 画两个矩形，比拉 ProgressBar 节点轻得多。

@export var width: float = 16.0
@export var height: float = 2.0

var _ratio: float = 1.0


func set_ratio(v: float) -> void:
	var nv := clampf(v, 0.0, 1.0)
	if is_equal_approx(nv, _ratio):
		return
	_ratio = nv
	queue_redraw()   # 只有数值真的变了才重画


func _draw() -> void:
	var half := width * 0.5
	# 外框 + 底
	draw_rect(Rect2(-half - 1.0, -1.0, width + 2.0, height + 2.0), Color(0.07, 0.06, 0.09, 0.9))
	if _ratio <= 0.0:
		return
	# 血量：满血偏绿，残血偏红
	var col := Color(0.85, 0.22, 0.22).lerp(Color(0.45, 0.78, 0.35), _ratio)
	draw_rect(Rect2(-half, 0.0, width * _ratio, height), col)
