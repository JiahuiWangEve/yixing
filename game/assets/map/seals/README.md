# 朱印军符

透明、代码原生SVG，依据用户确认的黑印＋红色将军印方向制作。七个节点符号无背景和标签，标签由地图统一绘制。少量缺墨为透明孔隙，不是白色底纹。

victory_seal.svg为透明红色方印，文字转为路径，不依赖客户端字体。mountains／river／fields保留为独立背景素材；当前绘制器使用同风格的原生线条，并只在碰撞检测后的空白区域放置。

原来的山水与建筑图集保留供历史追溯，不再用于v0.9地图运行时。

印章文字轮廓：Noto Serif CJK SC Bold 2.003（Adobe / Noto CJK），SIL Open Font License 1.1；仅“将”“军”两字转为SVG路径，未复制字体二进制。上游 https://github.com/notofonts/noto-cjk 。字体许可见本目录 FONT_LICENSE.txt。
