class_name MonsterAffix
extends RefCounted

## 精英怪的**一条词条**（PoE 里稀有怪头顶那几个词：迅捷 / 坚韧 / 抗火……）。
##
## ★ 为什么不直接往怪身上塞 Modifier 就完事？★
##   词条要能显示名字（怪头顶写着「迅捷·坚韧 骷髅战士」）、要能整组识别
##   （"这只怪有没有灼热之爪" → 近战时给玩家上点燃）、要能被随机抽取且不重复。
##   所以它是"一组词缀 + 一个名字 + 几个附带效果"的打包，和 SupportGem 一个思路。
##
## ★ 这个文件是纯逻辑，规矩同 combat/ 其它文件：零 Godot 场景依赖 ★
##   `body_scale` 只是一个倍率数字（"这只怪画大几倍"），表现层自己拿去用；
##   这里不认识 Sprite，也不认识场景坐标。

var id: StringName = &""
var display_name: String = ""
var description: String = ""

## 这条词条给怪叠的词缀（模板）。★ source 由 apply_to() 统一填成词条 id ★
## —— 和辅助宝石一样，整组来整组去，靠 source 就能 remove_by_source。
var mods: Array = []

## 近战命中玩家时附加的异常（null = 没有）。「灼热之爪」= 点燃、「霜爪」= 冰缓。
## 谁来施加由表现层（Enemy._attack）决定 —— 这里只是数据。
var on_hit_buff: BuffDef = null

## 体型倍率。1.0 = 不变；「巨型」是 1.35。表现层拿它放大精灵和碰撞体。
var body_scale: float = 1.0


func _init(p_id: StringName = &"", p_name: String = "") -> void:
	id = p_id
	display_name = p_name


# ---------------------------------------------------------------- 链式构造

func with_mod(m: Modifier) -> MonsterAffix:
	mods.append(m)
	return self


func with_on_hit(buff: BuffDef) -> MonsterAffix:
	on_hit_buff = buff
	return self


func with_scale(scale: float) -> MonsterAffix:
	body_scale = maxf(0.1, scale)
	return self


func with_desc(desc: String) -> MonsterAffix:
	description = desc
	return self


# ---------------------------------------------------------------- 应用

## 把这条词条挂到一只怪身上：词缀进 gear_mods（带 source = 词条 id），
## 词条本身记进 entity.affixes（表现层靠它画名字、判断有没有爪类效果）。
## ★ 只挂词缀，不 refill ★ —— 调用方叠完所有词条再统一 refill()，
##   否则第一条词条 refill 完、第二条又抬了生命上限，怪出生时就不是满血。
func apply_to(entity: CombatEntity) -> void:
	for m in mods:
		var t := m as Modifier
		entity.gear_mods.add(Modifier.new(t.stat, t.kind, t.value, t.required_tags, id))
	entity.affixes.append(self)


## 词条的一句话说明（面板 / 调试用）
func describe() -> String:
	var l := PackedStringArray()
	l.append("【%s】%s" % [display_name, description])
	for m in mods:
		l.append("  · " + (m as Modifier).describe())
	if on_hit_buff != null:
		l.append("  · 近战命中附加：%s" % on_hit_buff.display_name)
	if not is_equal_approx(body_scale, 1.0):
		l.append("  · 体型 ×%.2f" % body_scale)
	return "\n".join(l)
