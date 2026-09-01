# 架构

面向**开发者**：代码是怎么分层的、每个模块管什么、为什么这么分。

- 游戏玩法、系统讲解 → [README.md](../README.md)
- AI 规约、检查清单 → [AGENTS.md](../AGENTS.md)
- 每个设计决定的来龙去脉 → [DECISIONS.md](DECISIONS.md)

---

## 1. 三层

```
┌─────────────────────────────────────────────┐
│  game/    表现层                             │
│  怎么动、怎么演、怎么画、怎么读写文件           │
│  ↓ 只读数据，不写规则                         │
├─────────────────────────────────────────────┤
│  data/    内容层                             │
│  宝石、装备、Buff、角色的**数据**             │
│  ↓ 只填数据，不写逻辑                         │
├─────────────────────────────────────────────┤
│  combat/  纯逻辑层                           │
│  ★ 不依赖任何 Godot 节点 ★                   │
│  词缀、标签、伤害公式、背包规则                │
└─────────────────────────────────────────────┘
```

**依赖方向是单向的**：`game/` → `data/` → `combat/`，反过来一律不行。

### 为什么 `combat/` 必须零引擎依赖

1. **能跑单元测试** —— `test/run_tests.gd` 的 271 个断言全靠这一条
2. **能做离线 DPS 计算器**（Path of Building 那种）
3. **将来联机能搬到服务器验算**

所以 `combat/` 里不许有 `Node` / `Sprite` / `Camera` / 场景坐标 / `FileAccess` / `get_tree()`。

> 例外说明：`GemShape` / `GemGrid` 用 `Vector2i` 表示「第几列第几行」，
> 那是**逻辑下标**不是屏幕像素，纯数学类型，headless 下照样跑。

---

## 2. 模块职责

### combat/ —— 纯逻辑

| 文件 | 管什么 | 关键点 |
|---|---|---|
| `combat_tags.gd` | 标签位掩码 | 派生标签（元素）必须**独立占一位** |
| `combat_stat.gd` | 属性表 | 新增可被词缀影响的数值 = 在枚举里加一行 |
| `modifier.gd` | ★ 一条词缀 ★ | `FLAT` / `INCREASED` / `MORE` 三种乘区 |
| `stat_set.gd` | ★ 四段式公式的**唯一**实现 ★ | 所有算伤害的地方都走它 |
| `buff_def / buff_instance / buff_container` | Buff 模板 / 实例 / 叠加规则 | 4 种叠加规则：刷新 / 叠层 / 取最强 / 独立 |
| `skill_spec.gd` | 一次施法用的参数 | 没有等级概念 |
| `skill_gem.gd` | ★ 主动技能石 ★ | 等级 + 成长 + 标签 → `build()` 出 `SkillSpec` |
| `support_gem.gd` | ★ 辅助宝石 ★ | 一组带代价的词缀 + `required_tags` |
| `equip_item.gd` | ★ 一件装备 ★ | 一组词缀 + 一个占地方的形状 |
| `gem_shape.gd` | 占几格、箭头朝哪、怎么转 | 旋转后**归一化到左上角 (0,0)** |
| `gem_grid.gd` | ★ 背包网格 ★ | 放置/碰撞、箭头连接判定、存档序列化 |
| `gem_link.gd` | 网格**算出来的结果** | 1 主石 + 指着它的辅助。没有 socket/unsocket |
| `projectile_spec.gd` | 一发投射物的参数 | 由技能基础值 + 词缀算出 |
| `projectile_state.gd` | 穿透/分叉/弹射的判定 | 命中后该干嘛 |
| `damage_pipeline.gd` | ★ 五步伤害管线 ★ | 顺序写死：基础→词缀→暴击→减免→承受 |
| `combat_entity.gd` | 战斗单位的数据模型 | 持有四层词缀 |
| `hit_result.gd` | 一次伤害的完整记录 | 带分步说明，给面板用 |

### data/ —— 内容

| 文件 | 内容 |
|---|---|
| `demo_content.gd` | Buff、怪物技能、角色（含天赋 + 开局装备） |
| `gem_library.gd` | 2 颗主动技能石 + 9 颗辅助宝石 |
| `equip_library.gd` | 法杖 / 头盔 / 靴子 / 戒指 |

**这一层没有逻辑，全是数据** → 加内容最省事，也最适合多人/多 AI 并行。

### game/ —— 表现

| 文件 | 管什么 |
|---|---|
| `world.gd` | 主场景调度：搭场地、刷怪、接信号、把鼠标位置告诉玩家 |
| `player.gd` | 移动 + 施法 + **持有背包网格** |
| `enemy.gd` | 追击 + 近战 |
| `projectile.gd` | 投射物怎么飞、怎么弹、怎么分叉 |
| `inventory_ui.gd` | ★ 左侧 300px 常驻面板 ★ |
| `gem_grid_view.gd` | ★ 网格怎么画、点击怎么翻译成格子坐标 ★ |
| `hud.gd` | 盖在战斗画面上的两样：死亡大字 + Tab 详情面板 |
| `ui_helper.gd` | 面板和 HUD 共用的小工具 |
| `gem_save.gd` | ★ 背包存档读写 ★（`combat/` 不碰文件，所以放这） |
| `damage_report.gd` | Tab 面板的文本（迷你版 Path of Building） |
| `pixel_art.gd` | 占位美术：字符画 → 贴图 |
| `input_setup.gd` | 用代码注册按键 |

---

## 3. 数据流：从「按下鼠标」到「怪物掉血」

```
玩家按左键
  └→ Player._physics_process 看 can_aim（World 每帧按鼠标位置写进来）
      └→ Player._try_cast()：查魔力、算冷却（施放时间 ÷ 施法速度）
          └→ 发 cast_requested 信号
              └→ GameWorld._on_cast_requested()
                  ├→ ProjectileSpec.build(玩家属性, 当前技能)   ← 纯逻辑
                  │    读 PROJECTILE_COUNT / SPREAD / DURATION … 全走四段式
                  └→ 按 spread_angles() 生成 N 个 Projectile 节点
                      └→ Projectile._on_body_entered()
                          ├→ DamagePipeline.compute_hit()      ← 纯逻辑，五步
                          ├→ Enemy.take_hit() 扣血 + 飘字
                          └→ ProjectileState.decide_on_hit()   ← 纯逻辑
                               穿透？分叉？弹射？还是消失？
```

**注意所有带「纯逻辑」标记的步骤都在 `combat/` 里** —— 它们能脱离游戏单独测。

---

## 4. 词缀的四层

查询任何属性时，这四层**叠在一起**算一次四段式（`CombatEntity._layers()`）：

| 层 | 内容 | 谁维护 | 什么时候变 |
|---|---|---|---|
| `gear_mods` | 天赋 / 被动树 | `DemoContent.make_player()` | 不变 |
| `equip_mods` | ★ 背包里的装备 ★ | `Player.rebuild()` **整层重建** | 挪动装备时 |
| `skill_mods` | 箭头连着当前技能的辅助宝石 | `Player.rebuild()` **整层重建** | 挪宝石 / 切技能时 |
| Buff | 增益 / 减益 | `BuffContainer` | 每帧计时 |

**「整层重建」而不是增删单条**，是这套设计的关键：
背包一变就把整层清空重填，不用去追"哪一条该删"，也不会串味。

---

## 5. 背包网格：连接关系 = 摆放位置

```
┌──┬──┬──┬──┐
│  │多▶│电│  │   多重投射的箭头指进电球术 → 辅助它
├──┼──┼──┼──┤
│  │  │闪▲│  │   闪电增强的箭头朝上指进电球术 → 也辅助它
└──┴──┴──┴──┘
```

- 宝石都只占 **1 格**；装备占多格（法杖 1×3、头盔 2×2…）
- 辅助宝石有**箭头**，箭头指进哪颗技能石就辅助哪颗
- 装备**不用连**，放在背包里就生效
- 技能石只占 1 格 → 四面最多 4 个箭头位 → **PoE 的「4 连」是几何自然的结果**

判定全在 `GemGrid` 里（纯逻辑、能单测）：

| 方法 | 作用 |
|---|---|
| `can_place / reject_reason` | 能不能放、放不下的原因 |
| `arrow_state(p)` | `linked`（绿）/ `blocked`（红，标签不匹配）/ `idle`（灰） |
| `supports_for(技能石)` | 真正在辅助它的那些 |
| `link_for(技能石)` | 打包成 `GemLink` 交给战斗系统 |
| `to_data / from_data` | 存档序列化（不碰文件） |

---

## 6. 画面布局：SubViewport

```
┌──────────────┬──────────────────┐
│ 左侧常驻面板  │   战斗画面        │
│  300 × 400   │   400 × 400      │
│  InventoryUI │   SubViewport    │
└──────────────┴──────────────────┘
```

战斗画面是**真正的 `SubViewport`**，不是"拿面板盖住左半边"。
好处：怪物和投射物被硬边界裁掉，不可能跑到面板上面去。

**代价（两个必须记住的坑）**：

1. SubViewport 有**自己的一份 `World2D`** →
   场地里的一切（含 `_setup_walls()` 造的墙）必须 `view.add_child()`，
   挂到 `GameWorld` 自己身上就和角色不在同一个物理世界里，永远撞不到。

2. 玩家住在 SubViewport 里，**问不到主窗口的鼠标在哪** →
   "鼠标在不在战斗区里"由 `GameWorld._process` 判断后写进 `Player.can_aim`。
   判断时两边必须同坐标系：`get_global_rect()` 配 `get_global_mouse_position()`。

> 摄像机 `zoom = 2`，所以 400×400 的画面里看到的是 **200×200** 的世界，
> 场地是 400×400 → 摄像机会跟着玩家滚。

---

## 7. 存档

- 位置：`%APPDATA%\Godot\app_userdata\PoE-like ARPG\backpack.json`（**不在仓库里**，不会冲突）
- 序列化在 `GemGrid.to_data() / from_data()`（纯逻辑，能单测）
- 文件读写在 `game/gem_save.gd`（`combat/` 不碰文件）
- 存的是**「当前技能是哪颗宝石」的 id，不是下标** —— 下标会因为挪动宝石而指到别人身上

读档四层容错（因为宝石表还在改，存档一定会和代码对不上）：

| 情况 | 处理 |
|---|---|
| 存档里有已删掉的宝石 | 跳过，其余照常还原 |
| 位置冲突 / 越界 | 自动找空地，不丢东西 |
| 图鉴里新加了东西 | 自动补进空地 |
| 文件坏了 / 版本不对 | 退回默认摆法，不炸 |

---

## 8. 测试

| 文件 | 测什么 | 为什么需要 |
|---|---|---|
| `test/run_tests.gd` | 纯数值逻辑（271 断言） | 词缀交互复杂到一定程度，不写测试必炸 |
| `test/smoke_test.gd` | 逻辑层和表现层接得上 | **单元测试全绿不代表游戏里能跑** |

冒烟测试覆盖了这些"只有真跑才知道"的东西：

- 真实按键 → `Player._try_cast()` → 放出投射物（曾经这条没覆盖，导致"不能施法"的 bug 一条测试都没红）
- 按键 / 鼠标事件转发进 SubViewport
- 背包网格的点击、右键旋转、放置校验
- 存档真的落盘再读回来（含版本号不对、文件损坏）
