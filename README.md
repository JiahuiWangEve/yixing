# 弈行 v0.14.5 · 过牌补抽与强化展示

战斗内可统一支付3费过牌，不触发效果，随后正常抽1张；普通和消耗牌均进弃牌堆，免费移动牌仅在本回合移除，也抽1张。空牌堆正常洗牌，可能抽回刚弃的牌；新抽疲惫照常扣1能量（最低0）。强化展示保留旧牌、翻面、新牌读窗，完整播放2秒。选中或按住拖动时显示右侧弃置区，点击该区或拖入高亮后松手确认。声音开关统一移到首页“设置”，设置页可切换并保存声音偏好。流血改为当前、下一玩家回合末各 1 伤，均在敌方攻击前。封面移除过时调试选关入口。所有精英加速统一为每棋子每敌方回合最多移动一次，多余加速跨回合顺延。

# 弈行 v0.14.1 · 空投

将的专属奖励加入3费消耗牌“空投”：任意空格落地，周围3×3各3伤，自扣1命，下个玩家回合停行动。生命归零优先判负，下一场恢复消耗牌并清除休整状态。第二章与守阵 AI 保持不变。

# 弈行 v0.14.0 · 坚城与守阵

第一章决战后继承剩余血量与永久牌组进入第二章“坚城”。新增三套普通战、两套关隘和内城决阵，组合厚血棋子、可击倒后复归的不屈守军与有限增援。将优先维持有效防线而非追击，仍躲避真实炮线威胁。

详见 [第二章规则与模板](docs/SECOND_CHAPTER.md) 和 [快速发布与后台回归](docs/DEMO_RELEASE_CHECKS.md)。

# 弈行 v0.11.0 · 炮阵协同

炮与支援棋子联合走位、有效炮架留守、两阶段准备、侧翼护将与过时炮阵转移。保留先攻击后移动、决战每轮最多移动一次及加速顺延。主动战术留守消耗一次行动资格，受阻与冻结不消耗。地图、卡牌、血量和减包策略不变。

详见 [炮阵规则与搜索边界](docs/CANNON_AI.md) 和 [验证记录](docs/VALIDATION_v0.11.0.md)。

# 弈行 v0.10.1 · 决战加速顺延

新增士、急行卒与固定节点军阵，加入五类精英规则；敌马2血、象3血、精英将5血、Boss将9血。敌方回合才按最新棋盘决定移动，不再展示未来落点。保留 v0.9.2 地图性能缓存与字体减包。Demo 使用独立新局存档，升级需重新开局，旧数据、角色解锁与设置不删除。

详见 [军阵规则](docs/ENEMY_ENCOUNTERS.md) 与 [验证范围](docs/VALIDATION_v0.10.1.md)。

# 弈行 v0.9.2 · 手机地图性能修复

缓存道路曲线与遮挡计算，合批纸纹／道路绘制，静止地图不再逐帧重画；滚动、选择、行军与盖印仍实时响应。保留黑红军符画风、v0.9.1 减包与现有玩法／存档。验证和性能测量边界见 [v0.9.2](docs/VALIDATION_v0.9.2.md)。

# 弈行 v0.9.1 · 朱印军符与 Web 减包

保留 v0.9.0 黑印地图与红色我方标记／通关印，缩减字体并从 Web 导出排除旧山水素材，不改玩法。新增可重建字体子集、缺字与字形一致性检查、导出包审计。维护方法见 [Web 减包说明](docs/WEB_SIZE.md)，验证范围见 [v0.9.1](docs/VALIDATION_v0.9.1.md)。

# 弈行 v0.9.0 · 朱印军符行军图

当前源码分支为 `gpt`，发布产物为 `gh-pages`。本版将山水背景与建筑贴图替换为清淡中国纸底、纯黑木刻军符与透明红色“将军”通关印；我方位置以红帅标记。类别文字始终可见，可达路线使用深墨箭头，已走路线为实线；背景装饰只放在节点与道路之外的留白区。保持16节点、8步章节与现有卡牌／空格结束回合规则。

详见 [本版验证与限制](docs/VALIDATION_v0.9.0.md)、[开局与卡牌规则](docs/START_PROFILES.md)、[v0.8.0验证](docs/VALIDATION_v0.8.0.md)。本版不改变存档结构；v0.8.0当前局可继续，旧版不迁移。


# 弈行

历史三开局版本：**v0.5.0**。GPT 持续开发分支为 [`gpt`](https://github.com/JiahuiWangEve/yixing/tree/gpt)，网页导出分支为 [`gh-pages`](https://github.com/JiahuiWangEve/yixing/tree/gh-pages)。

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

在 Codex 环境设置中选择仓库 `JiahuiWangEve/yixing`，后续源码任务固定选择 `gpt` 分支，网页产物使用 `gh-pages`。将手动设置脚本设为：

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
