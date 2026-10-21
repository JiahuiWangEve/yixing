extends RefCounted



var game
var mode = "choice"
var selected = -1
var page = 0

func _init(owner): game = owner

func reset():
	mode = "choice";selected = -1;page = 0

func rows_per_page() -> int: return 4 if game.mobile_layout else 5
func page_count() -> int: return maxi(1, ceili(float(game.collection.size()) / rows_per_page()))
func visible_indices() -> Array:
	var result: Array = []
	var first = clampi(page, 0, page_count() - 1) * rows_per_page()
	for i in range(first, mini(first + rows_per_page(), game.collection.size())): result.append(i)
	return result


func choice_rect(i: int) -> Rect2:
	if not game.mobile_layout: return Rect2(220 + i * 285, 310, 260, 190)
	if game.compact_landscape: return Rect2(24 + i * 312, 170, 288, 174)
	return Rect2(24, 150 + i * 120, 432, 104)
func add_rect(i: int) -> Rect2:
	if game.mobile_layout and not game.compact_landscape:
		var step = 130 if game.ui_size.y < 700 else 150
		return Rect2(24, 142 + i * step, 432, 122 if game.ui_size.y < 700 else 138)
	return game.reward_rect(i)
func back_rect() -> Rect2:
	if mode == "add": return game.skip_reward_rect()
	if not game.mobile_layout: return Rect2(320, 700, 210, 54)
	if game.compact_landscape: return Rect2(600, 446, 156, 58)
	return Rect2(24, game.ui_size.y - 70, 166, 54)
func confirm_rect() -> Rect2:
	if not game.mobile_layout: return Rect2(550, 700, 410, 54)
	if game.compact_landscape: return Rect2(772, 446, 164, 58)
	return Rect2(206, game.ui_size.y - 70, 250, 54)

func row_rect(row: int) -> Rect2:
	if not game.mobile_layout: return Rect2(320, 236 + row * 72, 640, 62)
	if game.compact_landscape: return Rect2(24, 154 + row * 78, 552, 68)
	return Rect2(24, 145 + row * 70, 432, 62)
func prev_rect() -> Rect2:
	if not game.mobile_layout: return Rect2(320, 610, 160, 48)
	if game.compact_landscape: return Rect2(600, 356, 156, 54)
	return Rect2(24, 435, 130, 48)
func next_rect() -> Rect2:
	if not game.mobile_layout: return Rect2(800, 610, 160, 48)
	if game.compact_landscape: return Rect2(780, 356, 156, 54)
	return Rect2(326, 435, 130, 48)
func row_hit_index(pos: Vector2) -> int:
	var indices = visible_indices()
	for row in indices.size():
		if row_rect(row).has_point(pos): return indices[row]
	return -1
func choice_hit_index(pos: Vector2) -> int:
	for i in 3:
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
			1:
				if not game.collection.is_empty(): mode = "remove";selected = -1;page = 0
			2: game.choose_reward(-1)
	elif mode == "add":
		if back_rect().has_point(pos): reset()
		else:
			var index = add_hit_index(pos)
			if index >= 0: game.choose_reward(index)
	elif mode == "remove":
		if back_rect().has_point(pos): reset()
		elif confirm_rect().has_point(pos):
			if selected >= 0 and selected < game.collection.size(): game.delete_reward(selected)
		elif prev_rect().has_point(pos):
			if page > 0: page -= 1;selected = -1
		elif next_rect().has_point(pos):
			if page < page_count() - 1: page += 1;selected = -1
		else:
			var index = row_hit_index(pos)
			if index >= 0: selected = index
	game.queue_redraw()

func title_position() -> Vector2:
	if not game.mobile_layout: return Vector2(320, 185) if mode == "remove" else Vector2(220, 245)
	if game.compact_landscape: return Vector2(24, 112)
	return Vector2(24, 85)
func advances_chapter() -> bool:
	return game.route.active() and game.route.chapter() == 1 and game.route.state.pending >= 0 and game.route.state.nodes[game.route.state.pending].kind == "boss"
func title() -> String:
	if game.route.rewards_blocked(): return "破阵成功 · 本战收益抵消"
	if mode == "add": return "加牌 · 选择 1 张新牌"
	if mode == "remove": return "删牌 · 永久移除 1 张"
	if game.debug_remaining > 0: return "预选奖励 %d / %d" % [game.debug_reward_total - game.debug_remaining + 1, game.debug_reward_total]
	return "第一章突破 · 结算后进军坚城" if advances_chapter() else "破阵成功 · 选择本关奖励"
func _button(rect: Rect2, label: String, enabled: bool = true, danger: bool = false):
	game.panel(rect, game.THEME.BUTTON if enabled else game.THEME.BOARD, game.THEME.DANGER if danger and enabled else game.THEME.BORDER)
	var font_size = 18 if game.mobile_layout else 20
	while font_size > 14 and game.FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > rect.size.x - 24: font_size -= 1
	var width = game.FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	game.text_at(Vector2(rect.position.x + (rect.size.x - width) * 0.5, rect.position.y + (rect.size.y + font_size) * 0.5 - 3), label, font_size, game.THEME.INK if enabled else game.THEME.GRID)
func _count(id: String) -> int:
	var count = 0
	for card in game.collection:
		if card == id: count += 1
	return count

func draw():
	game.draw_rect(Rect2(Vector2.ZERO, game.ui_size), game.THEME.OVERLAY)
	game.text_at(title_position(), title(), 24 if game.mobile_layout else 30, game.THEME.HEADING)
	if game.route.rewards_blocked():
		var pos = title_position() + Vector2(0, 50)
		game.wrapped_text("课后作业：本战不获得加牌、删牌等常规战后奖励。行军进度照常推进。", Rect2(pos, Vector2(game.ui_size.x - pos.x - 24, 110)), 18, game.THEME.LIGHT)
		game.wrapped_text(game.route.homework_summary(), Rect2(pos + Vector2(0, 130), Vector2(game.ui_size.x - pos.x - 24, 100)), 18, game.THEME.HEADING)
		_button(confirm_rect(), "进军第二章 · 坚城" if advances_chapter() else "返回山河图")
		return
	match mode:
		"choice": _draw_choice()
		"add": _draw_add()
		"remove": _draw_remove()

func _draw_choice():
	var intro = "本轮三选一；查看加牌或删牌后可返回"
	game.text_at(title_position() + Vector2(0, 28 if game.mobile_layout else 32), intro, 16, game.THEME.LIGHT)
	var labels = ["加牌", "删牌", "跳过"]
	var subtitles = ["从 3 张奖励牌中选 1 张", "从整副牌组中永久删 1 张", "保持牌组，继续下一关"]
	if game.route.active(): subtitles[2] = "保持牌组，进军第二章" if advances_chapter() else "保持牌组，返回山河图"
	if game.debug_remaining > 0: subtitles[2] = "保持牌组，继续预选流程"
	if game.collection.is_empty(): subtitles[1] = "牌组为空，暂无可删牌"
	for i in 3:
		var rect = choice_rect(i)
		var enabled = i != 1 or not game.collection.is_empty()
		game.panel(rect, game.THEME.PAPER if enabled else game.THEME.BOARD, game.GOLD if enabled else game.THEME.BORDER)
		var portrait = game.mobile_layout and not game.compact_landscape
		game.text_at(rect.position + Vector2(20, 38 if portrait else 54), labels[i], 28, game.GOLD if enabled else game.THEME.GRID)
		game.text_at(rect.position + Vector2(20, 70 if portrait else 96), subtitles[i], 17, game.INK if enabled else game.THEME.GRID)
		if i == 1:
			game.text_at(rect.position + Vector2(20, 91 if portrait else 128), "当前牌组：%d 张" % game.collection.size(), 14, game.THEME.GRID)
	var footer = "三种选择都会消耗本轮奖励；返回不消耗。"
	var last = choice_rect(2)
	var footer_pos = Vector2(24, last.end.y + 34) if game.mobile_layout else Vector2(220, last.end.y + 42)
	game.text_at(footer_pos, footer, 15, game.THEME.LIGHT)

func _draw_add():
	game.text_at(title_position() + Vector2(0, 28 if game.mobile_layout else 32), "消耗牌：每张每关使用一次，下关恢复", 15, game.THEME.LIGHT)
	for i in game.rewards.size():
		var id: String = game.rewards[i]
		var rect = add_rect(i)
		var pos = rect.position
		game.panel(rect, game.THEME.PAPER, game.GOLD)
		game.text_at(pos + Vector2(20, 36 if game.mobile_layout else 45), game.CARDS[id][0], 26 if game.mobile_layout else 30, game.GOLD)
		game.text_at(pos + Vector2(20, 65 if game.mobile_layout else 80), "费用 %d" % game.CARDS[id][1], 19)
		if game.is_consumable(id):
			var tag = Rect2(pos + Vector2(rect.size.x - 68, 12), Vector2(54, 27))
			game.panel(tag, game.THEME.DANGER)
			game.text_at(tag.position + Vector2(9, 20), "消耗", 18, game.THEME.LIGHT)
		game.wrapped_text(game.CARDS[id][2], Rect2(pos + Vector2(20, 72 if game.mobile_layout else 96), Vector2(rect.size.x - 40, rect.size.y - (78 if game.mobile_layout else 102))), 16, game.INK)
	_button(back_rect(), "返回奖励选择")

func _draw_remove():
	page = clampi(page, 0, page_count() - 1)
	var caption = "当前牌组 %d 张 · 每行代表 1 张副本" % game.collection.size()
	game.text_at(title_position() + Vector2(0, 28), caption, 16, game.THEME.LIGHT)
	var indices = visible_indices()
	for row in indices.size():
		var index: int = indices[row]
		var id: String = game.collection[index]
		var rect = row_rect(row)
		var active = index == selected
		game.panel(rect, game.THEME.PAPER_SELECTED if active else game.THEME.PAPER, game.THEME.DANGER if active else game.THEME.BORDER)
		var name: String = game.CARDS[id][0]
		if game.is_consumable(id): name += " · 消耗"
		game.text_at(rect.position + Vector2(16, 27), name + ("  ✓" if active else ""), 21, game.INK)
		game.text_at(rect.position + Vector2(rect.size.x - 166, 27), "费用 %d · 共 %d 张" % [game.CARDS[id][1], _count(id)], 15, game.THEME.GRID)
		game.wrapped_text(game.CARDS[id][2], Rect2(rect.position + Vector2(16, 34), Vector2(rect.size.x - 32, 26)), 14, game.THEME.GRID)
	if indices.is_empty():
		var empty_rect = Rect2(row_rect(0).position, row_rect(0).size + Vector2(0, 80))
		game.panel(empty_rect, game.THEME.PAPER, game.THEME.BORDER)
		game.text_at(empty_rect.position + Vector2(18, 40), "牌组已空，没有可删除的普通牌。", 19, game.INK)
		game.text_at(empty_rect.position + Vector2(18, 75), "返回后可以加牌，或跳过本轮奖励。", 17, game.THEME.GRID)
	_button(prev_rect(), "上一页", page > 0)
	_button(next_rect(), "下一页", page < page_count() - 1)
	var page_label = "%d / %d" % [page + 1, page_count()]
	var page_pos = Vector2(615, 641)
	if game.compact_landscape: page_pos = Vector2(740, 430)
	elif game.mobile_layout: page_pos = Vector2(215, 466)
	game.text_at(page_pos, page_label, 18, game.THEME.LIGHT)
	var detail_rect = Rect2(320, 668, 640, 26)
	if game.compact_landscape: detail_rect = Rect2(600, 166, 336, 165)
	elif game.mobile_layout: detail_rect = Rect2(24, 499, 432, maxf(52, game.ui_size.y - 584))
	var valid = selected >= 0 and selected < game.collection.size()
	var confirm_label = "先选择一张牌"
	if valid:
		var name: String = game.CARDS[game.collection[selected]][0]
		confirm_label = "确认删除「%s」×1" % name
		if game.compact_landscape: confirm_label = "删除「%s」×1" % name
		game.wrapped_text("将永久移除「%s」1 张；只影响本局，下一关不再加入。" % name, detail_rect, 16, game.THEME.HEADING)
	else:
		game.wrapped_text("点选一张普通牌，再确认删除；可以删至空牌组。", detail_rect, 16, game.THEME.LIGHT)
	_button(back_rect(), "返回", true)
	_button(confirm_rect(), confirm_label, valid, true)
