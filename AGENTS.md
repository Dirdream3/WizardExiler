# AGENTS.md —— AI 协作规约

> **任何 AI（Claude Code / Cursor / Copilot / Codex …）动手改这个仓库之前，先读完这一页。**
> 人类协作流程看 [CONTRIBUTING.md](CONTRIBUTING.md)；设计原理看 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

---

## 0. 30 秒搞清楚这是什么

Godot 4 + GDScript 写的 2D 俯视角像素 ARPG，核心是一套 **PoE（流放之路）式的词缀 / 技能石 / 伤害系统**。

- 画面：左边 300px 常驻背包面板，右边 400×400 正方形战斗画面
- 背包是**「背包乱斗」式网格**：宝石占 1 格、装备占多格。
  ★ **法杖是技能的载体**（ADR-020）★：技能宝石必须镶进法杖的槽位才能施放；
  辅助宝石的**箭头指着法杖**（任意一格），就辅助槽里的技能
- 局模式共 **4 层**，每层一张 7 步的图、难度逐层递增（ADR-021）
- 项目主人的代码能力是初学者水平 → **注释要写"为什么"，不要只写"是什么"；中文注释**

---

## 1. ★ 不可违反的约束 ★

违反这四条 = 改错了，不管测试过没过。

### 1.1 `combat/` 里不许出现任何 Godot 场景依赖

不许有 `Node`、`Sprite`、`Camera`、场景坐标、`FileAccess`、`get_tree()`。
只能用纯数据类型（`int` / `float` / `Array` / `Dictionary` / `Vector2i` 当格子下标）。

**为什么**：这样战斗数值能脱离引擎跑单元测试、能做离线 DPS 计算器、将来联机能搬到服务器验算。
`test/run_tests.gd` 的 271 个断言全靠这一条才存在。

> `Vector2i` 在 `GemShape` / `GemGrid` 里是「第几列第几行」的**逻辑下标**，不是屏幕像素 —— 这是允许的。

### 1.2 四段式伤害公式只能有一处实现

```
最终值 = (基础值 + Σ增加点数) × (1 + Σ提高%) × Π(1 + 更多%)
         └─ FLAT ─┘            └─ INCREASED ─┘  └─── MORE ───┘
```

唯一实现在 `combat/stat_set.gd → breakdown_layered()`。
**任何地方想算伤害，都要走它**，不许另写一份。有第二处实现，数值一定会对不上。

`INCREASED`（相加，共用一个乘区）和 `MORE`（各自连乘）**绝对不能混成一个 float** ——
这是 PoE-like 项目最常见的返工点。

### 1.3 表现层「持有」数据模型，不是继承

```gdscript
# 对
class_name Player extends CharacterBody2D
var stats: CombatEntity

# 错
class_name Player extends CombatEntity
```

### 1.4 改了 `combat/` 或 `game/`，两套测试都必须跑，而且必须全绿

见第 3 节。**不许以"我只改了注释/UI"为由跳过。**

---

## 2. ★ 名词对照表 ★（踩过坑，务必先看）

| 项目里的叫法 | 英文 / 真身 | 别搞错的地方 |
|---|---|---|
| **电球术** | **Spark** | ★ PoE 中文版把 Spark 译作「电球术」★ 一次射 4 发乱窜的小球、撞墙会弹。**不是** Ball Lightning |
| 火球术 | Fireball | 单发直线 + 点燃 + ★ 命中爆炸（半径 45，打周围其他敌人；ADR-036）★ 仍是投射物 |
| 命中爆炸 / 变形 / 回旋 / 随行光环 / 环 / 蓄力 | ADR-036 | 投射物带 `area_radius` = 命中爆炸（不是范围技能）；冰矛飞 70 后速度 ×2 暴击 ×3；灵体投掷飞一半掉头且回程能再打；灵魂撕裂周围 45 每 0.3 秒结算；电击新星 45~120 的环；焚烧每段叠 1 层（+12% 火法伤，8 层） |
| 电弧 | Arc | PoE 里是瞬发连锁闪电；本项目用「高速投射物 + 天生**连锁** 3 次」还原（不回头、跳跃瞬移）。**不是**投射物雨、不是弹射 |
| 寒冰弹 | Frostbolt | 慢速穿透弹 + 冰缓。飞得慢是特性（同屏弹数多），别"顺手"调快 |
| 冰霜脉冲 | Freezing Pulse | 短射程（速度×存活≈150px）、穿透一切的冰锥。**故意不带**【持续时间】标签，射程就是它的代价。和被删掉的「脉冲机制」（ADR-011）无关，这是 PoE 的正经技能 |
| 冰缓 | Chill | 挂在**移动速度**上（-30%），不挂攻速 —— 普通怪没设过基础攻速，挂攻速是恒真数据 |
| 提高 / INCREASED | increased | 所有同类**相加**，共用一个乘区 |
| 更多 / MORE | more | 每一条**独立连乘** |
| 弹射 / CHAIN | chain | 命中敌人后转向下一个敌人，**可以**弹回打过的（两只怪来回弹）。翻滚岩浆、弹射支援 |
| ★ 连锁 / LINK ★ | link（ADR-035） | 命中后跳向**没打过**的敌人、永不回头，跳出去之后 +500% 速度（几乎瞬移）。电弧天生 3 次、连锁支援 +2。优先级：穿透 > 分叉 > 连锁 > 弹射 |
| 撞墙反弹 / BOUNCE | — | 撞地形弹开，**不消耗**任何命中次数，和弹射是两回事 |
| 辅助宝石 | support gem | 一组带代价的词缀，靠**箭头**连到**法杖**上（不是直接连技能石）。★ 没有等级 ★（max_level = 1，不参与合成/升级；技能宝石是 1~5 级） |
| **法杖** | wand | ★ 技能的载体 ★ 每根带 1 个镶嵌槽，技能宝石镶进去才能施放；箭头指着法杖的任意一格都算连上。★ 法杖自己的词缀也只对槽里的技能生效（走 skill_mods，不进 equip_mods）★ 裸放的技能宝石只是库存 |
| **触媒** | catalyst | ★ 特殊辅助宝石（紫色）★ 不给词缀，条件达成时**自动触发**箭头连着的法杖里的技能：无施法动作、正常扣蓝、蓝不够不触发。★ 结算口径：满足施加条件就计一次（同目标刷新/叠满层都算）；触发产物的击中/异常**不喂任何触媒**（防循环，`ProjectileState.from_trigger`）★ 「冰冻触媒」实际数的是**冰缓**（本项目没有冰冻状态） |
| 冰矛 | Ice Spear | 暴击路：20% 暴击 + 穿透 1 + 冰缓，★ 飞 70 像素后变形：速度 ×2、暴击 ×3（60%）★（ADR-036，照 PoE） |
| 翻滚岩浆 | Rolling Magma | 火系打群：慢弹 + 天生弹射 2 次（还原"沿地弹跳"）+ 点燃。弹跳距离故意比电弧短 |
| 焚烧 | Incinerate | ★ 引导的扇形范围 ★（ADR-034）：以自己为中心 40°、长 110px，每 0.22 秒一段 3 蓝、35% 点燃。PoE 3.3 后不是投射物 |
| 闪电之触 | Lightning Tendrils | ★ 引导的扇形范围 ★：60°、长 120px、每 0.4 秒一段、必定感电。PoE 里是 AoE 不是投射物 |
| 精髓吸取 | Essence Drain | ★ 混沌 DoT 弹 ★ 命中不疼、之后 4 秒掉血；REFRESH 不叠层。**故意不带**【持续时间】标签（DURATION 只延长弹的存活） |
| 虚空操纵 | Void Manipulation | 更多混沌伤害。只有混沌技能（精髓吸取 / 灵魂撕裂）连得上；混沌**不是**元素，元素集中连不上它 |
| 裂雷之矛 | Crackling Lance | ★ 光束 = 14° 的细扇形、长 320px ★（ADR-034），线上全中、必定感电。PoE 里是 AoE 不是投射物。★ 译名按记忆取的，没查证 ★ |
| 扇形 / 光束 | cone / beam | `SkillSpec.area_arc_deg`（`with_arc`）→ `AreaSpec.arc_deg`；候选带 `angle`（和朝向的夹角）才做扇形判定，贴身（dist ≤ 4）不看角度 |
| 寒冬之眼 | Eye of Winter | 唯一天生分叉（fork 1）+ 穿透 2 的冰弹。配分叉支援 = 一发变四发 |
| 灵魂撕裂 | Soulrend | 穿透一切的慢弹，沿途每人一份轻混沌 DoT（`soulrend`，和 `essence_drain` 不同 id、可共存） |
| 虚空匕首 | Ethereal Knives | ★ 唯一的物理法术 ★ 5 把飞刀扇面。不吃抗性、吃护甲；感电/石肤在护甲之后结算 |
| 冰霜新星 / 电击新星 | Ice Nova / Shock Nova | ★ 真正的范围技能（ADR-030）★ 以自己为中心的圈，圈里全部同时命中。**不带**【投射物】标签 → 多重投射/穿透连不上；不带【持续时间】。电击新星译名没查证 |
| 风暴呼唤 | Storm Call | 指哪打哪的延迟落雷（半径 70、射程 180、1.2 秒）。带【持续时间】：「延长持续」让它落得更慢（PoE 真实行为） |
| 范围 / AreaSpec | area of effect | ★ 和投射物平行的第二条管线 ★ 「范围效果」放大面积、半径按平方根走。结算在 `World._resolve_area()`，和投射物同一条五步管线 |
| 增大范围 / 集中效应 | Increased AoE / Concentrated Effect | 要求【范围】。集中效应 = 范围 MORE −30% + 范围伤害 MORE +40% |
| 烈焰风暴 / 漩涡 / 瘟疫 | Firestorm / Vortex / Contagion | 范围技能。烈焰风暴 6 次脉冲、漩涡 4 次脉冲（★ 脉冲次数吃「持续时间」倍率 ★）；瘟疫是第三个混沌 DoT id，不带持续时间 |
| 脉冲 / 连环 | pulses / cascade | `AreaSpec.pulses`：一个圈炸几次；`cascade_offsets()`：沿施法方向前后交替的额外圈。都是 CombatStat（`AREA_PULSES` / `AREA_CASCADE`）FLAT 词缀 |
| 崇高辅助 | sublime support（参考火炬之光的崇高/华贵） | `SupportGem.tier == SUBLIME`：普通款翻倍 + 一条负面。第 2 层起进奖励池、第 3 层起上货架。金色格 |
| 血脉辅助 | lineage support（参考 PoE2 的血脉宝石） | `tier == LINEAGE`：具名、独一份、不进池子，守关 Boss 必掉（`boss_lineage`）。魔力 ×1.0，代价在词缀里。绯红格。★ 名字是本项目自己起的 ★ |
| 缩短持续 | Less Duration | 更少 40% 持续 + 更多 10% 伤害。对风暴呼唤 = 落雷更快；对烈焰风暴 = 少落几次 |
| **近战武器** | weapon | ★ 攻击技能的载体（ADR-032）★ 和法杖同款槽，`socket_tags = ATTACK`（法杖 = SPELL）。词缀全要求 ATTACK、只给槽里的技能；`default_loadout()` 不含武器 |
| 近战 | melee | ★ 不是第三条管线 ★ = 范围管线的 `Origin.FRONT`（面前 range 像素处的圈）。单体近战不带【范围】标签。出手走 `ATTACK_SPEED` |
| 重击 / 横扫 / 重锤猛击 / 双重打击 / 旋风斩 | Heavy Strike / Cleave / Ground Slam / Double Strike / Cyclone | 物理近战。重锤猛击译名没查证。双重打击 2 脉冲；★ 旋风斩是引导 ★（SELF、跟着人走、每段 1 圈） |
| 引导技能 | channelling | `SkillSpec.channel`（ADR-033）：按住一段一段放、每段扣蓝、松手 / 没蓝就停；引导中 Q 无效（`Player.is_channeling()`）。旋风斩 / 焚烧 / 闪电之触。cast_time = 每段时长 |
| 炼狱之击 / 冰霜之锤 / 静电之击 / 毒蛇打击 | Infernal Blow / Glacial Hammer / Static Strike / Viper Strike | 元素 / 混沌近战：点燃 / 冰缓 / 感电 + 3 脉冲 / 中毒。★ 中毒 INDEPENDENT 独立叠加 ★（精髓吸取是 REFRESH） |
| 灵体投掷 | Spectral Throw | ★ 攻击也可以是投射物 ★ 镶武器、吃武器伤害、也吃投射物辅助。不回旋 |
| 冰川之刺 | Glacial Cascade | 法术，`Origin.FRONT` + 天生连环 2（`SkillSpec.area_cascade`）= 三个圈排成一线 |
| 精英怪 / 词条 | elite / monster affix | 底子 +80% 生命 / +30% 伤害 + 1~2 条随机词条（`data/monster_affixes.gd`）。★ 狂暴用 FLAT 攻速 ★ 普通怪基础攻速是 0，INCREASED 是恒真数据 |
| 分波 / 增援 | wave / reinforcement | 房间总数 `enemies_for_step`，同时在场上限 `max_alive_for_step`，死一只补一只。精英排队尾压轴 |
| 守关 BOSS | floor boss | 第 1~3 层最后一步的 Boss，打赢照常领三选一 + 金币；**最终 BOSS** 只在第 4 层 |
| 技能栏 | — | ★ 已经没有这个东西了 ★ 现在是背包网格，摆放位置就是连接 |

> 曾经有一次 AI（我）把「电球术」当成 Ball Lightning，凭空造了个脉冲技能，返工了一整轮。
> **拿不准就问，不要猜英文原名。**

---

## 3. 必须跑的命令

Godot 装在 `D:\godot`，**不在 PATH 里**，要写全路径：

```powershell
# ① 新建了带 class_name 的脚本之后，先跑这个（否则全局类名没注册，测试会报 "Identifier not declared"）
D:\godot\Godot_v4.4.1-stable_win64_console.exe --headless --path D:\ohhh --import

# ② 数值单元测试（纯逻辑，快）
D:\godot\Godot_v4.4.1-stable_win64_console.exe --headless --path D:\ohhh --script res://test/run_tests.gd

# ③ 集成冒烟测试（真的把游戏跑起来）
D:\godot\Godot_v4.4.1-stable_win64_console.exe --headless --path D:\ohhh --script res://test/smoke_test.gd
```

两套都要输出「全部通过」才算完。

**跑起来看效果**（可选，但改了 UI 强烈建议）：

```powershell
D:\godot\Godot_v4.4.1-stable_win64.exe --path D:\ohhh
```

---

## 4. 动手前 / 动手后的检查清单

### 改之前

- [ ] 读过本文件第 1 节（不可违反的约束）
- [ ] 读过 [docs/DECISIONS.md](docs/DECISIONS.md) —— **确认你要改的不是一个已经深思熟虑过的决定**
- [ ] 在 [docs/TASKS.md](docs/TASKS.md) 认领任务（多 AI 并行时尤其重要，见第 5 节）

### 改之后

- [ ] 新增了 `class_name` → 跑过 `--import`
- [ ] `run_tests.gd` 全绿
- [ ] `smoke_test.gd` 全绿
- [ ] **新机制补了测试用例**（不是可选项，见下）
- [ ] 改了 UI → 真的开窗口看过，或截图确认过
- [ ] 更新了受影响的文档（README / ARCHITECTURE / DECISIONS）
- [ ] 在 TASKS.md 把任务标成完成

### 关于补测试

**新增战斗机制 = 必须加测试用例。** 这个项目的测试不是形式主义：

- PoE 式词缀交互复杂到一定程度后，改一条乘区规则可能三天后才发现某个构筑伤害翻倍
- 已经有过真实教训：`can_aim` 的坐标系写错导致「点了不能施法」，
  而当时冒烟测试是直接调 `_on_cast_requested()` 的、**绕过了整条按键链路**，一条测试都没红

**不要写恒真的断言。** 曾经写过一条「SubViewport 鼠标 = 主视口鼠标 − 容器偏移」，
实测发现引擎是实时推算的、这条永远成立 —— 这种断言比没有更糟，它给假信心。写之前先想：**它可能红吗？**

---

## 5. 多 AI / 多人并行时怎么不打架

### 5.1 认领任务

改之前先在 [docs/TASKS.md](docs/TASKS.md) 把任务状态改成 `进行中`，写上自己是谁（`@claude` / `@cursor` / `@某人`）。
完成后改成 `完成`。**这是唯一的协调机制，别跳过。**

### 5.2 按文件分工，别踩同一个文件

同时干活时，尽量让不同的人/AI 碰不同的文件。这几组基本互不影响：

| 领域 | 主要文件 | 会连带影响 |
|---|---|---|
| 战斗数值 / 词缀 | `combat/stat_set.gd` `modifier.gd` `damage_pipeline.gd` | `test/run_tests.gd` |
| 技能石 / 背包规则 | `combat/skill_gem.gd` `support_gem.gd` `gem_grid.gd` `gem_shape.gd` | `test/run_tests.gd` |
| 内容数据（加宝石/装备） | `data/gem_library.gd` `equip_library.gd` | 一般不影响别人 ← **最适合并行** |
| 投射物表现 | `game/projectile.gd` `pixel_art.gd` | `test/smoke_test.gd` |
| 界面 | `game/inventory_ui.gd` `gem_grid_view.gd` `hud.gd` | `test/smoke_test.gd` |
| 存档 | `game/gem_save.gd` `combat/gem_grid.gd`(to_data/from_data) | 两套测试 |

⚠️ **`test/run_tests.gd` 和 `test/smoke_test.gd` 是最容易冲突的两个文件** ——
它们又长又是所有人都要改。加测试时**追加在文件末尾的对应分区**，别插在中间，减少 diff 冲突。

### 5.3 提交要小、要频繁

一个任务一个提交。不要攒一大堆改动一次提交 —— 冲突了没法拆。
提交信息规范见 [CONTRIBUTING.md](CONTRIBUTING.md#提交信息规范)。

### 5.4 别改这些

- `.godot/`（引擎生成的缓存，已在 `.gitignore` 里）
- `*.uid` 文件（Godot 4.4 的资源标识，**要提交但不要手改**）
- `%APPDATA%\Godot\app_userdata\PoE-like ARPG\backpack.json`（玩家存档，不在仓库里）

---

## 6. 已知陷阱（都是真的踩过的）

| 陷阱 | 症状 | 正确做法 |
|---|---|---|
| **新 `class_name` 没注册** | 测试报 `Identifier "XXX" not declared` | 先跑 `--import` |
| **坐标系混用** | 「只有屏幕最右边能施法」 | `get_global_rect()` 配 `get_global_mouse_position()`；`get_rect()`(父坐标) 配 `get_local_mouse_position()`(自身坐标)，**不能交叉** |
| **SubViewport 的 World2D 是独立的** | 投射物穿过怪物没反应 | 场地里的一切（含 `_setup_walls()` 造的墙）必须 `view.add_child()` |
| **测试覆盖玩家存档** | 跑完测试背包被清空 | 冒烟测试在场景 `_ready` **之前**设 `GemSave.autosave = false` |
| **`as` 优先级低于 `==`** | `a == b as Array[Vector2i]` 直接解析错误 | 用辅助函数逐个比较（`test/run_tests.gd → _cells_eq`） |
| **在按钮回调里重建 UI** | 正在处理事件的按钮被 free 掉 | 用 `refresh.call_deferred()` |
| **`Input.warp_mouse` 在本机挪不动光标** | 用它做的 UI 探针全是假结果 | 别依赖它；用几何断言 + 事件注入 |

---

## 7. 代码风格

- **中文注释，解释「为什么」**。项目主人是初学者，`# 把 x 加 1` 这种注释没有价值，
  `# ★ 必须延迟一帧 ★ 因为分叉是在物理查询回调里触发的，直接 add_child 会报错` 才有价值
- 用 **GDScript 静态类型**（`var x: float = 0.0`、`func f(a: int) -> String:`）
- 重要的坑用 `★ ... ★` 标出来，扫一眼就能看到
- 常量/魔法数字要给名字，并写清单位（像素？秒？倍率？）

---

## 8. 文档地图

| 文件 | 写给谁 | 内容 |
|---|---|---|
| [README.md](README.md) | 所有人 | 这是什么、怎么跑、怎么玩、系统讲解 |
| **AGENTS.md**（本文件） | **AI** | 规约、检查清单、陷阱、并行分工 |
| [CLAUDE.md](CLAUDE.md) | Claude Code | 指向本文件 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 人类 | 环境、分支、提交、PR 流程 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 开发者 | 分层、模块边界、数据流 |
| [docs/DECISIONS.md](docs/DECISIONS.md) | 所有人 | ★ 为什么这么设计（改之前必看）★ |
| [docs/TASKS.md](docs/TASKS.md) | 所有人 | 任务板 + 认领 |
