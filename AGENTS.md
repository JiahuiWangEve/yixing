# 弈行开发约定

- 当前可编辑工程是 `game/project.godot`，恢复自 v0.4.4。`archive/` 仅用于追溯。
- 使用 Godot **4.6.3 标准版**，不使用 .NET。Linux 首次运行 `bash scripts/setup.sh`。
- 始终可使用 `bin/godot`；若需要裸命令，先 `export PATH="$PWD/bin:$PATH"`。
- 验证命令：`bash scripts/verify.sh`。覆盖资源导入、所有游戏脚本解析、主场景 120 帧启动、核心规则回归。日志在 `verification/latest/`。
- 不提交 `.godot/`、安装的引擎、导出模板、运行时存档或 `build/`。
- 保留 `.gd.uid` 和资源 `.import` 设置；这些不是可删除的运行缓存。
- 草案只作流程参考；战法、宝物、地形、事件等扩展不作为当前已有功能，不在环境维护中擅自实现。
- 未来 Web 导出先运行 `bash scripts/install-web-templates.sh`，再 `mkdir -p build/web` 和 `bin/godot --headless --path game --export-release Web ../build/web/index.html`。Web 预设为单线程。
- 无界面验证不能代替桌面或手机的画面、拖放、触控与音效试玩。
