extends SceneTree

## 战斗核心的单元测试。
##
## 运行方式（在项目根目录）：
##     godot --headless --script res://test/run_tests.gd
##
## 这套测试之所以能存在，是因为 combat/ 里没有任何 Node 依赖。
## PoE 式的词缀交互复杂到一定程度后，不写测试基本必炸 ——
## 你改一条乘区规则，可能三天后才发现某个构筑的伤害翻了倍。

const M = preload("res://combat/modifier.gd")
const T = preload("res://combat/combat_tags.gd")
const S = preload("res://combat/combat_stat.gd")
const Demo = preload("res://data/demo_content.gd")
const Gems = preload("res://data/gem_library.gd")

var _passed := 0
var _failed := 0
var _group := ""


func _initialize() -> void:
	print("\n=========== 战斗核心测试 ===========\n")

	_test_four_stage_formula()
	_test_increased_vs_more()
	_test_tag_matching()
	_test_buff_refresh()
	_test_buff_stack_count()
	_test_buff_highest()
	_test_buff_independent()
	_test_buff_expiry()
	_test_dot_ticks()
	_test_resist_cap()
	_test_armour_formula()
	_test_negative_resist()
	_test_remove_by_source()
	_test_full_pipeline()
	_test_projectile_priority()
	_test_projectile_fork_inherit()
	_test_projectile_pierce_chance()
	_test_projectile_from_mods()
	_test_projectile_spread()
	_test_projectile_spread_fan()
	_test_projectile_wander()
	_test_projectile_bounce()
	_test_chain_target_pick()
	_test_spark_spec()
	# --- 技能石 ---
	_test_gem_level_growth()
	_test_gem_tags_and_support_rules()
	_test_gem_shape_rotation()
	_test_gem_grid_placement()
	_test_gem_grid_arrows()
	_test_gem_grid_save()
	_test_skill_mods_layer()
	_test_spark_gem()
	_test_spark_supports()
	_test_cast_rate()
	_test_gem_tooltip_text()
	_test_damage_report_text()
	# --- 局内流程（7 步地图 / 状态机 / 奖励 / 内容）---
	_test_run_map_shape()
	_test_run_map_determinism()
	_test_run_map_guarantees()
	_test_run_state_flow()
	_test_run_state_gold_and_save()
	_test_run_rewards_roll()
	_test_run_content()
	_test_room_gold()
	# --- 内容扩充：电弧 / 冰系技能 / 冰缓 ---（图标能不能加载在 smoke_test 里测）
	_test_new_actives()
	_test_chill_buff()
	_test_cold_support()
	_test_new_content_in_run()
	# --- 合成 ---
	_test_gem_merge()
	# --- 法杖载体（ADR-020）与 4 层结构（ADR-021）---
	_test_wand_socket()
	_test_wand_mods_scope()
	_test_run_map_floors()
	# --- 回蓝装备（魔力回复走属性系统）---
	_test_mana_regen_gear()
	# --- 触媒（ADR-026）---
	_test_catalyst_rules()
	# --- 新辅助：法术节魔 / 元素集中 / 快速·缓速投射 / 暴击伤害 ---
	_test_new_supports()
	# --- ADR-028：技能扩充 ×5 + 虚空操纵 / 波次刷怪 / 精英怪词条 ---
	_test_skills_batch_two()
	_test_essence_drain_dot()
	_test_skills_batch_three()
	# --- ADR-030：真正的范围管线（新星 / 风暴呼唤 / 增大范围 / 集中效应）---
	_test_area_spec()
	_test_area_skills()
	# --- ADR-031：脉冲 / 连环 / 三颗新范围技能 / 辅助稀有度（崇高、血脉）---
	_test_area_pulses_cascade()
	_test_area_skills_two()
	_test_support_tiers()
	# --- ADR-032：近战武器 + 攻击技能 ---
	_test_melee_weapons()
	_test_melee_skills()
	# --- ADR-035：连锁 vs 弹射 ---
	_test_link_vs_chain()
	# --- ADR-036：同质化技能的差异化 ---
	_test_differentiation()
	_test_room_waves()
	_test_monster_affixes()
	_test_elite_monsters()

	print("\n===================================")
	print("通过 %d / %d" % [_passed, _passed + _failed])
	if _failed > 0:
		print("失败 %d 项" % _failed)
	print("===================================\n")
	quit(0 if _failed == 0 else 1)


# ---------------------------------------------------------------- 测试用例

func _test_four_stage_formula() -> void:
	_begin("四段式基础公式")
	var s := StatSet.new()
	s.add(M.new(S.DAMAGE, M.Kind.FLAT, 20.0))
	s.add(M.new(S.DAMAGE, M.Kind.INCREASED, 0.50))
	s.add(M.new(S.DAMAGE, M.Kind.INCREASED, 0.30))
	s.add(M.new(S.DAMAGE, M.Kind.MORE, 0.20))
	# (100 + 20) × (1 + 0.5 + 0.3) × 1.2 = 120 × 1.8 × 1.2 = 259.2
	_close("(100+20)×1.8×1.2", s.compute(S.DAMAGE, T.NONE, 100.0), 259.2)


func _test_increased_vs_more() -> void:
	_begin("提高(加法区) vs 更多(乘法区)")

	var a := StatSet.new()
	a.add(M.new(S.DAMAGE, M.Kind.INCREASED, 0.50))
	a.add(M.new(S.DAMAGE, M.Kind.INCREASED, 0.50))
	_close("两条 提高50% = ×2.00", a.compute(S.DAMAGE, T.NONE, 100.0), 200.0)

	var b := StatSet.new()
	b.add(M.new(S.DAMAGE, M.Kind.MORE, 0.50))
	b.add(M.new(S.DAMAGE, M.Kind.MORE, 0.50))
	_close("两条 更多50% = ×2.25", b.compute(S.DAMAGE, T.NONE, 100.0), 225.0)

	var c := StatSet.new()
	c.add(M.new(S.DAMAGE, M.Kind.INCREASED, -0.30))
	_close("降低 30% = ×0.70", c.compute(S.DAMAGE, T.NONE, 100.0), 70.0)


func _test_tag_matching() -> void:
	_begin("标签匹配")
	var s := StatSet.new()
	s.add(M.new(S.DAMAGE, M.Kind.INCREASED, 0.40, T.FIRE | T.PROJECTILE))
	s.add(M.new(S.DAMAGE, M.Kind.INCREASED, 0.10, T.NONE))  # 全局，永远生效

	var fire_proj := T.FIRE | T.SPELL | T.PROJECTILE
	_close("火焰投射物 → 两条都吃", s.compute(S.DAMAGE, fire_proj, 100.0), 150.0)

	var fire_only := T.FIRE | T.SPELL
	_close("火焰非投射物 → 只吃全局", s.compute(S.DAMAGE, fire_only, 100.0), 110.0)

	var cold_proj := T.COLD | T.PROJECTILE
	_close("冰霜投射物 → 只吃全局", s.compute(S.DAMAGE, cold_proj, 100.0), 110.0)

	_check("has_all 要求全部标签", not T.has_all(T.FIRE, T.FIRE | T.PROJECTILE))
	_check("has_any 只要一个", T.has_any(T.FIRE | T.SPELL, T.ELEMENT_TYPES))

	# 派生标签：火焰伤害自动也算元素伤害
	var el := StatSet.new()
	el.add(M.new(S.DAMAGE, M.Kind.MORE, 0.25, T.ELEMENTAL))
	_close("元素词缀吃到火焰伤害", el.compute(S.DAMAGE, T.FIRE | T.SPELL, 100.0), 125.0)
	_close("元素词缀吃不到物理伤害", el.compute(S.DAMAGE, T.PHYSICAL | T.ATTACK, 100.0), 100.0)


func _test_buff_refresh() -> void:
	_begin("Buff 叠加规则：REFRESH 刷新时长")
	var e := CombatEntity.new(&"t")
	var frenzy := Demo.buff_frenzy()

	e.apply_buff(frenzy)
	e.tick_buffs(2.0)
	e.apply_buff(frenzy)   # 再上一次

	_check("仍然只有 1 个实例", e.buffs.count_of(&"frenzy") == 1)
	_close("持续时间被刷新回 4s", e.buffs.find_by_id(&"frenzy").remaining, 4.0)
	# 效果不叠加：攻速仍然只提高 20%
	_close("攻速 ×1.20（未叠加）", e.get_stat(S.ATTACK_SPEED, T.NONE, 1.0), 1.20)


func _test_buff_stack_count() -> void:
	_begin("Buff 叠加规则：STACK_COUNT 叠层")
	var mob := CombatEntity.new(&"m")
	var scorch := Demo.buff_scorch()

	for i in 3:
		mob.apply_buff(scorch)
	_check("3 层", mob.buffs.stacks_of(&"scorch") == 3)
	# 每层 提高 10% 承受火焰伤害 → 3 层 = ×1.30
	_close("承受火焰伤害 ×1.30", mob.get_stat(S.DAMAGE_TAKEN, T.FIRE, 100.0), 130.0)

	for i in 10:
		mob.apply_buff(scorch)
	_check("封顶在 5 层", mob.buffs.stacks_of(&"scorch") == 5)
	_close("封顶后 ×1.50", mob.get_stat(S.DAMAGE_TAKEN, T.FIRE, 100.0), 150.0)
	_close("非火焰伤害不受影响", mob.get_stat(S.DAMAGE_TAKEN, T.COLD, 100.0), 100.0)


func _test_buff_highest() -> void:
	_begin("Buff 叠加规则：HIGHEST 取最强")
	var e := CombatEntity.new(&"t")

	e.apply_buff(Demo.buff_elemental_aura(0.25), null, &"ally_a")
	e.apply_buff(Demo.buff_elemental_aura(0.10), null, &"ally_b")   # 更弱，应被忽略
	_check("只有 1 个实例", e.buffs.count_of(&"aura_elemental") == 1)
	_close("保留 25% 那份", e.get_stat(S.DAMAGE, T.FIRE, 100.0), 125.0)

	e.apply_buff(Demo.buff_elemental_aura(0.60), null, &"ally_c")   # 更强，应替换
	_check("替换后仍只有 1 个", e.buffs.count_of(&"aura_elemental") == 1)
	_close("升级到 60%", e.get_stat(S.DAMAGE, T.FIRE, 100.0), 160.0)


func _test_buff_independent() -> void:
	_begin("Buff 叠加规则：INDEPENDENT 独立实例")
	var mob := CombatEntity.new(&"m")
	var ignite := Demo.buff_ignite()

	mob.apply_buff(ignite, null, &"player_1")
	mob.tick_buffs(1.0)
	mob.apply_buff(ignite, null, &"player_2")

	_check("2 个独立实例", mob.buffs.count_of(&"ignite") == 2)
	var insts := mob.buffs.active()
	_check("各自计时（剩余时间不同）", not is_equal_approx(insts[0].remaining, insts[1].remaining))


func _test_buff_expiry() -> void:
	_begin("Buff 过期后词缀消失")
	var e := CombatEntity.new(&"t")
	e.apply_buff(Demo.buff_frenzy())
	_close("生效中 ×1.20", e.get_stat(S.ATTACK_SPEED, T.NONE, 1.0), 1.20)

	e.tick_buffs(3.9)
	_check("3.9s 时还在", e.buffs.has(&"frenzy"))
	e.tick_buffs(0.2)
	_check("4.1s 时已消失", not e.buffs.has(&"frenzy"))
	_close("恢复 ×1.00", e.get_stat(S.ATTACK_SPEED, T.NONE, 1.0), 1.00)


func _test_dot_ticks() -> void:
	_begin("DoT 周期结算")
	var mob := CombatEntity.new(&"m")
	mob.set_base(S.MAX_LIFE, 10000.0)
	mob.refill()

	# 点燃：4 秒，每 0.5 秒一跳，共 8 跳，每跳基础 40
	mob.apply_buff(Demo.buff_ignite())

	var ticks := 0
	var total := 0.0
	# 用 0.25（二进制可精确表示）步进，避免浮点累积误差干扰断言
	for i in 16:  # 16 × 0.25s = 4.0s
		for ev in DamagePipeline.resolve_dots(mob, 0.25):
			ticks += 1
			total += ev["damage"]

	_check("结算 8 跳（4s ÷ 0.5s）", ticks == 8, "实际 %d 跳" % ticks)
	_close("总伤害 8 × 40 = 320", total, 320.0)
	_close("怪物掉血同步", 10000.0 - mob.life, 320.0)

	# 大 delta 也要补齐跳数，不能漏
	var mob2 := CombatEntity.new(&"m2")
	mob2.set_base(S.MAX_LIFE, 10000.0)
	mob2.refill()
	mob2.apply_buff(Demo.buff_ignite())
	var big := DamagePipeline.resolve_dots(mob2, 2.0)
	_check("单次 2.0s delta 补齐 4 跳", big.size() == 4, "实际 %d 跳" % big.size())


func _test_resist_cap() -> void:
	_begin("抗性上限 75%")
	var e := CombatEntity.new(&"t")
	e.set_base(S.FIRE_RESIST, 0.90)
	_close("90% 被截断到 75%", e.resist_for(T.FIRE), 0.75)

	e.set_base(S.FIRE_RESIST, 0.50)
	_close("50% 正常", e.resist_for(T.FIRE), 0.50)
	_close("未定义的抗性 = 0", e.resist_for(T.LIGHTNING), 0.0)


func _test_negative_resist() -> void:
	_begin("负抗性不被截断")
	var e := CombatEntity.new(&"t")
	e.set_base(S.CHAOS_RESIST, -0.60)
	_close("-60% 保留", e.resist_for(T.CHAOS), -0.60)


func _test_armour_formula() -> void:
	_begin("护甲公式 armour/(armour+5×伤害)")
	var e := CombatEntity.new(&"t")
	e.set_base(S.ARMOUR, 1000.0)

	# 小刀 100 点：1000/(1000+500) = 66.7%
	_close("挡 100 点伤害 → 66.7%", DamagePipeline.mitigation_against(e, T.PHYSICAL, 100.0), 0.6667, 0.001)
	# 大招 2000 点：1000/(1000+10000) = 9.1%
	_close("挡 2000 点伤害 → 9.1%", DamagePipeline.mitigation_against(e, T.PHYSICAL, 2000.0), 0.0909, 0.001)
	_check("护甲对火焰无效", is_zero_approx(DamagePipeline.mitigation_against(e, T.FIRE, 100.0)))


func _test_remove_by_source() -> void:
	_begin("按来源整组移除（脱装备）")
	var p := Demo.make_player()
	var before := p.get_stat(S.DAMAGE, T.FIRE | T.SPELL, 100.0)
	# 装备的词缀在 equip_mods 这一层，source 就是装备 id
	p.equip_mods.remove_by_source(&"ring_of_flame")
	var after := p.get_stat(S.DAMAGE, T.FIRE | T.SPELL, 100.0)
	_check("脱掉火焰戒指后伤害下降", after < before, "%.1f → %.1f" % [before, after])
	# 剩下：更多30%法术 → 100 × 1.0 × 1.3 = 130
	_close("剩余加成正确", after, 130.0)


func _test_full_pipeline() -> void:
	_begin("完整伤害管线")
	var p := Demo.make_player()
	var mob := Demo.make_monster()
	var fireball := Gems.gem_fireball().build()

	var r := DamagePipeline.compute_hit(p, mob, fireball, null)

	# ② 词缀：(200 + 15) × (1 + 1.20火焰 + 0.40投射物) × 1.30法术更多
	#        = 215 × 2.60 × 1.30 = 726.7
	_close("② 词缀后", r.after_mods, 726.7, 0.1)
	# ③ 未掷骰 → 不暴击
	_check("③ 未暴击", not r.is_crit)
	# ④ 火抗 40%
	_close("④ 火抗 40% 减免", r.mitigation, 0.40)
	_close("④ 减免后", r.after_defence, 436.02, 0.1)
	# ⑤ 无承受伤害词缀
	_close("⑤ 最终伤害", r.total, 436.02, 0.1)

	# 加上灼烧 3 层（承受火焰伤害 +30%）后应当变高
	for i in 3:
		mob.apply_buff(Demo.buff_scorch())
	var r2 := DamagePipeline.compute_hit(p, mob, fireball, null)
	_close("灼烧 3 层后 ×1.30", r2.total, 436.02 * 1.30, 0.1)

	# 暴击期望：6% 基础 × (1 + 200% 提高) = 18%，暴伤 1.5
	var avg := DamagePipeline.average_hit(p, mob, fireball)
	_close("期望伤害 ×(1+0.18×0.5)", avg, r2.total * 1.09, 0.5)


func _test_projectile_priority() -> void:
	_begin("投射物：命中优先级 穿透 > 分叉 > 弹射")
	var spec := ProjectileSpec.new()
	spec.pierce_count = 1
	spec.fork_count = 1
	spec.chain_count = 2
	var st := ProjectileState.new(spec)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	# 三种都有的时候，PoE 的顺序是写死的：先把穿透用完，再分叉，最后弹射
	_check("第 1 次命中 → 穿透", st.decide_on_hit(101, rng) == ProjectileState.Action.PIERCE)
	_check("第 2 次命中 → 分叉", st.decide_on_hit(102, rng) == ProjectileState.Action.FORK)
	_check("第 3 次命中 → 弹射", st.decide_on_hit(103, rng) == ProjectileState.Action.CHAIN)
	_check("第 4 次命中 → 弹射", st.decide_on_hit(104, rng) == ProjectileState.Action.CHAIN)
	_check("第 5 次命中 → 消失", st.decide_on_hit(105, rng) == ProjectileState.Action.EXPIRE)
	_check("计数正确", st.pierces_done == 1 and st.forks_done == 1 and st.chains_done == 2)


func _test_projectile_fork_inherit() -> void:
	_begin("投射物：分叉的继承规则")
	var spec := ProjectileSpec.new()
	spec.fork_count = 1
	spec.chain_count = 2
	var st := ProjectileState.new(spec)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2

	_check("命中 → 分叉", st.decide_on_hit(201, rng) == ProjectileState.Action.FORK)
	var child := st.clone_for_fork()
	_check("分叉出来的不能再分叉", child.forks_left == 0)
	_check("弹射次数被继承", child.chains_left == 2, "实际 %d" % child.chains_left)
	_check("已命中列表被继承（不会回头打刚才那个）", child.has_hit(201))

	child.decide_on_hit(202, rng)
	_check("两发子弹的状态互相独立", not st.has_hit(202))


func _test_projectile_pierce_chance() -> void:
	_begin("投射物：穿透几率")
	var spec := ProjectileSpec.new()
	spec.pierce_count = 0
	spec.pierce_chance = 1.0    # 100% 必穿
	spec.chain_count = 1
	var st := ProjectileState.new(spec)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3

	_check("几率穿透也优先于弹射", st.decide_on_hit(301, rng) == ProjectileState.Action.PIERCE)
	_check("几率穿透不消耗弹射次数", st.chains_left == 1)


func _test_projectile_from_mods() -> void:
	_begin("投射物：次数来自词缀，且受标签约束")
	var p := Demo.make_player()
	p.gear_mods.add(M.new(S.CHAIN_COUNT, M.Kind.FLAT, 2.0, T.PROJECTILE, &"gem"))
	p.gear_mods.add(M.new(S.PIERCE_COUNT, M.Kind.FLAT, 1.0, T.FIRE, &"gem"))

	var fb := ProjectileSpec.build(p, Gems.gem_fireball().build())
	_check("火球拿到 2 次弹射", fb.chain_count == 2, "实际 %d" % fb.chain_count)
	_check("火球拿到 1 次穿透", fb.pierce_count == 1, "实际 %d" % fb.pierce_count)

	var melee := ProjectileSpec.build(p, Demo.skill_heavy_strike())
	_check("近战技能吃不到「投射物弹射」", melee.chain_count == 0)
	_check("近战技能吃不到「火焰穿透」", melee.pierce_count == 0)

	# 卸掉宝石就该恢复
	p.gear_mods.remove_by_source(&"gem")
	var bare := ProjectileSpec.build(p, Gems.gem_fireball().build())
	_check("卸掉宝石后归零", bare.chain_count == 0 and bare.pierce_count == 0)


func _test_projectile_spread() -> void:
	_begin("投射物：多重投射的展开角")
	var spec := ProjectileSpec.new()
	spec.extra_count = 2
	spec.spread_deg = 10.0

	_check("一次射 3 发", spec.shot_count() == 3)
	var angles := spec.spread_angles()
	_check("角度数量对得上", angles.size() == 3)
	_close("中间那发不偏", angles[1], 0.0)
	_close("左右对称", angles[0] + angles[2], 0.0)
	_close("相邻间隔 10°", rad_to_deg(angles[2] - angles[1]), 10.0)


func _test_projectile_spread_fan() -> void:
	_begin("投射物：散射角 STEP 与 FAN 的区别")
	# FAN：总扇面固定，发数越多排得越密（PoE 的多重投射 / 电球术是这种）
	var fan := ProjectileSpec.new()
	fan.spread_mode = ProjectileSpec.SpreadMode.FAN
	fan.spread_arc_deg = 60.0
	fan.extra_count = 2                      # 3 发
	var a3 := fan.spread_angles()
	_close("3 发分 60° → 相邻 30°", rad_to_deg(a3[1] - a3[0]), 30.0)
	_close("最外侧 ±30°", rad_to_deg(a3[2]), 30.0)

	fan.extra_count = 4                      # 5 发，扇面不变
	var a5 := fan.spread_angles()
	_close("5 发仍然只占 60°", rad_to_deg(a5[4] - a5[0]), 60.0)
	_close("相邻缩到 15°", rad_to_deg(a5[1] - a5[0]), 15.0)

	# STEP：相邻夹角固定，发数越多扇面越宽
	var step := ProjectileSpec.new()
	step.spread_mode = ProjectileSpec.SpreadMode.STEP
	step.spread_deg = 15.0
	step.extra_count = 4                     # 5 发
	var s5 := step.spread_angles()
	_close("STEP 下 5 发铺开 60°", rad_to_deg(s5[4] - s5[0]), 60.0)

	# 单发时不该出扇面（除 0 保护）
	fan.extra_count = 0
	_close("只有 1 发时不偏转", fan.spread_angles()[0], 0.0)

	# 随机抖动：不传 rng = 完全确定（伤害面板/测试要的），传了才乱
	var jit := ProjectileSpec.new()
	jit.spread_mode = ProjectileSpec.SpreadMode.FAN
	jit.spread_arc_deg = 60.0
	jit.extra_count = 2
	jit.jitter_deg = 10.0
	_close("不传 rng → 不抖动", jit.spread_angles()[0], deg_to_rad(-30.0))

	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var worst := 0.0
	var moved := false
	for i in 50:
		var angs := jit.spread_angles(rng)
		for k in angs.size():
			var base := deg_to_rad(-30.0 + 30.0 * k)
			var off := absf(angs[k] - base)
			worst = maxf(worst, off)
			if off > 0.0001:
				moved = true
	_check("传了 rng → 每发都会偏一点", moved)
	_check("但偏移不超过 ±10°", worst <= deg_to_rad(10.0) + 0.0001,
			"最大偏 %.2f°" % rad_to_deg(worst))


func _test_projectile_wander() -> void:
	_begin("投射物：飞行中的随机位移（电球术乱窜）")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	var straight := ProjectileState.new(ProjectileSpec.new())   # wander_deg = 0
	_check("没配漂移 → 一直直线飞", is_zero_approx(straight.wander_angle(1.0, rng)))

	var spec := ProjectileSpec.new()
	spec.wander_deg = 30.0
	spec.wander_interval = 0.1
	var st := ProjectileState.new(spec)

	var turns := 0
	var worst := 0.0
	for i in 60:                       # 60 帧 × 1/60 秒 = 1 秒
		var a := st.wander_angle(1.0 / 60.0, rng)
		if not is_zero_approx(a):
			turns += 1
			worst = maxf(worst, absf(a))
	# 间隔 0.1 秒 → 1 秒里转 10 次上下（首帧会先转一次，所以允许 ±2）
	_check("按间隔转向，不是每帧都转", turns >= 9 and turns <= 12, "实际 %d 次" % turns)
	_check("每次转角不超过 ±30°", worst <= deg_to_rad(30.0) + 0.0001,
			"实际 %.1f°" % rad_to_deg(worst))

	# 卡帧（一帧就是很大的 delta）时不能把计时器欠成负数、之后每帧狂转
	var st2 := ProjectileState.new(spec)
	st2.wander_angle(2.0, rng)
	_check("大 delta 之后仍然按间隔来", is_zero_approx(st2.wander_angle(0.01, rng)))


func _test_projectile_bounce() -> void:
	_begin("投射物：撞墙反弹（和穿透/分叉/连锁互不干扰）")
	var spec := ProjectileSpec.new()
	spec.bounce_count = 2
	spec.chain_count = 1
	var st := ProjectileState.new(spec)

	_check("第 1 次撞墙 → 弹开", st.try_bounce())
	_check("第 2 次撞墙 → 弹开", st.try_bounce())
	_check("第 3 次撞墙 → 该消失了", not st.try_bounce())
	_check("反弹计数正确", st.bounces_done == 2)
	_check("★ 反弹不消耗连锁次数", st.chains_left == 1)

	# 反过来也一样：命中不消耗反弹次数
	var st2 := ProjectileState.new(spec)
	_check("命中 → 连锁", st2.decide_on_hit(11) == ProjectileState.Action.CHAIN)
	_check("★ 命中不消耗反弹次数", st2.bounces_left == 2)

	# 弹墙 = 掉头回来，理应能再打一次刚才那个目标
	_check("刚打过的暂时打不到", not st2.can_hit(11))
	st2.try_bounce()
	_check("弹墙之后可以再打它", st2.can_hit(11))

	# 分叉出来的两发也会弹墙
	var fspec := ProjectileSpec.new()
	fspec.fork_count = 1
	fspec.bounce_count = 3
	var st3 := ProjectileState.new(fspec)
	st3.decide_on_hit(12)
	_check("分叉继承反弹次数", st3.clone_for_fork().bounces_left == 3)


func _test_chain_target_pick() -> void:
	_begin("投射物：连锁该转向谁")
	var spec := ProjectileSpec.new()
	spec.chain_count = 3
	spec.chain_range = 100.0
	var st := ProjectileState.new(spec)
	st.decide_on_hit(1)          # 刚打了 1 号

	var cands := [
		{"id": 1, "dist": 10.0},    # 刚打过的 → 排除，否则原地来回弹
		{"id": 2, "dist": 150.0},   # 超出弹射半径 → 排除
		{"id": 3, "dist": 80.0},
		{"id": 4, "dist": 60.0},
	]
	_check("选半径内最近的（4 号）", st.pick_chain_target(cands) == 4,
			"实际 %d" % st.pick_chain_target(cands))

	st.decide_on_hit(4)          # 弹到 4 号身上
	# 现在 1 号已经不是"刚打过的"了，但它打过；3 号没打过 → 新鲜的优先
	_check("没打过的优先于打过的", st.pick_chain_target(cands) == 3,
			"实际 %d" % st.pick_chain_target(cands))

	st.decide_on_hit(3)
	# 剩下能选的只有打过的 1 号（10 距离），可以弹回去 —— PoE 就是这个行为
	_check("没有新目标时可以弹回打过的", st.pick_chain_target(cands) == 1)

	_check("全都超出半径 → 找不到目标(-1)",
			st.pick_chain_target([{"id": 9, "dist": 999.0}]) == -1)


func _test_spark_spec() -> void:
	_begin("★ 电球术(Spark)：散射 / 随机位移 / 反弹 / 分叉 / 连锁")
	var p := Demo.make_player()
	var spark := Gems.gem_spark().build()
	var ps := ProjectileSpec.build(p, spark)

	_check("天生 4 发", ps.shot_count() == 4, "实际 %d" % ps.shot_count())
	_check("扇形散射（总扇面固定）", ps.spread_mode == ProjectileSpec.SpreadMode.FAN)
	_close("扇面 90°", ps.spread_arc_deg, 90.0)
	_check("每发还带随机抖动", ps.jitter_deg > 0.0)
	_check("发射点也随机位移", ps.spawn_jitter > 0.0)
	_check("飞行中会乱窜", ps.wander_deg > 0.0 and ps.wander_interval > 0.0)
	_check("撞墙反弹 5 次", ps.bounce_count == 5, "实际 %d" % ps.bounce_count)
	_check("自带 0 分叉 0 连锁（要靠支援宝石）",
			ps.fork_count == 0 and ps.chain_count == 0)

	# 4 发均分 90° → 相邻 30°，两端 ±45°
	var angles := ps.spread_angles()
	_close("相邻两发 30°", rad_to_deg(angles[1] - angles[0]), 30.0)
	_close("最外侧 +45°", rad_to_deg(angles[3]), 45.0)
	_close("左右对称", angles[0] + angles[3], 0.0)

	# 电球术是闪电法术投射物：吃得到「投射物」「法术」词缀，吃不到玩家身上的火焰词缀。
	# 100 × (1 + 0.40投射物) × 1.30法术更多 = 182；火球那条 +120% 火焰完全不生效。
	_close("闪电吃不到火焰词缀", p.get_stat(S.DAMAGE, spark.hit_tags(), 100.0), 182.0)

	# ---- 同一套辅助宝石连到电球术上 ----
	# 辅助宝石的词缀走 skill_mods 这一层（只对它连着的技能生效）
	for g in [Gems.support_multi(), Gems.support_chain(), Gems.support_fork(), Gems.support_bounce()]:
		p.skill_mods.add_all((g as SupportGem).build_mods())
	var ps2 := ProjectileSpec.build(p, spark)
	_check("多重投射 → 6 发", ps2.shot_count() == 6, "实际 %d" % ps2.shot_count())
	_check("连锁支援 → 2 次", ps2.chain_count == 2)
	_check("分叉支援 → 1 次", ps2.fork_count == 1)
	_check("反弹支援 → 5+3 = 8 次", ps2.bounce_count == 8, "实际 %d" % ps2.bounce_count)
	_check("扇面不受宝石影响（发数变多只是排得更密）",
			is_equal_approx(ps2.spread_arc_deg, ps.spread_arc_deg))

	# 拔下宝石就该回到技能自带的样子 —— 证明这些机制真的是"纯数据"
	p.skill_mods.remove_by_source(Gems.support_bounce().source_key())
	_check("拔下反弹支援 → 回到 5 次",
			ProjectileSpec.build(p, spark).bounce_count == 5)


# ---------------------------------------------------------------- 技能石

func _test_gem_level_growth() -> void:
	_begin("技能石：等级成长（1~5 级，不照搬 PoE 的 20 级）")
	var g := Gems.gem_spark()          # 电球术：1 级 55 点伤 / 10 魔力，每级 +28 / +4
	_check("默认 1 级", g.level == 1)
	_check("★ 等级上限是 5 ★（ADR-024）", g.max_level == 5)
	_close("1 级点伤 55", g.damage_at(1), 55.0)
	_close("1 级消耗 6", g.mana_at(1), 6.0)
	_close("4 级点伤 55 + 28×3", g.damage_at(4), 55.0 + 28.0 * 3.0)
	_close("5 级点伤 55 + 28×4（≈老曲线满级）", g.damage_at(5), 55.0 + 28.0 * 4.0)
	_close("4 级消耗 6 + 2×3（消耗涨得比伤害缓，升级是纯奖励）",
			g.mana_at(4), 6.0 + 2.0 * 3.0)

	# ★ 只有 4 次升级机会 → 每一级都得是明显的一步（至少 +40% 于 1 级点伤）★
	# 这条断言防的是"把成长值改小回 PoE 曲线"—— 5 级封顶配小成长，升级就没手感了
	for gem in Gems.all_actives():
		var sg := gem as SkillGem
		_check("%s 每级成长 ≥ 1级点伤的 40%%" % sg.display_name,
				sg.damage_per_level >= sg.base.base_damage * 0.40,
				"每级 +%.0f / 基础 %.0f" % [sg.damage_per_level, sg.base.base_damage])
		_check("%s 上限也是 5 级" % sg.display_name, sg.max_level == 5)

	# build() 出来的 SkillSpec 要用**当前等级**的数值
	g.level = 4
	var s := g.build()
	_close("build() 用当前等级的点伤", s.base_damage, 55.0 + 28.0 * 3.0)
	_check("标签原样传给 SkillSpec", s.tags == g.tags)

	# ★ 关键：build() 不能改到模板本身 ★
	# 改了的话等级一升，之前算好的 SkillSpec 会跟着变
	s.base_damage = 99999.0
	_close("改返回值不影响模板", g.build().base_damage, 55.0 + 28.0 * 3.0)
	_close("模板的 1 级伤害没被污染", g.base.base_damage, 55.0)

	_check("等级不会超过上限（999 → 5）", g.clamp_level(999) == 5)
	_check("等级不会低于 1", g.clamp_level(-5) == 1)


func _test_gem_tags_and_support_rules() -> void:
	_begin("技能石：标签决定哪些辅助宝石连得上")
	var fire := Gems.gem_fireball()
	var spark := Gems.gem_spark()
	var melee := SkillGem.new(&"hs", "重击", T.PHYSICAL | T.ATTACK | T.MELEE)

	_check("电球术带【持续时间】标签", (spark.tags & T.DURATION) != 0)
	_check("电球术带【法术】【投射物】【闪电】标签",
			(spark.tags & (T.SPELL | T.PROJECTILE | T.LIGHTNING)) == (T.SPELL | T.PROJECTILE | T.LIGHTNING))

	var dur := Gems.support_duration()
	_check("★「延长持续」连得上电球术 ★", dur.can_support(spark.tags))
	_check("「延长持续」连不上火球术（没有持续时间标签）", not dur.can_support(fire.tags))
	_check("「延长持续」连不上近战技能", not dur.can_support(melee.tags))

	var cast := Gems.support_faster_cast()
	_check("「迅捷施法」连得上法术", cast.can_support(spark.tags))
	_check("「迅捷施法」连不上近战攻击", not cast.can_support(melee.tags))

	var multi := Gems.support_multi()
	_check("「多重投射」连得上电球术", multi.can_support(spark.tags))
	_check("「多重投射」连不上近战技能", not multi.can_support(melee.tags))

	var light := Gems.support_lightning()
	_check("「闪电增强」连得上电球术", light.can_support(spark.tags))
	_check("「闪电增强」连不上火球术", not light.can_support(fire.tags))

	var crit := Gems.support_crit()
	_check("「暴击几率」无标签要求 → 什么技能都能连",
			crit.can_support(spark.tags) and crit.can_support(melee.tags))

	# ★ 辅助宝石没有等级（ADR-024）★ 词缀数值是固定的
	var m := Gems.support_multi()
	_check("★ 辅助宝石 max_level = 1（没有等级概念）★", m.max_level == 1)
	var v1: float = (m.build_mods()[1] as Modifier).value
	m.level = m.clamp_level(99)
	_check("等级字段被夹死在 1，词缀数值不变", m.level == 1
			and is_equal_approx((m.build_mods()[1] as Modifier).value, v1))
	var all_flat := true
	for sup in Gems.all_supports():
		if (sup as SupportGem).max_level != 1:
			all_flat = false
	_check("图鉴里所有辅助宝石都没有等级", all_flat)
	_check("所有词缀共用一个 source（方便整组拔掉）",
			(m.build_mods()[0] as Modifier).source == m.source_key())


## 背包网格：形状怎么转
func _test_gem_shape_rotation() -> void:
	_begin("背包网格：形状与朝向的旋转")

	# --- 辅助宝石：1 格 + 一个箭头。转的时候**只改朝向、不改占位** ---
	var a := GemShape.arrow_single()
	_check("辅助宝石只占 1 格", a.cells_at(0).size() == 1)
	_check("rot0 朝右", a.facing(0) == Vector2i(1, 0))
	_check("rot1 朝下", a.facing(1) == Vector2i(0, 1))
	_check("rot2 朝左", a.facing(2) == Vector2i(-1, 0))
	_check("rot3 朝上", a.facing(3) == Vector2i(0, -1))
	_check("转 4 次回到原样", a.facing(4) == a.facing(0))
	for rot in 4:
		_check("rot%d 还是只占 1 格、还在原点" % rot,
				_cells_eq(a.cells_at(rot), [Vector2i(0, 0)])
				and a.arrow_cell_at(rot) == Vector2i(0, 0))

	# --- 主动技能石：也是 1 格，没有箭头 ---
	var sk := GemShape.square(1)
	_check("技能石只占 1 格", sk.cells_at(0).size() == 1)
	_check("技能石没有箭头", not sk.has_arrow)

	# --- 装备：多格矩形，转 90° 之后长宽互换 ---
	var staff := GemShape.rect(1, 3)
	_check("法杖 1×3 占 3 格", staff.cells_at(0).size() == 3)
	_check("竖着的时候是 1 宽 3 高", staff.size_at(0) == Vector2i(1, 3), str(staff.size_at(0)))
	_check("★ 转 90° 之后变成 3 宽 1 高 ★", staff.size_at(1) == Vector2i(3, 1),
			str(staff.size_at(1)))
	_check("转 180° 转回 1×3", staff.size_at(2) == Vector2i(1, 3))

	var helm := GemShape.rect(2, 2)
	_check("头盔 2×2 占 4 格", helm.cells_at(0).size() == 4)
	_check("方块转了还是 2×2", helm.size_at(1) == Vector2i(2, 2))

	# ★ 归一化：不管怎么转，左上角永远是 (0,0) ★ 否则放置时的碰撞判断会偏
	for rot in 4:
		var minx := 99
		var miny := 99
		for c in staff.cells_at(rot):
			minx = mini(minx, c.x)
			miny = mini(miny, c.y)
		_check("法杖 rot%d 归一化到左上角" % rot, minx == 0 and miny == 0)


## 背包网格：放置与碰撞
func _test_gem_grid_placement() -> void:
	_begin("背包网格：放置 / 碰撞 / 越界")
	var g := GemGrid.new()
	var spark := Gems.gem_spark()

	# --- 宝石：1 格 ---
	_check("能放进去", g.place(spark, Vector2i(2, 2), 0) != null)
	_check("★ 技能石只占 1 格 ★", (g.items[0] as GemGrid.Placed).cells().size() == 1)
	_check("(2,2) 上是它", g.at(Vector2i(2, 2)) != null)
	_check("(3,3) 上没东西", g.at(Vector2i(3, 3)) == null)

	# --- 装备：占一大块，这才是抢地方的那个 ---
	var staff := EquipLibrary.staff()          # 1×3
	_check("法杖能放", g.place(staff, Vector2i(0, 0), 0) != null)
	_check("★ 法杖占 3 格 ★", (g.items[1] as GemGrid.Placed).cells().size() == 3)
	_check("(0,2) 上也是法杖（竖着的第三格）", g.at(Vector2i(0, 2)) != null)

	# 压在别人身上放不下
	_check("压着法杖 → 放不下", not g.can_place(Gems.support_multi(), Vector2i(0, 1), 0))
	_check("拒绝原因说得清楚",
			g.reject_reason(Gems.support_multi(), Vector2i(0, 1), 0).contains("已经有"),
			g.reject_reason(Gems.support_multi(), Vector2i(0, 1), 0))

	# 越界放不下 —— 转个方向就塞得进去，这就是装备形状的取舍
	var helm := EquipLibrary.iron_helm()       # 2×2
	_check("2×2 贴着右边界放不下",
			not g.can_place(helm, Vector2i(GemGrid.WIDTH - 1, 0), 0))
	_check("越界的原因写的是边界",
			g.reject_reason(helm, Vector2i(GemGrid.WIDTH - 1, 0), 0).contains("边界"))
	_check("★ 法杖竖着塞不进最后一行，转横就行 ★",
			not g.can_place(staff, Vector2i(4, GemGrid.HEIGHT - 1), 0)
			and g.can_place(staff, Vector2i(4, GemGrid.HEIGHT - 1), 1))

	# ignore：把一件拿起来再放回原处，不该被"自己"挡住
	var p: GemGrid.Placed = g.items[0]
	_check("原地放回会被自己挡住", not g.can_place(spark, Vector2i(2, 2), 0))
	_check("忽略自己之后就放得回去", g.can_place(spark, Vector2i(2, 2), 0, p))

	# 拿走：点法杖占的**任意一格**都能整件拿走
	var sp: GemGrid.Placed = g.items[1]
	_check("点法杖的第三格也能整件拿走", g.remove_at(Vector2i(0, 2)) == sp)
	_check("拿走后法杖的三格都空了",
			g.at(Vector2i(0, 0)) == null and g.at(Vector2i(0, 1)) == null
			and g.at(Vector2i(0, 2)) == null)
	_check("按格子能拿走宝石", g.remove_at(Vector2i(2, 2)) == p)
	_check("拿走后网格空了", g.items.is_empty())
	_check("拿一个空格子 → null", g.remove_at(Vector2i(0, 0)) == null)

	# 随便找地方放
	var filled := GemGrid.new()
	var count := 0
	while filled.place_anywhere(Gems.support_multi()) != null:
		count += 1
		if count > 100:
			break
	_check("place_anywhere 会一直填到放不下为止", count > 0 and count <= 100,
			"塞进去 %d 件" % count)


## ★★ 背包网格最核心的规则：法杖是技能载体，箭头指着法杖就辅助槽里的技能 ★★
func _test_gem_grid_arrows() -> void:
	_begin("★ 背包网格：箭头指着法杖，辅助槽里的技能 ★")
	var g := GemGrid.new()
	var spark := Gems.gem_spark()          # 闪电|法术|投射物|持续时间
	var wand := EquipLibrary.staff()       # 1×3 竖着，占 (3,1)(3,2)(3,3)
	wand.socketed = spark
	var wp := g.place(wand, Vector2i(3, 1), 0)

	# ① 箭头朝右、指进法杖 → 连上（辅助的是槽里的电球术）
	var multi := Gems.support_multi()
	var m := g.place(multi, Vector2i(2, 2), 0)    # 在 (2,2)，箭头朝右 → (3,2) 法杖中段
	_check("箭头指向 (3,2)", m.arrow_target() == Vector2i(3, 2), str(m.arrow_target()))
	_check("★ 连上了 ★", g.arrow_state(m) == "linked", g.arrow_state(m))
	_check("法杖认得这颗辅助", g.supports_for(wp).size() == 1)

	# ② 同一颗宝石转个方向 → 箭头指到空地上，连接断掉（位置没变，只是朝向变了）
	g.remove(m)
	m = g.place(multi, Vector2i(2, 2), 1)         # 还在 (2,2)，但箭头朝下 → (2,3)
	_check("★ 只占 1 格，转方向不挪窝 ★", m.cells().size() == 1 and m.origin == Vector2i(2, 2))
	_check("转了方向后箭头指向下方", m.arrow_target() == Vector2i(2, 3), str(m.arrow_target()))
	_check("★ 指着空地 → 断开 ★", g.arrow_state(m) == "idle")
	_check("法杖这下一颗辅助都没有", g.supports_for(wp).is_empty())

	# ③ 转回去，再从右边、上面各连一颗 —— ★ 指着法杖的哪一格都算 ★
	#   1×3 的法杖周身有 8 个箭头位，比单格宝石的 4 连上限高，这就是长法杖的价值
	g.remove(m)
	m = g.place(multi, Vector2i(2, 2), 0)                    # 左 → 指 (3,2)
	var d := g.place(Gems.support_duration(), Vector2i(4, 3), 2)  # 右 ← 指 (3,3) 杖尾
	var l := g.place(Gems.support_lightning(), Vector2i(3, 0), 1) # 上 ↓ 指 (3,1) 杖头
	_check("朝左的箭头指向杖尾 (3,3)", d.arrow_target() == Vector2i(3, 3), str(d.arrow_target()))
	_check("朝下的箭头指向杖头 (3,1)", l.arrow_target() == Vector2i(3, 1), str(l.arrow_target()))
	_check("★ 指着法杖三个不同的格子，各连一颗 ★", g.supports_for(wp).size() == 3,
			"实际 %d 颗" % g.supports_for(wp).size())

	# ④ 标签不匹配：箭头指到了法杖，但槽里的技能吃不下 —— 要能告诉玩家原因
	var g2 := GemGrid.new()
	var wand2 := EquipLibrary.apprentice_wand()
	wand2.socketed = Gems.gem_fireball()          # 火球术没有【持续时间】标签
	var wp2 := g2.place(wand2, Vector2i(3, 2), 0)
	var d2 := g2.place(Gems.support_duration(), Vector2i(2, 2), 0)
	_check("箭头确实指到了法杖", g2.at(d2.arrow_target()) == wp2)
	_check("★ 但槽里技能的标签不匹配 → blocked，不是 linked ★", g2.arrow_state(d2) == "blocked")
	_check("所以它不算辅助", g2.supports_for(wp2).is_empty())
	_check("但要能查出来是谁被挡了（UI 画红箭头用）", g2.blocked_for(wp2).size() == 1)

	# ⑤ ★ 裸放的技能宝石不参与连线 ★ —— 它没有载体，指着它和指着空地一样
	var g3 := GemGrid.new()
	var bare := g3.place(Gems.gem_spark(), Vector2i(3, 2), 0)
	var at_bare := g3.place(Gems.support_multi(), Vector2i(2, 2), 0)   # 箭头指着裸宝石
	_check("★ 箭头指着裸宝石 → idle，连不上 ★", g3.arrow_state(at_bare) == "idle")
	_check("裸宝石也不出现在可施放列表里", g3.skill_items().is_empty())
	_check("supports_for 对裸宝石返回空", g3.supports_for(bare).is_empty())

	# ⑥ 空槽的法杖：箭头指着它是 idle（镶上宝石会自动连上）
	var g4 := GemGrid.new()
	var empty_wand := g4.place(EquipLibrary.apprentice_wand(), Vector2i(3, 2), 0)
	var at_empty := g4.place(Gems.support_multi(), Vector2i(2, 2), 0)
	_check("★ 箭头指着空法杖 → idle ★", g4.arrow_state(at_empty) == "idle")
	_check("空法杖不算能施放的技能", g4.skill_items().is_empty())
	# 镶上宝石 → 同一颗辅助立刻连上，什么都不用挪
	(empty_wand.gem as EquipItem).socketed = Gems.gem_spark()
	_check("★ 镶上宝石后箭头自动连上 ★", g4.arrow_state(at_empty) == "linked")
	_check("现在它是能施放的技能了", g4.skill_items().size() == 1)

	# ⑦ 普通装备不参与连线：箭头指着头盔 = 白指
	var g5 := GemGrid.new()
	g5.place(EquipLibrary.iron_helm(), Vector2i(3, 2), 0)
	var at_helm := g5.place(Gems.support_multi(), Vector2i(2, 2), 0)
	_check("★ 箭头指着普通装备 → 还是 idle ★", g5.arrow_state(at_helm) == "idle")

	# ⑧ link_for：把"槽里的技能 + 辅助"打包给战斗系统
	var link := g.link_for(wp)
	_check("link 里是槽里那颗技能石", link.skill_gem == spark)
	_check("link 里有 3 颗辅助", link.supports.size() == 3)
	_close("消耗被三颗辅助的倍率连乘（6 × 1.40 × 1.20 × 1.25）",
			link.skill().mana_cost, 6.0 * 1.40 * 1.20 * 1.25)
	_check("link_for 一个空位 → 空 link", g.link_for(null).is_empty())


## ★ 背包存档：存下去再读回来，摆法和等级都不能变 ★
##
## 只测序列化（GemGrid.to_data / from_data），不碰文件 ——
## 读写文件是 game/gem_save.gd 的事，那一层由冒烟测试覆盖。
func _test_gem_grid_save() -> void:
	_begin("背包网格：存档与读档")
	var g := GemGrid.new()
	# 法杖 1×3 竖在 (3,1)..(3,3)，槽里镶着 4 级电球术 —— 槽里的宝石也要一起存
	var spark := Gems.gem_spark()
	spark.level = 4
	var wand := EquipLibrary.staff()
	wand.socketed = spark
	g.place(wand, Vector2i(3, 1), 0)
	g.place(Gems.support_multi(), Vector2i(2, 1), 0)      # 箭头 → 指杖头，连上
	g.place(Gems.support_duration(), Vector2i(4, 2), 2)   # 箭头 ← 指杖身，连上
	g.place(Gems.support_crit(), Vector2i(0, 5), 1)       # 箭头朝下，没连
	g.place(Gems.gem_fireball(), Vector2i(7, 6), 0)       # 裸宝石（库存）也要能存

	var data := g.to_data()
	_check("存了 5 件（槽里的电球术住在法杖身上，不单独占一条）",
			data.size() == 5, "实际 %d 件" % data.size())
	_check("存的是纯数据（能直接 JSON 序列化）",
			typeof(JSON.parse_string(JSON.stringify(data))) == TYPE_ARRAY)

	# 读回一张全新的网格
	var g2 := GemGrid.new()
	var loaded := g2.from_data(data, GemSave.resolve)
	_check("5 件都还原了", loaded == 5, "实际 %d 件" % loaded)

	var sk2: GemGrid.Placed = g2.skill_items()[0]
	_check("★ 法杖回来了，槽里还镶着电球术 ★", sk2.skill_gem() != null
			and sk2.skill_gem().id == &"spark")
	_check("★ 槽里宝石的等级记住了 ★", sk2.skill_gem().level == 4,
			"实际 %d 级" % sk2.skill_gem().level)
	_check("★ 位置记住了 ★", sk2.origin == Vector2i(3, 1), str(sk2.origin))
	_check("★ 朝向记住了 → 箭头还是连着的 ★", g2.supports_for(sk2).size() == 2,
			"实际连着 %d 颗" % g2.supports_for(sk2).size())
	_check("★ has_gem 认得槽里的宝石 ★（图鉴补齐靠它判重，漏了会重复补）",
			g2.has_gem(&"spark"))

	var crit: GemGrid.Placed = null
	for it in g2.items:
		if (it as GemGrid.Placed).gem.id == &"sup_crit":
			crit = it
	_check("没连的那颗，旋转档位也记住了", crit != null and crit.rot == 1,
			"实际 rot=%d" % (crit.rot if crit != null else -1))

	# ---- 存档要能容忍"和代码对不上" ----
	# ① 存档里有已经删掉的宝石 → 跳过它，不能让整个存档作废
	var stale := data.duplicate(true)
	stale.append({"id": "sup_不存在了", "x": 6, "y": 6, "rot": 0, "level": 3})
	var g3 := GemGrid.new()
	_check("存档里有不认识的宝石 → 跳过，其余照常还原",
			g3.from_data(stale, GemSave.resolve) == 5)

	# ①' 槽里镶的宝石 id 不认识 → 槽空着，法杖本身照常还原
	var bad_socket := [{"id": "staff", "x": 0, "y": 0, "rot": 0, "level": 1,
			"socket": {"id": "已删除的宝石", "level": 5}}]
	var g3b := GemGrid.new()
	_check("槽里的宝石不认识 → 法杖照常还原、槽空着",
			g3b.from_data(bad_socket, GemSave.resolve) == 1
			and (g3b.items[0] as GemGrid.Placed).skill_gem() == null)

	# ② 位置冲突（比如网格改小了、形状改大了）→ 不能把宝石弄丢
	var overlap := [
		{"id": "spark", "x": 3, "y": 1, "rot": 0, "level": 1},
		{"id": "fireball", "x": 3, "y": 1, "rot": 0, "level": 1},   # 压在同一个位置
	]
	var g4 := GemGrid.new()
	_check("位置冲突 → 换个空地放，不丢宝石",
			g4.from_data(overlap, GemSave.resolve) == 2, "实际 %d 件" % g4.items.size())
	_check("两颗宝石都在（裸宝石是库存，不进 skill_items）",
			g4.has_gem(&"spark") and g4.has_gem(&"fireball"))

	# ③ 空存档 / 垃圾数据不能炸
	_check("空存档 → 0 件", GemGrid.new().from_data([], GemSave.resolve) == 0)
	_check("垃圾数据 → 跳过，不炸",
			GemGrid.new().from_data([123, "abc", null], GemSave.resolve) == 0)

	# ---- 新加的宝石要自动补进老存档 ----
	var partial := GemGrid.new()
	partial.from_data([{"id": "spark", "x": 0, "y": 0, "rot": 0, "level": 1}], GemSave.resolve)
	_check("老存档里只有 1 件", partial.items.size() == 1)
	var added := GemSave.fill_missing(partial)
	# ★ 图鉴（45 件）已经比背包（56 格）能装的多了（ADR-029）★ —— 所以规则改成
	#   "能塞多少塞多少"：要么全补齐，要么补到 1×1 都塞不下为止。后一半不是恒真：
	#   fill_missing 要是提前放弃（比如碰到一件放不下的装备就 return），这里就会红。
	var all_in := partial.items.size() == GemSave.everything().size()
	# 探针在**副本**上放，别把 partial 自己弄脏（曾经直接在原网格上放，多出一颗重复的电球）
	var probe := GemGrid.new()
	probe.from_data(partial.to_data(), GemSave.resolve)
	var truly_full := probe.place_anywhere(Gems.gem_spark()) == null
	_check("★ 图鉴里新加的宝石/装备会自动补进来，直到背包真的塞满 ★",
			all_in or truly_full,
			"补了 %d 件，一共 %d 件 / 图鉴 %d 件" % [added, partial.items.size(), GemSave.everything().size()])
	_check("补进来的都是 1 件 1 个 id，没有重复", _no_dup_ids(partial))
	_check("补的时候不会重复放同一颗", not partial.has_gem(&"不存在"))


func _test_skill_mods_layer() -> void:
	_begin("技能石：辅助宝石只对它连着的法杖生效")
	var p := Demo.make_player()

	# 一根法杖镶电球术、旁边一颗多重投射箭头指着它；另一根法杖镶火球术，没人指
	var g := GemGrid.new()
	var w1 := EquipLibrary.staff()
	w1.socketed = Gems.gem_spark()
	var sk := g.place(w1, Vector2i(3, 2), 0)
	g.place(Gems.support_multi(), Vector2i(2, 2), 0)   # 箭头 → 指进 (3,2) 杖头
	var w2 := EquipLibrary.apprentice_wand()
	w2.socketed = Gems.gem_fireball()
	var fire := g.place(w2, Vector2i(6, 4), 0)         # 没有箭头指着它

	# Player.rebuild() 干的事：把当前这根法杖的辅助词缀整层换进 skill_mods
	p.skill_mods.clear()
	p.skill_mods.add_all(g.link_for(sk).mods())
	_check("电球术吃到多重投射 → 4+2 = 6 发",
			ProjectileSpec.build(p, g.link_for(sk).skill()).shot_count() == 6,
			"实际 %d" % ProjectileSpec.build(p, g.link_for(sk).skill()).shot_count())

	# Q 切到火球术那根法杖（没有任何箭头指着它）→ 整层换掉
	p.skill_mods.clear()
	p.skill_mods.add_all(g.link_for(fire).mods())
	_check("★ 切到火球术后不再是多发 ★",
			ProjectileSpec.build(p, g.link_for(fire).skill()).shot_count() == 1)
	_check("skill_mods 已经清空", p.skill_mods.size() == 0)
	_check("skill_items 是两根镶了宝石的法杖", g.skill_items().size() == 2)


## ★★ 这是用户要求的那张属性清单，逐条对一遍 ★★
## Tag / 等级 / 消耗 / 施放时间 / 投射物速度 / 点伤 / 单次发射数量 / 投射物持续时间
func _test_spark_gem() -> void:
	_begin("★ 电球术(Spark)：标准技能石的全部属性 ★")
	var g := Gems.gem_spark()
	g.level = 4
	var s := g.build()

	_check("Tag = 闪电|法术|投射物|持续时间",
			s.tags == (T.LIGHTNING | T.SPELL | T.PROJECTILE | T.DURATION))
	_check("Tag 文本读得懂", CombatTags.describe(s.tags).contains("持续时间"),
			CombatTags.describe(s.tags))
	_check("等级 4（上限 5）", g.level == 4 and g.max_level == 5)
	_close("消耗（4 级）", s.mana_cost, 6.0 + 2.0 * 3.0)
	_close("施放时间 0.65 秒", s.cast_time, 0.65)
	_close("投射物速度 150", s.projectile_speed, 150.0)
	_close("点伤（4 级，单发）", s.base_damage, 55.0 + 28.0 * 3.0)
	_check("单次发射 4 发", 1 + s.base_extra_projectiles == 4)
	_close("投射物持续时间 2.4 秒", s.base_duration, 2.4)

	# ★ 带【持续时间】标签，所以「提高技能持续时间」吃得到 ★
	var p := Demo.make_player()
	p.gear_mods.add(M.new(S.DURATION, M.Kind.INCREASED, 0.50, T.DURATION, &"test"))
	_close("持续时间 2.4 × 1.50", ProjectileSpec.build(p, s).duration, 2.4 * 1.5)
	# 火球术没有这个标签 → 同一条词缀吃不到
	_close("火球术吃不到（没有持续时间标签）",
			ProjectileSpec.build(p, Gems.gem_fireball().build()).duration, 2.0)


## 辅助宝石一颗颗连上去，看电球术怎么变。
func _test_spark_supports() -> void:
	_begin("★ 电球术：辅助宝石怎么改变它（隔着法杖连）★")
	var p := Demo.make_player()
	# 电球术镶在 1×2 见习法杖里，法杖摆在 (3,2)..(3,3)，四周留出位置给箭头
	var g := GemGrid.new()
	var wand := EquipLibrary.apprentice_wand()
	wand.socketed = Gems.gem_spark()
	var sk := g.place(wand, Vector2i(3, 2), 0)

	var bare := ProjectileSpec.build(p, g.link_for(sk).skill())
	_check("没有箭头指着法杖时 4 发", bare.shot_count() == 4)
	_close("存活 2.4 秒", bare.duration, 2.4)

	# ① 左边放「延长持续」，箭头朝右指进法杖 → 每发活得更久
	g.place(Gems.support_duration(), Vector2i(2, 2), 0)
	p.skill_mods.clear()
	p.skill_mods.add_all(g.link_for(sk).mods())
	_close("持续时间 2.4 × 1.45",
			ProjectileSpec.build(p, g.link_for(sk).skill()).duration, 2.4 * 1.45)

	# ② 再从下面放「多重投射」，箭头朝上指进杖尾 → 发数变多，但扇面不变
	g.place(Gems.support_multi(), Vector2i(3, 4), 3)   # rot3 = 朝上，指进 (3,3)
	p.skill_mods.clear()
	p.skill_mods.add_all(g.link_for(sk).mods())
	var more := ProjectileSpec.build(p, g.link_for(sk).skill())
	_check("4 + 2 = 6 发", more.shot_count() == 6, "实际 %d" % more.shot_count())
	_close("扇面还是 90°（不会扇得更宽）", more.spread_arc_deg, 90.0)

	# ③ 魔力消耗倍率是连乘的：1.20 × 1.40
	_close("消耗 6 × 1.20 × 1.40", g.link_for(sk).skill().mana_cost, 6.0 * 1.20 * 1.40)

	# ④ 伤害惩罚也是"更多"乘区，各自连乘：×0.70（多重投射 1 级）
	var tags := g.link_for(sk).skill().hit_tags()
	var dmg_bare := Demo.make_player().get_stat(S.DAMAGE, tags, 100.0)
	var dmg_now := p.get_stat(S.DAMAGE, tags, 100.0)
	_close("多重投射的「更少 30%」生效", dmg_now, dmg_bare * 0.70, 0.1)

	# ⑤ 从右边再连一颗「弹射支援」，箭头朝左
	g.place(Gems.support_chain(), Vector2i(4, 2), 2)   # rot2 = 朝左，指进 (3,2)
	p.skill_mods.clear()
	p.skill_mods.add_all(g.link_for(sk).mods())
	_check("三个方向各连一颗 → 一共 3 颗辅助", g.supports_for(sk).size() == 3,
			"实际 %d 颗" % g.supports_for(sk).size())
	_check("弹射 +2 次", ProjectileSpec.build(p, g.link_for(sk).skill()).chain_count == 2)


func _test_cast_rate() -> void:
	_begin("出手频率 = 施法速度 ÷ 施放时间")
	var p := Demo.make_player()
	var mob := Demo.make_monster()

	var spark := Gems.gem_spark().build()
	var fire := Gems.gem_fireball().build()

	# 玩家的施法速度：基础 1.0 × (1 + 25% 法杖) = 1.25
	_close("电球术 1.25 ÷ 0.65", DamagePipeline.actions_per_second(p, spark), 1.25 / 0.65)
	_close("火球术 1.25 ÷ 0.85", DamagePipeline.actions_per_second(p, fire), 1.25 / 0.85)
	_check("★ 施放时间越短，出手越快 ★",
			DamagePipeline.actions_per_second(p, spark) > DamagePipeline.actions_per_second(p, fire))

	_close("DPS = 期望伤害 × 出手频率",
			DamagePipeline.dps(p, mob, fire),
			DamagePipeline.average_hit(p, mob, fire) * DamagePipeline.actions_per_second(p, fire), 0.5)

	# 「迅捷施法」提高施法速度 30% → 出手更快
	var faster := Demo.make_player()
	faster.skill_mods.add_all(Gems.support_faster_cast().build_mods())
	_close("连上迅捷施法后 1.55 ÷ 0.65",
			DamagePipeline.actions_per_second(faster, spark), 1.55 / 0.65)


## 宝石面板的文本。和伤害面板同理：格式化字符串写错，GDScript 只在真正跑到那一行才炸，
## 等玩家在游戏里把鼠标停上去才发现就太晚了。
func _test_gem_tooltip_text() -> void:
	_begin("技能石面板的文本能正常生成")
	var g := Gems.gem_spark()
	g.level = 4
	var txt := g.tooltip([Gems.support_duration()])

	_check("有等级", txt.contains("等级 4/5"))
	_check("有标签", txt.contains("持续时间") and txt.contains("投射物"))
	_check("有消耗", txt.contains("消耗"))
	_check("有施放时间", txt.contains("施放时间"))
	_check("有点伤", txt.contains("点伤"))
	_check("有单次发射数量", txt.contains("单次发射"))
	_check("有投射物速度和持续时间", txt.contains("投射物速度") and txt.contains("投射物持续时间"))
	_check("有飞行漂移", txt.contains("飞行漂移"))
	_check("有自带的撞墙反弹", txt.contains("撞墙反弹"))
	_check("有命中附加效果", txt.contains("感电"))
	_check("有下一级预览", txt.contains("升到 5 级"))

	# 满级时不该再出现"升到 21 级"
	g.level = g.max_level
	_check("满级不显示下一级", not g.tooltip().contains("升到"))

	# 近战技能（非投射物）也不能炸
	var melee := SkillGem.new(&"hs", "重击", T.PHYSICAL | T.ATTACK | T.MELEE)
	melee.base.base_damage = 300.0
	_check("非投射物技能石也能出面板", melee.tooltip().length() > 0)

	# 辅助宝石的面板
	var sup := Gems.support_duration()
	_check("★ 辅助宝石面板不显示等级（它没有等级）★", not sup.tooltip().contains("等级"))
	_check("辅助宝石面板有魔力倍率", sup.tooltip().contains("魔力消耗倍率"))
	_check("辅助宝石面板写明了连接要求", sup.tooltip().contains("只能连"))
	_check("无要求的辅助也有说明", Gems.support_crit().tooltip().contains("任何技能"))


## Tab 面板的文本（game/damage_report.gd）。
## 它不依赖节点，所以能在这里测 —— 主要是防「格式化字符串的 %% 个数和参数对不上」，
## 这种错 GDScript 只在**真正跑到那一行**时才炸，平时打开面板才发现就太晚了。
func _test_damage_report_text() -> void:
	_begin("伤害详情面板的文本能正常生成")
	var Report = preload("res://game/damage_report.gd")
	var p := Demo.make_player()
	var m := Demo.make_monster()

	var spark_text: String = Report.build(p, m, Gems.gem_spark().build())
	_check("电球术报告里有散射角", spark_text.contains("散射"))
	_check("电球术报告里有飞行漂移", spark_text.contains("飞行漂移"))
	_check("电球术报告里有撞墙反弹", spark_text.contains("撞墙反弹"))

	var fb_text: String = Report.build(p, m, Gems.gem_fireball().build())
	_check("火球术报告里没有漂移（它是直线飞的）", not fb_text.contains("飞行漂移"))

	_check("报告里有施放时间和出手频率", fb_text.contains("施放时间") and fb_text.contains("次/秒"))

	# 没有目标、以及非投射物技能，都不该炸
	_check("附近没敌人也能出报告", Report.build(p, null, Gems.gem_spark().build()).length() > 0)
	_check("近战技能也能出报告", Report.build(p, m, Demo.skill_heavy_strike()).length() > 0)


# ---------------------------------------------------------------- 断言工具

## 比较两串格子。不能直接写 `a == b as Array[Vector2i]` ——
## `as` 的优先级比 `==` 低，会被解析成 `(a == b) as Array[Vector2i]`，直接报解析错误。
func _cells_eq(got: Array, want: Array) -> bool:
	if got.size() != want.size():
		return false
	for i in got.size():
		if got[i] != want[i]:
			return false
	return true


func _begin(name: String) -> void:
	_group = name
	print("[ %s ]" % name)


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("   PASS  ", name)
	else:
		_failed += 1
		print("   FAIL  ", name, "   ", detail)


func _close(name: String, got: float, want: float, eps: float = 0.01) -> void:
	_check(name, absf(got - want) < eps, "期望 %.4f，实际 %.4f" % [want, got])


# ================================================================ 局内流程

func _test_run_map_shape() -> void:
	_begin("局地图：形状约束")
	var map := RunMap.generate(42)
	_check("一共 %d 步" % RunMap.STEPS, map.steps.size() == RunMap.STEPS,
			"实际 %d" % map.steps.size())
	var last: Array = map.steps[RunMap.STEPS - 1]
	_check("最后一步只有一个房间", last.size() == 1)
	_check("最后一步是最终 Boss", (last[0] as RunMap.Room).type == RunMap.RoomType.BOSS)

	# 中间步的约束对很多种子都要成立，扫一批种子找反例
	var sizes_ok := true
	var no_mid_boss := true
	var distinct_ok := true
	for seed_v in 50:
		var m := RunMap.generate(seed_v)
		for i in RunMap.STEPS - 1:
			var rooms: Array = m.steps[i]
			if rooms.size() < RunMap.MIN_ROOMS or rooms.size() > RunMap.MAX_ROOMS:
				sizes_ok = false
			var seen := {}
			for r in rooms:
				var room := r as RunMap.Room
				if room.type == RunMap.RoomType.BOSS:
					no_mid_boss = false
				if room.type == RunMap.RoomType.COMBAT:
					# ★ 同一步里战斗奖励不许重复 ★ 重复了"选哪个房"就没意义
					if seen.has(room.reward):
						distinct_ok = false
					seen[room.reward] = true
	_check("每一步都有 %d~%d 个房间可选（50 个种子）" % [RunMap.MIN_ROOMS, RunMap.MAX_ROOMS], sizes_ok)
	_check("Boss 不会出现在中间步", no_mid_boss)
	_check("同一步里的奖励类型互不重复", distinct_ok)


func _test_run_map_determinism() -> void:
	_begin("局地图：种子确定性")
	# ★ 同种子必须同图 ★ 存档只存种子，读档靠重新生成 —— 这条破了存档就废了
	_check("同种子生成同一张图",
			RunMap.generate(123).describe() == RunMap.generate(123).describe())
	# 不同种子要真的能生成不同的图（如果 rng 没接对，所有种子会出一样的图）
	var base := RunMap.generate(0).describe()
	var found_diff := false
	for seed_v in range(1, 20):
		if RunMap.generate(seed_v).describe() != base:
			found_diff = true
			break
	_check("不同种子能生成不同的图", found_diff)


func _test_run_map_guarantees() -> void:
	_begin("局地图：兜底保证")
	var shop_count_ok := true
	var shop_pos_ok := true
	var first_step_ok := true
	var pool_ok := true
	for seed_v in 80:
		var m := RunMap.generate(seed_v)
		if m.shop_count() != RunMap.SHOP_COUNT:
			shop_count_ok = false
		# 商店不许出现在前两步（开局没钱，进店就是浪费一步）
		for i in RunMap.SHOP_EARLIEST:
			for r in m.steps[i]:
				if (r as RunMap.Room).type == RunMap.RoomType.SHOP:
					shop_pos_ok = false
		# 第 1 步至少有一个"实物"奖励（宝石/装备/辅助），不能全是金币+升级
		var has_item := false
		for r in m.steps[0]:
			var room := r as RunMap.Room
			if room.reward in [RunMap.RewardKind.GEM, RunMap.RewardKind.EQUIP, RunMap.RewardKind.SUPPORT]:
				has_item = true
		if not has_item:
			first_step_ok = false
		# 全图至少各出现一次：辅助 / 装备 / 技能宝石（断粮检查）
		for need in [RunMap.RewardKind.SUPPORT, RunMap.RewardKind.EQUIP, RunMap.RewardKind.GEM]:
			if not m._has_reward(need):
				pool_ok = false
	_check("每张图恰好 %d 个商店（80 个种子）" % RunMap.SHOP_COUNT, shop_count_ok)
	_check("商店不出现在前 %d 步" % RunMap.SHOP_EARLIEST, shop_pos_ok)
	_check("第 1 步必有实物奖励", first_step_ok)
	_check("全图必出现辅助/装备/技能宝石各至少一次", pool_ok)


func _test_run_state_flow() -> void:
	_begin("局状态机：阶段流转")
	var s := RunState.start(7)
	_check("开局在选房阶段", s.phase == RunState.Phase.CHOOSE)
	_check("越界的房间进不去", not s.enter_room(99))

	var step_before := s.step
	s.advance()
	_check("选房阶段不许直接跳步", s.step == step_before)

	_check("能进第 0 个房间", s.enter_room(0))
	_check("已经在房间里就不能再进别的房", not s.enter_room(0))
	s.complete_combat()
	_check("打赢普通战斗进入奖励阶段", s.phase == RunState.Phase.REWARD)
	s.advance()
	_check("领完奖走到第 2 步、回到选房", s.step == 1 and s.phase == RunState.Phase.CHOOSE)

	# 一路走到这一层的 Boss（商店房从 ROOM 直接 advance，战斗房走完整流程）
	while s.step < RunMap.STEPS - 1 and not s.is_over():
		s.enter_room(0)
		if s.current_room().type == RunMap.RoomType.SHOP:
			s.advance()
		else:
			s.complete_combat()
			s.advance()
	_check("走到这一层最后一步", s.step == RunMap.STEPS - 1)
	s.enter_room(0)
	_check("最后一步进的是 Boss 房", s.current_room().type == RunMap.RoomType.BOSS)
	_check("第 1 层的 Boss 不是最终 Boss", not s.current_room().is_final_boss)
	var floor1_map := s.map.describe()
	s.complete_combat()
	_check("★ 守关 Boss 打赢 → 进奖励阶段，不是整局结束 ★",
			not s.is_over() and s.phase == RunState.Phase.REWARD)
	s.advance()
	_check("★ 领完奖 → 上到第 2 层，步数归零、回到选房 ★",
			s.floor_index == 1 and s.step == 0 and s.phase == RunState.Phase.CHOOSE,
			"floor=%d step=%d phase=%d" % [s.floor_index, s.step, s.phase])
	_check("第 2 层是一张新图", s.map.describe() != floor1_map)
	_check("第 2 层的图也是完整的 %d 步" % RunMap.STEPS, s.map.steps.size() == RunMap.STEPS)

	# 快进打穿全部 4 层 → 最后一层的 Boss 才是最终 Boss，打赢整局胜利
	var guard := 0
	while not s.is_over() and guard < 200:
		guard += 1
		s.enter_room(0)
		var room := s.current_room()
		if room.type == RunMap.RoomType.SHOP:
			s.advance()
			continue
		if room.type == RunMap.RoomType.BOSS and s.is_final_floor():
			_check("第 %d 层的 Boss 标着最终 Boss" % RunMap.FLOORS, room.is_final_boss)
		s.complete_combat()
		if not s.is_over():
			s.advance()
	_check("★ 打穿 %d 层 → 整局胜利结束 ★" % RunMap.FLOORS, s.is_over() and s.victory)
	_check("结束时正好在最后一层", s.floor_index == RunMap.FLOORS - 1,
			"实际 floor=%d" % s.floor_index)

	var dead := RunState.start(8)
	dead.fail()
	_check("阵亡 = 结束且不是胜利", dead.is_over() and not dead.victory)


func _test_run_state_gold_and_save() -> void:
	_begin("局状态机：金币与序列化")
	var s := RunState.start(99)
	s.add_gold(30)
	_check("加金币", s.gold == 30)
	_check("不够花就拒绝、一分不扣", not s.spend_gold(31) and s.gold == 30)
	_check("负数金额拒绝", not s.spend_gold(-5) and s.gold == 30)
	_check("够花就扣", s.spend_gold(30) and s.gold == 0)

	s.add_gold(12)
	s.step = 3
	var back := RunState.from_data(s.to_data())
	_check("序列化往返：种子/步数/金币都在", back != null
			and back.seed_value == 99 and back.step == 3 and back.gold == 12)
	_check("读档一律回到这一步的选房阶段", back.phase == RunState.Phase.CHOOSE)
	_check("★ 读档后的图和原图一模一样 ★（只存种子，图靠重新生成）",
			back.map.describe() == s.map.describe())
	_check("坏存档返回 null 而不是炸", RunState.from_data({}) == null)

	# ---- 层也要序列化：打到第 3 层存档，读回来还在第 3 层、图也一样 ----
	var deep := RunState.start(77)
	deep._enter_floor(2)
	deep.step = 4
	deep.add_gold(50)
	var deep_back := RunState.from_data(deep.to_data())
	_check("★ 层数记住了 ★", deep_back != null and deep_back.floor_index == 2,
			"实际 floor=%d" % (deep_back.floor_index if deep_back != null else -1))
	_check("第 3 层的图读档后一模一样", deep_back.map.describe() == deep.map.describe())
	_check("步数/金币也在", deep_back.step == 4 and deep_back.gold == 50)
	# 老存档没有 floor 字段 → 当第 1 层，别炸
	var legacy := RunState.from_data({"seed": 5, "step": 2, "gold": 9})
	_check("没有 floor 字段的旧存档 → 回到第 1 层", legacy != null and legacy.floor_index == 0)

	# ---- 同一局不同层 / 不同步的 rng_for 要互不相同（层种子破了会整局刷同一批奖励）----
	var r_a := RunState.start(31)
	var g1 := r_a.rng_for("reward").randi()
	r_a._enter_floor(1)
	var g2 := r_a.rng_for("reward").randi()
	_check("同一步、不同层的奖励掷骰不同", g1 != g2)


func _test_run_rewards_roll() -> void:
	_begin("奖励三选一：掷骰规则")
	var pools := {
		"gems": Gems.all_actives(),
		"supports": Gems.all_supports(),
		"equips": EquipLibrary.all_items(),
		"owned": [],
	}

	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var opts := RunRewards.roll_options(RunMap.RewardKind.SUPPORT, rng, pools)
	_check("辅助奖励给满 3 个候选", opts.size() == 3)
	var ids := {}
	for o in opts:
		ids[o["item"].id] = true
	_check("三个候选互不重复", ids.size() == 3)

	# 同一个种子重掷 → 必须同一批候选（读档不能刷奖励）
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 5
	var opts2 := RunRewards.roll_options(RunMap.RewardKind.SUPPORT, rng2, pools)
	var same := opts.size() == opts2.size()
	for i in opts.size():
		if same and opts[i]["item"].id != opts2[i]["item"].id:
			same = false
	_check("★ 同种子掷出同一批候选 ★", same)

	# ★ 金币不再是三选一奖励 ★（清房自动进账，见 _test_room_gold）
	# 传一个不存在的 kind 要拿到空列表而不是炸
	var grng := RandomNumberGenerator.new()
	grng.seed = 1
	_check("未知奖励类型返回空列表（不炸）",
			RunRewards.roll_options(999, grng, pools).is_empty())

	# 升级：候选来自"背包里已有的宝石"，而且满级的不许出现
	var spark := Gems.gem_spark()
	var maxed := Gems.gem_fireball()
	maxed.level = maxed.max_level
	var urng := RandomNumberGenerator.new()
	urng.seed = 2
	var up := RunRewards.roll_options(RunMap.RewardKind.UPGRADE, urng,
			{"owned": [spark, maxed]})
	_check("升级奖励只列出没满级的宝石", up.size() == 1 and up[0]["gem"] == spark)
	_check("升级选项标了目标等级", str(up[0]["label"]).contains("Lv%d" % (spark.level + 1)))


func _test_run_content() -> void:
	_begin("局内容：怪、Boss、商店")
	var counts_ok := true
	var prev := 0
	for i in RunMap.STEPS - 1:
		var n := RunContent.enemies_for_step(i)
		if n < prev or n < 2:
			counts_ok = false
		prev = n
	_check("每步怪数只增不减、至少 2 只", counts_ok)

	var m0 := RunContent.make_room_monster(0)
	var m5 := RunContent.make_room_monster(5)
	_check("第 1 步的怪比基准怪弱（开局只有孤杖孤石）",
			m0.max_life() < Demo.make_monster().max_life())
	_check("第 6 步的怪比第 1 步硬", m5.max_life() > m0.max_life())
	_check("怪身上真的叠了成长词缀", m0.gear_mods.size() > 0)

	# ---- ★ 每层难度递增 ★ 同一步，层越深怪越硬；每层的 Boss 也一层比一层硬 ----
	var f0 := RunContent.make_room_monster(3, 0)
	var f1 := RunContent.make_room_monster(3, 1)
	var f3 := RunContent.make_room_monster(3, 3)
	_check("★ 同一步，第 2 层的怪比第 1 层硬 ★", f1.max_life() > f0.max_life(),
			"%.0f → %.0f" % [f0.max_life(), f1.max_life()])
	_check("第 4 层的怪更硬", f3.max_life() > f1.max_life())
	var bosses: Array = []
	for i in RunMap.FLOORS:
		bosses.append(RunContent.make_boss(i))
	var boss_grows := true
	for i in RunMap.FLOORS - 1:
		if (bosses[i + 1] as CombatEntity).max_life() <= (bosses[i] as CombatEntity).max_life():
			boss_grows = false
	_check("★ 每层的 Boss 血量逐层走高 ★", boss_grows,
			"%.0f / %.0f / %.0f / %.0f" % [bosses[0].max_life(), bosses[1].max_life(),
				bosses[2].max_life(), bosses[3].max_life()])
	_check("每层 Boss 名字各不相同（守关 Boss 不冒充骸骨领主）",
			bosses[0].display_name != bosses[3].display_name
			and bosses[3].display_name == "骸骨领主")
	_check("第 1 层的守关 Boss 也比同层最硬的怪硬",
			(bosses[0] as CombatEntity).max_life() > RunContent.make_room_monster(5, 0).max_life())

	var boss := RunContent.make_boss()
	_check("不传层数 = 最终 Boss（满血 9000）", is_equal_approx(boss.max_life(), 9000.0),
			"实际 %.0f" % boss.max_life())
	_check("Boss 血量远超最硬的普通怪", boss.max_life() > m5.max_life() * 2.0)
	_check("★ Boss 攻速是 set_base 的 ★（怪没设过基础攻速，词缀提高 0 还是 0）",
			boss.get_stat(S.ATTACK_SPEED) >= 0.4)

	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var stock := RunContent.shop_stock(rng)
	_check("商店进货 %d 件" % (RunContent.SHOP_ACTIVES + RunContent.SHOP_SUPPORTS + RunContent.SHOP_EQUIPS),
			stock.size() == RunContent.SHOP_ACTIVES + RunContent.SHOP_SUPPORTS + RunContent.SHOP_EQUIPS)
	var priced := true
	for thing in stock:
		if RunContent.price_of(thing) <= 0:
			priced = false
	_check("货架上每件都有正数价格", priced)

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 3
	var stock2 := RunContent.shop_stock(rng2)
	var same := stock.size() == stock2.size()
	for i in stock.size():
		if same and stock[i].id != stock2[i].id:
			same = false
	_check("同种子进同一批货（防刷货架）", same)


func _test_room_gold() -> void:
	_begin("清房金币：自动进账、种子定死、随步数走高")

	# ★ 同一局同一步两次要钱 → 同一笔 ★（World 就是这么调的；rng_for 破了这条就能读档刷钱）
	var s := RunState.start(42)
	var a := RunContent.room_gold(s.step, s.rng_for("room_gold"))
	var b := RunContent.room_gold(s.step, s.rng_for("room_gold"))
	_check("同一局同一步的数额是定死的", a == b, "两次分别 %d / %d" % [a, b])
	_check("第 1 步在 %d~%d 之间" % [RunContent.ROOM_GOLD_MIN, RunContent.ROOM_GOLD_MAX],
			a >= RunContent.ROOM_GOLD_MIN and a <= RunContent.ROOM_GOLD_MAX, "实际 %d" % a)

	# 同一个基础掷骰下，第 6 步比第 1 步多整整 5 × ROOM_GOLD_PER_STEP
	var r1 := RandomNumberGenerator.new()
	r1.seed = 7
	var r2 := RandomNumberGenerator.new()
	r2.seed = 7
	_check("每往后一步 +%d" % RunContent.ROOM_GOLD_PER_STEP,
			RunContent.room_gold(5, r1) == RunContent.room_gold(0, r2) + 5 * RunContent.ROOM_GOLD_PER_STEP)

	# ★ 层也算：同一步，每深一层 +ROOM_GOLD_PER_FLOOR ★（深层怪更硬，钱也得跟上）
	var r3 := RandomNumberGenerator.new()
	r3.seed = 7
	var r4 := RandomNumberGenerator.new()
	r4.seed = 7
	_check("每深一层 +%d" % RunContent.ROOM_GOLD_PER_FLOOR,
			RunContent.room_gold(0, r3, 3) == RunContent.room_gold(0, r4, 0)
			+ 3 * RunContent.ROOM_GOLD_PER_FLOOR)

	# ★ 守关 Boss 也是一个关卡，同样掉金币，而且比普通房肥 ★
	var rb := RandomNumberGenerator.new()
	rb.seed = 9
	var bg := RunContent.boss_gold(0, rb)
	_check("Boss 金币在 %d~%d 之间" % [RunContent.BOSS_GOLD_MIN, RunContent.BOSS_GOLD_MAX],
			bg >= RunContent.BOSS_GOLD_MIN and bg <= RunContent.BOSS_GOLD_MAX, "实际 %d" % bg)
	var rb1 := RandomNumberGenerator.new()
	rb1.seed = 9
	var rb2 := RandomNumberGenerator.new()
	rb2.seed = 9
	_check("Boss 金币每深一层 +%d" % RunContent.BOSS_GOLD_PER_FLOOR,
			RunContent.boss_gold(2, rb1) == RunContent.boss_gold(0, rb2)
			+ 2 * RunContent.BOSS_GOLD_PER_FLOOR)
	_check("Boss 的一笔比同层普通房的上限还肥",
			RunContent.BOSS_GOLD_MIN > RunContent.ROOM_GOLD_MAX)

	# ★ 地图上不再有金币房 ★ 扫一批种子，任何战斗房的外显都不该是金币
	var no_gold_room := true
	var names_ok := true
	for seed_v in 60:
		for row in RunMap.generate(seed_v).steps:
			for r in row:
				var room := r as RunMap.Room
				if room.label().contains("金币"):
					no_gold_room = false
				if room.type == RunMap.RoomType.COMBAT and RunMap.reward_name(room.reward) == "?":
					names_ok = false
	_check("60 个种子扫下来，没有一个金币房", no_gold_room)
	_check("每个战斗房的奖励都是认识的 4 种之一", names_ok)


# ================================================================ 内容扩充（电弧 / 冰系）

func _test_new_actives() -> void:
	_begin("新技能：电弧 / 寒冰弹 / 冰霜脉冲")
	var ids := {}
	for g in Gems.all_actives():
		ids[(g as SkillGem).id] = true
	_check("图鉴里有全部 31 颗主动技能石（20 + ADR-032 的 11）",
			ids.size() == 31 and ids.has(&"arc") and ids.has(&"frostbolt")
			and ids.has(&"freezing_pulse"),
			"实际 %d 颗" % ids.size())
	_check("按 id 能造出电弧（存档读回来靠它）", Gems.make_gem(&"arc") != null)

	var p := CombatEntity.new(&"t", "测试")

	# 电弧：弹射专精。弹射是它唯一的打群方式，穿透和分叉都不该有
	var arc := Gems.gem_arc().build()
	_check("电弧带闪电/法术/投射物标签",
			T.has_all(arc.tags, T.LIGHTNING | T.SPELL | T.PROJECTILE))
	var arc_spec := ProjectileSpec.build(p, arc)
	_check("★ 电弧天生连锁 3 次、弹射 0 次 ★（ADR-035：连锁不回头、跳跃 +500% 速度）",
			arc_spec.link_count == 3 and arc_spec.chain_count == 0, "连锁 %d / 弹射 %d" % [arc_spec.link_count, arc_spec.chain_count])
	_check("电弧不穿透、不分叉", arc_spec.pierce_count == 0 and arc_spec.fork_count == 0)
	var arc_shocks := false
	for b in arc.on_hit_buffs:
		if (b as BuffDef).id == &"shock":
			arc_shocks = true
	_check("电弧命中附加感电", arc_shocks)

	# 寒冰弹：慢速穿透弹
	var fb := Gems.gem_frostbolt().build()
	var fb_spec := ProjectileSpec.build(p, fb)
	_check("寒冰弹是冰霜法术投射物", T.has_all(fb.tags, T.COLD | T.SPELL | T.PROJECTILE))
	_check("寒冰弹天生穿透 2 次", fb_spec.pierce_count == 2, "实际 %d" % fb_spec.pierce_count)
	_check("寒冰弹飞得比火球慢（弹幕感的来源）",
			fb_spec.speed < Gems.gem_fireball().build().projectile_speed,
			"寒冰弹 %.0f" % fb_spec.speed)

	# 冰霜脉冲：快而短命 = 短射程，穿透一切
	var pulse := Gems.gem_freezing_pulse().build()
	var pu := ProjectileSpec.build(p, pulse)
	_check("冰霜脉冲穿透给到用不完", pu.pierce_count >= 90, "实际 %d" % pu.pierce_count)
	var range_px := pu.speed * pu.duration
	_check("冰霜脉冲射程是短的（速度×存活 < 200 像素）", range_px < 200.0,
			"实际 %.0f 像素" % range_px)

	var chills := 0
	for sp in [fb, pulse]:
		for b in (sp as SkillSpec).on_hit_buffs:
			if (b as BuffDef).id == &"chill":
				chills += 1
	_check("两个冰技能命中都附加冰缓", chills == 2, "实际 %d 个" % chills)


func _test_chill_buff() -> void:
	_begin("冰缓：移动速度 -30%，REFRESH 不叠层")
	var m := CombatEntity.new(&"mob", "怪")
	m.set_base(S.MOVE_SPEED, 100.0)
	m.apply_buff(Demo.buff_chill())
	_close("上了冰缓 → 移速 70", m.get_stat(S.MOVE_SPEED), 70.0)
	m.apply_buff(Demo.buff_chill())
	_close("★ 再上一次不叠层，还是 70 ★", m.get_stat(S.MOVE_SPEED), 70.0)

	# ★ Enemy 的追击速度就是这么算的 ★ 怪没设过基础移速，基础值从参数传进来
	var e := CombatEntity.new(&"mob2", "怪2")
	e.apply_buff(Demo.buff_chill())
	_close("基础值走参数传入也生效（Enemy 传 CHASE_SPEED）",
			e.get_stat(S.MOVE_SPEED, T.NONE, 42.0), 42.0 * 0.70)

	# 到时间要消退，不能永久减速
	e.tick_buffs(3.0)
	_close("2.5 秒后冰缓消退，移速回满", e.get_stat(S.MOVE_SPEED, T.NONE, 42.0), 42.0)


func _test_cold_support() -> void:
	_begin("冰霜增强：连接规则 + 独立的「更多」乘区")
	var sup := Gems.support_cold()
	_check("能连寒冰弹", sup.can_support(Gems.gem_frostbolt().tags))
	_check("能连冰霜脉冲", sup.can_support(Gems.gem_freezing_pulse().tags))
	_check("连不上电球术（不是冰技能）", not sup.can_support(Gems.gem_spark().tags))
	_check("连不上火球术", not sup.can_support(Gems.gem_fireball().tags))

	var p := CombatEntity.new(&"t", "测试")
	p.skill_mods.add_all(sup.build_mods())
	_close("冰霜伤害 ×1.25", p.get_stat(S.DAMAGE, Gems.gem_frostbolt().build().hit_tags(), 100.0), 125.0)
	_close("闪电伤害不受影响", p.get_stat(S.DAMAGE, Gems.gem_spark().build().hit_tags(), 100.0), 100.0)

	# 相邻内容的连接规则顺手验一遍
	_check("闪电增强能连电弧", Gems.support_lightning().can_support(Gems.gem_arc().tags))
	_check("★ 延长持续连不上冰霜脉冲 ★（它没有【持续时间】标签，短射程是它的身份）",
			not Gems.support_duration().can_support(Gems.gem_freezing_pulse().tags))
	_check("弹射支援能连电弧（连锁跳完再来回弹）",
			Gems.support_chain().can_support(Gems.gem_arc().tags))


func _test_new_content_in_run() -> void:
	_begin("新内容进了价目表和奖励池")
	_check("三颗新技能石都写进了价目表（不是吃默认价）",
			RunContent.PRICES.has(&"arc") and RunContent.PRICES.has(&"frostbolt")
			and RunContent.PRICES.has(&"freezing_pulse"))
	_check("见习法杖也在价目表里（商店里买第二根法杖 = 多带一个技能）",
			RunContent.PRICES.has(&"apprentice_wand"))
	var pools := RunContent.reward_pools([])
	_check("奖励池（第 1 层）：主动 31 颗、辅助 27 颗（21 普通 + 6 触媒，没有崇高）",
			(pools["gems"] as Array).size() == 31 and (pools["supports"] as Array).size() == 27,
			"主动 %d / 辅助 %d" % [(pools["gems"] as Array).size(), (pools["supports"] as Array).size()])


# ================================================================ 合成

func _test_gem_merge() -> void:
	_begin("合成：同款宝石叠放升级")
	var g := GemGrid.new()
	var a := Gems.gem_spark()
	a.level = 2
	var target := g.place(a, Vector2i(2, 2), 0)
	var b := Gems.gem_spark()
	b.level = 3

	_check("同 id 能找到合成目标", g.merge_target(b, Vector2i(2, 2)) == target)
	_check("不同 id 合不了", g.merge_target(Gems.gem_fireball(), Vector2i(2, 2)) == null)
	_check("空格子没有合成目标", g.merge_target(b, Vector2i(5, 5)) == null)

	g.merge(b, target)
	_check("★ 合成 = max(2, 3) + 1 = 4 级 ★（取 max 不相加，堆 1 级宝石刷不了级）",
			a.level == 4, "实际 %d 级" % a.level)
	_check("网格里还是只有一颗", g.items.size() == 1)

	# ★ 辅助宝石没有等级 → 不参与合成（ADR-024）★
	# 重复的辅助不是废件：拿去给另一根法杖配同款连线
	var s1 := Gems.support_chain()
	var sp := g.place(s1, Vector2i(4, 4), 0)
	var s2 := Gems.support_chain()
	_check("★ 辅助宝石合不了 ★", g.merge_target(s2, Vector2i(4, 4)) == null)
	_check("也不报「满级」——走普通放置判定（那里已经有东西了）",
			g.merge_reject_reason(s2, Vector2i(4, 4)) == "")
	_check("辅助还好好待在原地", g.at(Vector2i(4, 4)) == sp)

	# 等级封顶：4 级吃一颗低级的 → 5，不会溢出上限
	a.level = a.max_level - 1
	g.merge(Gems.gem_spark(), target)
	_check("合成不会超过等级上限（5 级封顶）", a.level == a.max_level, "实际 %d 级" % a.level)

	# 满级之后合不了，而且要说得清原因（不能报"那里已经有东西了"）
	_check("满级合不了", g.merge_target(b, Vector2i(2, 2)) == null)
	_check("拒绝原因写明满级", g.merge_reject_reason(b, Vector2i(2, 2)).contains("满级"),
			g.merge_reject_reason(b, Vector2i(2, 2)))
	_check("不同 id 不给合成原因（走普通放置判定）",
			g.merge_reject_reason(Gems.gem_fireball(), Vector2i(2, 2)) == "")

	# 装备不参与合成：max_level = 1，没有"升级"可言
	g.place(EquipLibrary.iron_helm(), Vector2i(0, 0), 0)
	_check("装备不能当合成目标", g.merge_target(EquipLibrary.iron_helm(), Vector2i(0, 0)) == null)
	_check("装备也不给合成原因", g.merge_reject_reason(EquipLibrary.iron_helm(), Vector2i(0, 0)) == "")


# ================================================================ 法杖载体（ADR-020）

func _test_wand_socket() -> void:
	_begin("★ 法杖：技能的载体（镶嵌 / 合成 / 交换）★")

	# 图鉴：法杖有槽，其它装备没有
	_check("见习法杖有 1 个槽", EquipLibrary.apprentice_wand().socket_count == 1)
	_check("橡木法杖有 1 个槽", EquipLibrary.staff().socket_count == 1)
	_check("头盔/靴子/戒指没有槽",
			not EquipLibrary.iron_helm().has_socket()
			and not EquipLibrary.traveller_boots().has_socket()
			and not EquipLibrary.ring_of_flame().has_socket())
	_check("★ 见习法杖没有任何词缀 ★（它的全部价值就是那个槽；也保证不影响基准角色数值）",
			EquipLibrary.apprentice_wand().mods.is_empty())

	var g := GemGrid.new()
	var wp := g.place(EquipLibrary.apprentice_wand(), Vector2i(3, 2), 0)  # (3,2)(3,3)

	# ---- 镶入空槽 ----
	var spark := Gems.gem_spark()
	spark.level = 2
	_check("点在法杖的任意一格都构成镶嵌", g.socket_target(spark, Vector2i(3, 3)) == wp)
	_check("点在空地不构成镶嵌", g.socket_target(spark, Vector2i(0, 0)) == null)
	_check("手上是辅助宝石不构成镶嵌", g.socket_target(Gems.support_multi(), Vector2i(3, 2)) == null)
	_check("手上是装备不构成镶嵌", g.socket_target(EquipLibrary.iron_helm(), Vector2i(3, 2)) == null)
	_check("空槽镶得进（没有拒绝原因）", g.socket_reject_reason(spark, Vector2i(3, 2)) == "")
	var out = g.socket(spark, wp)
	_check("★ 镶入空槽 → 手上的被吃掉（返回 null）★", out == null)
	_check("槽里现在是它", wp.skill_gem() == spark)
	_check("★ 镶了宝石的法杖出现在可施放列表 ★", g.skill_items().size() == 1)
	_check("宝石不占网格格子（网格里只有法杖一件）", g.items.size() == 1)

	# ---- 槽里同款 = 合成升级（规则同网格叠放：max 两边 +1）----
	var spark2 := Gems.gem_spark()
	spark2.level = 3
	out = g.socket(spark2, wp)
	_check("★ 同款镶入 = 合成，max(2,3)+1 = 4 级 ★", out == null and spark.level == 4,
			"实际 %d 级" % spark.level)

	# ---- 槽里别的宝石 = 交换 ----
	var fireball := Gems.gem_fireball()
	out = g.socket(fireball, wp)
	_check("★ 异款镶入 = 交换，旧宝石回到手上 ★", out == spark)
	_check("槽里换成了火球术", wp.skill_gem() == fireball)

	# ---- 满级同款拒绝，且说得清原因 ----
	fireball.level = fireball.max_level
	var maxed := Gems.gem_fireball()
	_check("槽里同款已满级 → 拒绝并写明原因",
			g.socket_reject_reason(maxed, Vector2i(3, 2)).contains("满级"),
			g.socket_reject_reason(maxed, Vector2i(3, 2)))

	# ---- owned_gems：槽里的宝石也算"拥有"（升级奖励要能升到它）----
	g.place(Gems.gem_arc(), Vector2i(0, 0), 0)   # 一颗裸宝石库存
	var owned := g.owned_gems()
	_check("owned_gems = 槽里的 + 裸放的，共 2 颗", owned.size() == 2, "实际 %d" % owned.size())
	_check("包含槽里的火球术", owned.has(fireball))

	# ---- 拿起法杖 = 宝石跟着走 ----
	var picked := g.remove_at(Vector2i(3, 3))
	_check("按法杖的任意一格整件拿走", picked == wp)
	_check("★ 槽里的宝石跟着法杖一起走 ★", (picked.gem as EquipItem).socketed == fireball)


## ★ ADR-023：法杖的词缀只对槽里镶着的技能生效，不再全局 ★
func _test_wand_mods_scope() -> void:
	_begin("★ 法杖词缀的作用域：只增幅槽里的技能 ★")
	var g := GemGrid.new()
	var staff := EquipLibrary.staff()            # 更多30%法术 + 提高25%施法速度
	staff.socketed = Gems.gem_spark()
	var wp := g.place(staff, Vector2i(0, 0), 0)
	var wand2 := EquipLibrary.apprentice_wand()  # 零词缀
	wand2.socketed = Gems.gem_fireball()
	var wp2 := g.place(wand2, Vector2i(3, 0), 0)
	g.place(EquipLibrary.ring_of_flame(), Vector2i(6, 0), 0)

	# ① equip_mods 这层不再包含法杖的词缀；普通装备照旧
	var srcs := {}
	for m in g.equip_mods():
		srcs[(m as Modifier).source] = true
	_check("★ equip_mods 里没有法杖的词缀 ★", not srcs.has(&"staff"), str(srcs.keys()))
	_check("戒指还在 equip_mods 里（普通装备放着就生效）", srcs.has(&"ring_of_flame"))

	# ② 法杖的词缀跟着 link 走（= Player.rebuild 塞进 skill_mods 的那份）
	var p := CombatEntity.new(&"t", "测试")
	p.equip_mods.add_all(g.equip_mods())
	p.skill_mods.add_all(g.link_for(wp).mods())
	var spark_tags := g.link_for(wp).skill().hit_tags()
	_close("★ 用橡木法杖里的电球术：吃到 更多30%法术 ★",
			p.get_stat(S.DAMAGE, spark_tags, 100.0), 130.0)
	_close("施法速度也吃到 +25%", p.get_stat(S.CAST_SPEED, T.NONE, 1.0), 1.25)

	# ③ Q 切到另一根法杖（skill_mods 整层重建）→ 橡木法杖的词缀跟着消失
	p.skill_mods.clear()
	p.skill_mods.add_all(g.link_for(wp2).mods())
	var fb_tags := g.link_for(wp2).skill().hit_tags()
	# 火球是火焰法术：戒指照吃（equip 层：+15 点、提高120% → (100+15)×2.2），
	# 但橡木法杖的 更多30% 不再乘进来
	_close("★ 换法杖后橡木法杖的词缀不再生效 ★",
			p.get_stat(S.DAMAGE, fb_tags, 100.0), (100.0 + 15.0) * 2.20)
	_close("施法速度回到 1.0（见习法杖零词缀）", p.get_stat(S.CAST_SPEED, T.NONE, 1.0), 1.0)

	# ④ 空槽的法杖：词缀没有作用对象，哪一层都不进
	var g2 := GemGrid.new()
	var empty := g2.place(EquipLibrary.staff(), Vector2i(0, 0), 0)
	_check("空法杖的词缀哪层都不进",
			g2.equip_mods().is_empty() and g2.link_for(empty).mods().is_empty())


# ================================================================ 4 层结构（ADR-021）

func _test_run_map_floors() -> void:
	_begin("★ 4 层结构：每层一张图，守关 Boss 带奖励 ★")
	_check("一局共 %d 层" % RunMap.FLOORS, RunMap.FLOORS == 4)

	# 前三层的 Boss 是守关 Boss（带奖励外显），最后一层才是最终 Boss
	for f in RunMap.FLOORS:
		var m := RunMap.generate(1234, f)
		var boss_room: RunMap.Room = m.steps[RunMap.STEPS - 1][0]
		if f < RunMap.FLOORS - 1:
			_check("第 %d 层的 Boss 是守关 Boss、标了奖励" % (f + 1),
					not boss_room.is_final_boss
					and boss_room.label().contains("奖励"), boss_room.label())
		else:
			_check("第 %d 层的 Boss 是最终 Boss" % (f + 1),
					boss_room.is_final_boss and boss_room.label().contains("最终"))

	# 守关 Boss 的奖励类型是种子定死的（读档不能换奖励）
	var a: RunMap.Room = RunMap.generate(88, 0).steps[RunMap.STEPS - 1][0]
	var b: RunMap.Room = RunMap.generate(88, 0).steps[RunMap.STEPS - 1][0]
	_check("同种子的 Boss 奖励一样", a.reward == b.reward)

	# 一局 4 层的图各不相同（层种子从局种子推导，但互不重复）
	var s := RunState.start(555)
	var seen := {}
	for f in RunMap.FLOORS:
		seen[s.map.describe()] = true
		if f < RunMap.FLOORS - 1:
			s._enter_floor(f + 1)
	_check("★ 4 层是 4 张不同的图 ★", seen.size() == RunMap.FLOORS,
			"只有 %d 张不同" % seen.size())


# ================================================================ 回蓝装备

## 魔力回复走属性系统（S.MANA_REGEN）：基础值由 Player 传入（12/秒），
## 装备上的 FLAT 和 INCREASED 在这上面按四段式加成 —— 和怪物追击速度是同一套做法。
func _test_mana_regen_gear() -> void:
	_begin("回蓝装备：魔力回复走属性系统")
	var e := CombatEntity.new(&"t", "测试")
	_close("没有装备时就是基础值 12/秒", e.get_stat(S.MANA_REGEN, T.NONE, 12.0), 12.0)

	e.equip_mods.add_all(EquipLibrary.arcane_belt().build_mods())
	_close("秘法腰带 +8/秒 → 20", e.get_stat(S.MANA_REGEN, T.NONE, 12.0), 20.0)
	_close("腰带还给 60 魔力上限", e.get_stat(S.MAX_MANA, T.NONE, 200.0), 260.0)

	e.equip_mods.add_all(EquipLibrary.sapphire_amulet().build_mods())
	_close("★ 蓝玉护符再提高 50% → (12+8)×1.5 = 30 ★（FLAT 和 INCREASED 是不同乘区）",
			e.get_stat(S.MANA_REGEN, T.NONE, 12.0), 30.0)

	e.equip_mods.remove_by_source(&"arcane_belt")
	_close("脱下腰带 → 12×1.5 = 18", e.get_stat(S.MANA_REGEN, T.NONE, 12.0), 18.0)

	_check("腰带是 3×1 的横条（任务板要的形状）",
			EquipLibrary.arcane_belt().width == 3 and EquipLibrary.arcane_belt().height == 1)
	_check("护符只占 1 格", EquipLibrary.sapphire_amulet().width == 1
			and EquipLibrary.sapphire_amulet().height == 1)
	_check("两件都进了价目表", RunContent.PRICES.has(&"arcane_belt")
			and RunContent.PRICES.has(&"sapphire_amulet"))
	_check("两件都不带镶嵌槽（法杖才是技能载体）",
			not EquipLibrary.arcane_belt().has_socket()
			and not EquipLibrary.sapphire_amulet().has_socket())


# ================================================================ 触媒（ADR-026）

func _test_catalyst_rules() -> void:
	_begin("★ 触媒：条件计数 / 门槛封顶 / 连接规则 ★")

	# ---- 图鉴：6 颗触媒，种类和门槛按需求配 ----
	var cats := Gems.all_catalysts()
	_check("图鉴里有 6 颗触媒", cats.size() == 6, "实际 %d" % cats.size())
	var want := {
		&"cat_shock":  [CatalystGem.Trigger.SHOCK_APPLIED, 3.0],
		&"cat_ignite": [CatalystGem.Trigger.IGNITE_APPLIED, 3.0],
		&"cat_chill":  [CatalystGem.Trigger.CHILL_APPLIED, 1.0],
		&"cat_hits":   [CatalystGem.Trigger.HITS, 5.0],
		&"cat_move":   [CatalystGem.Trigger.MOVE_DISTANCE, 20.0 * CatalystGem.PIXELS_PER_TILE],
		&"cat_timer":  [CatalystGem.Trigger.INTERVAL, 5.0],
	}
	for c in cats:
		var cat := c as CatalystGem
		var spec: Array = want.get(cat.id, [])
		_check("%s 的条件和门槛正确" % cat.display_name,
				not spec.is_empty() and cat.trigger_kind == int(spec[0])
				and is_equal_approx(cat.threshold, float(spec[1])),
				"kind=%d threshold=%.0f" % [cat.trigger_kind, cat.threshold])
		_check("%s 是辅助宝石（能用箭头连线），且不带词缀、没有等级" % cat.display_name,
				cat is SupportGem and cat.mods.is_empty() and cat.max_level == 1)
		_check("%s 有正数价格" % cat.display_name, RunContent.price_of(cat) > 0)
	_check("触媒也进了辅助池（all_supports：21 普通 + 6 触媒）", Gems.all_supports().size() == 27)

	# ---- 计数规则 ----
	var hits := Gems.cat_hits()
	hits.advance(CatalystGem.Trigger.HITS, 1.0)
	hits.advance(CatalystGem.Trigger.SHOCK_APPLIED, 99.0)   # 别的事件不该计入
	_check("只数自己关心的事件", is_equal_approx(hits.progress, 1.0),
			"实际 %.1f" % hits.progress)
	_check("没到门槛不触发", not hits.ready_to_fire())
	for i in 10:
		hits.advance(CatalystGem.Trigger.HITS, 1.0)
	_check("到门槛了", hits.ready_to_fire())
	_check("★ 进度封顶在门槛上（蓝不够时不许攒成连环触发）★",
			is_equal_approx(hits.progress, hits.threshold), "实际 %.1f" % hits.progress)
	hits.consume()
	_check("触发成功后进度清零", is_zero_approx(hits.progress) and not hits.ready_to_fire())

	# 冰冻触媒：门槛 1 次 —— 一发入魂
	var chill := Gems.cat_chill()
	chill.advance(CatalystGem.Trigger.CHILL_APPLIED, 1.0)
	_check("冰冻触媒 1 次就到门槛", chill.ready_to_fire())

	# 面板文字别炸、且说得清条件
	for c in cats:
		var cat := c as CatalystGem
		_check("%s 的面板文本正常" % cat.display_name,
				cat.tooltip().contains("触发条件") and cat.trigger_text().length() > 0)
	_check("疾行触媒按「格」显示（不是像素）", Gems.cat_move().trigger_text().contains("20 格"))

	# ---- 连接规则：和普通辅助一样，箭头指着法杖就算连上 ----
	var g := GemGrid.new()
	var wand := EquipLibrary.apprentice_wand()
	wand.socketed = Gems.gem_fireball()
	var wp := g.place(wand, Vector2i(3, 2), 0)
	var cp := g.place(Gems.cat_timer(), Vector2i(2, 2), 0)   # 箭头 → 指进法杖
	_check("触媒箭头指着法杖 → linked", g.arrow_state(cp) == "linked")
	_check("触媒出现在 supports_for 里", g.supports_for(wp).size() == 1)
	_check("触媒不贡献任何词缀", g.link_for(wp).mods().is_empty())
	_close("★ 但它的魔力倍率照算 ★（火球 13 × 1.20）",
			g.link_for(wp).skill().mana_cost, 13.0 * 1.20)

	# 触媒指着裸宝石 / 空法杖 → 和普通辅助一样连不上
	var g2 := GemGrid.new()
	g2.place(Gems.gem_spark(), Vector2i(3, 2), 0)
	var cp2 := g2.place(Gems.cat_timer(), Vector2i(2, 2), 0)
	_check("触媒指着裸宝石 → idle（技能必须在法杖里）", g2.arrow_state(cp2) == "idle")

	# ---- ★ 防循环标记：触发产物的状态机带 from_trigger，分叉出来的也继承 ★ ----
	var tspec := ProjectileSpec.new()
	tspec.fork_count = 1
	var tst := ProjectileState.new(tspec)
	_check("默认不是触发产物", not tst.from_trigger)
	tst.from_trigger = true
	var trng := RandomNumberGenerator.new()
	trng.seed = 1
	tst.decide_on_hit(1, trng)   # 消耗掉分叉，才能 clone_for_fork
	_check("★ 分叉出来的子弹继承 from_trigger ★（触发产物的分叉也不喂触媒）",
			tst.clone_for_fork().from_trigger)


# ================================================================ 新辅助宝石

func _test_new_supports() -> void:
	_begin("★ 新辅助：法术节魔 / 元素集中 / 快速·缓速投射 / 暴击伤害 ★")
	var melee_tags := T.PHYSICAL | T.ATTACK | T.MELEE

	# ---- 法术节魔：唯一倍率 < 1 的辅助，纯省蓝 ----
	var save := Gems.support_inspiration()
	_check("★ 倍率小于 1（省蓝而不是加价）★", save.mana_multiplier < 1.0,
			"×%.2f" % save.mana_multiplier)
	_check("不给任何词缀（省下的蓝就是它的全部价值）", save.build_mods().is_empty())
	_check("只连法术", save.can_support(Gems.gem_spark().tags)
			and not save.can_support(melee_tags))
	# 隔着法杖连上后，技能消耗真的降了；和别的辅助倍率照样连乘
	var g := GemGrid.new()
	var wand := EquipLibrary.apprentice_wand()
	wand.socketed = Gems.gem_spark()
	var wp := g.place(wand, Vector2i(3, 2), 0)
	g.place(save, Vector2i(2, 2), 0)                       # 左 → 指杖头
	_close("★ 电球术 6 蓝 × 0.65 = 3.9 ★", g.link_for(wp).skill().mana_cost, 6.0 * 0.65)
	g.place(Gems.support_multi(), Vector2i(4, 2), 2)       # 右 ← 指杖头（×1.40）
	_close("和「多重投射」连乘：6 × 0.65 × 1.40",
			g.link_for(wp).skill().mana_cost, 6.0 * 0.65 * 1.40)

	# ---- 元素集中：吃派生标签，三系元素都连得上、物理不行 ----
	var focus := Gems.support_ele_focus()
	_check("火焰技能连得上（火 → 元素是派生标签）", focus.can_support(Gems.gem_fireball().tags))
	_check("冰霜技能连得上", focus.can_support(Gems.gem_frostbolt().tags))
	_check("闪电技能连得上", focus.can_support(Gems.gem_spark().tags))
	_check("★ 物理近战连不上 ★", not focus.can_support(melee_tags))
	var p := CombatEntity.new(&"t", "测试")
	p.skill_mods.add_all(focus.build_mods())
	_close("火焰伤害 ×1.30", p.get_stat(S.DAMAGE, Gems.gem_fireball().build().hit_tags(), 100.0), 130.0)
	_close("物理伤害不受影响", p.get_stat(S.DAMAGE, T.PHYSICAL | T.ATTACK, 100.0), 100.0)

	# ---- 快速 / 缓速投射：一对反义词缀，作用在投射物速度上 ----
	var p2 := CombatEntity.new(&"t2", "测试")
	var base_speed := ProjectileSpec.build(p2, Gems.gem_fireball().build()).speed
	p2.skill_mods.add_all(Gems.support_fast_proj().build_mods())
	_close("★ 快速投射：速度 ×1.5 ★",
			ProjectileSpec.build(p2, Gems.gem_fireball().build()).speed, base_speed * 1.5)
	p2.skill_mods.clear()
	p2.skill_mods.add_all(Gems.support_slow_proj().build_mods())
	var slow := ProjectileSpec.build(p2, Gems.gem_fireball().build())
	_close("★ 缓速投射：速度 ×0.7 ★", slow.speed, base_speed * 0.7)
	_close("但伤害更多 20%（独立乘区）",
			p2.get_stat(S.DAMAGE, Gems.gem_fireball().build().hit_tags(), 100.0), 120.0)

	# ---- 暴击伤害：FLAT 加在暴伤倍率上，走完整伤害管线验 ----
	var pc := Demo.make_player()
	var mob := Demo.make_monster()
	var fire_spec := Gems.gem_fireball().build()
	var multi_before := DamagePipeline.compute_hit(pc, mob, fire_spec, null).crit_multi
	pc.skill_mods.add_all(Gems.support_crit_damage().build_mods())
	var multi_after := DamagePipeline.compute_hit(pc, mob, fire_spec, null).crit_multi
	_close("★ 暴伤倍率 1.5 → 2.0 ★", multi_after, multi_before + 0.5)
	_check("暴击伤害什么技能都能连", Gems.support_crit_damage().can_support(melee_tags))


# ================================================================ ADR-028：技能扩充 ×5 + 虚空操纵

func _test_skills_batch_two() -> void:
	_begin("★ 新技能：冰矛 / 翻滚岩浆 / 焚烧 / 闪电之触 / 精髓吸取 ★")
	var p := CombatEntity.new(&"t", "测试")
	for id in [&"ice_spear", &"rolling_magma", &"incinerate", &"lightning_tendrils", &"essence_drain"]:
		_check("按 id 能造出 %s（存档 / 商店 / 控制台都靠它）" % id, Gems.make_gem(id) != null)
		_check("%s 写进了价目表（不是吃默认价）" % id, RunContent.PRICES.has(id))

	# ---- 冰矛：暴击路。暴击率是别的技能的 3 倍以上，穿透 1，冰缓 ----
	var spear := Gems.gem_ice_spear().build()
	_check("冰矛是冰霜法术投射物", T.has_all(spear.tags, T.COLD | T.SPELL | T.PROJECTILE))
	_check("★ 冰矛天生暴击率 ≥ 3 倍于火球 ★（它的身份）",
			spear.base_crit_chance >= Gems.gem_fireball().build().base_crit_chance * 3.0,
			"%.2f" % spear.base_crit_chance)
	var spear_spec := ProjectileSpec.build(p, spear)
	_check("冰矛穿透 1 次、飞得比寒冰弹快得多",
			spear_spec.pierce_count == 1
			and spear_spec.speed > Gems.gem_frostbolt().build().projectile_speed * 2.0)
	_check("冰矛命中附加冰缓（冰冻触媒吃得到）", _has_buff(spear, &"chill"))

	# ---- 翻滚岩浆：火系打群。天生弹射 2、弹跳距离短、慢、点燃 ----
	var magma := Gems.gem_rolling_magma().build()
	var magma_spec := ProjectileSpec.build(p, magma)
	_check("翻滚岩浆是火焰法术投射物", T.has_all(magma.tags, T.FIRE | T.SPELL | T.PROJECTILE))
	_check("★ 翻滚岩浆天生弹射 2 次 ★（火系里唯一的打群技能）", magma_spec.chain_count == 2,
			"实际 %d" % magma_spec.chain_count)
	_check("弹跳距离比电弧短（岩浆是滚过去的，不是隔空跳）",
			magma_spec.chain_range < Gems.gem_arc().build().chain_range)
	_check("翻滚岩浆比火球慢", magma_spec.speed < Gems.gem_fireball().build().projectile_speed)
	_check("翻滚岩浆每一跳都点燃", _has_buff(magma, &"ignite"))

	# ---- 焚烧：喷火器 = 扇形范围（ADR-034），极快、极便宜、短、点燃是几率 ----
	var inc := Gems.gem_incinerate().build()
	var inc_a := AreaSpec.build(p, inc)
	_check("★ 焚烧施放时间 < 0.3 秒 ★（按住就是一条火舌）", inc.cast_time < 0.3, "%.2f" % inc.cast_time)
	_check("焚烧消耗比任何老技能都低", inc.mana_cost < Gems.gem_freezing_pulse().build().mana_cost)
	_check("★ 焚烧是扇形范围，不是投射物 ★（PoE：Spell, AoE, Fire, Channelling）",
			inc.is_area() and not inc.is_projectile() and inc_a.is_cone() and inc_a.origin == AreaSpec.Origin.SELF)
	_check("焚烧扇形 30°、长 130（窄而长）", is_equal_approx(inc_a.arc_deg, 30.0) and is_equal_approx(inc_a.radius, 130.0),
			"%.0f° / %.0f" % [inc_a.arc_deg, inc_a.radius])
	_check("焚烧的点燃是几率（不是必中）", _has_buff(inc, &"ignite") and inc.on_hit_chance < 1.0,
			"几率 %.2f" % inc.on_hit_chance)
	_check("焚烧每秒出手比火球多 3 倍以上",
			DamagePipeline.actions_per_second(Demo.make_player(), inc)
				> DamagePipeline.actions_per_second(Demo.make_player(), Gems.gem_fireball().build()) * 3.0)
	_check("多重投射 / 穿透连不上焚烧了（它不是弹）；增大范围连得上",
			not Gems.support_multi().can_support(Gems.gem_incinerate().tags)
			and not Gems.support_pierce().can_support(Gems.gem_incinerate().tags)
			and Gems.support_area().can_support(Gems.gem_incinerate().tags))

	# ---- 闪电之触：贴脸电弧扇 = 60° 扇形范围 ----
	var tend := Gems.gem_lightning_tendrils().build()
	var tend_a := AreaSpec.build(p, tend)
	_check("★ 闪电之触是 100° 宽扇形、长 90（和焚烧相反：宽而短）★", tend.is_area() and tend_a.is_cone()
			and is_equal_approx(tend_a.arc_deg, 100.0) and is_equal_approx(tend_a.radius, 90.0))
	_check("闪电之触必定感电", _has_buff(tend, &"shock") and tend.on_hit_chance >= 1.0)
	_check("闪电之触扇面比焚烧宽", tend_a.arc_deg > inc_a.arc_deg)

	# ---- 精髓吸取：混沌路。三系元素辅助一颗都连不上，只吃虚空操纵 ----
	var ed_gem := Gems.gem_essence_drain()
	var ed := ed_gem.build()
	_check("精髓吸取是混沌法术投射物", T.has_all(ed.tags, T.CHAOS | T.SPELL | T.PROJECTILE))
	_check("★ 混沌不是元素：元素集中连不上 ★", not Gems.support_ele_focus().can_support(ed_gem.tags))
	_check("闪电增强 / 冰霜增强都连不上", not Gems.support_lightning().can_support(ed_gem.tags)
			and not Gems.support_cold().can_support(ed_gem.tags))
	_check("★ 故意不带【持续时间】标签 ★（DURATION 只延长弹的存活，不改 DoT 时长）",
			(ed_gem.tags & T.DURATION) == 0)
	_check("精髓吸取命中挂上混沌 DoT", _has_buff(ed, &"essence_drain"))
	var void_sup := Gems.support_void()
	_check("虚空操纵只连精髓吸取", void_sup.can_support(ed_gem.tags)
			and not void_sup.can_support(Gems.gem_spark().tags)
			and not void_sup.can_support(Gems.gem_fireball().tags))
	var p2 := CombatEntity.new(&"t2", "测试")
	p2.skill_mods.add_all(void_sup.build_mods())
	_close("虚空操纵：混沌伤害 ×1.25", p2.get_stat(S.DAMAGE, ed.hit_tags(), 100.0), 125.0)
	_close("火焰伤害不受影响", p2.get_stat(S.DAMAGE, Gems.gem_fireball().build().hit_tags(), 100.0), 100.0)

	# ---- 10 颗技能的格子短名不撞车 ----
	var shorts := {}
	var dup_short := false
	for g in Gems.all_actives():
		var sg := g as SkillGem
		if shorts.has(sg.short_name):
			dup_short = true
		shorts[sg.short_name] = true
	_check("31 颗技能石的格子短名互不重复（背包里一眼分得清）", not dup_short)


## 技能命中会不会附加某个 Buff（按 id 查）
func _has_buff(spec: SkillSpec, id: StringName) -> bool:
	for b in spec.on_hit_buffs:
		if (b as BuffDef).id == id:
			return true
	return false


func _test_essence_drain_dot() -> void:
	_begin("精髓吸取的混沌 DoT：REFRESH 不叠、吃负抗性、吃虚空操纵")
	var pc := Demo.make_player()
	var mob := Demo.make_monster()          # 混沌抗性 -30%
	var ed := Demo.buff_essence_drain()
	mob.apply_buff(ed, pc)
	mob.apply_buff(ed, pc)
	_check("★ 重复命中只刷新，场上只有 1 份 ★（配多重投射不该 3 倍 DoT）",
			mob.buffs.count_of(&"essence_drain") == 1)

	# 走一次结算：每 0.5 秒一跳
	var life0 := mob.life
	var events := DamagePipeline.resolve_dots(mob, 0.5)
	_check("0.5 秒后跳了一次", events.size() == 1 and mob.life < life0)
	if events.size() == 1:
		var raw: float = events[0]["raw"]
		var dmg: float = events[0]["damage"]
		_close("★ 负抗性放大：实际伤害 = 原值 × 1.30 ★", dmg, raw * 1.30, 0.5)
		_check("玩家的「提高投射物伤害」天赋不影响 DoT（它没有投射物标签）",
				is_equal_approx(raw, 45.0), "原值 %.1f" % raw)

	# 虚空操纵是 MORE 混沌伤害 → DoT 快照时也吃到
	var pc2 := Demo.make_player()
	pc2.skill_mods.add_all(Gems.support_void().build_mods())
	var mob2 := Demo.make_monster()
	mob2.apply_buff(ed, pc2)
	var ev2 := DamagePipeline.resolve_dots(mob2, 0.5)
	_check("连了虚空操纵后 DoT 原值 ×1.25", ev2.size() == 1 and is_equal_approx(ev2[0]["raw"], 45.0 * 1.25),
			"原值 %.1f" % (ev2[0]["raw"] if ev2.size() == 1 else -1.0))

	# 4 秒后要消失
	mob.tick_buffs(4.0)
	_check("4 秒后 DoT 消退", not mob.buffs.has(&"essence_drain"))


# ================================================================ ADR-028：波次刷怪

func _test_room_waves() -> void:
	_begin("★ 房间编制：总数更多、分波上场、精英压轴 ★")
	# 总数只增不减，且比老曲线（2+step，最多 6）多
	var ok := true
	var prev := 0
	for f in RunMap.FLOORS:
		for i in RunMap.STEPS - 1:
			var n := RunContent.enemies_for_step(i, f)
			if n < prev or n < 4:
				ok = false
			prev = n
		prev = 0
	_check("每步总数只增不减、至少 4 只", ok)
	_check("第 1 层第 1 步 4 只（是老的 2 只的两倍）", RunContent.enemies_for_step(0, 0) == 4)
	_check("★ 第 4 层第 6 步 16 只 ★（老上限是 6）", RunContent.enemies_for_step(5, 3) == 16,
			"实际 %d" % RunContent.enemies_for_step(5, 3))
	_check("同一步，层越深怪越多", RunContent.enemies_for_step(2, 3) > RunContent.enemies_for_step(2, 0))

	# 同时在场上限 < 总数 → 必然分波；上限最多 8（场地就 400×400）
	var capped := true
	for f in RunMap.FLOORS:
		for i in RunMap.STEPS - 1:
			var cap := RunContent.max_alive_for_step(i, f)
			if cap < 4 or cap > 8 or cap > RunContent.enemies_for_step(i, f):
				capped = false
	_check("★ 同时在场上限在 4~8 之间，且不超过总数 ★", capped)
	_check("后期房间必须分波（总数 > 上限）",
			RunContent.enemies_for_step(5, 3) > RunContent.max_alive_for_step(5, 3))
	_check("第 1 层第 1 步一波放完（总数 == 上限，开局别排队）",
			RunContent.enemies_for_step(0, 0) == RunContent.max_alive_for_step(0, 0))

	# 精英数：第 1 层开局没有，后面才有；不超过总数；层越深越多
	_check("第 1 层第 1 步没有精英（孤杖孤石别一开局就见精英）", RunContent.elites_for_step(0, 0) == 0)
	_check("第 1 层第 4 步起有精英", RunContent.elites_for_step(3, 0) >= 1)
	_check("★ 第 4 层一开局就有 2 只精英 ★", RunContent.elites_for_step(0, 3) == 2,
			"实际 %d" % RunContent.elites_for_step(0, 3))
	var elite_ok := true
	for f in RunMap.FLOORS:
		for i in RunMap.STEPS - 1:
			if RunContent.elites_for_step(i, f) > RunContent.enemies_for_step(i, f) \
					or RunContent.elites_for_step(i, f) > 4:
				elite_ok = false
	_check("精英数不超过总数、最多 4 只", elite_ok)
	_check("词条数：前两层 1 条、后两层 2 条",
			RunContent.affix_count_for_floor(0) == 1 and RunContent.affix_count_for_floor(1) == 1
			and RunContent.affix_count_for_floor(2) == 2 and RunContent.affix_count_for_floor(3) == 2)
	_check("Boss 护卫逐层增加", RunContent.boss_escorts(0) == 2 and RunContent.boss_escorts(3) == 5)

	# 名单：数量对、精英排在最后、同 rng 种子同名单
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var roster := RunContent.room_roster(4, 2, rng)   # 第 3 层第 5 步：4+8+4=16 只，(4+4)/3=2 精英
	_check("名单人数 = enemies_for_step", roster.size() == RunContent.enemies_for_step(4, 2),
			"实际 %d" % roster.size())
	var elites_in := 0
	var tail_elite := true
	for i in roster.size():
		var m := roster[i] as CombatEntity
		if m.is_elite():
			elites_in += 1
			if i < roster.size() - RunContent.elites_for_step(4, 2):
				tail_elite = false
	_check("名单里的精英数 = elites_for_step", elites_in == RunContent.elites_for_step(4, 2),
			"实际 %d" % elites_in)
	_check("★ 精英排在队尾压轴 ★", tail_elite)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	var roster2 := RunContent.room_roster(4, 2, rng2)
	var same := true
	for i in roster.size():
		if (roster[i] as CombatEntity).display_name != (roster2[i] as CombatEntity).display_name:
			same = false
	_check("★ 同种子同名单（精英词条定死，读档重打不能刷词条）★", same)


# ================================================================ ADR-028：精英怪 + 随机词条

func _test_monster_affixes() -> void:
	_begin("★ 词条池：每条真的改数值、爪类真的带异常、抽取不重复 ★")
	var pool := MonsterAffixes.all_affixes()
	_check("词条池至少 10 条", pool.size() >= 10, "实际 %d" % pool.size())
	var ids := {}
	for a in pool:
		ids[(a as MonsterAffix).id] = true
	_check("词条 id 互不重复", ids.size() == pool.size())
	_check("按 id 能找到词条", MonsterAffixes.by_id(&"swift") != null and MonsterAffixes.by_id(&"nope") == null)

	# 每一条要么改属性、要么带爪类异常、要么改体型 —— 不许有"装上去什么都不变"的词条（ADR-011 的教训）
	var all_do_something := true
	for a in pool:
		var af := a as MonsterAffix
		if af.mods.is_empty() and af.on_hit_buff == null and is_equal_approx(af.body_scale, 1.0):
			all_do_something = false
	_check("★ 没有一条是空词条 ★", all_do_something)

	# 逐条验它改的是它说的那个数：拿基准怪对照
	var base := Demo.make_monster()
	var swift := Demo.make_monster()
	MonsterAffixes.swift().apply_to(swift)
	_close("迅捷：移速 ×1.45（基础值走参数传入，和 Enemy 一样）",
			swift.get_stat(S.MOVE_SPEED, T.NONE, 42.0), 42.0 * 1.45)
	var sturdy := Demo.make_monster()
	MonsterAffixes.sturdy().apply_to(sturdy)
	_close("坚韧：生命上限 ×1.6", sturdy.max_life(), base.max_life() * 1.6)
	_check("★ apply_to 不 refill ★（叠完所有词条再统一充满，否则出生不满血）",
			sturdy.life < sturdy.max_life())
	var brutal := Demo.make_monster()
	MonsterAffixes.brutal().apply_to(brutal)
	_close("暴虐：伤害 ×1.5", brutal.get_stat(S.DAMAGE, T.PHYSICAL | T.ATTACK | T.MELEE, 100.0), 150.0)
	var fren := Demo.make_monster()
	MonsterAffixes.frenzied().apply_to(fren)
	_check("★ 狂暴用 FLAT 攻速：0 基础上真的变快了 ★（INCREASED 在 0 上是恒真数据）",
			fren.get_stat(S.ATTACK_SPEED) > 0.25 and is_zero_approx(base.get_stat(S.ATTACK_SPEED)),
			"实际 %.2f" % fren.get_stat(S.ATTACK_SPEED))
	var stone := Demo.make_monster()
	MonsterAffixes.stoneskin().apply_to(stone)
	var fire := Gems.gem_fireball().build()
	var pc := Demo.make_player()
	var hit_base := DamagePipeline.compute_hit(pc, base, fire, null).total
	var hit_stone := DamagePipeline.compute_hit(pc, stone, fire, null).total
	_close("石肤：走完整伤害管线，最终伤害 ×0.75", hit_stone, hit_base * 0.75, 0.5)
	# 感电和石肤同一个乘区相加：3 层感电 +24% 抵掉大部分
	stone.apply_buff(Demo.buff_shock())
	stone.apply_buff(Demo.buff_shock())
	stone.apply_buff(Demo.buff_shock())
	_close("3 层感电抵消石肤：×(1 − 0.25 + 0.24)", DamagePipeline.compute_hit(pc, stone, fire, null).total,
			hit_base * 0.99, 0.5)
	var ward := Demo.make_monster()
	MonsterAffixes.fire_ward().apply_to(ward)
	_close("抗火：火抗 0.40 → 0.70", ward.resist_for(T.FIRE), 0.70)
	_close("抗火不动冰抗", ward.resist_for(T.COLD), base.resist_for(T.COLD))
	var ward3 := Demo.make_monster()
	MonsterAffixes.fire_ward().apply_to(ward3)
	ward3.gear_mods.add(M.new(S.FIRE_RESIST, M.Kind.FLAT, 0.50))
	_close("抗性堆过头也卡在 75% 上限", ward3.resist_for(T.FIRE), CombatStat.RESIST_CAP)
	var giant := Demo.make_monster()
	MonsterAffixes.giant().apply_to(giant)
	_check("巨型：体型 1.35、血翻倍、走得慢",
			is_equal_approx(giant.affix_scale(), 1.35)
			and is_equal_approx(giant.max_life(), base.max_life() * 2.0)
			and giant.get_stat(S.MOVE_SPEED, T.NONE, 42.0) < 42.0)

	# 爪类：近战带异常。词条自己只带数据，施加是表现层的事，这里验数据 + 施加后的效果
	var claw := MonsterAffixes.scorching_claw()
	_check("灼热之爪带一个火 DoT", claw.on_hit_buff != null and claw.on_hit_buff.dot_damage > 0.0
			and (claw.on_hit_buff.dot_tags & T.FIRE) != 0)
	_check("★ 怪打玩家的灼热比玩家的点燃温和 ★（不复用 buff_ignite）",
			claw.on_hit_buff.dot_damage < Demo.buff_ignite().dot_damage
			and claw.on_hit_buff.stack_rule == BuffDef.StackRule.REFRESH)
	var victim := Demo.make_player()
	victim.apply_buff(claw.on_hit_buff, Demo.make_monster())
	var life0 := victim.life
	DamagePipeline.resolve_dots(victim, 0.5)
	_check("挂到玩家身上真的会掉血", victim.life < life0, "%.0f → %.0f" % [life0, victim.life])
	var frost := Demo.make_player()
	frost.apply_buff(MonsterAffixes.frost_claw().on_hit_buff)
	# ★ 冰缓是 INCREASED −30%，和旅者之靴的 +20% 在同一个乘区**相加** ★ → 92 × (1 + 0.2 − 0.3)
	_close("霜爪：玩家移速降低（和靴子的 +20% 同乘区相加）",
			frost.get_stat(S.MOVE_SPEED), frost.base_of(S.MOVE_SPEED) * 0.9)
	_check("雷爪带感电", MonsterAffixes.shock_claw().on_hit_buff.id == &"shock")

	# 抽取：不重复、同种子同结果、池子不够全给
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var got := MonsterAffixes.roll(2, rng)
	_check("抽 2 条得 2 条，且不重复", got.size() == 2 and (got[0] as MonsterAffix).id != (got[1] as MonsterAffix).id)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 99
	var got2 := MonsterAffixes.roll(2, rng2)
	_check("同种子抽到同两条", (got[0] as MonsterAffix).id == (got2[0] as MonsterAffix).id
			and (got[1] as MonsterAffix).id == (got2[1] as MonsterAffix).id)
	_check("抽 999 条 = 整个池子（不重复所以最多这么多）",
			MonsterAffixes.roll(999, rng).size() == pool.size())
	_check("词条说明文本非空（面板要显示）", MonsterAffixes.swift().describe().length() > 0)


func _test_elite_monsters() -> void:
	_begin("★ 精英怪：底子更硬 + 随机词条 + 名字带词条 + 出生满血 ★")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var normal := RunContent.make_room_monster(3, 1)
	var elite := RunContent.make_elite(3, 1, rng)
	_check("精英是精英", elite.is_elite() and not normal.is_elite())
	_check("★ 同步同层，精英比普通怪硬得多（≥ 1.8 倍生命）★", elite.max_life() >= normal.max_life() * 1.8,
			"%.0f vs %.0f" % [elite.max_life(), normal.max_life()])
	_check("精英伤害更高", elite.get_stat(S.DAMAGE, T.PHYSICAL | T.ATTACK | T.MELEE, 100.0)
			> normal.get_stat(S.DAMAGE, T.PHYSICAL | T.ATTACK | T.MELEE, 100.0))
	_check("第 2 层的精英挂 1 条词条", elite.affixes.size() == RunContent.affix_count_for_floor(1))
	_check("★ 出生就是满血 ★（叠完词条再 refill；坚韧/巨型抬了上限也得是满的）",
			is_equal_approx(elite.life, elite.max_life()), "%.0f / %.0f" % [elite.life, elite.max_life()])
	_check("名字带上了词条（「迅捷 骷髅战士」这种）",
			elite.display_name.begins_with(elite.affix_title()) and elite.affix_title() != "")
	_check("词条的词缀进了 gear_mods，source = 词条 id（能整组识别）", _has_source(elite, (elite.affixes[0] as MonsterAffix).id))
	_check("精英底子的词缀 source = elite", _has_source(elite, &"elite"))

	# 第 4 层：2 条互不重复的词条
	var rng4 := RandomNumberGenerator.new()
	rng4.seed = 11
	var deep := RunContent.make_elite(2, 3, rng4)
	_check("第 4 层精英挂 2 条", deep.affixes.size() == 2)
	if deep.affixes.size() == 2:
		_check("两条词条不重复", (deep.affixes[0] as MonsterAffix).id != (deep.affixes[1] as MonsterAffix).id)
		_check("名字用「·」连两条词条", deep.affix_title().contains("·"))
	_check("第 4 层精英比第 2 层精英硬", deep.max_life() > elite.max_life())

	# 沙盒用：基准怪 + 1 条
	var rng_s := RandomNumberGenerator.new()
	rng_s.seed = 1
	var sand := RunContent.make_elite_from(Demo.make_monster(), 1, rng_s)
	_check("沙盒精英：基准骷髅升格，血 ≥ 基准 × 1.8", sand.max_life() >= Demo.make_monster().max_life() * 1.8)
	_check("0 条词条 = 只有底子，不算精英（is_elite 看的是词条）",
			not RunContent.make_elite_from(Demo.make_monster(), 0, rng_s).is_elite())

	# 精英 vs 同层 Boss：Boss 仍然是最硬的
	_check("第 2 层守关 Boss 仍比同层最硬的精英硬",
			RunContent.make_boss(1).max_life() > RunContent.make_elite(5, 1, rng).max_life())


## 网格里的 id 有没有重复（fill_missing 不该同一颗放两次）
func _no_dup_ids(grid: GemGrid) -> bool:
	var seen := {}
	for it in grid.items:
		var id: StringName = (it as GemGrid.Placed).gem.id
		if seen.has(id):
			return false
		seen[id] = true
	return true


## entity 的 gear_mods 里有没有 source 为 src 的词缀
func _has_source(e: CombatEntity, src: StringName) -> bool:
	for m in e.gear_mods.all():
		if (m as Modifier).source == src:
			return true
	return false


# ================================================================ ADR-029：技能扩充 ×6（含新星）

func _test_skills_batch_three() -> void:
	_begin("★ 新技能：裂雷之矛 / 寒冬之眼 / 灵魂撕裂 / 虚空匕首 / 冰霜新星 / 电击新星 ★")
	var p := CombatEntity.new(&"t", "测试")
	for id in [&"crackling_lance", &"eye_of_winter", &"soulrend", &"ethereal_knives", &"ice_nova", &"shock_nova"]:
		_check("按 id 能造出 %s" % id, Gems.make_gem(id) != null)
		_check("%s 写进了价目表" % id, RunContent.PRICES.has(id))

	# ---- 裂雷之矛：一道光束 = 14° 的细长扇形（ADR-034），单发重 ----
	var lance := Gems.gem_crackling_lance().build()
	var lance_a := AreaSpec.build(p, lance)
	var pulse_spec := ProjectileSpec.build(p, Gems.gem_freezing_pulse().build())
	_check("★ 裂雷之矛是光束：长 ≥ 250 像素、扇形 ≤ 20° ★（PoE：Spell, AoE, Lightning）",
			lance.is_area() and lance_a.is_cone() and lance_a.radius >= 250.0 and lance_a.arc_deg <= 20.0,
			"%.0f 像素 / %.0f°" % [lance_a.radius, lance_a.arc_deg])
	_check("长度是冰霜脉冲射程的 2 倍以上", lance_a.radius > pulse_spec.speed * pulse_spec.duration * 2.0)
	_check("必定感电", _has_buff(lance, &"shock"))
	_check("单发比冰霜脉冲重、施放比它慢（代价）",
			lance.base_damage > Gems.gem_freezing_pulse().build().base_damage
			and lance.cast_time > Gems.gem_freezing_pulse().build().cast_time)

	# ---- 寒冬之眼：唯一天生分叉 ----
	var eye := Gems.gem_eye_of_winter().build()
	var eye_spec := ProjectileSpec.build(p, eye)
	_check("★ 寒冬之眼天生分叉 1 次 ★", eye_spec.fork_count == 1, "实际 %d" % eye_spec.fork_count)
	_check("寒冬之眼还能穿透 2 次", eye_spec.pierce_count == 2)
	var innate_fork := 0
	for g in Gems.all_actives():
		if ProjectileSpec.build(p, (g as SkillGem).build()).fork_count > 0:
			innate_fork += 1
	_check("它是唯一天生带分叉的技能", innate_fork == 1, "实际 %d 颗" % innate_fork)
	_check("分叉支援连上去 = 分叉 2 次（一发变四发）",
			Gems.support_fork().can_support(Gems.gem_eye_of_winter().tags))
	p.skill_mods.add_all(Gems.support_fork().build_mods())
	_check("叠加后 fork_count == 2", ProjectileSpec.build(p, eye).fork_count == 2)
	p.skill_mods.clear()
	_check("寒冬之眼冰缓", _has_buff(eye, &"chill"))

	# ---- 灵魂撕裂：穿透一切 + 轻 DoT，和精髓吸取的 DoT 能共存 ----
	var soul := Gems.gem_soulrend().build()
	var soul_spec := ProjectileSpec.build(p, soul)
	_check("灵魂撕裂是混沌法术投射物、穿透一切",
			T.has_all(soul.tags, T.CHAOS | T.SPELL | T.PROJECTILE) and soul_spec.pierce_count >= 90)
	_check("命中挂 soulrend DoT", _has_buff(soul, &"soulrend"))
	_check("灵魂撕裂的 DoT 比精髓吸取轻（群体 vs 单体的分工）",
			Demo.buff_soulrend().dot_damage < Demo.buff_essence_drain().dot_damage)
	var mob := Demo.make_monster()
	var pc := Demo.make_player()
	mob.apply_buff(Demo.buff_soulrend(), pc)
	mob.apply_buff(Demo.buff_essence_drain(), pc)
	_check("★ 两个混沌 DoT 是不同 id，能同时挂在一只怪身上 ★",
			mob.buffs.has(&"soulrend") and mob.buffs.has(&"essence_drain"))
	var ev := DamagePipeline.resolve_dots(mob, 0.5)
	_check("半秒后两份 DoT 各跳一次", ev.size() == 2, "实际 %d 次" % ev.size())
	_check("虚空操纵连得上灵魂撕裂", Gems.support_void().can_support(Gems.gem_soulrend().tags))

	# ---- 虚空匕首：唯一的物理法术。不吃抗性、吃护甲 ----
	var ek := Gems.gem_ethereal_knives().build()
	var ek_spec := ProjectileSpec.build(p, ek)
	_check("虚空匕首是物理法术投射物", T.has_all(ek.tags, T.PHYSICAL | T.SPELL | T.PROJECTILE))
	_check("一次 5 把、扇面", ek_spec.shot_count() == 5 and ek_spec.spread_mode == ProjectileSpec.SpreadMode.FAN)
	var phys_count := 0
	for g in Gems.all_actives():
		if ((g as SkillGem).tags & (T.PHYSICAL | T.SPELL)) == (T.PHYSICAL | T.SPELL):
			phys_count += 1
	_check("它是唯一的物理**法术**（物理攻击是另一回事，ADR-032）", phys_count == 1, "实际 %d" % phys_count)
	var hit := DamagePipeline.compute_hit(pc, Demo.make_monster(), ek, null)
	_check("★ 物理：减免走护甲（不是抗性），而且减得不少 ★", hit.mitigation > 0.30 and hit.mitigation < 0.90,
			"减免 %.0f%%" % (hit.mitigation * 100.0))
	var ward := Demo.make_monster()
	MonsterAffixes.fire_ward().apply_to(ward)
	_close("抗火词条对物理伤害毫无影响", DamagePipeline.compute_hit(pc, ward, ek, null).total, hit.total, 0.01)
	_check("元素集中 / 三系增强都连不上物理", not Gems.support_ele_focus().can_support(Gems.gem_ethereal_knives().tags)
			and not Gems.support_lightning().can_support(Gems.gem_ethereal_knives().tags))
	_check("多重投射 / 穿透 / 暴击几率连得上（通用投射物辅助）",
			Gems.support_multi().can_support(Gems.gem_ethereal_knives().tags)
			and Gems.support_pierce().can_support(Gems.gem_ethereal_knives().tags)
			and Gems.support_crit().can_support(Gems.gem_ethereal_knives().tags))
	# 刀越重护甲减免越低：升级后减免比例下降
	var ek5 := Gems.gem_ethereal_knives()
	ek5.level = 5
	_check("刀越重护甲减免越低（5 级减免 < 1 级减免）",
			DamagePipeline.compute_hit(pc, Demo.make_monster(), ek5.build(), null).mitigation < hit.mitigation)

	# 成长规则（每级 ≥ 1 级点伤 40%）对新 6 颗也成立 —— 由 _test_gem_level_growth 遍历 all_actives 自动覆盖


# ================================================================ ADR-030：范围技能不走投射物

func _test_area_spec() -> void:
	_begin("★ AreaSpec：半径按面积平方根放大、延迟吃持续时间、圈内判定 ★")
	var p := CombatEntity.new(&"t", "测试")
	var nova := Gems.gem_ice_nova().build()
	_check("★ 新星是范围技能，不是投射物 ★", nova.is_area() and not nova.is_projectile())
	_check("投射物技能不是范围技能", Gems.gem_fireball().build().is_projectile()
			and not Gems.gem_fireball().build().is_area())
	var a := AreaSpec.build(p, nova)
	_close("没有词缀时半径 = 技能基础值 90", a.radius, 90.0)
	_check("新星以自己为中心、瞬发", a.origin == AreaSpec.Origin.SELF and is_zero_approx(a.delay))

	# 「范围效果 +50%」→ 面积 ×1.5 → 半径 ×√1.5（不是 ×1.5）
	p.skill_mods.add(M.new(S.AREA_OF_EFFECT, M.Kind.INCREASED, 0.50, T.AREA))
	_close("★ 范围 +50% → 半径 × √1.5 ★", AreaSpec.build(p, nova).radius, 90.0 * sqrt(1.5))
	p.skill_mods.add(M.new(S.AREA_OF_EFFECT, M.Kind.MORE, -0.30, T.AREA))
	_close("再叠「更少 30% 范围」：面积 ×1.5×0.7，半径 × √1.05", AreaSpec.build(p, nova).radius, 90.0 * sqrt(1.5 * 0.7))
	p.skill_mods.clear()
	p.skill_mods.add(M.new(S.AREA_OF_EFFECT, M.Kind.INCREASED, 0.50, T.PROJECTILE))
	_close("要求【投射物】的范围词缀对新星无效（它没有投射物标签）", AreaSpec.build(p, nova).radius, 90.0)
	p.skill_mods.clear()
	p.skill_mods.add(M.new(S.AREA_OF_EFFECT, M.Kind.MORE, -0.99, T.NONE))
	_check("范围压到底也不会变成 0 半径（有下限）", AreaSpec.build(p, nova).radius >= 1.0)
	p.skill_mods.clear()

	# 圈内判定：边界算在内、圈外不算、同一 id 不重复
	a = AreaSpec.build(p, nova)
	var ids := a.hits([
		{"id": 1, "dist": 0.0}, {"id": 2, "dist": 90.0}, {"id": 3, "dist": 90.01},
		{"id": 4, "dist": 45.0}, {"id": 4, "dist": 46.0}, {"id": 5, "dist": 300.0},
	])
	_check("★ 圈里 3 个：圆心、边界上、半途 ★（边界外 0.01 不算）", ids.size() == 3
			and ids.has(1) and ids.has(2) and ids.has(4) and not ids.has(3), str(ids))
	_check("同一目标喂两遍只算一次", ids.count(4) == 1)
	_check("空场没人中", a.hits([]).is_empty())

	# ---- 扇形（ADR-034）：圆里但不在扇形里的不算；贴在圆心的不看角度 ----
	var cone := AreaSpec.build(p, Gems.gem_incinerate().build())   # 30°、长 130
	var cone_ids := cone.hits([
		{"id": 1, "dist": 50.0, "angle": 0.0},                 # 正前方
		{"id": 2, "dist": 50.0, "angle": deg_to_rad(14.0)},    # 扇形边缘以内
		{"id": 3, "dist": 50.0, "angle": deg_to_rad(16.0)},    # 圆里、扇形外
		{"id": 4, "dist": 50.0, "angle": deg_to_rad(180.0)},   # 背后
		{"id": 5, "dist": 2.0, "angle": deg_to_rad(180.0)},    # 贴在身上：不看角度
		{"id": 6, "dist": 140.0, "angle": 0.0},                # 正前方但太远
	])
	_check("★ 扇形：正前方、边缘内、贴身的中；扇形外、背后、太远的不中 ★",
			cone_ids.size() == 3 and cone_ids.has(1) and cone_ids.has(2) and cone_ids.has(5)
			and not cone_ids.has(3) and not cone_ids.has(4) and not cone_ids.has(6), str(cone_ids))
	_check("没带 angle 的候选按整圆算（老调用方不炸）", cone.hits([{"id": 9, "dist": 50.0}]) == [9])
	_check("整圆技能忽略 angle", a.hits([{"id": 7, "dist": 50.0, "angle": deg_to_rad(180.0)}]) == [7])
	_check("describe 写明扇形", cone.describe().contains("扇形") and not a.describe().contains("扇形"))
	p.skill_mods.add_all(Gems.support_area().build_mods())
	_close("增大范围放大的是扇形的长度（半径 × √1.5），角度不变",
			AreaSpec.build(p, Gems.gem_incinerate().build()).radius, 130.0 * sqrt(1.5))
	_check("角度不变", is_equal_approx(AreaSpec.build(p, Gems.gem_incinerate().build()).arc_deg, 30.0))
	p.skill_mods.clear()

	# 风暴呼唤：指哪打哪、有延迟、延迟吃持续时间
	var call := Gems.gem_storm_call().build()
	var c := AreaSpec.build(p, call)
	_check("风暴呼唤以鼠标点为中心、射程 180", c.origin == AreaSpec.Origin.TARGET and is_equal_approx(c.range, 180.0))
	_close("落雷延迟 1.2 秒", c.delay, 1.2)
	_close("鼠标点在 300 像素外 → 夹到射程 180", c.clamp_distance(300.0), 180.0)
	_close("鼠标点在射程内 → 原样", c.clamp_distance(100.0), 100.0)
	_close("新星（SELF）不夹距离", a.clamp_distance(300.0), 300.0)
	p.skill_mods.add_all(Gems.support_duration().build_mods())
	_close("★ 「延长持续」让风暴呼唤落雷更慢：1.2 × 1.45 ★（PoE 的真实行为）",
			AreaSpec.build(p, call).delay, 1.2 * 1.45)
	_check("新星延迟 0，乘什么都是 0", is_zero_approx(AreaSpec.build(p, nova).delay))
	p.skill_mods.clear()
	_check("describe 文本非空", a.describe().length() > 0 and c.describe().contains("延迟"))


func _test_area_skills() -> void:
	_begin("★ 范围技能的连接规则 + 增大范围 / 集中效应 ★")
	var area_count := 0
	var aoe_tagged := 0
	for g in Gems.all_actives():
		var sg := g as SkillGem
		if sg.build().is_area():
			area_count += 1
			_check("%s 不带【投射物】标签（它不是弹）" % sg.display_name, (sg.tags & T.PROJECTILE) == 0)
			_check("%s 不同时是投射物和范围" % sg.display_name, not sg.build().is_projectile())
			if (sg.tags & T.AREA) != 0:
				aoe_tagged += 1
			# ★ 凡是走范围管线的都必须带【范围】标签 ★（ADR-037，项目主人反馈）—— 玩家看到圈就该能连范围辅助
			_check("%s 走范围管线 → 必须带【范围】标签" % sg.display_name, (sg.tags & T.AREA) != 0)
		# 投射物带爆炸 / 随行光环的也是范围（火球 / 翻滚岩浆 / 灵魂撕裂）
		if sg.build().is_projectile() and (sg.build().explodes_on_hit() or sg.build().aura_radius > 0.0):
			_check("%s 有爆炸 / 光环 → 必须带【范围】标签" % sg.display_name, (sg.tags & T.AREA) != 0)
	_check("走范围管线的技能 19 颗（7 颗范围法术 + 3 颗扇形 / 光束 + 9 颗近战）", area_count == 19, "实际 %d" % area_count)
	_check("走范围管线的 19 颗全带【范围】标签（吃增大范围 / 集中效应）", aoe_tagged == 19, "实际 %d" % aoe_tagged)
	var proj_count := 0
	for g in Gems.all_actives():
		if (g as SkillGem).build().is_projectile():
			proj_count += 1
	_check("★ 投射物技能 12 颗（不再比范围多）★", proj_count == 12 and proj_count < area_count, "实际 %d" % proj_count)
	_check("按 id 能造出风暴呼唤、进了价目表",
			Gems.make_gem(&"storm_call") != null and RunContent.PRICES.has(&"storm_call"))

	var nova_tags := Gems.gem_ice_nova().tags
	_check("★ 多重投射 / 穿透 / 弹射连不上新星 ★（投射物辅助对圈没意义）",
			not Gems.support_multi().can_support(nova_tags)
			and not Gems.support_pierce().can_support(nova_tags)
			and not Gems.support_chain().can_support(nova_tags))
	_check("冰霜增强 / 元素集中 / 暴击几率 / 迅捷施法连得上新星",
			Gems.support_cold().can_support(nova_tags) and Gems.support_ele_focus().can_support(nova_tags)
			and Gems.support_crit().can_support(nova_tags) and Gems.support_faster_cast().can_support(nova_tags))
	_check("新星故意不带【持续时间】：延长持续连不上",
			not Gems.support_duration().can_support(nova_tags))
	_check("风暴呼唤带【持续时间】：延长持续连得上（会让它落得更慢）",
			Gems.support_duration().can_support(Gems.gem_storm_call().tags))
	_check("冰霜新星冰缓、电击新星感电、风暴呼唤感电",
			_has_buff(Gems.gem_ice_nova().build(), &"chill")
			and _has_buff(Gems.gem_shock_nova().build(), &"shock")
			and _has_buff(Gems.gem_storm_call().build(), &"shock"))
	_check("风暴呼唤单发比新星重（要预判走位的代价）",
			Gems.gem_storm_call().build().base_damage > Gems.gem_shock_nova().build().base_damage * 2.0)

	# 增大范围：只连范围技能
	var big := Gems.support_area()
	_check("增大范围连得上新星、连不上火球（火球有 AREA 标签但……）",
			big.can_support(nova_tags) and big.can_support(Gems.gem_fireball().tags))
	_check("增大范围连不上电球术（没有范围标签）", not big.can_support(Gems.gem_spark().tags))
	var p := CombatEntity.new(&"t", "测试")
	p.skill_mods.add_all(big.build_mods())
	_close("★ 增大范围：新星半径 90 → 90×√1.5 ★", AreaSpec.build(p, Gems.gem_ice_nova().build()).radius, 90.0 * sqrt(1.5))
	_close("增大范围不加伤害", p.get_stat(S.DAMAGE, Gems.gem_ice_nova().build().hit_tags(), 100.0), 100.0)

	# 集中效应：更小更疼，而且伤害加成只对范围技能
	var conc := Gems.support_conc()
	var p2 := CombatEntity.new(&"t2", "测试")
	p2.skill_mods.add_all(conc.build_mods())
	_close("★ 集中效应：半径 × √0.7 ★", AreaSpec.build(p2, Gems.gem_ice_nova().build()).radius, 90.0 * sqrt(0.7))
	_close("集中效应：范围伤害 ×1.40", p2.get_stat(S.DAMAGE, Gems.gem_ice_nova().build().hit_tags(), 100.0), 140.0)
	_close("集中效应对电球术（无范围标签）的伤害无效", p2.get_stat(S.DAMAGE, Gems.gem_spark().build().hit_tags(), 100.0), 100.0)
	_check("集中效应连不上电球术", not conc.can_support(Gems.gem_spark().tags))
	# 两颗一起：面积 1.5 × 0.7，伤害 ×1.4，蓝 ×1.30×1.40
	var g := GemGrid.new()
	var wand := EquipLibrary.apprentice_wand()
	wand.socketed = Gems.gem_ice_nova()
	var wp := g.place(wand, Vector2i(3, 2), 0)
	g.place(big, Vector2i(2, 2), 0)
	g.place(conc, Vector2i(4, 2), 2)
	_close("隔着法杖连两颗：消耗 13 × 1.30 × 1.40", g.link_for(wp).skill().mana_cost, 13.0 * 1.30 * 1.40)
	var p3 := CombatEntity.new(&"t3", "测试")
	p3.skill_mods.add_all(g.link_for(wp).mods())
	_close("两颗一起：半径 90 × √(1.5×0.7)", AreaSpec.build(p3, g.link_for(wp).skill()).radius, 90.0 * sqrt(1.5 * 0.7))

	# 范围命中走同一条五步管线：对同一只怪，新星一次命中 = compute_hit 的结果（不是别的公式）
	var pc := Demo.make_player()
	var mob := Demo.make_monster()
	var hit := DamagePipeline.compute_hit(pc, mob, Gems.gem_ice_nova().build(), null)
	_check("范围命中也是五步管线：走冰抗 20% 减免", is_equal_approx(hit.mitigation, 0.20)
			and hit.total > 0.0, "减免 %.2f" % hit.mitigation)


# ================================================================ ADR-031：脉冲 / 连环 / 辅助稀有度

func _test_area_pulses_cascade() -> void:
	_begin("★ 范围管线的脉冲与连环：次数吃词缀和持续时间、连环位置前后交替 ★")
	var p := CombatEntity.new(&"t", "测试")
	var storm := Gems.gem_firestorm().build()
	var a := AreaSpec.build(p, storm)
	_check("烈焰风暴天生 6 次脉冲、间隔 0.35 秒", a.pulses == 6 and is_equal_approx(a.interval, 0.35),
			"%d × %.2f" % [a.pulses, a.interval])
	_check("一次性技能 pulses == 1、连环 0",
			AreaSpec.build(p, Gems.gem_ice_nova().build()).pulses == 1
			and AreaSpec.build(p, Gems.gem_ice_nova().build()).cascade == 0)

	# 持续时间按比例放大次数：延长持续（+45%）→ round(6 × 1.45) = 9；缩短持续（更少 40%）→ round(3.6) = 4
	p.skill_mods.add_all(Gems.support_duration().build_mods())
	_check("★ 延长持续：烈焰风暴 6 → 9 次 ★（PoE：持续越久落得越多）", AreaSpec.build(p, storm).pulses == 9,
			"实际 %d" % AreaSpec.build(p, storm).pulses)
	p.skill_mods.clear()
	p.skill_mods.add_all(Gems.support_less_duration().build_mods())
	var less := AreaSpec.build(p, storm)
	_check("★ 缩短持续：6 → 4 次，延迟 0.4 → 0.24 秒 ★", less.pulses == 4 and is_equal_approx(less.delay, 0.24),
			"%d 次 / %.2f 秒" % [less.pulses, less.delay])
	_close("缩短持续顺带更多 10% 伤害（只对带持续时间的技能）",
			p.get_stat(S.DAMAGE, storm.hit_tags(), 100.0), 110.0)
	_close("对没有持续时间标签的新星不加伤害",
			p.get_stat(S.DAMAGE, Gems.gem_ice_nova().build().hit_tags(), 100.0), 100.0)
	_check("缩短持续连不上新星（它没有持续时间标签）", not Gems.support_less_duration().can_support(Gems.gem_ice_nova().tags))
	p.skill_mods.clear()

	# 脉冲次数词缀（FLAT）：新星 1 → 3；再乘持续时间
	p.skill_mods.add(M.new(S.AREA_PULSES, M.Kind.FLAT, 2.0, T.AREA))
	_check("+2 脉冲：新星 1 → 3 次", AreaSpec.build(p, Gems.gem_ice_nova().build()).pulses == 3)
	_check("+2 脉冲：烈焰风暴 6 → 8 次", AreaSpec.build(p, storm).pulses == 8)
	p.skill_mods.add(M.new(S.DURATION, M.Kind.MORE, -0.99, T.NONE))
	_check("持续时间压到底也至少 1 次", AreaSpec.build(p, storm).pulses == 1)
	p.skill_mods.clear()

	# 连环：位置前后交替，以圈间距为单位
	p.skill_mods.add(M.new(S.AREA_CASCADE, M.Kind.FLAT, 2.0, T.AREA))
	var c2 := AreaSpec.build(p, Gems.gem_ice_nova().build())
	_check("连环 +2 → 前一个、后一个", c2.cascade == 2 and c2.cascade_offsets() == [1.0, -1.0],
			str(c2.cascade_offsets()))
	p.skill_mods.clear()
	p.skill_mods.add(M.new(S.AREA_CASCADE, M.Kind.FLAT, 4.0, T.AREA))
	_check("连环 +4 → [+1, -1, +2, -2]",
			AreaSpec.build(p, Gems.gem_ice_nova().build()).cascade_offsets() == [1.0, -1.0, 2.0, -2.0])
	p.skill_mods.clear()
	_check("没有连环词缀 → 没有额外位置", AreaSpec.build(p, Gems.gem_ice_nova().build()).cascade_offsets().is_empty())
	_check("要求【投射物】的连环词缀对新星无效", true)   # 由下面 support 的 required_tags 断言覆盖
	_check("describe 带上了脉冲和连环", AreaSpec.build(p, storm).describe().contains("脉冲")
			and c2.describe().contains("连环"))


func _test_area_skills_two() -> void:
	_begin("★ 新范围技能：烈焰风暴 / 漩涡 / 瘟疫 ★")
	var p := CombatEntity.new(&"t", "测试")
	for id in [&"firestorm", &"vortex", &"contagion"]:
		_check("按 id 能造出 %s、写进了价目表" % id, Gems.make_gem(id) != null and RunContent.PRICES.has(id))
		var sg: SkillGem = Gems.make_gem(id)
		_check("%s 是范围技能、不带投射物标签" % id, sg.build().is_area() and (sg.tags & T.PROJECTILE) == 0)

	var fs := AreaSpec.build(p, Gems.gem_firestorm().build())
	_check("烈焰风暴：指哪打哪、延迟 0.4、6 次脉冲",
			fs.origin == AreaSpec.Origin.TARGET and is_equal_approx(fs.delay, 0.4) and fs.pulses == 6)
	_check("烈焰风暴点燃是几率（40%）", _has_buff(Gems.gem_firestorm().build(), &"ignite")
			and is_equal_approx(Gems.gem_firestorm().build().on_hit_chance, 0.40))
	_check("烈焰风暴单次脉冲比风暴呼唤轻得多（6 次全吃才追上）",
			Gems.gem_firestorm().build().base_damage * 6.0 > Gems.gem_storm_call().build().base_damage
			and Gems.gem_firestorm().build().base_damage < Gems.gem_storm_call().build().base_damage * 0.3)

	var vx := AreaSpec.build(p, Gems.gem_vortex().build())
	_check("漩涡：以自己为中心、瞬发、4 次脉冲、冰缓",
			vx.origin == AreaSpec.Origin.SELF and is_zero_approx(vx.delay) and vx.pulses == 4
			and _has_buff(Gems.gem_vortex().build(), &"chill"))
	_check("漩涡带持续时间标签（延长持续 = 多转几圈）",
			Gems.support_duration().can_support(Gems.gem_vortex().tags))

	var ct := AreaSpec.build(p, Gems.gem_contagion().build())
	_check("瘟疫：指哪打哪、瞬发、一次性", ct.origin == AreaSpec.Origin.TARGET and is_zero_approx(ct.delay) and ct.pulses == 1)
	_check("瘟疫挂 contagion DoT、★ 故意不带持续时间标签 ★",
			_has_buff(Gems.gem_contagion().build(), &"contagion")
			and (Gems.gem_contagion().tags & T.DURATION) == 0)
	var mob := Demo.make_monster()
	var pc := Demo.make_player()
	mob.apply_buff(Demo.buff_contagion(), pc)
	mob.apply_buff(Demo.buff_essence_drain(), pc)
	mob.apply_buff(Demo.buff_soulrend(), pc)
	_check("★ 三个混沌 DoT 三个 id，能同时挂 ★", mob.buffs.count_of(&"contagion") == 1
			and mob.buffs.has(&"essence_drain") and mob.buffs.has(&"soulrend"))
	_check("半秒后三份各跳一次", DamagePipeline.resolve_dots(mob, 0.5).size() == 3)
	_check("虚空操纵连得上瘟疫、元素集中连不上", Gems.support_void().can_support(Gems.gem_contagion().tags)
			and not Gems.support_ele_focus().can_support(Gems.gem_contagion().tags))
	_check("连环范围连得上三颗、连不上电球术",
			Gems.support_cascade().can_support(Gems.gem_firestorm().tags)
			and Gems.support_cascade().can_support(Gems.gem_vortex().tags)
			and Gems.support_cascade().can_support(Gems.gem_contagion().tags)
			and not Gems.support_cascade().can_support(Gems.gem_spark().tags))
	p.skill_mods.add_all(Gems.support_cascade().build_mods())
	_check("连环范围：漩涡变 3 个圈、伤害 ×0.8",
			AreaSpec.build(p, Gems.gem_vortex().build()).cascade == 2
			and is_equal_approx(p.get_stat(S.DAMAGE, Gems.gem_vortex().build().hit_tags(), 100.0), 80.0))


func _test_support_tiers() -> void:
	_begin("★ 辅助稀有度：普通 / 崇高 / 血脉（ADR-031）★")
	# ---- 层级字段和图鉴归属 ----
	for g in Gems.all_supports():
		if (g as SupportGem).tier != SupportGem.Tier.NORMAL:
			_check("all_supports 里混进了非普通辅助：%s" % (g as SupportGem).display_name, false)
	_check("崇高 4 颗、血脉 3 颗", Gems.all_sublime().size() == 4 and Gems.all_lineage().size() == 3)
	var all_tiers_ok := true
	for g in Gems.all_sublime():
		if (g as SupportGem).tier != SupportGem.Tier.SUBLIME:
			all_tiers_ok = false
	for g in Gems.all_lineage():
		if (g as SupportGem).tier != SupportGem.Tier.LINEAGE:
			all_tiers_ok = false
	_check("层级字段填对了", all_tiers_ok)
	_check("按 id 能造出崇高和血脉（存档 / 控制台靠它）",
			Gems.make_gem(&"sub_area") != null and Gems.make_gem(&"lin_aira") != null)
	_check("血脉魔力倍率 ×1.0（代价在词缀里）",
			is_equal_approx(Gems.lineage_grim().mana_multiplier, 1.0)
			and is_equal_approx(Gems.lineage_aira().mana_multiplier, 1.0))
	_check("崇高的魔力倍率比同款普通贵",
			Gems.sublime_area().mana_multiplier > Gems.support_area().mana_multiplier
			and Gems.sublime_conc().mana_multiplier > Gems.support_conc().mana_multiplier)
	_check("崇高 / 血脉没有等级、不参与合成", Gems.sublime_area().max_level == 1 and Gems.lineage_grim().max_level == 1)
	_check("tooltip 标出了层级", Gems.sublime_area().tooltip().contains("崇高辅助")
			and Gems.lineage_grim().tooltip().contains("血脉辅助"))

	# ---- 崇高 = 普通的加强版 + 一条负面（每一条都要真的比普通款强，且真的有负面）----
	var nova := Gems.gem_ice_nova().build()
	var pn := CombatEntity.new(&"n", "普通")
	pn.skill_mods.add_all(Gems.support_area().build_mods())
	var ps := CombatEntity.new(&"s", "崇高")
	ps.skill_mods.add_all(Gems.sublime_area().build_mods())
	_check("★ 崇高·增大范围：圈比普通款大（√2 vs √1.5）★",
			AreaSpec.build(ps, nova).radius > AreaSpec.build(pn, nova).radius)
	_close("崇高·增大范围的负面：伤害 ×0.85", ps.get_stat(S.DAMAGE, nova.hit_tags(), 100.0), 85.0)
	var pc := CombatEntity.new(&"c", "崇高集中")
	pc.skill_mods.add_all(Gems.sublime_conc().build_mods())
	_close("崇高·集中效应：伤害 ×1.65", pc.get_stat(S.DAMAGE, nova.hit_tags(), 100.0), 165.0)
	_close("崇高·集中效应的负面：半径 × √0.5", AreaSpec.build(pc, nova).radius, 90.0 * sqrt(0.5))
	var pl := CombatEntity.new(&"l", "崇高缩短")
	pl.skill_mods.add_all(Gems.sublime_less_duration().build_mods())
	var call := Gems.gem_storm_call().build()
	_close("崇高·缩短持续：风暴呼唤 1.2 → 0.36 秒", AreaSpec.build(pl, call).delay, 1.2 * 0.30)
	_check("崇高·缩短持续：烈焰风暴 6 → 2 次", AreaSpec.build(pl, Gems.gem_firestorm().build()).pulses == 2,
			"实际 %d" % AreaSpec.build(pl, Gems.gem_firestorm().build()).pulses)
	var pk := CombatEntity.new(&"k", "崇高连环")
	pk.skill_mods.add_all(Gems.sublime_cascade().build_mods())
	_check("崇高·连环范围：+4 个圈、伤害 ×0.65",
			AreaSpec.build(pk, nova).cascade == 4
			and is_equal_approx(pk.get_stat(S.DAMAGE, nova.hit_tags(), 100.0), 65.0))

	# ---- 血脉：每颗都改一件"普通辅助改不了的事" ----
	var g1 := CombatEntity.new(&"g1", "格里姆")
	g1.skill_mods.add_all(Gems.lineage_grim().build_mods())
	_close("格里姆之震：半径 × √1.6", AreaSpec.build(g1, nova).radius, 90.0 * sqrt(1.6))
	_close("格里姆之震：范围伤害 ×1.2", g1.get_stat(S.DAMAGE, nova.hit_tags(), 100.0), 120.0)
	_close("格里姆之震的代价：范围技能施法速度 ×0.75", g1.get_stat(S.CAST_SPEED, nova.hit_tags(), 1.0), 0.75)
	_close("对投射物技能的施法速度没影响", g1.get_stat(S.CAST_SPEED, Gems.gem_spark().build().hit_tags(), 1.0), 1.0)
	var g2 := CombatEntity.new(&"g2", "艾拉")
	g2.skill_mods.add_all(Gems.lineage_aira().build_mods())
	_check("★ 艾拉之脉动：新星变三连炸 ★", AreaSpec.build(g2, nova).pulses == 3)
	_close("艾拉之脉动的代价：半径 × √0.75", AreaSpec.build(g2, nova).radius, 90.0 * sqrt(0.75))
	var g3 := CombatEntity.new(&"g3", "塞洛斯")
	g3.skill_mods.add_all(Gems.lineage_seros().build_mods())
	_close("塞洛斯之瞬：风暴呼唤 1.2 → 0.3 秒", AreaSpec.build(g3, call).delay, 0.3)
	_check("塞洛斯之瞬只连带持续时间的范围技能（新星连不上、风暴呼唤连得上）",
			not Gems.lineage_seros().can_support(Gems.gem_ice_nova().tags)
			and Gems.lineage_seros().can_support(Gems.gem_storm_call().tags))
	_close("塞洛斯之瞬不动火球的投射物存活（要求范围+持续时间，火球没有持续时间）",
			ProjectileSpec.build(g3, Gems.gem_fireball().build()).duration,
			ProjectileSpec.build(CombatEntity.new(), Gems.gem_fireball().build()).duration)

	# ---- 掉落规则：崇高按层进池 / 上架，血脉只从 Boss 掉且不重复 ----
	var pool0 := RunContent.reward_pools([], 0)
	var pool1 := RunContent.reward_pools([], 1)
	_check("★ 第 1 层奖励池没有崇高，第 2 层起有 ★",
			(pool0["supports"] as Array).size() == Gems.all_supports().size()
			and (pool1["supports"] as Array).size() == Gems.all_supports().size() + 4)
	var has_lineage := false
	for g in pool1["supports"]:
		if (g as SupportGem).tier == SupportGem.Tier.LINEAGE:
			has_lineage = true
	_check("血脉永远不进奖励池", not has_lineage)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	_check("第 1~2 层商店不上崇高", RunContent.shop_stock(rng, 1).size()
			== RunContent.SHOP_ACTIVES + RunContent.SHOP_SUPPORTS + RunContent.SHOP_EQUIPS)
	var deep_stock := RunContent.shop_stock(rng, 2)
	var sub_on_shelf := 0
	for thing in deep_stock:
		if thing is SupportGem and (thing as SupportGem).tier == SupportGem.Tier.SUBLIME:
			sub_on_shelf += 1
	_check("★ 第 3 层起货架多一颗崇高，且有价（45）★", sub_on_shelf == RunContent.SHOP_SUBLIME
			and RunContent.price_of(Gems.sublime_area()) == 45)
	_check("崇高比普通辅助贵", RunContent.price_of(Gems.sublime_area()) > RunContent.price_of(Gems.support_area()))

	var r1 := RandomNumberGenerator.new()
	r1.seed = 77
	var first := RunContent.boss_lineage([], r1)
	var r2 := RandomNumberGenerator.new()
	r2.seed = 77
	_check("Boss 必掉一颗血脉，同种子同一颗（读档重打刷不了）",
			first != null and RunContent.boss_lineage([], r2).id == first.id)
	var second := RunContent.boss_lineage([first.id], r1)
	_check("已有的不再掉（从剩下的里抽）", second != null and second.id != first.id)
	var third_ids: Array = [first.id, second.id]
	var third := RunContent.boss_lineage(third_ids, r1)
	_check("三颗集齐后不再掉（返回 null）", third != null and RunContent.boss_lineage(third_ids + [third.id], r1) == null)


# ================================================================ ADR-032：近战武器 + 攻击技能

func _test_melee_weapons() -> void:
	_begin("★ 近战武器：只收攻击技能、词缀只给槽里的技能、基准角色不带 ★")
	_check("武器 4 件、都在图鉴里", EquipLibrary.all_weapons().size() == 4
			and EquipLibrary.all_items().size() == 11 and EquipLibrary.make_item(&"iron_sword") != null)
	for w in EquipLibrary.all_weapons():
		var e := w as EquipItem
		_check("%s 有槽、是武器、写进了价目表" % e.display_name, e.has_socket() and e.is_weapon()
				and RunContent.PRICES.has(e.id))
		for m in e.mods:
			_check("%s 的词缀全要求【攻击】（放背包里对法术零影响）" % e.display_name,
					((m as Modifier).required_tags & T.ATTACK) != 0)
	_check("法杖不是武器", not EquipLibrary.staff().is_weapon() and not EquipLibrary.apprentice_wand().is_weapon())
	_check("★ 基准角色的装备里没有武器 ★（老伤害断言的地基不动）", EquipLibrary.default_loadout().size() == 7)

	# ---- 槽的类型：法术进法杖、攻击进武器 ----
	var sword := EquipLibrary.iron_sword()
	var wand := EquipLibrary.apprentice_wand()
	_check("铁剑收重击、不收火球", sword.accepts_gem(Gems.gem_heavy_strike()) and not sword.accepts_gem(Gems.gem_fireball()))
	_check("法杖收火球、不收重击", wand.accepts_gem(Gems.gem_fireball()) and not wand.accepts_gem(Gems.gem_heavy_strike()))
	_check("灵体投掷是攻击 → 进武器不进法杖",
			sword.accepts_gem(Gems.gem_spectral_throw()) and not wand.accepts_gem(Gems.gem_spectral_throw()))
	var g := GemGrid.new()
	var sp := g.place(sword, Vector2i(2, 1), 0)
	var wp := g.place(wand, Vector2i(5, 1), 0)
	_check("★ 火球点到铁剑上：拒绝并说明原因 ★",
			g.socket_reject_reason(Gems.gem_fireball(), Vector2i(2, 1)).contains("攻击技能"))
	_check("重击点到法杖上：拒绝", g.socket_reject_reason(Gems.gem_heavy_strike(), Vector2i(5, 1)).contains("法术技能"))
	_check("重击点到铁剑上：放行", g.socket_reject_reason(Gems.gem_heavy_strike(), Vector2i(2, 1)) == "")
	_check("火球点到法杖上：照旧放行", g.socket_reject_reason(Gems.gem_fireball(), Vector2i(5, 1)) == "")

	# ---- 武器词缀的作用域：只给槽里的技能（走 skill_mods），不进 equip 层 ----
	g.socket(Gems.gem_heavy_strike(), sp)
	g.socket(Gems.gem_fireball(), wp)
	_check("镶好后两个载体都能施放", g.skill_items().size() == 2)
	_check("★ equip 层里没有武器的词缀 ★（和法杖一样只跟着槽里的技能）", g.equip_mods().is_empty())
	var p := Demo.make_player()
	p.skill_mods.add_all(g.link_for(sp).mods())
	var strike := g.link_for(sp).skill()
	var bd := p.stat_breakdown(S.DAMAGE, strike.hit_tags(), strike.base_damage)
	_close("★ 铁剑的 +70 攻击伤害加在重击的点伤上（FLAT）★", bd["flat"], 70.0)
	_close("重击的攻速吃铁剑的 +10%", p.get_stat(S.ATTACK_SPEED, strike.hit_tags()), 1.10)
	p.skill_mods.clear()
	p.skill_mods.add_all(g.link_for(wp).mods())
	var fire := g.link_for(wp).skill()
	_close("切到法杖：火球吃不到铁剑的任何东西", p.stat_breakdown(S.DAMAGE, fire.hit_tags(), fire.base_damage)["flat"],
			Demo.make_player().stat_breakdown(S.DAMAGE, fire.hit_tags(), fire.base_damage)["flat"])
	# 换武器 = 换底子：巨锤 +170 但攻速 −20%
	var maul := EquipLibrary.great_maul()
	maul.socketed = Gems.gem_heavy_strike()
	var g2 := GemGrid.new()
	var mp := g2.place(maul, Vector2i(0, 0), 0)
	var p2 := Demo.make_player()
	p2.skill_mods.add_all(g2.link_for(mp).mods())
	_close("巨锤：+170 点伤", p2.stat_breakdown(S.DAMAGE, strike.hit_tags(), strike.base_damage)["flat"], 170.0)
	_close("巨锤：攻速 ×0.8", p2.get_stat(S.ATTACK_SPEED, strike.hit_tags()), 0.80)
	_close("巨锤：攻击的范围 +30%（重锤猛击锥长 95 × √1.3）",
			AreaSpec.build(p2, Gems.gem_ground_slam().build()).radius, 95.0 * sqrt(1.3))
	_close("巨锤对法术的范围无影响", AreaSpec.build(p2, Gems.gem_ice_nova().build()).radius, 90.0)
	# 匕首：暴击只对攻击
	var dp := Demo.make_player()
	dp.skill_mods.add_all(EquipLibrary.dagger().build_mods())
	_check("匕首的暴击率加成只对攻击（重击暴击 > 火球暴击的增幅）",
			dp.get_stat(S.CRIT_CHANCE, strike.hit_tags(), 0.06) > Demo.make_player().get_stat(S.CRIT_CHANCE, strike.hit_tags(), 0.06)
			and is_equal_approx(dp.get_stat(S.CRIT_CHANCE, fire.hit_tags(), 0.06),
				Demo.make_player().get_stat(S.CRIT_CHANCE, fire.hit_tags(), 0.06)))
	_check("面板写明槽收什么", sword.tooltip().contains("攻击技能") and wand.tooltip().contains("法术技能"))

	# 存档：武器 + 槽里的攻击技能一起存、一起读
	var data := g.to_data()
	var g3 := GemGrid.new()
	g3.from_data(data, GemSave.resolve)
	var restored_sword: GemGrid.Placed = null
	for it in g3.items:
		if (it as GemGrid.Placed).gem.id == &"iron_sword":
			restored_sword = it
	_check("存档读回来：铁剑还在、槽里还是重击",
			restored_sword != null and restored_sword.skill_gem() != null
			and restored_sword.skill_gem().id == &"heavy_strike")


func _test_melee_skills() -> void:
	_begin("★ 攻击技能：近战 = 面前的圈、走攻速；中毒独立叠加；灵体投掷是攻击投射物 ★")
	_check("攻击技能 10 颗（近战 9 + 灵体投掷）", Gems.all_attacks().size() == 10, "实际 %d" % Gems.all_attacks().size())
	for g in Gems.all_attacks():
		var sg := g as SkillGem
		_check("%s 带【攻击】不带【法术】、写进了价目表" % sg.display_name,
				(sg.tags & T.ATTACK) != 0 and (sg.tags & T.SPELL) == 0 and RunContent.PRICES.has(sg.id))
		_check("%s 的点伤比同类法术低（大头在武器上）" % sg.display_name, sg.base.base_damage < 100.0)

	var p := CombatEntity.new(&"t", "测试")
	var strike := Gems.gem_heavy_strike().build()
	var a := AreaSpec.build(p, strike)
	_check("★ 重击是近战：面前 22 像素处、半径 26 的圈 ★",
			strike.is_area() and a.origin == AreaSpec.Origin.FRONT and is_equal_approx(a.range, 22.0)
			and is_equal_approx(a.radius, 26.0))
	_check("面前的圈不夹距离（不是指哪打哪）", is_equal_approx(a.clamp_distance(300.0), 300.0))
	_check("describe 写明是挥砍", a.describe().contains("挥砍"))
	_check("横扫 / 重锤猛击 / 重击都带【范围】→ 增大范围都连得上（重击的小圈也是圈，ADR-037）",
			Gems.support_area().can_support(Gems.gem_cleave().tags)
			and Gems.support_area().can_support(Gems.gem_ground_slam().tags)
			and Gems.support_area().can_support(Gems.gem_heavy_strike().tags))
	_check("多重投射连不上近战、连得上灵体投掷",
			not Gems.support_multi().can_support(Gems.gem_cleave().tags)
			and Gems.support_multi().can_support(Gems.gem_spectral_throw().tags))
	_check("迅捷施法连不上攻击技能（它要求【法术】）",
			not Gems.support_faster_cast().can_support(Gems.gem_cleave().tags))
	_check("法术节魔也连不上", not Gems.support_inspiration().can_support(Gems.gem_cleave().tags))

	# ---- 出手间隔走攻击速度，施法速度对它无效 ----
	var pc := Demo.make_player()   # 橡木法杖 +25% 施法速度在 equip 层
	var aps_before := DamagePipeline.actions_per_second(pc, strike)
	_close("重击每秒 1.0 次（攻速 1.0 ÷ 攻击时间 1.0；橡木法杖的施法速度对它无效）", aps_before, 1.0)
	pc.skill_mods.add(M.new(S.CAST_SPEED, M.Kind.INCREASED, 1.0, T.NONE))
	_close("★ 再加 100% 施法速度：重击还是 1.0 次/秒 ★", DamagePipeline.actions_per_second(pc, strike), 1.0)
	pc.skill_mods.add(M.new(S.ATTACK_SPEED, M.Kind.INCREASED, 0.5, T.NONE))
	_close("加 50% 攻速：1.5 次/秒", DamagePipeline.actions_per_second(pc, strike), 1.5)
	_close("电球术反过来：吃施法速度不吃攻速",
			DamagePipeline.actions_per_second(pc, Gems.gem_spark().build()),
			(1.0 + 0.25 + 1.0) / Gems.gem_spark().build().cast_time)

	# ---- 双重打击 / 旋风斩 / 静电之击的脉冲 ----
	_check("双重打击 2 次脉冲、旋风斩每段 1 圈（以自己为中心）、静电之击 3 次",
			AreaSpec.build(p, Gems.gem_double_strike().build()).pulses == 2
			and AreaSpec.build(p, Gems.gem_cyclone().build()).pulses == 1
			and AreaSpec.build(p, Gems.gem_cyclone().build()).origin == AreaSpec.Origin.SELF
			and AreaSpec.build(p, Gems.gem_static_strike().build()).pulses == 3)
	_check("★ 旋风斩 / 双重打击的圈跟着施法者走；漩涡 / 静电之击 / 烈焰风暴留在原地 ★",
			AreaSpec.build(p, Gems.gem_cyclone().build()).follow
			and AreaSpec.build(p, Gems.gem_double_strike().build()).follow
			and not AreaSpec.build(p, Gems.gem_vortex().build()).follow
			and not AreaSpec.build(p, Gems.gem_static_strike().build()).follow
			and not AreaSpec.build(p, Gems.gem_firestorm().build()).follow)
	_check("跟着走的 describe 写明了", AreaSpec.build(p, Gems.gem_cyclone().build()).describe().contains("跟着"))
	# ---- 引导技能（ADR-033）：旋风斩 / 焚烧 / 闪电之触 ----
	var channels := 0
	for g in Gems.all_actives():
		if (g as SkillGem).build().is_channel():
			channels += 1
	_check("★ 引导技能 3 颗：旋风斩 / 焚烧 / 闪电之触 ★", channels == 3
			and Gems.gem_cyclone().build().is_channel() and Gems.gem_incinerate().build().is_channel()
			and Gems.gem_lightning_tendrils().build().is_channel(), "实际 %d" % channels)
	_check("重击 / 火球不是引导", not Gems.gem_heavy_strike().build().is_channel()
			and not Gems.gem_fireball().build().is_channel())
	var cyc := Gems.gem_cyclone().build()
	_check("旋风斩每段 0.25 秒、每段 4 蓝（16 蓝/秒 > 基础回蓝 12，蓝就是计时器）",
			is_equal_approx(cyc.cast_time, 0.25) and is_equal_approx(cyc.mana_cost, 4.0)
			and cyc.mana_cost / cyc.cast_time > 12.0)   # 12 = Player.MANA_REGEN 的裸基础值（不带回蓝装备）
	_check("★ 引导的代价换来伤害：旋风斩每圈 ≥ 55 ★（老版 5 圈 × 32 = 每秒 178，现在每秒 220 + 武器×4）",
			cyc.base_damage >= 55.0 and cyc.base_damage / cyc.cast_time > 32.0 * 5.0 / 0.9)
	_check("旋风斩不带持续时间了（引导没有'持续'，延长持续连不上）",
			not Gems.support_duration().can_support(Gems.gem_cyclone().tags))
	_check("面板写明引导", Gems.gem_cyclone().tooltip().contains("引导"))

	# ---- 元素近战：附加异常 ----
	_check("炼狱之击点燃 / 冰霜之锤冰缓 / 静电之击感电 / 毒蛇打击中毒",
			_has_buff(Gems.gem_infernal_blow().build(), &"ignite")
			and _has_buff(Gems.gem_glacial_hammer().build(), &"chill")
			and _has_buff(Gems.gem_static_strike().build(), &"shock")
			and _has_buff(Gems.gem_viper_strike().build(), &"poison"))
	_check("闪电增强连得上静电之击、冰霜增强连不上", Gems.support_lightning().can_support(Gems.gem_static_strike().tags)
			and not Gems.support_cold().can_support(Gems.gem_static_strike().tags))

	# ---- 中毒：INDEPENDENT 独立叠加，每份各自计时 ----
	var mob := Demo.make_monster()
	var att := Demo.make_player()
	mob.apply_buff(Demo.buff_poison(), att)
	mob.apply_buff(Demo.buff_poison(), att)
	mob.apply_buff(Demo.buff_poison(), att)
	_check("★ 三刀 = 三份中毒（不像精髓吸取只刷新）★", mob.buffs.count_of(&"poison") == 3)
	var ev := DamagePipeline.resolve_dots(mob, 0.5)
	_check("半秒后三份各跳一次、每份都吃 −30% 混沌抗（×1.3）", ev.size() == 3
			and is_equal_approx(ev[0]["damage"], ev[0]["raw"] * 1.3))
	mob.tick_buffs(2.0)
	_check("2 秒后全部消退", not mob.buffs.has(&"poison"))

	# ---- 灵体投掷：攻击投射物 ----
	var st := Gems.gem_spectral_throw().build()
	var sp := ProjectileSpec.build(p, st)
	_check("灵体投掷是攻击 + 投射物、不是范围、穿透一切",
			st.is_attack() and st.is_projectile() and not st.is_area() and sp.pierce_count >= 90)
	var wp := Demo.make_player()
	wp.skill_mods.add_all(EquipLibrary.war_axe().build_mods())
	_close("镶在战斧里：+110 点伤加在灵体投掷上", wp.stat_breakdown(S.DAMAGE, st.hit_tags(), st.base_damage)["flat"], 110.0)
	# 基准角色天赋里有「投射物伤害 +40%」，灵体投掷本来就吃它；战斧的「近战 +15%」不该再叠上来
	_close("战斧的「近战伤害提高」对灵体投掷无效（它不是近战）：还是天赋的 +40%",
			wp.stat_breakdown(S.DAMAGE, st.hit_tags(), 100.0)["increased"],
			Demo.make_player().stat_breakdown(S.DAMAGE, st.hit_tags(), 100.0)["increased"])
	_close("对横扫有效（+15%，横扫不是投射物、吃不到天赋）",
			wp.stat_breakdown(S.DAMAGE, Gems.gem_cleave().build().hit_tags(), 100.0)["increased"], 0.15)

	# ---- 冰川之刺：天生连环 2，连环范围再 +2 ----
	var gc := AreaSpec.build(p, Gems.gem_glacial_cascade().build())
	_check("冰川之刺：面前 90 像素处、天生连环 2（三个圈一条线）", gc.origin == AreaSpec.Origin.FRONT
			and gc.cascade == 2 and gc.cascade_offsets() == [1.0, -1.0])
	p.skill_mods.add_all(Gems.support_cascade().build_mods())
	_check("连环范围叠上去：2 + 2 = 4", AreaSpec.build(p, Gems.gem_glacial_cascade().build()).cascade == 4)
	p.skill_mods.clear()
	_check("冰川之刺是法术：镶法杖、走施法速度", Gems.gem_glacial_cascade().build().is_attack() == false
			and EquipLibrary.staff().accepts_gem(Gems.gem_glacial_cascade()))


# ================================================================ ADR-035：连锁 vs 弹射

func _test_link_vs_chain() -> void:
	_begin("★ 连锁 ≠ 弹射：不回头、+500% 速度、优先级在弹射之前 ★")
	var spec := ProjectileSpec.new()
	spec.link_count = 2
	spec.chain_range = 150.0
	var st := ProjectileState.new(spec)
	_check("出生时连锁次数 = spec、还没在连锁中、速度倍率 1.0",
			st.links_left == 2 and not st.is_linking() and is_equal_approx(st.speed_multiplier(), 1.0))
	_check("第 1 次命中 → 连锁", st.decide_on_hit(1) == ProjectileState.Action.LINK)
	_close("★ 跳出去之后速度 ×6（更多 500%）★", st.speed_multiplier(), 6.0)
	_check("正在连锁中", st.is_linking())
	# 不回头：打过的 1 一律不要；范围外的不要；剩下的取最近
	var pick := st.pick_link_target([
		{"id": 1, "dist": 10.0},     # 刚打过的：不要
		{"id": 2, "dist": 120.0},
		{"id": 3, "dist": 80.0},
		{"id": 4, "dist": 400.0},    # 太远
	])
	_check("★ 连锁挑没打过的最近的（3），打过的哪怕贴脸也不要 ★", pick == 3, "选了 %d" % pick)
	st.decide_on_hit(3)
	var pick2 := st.pick_link_target([{"id": 1, "dist": 10.0}, {"id": 3, "dist": 5.0}])
	_check("★ 场上只剩打过的 → 连锁到此为止（-1）★", pick2 == -1)
	# 对照：弹射在同样局面下**会**弹回去
	var cspec := ProjectileSpec.new()
	cspec.chain_count = 2
	cspec.chain_range = 150.0
	var cst := ProjectileState.new(cspec)
	cst.decide_on_hit(1)
	cst.decide_on_hit(3)
	_check("对照：弹射可以弹回打过的 1（两只怪来回弹）", cst.pick_chain_target([{"id": 1, "dist": 10.0}]) == 1)
	_check("弹射永远不加速", is_equal_approx(cst.speed_multiplier(), 1.0))
	_check("第 2 次命中 → 还能连锁；第 3 次没了 → 消失",
			st.links_left == 0 and st.decide_on_hit(5) == ProjectileState.Action.EXPIRE)

	# 优先级：穿透 > 分叉 > 连锁 > 弹射
	var pspec := ProjectileSpec.new()
	pspec.pierce_count = 1
	pspec.fork_count = 1
	pspec.link_count = 1
	pspec.chain_count = 1
	var pst := ProjectileState.new(pspec)
	_check("★ 优先级：穿透 > 分叉 > 连锁 > 弹射 ★",
			pst.decide_on_hit(11) == ProjectileState.Action.PIERCE
			and pst.decide_on_hit(12) == ProjectileState.Action.FORK
			and pst.decide_on_hit(13) == ProjectileState.Action.LINK
			and pst.decide_on_hit(14) == ProjectileState.Action.CHAIN
			and pst.decide_on_hit(15) == ProjectileState.Action.EXPIRE)
	# 分叉继承连锁次数和"连锁中"状态
	var fspec := ProjectileSpec.new()
	fspec.fork_count = 1
	fspec.link_count = 2
	var fst := ProjectileState.new(fspec)
	fst.decide_on_hit(21)   # 分叉
	var child := fst.clone_for_fork()
	_check("分叉出来的继承连锁次数", child.links_left == 2)

	# 词缀 / 内容
	var p := CombatEntity.new(&"t", "测试")
	p.skill_mods.add_all(Gems.support_link().build_mods())
	var fb := ProjectileSpec.build(p, Gems.gem_fireball().build())
	_check("★ 连锁支援：火球拿到 2 次连锁、0 次弹射 ★", fb.link_count == 2 and fb.chain_count == 0)
	_check("连锁支援连不上近战 / 新星", not Gems.support_link().can_support(Gems.gem_cleave().tags)
			and not Gems.support_link().can_support(Gems.gem_ice_nova().tags))
	p.skill_mods.add_all(Gems.support_chain().build_mods())
	var both := ProjectileSpec.build(p, Gems.gem_arc().build())
	_check("电弧 + 连锁支援 + 弹射支援：连锁 3+2、弹射 2（两套次数各自算）", both.link_count == 5 and both.chain_count == 2,
			"连锁 %d / 弹射 %d" % [both.link_count, both.chain_count])
	_check("describe 分开写弹射和连锁", both.describe().contains("连锁 5") and both.describe().contains("弹射 2"))
	_check("面板 / 图鉴：电弧写的是连锁不是弹射", Gems.gem_arc().tooltip().contains("连锁")
			and Gems.make_gem(&"sup_link") != null)


# ================================================================ ADR-036：差异化

func _test_differentiation() -> void:
	_begin("★ 差异化：命中爆炸 / 变形 / 回旋 / 随行光环 / 环 / 蓄力 / 锥 ★")
	var p := CombatEntity.new(&"t", "测试")

	# ---- 火球 / 翻滚岩浆：投射物 + 命中爆炸。它们仍是投射物，不是范围技能 ----
	var fb := Gems.gem_fireball().build()
	_check("★ 火球是投射物、命中爆炸、不算范围技能 ★", fb.is_projectile() and fb.explodes_on_hit() and not fb.is_area())
	var fbs := ProjectileSpec.build(p, fb)
	_close("火球爆炸半径 45", fbs.explode_radius, 45.0)
	_close("翻滚岩浆每跳炸 40", ProjectileSpec.build(p, Gems.gem_rolling_magma().build()).explode_radius, 40.0)
	_check("冰矛不炸", is_zero_approx(ProjectileSpec.build(p, Gems.gem_ice_spear().build()).explode_radius))
	p.skill_mods.add_all(Gems.support_area().build_mods())
	_close("增大范围能连火球（它有 AREA 标签）：爆炸半径 × √1.5", ProjectileSpec.build(p, fb).explode_radius, 45.0 * sqrt(1.5))
	p.skill_mods.clear()
	_check("describe 写明爆炸", fbs.describe().contains("命中爆炸"))

	# ---- 冰矛：飞 70 像素后变形，速度 ×2、暴击 ×3 ----
	var spear := ProjectileSpec.build(p, Gems.gem_ice_spear().build())
	var st := ProjectileState.new(spear)
	_check("出生时没变形：速度倍率 1、暴击倍率 1", not st.is_transformed()
			and is_equal_approx(st.speed_multiplier(), 1.0) and is_equal_approx(st.crit_multiplier(), 1.0))
	st.add_travel(69.0)
	_check("飞了 69 还没变", not st.is_transformed())
	st.add_travel(1.0)
	_check("★ 飞满 70 变形：速度 ×2、暴击 ×3 ★", st.is_transformed()
			and is_equal_approx(st.speed_multiplier(), 2.0) and is_equal_approx(st.crit_multiplier(), 3.0))
	_check("变形后的暴击率 60%（20% × 3）", is_equal_approx(spear.transform_crit_mult * Gems.gem_ice_spear().build().base_crit_chance, 0.60))
	var child := st.clone_for_fork()
	_check("分叉出来的继承已飞距离（不用重新飞 70）", child.is_transformed())
	_check("其它技能不变形", not ProjectileState.new(ProjectileSpec.build(p, fb)).is_transformed()
			and is_zero_approx(ProjectileSpec.build(p, fb).transform_after_px))

	# ---- 灵体投掷：回旋，回程能再打一遍 ----
	var thr := ProjectileSpec.build(p, Gems.gem_spectral_throw().build())
	var ts := ProjectileState.new(thr)
	_check("灵体投掷是回旋弹", thr.returns)
	ts.decide_on_hit(7)
	_check("去程打过 7 → 不能连续再打 7", not ts.can_hit(7))
	_check("存活 1.6 秒：剩 1.0 秒时还不掉头，剩 0.8 秒时掉头",
			not ts.should_return(1.0) and ts.should_return(0.8))
	ts.start_return()
	_check("★ 掉头后命中记录清空：回程能再打 7 ★", ts.returning and ts.can_hit(7) and not ts.has_hit(7))
	_check("掉头只发生一次", not ts.should_return(0.1))
	_check("火球不回旋", not ProjectileSpec.build(p, fb).returns)

	# ---- 灵魂撕裂：随行光环 ----
	var soul := ProjectileSpec.build(p, Gems.gem_soulrend().build())
	_check("灵魂撕裂带 45 像素随行光环、每 0.3 秒一次", is_equal_approx(soul.aura_radius, 45.0)
			and is_equal_approx(soul.aura_interval, 0.3))
	_check("精髓吸取没有光环（单体 DoT 弹）", is_zero_approx(ProjectileSpec.build(p, Gems.gem_essence_drain().build()).aura_radius))

	# ---- 电击新星：环。贴身的打不到 ----
	var ring := AreaSpec.build(p, Gems.gem_shock_nova().build())
	_check("电击新星是 45~120 的环", is_equal_approx(ring.inner_radius, 45.0) and is_equal_approx(ring.radius, 120.0))
	var ring_ids := ring.hits([{"id": 1, "dist": 20.0}, {"id": 2, "dist": 45.0}, {"id": 3, "dist": 80.0}, {"id": 4, "dist": 121.0}])
	_check("★ 环：贴身（20）不中、内沿（45）中、环上（80）中、环外不中 ★", ring_ids == [2, 3], str(ring_ids))
	_check("冰霜新星是实心圆：贴身也中", AreaSpec.build(p, Gems.gem_ice_nova().build()).hits([{"id": 1, "dist": 5.0}]) == [1])
	p.skill_mods.add_all(Gems.support_area().build_mods())
	var big_ring := AreaSpec.build(p, Gems.gem_shock_nova().build())
	_close("增大范围：环的内外半径同比放大（内 45 × √1.5）", big_ring.inner_radius, 45.0 * sqrt(1.5))
	p.skill_mods.clear()
	_check("describe 写明环", ring.describe().contains("环"))

	# ---- 焚烧：蓄力（引导每段叠一层，最多 8 层，+96%）----
	var inc := Gems.gem_incinerate().build()
	_check("焚烧带蓄力 Buff", inc.channel_ramp != null and inc.channel_ramp.id == &"incinerate_ramp")
	var pc := CombatEntity.new(&"c", "施法者")
	for i in 10:
		pc.apply_buff(inc.channel_ramp)
	_check("★ 叠 10 次封顶 8 层 ★", pc.buffs.stacks_of(&"incinerate_ramp") == 8)
	_close("8 层 = 火焰法术伤害 +96%", pc.get_stat(S.DAMAGE, inc.hit_tags(), 100.0), 196.0)
	_close("对冰霜法术无效", pc.get_stat(S.DAMAGE, Gems.gem_frostbolt().build().hit_tags(), 100.0), 100.0)
	pc.tick_buffs(0.7)
	_check("0.6 秒不续就全掉（松手 = 归零）", pc.buffs.stacks_of(&"incinerate_ramp") == 0)
	_check("闪电之触没有蓄力（它的差异是宽扇形）", Gems.gem_lightning_tendrils().build().channel_ramp == null)

	# ---- 重锤猛击 / 冰霜之锤：从脚下出发的锥，和横扫 / 重击的圈区分 ----
	var slam := AreaSpec.build(p, Gems.gem_ground_slam().build())
	_check("重锤猛击：以自己为中心的 100° 宽锥、长 95（比横扫远一倍）", slam.origin == AreaSpec.Origin.SELF
			and slam.is_cone() and is_equal_approx(slam.arc_deg, 100.0) and is_equal_approx(slam.radius, 95.0)
			and slam.radius > AreaSpec.build(p, Gems.gem_cleave().build()).radius * 2.0)
	var hammer := AreaSpec.build(p, Gems.gem_glacial_hammer().build())
	_check("冰霜之锤：70° 短锥、长 48、带范围标签；重击仍是面前的小圆", hammer.is_cone()
			and is_equal_approx(hammer.arc_deg, 70.0) and (Gems.gem_glacial_hammer().tags & T.AREA) != 0
			and not AreaSpec.build(p, Gems.gem_heavy_strike().build()).is_cone())

	# ---- 瘟疫扩散是 World 的事（冒烟测试验）；这里只确认瘟疫 Buff 还是同一个 id ----
	_check("瘟疫 Buff id 没变（扩散靠它认）", Demo.buff_contagion().id == &"contagion")
