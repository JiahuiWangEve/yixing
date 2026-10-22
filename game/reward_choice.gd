extends RefCounted
const Palette = preload("res://palette.gd")



var game
var face
var mode = "choice"
var selected = -1
var page = 0

func _init(owner):
	game = owner;face = preload("res://card_face.gd").new(owner)

func reset():
	mode = "choice";selected = -1;page = 0

func choice_rect(i: int) -> Rect2:
	if not game.mobile_layout: return Rect2(350 + i * 300, 310, 280, 190)
	if game.compact_landscape: return Rect2(168 + i * 320, 170, 304, 174)
	return Rect2(24, 150 + i * 120, 432, 104)
func add_rect(i: int) -> Rect2:
	if game.rewards.size() > 3:
		if not game.mobile_layout: return Rect2(90 + i * 280, 310, 264, 300)
		if game.compact_landscape: return Rect2(24 + i * 232, 150, 216, 250)
		# All four remain visible. The same card-face renderer keeps readable
		# type without forcing a fourth card behind the fixed return button.
		var height = minf(280, (back_rect().position.y - 170) * 0.5)
		return Rect2(24 + (i % 2) * 224, 138 + (i / 2) * (height + 16), 208, height)
	# Preserve the existing three-candidate geometry, including tutorial taps.
	if not game.mobile_layout: return Rect2(220 + i * 285, 310, 260, 190)
	if game.compact_landscape: return Rect2(24 + i * 312, 150, 288, 180)
	var step = 130 if game.ui_size.y < 700 else 150
	return Rect2(24, 142 + i * step, 432, 122 if game.ui_size.y < 700 else 138)
func back_rect() -> Rect2:
	if mode == "add":
		if game.rewards.size() <= 3: return game.skip_reward_rect()
		if not game.mobile_layout: return Rect2(530, 660, 220, 50)
		if game.compact_landscape: return Rect2(370, 446, 220, 58)
		return Rect2(120, game.ui_size.y - 70, 240, 54)
	if not game.mobile_layout: return Rect2(320, 700, 210, 54)
	if game.compact_landscape: return Rect2(600, 446, 156, 58)
	return Rect2(24, game.ui_size.y - 70, 166, 54)
func confirm_rect() -> Rect2:
	if not game.mobile_layout: return Rect2(550, 700, 410, 54)
	if game.compact_landscape: return Rect2(772, 446, 164, 58)
	return Rect2(206, game.ui_size.y - 70, 250, 54)

func choice_hit_index(pos: Vector2) -> int:
	for i in 2:
		if choice_rect(i).has_point(pos): return i
	return -1
func add_hit_index(pos: Vector2) -> int:
	for i in game.rewards.size():
		if add_rect(i).has_point(pos): return i
	return -1

func click(pos: Vector2):
	if game.screen != "game" or game.phase != "reward" or game.input_lock > 0 or game.navigation_lock > 0: return
	if game.route.rewards_blocked():
		if confirm_rect().has_point(pos): game.choose_reward(-1)
		return
	if mode == "choice":
		match choice_hit_index(pos):
			0: mode = "add";selected = -1;page = 0
			1: game.choose_reward(-1)
	elif mode == "add":
		if back_rect().has_point(pos): reset()
		else:
			var index = add_hit_index(pos)
			if index >= 0: game.choose_reward(index)

	game.queue_redraw()

func title_position() -> Vector2:
	if not game.mobile_layout: return Vector2(220, 245)
	if game.compact_landscape: return Vector2(24, 112)
	return Vector2(24, 85)
func advances_chapter() -> bool:
	return game.route.active() and game.route.chapter() == 1 and game.route.state.pending >= 0 and game.route.state.nodes[game.route.state.pending].kind == "boss"
func title() -> String:
	if game.route.rewards_blocked(): return "破阵成功 · 本战收益抵消"
	if mode == "add": return "加牌 · 选择 1 张新牌"
	if game.debug_remaining > 0: return "预选奖励 %d / %d" % [game.debug_reward_total - game.debug_remaining + 1, game.debug_reward_total]
	return "第一章突破 · 结算后进军坚城" if advances_chapter() else "破阵成功 · 选择本关奖励"
func _button(rect: Rect2, label: String, enabled: bool = true, danger: bool = false):
	game.panel(rect, Palette.SURFACE if enabled else Palette.HAND, game.THEME.DANGER if danger and enabled else game.THEME.BORDER)
	var font_size = 18 if game.mobile_layout else 20
	while font_size > 14 and game.FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > rect.size.x - 24: font_size -= 1
	var width = game.FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	game.text_at(Vector2(rect.position.x + (rect.size.x - width) * 0.5, rect.position.y + (rect.size.y + font_size) * 0.5 - 3), label, font_size, Palette.INK if enabled else Palette.INK_SECONDARY)
func draw():
	game.draw_rect(Rect2(Vector2.ZERO, game.ui_size), Palette.PAPER)
	game.text_at(title_position(), title(), 24 if game.mobile_layout else 30, game.THEME.HEADING)
	if game.route.rewards_blocked():
		var pos = title_position() + Vector2(0, 50)
		game.wrapped_text("课后作业：本战不获得加牌等常规战后奖励。行军进度照常推进。", Rect2(pos, Vector2(game.ui_size.x - pos.x - 24, 110)), 18, game.THEME.LIGHT)
		game.wrapped_text(game.route.homework_summary(), Rect2(pos + Vector2(0, 130), Vector2(game.ui_size.x - pos.x - 24, 100)), 18, game.THEME.HEADING)
		_button(confirm_rect(), "进军第二章 · 坚城" if advances_chapter() else "返回山河图")
		return
	match mode:
		"choice": _draw_choice()
		"add": _draw_add()

func _draw_choice():
	game.text_at(title_position() + Vector2(0, 28 if game.mobile_layout else 32), "选择加牌或跳过；查看奖励牌后可返回", 16, game.THEME.LIGHT)
	var labels = ["加牌", "跳过"]
	var subtitles = ["从 %d 张奖励牌中选 1 张" % game.rewards.size(), "保持牌组，继续下一关"]
	if game.route.active(): subtitles[1] = "保持牌组，进军第二章" if advances_chapter() else "保持牌组，返回山河图"
	if game.debug_remaining > 0: subtitles[1] = "保持牌组，继续预选流程"
	for i in 2:
		var rect = choice_rect(i)
		game.panel(rect, Palette.SURFACE, game.GOLD)
		var portrait = game.mobile_layout and not game.compact_landscape
		game.text_at(rect.position + Vector2(20, 38 if portrait else 54), labels[i], 28, Palette.INK)
		game.text_at(rect.position + Vector2(20, 70 if portrait else 96), subtitles[i], 17, Palette.INK)
	var last = choice_rect(1)
	var footer_pos = Vector2(24, last.end.y + 34) if game.mobile_layout else Vector2(220, last.end.y + 42)
	game.text_at(footer_pos, "加牌或跳过会消耗本轮奖励；返回不消耗。", 15, game.THEME.LIGHT)

func _draw_add():
	game.text_at(title_position() + Vector2(0, 28 if game.mobile_layout else 32), "消耗牌：每张每关使用一次，下关恢复", 15, game.THEME.LIGHT)
	for i in game.rewards.size():
		var id: String = game.rewards[i]
		var rect = add_rect(i)
		var pos = rect.position
		if game.rewards.size() > 3:
			var transform = Transform2D(Vector2(rect.size.x / 156, 0), Vector2(0, rect.size.y / 156), pos)
			face.draw_data(game, game.descriptions.data(id), game.is_consumable(id), transform)
			continue
		game.panel(rect, game.THEME.PAPER, game.GOLD)
		game.text_at(pos + Vector2(20, 36 if game.mobile_layout else 45), game.CARDS[id][0], 26 if game.mobile_layout else 30, Palette.INK)
		game.text_at(pos + Vector2(20, 65 if game.mobile_layout else 80), "费用 %d" % game.CARDS[id][1], 19)
		if game.is_consumable(id):
			var tag = Rect2(pos + Vector2(rect.size.x - 68, 12), Vector2(54, 27))
			game.panel(tag, game.THEME.DANGER)
			game.text_at(tag.position + Vector2(9, 20), "消耗", 18, Palette.WHITE)
		game.wrapped_text(game.descriptions.data(id)[2], Rect2(pos + Vector2(20, 72 if game.mobile_layout else 96), Vector2(rect.size.x - 40, rect.size.y - (78 if game.mobile_layout else 102))), 16, game.INK)
	_button(back_rect(), "返回奖励选择")
