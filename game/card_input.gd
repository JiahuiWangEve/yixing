extends RefCounted
var game
var uid = -1
var down = Vector2.ZERO
var pointer = Vector2.ZERO
var active = false
var dragging = false
var free_move = false
var source = ""
var pass_armed = false
var pass_pressed = false
var pass_click_moved = false
const DRAG_THRESHOLD = 12.0
func _init(owner): game = owner
func cancel():
	active = false;dragging = false;free_move = false;uid = -1;source = "";pass_armed = false;pass_pressed = false;pass_click_moved = false
func press(position: Vector2, kind: String = "mouse") -> bool:
	if active: return true
	# The shared overlay owns pointer-down before any overlapping hand card.
	# Bind its selected UID now, so a later release cannot discard another copy.
	if game.pass_zone_visible() and game.pass_drop_rect().has_point(position):
		game.sync_hand_ids()
		free_move = game.free_selected
		uid = game.free_card_uid if free_move else game.hand_ids[game.selected]
		down = position;pointer = position;active = true;dragging = false;source = kind;pass_pressed = true
		return true
	if game.phase == "play" and game.recovery_active(): return false
	if game.screen != "game" or game.phase not in ["play", "discard"]: return false
	if game.card_picker.active or game.encounter_info_open or game.presentation.active(): return false
	if game.freecard.hit_test(position):


		if not game.free_card_available() or game.input_lock > 0 or game.navigation_lock > 0: return true
		uid = game.free_card_uid;free_move = true;down = position;pointer = position;active = true;dragging = false;source = kind;pass_armed = position.x < game.pass_drop_rect().position.x - 12
		return true
	var index = game.handui.hit_index(position)
	if index < 0: return false
	if game.input_lock > 0 or game.navigation_lock > 0: return true
	game.sync_hand_ids()
	uid = game.hand_ids[index];free_move = false;down = position;pointer = position;active = true;dragging = false;source = kind;pass_armed = position.x < game.pass_drop_rect().position.x - 12
	return true
func motion(position: Vector2):
	if not active: return
	pointer = position
	if pass_pressed:
		# Once a press becomes movement, returning to the zone is not a click.
		pass_click_moved = pass_click_moved or position.distance_to(down) >= DRAG_THRESHOLD
		return # A zone press never starts a new card drag underneath it.
	if position.x < game.pass_drop_rect().position.x - 12 or position.x - down.x >= 28: pass_armed = true
	if position.distance_to(down) >= DRAG_THRESHOLD: dragging = true
func release(position: Vector2, canceled: bool = false):
	if not active: return
	pointer = position
	var chosen_uid = uid
	var chosen_free = free_move
	var clicked_pass = pass_pressed
	var was_dragging = dragging or pass_click_moved or position.distance_to(down) >= DRAG_THRESHOLD
	var over_pass = was_dragging and game.pass_drop_rect().has_point(position)
	var deliberate_pass = pass_armed or position.x - down.x >= 28
	cancel()
	if canceled or game.screen != "game" or game.input_lock > 0 or game.navigation_lock > 0: return
	if game.card_picker.active or game.encounter_info_open or game.presentation.active(): return
	if clicked_pass:
		if was_dragging or not game.pass_zone_visible() or not game.pass_drop_rect().has_point(position): return
		if chosen_free:
			if chosen_uid == game.free_card_uid: game.pass_card(-1, true)
		else:
			game.pass_card(game.hand_ids.find(chosen_uid))
		return
	if over_pass:
		if not deliberate_pass: return
		if chosen_free:
			if chosen_uid == game.free_card_uid: game.pass_card(-1, true)
		else:
			game.pass_card(game.hand_ids.find(chosen_uid))
		return # Invalid side drops never fall through to normal card use.
	if chosen_free:
		if chosen_uid != game.free_card_uid or not game.free_card_available(): return
		if not was_dragging:
			game.select_free_card()
		elif game.phase == "play" and game.BOARD_RECT.has_point(position):
			var target = game.board_cell(position)
			if game.basic_legal(target): game.basic_move(target)
		return
	var index = game.hand_ids.find(chosen_uid)
	if index < 0: return
	if not was_dragging:
		game.select_card(index)
		return
	if game.phase != "play" or not game.BOARD_RECT.has_point(position): return
	var card: String = game.hand[index]
	var target = game.board_cell(position)
	if card in game.UNTARGETED: target = game.player
	if game.can_commit_card(index, target): game.play_card(index, target)
func target_cell() -> Vector2i:
	return game.board_cell(pointer) if dragging else Vector2i(-1, -1)
func valid_target() -> bool:
	if game.pass_drop_rect().has_point(pointer): return false
	if not dragging or game.phase != "play" or not game.BOARD_RECT.has_point(pointer): return false
	if free_move:
		return uid == game.free_card_uid and game.free_card_available() and game.basic_legal(target_cell())
	var index = game.hand_ids.find(uid)
	if index < 0: return false
	var card: String = game.hand[index]
	return game.can_commit_card(index, game.player if card in game.UNTARGETED else target_cell())
func pass_zone_state() -> Dictionary:
	var visible: bool = game.pass_zone_visible()
	var chosen_free: bool = free_move if active else game.free_selected
	var index: int = game.hand_ids.find(uid) if active else game.selected
	var allowed: bool = visible and game.can_pass_card(index, chosen_free)
	var inside: bool = visible and active and dragging and pass_armed and game.pass_drop_rect().has_point(pointer)
	var hint = "单击弃置"
	if active and not pass_pressed: hint = "松手弃置" if inside else "拖入弃置"
	if not allowed: hint = "能量不足" if game.energy < game.PASS_CARD_COST else "不可弃置"
	return {"visible": visible, "enabled": allowed, "highlighted": inside and allowed, "inside": inside, "title": "弃置", "cost": "%d费" % game.PASS_CARD_COST, "replacement": "补抽1张", "hint": hint}
func draw_pass_zone():
	var state = pass_zone_state()
	if not state.visible: return
	var rect: Rect2 = game.pass_drop_rect()
	var outline: Color = game.THEME.SAFE if state.highlighted else (game.RED if state.inside else game.THEME.BORDER)
	game.panel(rect, game.THEME.PAPER_SELECTED if state.highlighted else game.THEME.BUTTON, outline)
	if state.inside: game.draw_rect(rect.grow(-3), outline, false, 3)
	var x = rect.position.x + 8
	game.text_at(Vector2(x, rect.position.y + 36), state.title, 22, game.THEME.INK if state.enabled else game.THEME.GRID)
	game.text_at(Vector2(x, rect.position.y + 66), state.cost, 20, game.THEME.INK if state.enabled else game.THEME.GRID)
	game.text_at(Vector2(x, rect.position.y + 100), state.hint, 14, game.THEME.INK if state.enabled else game.RED)
	game.text_at(Vector2(x, rect.position.y + 124), state.replacement, 14, game.THEME.GRID)
func draw():
	if not dragging:
		draw_pass_zone()
		return
	if free_move:
		_draw_free()
		draw_pass_zone()
		return
	var index = game.hand_ids.find(uid)
	if index < 0: return
	var t: Transform2D = game.handui.card_transform(index)
	var scale = t.get_scale()
	t.x = Vector2(scale.x, 0);t.y = Vector2(0, scale.y)
	t.origin = pointer - game.handui.card_size() * scale * 0.5
	var over_board = game.BOARD_RECT.has_point(pointer)
	game.handui.draw_card(index, t, 0.2 if over_board or game.pass_drop_rect().has_point(pointer) else 0.9)
	var polygon = PackedVector2Array()
	var size = game.handui.card_size()
	for point in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y), Vector2.ZERO]: polygon.append(t * point)
	game.draw_polyline(polygon, game.THEME.SAFE if valid_target() else Color(game.THEME.INK, 0.7), 2)
	if valid_target():
		var p = target_cell()
		if p.x >= 0:
			var danger = game.target_danger(game.hand[index], p)
			game.draw_arc(game.cell_pos(p), game.CELL * 0.42 + sin(game.tick * 8) * 2, 0, TAU, 32, game.RED if danger else game.THEME.SAFE, 3)

	draw_pass_zone() # Keep drop instructions legible above the translucent dragged card.

func _draw_free():
	if uid != game.free_card_uid or not game.free_card_available(): return
	var transform: Transform2D = game.handui.free_transform()
	var size = Vector2(transform.x.length(), transform.y.length()) * game.handui.card_size()
	var rect = Rect2(pointer - size * 0.5, size)
	var over_board: bool = game.BOARD_RECT.has_point(pointer)
	game.freecard.draw_card(rect, 0.2 if over_board or game.pass_drop_rect().has_point(pointer) else 0.9)
	var polygon = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), rect.position])
	var legal = valid_target()
	var color: Color = game.THEME.SAFE if legal else Color(game.THEME.INK, 0.7)
	game.draw_polyline(polygon, color, 2)
	if legal:
		var target = target_cell()
		var danger: bool = game.R.threatened(target, game.enemies)
		game.draw_arc(game.cell_pos(target), game.CELL * 0.42 + sin(game.tick * 8) * 2, 0, TAU, 32, game.RED if danger else game.THEME.SAFE, 3)
