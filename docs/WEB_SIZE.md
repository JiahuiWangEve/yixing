# Web 资源减包与字体维护

v0.9.1 不修改玩法、中文文字外观或存档格式。全量字体与旧山水素材保留在 Git 源码，Web 导出排除它们。

## 字体子集

- 原始来源：`game/assets/font.ttc` 与原许可 `FONT_LICENSE.txt`，均保留。
- 运行时：`game/assets/font-subset.otf`，重命名为 **Yixing UI Subset**；许可随 Web 包分发。
- 使用原始集合第 **0** 面。Godot 4.6.3 实测原 FontFile 为 `Noto Sans CJK JP Regular`，`cache/0/face_index=0`。虽然游戏使用简体中文，不能擅自切到第 2 面 SC，否则部分汉字轮廓会改变。
- 构建保留 OpenType 排版特性，并逐字比较原字体和子集的轮廓、字宽。运行时检查关闭系统字体兜底，防止本机字体掩盖缺字。

改动游戏文案后：

```bash
python3 -m pip install -r scripts/font-requirements.txt
python3 scripts/font_subset.py --write
bash scripts/verify.sh
```

提交 `font-subset.otf` 和 `font-subset.json`。默认不带 `--write` 是严格检查，不自动更改文件。CI 会拒绝陈旧子集、未覆盖字符、变化的字形或不匹配的工具版本。

收集范围是 `game/` 下全部 `.gd/.tscn/.tres/.godot/.json/.csv/.po` 文本（排除 `.godot/` 缓存和生成的字体清单自身），加完整可打印 ASCII。源码中的 Unicode 转义和常量 `char()`/`String.chr()` 也计入。动态码点表达式将报错，必须先扩展收集规则。当前游戏无用户任意文字输入；将来增加聊天、玩家命名、外部语言文件或服务器文案时，必须重新设计字体覆盖，不可假定本子集覆盖任意汉字。

不要在临时 QA 场景留在 `game/` 时重建，以免将测试文案收进正式字体。

## 导出审计

```bash
bin/godot --headless --path game --export-release Web ../build/web/index.html
python3 scripts/check_web_package.py build/web/index.pck
```

审计读取 PCK v3 清单并验证每项 MD5，拒绝原 TTC 与旧山水图，确认子集、字体许可与新军符存在，并限制 PCK 小于 2 MB。持续保留旧素材源码，不等于要继续打包。

Godot 引擎 WASM 不在本轮改动范围。下载大小不等于启动耗时；gzip 已由 GitHub Pages 启用，实际网络延迟和浏览器编译成本仍依设备而异。没有增加 PWA、改变缓存策略或迁移托管。
