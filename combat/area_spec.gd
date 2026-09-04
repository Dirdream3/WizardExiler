class_name AreaSpec
extends RefCounted

## 一次**范围技能**的行为参数 —— 由「技能基础值 + 角色词缀」算出来（ADR-030）。
##
## 和 ProjectileSpec 是平行的两条管线：
##   投射物 = 飞出去、撞到谁算谁
##   范围   = 以某个点为中心画一个圈，圈里的**全部**目标同时结算一次命中
## 新星（围着自己炸）、风暴呼唤（鼠标点上延迟落雷）都走这里，**不再**用一圈投射物冒充。
##
## ★ 这个类里不许出现 Vector2 / 场景坐标 ★
##   谁在圈里，由表现层把 [{id, dist}] 喂进来、这里只比大小 —— 和弹射选目标一个做法。
##   保持零引擎依赖，才能跑单元测试。


## 范围以谁为中心
enum Origin {
	SELF,     ## 施法者脚下（新星）：不用瞄准
	TARGET,   ## 鼠标指的点（风暴呼唤）：最远 range 像素，超出就夹到边上
	FRONT,    ## ★ 面前 range 像素处（近战挥砍，ADR-032）★ 朝向由鼠标定，距离固定 = 武器够得着的地方
}

var radius: float = 60.0          ## 半径（像素）—— 已经吃过「范围效果」加成
var origin: int = Origin.SELF
var delay: float = 0.0            ## 落地延迟（秒）。0 = 瞬发。吃「持续时间」加成（PoE 的风暴呼唤就是这样）
var range: float = 0.0            ## TARGET 模式的最大施放距离（像素）
var pulses: int = 1               ## 圈炸几次（≥1）。已经吃过「脉冲次数」和「持续时间」
var interval: float = 0.4         ## 两次脉冲的间隔（秒）
var cascade: int = 0              ## 沿施法方向额外几个圈（ADR-031 的「连环范围」）
var follow: bool = false          ## 圈跟着施法者走（旋风斩）。表现层每帧把圈挪到施法者身上
var arc_deg: float = 360.0        ## 扇形角（ADR-034）。< 360 时只有朝向两侧各 arc/2 度以内的目标算在圈里
var inner_radius: float = 0.0     ## 环形（ADR-036）：比它近的不算。和外半径一起按面积平方根缩放，环的比例不变


## 从施法者的属性 + 技能基础值构建。
static func build(attacker: CombatEntity, skill: SkillSpec) -> AreaSpec:
	var s := AreaSpec.new()
	var tags := skill.hit_tags()

	# ★ 「范围效果提高 50%」提高的是**面积**，半径按平方根放大 ★（PoE 的口径）
	#   要是直接乘半径，+100% 就是 4 倍面积，「增大范围」辅助会强得离谱。
	#   AREA_OF_EFFECT 的基础值是 1.0（倍率），INCREASED / MORE 都在它上面算。
	var area_mult := maxf(0.05, attacker.get_stat(CombatStat.AREA_OF_EFFECT, tags, 1.0))
	s.radius = maxf(1.0, skill.area_radius * sqrt(area_mult))

	s.origin = skill.area_origin
	# 延迟走「持续时间」属性：风暴呼唤带 DURATION 标签，「延长持续」会让它落雷更慢 ——
	# 这是 PoE 的真实行为（玩家反过来用「缩短持续」让它落得更快）。新星延迟 0，乘什么都是 0。
	s.delay = maxf(0.0, attacker.get_stat(CombatStat.DURATION, tags, skill.area_delay))
	s.range = maxf(0.0, skill.area_range)

	# 脉冲次数：先加词缀（艾拉之脉动 +2），再按「持续时间」倍率放大（延长持续 = 多炸几次）。
	# 用倍率而不是把 DURATION 当秒数：脉冲技能的"持续时间"就是"炸几次 × 间隔"，
	# 间隔不动、次数走倍率，和 PoE 烈焰风暴"持续越久落的火球越多"一致。四舍五入、至少 1 次
	var base_pulses := attacker.get_stat(CombatStat.AREA_PULSES, tags, float(skill.area_pulses))
	var dur_mult := maxf(0.0, attacker.get_stat(CombatStat.DURATION, tags, 1.0))
	s.pulses = maxi(1, int(roundf(base_pulses * dur_mult)))
	s.interval = maxf(0.05, skill.area_interval)
	s.cascade = maxi(0, int(roundf(attacker.get_stat(CombatStat.AREA_CASCADE, tags, float(skill.area_cascade)))))
	s.follow = skill.area_follow
	s.arc_deg = clampf(skill.area_arc_deg, 1.0, 360.0)
	s.inner_radius = maxf(0.0, skill.area_inner_radius * sqrt(area_mult))
	return s


## 连环范围：额外那几个圈落在施法方向上的哪些位置（以"一个圈的间距"为单位）。
## +2 = 前一个、后一个（PoE 法术连锁的样子）；+3 = 再往前一个；+4 = 再往后一个 ……
## 位置由纯逻辑定、像素间距由表现层乘，方便单测。
func cascade_offsets() -> Array:
	var out: Array = []
	for i in cascade:
		var k := i / 2 + 1
		out.append(float(k) if i % 2 == 0 else -float(k))
	return out


## 圈里有谁。candidates = [{ "id": int, "dist": float }, ...]（到圆心的距离，像素），
## 返回命中的 id 列表。边界算在圈内（dist == radius 也中）。
## 一个目标只出现一次 —— 就算调用方把同一个 id 喂了两遍。
## 扇形时候选还要带 "angle"：目标方向和朝向的夹角（弧度，取绝对值）；贴在圆心上（dist 很小）的不看角度。
func hits(candidates: Array) -> Array:
	var out: Array = []
	var half := deg_to_rad(arc_deg) * 0.5
	for c in candidates:
		var id := int(c["id"])
		var dist := float(c["dist"])
		if dist > radius or dist < inner_radius or out.has(id):
			continue
		if arc_deg < 360.0 and dist > 4.0 and c.has("angle") and absf(float(c["angle"])) > half:
			continue   # 在圆里但不在扇形里
		out.append(id)
	return out


## 是扇形（锥 / 光束）吗
func is_cone() -> bool:
	return arc_deg < 360.0


## TARGET 模式：鼠标点离施法者 dist 像素，实际圆心离施法者多远（超过射程就夹住）
func clamp_distance(dist: float) -> float:
	if origin != Origin.TARGET or range <= 0.0:
		return dist
	return minf(dist, range)


func describe() -> String:
	var parts := PackedStringArray()
	parts.append("半径 %.0f" % radius)
	if is_cone():
		parts[0] = "扇形 %.0f°  长 %.0f" % [arc_deg, radius]
	if inner_radius > 0.0:
		parts[0] = "环 %.0f~%.0f" % [inner_radius, radius]
	if origin == Origin.TARGET:
		parts.append("指哪打哪（射程 %.0f）" % range)
	elif origin == Origin.FRONT:
		parts.append("面前 %.0f 像素处挥砍" % range)
	else:
		parts.append("以自己为中心")
	if delay > 0.0:
		parts.append("延迟 %.1fs" % delay)
	else:
		parts.append("瞬发")
	if pulses > 1:
		parts.append("脉冲 %d×%.2fs" % [pulses, interval])
	if cascade > 0:
		parts.append("连环 +%d" % cascade)
	if follow:
		parts.append("跟着你走")
	return "  ".join(parts)
