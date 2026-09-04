class_name SkillSpec
extends RefCounted

## 技能定义。
##
## 注意技能自己只提供"基础值 + 标签"，所有加成都来自角色身上的词缀。
## 这就是 PoE 的核心设计：同一个技能在不同构筑里表现完全不同。

var id: StringName = &""
var display_name: String = ""

## 基础伤害（还没算任何词缀）
var base_damage: float = 0.0
## 技能标签，决定哪些词缀能吃到
var tags: int = CombatTags.NONE

var base_crit_chance: float = 0.05
var base_crit_multi: float = 1.5

var mana_cost: float = 0.0
var base_cooldown: float = 0.0
## ★ 基础施放时间（秒）★ —— PoE 技能石上印的那个「施放时间 0.75 秒」。
##
## 每秒能放几次 = 施法速度倍率 ÷ 施放时间：
##     施法速度 1.25 × 施放时间 0.75 秒 → 1.25 / 0.75 = 1.67 次/秒
## 所以「提高施法速度」是缩短这个时间，而不是改这个字段本身。
var cast_time: float = 1.0

## 命中后附加的 Debuff（点燃、中毒、诅咒……）
var on_hit_buffs: Array[BuffDef] = []
## 附加概率（0~1）
var on_hit_chance: float = 1.0

# ---------------- 投射物：发射 ----------------
# 这些是技能自带的**基础值**，角色的词缀会在 ProjectileSpec.build() 里叠上去。
# 只有带 PROJECTILE 标签的技能才用得到。

## 技能自带的额外发数（0 = 只射 1 发）。电球术这种天生就是多发的技能填 3
var base_extra_projectiles: int = 0
var projectile_speed: float = 240.0

## 散射方式。这里存 int 而不是 ProjectileSpec.SpreadMode，是为了不让 SkillSpec
## 反过来依赖 ProjectileSpec（build() 已经依赖 SkillSpec 了，循环引用很难受）。
## 填数据时写 ProjectileSpec.SpreadMode.FAN 即可，值是一样的。
##   0 = STEP：相邻两发固定夹角，发数越多扇面越宽
##   1 = FAN ：总扇面固定，均分给所有发 —— PoE 的「多重投射」是这种
var spread_mode: int = 0
## STEP 模式下相邻两发的夹角（度）
var spread_deg: float = 10.0
## FAN 模式下的总扇面角（度）
var spread_arc_deg: float = 40.0
## 每发额外的随机角度抖动（±度），0 = 完全整齐。电球术那种乱射感靠它
var spread_jitter_deg: float = 0.0
## 发射点的随机位移半径（像素）。让多发不要挤在同一个点上出生
var spawn_jitter: float = 0.0

# ---------------- 投射物：飞行 ----------------

## 存活秒数。★ 默认 2 秒，别填 0 ★（0 会被 build() 夹成 0.05 秒，等于一出生就没）
var base_duration: float = 2.0
## 飞行中每次随机漂移的最大转角（±度）。0 = 直线飞
var wander_deg: float = 0.0
## 多久漂移一次（秒）。配合 wander_deg 用
var wander_interval: float = 0.1

# ---------------- 投射物：命中 / 撞墙 ----------------

# ---------------- 范围（AoE）----------------
# ★ 范围技能不走投射物管线（ADR-030）★ —— 新星、风暴呼唤这类"画一个圈、圈里全中"的技能
#   由 AreaSpec.build() 展开，表现层用 AreaBurst 画圈。一个技能要么是投射物、要么是范围，
#   不同时是两者（火球的"命中爆炸"以后再说）。

## 范围半径（像素）。> 0 = 这是范围技能。角色的「范围效果」词缀在 AreaSpec.build() 里叠上去
var area_radius: float = 0.0
## 圈以谁为中心：0 = 施法者脚下（新星），1 = 鼠标点（风暴呼唤）。存 int 是为了不反向依赖 AreaSpec
var area_origin: int = 0
## 落地延迟（秒）。0 = 瞬发。风暴呼唤 1.2 秒后落雷；它吃「持续时间」加成
var area_delay: float = 0.0
## 鼠标点模式的最大施放距离（像素）
var area_range: float = 0.0
## 圈炸几次（ADR-031）。1 = 一次性；烈焰风暴 6 次、漩涡 4 次。角色的「脉冲次数」词缀在其上加，
## 「持续时间」按比例放大次数（延长持续 = 多炸几次，PoE 烈焰风暴的行为）
var area_pulses: int = 1
## 两次脉冲之间隔几秒
var area_interval: float = 0.4
## 技能天生的连环圈数（冰川之刺天生 2）。角色的「连环次数」词缀在其上加
var area_cascade: int = 0
## ★ 环形（ADR-036）★：内半径以内不算命中（电击新星是一个环，贴身的打不到）。0 = 实心圆
var area_inner_radius: float = 0.0
## ★ 投射物命中爆炸（ADR-036）★：带 area_radius 的**投射物**在每次命中时以命中点炸一圈（火球 / 翻滚岩浆）。
## 爆炸打的是命中点周围的**其他**敌人（被直接命中的那只已经吃过一次命中）
## ★ 变形（ADR-036，冰矛）★：飞过 transform_after_px 像素后速度 ×transform_speed_mult、暴击率 ×transform_crit_mult
var transform_after_px: float = 0.0
var transform_speed_mult: float = 1.0
var transform_crit_mult: float = 1.0
## ★ 回旋（ADR-036，灵体投掷）★：飞到一半掉头飞回施法者，回程能再打一遍打过的
var projectile_returns: bool = false
## ★ 随行光环（ADR-036，灵魂撕裂）★：投射物飞行时每 aura_interval 秒对周围 aura_radius 内的敌人结算一次
var aura_radius: float = 0.0
var aura_interval: float = 0.3
## ★ 引导蓄力（ADR-036，焚烧）★：每放出一段就给自己叠一层这个 Buff（STACK_COUNT），松手后自然消退
var channel_ramp: BuffDef = null

## ★ 扇形角（度）★（ADR-034）：360 = 整个圆；焚烧 40°、闪电之触 60°、裂雷之矛 14°（一道光束）。
## 扇形以施法者为中心、朝鼠标方向张开 —— 半径就是它的长度
var area_arc_deg: float = 360.0
## ★ 引导技能 ★（ADR-033）：按住不放就一段一段地持续施放，每段 = 一次施法、扣一次蓝；
## 松手 / 蓝不够就停。引导中不能切技能（Q 无效）。旋风斩 / 焚烧 / 闪电之触是引导。
## cast_time 在引导技能上的含义 = 每一段的时长（÷ 攻速或施速）。
var channel: bool = false

## ★ 圈跟着施法者走 ★（ADR-032 补充）：旋风斩边转边走、双重打击第二刀跟着人。
## 漩涡 / 静电之击 / 烈焰风暴按 PoE 的行为留在原地（false）。只对有脉冲 / 延迟的技能有意义
var area_follow: bool = false

var base_pierce: int = 0      ## 自带穿透次数
var base_fork: int = 0        ## 自带分叉次数
var base_chain: int = 0       ## 自带弹射次数（命中后转向下一个敌人，**可以**弹回打过的）
## ★ 自带连锁次数（ADR-035）★ 电弧的那种：跳向**没打过**的敌人，连锁中速度 +500%（几乎瞬移）。
## 和弹射是两套次数、两套规则：弹射能两只怪来回弹，连锁永不回头
var base_link: int = 0
## 自带撞墙反弹次数。★ 和「弹射」不是一回事 ★
##   弹射(chain) = 命中敌人后转向下一个敌人
##   反弹(bounce) = 撞到墙/地形后镜面弹开，不消耗任何命中次数
var base_bounce: int = 0
## 分叉时向两侧偏转的角度（度）。PoE 是 30°
var fork_angle_deg: float = 30.0
## 弹射的搜索半径（像素）
var chain_range: float = 150.0


func _init(p_id: StringName = &"", p_name: String = "", p_damage: float = 0.0, p_tags: int = CombatTags.NONE) -> void:
	id = p_id
	display_name = p_name
	base_damage = p_damage
	tags = p_tags


## 复制一份。技能石（SkillGem）拿它当"1 级模板"，每次施法都复制一份再按等级加成 ——
## 直接改模板的话，等级一升，之前算好的那些 SkillSpec 会跟着一起变。
func duplicate() -> SkillSpec:
	var c := SkillSpec.new()
	# 用属性表逐个拷贝，这样以后给 SkillSpec 加字段，不用回来改这里
	for p in get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			c.set(p["name"], get(p["name"]))
	# ★ 数组是引用类型 ★ 上面拷过去的是"同一个数组"，改一个两个都会变
	c.on_hit_buffs = on_hit_buffs.duplicate()
	return c


func with_crit(chance: float, multi: float) -> SkillSpec:
	base_crit_chance = chance
	base_crit_multi = multi
	return self


func with_cost(mana: float, cooldown: float = 0.0) -> SkillSpec:
	mana_cost = mana
	base_cooldown = cooldown
	return self


## 基础施放时间（秒）。
func with_cast_time(seconds: float) -> SkillSpec:
	cast_time = maxf(0.05, seconds)
	return self


func with_on_hit(buff: BuffDef, chance: float = 1.0) -> SkillSpec:
	on_hit_buffs.append(buff)
	on_hit_chance = chance
	return self


func with_projectile(speed: float, pierce: int = 0, fork: int = 0, chain: int = 0) -> SkillSpec:
	projectile_speed = speed
	base_pierce = pierce
	base_fork = fork
	base_chain = chain
	return self


## 技能天生射几发（extra = 3 → 一次 4 发）。多重投射支援会在这个基础上再加。
func with_count(extra: int) -> SkillSpec:
	base_extra_projectiles = maxi(0, extra)
	return self


## 散射方式。mode = ProjectileSpec.SpreadMode.STEP 时 value 是「相邻夹角」，
## mode = FAN 时 value 是「总扇面角」。jitter 是每发额外的随机抖动。
func with_spread(mode: int, value: float, jitter: float = 0.0) -> SkillSpec:
	spread_mode = mode
	if mode == 1:   # FAN
		spread_arc_deg = value
	else:
		spread_deg = value
	spread_jitter_deg = jitter
	return self


## 飞行中的随机漂移：每 interval 秒转一个 ±deg 以内的随机角。
## 这是电球术"到处乱窜"的来源。
func with_wander(deg: float, interval: float = 0.1) -> SkillSpec:
	wander_deg = deg
	wander_interval = maxf(0.01, interval)
	return self


## 天生连锁次数（电弧 3）。
func with_link(count: int) -> SkillSpec:
	base_link = maxi(0, count)
	return self


## 撞墙反弹次数（电球术靠它在房间里弹来弹去）。
func with_bounce(count: int) -> SkillSpec:
	base_bounce = maxi(0, count)
	return self


## 存活时间 + 发射点随机位移。
func with_duration(seconds: float, spawn_spread: float = 0.0) -> SkillSpec:
	base_duration = maxf(0.05, seconds)
	spawn_jitter = maxf(0.0, spawn_spread)
	return self


## 范围技能的参数：半径 / 中心（AreaSpec.Origin 的值）/ 延迟 / 射程。
func with_area(radius: float, origin: int = 0, delay: float = 0.0, p_range: float = 0.0) -> SkillSpec:
	area_radius = maxf(0.0, radius)
	area_origin = origin
	area_delay = maxf(0.0, delay)
	area_range = maxf(0.0, p_range)
	return self


## 范围技能的脉冲：圈炸 count 次、每 interval 秒一次（第一次在 area_delay 之后）。
func with_pulses(count: int, interval: float) -> SkillSpec:
	area_pulses = maxi(1, count)
	area_interval = maxf(0.05, interval)
	return self


func is_projectile() -> bool:
	return (tags & CombatTags.PROJECTILE) != 0


## 是范围技能吗（走 AreaSpec，不走投射物）。
## ★ 带 area_radius 的投射物不算 ★ —— 那是"命中爆炸"（explodes_on_hit），它仍然走投射物管线
func is_area() -> bool:
	return area_radius > 0.0 and not is_projectile()


## 投射物命中时炸一圈吗（火球 / 翻滚岩浆）
func explodes_on_hit() -> bool:
	return is_projectile() and area_radius > 0.0


## 环形：内半径以内不算
func with_inner(inner: float) -> SkillSpec:
	area_inner_radius = maxf(0.0, inner)
	return self


## 投射物命中爆炸：以命中点为中心、半径 radius 的圈打周围的其他敌人
func with_explosion(radius: float) -> SkillSpec:
	area_radius = maxf(0.0, radius)
	return self


## 变形：飞过 px 像素后，速度 ×speed_mult、暴击率 ×crit_mult（冰矛的第二形态）
func with_transform(px: float, speed_mult: float, crit_mult: float) -> SkillSpec:
	transform_after_px = maxf(0.0, px)
	transform_speed_mult = maxf(0.1, speed_mult)
	transform_crit_mult = maxf(0.0, crit_mult)
	return self


## 回旋：存活过半掉头飞回施法者，回程能再打一遍
func with_return() -> SkillSpec:
	projectile_returns = true
	return self


## 随行光环：飞行途中每 interval 秒对周围 radius 内的敌人结算一次
func with_aura(radius: float, interval: float) -> SkillSpec:
	aura_radius = maxf(0.0, radius)
	aura_interval = maxf(0.05, interval)
	return self


## 引导蓄力：每放一段叠一层 buff
func with_ramp(buff: BuffDef) -> SkillSpec:
	channel_ramp = buff
	return self


## 是攻击技能吗（出手间隔走「攻击速度」，镶在武器里；法术走「施法速度」，镶在法杖里）
func is_attack() -> bool:
	return (tags & CombatTags.ATTACK) != 0


## 扇形范围（锥 / 光束）：朝施法方向张开 deg 度，半径 = 长度
func with_arc(deg: float) -> SkillSpec:
	area_arc_deg = clampf(deg, 1.0, 360.0)
	return self


## 引导技能：按住持续施放、逐段扣蓝、引导中不能切技能
func with_channel() -> SkillSpec:
	channel = true
	return self


func is_channel() -> bool:
	return channel


## 圈跟着施法者走（每次脉冲都按施法者此刻的位置结算）
func with_follow() -> SkillSpec:
	area_follow = true
	return self


## 天生的连环圈数
func with_cascade(count: int) -> SkillSpec:
	area_cascade = maxi(0, count)
	return self


## 命中时实际使用的标签 = 技能标签 + HIT
func hit_tags() -> int:
	return tags | CombatTags.HIT
