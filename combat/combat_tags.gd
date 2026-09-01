class_name CombatTags
extends RefCounted

## 战斗标签（位掩码）
##
## 这是整个 PoE 式词缀系统的地基。
## 每一次伤害、每一个技能都会带上一组标签，比如火球术 = 火焰 | 法术 | 投射物 | 范围。
## 每一条词缀声明"我要求哪些标签"，只有目标标签**全部包含**要求的标签时才生效。
##
## 例子：
##   「增加 40% 火焰投射物伤害」 → required_tags = FIRE | PROJECTILE
##   火球术(FIRE|SPELL|PROJECTILE|AREA) 命中 → 生效 ✔
##   冰霜新星(COLD|SPELL|AREA)     命中 → 不生效 ✘
##
## 用位掩码（一个 int 存所有标签）而不是字符串数组，是因为战斗里每帧要做成千上万次
## 匹配判断，位运算是 O(1) 且零内存分配。

const NONE := 0

# --- 伤害类型 ---
const PHYSICAL  := 1 << 0
const FIRE      := 1 << 1
const COLD      := 1 << 2
const LIGHTNING := 1 << 3
const CHAOS     := 1 << 4

# --- 来源类型 ---
const ATTACK := 1 << 5  ## 攻击（武器）
const SPELL  := 1 << 6  ## 法术

# --- 传递方式 ---
const PROJECTILE := 1 << 7
const MELEE      := 1 << 8
const AREA       := 1 << 9

# --- 结算方式 ---
const HIT     := 1 << 10  ## 一次性命中
const DOT     := 1 << 11  ## 持续伤害（每秒结算）
const AILMENT := 1 << 12  ## 异常状态（点燃/冰缓/感电）

# --- 效果类型 ---
const CURSE := 1 << 13
const AURA  := 1 << 14
const BUFF  := 1 << 15
const DEBUFF := 1 << 16

## 「持续时间」标签。PoE 里凡是印着这个标签的技能，才吃得到
## 「提高技能持续时间」这类词缀和「延长持续时间辅助」。
## 电球术正是靠它 —— 每一发活得越久，在房间里弹得越久，打到的次数越多。
const DURATION := 1 << 18

## ★ 派生标签 ★
## 「元素」必须是**独立的一位**，不能写成 FIRE|COLD|LIGHTNING。
## 因为匹配用的是 has_all（要求全部包含），如果 ELEMENTAL = 三个位，
## 那「提高元素伤害」就会变成"必须同时是火+冰+电才生效"，永远吃不到。
## 正确做法：给它自己一位，由 normalize() 在查询时自动补上。
const ELEMENTAL := 1 << 17

## 三种元素伤害类型的集合（内部用，不要拿去当 required_tags）
const ELEMENT_TYPES := FIRE | COLD | LIGHTNING
const ANY_DAMAGE_TYPE := PHYSICAL | ELEMENT_TYPES | CHAOS


## 补齐派生标签。StatSet 查询时会自动调用，你平时构造标签不用管它。
## 以后要加「异常状态伤害」「击中或持续伤害」这类派生标签，都加在这里。
static func normalize(tags: int) -> int:
	if tags & ELEMENT_TYPES:
		tags |= ELEMENTAL
	return tags


## 目标标签 tags 是否**包含全部** required 要求的标签。
## required 为 0（无要求）时永远为真 —— 这就是"全局增伤"词缀。
static func has_all(tags: int, required: int) -> bool:
	return (tags & required) == required


## 目标标签是否包含 mask 里的**任意一个**。
static func has_any(tags: int, mask: int) -> bool:
	return (tags & mask) != 0


## 转成可读文本，调试和 UI 用。
static func describe(tags: int) -> String:
	if tags == NONE:
		return "无标签"
	var names := PackedStringArray()
	if tags & PHYSICAL:   names.append("物理")
	if tags & FIRE:       names.append("火焰")
	if tags & COLD:       names.append("冰霜")
	if tags & LIGHTNING:  names.append("闪电")
	if tags & CHAOS:      names.append("混沌")
	if tags & ELEMENTAL:  names.append("元素")
	if tags & ATTACK:     names.append("攻击")
	if tags & SPELL:      names.append("法术")
	if tags & PROJECTILE: names.append("投射物")
	if tags & MELEE:      names.append("近战")
	if tags & AREA:       names.append("范围")
	if tags & HIT:        names.append("命中")
	if tags & DOT:        names.append("持续伤害")
	if tags & AILMENT:    names.append("异常状态")
	if tags & CURSE:      names.append("诅咒")
	if tags & AURA:       names.append("光环")
	if tags & BUFF:       names.append("增益")
	if tags & DEBUFF:     names.append("减益")
	if tags & DURATION:   names.append("持续时间")
	return ", ".join(names)
