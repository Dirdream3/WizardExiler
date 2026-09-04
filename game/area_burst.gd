class_name AreaBurst
extends Node2D

## 范围技能的**表现层**（ADR-030）：先画预警圈（有延迟的话），到点发 `exploded`，
## 然后画一圈扩散的冲击波、淡出、自毁。
##
## ★ 这里没有任何规则 ★ 谁在圈里、打多少，全在 World._resolve_area()（用 AreaSpec 判定）。
## 它只是"一个会画圈的计时器"：World 接 exploded 信号去结算伤害。
## 纯代码画（_draw），不需要场景文件 —— 和 HealthBar 一个思路。

signal exploded

const BURST_TIME := 0.28     ## 冲击波从 0 扩到满半径再淡掉，一共几秒
const RING_WIDTH := 3.0

var radius := 60.0
var color := Color(0.6, 0.85, 1.0)
## 预警多久（秒）。0 = 一出生就炸
var delay := 0.0
## 一共炸几次（ADR-031 的脉冲）。第一次在 delay 之后，之后每 interval 秒一次
var pulses := 1
var interval := 0.4
## 扇形画法（近战挥砍，ADR-032）：arc_deg < 360 时只画朝 facing 方向张开 arc_deg 度的扇形。
## ★ 只是画法 ★ 命中判定在 AreaSpec，仍然是整个圆
var facing := 0.0
var arc_deg := 360.0
## ★ 跟着谁走 ★（旋风斩）：非 null 时每帧把自己挪到 follow.global_position + follow_offset。
## 圈的位置由表现层维护，World 结算时读 global_position —— 所以"跟着走"对结算是透明的
var follow: Node2D = null
var follow_offset := Vector2.ZERO
## 跟着的东西没了就自己也消失（随行光环）；false = 停在原地（旋风斩的圈）
var die_with_follow := false
## ★ 贴图特效（ADR-037 补充）★ 有贴图就画贴图，没有退回画圈：
##   burst_tex —— 整圆 / 环用的爆发图（按半径缩放，淡出）
##   beam_tex  —— 锥 / 光束用的水平光束图（转到 facing、拉到长度）
##   slash     —— 近战挥砍：burst_tex 当刀光，转到 facing
var burst_tex: Texture2D = null
var beam_tex: Texture2D = null
var slash := false

enum Phase { TELEGRAPH, ACTIVE }
var _phase := Phase.TELEGRAPH
var _t := 0.0             ## 当前阶段过了多久（ACTIVE 里 = 距上一次炸过了多久）
var _pulses_left := 0     ## 还要再炸几次（不含刚炸的这一次）


func _ready() -> void:
	z_index = 5   # 压在地板上、在角色下面（不挡住怪）
	_pulses_left = maxi(1, pulses)
	if delay <= 0.0:
		_explode()


func _process(delta: float) -> void:
	if follow != null:
		if is_instance_valid(follow) and not follow.is_queued_for_deletion():
			global_position = follow.global_position + follow_offset
		elif die_with_follow:
			queue_free()
			return
		else:
			follow = null   # 施法者没了就停在原地
	_t += delta
	if _phase == Phase.TELEGRAPH:
		if _t >= delay:
			_explode()
	elif _pulses_left > 0:
		# 还有脉冲：等间隔到了再炸一次（间隔比冲击波动画短的话，动画会被打断重来，没关系）
		if _t >= interval:
			_explode()
	elif _t >= BURST_TIME:
		queue_free()
		return
	queue_redraw()


func _explode() -> void:
	_phase = Phase.ACTIVE
	_t = 0.0
	_pulses_left -= 1
	exploded.emit()
	queue_redraw()


func _draw() -> void:
	if _phase == Phase.TELEGRAPH:
		# 预警：虚一点的外圈 + 从中心慢慢涨满的实心，涨满 = 该炸了。玩家和怪都看得到
		var k := clampf(_t / maxf(0.01, delay), 0.0, 1.0)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color, 0.55), 1.5)
		draw_circle(Vector2.ZERO, radius * k, Color(color, 0.10 + 0.15 * k))
		return
	# 冲击波：半径按 ease-out 扩到满，同时淡出
	var p := clampf(_t / BURST_TIME, 0.0, 1.0)
	var eased := 1.0 - (1.0 - p) * (1.0 - p)
	var a := 1.0 - p
	# ---- 贴图版 ----
	if beam_tex != null and arc_deg < 360.0 and not slash:
		# 锥 / 光束：光束图转到朝向，长度 = 半径，宽度 = 锥的张角在末端的弦长（光束至少 22 宽）
		var half := deg_to_rad(arc_deg) * 0.5
		var length := radius * eased
		var w1 := maxf(22.0, 2.0 * radius * sin(half))   # 末端宽 = 张角在末端的弦长（光束至少 22）
		var w0 := minf(w1, 10.0)                          # 根部收细 → 真正的锥形，不是一根矩形
		draw_set_transform(Vector2.ZERO, facing, Vector2.ONE)
		# 用带 UV 的多边形把光束贴图拉成梯形：根部窄、末端宽
		var pts := PackedVector2Array([Vector2(0, -w0 * 0.5), Vector2(length, -w1 * 0.5),
				Vector2(length, w1 * 0.5), Vector2(0, w0 * 0.5)])
		var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		var tint := Color(1, 1, 1, 0.95 * a)
		draw_polygon(pts, PackedColorArray([tint, tint, tint, tint]), uvs, beam_tex)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_arc(Vector2.ZERO, radius * eased, facing - half, facing + half, 24, Color(color, 0.5 * a), 1.0)
		return
	if burst_tex != null:
		var r := radius * (0.55 + 0.45 * eased) * 1.15
		if slash:
			# 刀光：转到挥砍方向、往前挪半个半径，只画朝前的那一片
			draw_set_transform(Vector2.from_angle(facing) * radius * 0.35, facing, Vector2.ONE)
			draw_texture_rect(burst_tex, Rect2(-r, -r, 2.0 * r, 2.0 * r), false, Color(1, 1, 1, 0.9 * a))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect(burst_tex, Rect2(-r, -r, 2.0 * r, 2.0 * r), false, Color(1, 1, 1, 0.9 * a))
		# 判定圈的细边留着：玩家得知道"到底打到哪"
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color, 0.45 * a), 1.0)
		if _pulses_left > 0:
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color, 0.35), 1.0)
		return
	# ---- 退路：没有贴图时画圈 ----
	if arc_deg < 360.0:
		# 扇形：从 facing 两侧各张开一半
		var half := deg_to_rad(arc_deg) * 0.5
		var pts := PackedVector2Array([Vector2.ZERO])
		for i in 25:
			var ang := facing - half + deg_to_rad(arc_deg) * float(i) / 24.0
			pts.append(Vector2.from_angle(ang) * radius * eased)
		draw_colored_polygon(pts, Color(color, 0.22 * a))
		draw_arc(Vector2.ZERO, radius * eased, facing - half, facing + half, 24, Color(color, 0.9 * a), RING_WIDTH)
		return
	draw_circle(Vector2.ZERO, radius * eased, Color(color, 0.22 * a))
	draw_arc(Vector2.ZERO, radius * eased, 0.0, TAU, 48, Color(color, 0.9 * a), RING_WIDTH)
	if _pulses_left > 0:
		# 还会再炸：留一圈常亮的边，告诉玩家"这块地还没安全"
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color, 0.35), 1.0)
