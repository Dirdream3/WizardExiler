# CLAUDE.md

Claude Code 会自动读这个文件。**内容不写在这里，全部在 [AGENTS.md](AGENTS.md)** ——
这样 Cursor / Copilot / Codex 等其它 AI 工具读同一份规约，不会出现"各家 AI 遵守不同规则"的情况。

## → 先读 [AGENTS.md](AGENTS.md)

下面只重复三条最容易出事的，其余一律以 AGENTS.md 为准：

1. **`combat/` 里不许出现任何 Godot 场景依赖**（Node / Sprite / 场景坐标 / FileAccess / get_tree）。
   整套单元测试就是靠这一条才能存在。

2. **「电球术」= PoE 的 Spark**（一次射 4 发乱窜的小球，撞墙会弹），
   **不是** Ball Lightning。这个坑返工过一整轮。

3. **改完必须跑两套测试，都要全绿**（Godot 在 `D:\godot`，不在 PATH）：
   ```powershell
   D:\godot\Godot_v4.4.1-stable_win64_console.exe --headless --path D:\ohhh --import          # 新增 class_name 后
   D:\godot\Godot_v4.4.1-stable_win64_console.exe --headless --path D:\ohhh --script res://test/run_tests.gd
   D:\godot\Godot_v4.4.1-stable_win64_console.exe --headless --path D:\ohhh --script res://test/smoke_test.gd
   ```

新增战斗机制**必须**补测试用例。写之前先问自己：**这条断言可能红吗？** 恒真的断言比没有更糟。
