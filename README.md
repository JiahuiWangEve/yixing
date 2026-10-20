# 弈行

当前开发版本：**v0.5.0**。GPT 持续开发分支为 [`gpt`](https://github.com/JiahuiWangEve/yixing/tree/gpt)，网页导出分支为 [`gh-pages`](https://github.com/JiahuiWangEve/yixing/tree/gh-pages)。

本版加入三种开局与专属牌组／奖励池：将2命、马1命、炮车1命。炮车可切换行军与攻击姿态，展开时每回合首次抽3张牌；新增统一“消耗”标签和将专属奖励“吐纳”。完整规则与初始牌组见 [docs/START_PROFILES.md](docs/START_PROFILES.md)。

以下保留恢复工程的说明与验证入口。

# 恢复工程 Godot 恢复工程

当前游戏基线为从发布包恢复的 **v0.4.4**。本次只准备开发环境、整理工程并核对现有行为，没有修改游戏逻辑或实现扩展草案。

## 开发与验证

在仓库根目录运行：

```bash
bash scripts/setup.sh
export PATH="$PWD/bin:$PATH"
godot --version
bash scripts/verify.sh
```

`setup.sh` 安装 Linux 对应架构的 Godot 4.6.3 标准版，校验官方 SHA-512，再完成验证。重复运行会复用已安装引擎。`bin/godot` 无需依赖系统目录写权限；安装脚本仅在 `/usr/local/bin` 可写时额外安装全局命令。前置命令为 bash、curl、python3、timeout，标准 Linux Codex 镜像具备这些命令。

桌面运行：用相同版本编辑器导入 `game/project.godot`，按 F5。

## Codex 云端环境

在 Codex 环境设置中选择仓库 `JiahuiWangEve/yixing`，先选择本 PR 分支测试，合并后使用 `main`。将手动设置脚本设为：

```bash
bash scripts/setup.sh
```

如界面提供维护脚本，填写 `bash scripts/maintenance.sh`。后续任务统一执行 `bin/godot`，或在当前 shell 中设置上述 PATH。设置阶段需允许下载官方引擎与校验文件，涉及 `downloads.godotengine.org`、`godot-releases.nbg1.your-objectstorage.com`、`github.com` 及 GitHub 下载重定向域名。日常检查可离线运行。

仓库文件提供可复用配置，但不会自动创建或绑定你账号内的 Codex 托管环境。本次实际检查在当前 Linux x86_64 工作容器完成；Codex 环境界面的保存与首次任务验证尚待执行。

## 工程结构

- `game/`：唯一当前工程，17 份原游戏脚本与素材、UID、导入设置均保留。
- `scripts/`：安装、维护、验证与未来 Web 模板安装命令。
- `tests/recovered_checks.gd`：针对当前恢复版的核心行为回归。
- `verification/2026-10-20/`：本次实测日志；`verification/latest/` 为后续运行生成的临时日志。
- `docs/VALIDATION.md`：验证结果、两版差异与边界。
- `docs/recovery-original/`：恢复时的原始清单、工具日志和旧验证记录。
- `archive/`：原始旧版与恢复版 ZIP，以及仓库旧展开工程中特有的文件。ZIP 与上传附件逐字相同；归档用于追溯，不作为活动工程。

## 后续 Web 导出

已补 `game/export_presets.cfg`，名称 `Web`，单线程，与恢复包发布记录一致。按本次范围，尚未安装模板或执行 Web 导出。需要时运行：

```bash
bash scripts/install-web-templates.sh
mkdir -p build/web
bin/godot --headless --path game --export-release Web ../build/web/index.html
```

模板安装脚本下载官方完整模板包并校验，仅保留匹配 4.6.3 的 Web 模板。首次下载较大。预设还需在实际导出及浏览器试玩后验收。导出的文件不是原 Site 的外层网页；重新发布仍需处理网页外壳与静态资源。

## 参考

- [玩法与扩展草案](https://chatgpt.com/space/page_089b80df348481918b9abdaa71a167c6)：构思参考，扩展项不作现版本验收要求。
- [原发布站点](https://yixing-xiangqi-cards-v02.darkquail259.chatgpt.site)
- [Godot 4.6.3 官方下载](https://godotengine.org/download/archive/4.6.3-stable/)
- [Godot Web 导出说明](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_web.html)
- [Codex 设置脚本与维护脚本说明](https://learn.chatgpt.com/docs/environments/cloud-environment)
