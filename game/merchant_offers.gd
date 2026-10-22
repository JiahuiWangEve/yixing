extends RefCounted
# Presentation only: the route owns fixed offers and the atomic exchange.
var game
var face
var scroll_y = 0.0
var node_id = -1
var run_seed = 0
var pointer = -2
var start = Vector2.ZERO
var last = Vector2.ZERO
var dragged = false
var scrolling = false

func _init(owner):
	game = owner;face = preload("res://card_face.gd").new(owner)
func active() -> bool:
	return game.screen == "route_choice" and game.route.choice_mode == "root" and game.route.state.get("pending", -1) >= 0 and game.route.state.nodes[game.route.state.pending].kind == "event" and game.route.state.nodes[game.route.state.pending].get("event_id", "") == "merchant"
func sync():
	if node_id != game.route.state.pending or run_seed != game.route.state.seed:
		node_id = game.route.state.pending;run_seed = game.route.state.seed;scroll_y = 0;pointer = -2
	scroll_y = clampf(scroll_y, 0, scroll_limit())
func area() -> Rect2: return Rect2(24, 140, game.ui_size.x - 48, game.ui_size.y - 224)
func columns() -> int: return 2 if game.mobile_layout and not game.compact_landscape else 3
func card_size() -> Vector2:
	var width = minf(288, (area().size.x - (columns() - 1) * 20) / columns())
	return Vector2(width, 270 if game.compact_landscape else maxf(270, width * 1.15))
func card_rect(index: int) -> Rect2:
	var size = card_size();var total = columns() * size.x + (columns() - 1) * 20
	return Rect2(Vector2((game.ui_size.x - total) * 0.5 + (index % columns()) * (size.x + 20), area().position.y + (index / columns()) * (size.y + 20) - scroll_y), size)
func scroll_limit() -> float:
	var count = game.route.state.nodes[game.route.state.pending].offers.size()
	return maxf(0, ceili(float(count) / columns()) * (card_size().y + 20) - 20 - area().size.y)
func leave_rect() -> Rect2: return Rect2((game.ui_size.x - 220) * 0.5, game.ui_size.y - 64, 220, 48)
func click(pos: Vector2):
	if not active(): return
	sync()
	if leave_rect().has_point(pos):
		game.route.resolve(game.route.choices.size() - 1);return
	if not area().has_point(pos) or game.collection.is_empty(): return
	for index in game.route.state.nodes[game.route.state.pending].offers.size():
		if card_rect(index).has_point(pos): game.route.resolve(index);return
func press(pos: Vector2, id: int):
	if pointer != -2: return
	pointer = id;start = pos;last = pos;dragged = false;scrolling = area().has_point(pos)
func motion(pos: Vector2, id: int):
	if pointer != id: return
	if pos.distance_to(start) >= 12: dragged = true
	if dragged and scrolling: scroll_y = clampf(scroll_y - (pos.y - last.y), 0, scroll_limit());game.queue_redraw()
	last = pos
func release(pos: Vector2, id: int, canceled: bool = false):
	if pointer != id: return
	var tap = not canceled and not dragged and pos.distance_to(start) < 12
	pointer = -2
	if tap: click(pos)
func cancel_pointer(): pointer = -2;dragged = false
func input_event(event) -> bool:
	if not active(): return false
	sync()
	if event is InputEventKey: return true # No battle shortcuts through offers.
	if event is InputEventScreenTouch:
		game.touch_seen = true
		if event.pressed: press(event.position, event.index)
		else: release(event.position, event.index, event.canceled)
	elif event is InputEventScreenDrag: motion(event.position, event.index)
	elif event is InputEventMouse:
		if event.device == -1 and game.touch_seen: return true
		if event is InputEventMouseMotion: motion(event.position, -1)
		elif event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed: press(event.position, -1)
				else: release(event.position, -1)
			elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and area().has_point(event.position):
				scroll_y = clampf(scroll_y + (100 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -100), 0, scroll_limit());game.queue_redraw()
	return true
func draw():
	sync()
	game.draw_rect(Rect2(Vector2.ZERO, game.ui_size), game.THEME.BACKGROUND)
	var offers = game.route.state.nodes[game.route.state.pending].offers
	for i in offers.size():
		var rect = card_rect(i)
		if not rect.intersects(area()): continue
		var id: String = offers[i]
		var transform = Transform2D(Vector2(rect.size.x / 156, 0), Vector2(0, rect.size.y / 156), rect.position)
		face.draw_data(game, game.CARDS[id], game.is_consumable(id), transform)
	# Fixed masks keep cards behind the rules and the always-reachable leave button.
	game.draw_rect(Rect2(0, 0, game.ui_size.x, area().position.y), game.THEME.BACKGROUND)
	game.draw_rect(Rect2(0, area().end.y, game.ui_size.x, game.ui_size.y - area().end.y), game.THEME.BACKGROUND)
	game.text_at(Vector2(24, 42), "行商 · 以牌换牌", 26, game.THEME.HEADING)
	game.wrapped_text("选择一张想要的牌，再交出一张永久牌。交换后牌组总张数不变。", Rect2(24, 62, game.ui_size.x - 48, 70), 18, game.THEME.LIGHT)
	if game.collection.is_empty(): game.text_at(Vector2(24, 128), "牌组为空，暂无可交换的牌。", 17, game.THEME.HEADING)
	game.rewardui._button(leave_rect(), "离开")
	if scroll_limit() > 0:
		var height = maxf(24, area().size.y * area().size.y / (area().size.y + scroll_limit()))
		game.draw_rect(Rect2(area().end.x + 7, area().position.y + (area().size.y - height) * scroll_y / scroll_limit(), 3, height), game.GOLD)
