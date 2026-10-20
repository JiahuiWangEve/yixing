弈行 v0.4.4 · 从发布包恢复的 Godot 可编辑工程

打开方法
1. 使用 Godot 4.6.3 标准版编辑器。
2. 解压 ZIP，在 Godot 项目管理器选择“导入”，选中本目录的 project.godot。
3. 等待字体和音效自动导入，打开工程，按 F6 运行当前主场景或 F5 运行项目。
4. 手机端可以先保存 ZIP，再传到电脑上操作。

恢复范围
来源：弈行 Site 第14个保存版本，游戏 v0.4.4，Godot 4.6.3。
从该版本的 PCK 恢复出 project.godot、主场景 main.tscn、17份 GDScript、
字体和12个WAV音效。保留脚本UID、资源导入设置和字体许可说明。
这是从发布包重建的可编辑工程，不是最初工作目录的逐字备份。
原始代码注释、排版、未导出的文件、原工作目录中的测试和其他开发资料，
无法仅凭此发布包保证恢复。游戏逻辑未作人为修改。

主要编辑位置
main.gd：主流程、卡牌定义、出牌和回合。
rules.gd：棋子移动、攻击和受击转移规则。
campaign.gd / enemy_ai.gd：关卡和敌方行为。
fan_hand.gd / card_input.gd：手牌布局、拖放操作。
reward_choice.gd / player_skills.gd：奖励选择、技能与解锁。
frontend.gd / tutorial.gd：菜单与教学。
assets/：字体和音效素材。

验证情况
GDRE Tools 2.7.4 识别引擎为4.6.3；67个包内文件校验通过。
17份脚本全部反编译，31项导出资源转换全部成功，工具报告失败0、损失转换0。
已用官方 Godot 4.6.3 在没有生成缓存的工程副本上重新导入全部素材，退出码0；
主场景以无界面模式启动120帧后正常退出，未出现脚本或资源加载错误。
导入期间受限测试环境不允许编辑器开启本地调试TCP端口，出现网络监听提示；
不影响资源导入和独立游戏启动。完整的画面、触屏、音效和规则回归尚未完成。
导入和启动的原始日志记录在 verification/。

重新发布到 Web
这个恢复工程没有原 export_presets.cfg。重新导出前需在 Godot 中新建 Web
导出预设，并安装匹配4.6.3的导出模板。原Site采用单线程Web导出；要沿用
原网站的打包方式，可参考先前提供的网页备份和 SITE_BUILD_INFO.json。
本ZIP不包含已经发布的Web引擎、外层网页和用户浏览器中的技能解锁存档。
修改Godot工程并不会自动更改Site，需要重新导出并发布。

来源记录
Site：https://yixing-xiangqi-cards-v02.darkquail259.chatgpt.site
来源Git提交：9753f06ffef5fc83939e39ffc112051f51a3fcf6
来源PCK的SHA-256：0e17c73f2300f5d9430ddfe512a25d62422e6e5f0dd47341ba0bc06fc7359f1b
恢复工具：https://github.com/GDRETools/gdsdecomp/releases/tag/v2.7.4
Godot引擎：https://github.com/godotengine/godot/releases/tag/4.6.3-stable

今后建议每次修改都保存源工程ZIP，并明确其游戏版本和对应Site版本。
