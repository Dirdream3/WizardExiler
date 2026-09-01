# 参与开发

写给**人类**协作者。AI 看 [AGENTS.md](AGENTS.md)（那份规约同样适用于你，值得扫一遍第 1、2、6 节）。

---

## 1. 环境准备

| 需要 | 版本 | 说明 |
|---|---|---|
| Godot | **4.4.1 stable** | 本项目在 `D:\godot\Godot_v4.4.1-stable_win64.exe`，**没加到 PATH** |
| Git | 任意 | 没装的话：`winget install --id Git.Git -e` |

不需要编译、不需要装依赖。Godot 打开 `D:\ohhh` 这个文件夹按 **F5** 就能跑。

> 带 `_console` 后缀的那个 exe 会额外开一个控制台窗口，能看到 `print` 输出 —— 跑测试用它。

---

## 2. 跑测试

**改了 `combat/` 或 `game/`，两套都要跑，都要全绿。**

```powershell
# 新建了带 class_name 的脚本之后先跑这个，否则全局类名没注册
D:\godot\Godot_v4.4.1-stable_win64_console.exe --headless --path D:\ohhh --import

# 数值单元测试（纯逻辑，秒级）
D:\godot\Godot_v4.4.1-stable_win64_console.exe --headless --path D:\ohhh --script res://test/run_tests.gd

# 集成冒烟测试（真的把游戏跑起来，约 15 秒）
D:\godot\Godot_v4.4.1-stable_win64_console.exe --headless --path D:\ohhh --script res://test/smoke_test.gd
```

两套测试各管一半，都不能少：

- `run_tests.gd` —— 纯数值逻辑。它能存在，是因为 `combat/` 里没有任何引擎依赖
- `smoke_test.gd` —— 逻辑层和表现层接得上没有。**单元测试全绿不代表游戏里能跑**

冒烟测试里那行 `ERROR: Parse JSON failed` 是**故意的** —— 它在测"存档文件坏掉也不能炸"。

---

## 3. 目录约定

```
combat/   纯逻辑层。★ 不许出现 Node / Sprite / 场景坐标 / 文件读写 ★
game/     表现层。只管"怎么动、怎么演"，不写伤害公式
data/     内容数据（宝石、装备、Buff、角色）。没有逻辑，最适合并行加内容
test/     两套测试
docs/     设计文档
```

详细的模块职责看 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

---

## 4. 代码风格

- **中文注释，解释「为什么」不是「是什么」**。项目主人是初学者，
  `# 把 x 加 1` 没有价值；`# ★ 必须延迟一帧 ★ 分叉是在物理查询回调里触发的，直接 add_child 会报错` 才有价值
- 用 GDScript **静态类型**：`var x: float = 0.0`、`func f(a: int) -> String:`
- 重要的坑用 `★ ... ★` 框出来
- 魔法数字要给名字并注明单位（像素？秒？倍率？）

---

## 5. 分支

```
main            始终可运行、两套测试全绿
feat/xxx        新功能
fix/xxx         修 bug
docs/xxx        只改文档
```

直接往 `main` 推小改动可以；**功能性改动走分支 + PR**，方便别人（和 AI）看清楚改了什么。

---

## 6. 提交信息规范

用 [Conventional Commits](https://www.conventionalcommits.org/)，**正文写中文**：

```
<类型>(<范围>): <一句话说清楚改了什么>

<为什么这么改，以及有什么后果>
```

**类型**：`feat` 新功能 / `fix` 修 bug / `refactor` 重构 / `docs` 文档 / `test` 测试 / `chore` 杂项

**范围**：`combat` `game` `data` `ui` `save` `test` `docs`

例子：

```
feat(data): 加入「暴击伤害」辅助宝石

新增一颗要求 NONE 标签的辅助，提供 CRIT_MULTI INCREASED +0.5。
因为暴伤是独立乘区，配合已有的「暴击几率」能明显拉开构筑差距。
run_tests 补了 3 条断言。
```

```
fix(ui): 修正 can_aim 的坐标系，之前只有屏幕最右边能施法

get_rect() 是父节点坐标（x 从 300 起），get_local_mouse_position() 是
控件自身坐标（x 从 0 起），两个混着比 → 要求局部 x ≥ 300。
统一改用 get_global_rect() 配 get_global_mouse_position()。
冒烟测试补了 6 条边界断言。
```

**一个任务一个提交。** 攒一大堆一次提交，冲突了没法拆。

---

## 7. PR 流程

1. 从 `main` 开分支
2. 在 [docs/TASKS.md](docs/TASKS.md) 认领任务（改状态 + 写上自己）
3. 改代码 **+ 补测试**
4. 两套测试全绿；改了 UI 的话开窗口看一眼
5. 更新受影响的文档
6. 提 PR，描述里写清楚**为什么**这么改

### PR 自检清单

```markdown
- [ ] `--import` 跑过（如果新增了 class_name）
- [ ] `run_tests.gd` 全绿
- [ ] `smoke_test.gd` 全绿
- [ ] 新机制补了测试用例，而且这些断言**可能会红**
- [ ] 改了 UI → 实际跑过 / 截图确认
- [ ] 没有违反 AGENTS.md 第 1 节的四条约束
- [ ] 更新了 README / ARCHITECTURE / DECISIONS（如有需要）
- [ ] TASKS.md 状态已更新
```

---

## 8. 加内容最省事（推荐新人从这开始）

想加一颗辅助宝石？只要在 `data/gem_library.gd` 里加一个函数：

```gdscript
static func support_crit_multi() -> SupportGem:
    return _sup(&"sup_crit_multi", "暴击伤害", "伤", T.NONE, 1.20,
        "提高暴击伤害。暴伤是独立乘区，和暴击率是乘法关系。",
        [M.new(S.CRIT_MULTI, M.Kind.INCREASED, 0.50, T.NONE)],
        [0.02])
```

再把它加进 `all_supports()` 就完事了 —— **一行逻辑都不用写**，
它会自动出现在背包里（老存档也会自动补进来）。装备同理，看 `data/equip_library.gd`。

这就是标签 + 词缀系统的意义：**内容是纯数据**。
