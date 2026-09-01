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

var base_pierce: int = 0      ## 自带穿透次数
var base_fork: int = 0        ## 自带分叉次数
var base_chain: int = 0       ## 自带弹射（连锁）次数
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


## 撞墙反弹次数（电球术靠它在房间里弹来弹去）。
func with_bounce(count: int) -> SkillSpec:
	base_bounce = maxi(0, count)
	return self


## 存活时间 + 发射点随机位移。
func with_duration(seconds: float, spawn_spread: float = 0.0) -> SkillSpec:
	base_duration = maxf(0.05, seconds)
	spawn_jitter = maxf(0.0, spawn_spread)
	return self


func is_projectile() -> bool:
	return (tags & CombatTags.PROJECTILE) != 0


## 命中时实际使用的标签 = 技能标签 + HIT
func hit_tags() -> int:
	return tags | CombatTags.HIT
