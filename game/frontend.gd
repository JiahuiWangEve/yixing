extends RefCounted
const LESSON_NAMES = ["移动与抽牌", "攻击与能量", "移动牌与留牌", "危险与行动顺序", "破将、奖励与增援"]
var game
func _init(owner): game = owner
func entries() -> Array:
	match game.screen:
		"home": return ["开始游戏", "教程", "声音：" + ("静音" if game.audio_system.muted else "开启"), "继续山河棋路存档"]
		"skill_selection": return ["将 · 四向一步", "马 · 马步移动" if game.skill_system.is_unlocked("horse") else "马 · 通关后解锁", "炮车 · 行军与驻扎" if game.skill_system.is_unlocked("artillery") else "炮车 · 通关后解锁", "返回首页"]
		"debug_profile": return ["将 · 2命与恢复", "马 · 1命与机动", "炮车 · 1命与炮击", "返回首页"]
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
				2: game.audio_system.toggle_mute()
				3:
					if not game.route.resume(): game.notice = "此存档不可续用，请开始新征途。"
		"skill_selection":
			match i:
				0: game.skill_system.choose("king")
				1: game.skill_system.choose("horse")
				2: game.skill_system.choose("artillery")
				3: game.show_home()
		"debug_profile":
			if i < 3:
				game.player_skill = ["king", "horse", "artillery"][i]
				game.screen = "debug_menu"
			else: game.show_home()
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
	var titles = {"home": "弈 行", "skill_selection": "选择开局", "debug_profile": "调试 · 选择开局", "tutorial_menu": "教程 · 选择小节", "debug_menu": "调试选关", "tutorial_pause": "教学菜单", "tutorial_complete": "本节完成"}
	var origin = (Vector2(24, 60) if game.compact_landscape else Vector2(24, 90)) if game.mobile_layout else Vector2(420, 100)
	game.text_at(origin, titles.get(game.screen, "弈 行"), 32, game.THEME.HEADING)
	if game.screen == "home":
		game.text_at(origin + Vector2(0, 32), "山河棋路 · 三种开局 · 八步破关", 16, game.THEME.LIGHT)
		if game.notice in ["暂无可继续的章节", "此存档不可续用，请开始新征途。"]: game.text_at(Vector2(24, game.ui_size.y - 48), game.notice, 16, game.THEME.HEADING)
	elif game.screen == "skill_selection":
		game.text_at(origin + Vector2(0, 28), "各有 8 张初始牌；移动抽牌，回合保留手牌", 16, game.THEME.LIGHT)
		game.text_at(origin + Vector2(0, 48), "消耗：每张每关使用一次，下关恢复", 16, game.THEME.LIGHT)
	elif game.screen == "debug_profile":
		game.text_at(origin + Vector2(0, 28), "调试可直接选择全部开局", 16, game.THEME.LIGHT)
	elif game.screen == "debug_menu":
		var profile_name = {"king": "将", "horse": "马", "artillery": "炮车"}.get(game.player_skill, "将")
		game.text_at(origin + Vector2(0, 30), profile_name + " · 先选专属奖励，再入关", 16, game.THEME.LIGHT)
	elif game.screen == "tutorial_menu": game.text_at(origin + Vector2(0, 28), "预设练习；仅教学限制非目标操作", 16, game.THEME.LIGHT)
	elif game.screen == "tutorial_complete":
		var summary = game.tutorial.hint()
		game.text_at(origin + Vector2(0, 30), summary.substr(0, 26), 16, game.THEME.LIGHT)
		if summary.length() > 26: game.text_at(origin + Vector2(0, 50), summary.substr(26), 16, game.THEME.LIGHT)
	for i in entries().size():
		var rect = button_rect(i)
		var locked = game.screen == "skill_selection" and i in [1, 2] and not game.skill_system.is_unlocked("horse" if i == 1 else "artillery")
		game.panel(rect, game.THEME.BOARD if locked else game.THEME.BUTTON, game.GOLD if i == 0 else game.THEME.BORDER)
		var profile_entry = game.screen in ["skill_selection", "debug_profile"] and i < 3
		game.text_at(rect.position + Vector2(20, 26 if profile_entry else 35), entries()[i], 20, game.THEME.GRID if locked else game.THEME.INK)
		if profile_entry:
			var summaries = ["2 命 · 恢复与近战 · 奖励含续命、吐纳", "1 命 · 马步与进退攻击 · 击杀切入", "1 命 · 行军走 1–2 格 · 展开抽 3 张"]
			game.text_at(rect.position + Vector2(20, 47), summaries[i], 14, game.THEME.GRID if locked else game.THEME.SAFE)
	if game.screen == "skill_selection":
		var bottom = button_rect(3).end.y
		var footer = "解锁记录仅保存在当前浏览器；清除数据后会重置"
		if game.skill_system.horse_unlocked and game.skill_system.save_error != OK: footer = "马与炮车已解锁；本地保存暂不可用"
		game.text_at(Vector2(24 if game.mobile_layout else 420, bottom + 28), footer, 14, game.THEME.LIGHT)

	if game.screen in ["skill_selection", "debug_profile"]:
		var help_y = button_rect(3).end.y + (52 if game.screen == "skill_selection" else 28)
		var help_x = 24 if game.mobile_layout else 420
		game.text_at(Vector2(help_x, help_y), "炮车：展开抽3张；攻击走1格，行军走1～2格", 14, game.THEME.LIGHT)
		game.text_at(Vector2(help_x, help_y + 22), "炮击须隔恰好一子；木桩也可被敌炮利用", 14, game.THEME.LIGHT)

	game.text_at(Vector2(game.ui_size.x - 112, game.ui_size.y - 16), "游戏 " + game.BUILD_VERSION, 12, game.THEME.LIGHT.darkened(0.28))
