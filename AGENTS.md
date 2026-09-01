# AGENTS.md —— AI 协作规约

> **任何 AI（Claude Code / Cursor / Copilot / Codex …）动手改这个仓库之前，先读完这一页。**
> 人类协作流程看 [CONTRIBUTING.md](CONTRIBUTING.md)；设计原理看 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

---

## 0. 30 秒搞清楚这是什么

Godot 4 + GDScript 写的 2D 俯视角像素 ARPG，核心是一套 **PoE（流放之路）式的词缀 / 技能石 / 伤害系统**。

- 画面：左边 300px 常驻背包面板，右边 400×400 正方形战斗画面
- 背包是**「背包乱斗」式网格**：宝石占 1 格、装备占多格，辅助宝石的**箭头指着谁就辅助谁**
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
| 火球术 | Fireball | 单发直线 + 点燃 |
| 提高 / INCREASED | increased | 所有同类**相加**，共用一个乘区 |
| 更多 / MORE | more | 每一条**独立连乘** |
| 弹射 / CHAIN | chain | 命中敌人后转向下一个敌人 |
| 撞墙反弹 / BOUNCE | — | 撞地形弹开，**不消耗**任何命中次数，和弹射是两回事 |
| 辅助宝石 | support gem | 一组带代价的词缀，靠**箭头**连到技能石上 |
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
