class_name CombatStat
extends RefCounted

## 属性表
##
## 所有可被词缀影响的数值都要在这里登记。新增一条属性 = 在枚举里加一行。
## 用 int 枚举而不是字符串，是为了让 StatSet 的查询是整数比较。

enum {
	DAMAGE,            ## 伤害（配合标签使用：火焰伤害、投射物伤害……都是这一条）
	ATTACK_SPEED,      ## 攻击速度（次/秒）
	CAST_SPEED,        ## 施法速度（次/秒）
	CRIT_CHANCE,       ## 暴击率（0~1）
	CRIT_MULTI,        ## 暴击伤害倍率（1.5 = 150%）
	MAX_LIFE,          ## 生命上限
	MAX_MANA,          ## 魔力上限
	MANA_REGEN,        ## 魔力回复（点/秒）。基础值由 Player 传入，装备词缀在其上加成
	ARMOUR,            ## 护甲（减物理）
	EVASION,           ## 闪避值
	MOVE_SPEED,        ## 移动速度
	FIRE_RESIST,       ## 火焰抗性（0.75 = 75%）
	COLD_RESIST,
	LIGHTNING_RESIST,
	CHAOS_RESIST,
	DAMAGE_TAKEN,      ## 受到的伤害（防守方词缀，如「受到的伤害减少 10%」= INCREASED -0.10）
	AREA_OF_EFFECT,    ## 范围效果
	COOLDOWN_RECOVERY, ## 冷却回复速度
	DURATION,          ## 效果持续时间

	# --- 投射物 ---
	PROJECTILE_COUNT,  ## 额外投射物数量（FLAT：+2 = 一次射 3 发）
	PROJECTILE_SPEED,  ## 投射物飞行速度
	PIERCE_COUNT,      ## 穿透次数
	PIERCE_CHANCE,     ## 穿透几率（0~1，用完次数后还能靠几率穿）
	FORK_COUNT,        ## 分叉次数
	CHAIN_COUNT,       ## 弹射（连锁）次数：命中敌人后转向下一个敌人
	CHAIN_RANGE,       ## 弹射 / 连锁的搜索半径（像素）
	LINK_COUNT,        ## ★ 连锁次数（ADR-035）★ 和弹射不同：连锁**不会重复命中**同一个敌人，且连锁中投射物速度 +500%
	BOUNCE_COUNT,      ## 撞墙反弹次数：撞到地形镜面弹开，不消耗命中次数
	PROJECTILE_SPREAD, ## 散射角（多发投射物展开的角度，同时也放大随机抖动）
	PROJECTILE_WANDER, ## 飞行中的随机漂移强度（度/次）。电球术到处乱窜就靠它

	# --- 范围（ADR-031）---
	AREA_PULSES,       ## 范围技能的脉冲次数（FLAT：+2 = 圈多炸 2 次）。烈焰风暴天生 6 次
	AREA_CASCADE,      ## 连环次数（FLAT：+2 = 沿施法方向前后各多一个圈）

	COUNT,
}

## 抗性上限，PoE 默认 75%
const RESIST_CAP := 0.75
## 护甲最多减免 90% 物理伤害
const ARMOUR_REDUCTION_CAP := 0.90


static func stat_name(stat: int) -> String:
	match stat:
		DAMAGE:            return "伤害"
		ATTACK_SPEED:      return "攻击速度"
		CAST_SPEED:        return "施法速度"
		CRIT_CHANCE:       return "暴击率"
		CRIT_MULTI:        return "暴击伤害"
		MAX_LIFE:          return "生命上限"
		MAX_MANA:          return "魔力上限"
		MANA_REGEN:        return "魔力回复"
		ARMOUR:            return "护甲"
		EVASION:           return "闪避"
		MOVE_SPEED:        return "移动速度"
		FIRE_RESIST:       return "火焰抗性"
		COLD_RESIST:       return "冰霜抗性"
		LIGHTNING_RESIST:  return "闪电抗性"
		CHAOS_RESIST:      return "混沌抗性"
		DAMAGE_TAKEN:      return "承受伤害"
		AREA_OF_EFFECT:    return "范围效果"
		COOLDOWN_RECOVERY: return "冷却回复"
		DURATION:          return "持续时间"
		PROJECTILE_COUNT:  return "额外投射物"
		PROJECTILE_SPEED:  return "投射物速度"
		PIERCE_COUNT:      return "穿透次数"
		PIERCE_CHANCE:     return "穿透几率"
		FORK_COUNT:        return "分叉次数"
		CHAIN_COUNT:       return "弹射次数"
		CHAIN_RANGE:       return "弹射半径"
		LINK_COUNT:        return "连锁次数"
		BOUNCE_COUNT:      return "反弹次数"
		PROJECTILE_SPREAD: return "散射角"
		PROJECTILE_WANDER: return "随机漂移"
		AREA_PULSES:       return "脉冲次数"
		AREA_CASCADE:      return "连环次数"
	return "未知属性(%d)" % stat


## 某个伤害标签对应哪条抗性属性；不是元素/混沌伤害则返回 -1。
static func resist_stat_for_tags(tags: int) -> int:
	if tags & CombatTags.FIRE:      return FIRE_RESIST
	if tags & CombatTags.COLD:      return COLD_RESIST
	if tags & CombatTags.LIGHTNING: return LIGHTNING_RESIST
	if tags & CombatTags.CHAOS:     return CHAOS_RESIST
	return -1
