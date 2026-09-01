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
	_begin("技能石：等级成长")
	var g := Gems.gem_spark()          # 电球术：1 级 55 点伤 / 10 魔力，每级 +6 / +0.8
	_check("默认 1 级", g.level == 1)
	_close("1 级点伤 55", g.damage_at(1), 55.0)
	_close("1 级消耗 10", g.mana_at(1), 10.0)
	_close("8 级点伤 55 + 6×7", g.damage_at(8), 55.0 + 6.0 * 7.0)
	_close("20 级点伤 55 + 6×19", g.damage_at(20), 55.0 + 6.0 * 19.0)
	_close("8 级消耗 10 + 0.8×7", g.mana_at(8), 10.0 + 0.8 * 7.0)

	# build() 出来的 SkillSpec 要用**当前等级**的数值
	g.level = 8
	var s := g.build()
	_close("build() 用当前等级的点伤", s.base_damage, 55.0 + 6.0 * 7.0)
	_check("标签原样传给 SkillSpec", s.tags == g.tags)

	# ★ 关键：build() 不能改到模板本身 ★
	# 改了的话等级一升，之前算好的 SkillSpec 会跟着变
	s.base_damage = 99999.0
	_close("改返回值不影响模板", g.build().base_damage, 55.0 + 6.0 * 7.0)
	_close("模板的 1 级伤害没被污染", g.base.base_damage, 55.0)

	_check("等级不会超过上限", g.clamp_level(999) == g.max_level)
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

	# 辅助宝石的词缀数值随等级成长
	var m := Gems.support_multi()
	var v1: float = (m.build_mods()[1] as Modifier).value
	m.level = 20
	var v20: float = (m.build_mods()[1] as Modifier).value
	_check("多重投射升级 → 伤害惩罚变小", v20 > v1, "1级 %.4f → 20级 %.4f" % [v1, v20])
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


## ★★ 背包网格最核心的规则：箭头指着谁就辅助谁 ★★
func _test_gem_grid_arrows() -> void:
	_begin("★ 背包网格：箭头指着谁就辅助谁 ★")
	var g := GemGrid.new()
	var spark := Gems.gem_spark()          # 闪电|法术|投射物|持续时间
	var sk := g.place(spark, Vector2i(3, 2), 0)   # 1 格，就在 (3,2)

	# ① 箭头朝右、指进技能石 → 连上
	var multi := Gems.support_multi()
	var m := g.place(multi, Vector2i(2, 2), 0)    # 在 (2,2)，箭头朝右 → (3,2)
	_check("箭头指向 (3,2)", m.arrow_target() == Vector2i(3, 2), str(m.arrow_target()))
	_check("★ 连上了 ★", g.arrow_state(m) == "linked", g.arrow_state(m))
	_check("技能石认得这颗辅助", g.supports_for(sk).size() == 1)

	# ② 同一颗宝石转个方向 → 箭头指到空地上，连接断掉（位置没变，只是朝向变了）
	g.remove(m)
	m = g.place(multi, Vector2i(2, 2), 1)         # 还在 (2,2)，但箭头朝下 → (2,3)
	_check("★ 只占 1 格，转方向不挪窝 ★", m.cells().size() == 1 and m.origin == Vector2i(2, 2))
	_check("转了方向后箭头指向下方", m.arrow_target() == Vector2i(2, 3), str(m.arrow_target()))
	_check("★ 指着空地 → 断开 ★", g.arrow_state(m) == "idle")
	_check("技能石这下一颗辅助都没有", g.supports_for(sk).is_empty())

	# ③ 转回去，再从右边、上面各连一颗 —— 1 格技能石四面最多 4 个箭头位（天然 4 连）
	g.remove(m)
	m = g.place(multi, Vector2i(2, 2), 0)                    # 左 →
	var d := g.place(Gems.support_duration(), Vector2i(4, 2), 2)  # 右 ←
	var l := g.place(Gems.support_lightning(), Vector2i(3, 1), 1) # 上 ↓
	_check("朝左的箭头指向 (3,2)", d.arrow_target() == Vector2i(3, 2), str(d.arrow_target()))
	_check("朝下的箭头指向 (3,2)", l.arrow_target() == Vector2i(3, 2), str(l.arrow_target()))
	_check("★ 三个方向各连一颗 ★", g.supports_for(sk).size() == 3,
			"实际 %d 颗" % g.supports_for(sk).size())

	# ④ 标签不匹配：箭头指到了，但连不上 —— 而且要能告诉玩家原因
	var g2 := GemGrid.new()
	var sk2 := g2.place(Gems.gem_fireball(), Vector2i(3, 2), 0)   # 没有【持续时间】标签
	var d2 := g2.place(Gems.support_duration(), Vector2i(2, 2), 0)
	_check("箭头确实指到了火球术", g2.at(d2.arrow_target()) == sk2)
	_check("★ 但标签不匹配 → blocked，不是 linked ★", g2.arrow_state(d2) == "blocked")
	_check("所以它不算辅助", g2.supports_for(sk2).is_empty())
	_check("但要能查出来是谁被挡了（UI 画红箭头用）", g2.blocked_for(sk2).size() == 1)

	# ⑤ 一颗辅助只有一个箭头 → 不可能同时辅助两颗技能石
	var g3 := GemGrid.new()
	var a := g3.place(Gems.gem_spark(), Vector2i(0, 0), 0)
	var b := g3.place(Gems.gem_spark(), Vector2i(3, 0), 0)
	g3.place(Gems.support_crit(), Vector2i(1, 3), 0)          # 谁都没指着
	_check("箭头没指着技能石时，两边都没有辅助",
			g3.supports_for(a).is_empty() and g3.supports_for(b).is_empty())

	# ⑥ 装备不参与连线：箭头指着装备 = 白指
	var g4 := GemGrid.new()
	g4.place(EquipLibrary.iron_helm(), Vector2i(3, 2), 0)
	var at_helm := g4.place(Gems.support_multi(), Vector2i(2, 2), 0)
	_check("★ 箭头指着装备 → 还是 idle（装备不用连）★", g4.arrow_state(at_helm) == "idle")

	# ⑦ link_for：把结果打包给战斗系统
	var link := g.link_for(sk)
	_check("link 里是那颗技能石", link.skill_gem == spark)
	_check("link 里有 3 颗辅助", link.supports.size() == 3)
	_close("消耗被三颗辅助的倍率连乘（10 × 1.40 × 1.20 × 1.25）",
			link.skill().mana_cost, 10.0 * 1.40 * 1.20 * 1.25)
	_check("link_for 一个空位 → 空 link", g.link_for(null).is_empty())


## ★ 背包存档：存下去再读回来，摆法和等级都不能变 ★
##
## 只测序列化（GemGrid.to_data / from_data），不碰文件 ——
## 读写文件是 game/gem_save.gd 的事，那一层由冒烟测试覆盖。
func _test_gem_grid_save() -> void:
	_begin("背包网格：存档与读档")
	var g := GemGrid.new()
	var spark := Gems.gem_spark()
	spark.level = 13
	g.place(spark, Vector2i(3, 1), 0)
	g.place(Gems.support_multi(), Vector2i(2, 1), 0)      # 箭头 → 连上
	g.place(Gems.support_duration(), Vector2i(4, 1), 2)   # 箭头 ← 连上
	g.place(Gems.support_crit(), Vector2i(0, 5), 1)       # 箭头朝下，没连
	g.place(EquipLibrary.staff(), Vector2i(7, 0), 0)      # 装备也要能存

	var data := g.to_data()
	_check("存了 5 件（宝石 + 装备）", data.size() == 5, "实际 %d 件" % data.size())
	_check("存的是纯数据（能直接 JSON 序列化）",
			typeof(JSON.parse_string(JSON.stringify(data))) == TYPE_ARRAY)

	# 读回一张全新的网格
	var g2 := GemGrid.new()
	var loaded := g2.from_data(data, GemSave.resolve)
	_check("5 件都还原了", loaded == 5, "实际 %d 件" % loaded)

	var sk2: GemGrid.Placed = g2.skill_items()[0]
	_check("★ 等级记住了 ★", (sk2.gem as SkillGem).level == 13,
			"实际 %d 级" % (sk2.gem as SkillGem).level)
	_check("★ 位置记住了 ★", sk2.origin == Vector2i(3, 1), str(sk2.origin))
	_check("★ 朝向记住了 → 箭头还是连着的 ★", g2.supports_for(sk2).size() == 2,
			"实际连着 %d 颗" % g2.supports_for(sk2).size())

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

	# ② 位置冲突（比如网格改小了、形状改大了）→ 不能把宝石弄丢
	var overlap := [
		{"id": "spark", "x": 3, "y": 1, "rot": 0, "level": 1},
		{"id": "fireball", "x": 3, "y": 1, "rot": 0, "level": 1},   # 压在同一个位置
	]
	var g4 := GemGrid.new()
	_check("位置冲突 → 换个空地放，不丢宝石",
			g4.from_data(overlap, GemSave.resolve) == 2, "实际 %d 件" % g4.items.size())
	_check("两颗技能石都在", g4.skill_items().size() == 2)

	# ③ 空存档 / 垃圾数据不能炸
	_check("空存档 → 0 件", GemGrid.new().from_data([], GemSave.resolve) == 0)
	_check("垃圾数据 → 跳过，不炸",
			GemGrid.new().from_data([123, "abc", null], GemSave.resolve) == 0)

	# ---- 新加的宝石要自动补进老存档 ----
	var partial := GemGrid.new()
	partial.from_data([{"id": "spark", "x": 0, "y": 0, "rot": 0, "level": 1}], GemSave.resolve)
	_check("老存档里只有 1 件", partial.items.size() == 1)
	var added := GemSave.fill_missing(partial)
	_check("★ 图鉴里新加的宝石/装备会自动补进来 ★",
			partial.items.size() == GemSave.everything().size(),
			"补了 %d 件，一共 %d 件" % [added, partial.items.size()])
	_check("补的时候不会重复放同一颗", not partial.has_gem(&"不存在"))


func _test_skill_mods_layer() -> void:
	_begin("技能石：辅助宝石只对它连着的技能生效")
	var p := Demo.make_player()

	# 网格里摆一颗电球术，左边挨着放一颗多重投射，箭头指着它
	var g := GemGrid.new()
	var sk := g.place(Gems.gem_spark(), Vector2i(3, 2), 0)
	g.place(Gems.support_multi(), Vector2i(2, 2), 0)
	var fire := g.place(Gems.gem_fireball(), Vector2i(6, 5), 0)   # 没有箭头指着它

	# Player.rebuild() 干的事：把当前这颗技能石的词缀整层换进 skill_mods
	p.skill_mods.clear()
	p.skill_mods.add_all(g.link_for(sk).mods())
	_check("电球术吃到多重投射 → 4+2 = 6 发",
			ProjectileSpec.build(p, g.link_for(sk).skill()).shot_count() == 6,
			"实际 %d" % ProjectileSpec.build(p, g.link_for(sk).skill()).shot_count())

	# 切到火球术（没有任何箭头指着它）→ 整层换掉
	p.skill_mods.clear()
	p.skill_mods.add_all(g.link_for(fire).mods())
	_check("★ 切到火球术后不再是多发 ★",
			ProjectileSpec.build(p, g.link_for(fire).skill()).shot_count() == 1)
	_check("skill_mods 已经清空", p.skill_mods.size() == 0)


## ★★ 这是用户要求的那张属性清单，逐条对一遍 ★★
## Tag / 等级 / 消耗 / 施放时间 / 投射物速度 / 点伤 / 单次发射数量 / 投射物持续时间
func _test_spark_gem() -> void:
	_begin("★ 电球术(Spark)：标准技能石的全部属性 ★")
	var g := Gems.gem_spark()
	g.level = 8
	var s := g.build()

	_check("Tag = 闪电|法术|投射物|持续时间",
			s.tags == (T.LIGHTNING | T.SPELL | T.PROJECTILE | T.DURATION))
	_check("Tag 文本读得懂", CombatTags.describe(s.tags).contains("持续时间"),
			CombatTags.describe(s.tags))
	_check("等级 8", g.level == 8)
	_close("消耗（8 级）", s.mana_cost, 10.0 + 0.8 * 7.0)
	_close("施放时间 0.65 秒", s.cast_time, 0.65)
	_close("投射物速度 150", s.projectile_speed, 150.0)
	_close("点伤（8 级，单发）", s.base_damage, 55.0 + 6.0 * 7.0)
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
	_begin("★ 电球术：辅助宝石怎么改变它 ★")
	var p := Demo.make_player()
	# 电球术摆在 (3,2)，四周留出位置给箭头
	var g := GemGrid.new()
	var sk := g.place(Gems.gem_spark(), Vector2i(3, 2), 0)

	var bare := ProjectileSpec.build(p, g.link_for(sk).skill())
	_check("没有箭头指着它时 4 发", bare.shot_count() == 4)
	_close("存活 2.4 秒", bare.duration, 2.4)

	# ① 左边放「延长持续」，箭头朝右指进来 → 每发活得更久
	g.place(Gems.support_duration(), Vector2i(2, 2), 0)
	p.skill_mods.clear()
	p.skill_mods.add_all(g.link_for(sk).mods())
	_close("持续时间 2.4 × 1.45",
			ProjectileSpec.build(p, g.link_for(sk).skill()).duration, 2.4 * 1.45)

	# ② 再从下面放「多重投射」，箭头朝上指进来 → 发数变多，但扇面不变
	g.place(Gems.support_multi(), Vector2i(3, 3), 3)   # rot3 = 朝上，指进 (3,2)
	p.skill_mods.clear()
	p.skill_mods.add_all(g.link_for(sk).mods())
	var more := ProjectileSpec.build(p, g.link_for(sk).skill())
	_check("4 + 2 = 6 发", more.shot_count() == 6, "实际 %d" % more.shot_count())
	_close("扇面还是 90°（不会扇得更宽）", more.spread_arc_deg, 90.0)

	# ③ 魔力消耗倍率是连乘的：1.20 × 1.40
	_close("消耗 10 × 1.20 × 1.40", g.link_for(sk).skill().mana_cost, 10.0 * 1.20 * 1.40)

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
	g.level = 8
	var txt := g.tooltip([Gems.support_duration()])

	_check("有等级", txt.contains("等级 8/20"))
	_check("有标签", txt.contains("持续时间") and txt.contains("投射物"))
	_check("有消耗", txt.contains("消耗"))
	_check("有施放时间", txt.contains("施放时间"))
	_check("有点伤", txt.contains("点伤"))
	_check("有单次发射数量", txt.contains("单次发射"))
	_check("有投射物速度和持续时间", txt.contains("投射物速度") and txt.contains("投射物持续时间"))
	_check("有飞行漂移", txt.contains("飞行漂移"))
	_check("有自带的撞墙反弹", txt.contains("撞墙反弹"))
	_check("有命中附加效果", txt.contains("感电"))
	_check("有下一级预览", txt.contains("升到 9 级"))

	# 满级时不该再出现"升到 21 级"
	g.level = g.max_level
	_check("满级不显示下一级", not g.tooltip().contains("升到"))

	# 近战技能（非投射物）也不能炸
	var melee := SkillGem.new(&"hs", "重击", T.PHYSICAL | T.ATTACK | T.MELEE)
	melee.base.base_damage = 300.0
	_check("非投射物技能石也能出面板", melee.tooltip().length() > 0)

	# 辅助宝石的面板
	var sup := Gems.support_duration()
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
