extends RefCounted
# Shared read-only inspection. No gameplay transaction is performed here.
const MOUSE_DELAY = 0.3
const TOUCH_DELAY = 0.4
const MOVE_LIMIT = 12.0
var game
var data: Dictionary = {}
var visible = false
var elapsed = 0.0
var pointer = -2
var start = Vector2.ZERO
var position = Vector2.ZERO
var source = ""
var context = []
var rows: Array[String] = []
var area = Rect2()
var font_size = 16
var consumed_hold = false
var sticky = false
var touch_moved = false
func _init(owner): game = owner
func allowed() -> bool:
	if game.card_picker.active or game.presentation.active() or game.encounter_info_open: return false
	if game.screen == "map": return game.route.travel_target < 0 and not game.route.deck_view
	return game.screen == "game" and game.phase in ["play", "discard"] and game.input_lock <= 0 and game.navigation_lock <= 0 and not game.gesture.active
func context_key() -> Array:
	return [game.screen, game.phase, game.turn, game.selected, game.free_selected, game.route.state.get("pending", -1), game.route.scroll_y, game.enemies.size(), game.ui_size, game.route.page]
func lookup(pos: Vector2) -> Dictionary:
	if not allowed(): return {}
	if game.screen == "map": return game.route.inspect_at(pos)
	return game.inspect_information(pos)
func clear():
	# Dismissing a fired hold never converts its outstanding release to an action.
	if consumed_hold:
		game.touch_dragged = true
		game.route.pointer_dragged = true
	var had_map_frame = data.has("node_id") and game.route.selected_node >= 0
	if data.has("node_id"): game.route.selected_node = -1
	var was_visible = visible
	data = {};visible = false;elapsed = 0;pointer = -2;source = "";rows = [];consumed_hold = false;sticky = false;touch_moved = false
	if was_visible or had_map_frame: game.queue_redraw()
func dismiss_map_drag():
	if not data.has("node_id"): return
	if consumed_hold:
		# Keep capture even after the visible hold is dismissed, including an
		# excursion out of the hit rectangle smaller than the drag threshold.
		visible = false;sticky = false;touch_moved = true
		game.touch_dragged = true;game.route.pointer_dragged = true;game.route.selected_node = -1;game.queue_redraw()
	else: clear()
func candidate(pos: Vector2, kind: String, id: int = -2):
	var found = lookup(pos)
	if found.is_empty(): clear();return
	if kind == "mouse" and source == "mouse" and found.get("key") == data.get("key") and pos.distance_to(start) < MOVE_LIMIT: return
	clear();data = found;position = pos;start = pos;source = kind;pointer = id;context = context_key()
	if data.has("node_id"):
		game.route.selected_node = data.node_id;game.queue_redraw()
func tick(delta: float):
	if data.is_empty(): return
	if not allowed() or context != context_key():
		var map_press = data.has("node_id") and pointer >= 0
		clear()
		if map_press: game.route.cancel_pointer(false, true)
		return
	if visible or touch_moved: return
	elapsed += delta
	if elapsed < (TOUCH_DELAY if source == "touch" else MOUSE_DELAY): return
	var fresh = lookup(position)
	if fresh.get("key") != data.get("key"): clear();return
	data = fresh;visible = true;consumed_hold = source == "touch";layout();game.queue_redraw()
func input_event(event) -> bool:
	if event is InputEventKey:
		if event.pressed and visible and event.keycode == KEY_ESCAPE: clear();return true
		if event.pressed: clear()
		return false
	if event is InputEventScreenTouch:
		if event.pressed:
			if game.screen == "map":
				game.touch_seen = true
				# Let the route tracker see every contact so it can block the
				# complete multi-touch sequence until all fingers have lifted.
				if game.route.touch_sequence_blocked or (game.route.pointer_id >= 0 and game.route.pointer_id != event.index):
					clear();return false
			if pointer == -2: candidate(event.position, "touch", event.index)
		elif event.index == pointer:
			var consume = consumed_hold and not event.canceled
			if data.has("node_id") and consumed_hold:
				var fresh = lookup(event.position)
				var keep = consume and not touch_moved and not game.route.pointer_dragged and event.position.distance_to(start) < MOVE_LIMIT and fresh.get("key") == data.get("key") and context == context_key()
				if keep:
					pointer = -2;consumed_hold = false;sticky = true
					game.route.finish_inspection(event.index, true)
					game.queue_redraw()
				else:
					clear();game.route.finish_inspection(event.index)
				return true
			clear()
			if consume:
				# Board inspection deliberately remains release-to-dismiss.
				game.cancel_gesture();game.route.cancel_pointer();return true
		return false
	if event is InputEventScreenDrag:
		if pointer == event.index:
			position = event.position
			if data.has("node_id"):
				if position.distance_to(start) >= MOVE_LIMIT or lookup(position).get("key") != data.get("key"): dismiss_map_drag()
			elif position.distance_to(start) >= MOVE_LIMIT:
				# Preserve the board's existing long-hold release capture.
				if consumed_hold:
					visible = false;game.touch_dragged = true;game.route.pointer_dragged = true;game.queue_redraw()
				else: clear()
		return false
	if event is InputEventMouse:
		if event.device == -1 and game.touch_seen: return false
		if game.screen == "map" and not game.route.touch_contacts.is_empty(): return false
		if event is InputEventMouseMotion:
			if event.button_mask != 0: clear()
			else: candidate(event.position, "mouse")
		elif event is InputEventMouseButton and event.pressed: clear()
	return false
func wrapped(value: String, width: float, size: int) -> Array[String]:
	var result: Array[String] = []
	var line = ""
	for ch in value:
		if ch == "\n": result.append(line);line = "";continue
		if not line.is_empty() and game.FONT.get_string_size(line + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			result.append(line);line = ""
		line += ch
	if not line.is_empty(): result.append(line)
	return result
func layout():
	var width = minf(390, game.ui_size.x - 24)
	var text = "\n".join(data.get("lines", []))
	font_size = 17
	rows = wrapped(text, width - 28, font_size)
	while rows.size() * (font_size + 4) + 54 > game.ui_size.y - 24 and font_size > 12:
		font_size -= 1;rows = wrapped(text, width - 28, font_size)
	var height = rows.size() * (font_size + 4) + 52
	var anchor: Rect2 = data.get("anchor", Rect2(position, Vector2.ONE))
	var x = clampf(anchor.get_center().x - width * 0.5, 12, game.ui_size.x - width - 12)
	var y = anchor.position.y - height - (28 if source == "touch" else 10)
	if y < 12:
		y = anchor.end.y + (54 if source == "touch" else 12)
		if y + height > game.ui_size.y - 12:
			y = clampf(position.y - height - 45, 12, game.ui_size.y - height - 12)
	area = Rect2(x, y, width, height)
func draw():
	if not visible: return
	var ink = game.route.INK if game.screen == "map" else game.THEME.INK
	game.panel(area, game.route.PAPER_LIGHT if game.screen == "map" else game.THEME.PAPER, game.route.MUTED if game.screen == "map" else game.GOLD)
	game.text_at(area.position + Vector2(14, 27), data.get("title", ""), 20, ink)
	for i in rows.size(): game.text_at(area.position + Vector2(14, 50 + i * (font_size + 4)), rows[i], font_size, ink)
