extends RefCounted
const LESSON_NAMES = ["移动与抽牌", "攻击与能量", "移动牌与留牌", "危险与行动顺序", "破将、奖励与增援"]
var game
func _init(owner): game = owner
func entries() -> Array:
	match game.screen:
		"home": return ["开始游戏", "教程", "调试选关", "声音：" + ("静音" if game.audio_system.muted else "开启")]
		"skill_selection": return ["帅 · 四向一步", "马 · 马步移动" if game.skill_system.is_unlocked("horse") else "马 · 击败第 6 关解锁", "返回首页"]
		"tutorial_menu":
			var result = ["继续上次小节：%d" % (game.tutorial_resume_lesson + 1)]
			for i in 5: result.append("%d · %s" % [i + 1, LESSON_NAMES[i]])
			result.append("返回首页");return result
		"debug_menu":
			var result = []
			for n in range(1, game.CAMPAIGN.LAST_STAGE + 1): result.append("第 %d 关 · 预选 %d 轮奖励" % [n, n - 1])
			result.append("返回首页");return result
		"tutorial_pause": return ["继续练习", "重玩本节", "跳过当前练习", "跳过本节", "教程目录", "返回首页"]
		"tutorial_complete": return ["下一节" if game.tutorial.lesson_index < 4 else "完成教程，返回首页", "重玩本节", "教程目录", "返回首页"]
	return []
func button_rect(i: int) -> Rect2:
	var count = entries().size()
	if game.compact_landscape:
		var col = i % 2; var row = i / 2
		return Rect2(70 + col * 430, 140 + row * 72, 390, 58)
	if game.mobile_layout:
		var top = 142 if count > 5 else maxf(150, game.ui_size.y * 0.25)
		var step = 56 if count > 5 else 74
		return Rect2(24, top + i * step, 432, 52 if count > 5 else 60)
	return Rect2(420, 180 + i * 72, 440, 58)
func click(pos: Vector2):
	for i in entries().size():
		if button_rect(i).has_point(pos): activate(i);return
func activate(i: int):
	match game.screen:
		"home":
			match i:
				0: game.skill_system.show_selection()
				1: game.open_tutorial_menu()
				2: game.screen = "debug_menu"
				3: game.audio_system.toggle_mute()
		"skill_selection":
			match i:
				0: game.skill_system.choose("king")
				1: game.skill_system.choose("horse")
				2: game.show_home()
		"tutorial_menu":
			if i == 0: game.start_tutorial(game.tutorial_resume_lesson)
			elif i <= 5: game.start_tutorial(i - 1)
			else: game.show_home()
		"debug_menu":
			if i < game.CAMPAIGN.LAST_STAGE: game.start_debug_stage(i + 1)
			else: game.show_home()
		"tutorial_pause":
			match i:
				0: game.screen = "game"
				1: game.screen = "game";game.tutorial.restart()
				2: game.screen = "game";game.tutorial.skip_step()
				3:
					if game.tutorial.lesson_index < 4: game.start_tutorial(game.tutorial.lesson_index + 1)
					else: game.show_home()
				4: game.open_tutorial_menu()
				5: game.show_home()
		"tutorial_complete":
			match i:
				0:
					if game.tutorial.lesson_index < 4: game.start_tutorial(game.tutorial.lesson_index + 1)
					else: game.show_home()
				1: game.screen = "game";game.tutorial.restart()
				2: game.open_tutorial_menu()
				3: game.show_home()
func draw():
	game.draw_rect(Rect2(Vector2.ZERO, game.ui_size), game.THEME.BACKGROUND)
	var titles = {"home": "弈 行", "skill_selection": "选择初始技能", "tutorial_menu": "教程 · 选择小节", "debug_menu": "调试选关", "tutorial_pause": "教学菜单", "tutorial_complete": "本节完成"}
	var origin = (Vector2(24, 60) if game.compact_landscape else Vector2(24, 90)) if game.mobile_layout else Vector2(420, 100)
	game.text_at(origin, titles.get(game.screen, "弈 行"), 32, game.THEME.HEADING)
	if game.screen == "home": game.text_at(origin + Vector2(0, 32), "单命开局 · 移动抽牌 · 破将过关", 16, game.THEME.LIGHT)
	elif game.screen == "skill_selection":
		game.text_at(origin + Vector2(0, 28), "开局：0 张普通手牌 + 1 张临时免费移动牌", 16, game.THEME.LIGHT)
		game.text_at(origin + Vector2(0, 48), "帅走四向一步；马走马步，遵守蹩马腿", 16, game.THEME.LIGHT)
	elif game.screen == "debug_menu": game.text_at(origin + Vector2(0, 30), "先选奖励，再以完整初始状态入关", 16, game.THEME.LIGHT)
	elif game.screen == "tutorial_menu": game.text_at(origin + Vector2(0, 28), "预设练习；仅教学限制非目标操作", 16, game.THEME.LIGHT)
	elif game.screen == "tutorial_complete":
		var summary = game.tutorial.hint()
		game.text_at(origin + Vector2(0, 30), summary.substr(0, 26), 16, game.THEME.LIGHT)
		if summary.length() > 26: game.text_at(origin + Vector2(0, 50), summary.substr(26), 16, game.THEME.LIGHT)
	for i in entries().size():
		var rect = button_rect(i)
		var locked = game.screen == "skill_selection" and i == 1 and not game.skill_system.is_unlocked("horse")
		game.panel(rect, game.THEME.BOARD if locked else game.THEME.BUTTON, game.GOLD if i == 0 else game.THEME.BORDER)
		game.text_at(rect.position + Vector2(20, 35), entries()[i], 20, game.THEME.GRID if locked else game.THEME.INK)
	if game.screen == "skill_selection":
		var bottom = button_rect(2).end.y
		var footer = "解锁记录仅保存在当前浏览器；清除数据后会重置"
		if game.skill_system.horse_unlocked and game.skill_system.save_error != OK: footer = "马已在本次游玩中解锁；本地保存暂不可用"
		game.text_at(Vector2(24 if game.mobile_layout else 420, bottom + 28), footer, 14, game.THEME.LIGHT)

	game.text_at(Vector2(game.ui_size.x - 112, game.ui_size.y - 16), "游戏 " + game.BUILD_VERSION, 12, game.THEME.LIGHT.darkened(0.28))
