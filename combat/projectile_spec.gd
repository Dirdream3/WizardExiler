class_name ProjectileSpec
extends RefCounted

## 一发投射物的**行为参数** —— 由「技能基础值 + 角色词缀」算出来。
##
## 和伤害一样，穿透/分叉/弹射/散射角/漂移的数值全部走属性系统：
##   技能自带 base_chain = 0
##   支援宝石给 CHAIN_COUNT FLAT +2（要求 PROJECTILE 标签）
##   → 查询结果 = 2 次弹射
##
## 所以「增加 1 次弹射，仅限闪电技能」这种词缀是**纯数据**，一行代码都不用写。
##
## ★ 这个类里不许出现 Vector2 / 位置坐标 ★
##   角度用弧度、距离用标量，"往哪偏多少像素"由表现层自己去算。
##   保持零引擎依赖，才能跑单元测试、做离线 DPS 计算器。


## 多发投射物的散开方式
enum SpreadMode {
	## 相邻两发固定夹角：发数越多，扇面越宽（火球这种"多来几发"的技能）
	STEP,
	## 总扇面固定，均分给所有发：发数越多越密（PoE 的多重投射是这种）
	FAN,
}


# ---------------------------------------------------------------- 发射
var extra_count: int = 0          ## 额外投射物（0 = 只射 1 发）
var spread_mode: int = SpreadMode.STEP
var spread_deg: float = 10.0      ## STEP 模式：相邻两发的夹角
var spread_arc_deg: float = 40.0  ## FAN  模式：总扇面角
var jitter_deg: float = 0.0       ## 每发额外的随机角度抖动（±度）
var spawn_jitter: float = 0.0     ## 发射点的随机位移半径（像素）

# ---------------------------------------------------------------- 飞行
var speed: float = 240.0
var duration: float = 2.0         ## 存活秒数
var wander_deg: float = 0.0       ## 每次漂移的最大转角（±度）。0 = 直线飞
var wander_interval: float = 0.1  ## 多久漂移一次（秒）

# ---------------------------------------------------------------- 命中行为
var pierce_count: int = 0
var pierce_chance: float = 0.0
var fork_count: int = 0
var chain_count: int = 0
## ★ 连锁次数（ADR-035）★ 和 chain_count（弹射）是两套：连锁不重复命中、连锁中速度 ×(1 + LINK_SPEED_MORE)
var link_count: int = 0
var fork_angle_deg: float = 30.0
var chain_range: float = 150.0   ## 弹射和连锁共用这个搜索半径

# ---------------------------------------------------------------- 差异化（ADR-036）
var transform_after_px: float = 0.0   ## 飞过这么多像素后变形（0 = 不变形）
var transform_speed_mult: float = 1.0
var transform_crit_mult: float = 1.0
var returns: bool = false              ## 回旋：存活过半掉头飞回
var explode_radius: float = 0.0        ## 命中爆炸半径（已吃「范围效果」）。0 = 不炸
var aura_radius: float = 0.0           ## 随行光环半径（已吃「范围效果」）。0 = 没有
var aura_interval: float = 0.3

## 连锁中的投射物「更多 500% 速度」—— 电弧的跳跃几乎是瞬间的，这就是"连锁"和"弹射"手感上的区别
const LINK_SPEED_MORE := 5.0

# ---------------------------------------------------------------- 撞墙
## 撞到墙/地形能镜面弹开几次。★ 和「弹射(chain)」是两回事 ★
##   弹射  = 命中敌人后转向下一个敌人，消耗 chain_count
##   反弹  = 撞到地形弹开，只消耗 bounce_count，命中次数一次都不掉
## 电球术(Spark)就是靠它在房间里到处乱弹的。
var bounce_count: int = 0


## 从施法者的属性 + 技能基础值构建。
static func build(attacker: CombatEntity, skill: SkillSpec) -> ProjectileSpec:
	var s := ProjectileSpec.new()
	var tags := skill.hit_tags()

	# --- 发射 ---
	# 基础值来自技能自己（电球术天生 4 发），多重投射支援再往上加
	s.extra_count = _as_count(attacker.get_stat(
			CombatStat.PROJECTILE_COUNT, tags, float(skill.base_extra_projectiles)))
	s.spread_mode = skill.spread_mode
	# STEP 用「相邻夹角」当基础值，FAN 用「总扇面」当基础值，
	# 但它们共用同一条 PROJECTILE_SPREAD 属性 —— 于是「散射角提高 100%」
	# 这一条词缀对两种模式都有效，不用为每种模式各写一条。
	var spread_base: float = skill.spread_arc_deg if skill.spread_mode == SpreadMode.FAN else skill.spread_deg
	var spread := maxf(0.0, attacker.get_stat(CombatStat.PROJECTILE_SPREAD, tags, spread_base))
	if s.spread_mode == SpreadMode.FAN:
		s.spread_arc_deg = spread
	else:
		s.spread_deg = spread
	# 抖动也吃「散射角」加成：散得越开，越乱。技能本身抖动为 0 时，
	# 提高多少百分比都还是 0（0 × 任何倍率 = 0），这正是我们想要的。
	s.jitter_deg = maxf(0.0, attacker.get_stat(CombatStat.PROJECTILE_SPREAD, tags, skill.spread_jitter_deg))
	s.spawn_jitter = maxf(0.0, skill.spawn_jitter)

	# --- 飞行 ---
	s.speed = maxf(1.0, attacker.get_stat(CombatStat.PROJECTILE_SPEED, tags, skill.projectile_speed))
	s.duration = maxf(0.05, attacker.get_stat(CombatStat.DURATION, tags, skill.base_duration))
	s.wander_deg = maxf(0.0, attacker.get_stat(CombatStat.PROJECTILE_WANDER, tags, skill.wander_deg))
	s.wander_interval = maxf(0.01, skill.wander_interval)

	# --- 命中行为 ---
	s.pierce_count = _as_count(attacker.get_stat(CombatStat.PIERCE_COUNT, tags, float(skill.base_pierce)))
	s.pierce_chance = clampf(attacker.get_stat(CombatStat.PIERCE_CHANCE, tags, 0.0), 0.0, 1.0)
	s.fork_count = _as_count(attacker.get_stat(CombatStat.FORK_COUNT, tags, float(skill.base_fork)))
	s.chain_count = _as_count(attacker.get_stat(CombatStat.CHAIN_COUNT, tags, float(skill.base_chain)))
	s.chain_range = maxf(0.0, attacker.get_stat(CombatStat.CHAIN_RANGE, tags, skill.chain_range))
	s.link_count = _as_count(attacker.get_stat(CombatStat.LINK_COUNT, tags, float(skill.base_link)))

	# --- 差异化（ADR-036）---
	s.transform_after_px = skill.transform_after_px
	s.transform_speed_mult = skill.transform_speed_mult
	s.transform_crit_mult = skill.transform_crit_mult
	s.returns = skill.projectile_returns
	# 爆炸 / 光环的半径和范围技能一样吃「范围效果」（面积倍率的平方根）
	var area_mult := maxf(0.05, attacker.get_stat(CombatStat.AREA_OF_EFFECT, tags, 1.0))
	s.explode_radius = skill.area_radius * sqrt(area_mult) if skill.explodes_on_hit() else 0.0
	s.aura_radius = skill.aura_radius * sqrt(area_mult)
	s.aura_interval = skill.aura_interval
	s.fork_angle_deg = skill.fork_angle_deg

	# --- 撞墙 ---
	s.bounce_count = _as_count(attacker.get_stat(CombatStat.BOUNCE_COUNT, tags, float(skill.base_bounce)))
	return s


## 这一次施法总共发射几发
func shot_count() -> int:
	return 1 + maxi(0, extra_count)


## 多发时每一发相对准星的偏转角（弧度），中心对称展开。
##   rng 传 null = 不抖动（伤害面板、单元测试要的是确定结果）
func spread_angles(rng: RandomNumberGenerator = null) -> PackedFloat32Array:
	var n := shot_count()
	var out := PackedFloat32Array()

	# 相邻两发的夹角
	var step := deg_to_rad(spread_deg)
	if spread_mode == SpreadMode.FAN:
		# 总扇面固定：3 发均分 40° → 相邻 20°，两端刚好落在 ±20°
		step = 0.0 if n <= 1 else deg_to_rad(spread_arc_deg) / float(n - 1)

	var start := -step * float(n - 1) * 0.5
	for i in n:
		var a := start + step * float(i)
		if jitter_deg > 0.0 and rng != null:
			a += deg_to_rad(rng.randf_range(-jitter_deg, jitter_deg))
		out.append(a)
	return out


func describe() -> String:
	var parts := PackedStringArray()
	parts.append("%d 发" % shot_count())
	if shot_count() > 1:
		if spread_mode == SpreadMode.FAN:
			parts.append("扇面 %.0f°" % spread_arc_deg)
		else:
			parts.append("间隔 %.0f°" % spread_deg)
	if jitter_deg > 0.0:
		parts.append("抖动 ±%.0f°" % jitter_deg)
	if wander_deg > 0.0:
		parts.append("漂移 ±%.0f°" % wander_deg)
	if pierce_count > 0:
		parts.append("穿透 %d" % pierce_count)
	if pierce_chance > 0.0:
		parts.append("穿透几率 %.0f%%" % (pierce_chance * 100.0))
	if fork_count > 0:
		parts.append("分叉 %d" % fork_count)
	if chain_count > 0:
		parts.append("弹射 %d" % chain_count)
	if link_count > 0:
		parts.append("连锁 %d" % link_count)
	if bounce_count > 0:
		parts.append("反弹 %d" % bounce_count)
	if explode_radius > 0.0:
		parts.append("命中爆炸 r%.0f" % explode_radius)
	if transform_after_px > 0.0:
		parts.append("飞 %.0f 后变形" % transform_after_px)
	if returns:
		parts.append("回旋")
	if aura_radius > 0.0:
		parts.append("随行光环 r%.0f" % aura_radius)
	parts.append("速度 %.0f" % speed)
	parts.append("存活 %.1fs" % duration)
	return "  ".join(parts)


static func _as_count(v: float) -> int:
	return maxi(0, int(roundf(v)))
