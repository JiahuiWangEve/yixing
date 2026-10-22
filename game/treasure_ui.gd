extends RefCounted
# Presentation and input capture only. Route owns the saved choice/claim; the
# treasure system owns rules and counters. Reading/drawing never grants effects.
const Palette = preload("res://palette.gd")
const TREASURES = preload("res://treasure_system.gd")
const ICONS = {
	"longevity_seal": preload("res://assets/treasures/longevity_seal.png"),
	"life_talisman": preload("res://assets/treasures/life_talisman.png"),
	"tiger_tally": preload("res://assets/treasures/tiger_tally.png"),
	"wind_horseshoe": preload("res://assets/treasures/wind_horseshoe.png"),
	"battle_tassel": preload("res://assets/treasures/battle_tassel.png"),
	"spring_bit": preload("res://assets/treasures/spring_bit.png"),
	"gate_cannon_seal": preload("res://assets/treasures/gate_cannon_seal.png"),
	"roving_axle": preload("res://assets/treasures/roving_axle.png"),
	"chain_fire_fuse": preload("res://assets/treasures/chain_fire_fuse.png")
}
const MOVE_LIMIT = 12.0
const GAP = 20.0
var game
var scroll_y = 0.0
var source_context: Array = []
var layout_size = Vector2.ZERO
var pointer = -2
var pointer_start = Vector2.ZERO
var pointer_last = Vector2.ZERO
var pressed_id = ""
var dragged = false
var scrolling = false
var claimed = false
var touch_contacts: Dictionary = {}
var touch_blocked = false
var feedback = ""
var feedback_label = ""
var feedback_elapsed = 0.0
var feedback_id = ""
var feedback_stage = -1

func _init(owner): game = owner
func active() -> bool: return game.screen == "treasure_choice"
func choice_ids() -> Array:
	# Never synthesize or reroll choices in the view, including on reload/resize.
	var saved = game.route.state.get("treasure_choices", [])
	if not saved is Array or saved.size() != 3: return []
	var unique: Dictionary = {}
	for id in saved:
		if not id is String or not TREASURES.DATA.has(id) or unique.has(id): return []
		if TREASURES.DATA[id].role != game.player_skill: return []
		unique[id] = true
	return saved.duplicate()
func choice_context() -> Array:
	return [game.route.state.get("seed", 0), game.route.state.get("pending", -1), choice_ids()]
func sync():
	if not active(): return
	var current = choice_context()
	if current != source_context:
		source_context = current;scroll_y = 0;claimed = false;cancel_pointer()
	if layout_size != game.ui_size:
		layout_size = game.ui_size;cancel_pointer()
	scroll_y = clampf(scroll_y, 0, scroll_limit())
func portrait() -> bool: return game.mobile_layout and not game.compact_landscape
func area() -> Rect2:
	return Rect2(24, 132, game.ui_size.x - 48, maxf(120, game.ui_size.y - 214))
func columns() -> int: return 1 if portrait() else 3
func card_size() -> Vector2:
	var width = minf(316, (area().size.x - (columns() - 1) * GAP) / columns())
	if portrait(): width = area().size.x
	var text_width = width - (148 if portrait() else 40)
	var max_lines = 0
	for id in choice_ids():
		max_lines = maxi(max_lines, wrapped(TREASURES.DATA[id].get("summary", TREASURES.DATA[id].description), text_width, 18).size())
	var height = maxf(168, 74 + max_lines * 24) if portrait() else maxf(322, 196 + max_lines * 24)
	return Vector2(width, height)
func card_rect(index: int) -> Rect2:
	var dimensions = card_size()
	var row_width = columns() * dimensions.x + (columns() - 1) * GAP
	var y = area().position.y + (index / columns()) * (dimensions.y + GAP) - scroll_y
	if columns() == 3 and scroll_limit() <= 0: y += maxf(0, (area().size.y - dimensions.y) * 0.32)
	return Rect2((game.ui_size.x - row_width) * 0.5 + (index % columns()) * (dimensions.x + GAP), y, dimensions.x, dimensions.y)
func scroll_limit() -> float:
	var rows = ceili(float(choice_ids().size()) / columns())
	return maxf(0, rows * (card_size().y + GAP) - GAP - area().size.y)
func choice_at(pos: Vector2) -> String:
	if not area().has_point(pos): return ""
	var ids = choice_ids()
	for index in ids.size():
		if card_rect(index).has_point(pos): return ids[index]
	return ""
func interactive() -> bool:
	return active() and not claimed and not game.card_picker.active and not game.presentation.active() and not game.encounter_info_open and game.input_lock <= 0 and game.navigation_lock <= 0
func cancel_pointer(keep_touches: bool = false):
	pointer = -2;pressed_id = "";dragged = false;scrolling = false
	if not keep_touches: touch_contacts.clear();touch_blocked = false
func press(pos: Vector2, id: int):
	if not interactive() or pointer != -2: return
	pointer = id;pointer_start = pos;pointer_last = pos;dragged = false
	pressed_id = choice_at(pos);scrolling = area().has_point(pos)
func motion(pos: Vector2, id: int):
	if pointer != id: return
	if pos.distance_to(pointer_start) >= MOVE_LIMIT: dragged = true
	# Leaving the pressed card, even briefly and by less than the threshold,
	# permanently cancels that claim. Scroll gestures never turn into taps.
	if not pressed_id.is_empty() and choice_at(pos) != pressed_id: dragged = true
	if dragged and scrolling:
		scroll_y = clampf(scroll_y - (pos.y - pointer_last.y), 0, scroll_limit());game.queue_redraw()
	pointer_last = pos
func release(pos: Vector2, id: int, canceled: bool = false):
	if pointer != id: return
	var chosen = pressed_id
	var valid = not canceled and not dragged and not chosen.is_empty() and pos.distance_to(pointer_start) < MOVE_LIMIT and choice_at(pos) == chosen
	cancel_pointer(true)
	if not valid or not interactive() or source_context != choice_context(): return
	# Latch before the route transaction. Repeated clicks/releases cannot claim
	# twice, and a release cannot fall through into the new chapter's map.
	claimed = true
	game.route.choose_treasure(chosen)
	game.queue_redraw()
func input_event(event) -> bool:
	if not active(): return false
	sync()
	if event is InputEventKey: return true # Includes 1–7, Space, Enter and Escape.
	if event is InputEventScreenTouch:
		game.touch_seen = true
		if event.pressed:
			touch_contacts[event.index] = true
			if touch_blocked or touch_contacts.size() > 1:
				cancel_pointer(true);touch_blocked = true
			else: press(event.position, event.index)
		else:
			touch_contacts.erase(event.index)
			if touch_blocked:
				if touch_contacts.is_empty(): touch_blocked = false
			else: release(event.position, event.index, event.canceled)
	elif event is InputEventScreenDrag:
		if not touch_blocked: motion(event.position, event.index)
	elif event is InputEventMouse:
		if (event.device == -1 and game.touch_seen) or not touch_contacts.is_empty(): return true
		if event is InputEventMouseMotion: motion(event.position, -1)
		elif event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed: press(event.position, -1)
				else: release(event.position, -1)
			elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and area().has_point(event.position):
				cancel_pointer();scroll_y = clampf(scroll_y + (100 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -100), 0, scroll_limit());game.queue_redraw()
	return true
func icon_rect() -> Rect2:
	if game.screen == "map":
		if game.compact_landscape: return Rect2(744, 14, 48, 48)
		if game.mobile_layout: return Rect2(game.ui_size.x - 68, 62, 48, 48)
		return Rect2(760, 12, 48, 48)
	if game.compact_landscape: return Rect2(832, 12, 48, 48)
	if game.mobile_layout: return Rect2(244, 12, 48, 48)
	return Rect2(24, 78, 48, 48)
func hud_visible() -> bool:
	if game.card_picker.active or game.encounter_info_open: return false
	if game.screen == "map": return not game.route.deck_view
	return game.screen == "game" and game.phase in ["play", "discard"]
func inspection_context() -> Array:
	var id: String = game.treasures.active_id()
	if game.screen != "game": return [id]
	return [id, game.treasure_battle.duplicate(true), game.active_displacements, game.artillery_mode, game.lives]
func inspect_at(pos: Vector2) -> Dictionary:
	if not hud_visible() or game.presentation.active() or not icon_rect().has_point(pos): return {}
	var id: String = game.treasures.active_id()
	if id.is_empty() or not ICONS.has(id): return {}
	var lines: Array = [TREASURES.DATA[id].description]
	if game.screen == "game": lines = game.treasures.status().get("lines", lines).duplicate()
	# Map never reads battle status, even if the prior battle's counters remain.
	return {"key": "treasure:" + id, "treasure_id": id, "title": TREASURES.DATA[id].name, "lines": lines, "anchor": icon_rect()}
func trigger(kind: String, label: String = ""):
	# Exact gameplay events call this; inspecting, restoring and undoing do not.
	feedback = kind;feedback_label = label;feedback_elapsed = 0
	feedback_id = game.treasures.active_id();feedback_stage = game.stage
	game.queue_redraw()
func tick(delta: float):
	if active(): sync()
	elif pointer != -2 or not source_context.is_empty():
		cancel_pointer();source_context = [];claimed = false
	if feedback.is_empty(): return
	feedback_elapsed += maxf(0, delta)
	if feedback_elapsed >= 0.72 or game.screen != "game" or feedback_stage != game.stage or feedback_id != game.treasures.active_id(): feedback = ""
	game.queue_redraw()
func wrapped(value: String, width: float, size: int) -> Array[String]:
	var result: Array[String] = [];var line = ""
	for ch in value:
		if ch == "\n": result.append(line);line = "";continue
		if not line.is_empty() and game.FONT.get_string_size(line + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			result.append(line);line = ""
		line += ch
	if not line.is_empty(): result.append(line)
	return result
func centered(point: Vector2, value: String, size: int, color: Color):
	var width = game.FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	game.text_at(point - Vector2(width * 0.5, 0), value, size, color)
func draw_card(id: String, rect: Rect2):
	var selected = pointer != -2 and not dragged and pressed_id == id
	game.panel(Rect2(rect.position + Vector2(2, 3), rect.size), Color(Palette.INK, 0.12))
	game.panel(rect, Palette.HAND if selected else Palette.SURFACE, Palette.ACCENT if selected else Palette.BORDER)
	game.draw_rect(rect.grow(-6), Color(Palette.BORDER, 0.35), false, 1)
	var icon = Rect2(rect.position + Vector2(18, (rect.size.y - 96) * 0.5), Vector2(96, 96)) if portrait() else Rect2(rect.position + Vector2((rect.size.x - 104) * 0.5, 20), Vector2(104, 104))
	game.draw_texture_rect(ICONS[id], icon, false)
	var text_origin = rect.position + Vector2(130, 38) if portrait() else rect.position + Vector2(20, 160)
	if portrait(): game.text_at(text_origin, TREASURES.DATA[id].name, 24, Palette.INK)
	else: centered(Vector2(rect.get_center().x, text_origin.y), TREASURES.DATA[id].name, 27, Palette.INK)
	var rows = wrapped(TREASURES.DATA[id].get("summary", TREASURES.DATA[id].description), rect.size.x - (148 if portrait() else 40), 18)
	for index in rows.size(): game.text_at(text_origin + Vector2(0, 34 + index * 24), rows[index], 18, Palette.INK)
func draw_choice():
	game.draw_rect(Rect2(Vector2.ZERO, game.ui_size), Palette.PAPER)
	var ids = choice_ids()
	for index in ids.size():
		var rect = card_rect(index)
		if rect.intersects(area()): draw_card(ids[index], rect)
	# Fixed masks preserve the header/footer while the three saved choices scroll.
	game.draw_rect(Rect2(0, 0, game.ui_size.x, area().position.y), Palette.PAPER)
	game.draw_rect(Rect2(0, area().end.y, game.ui_size.x, game.ui_size.y - area().end.y), Palette.PAPER)
	game.text_at(Vector2(24, 48), "第一章突破 · 选择宝物", 28, Palette.INK)
	game.text_at(Vector2(24, 83), "选择一件宝物，带入第二章。", 18, Palette.INK_SECONDARY)
	if ids.is_empty():
		game.wrapped_text("宝物待选记录异常，无法领取。请重新载入本局。", area().grow(-20), 20, Palette.INK_SECONDARY)
	if scroll_limit() > 0:
		var height = maxf(28, area().size.y * area().size.y / (area().size.y + scroll_limit()))
		game.draw_rect(Rect2(area().end.x + 8, area().position.y + (area().size.y - height) * scroll_y / scroll_limit(), 3, height), Palette.INK)
func draw_feedback():
	if feedback.is_empty() or game.screen != "game": return
	var t = clampf(feedback_elapsed / 0.72, 0, 1)
	var alpha = sin(t * PI)
	var center = icon_rect().get_center()
	game.draw_arc(center, 27 + t * 9, 0, TAU, 32, Color(Palette.ACCENT, alpha), 2.5, true)
	if not feedback_label.is_empty():
		game.text_at(center + Vector2(28, 5 - t * 22), feedback_label, 20, Color(Palette.INK, 1 - t))
	if feedback == "revive":
		var pos: Vector2 = game.player_visual
		game.draw_circle(pos, game.CELL * (0.65 + t * 0.55), Color(Palette.ACCENT, alpha * 0.18))
		game.draw_arc(pos, game.CELL * (0.6 + t * 0.45), 0, TAU, 40, Color(Palette.ACCENT, alpha * 0.9), 3, true)
		var sigil = Rect2(pos - Vector2(24, 72 + t * 12), Vector2(48, 48))
		game.draw_texture_rect(ICONS.life_talisman, sigil, false, Color(1, 1, 1, alpha))
func draw():
	if active(): draw_choice();return
	if not hud_visible(): return
	var id: String = game.treasures.active_id()
	if id.is_empty() or not ICONS.has(id): return # No treasure means no empty slot.
	var rect = icon_rect()
	if game.screen == "game": game.draw_circle(rect.get_center(), 25, Palette.SURFACE)
	game.draw_texture_rect(ICONS[id], rect, false)
	if game.screen == "game":
		var status: Dictionary = game.treasures.status()
		var badge: String = str(status.get("badge", ""))
		if not badge.is_empty():
			var width = maxf(18, game.FONT.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 8)
			var badge_rect = Rect2(rect.get_center().x - width * 0.5, rect.end.y - 9, width, 18)
			var color = Palette.ACCENT if status.get("ready", false) else Palette.INK_SECONDARY
			game.panel(badge_rect, color)
			centered(Vector2(badge_rect.get_center().x, badge_rect.position.y + 13), badge, 12, Palette.WHITE)
		draw_feedback()
