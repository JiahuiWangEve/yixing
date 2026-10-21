# 弈行开发约定

- 当前可编辑工程是 `game/project.godot`，恢复自 v0.4.4，当前开发 v0.10.0。`archive/` 仅用于追溯。
- 使用 Godot **4.6.3 标准版**，不使用 .NET。Linux 首次运行 `bash scripts/setup.sh`。
- 始终可使用 `bin/godot`；若需要裸命令，先 `export PATH="$PWD/bin:$PATH"`。
- 验证命令：`bash scripts/verify.sh`。覆盖资源导入、所有游戏脚本解析、主场景 120 帧启动、核心规则回归。日志在 `verification/latest/`。
- 不提交 `.godot/`、安装的引擎、导出模板、运行时存档或 `build/`。
- 保留 `.gd.uid` 和资源 `.import` 设置；这些不是可删除的运行缓存。
- 草案只作流程参考；战法、宝物、地形、事件等扩展不作为当前已有功能，不在环境维护中擅自实现。
- 未来 Web 导出先运行 `bash scripts/install-web-templates.sh`，再 `mkdir -p build/web` 和 `bin/godot --headless --path game --export-release Web ../build/web/index.html`。Web 预设为单线程。
- 无界面验证不能代替桌面或手机的画面、拖放、触控与音效试玩。

- GPT 后续源码更新固定提交到 `gpt` 分支，不直接更新 `main`。用户授权发布时，将该分支 Web 导出产物更新到现有 `gh-pages` 分支。
- 开局配置见 `game/start_profiles.gd`；规则汇总见 `docs/START_PROFILES.md`。新增规则继续扩展现有 Godot SceneTree 回归。
- `gpt-web.yml` 在 gpt 源码变更后验证并将导出提交到 gh-pages。GITHUB_TOKEN 的推送不会触发其他工作流；发布任务需再通过 GitHub App 向 gh-pages 提交发布标记（如 `release.json`），触发该分支原有 Pages 工作流，并检查其结果。

- 改动游戏文案后运行 `python3 scripts/font_subset.py --write`；提交 OTF 与 JSON。验证会拒绝陈旧/缺字子集，保留原字体第 0 面字形。安装依赖 `python3 -m pip install -r scripts/font-requirements.txt`。Web 导出后运行 `python3 scripts/check_web_package.py build/web/index.pck`。
