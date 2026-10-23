extends RefCounted
var game
var uid = -1
var down = Vector2.ZERO
var pointer = Vector2.ZERO
var active = false
var dragging = false
var free_move = false
var source = ""
var source_card = ""
var source_turn = -1
var source_grapple_anchor_uid = -1
var pass_armed = false
var pass_pressed = false
var pass_click_moved = false
const DRAG_THRESHOLD = 12.0
const PLAY_DRAG_THRESHOLD = 28.0
const UPWARD_CLEARANCE = 16.0
const INVALID_TARGET = Vector2i(-1, -1)
func _init(owner): game = owner
func cancel():
	active = false;dragging = false;free_move = false;uid = -1;source = "";pass_armed = false;pass_pressed = false;pass_click_moved = false
	source_card = "";source_turn = -1
	source_grapple_anchor_uid = -1
func press(position: Vector2, kind: String = "mouse") -> bool:
	if active: return true
	# The shared overlay owns pointer-down before any overlapping hand card.
	# Bind its selected UID now, so a later release cannot discard another copy.
	if game.pass_zone_visible() and game.pass_drop_rect().has_point(position):
		game.sync_hand_ids()
		free_move = game.free_selected
		uid = game.free_card_uid if free_move else game.hand_ids[game.selected]
		source_card = "" if free_move else game.hand[game.selected];source_turn = game.turn
		down = position;pointer = position;active = true;dragging = false;source = kind;pass_pressed = true
		return true
	if game.phase == "play" and game.recovery_active(): return false
	if game.screen != "game" or game.phase not in ["play", "discard"]: return false
	if game.card_picker.active or game.encounter_info_open or game.presentation.active(): return false
	if game.freecard.hit_test(position):


		if not game.free_card_available() or game.input_lock > 0 or game.navigation_lock > 0: return true
		game.grapple_targets.cancel()
		uid = game.free_card_uid;free_move = true;down = position;pointer = position;active = true;dragging = false;source = kind;pass_armed = position.x < game.pass_drop_rect().position.x - 12
		source_card = "";source_turn = game.turn
		return true
	var index = game.handui.hit_index(position)
	if index < 0: return false
	if game.input_lock > 0 or game.navigation_lock > 0: return true
	game.sync_hand_ids()
	if game.grapple_targets.active and game.hand_ids[index] != game.grapple_targets.card_uid: game.grapple_targets.cancel()
	uid = game.hand_ids[index];free_move = false;down = position;pointer = position;active = true;dragging = false;source = kind;pass_armed = position.x < game.pass_drop_rect().position.x - 12
	source_card = game.hand[index];source_turn = game.turn
	if source_card == "grappling_hook" and game.grapple_targets.active: source_grapple_anchor_uid = game.grapple_targets.anchor_uid
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
	var chosen_card = source_card
	var chosen_turn = source_turn
	var chosen_grapple_anchor_uid = source_grapple_anchor_uid
	var origin = down
	var clicked_pass = pass_pressed
	var was_dragging = dragging or pass_click_moved or position.distance_to(down) >= DRAG_THRESHOLD
	var over_pass = was_dragging and game.pass_drop_rect().has_point(position)
	var deliberate_pass = pass_armed or position.x - down.x >= 28
	cancel()
	if canceled: game.grapple_targets.cancel()
	if canceled or game.screen != "game" or game.input_lock > 0 or game.navigation_lock > 0: return
	if game.card_picker.active or game.encounter_info_open or game.presentation.active(): return
	if game.turn != chosen_turn: return
	var index = game.hand_ids.find(chosen_uid) if not chosen_free else -1
	if not chosen_free and (index < 0 or index >= game.hand.size() or game.hand[index] != chosen_card): return
	if clicked_pass:
		if was_dragging or not game.pass_zone_visible() or not game.pass_drop_rect().has_point(position): return
		if chosen_free:
			if chosen_uid == game.free_card_uid: game.pass_card(-1, true)
		else:
			game.pass_card(index)
		return
	if over_pass:
		if not deliberate_pass: return
		if chosen_free:
			if chosen_uid == game.free_card_uid: game.pass_card(-1, true)
		else:
			game.pass_card(index)
		return # Invalid side drops never fall through to normal card use.
	if chosen_free:
		if chosen_uid != game.free_card_uid or not game.free_card_available(): return
		if not was_dragging:
			game.select_free_card()
		elif game.phase == "play" and game.BOARD_RECT.has_point(position):
			var target = game.board_cell(position)
			if game.basic_legal(target): game.basic_move(target)
		return
	if not was_dragging:
		game.select_card(index)
		return
	if game.attack_targets.is_attack(chosen_card):
		var attack_target = _attack_release_target(index, position, origin)
		if attack_target != INVALID_TARGET and game.can_commit_card(index, attack_target): game.play_card(index, attack_target)
		return
	if chosen_card == "grappling_hook":
		# Hooks never use the generic upward attack gesture. A real occupied
		# board anchor is mandatory, followed by an explicit diagonal landing.
		if chosen_grapple_anchor_uid >= 0 and (not game.grapple_targets.active or game.grapple_targets.anchor_uid != chosen_grapple_anchor_uid): return
		if game.phase == "play" and game.BOARD_RECT.has_point(position): game.grapple_targets.choose(index, game.board_cell(position))
		return
	if game.phase != "play" or not game.BOARD_RECT.has_point(position): return
	var card: String = game.hand[index]
	var target = game.board_cell(position)
	if card in game.UNTARGETED: target = game.player
	if game.can_commit_card(index, target): game.play_card(index, target)
func target_cell() -> Vector2i:
	return game.board_cell(pointer) if dragging else Vector2i(-1, -1)

func _attack_release_target(index: int, position: Vector2, origin: Vector2) -> Vector2i:
	if game.phase != "play" or game.pass_drop_rect().has_point(position) or game.full_hand_area().has_point(position): return INVALID_TARGET
	if position.distance_to(origin) < PLAY_DRAG_THRESHOLD: return INVALID_TARGET
	var on_board: bool = game.BOARD_RECT.has_point(position)
	var upward: bool = origin.y - position.y >= PLAY_DRAG_THRESHOLD and position.y <= game.full_hand_area().position.y - UPWARD_CLEARANCE
	if not on_board and not upward: return INVALID_TARGET
	var cell: Vector2i = game.board_cell(position) if on_board else INVALID_TARGET
	var id: String = game.hand[index]
	var explicit_aim = false
	if id == "airdrop": explicit_aim = on_board
	elif id == "blood_edge": explicit_aim = on_board and (game.R.occupied(cell, game.enemies) >= 0 or game.KING_BLOOD.direction(game.player, cell) != Vector2i.ZERO)
	elif id not in ["sweep", "blood_break"]: explicit_aim = on_board and game.R.occupied(cell, game.enemies) >= 0
	return game.attack_targets.resolve_release(index, cell, explicit_aim)

func preview_target() -> Vector2i:
	# The same pure resolution drives the release hint and the eventual action.
	# A pointer over an empty generic board square may resolve a unique victim;
	# an explicit invalid aim must remain invalid rather than redirecting it.
	if not active or not dragging or pass_pressed or source_turn != game.turn: return INVALID_TARGET
	if game.screen != "game" or game.phase != "play" or game.input_lock > 0 or game.navigation_lock > 0: return INVALID_TARGET
	if game.card_picker.active or game.encounter_info_open or game.presentation.active(): return INVALID_TARGET
	if game.pass_drop_rect().has_point(pointer): return INVALID_TARGET
	if free_move:
		if game.BOARD_RECT.has_point(pointer) and uid == game.free_card_uid and game.free_card_available() and game.basic_legal(target_cell()): return target_cell()
		return INVALID_TARGET
	var index = game.hand_ids.find(uid)
	if index < 0 or index >= game.hand.size() or game.hand[index] != source_card: return INVALID_TARGET
	var card: String = game.hand[index]
	if game.attack_targets.is_attack(card): return _attack_release_target(index, pointer, down)
	if card == "grappling_hook" and source_grapple_anchor_uid >= 0 and (not game.grapple_targets.active or game.grapple_targets.anchor_uid != source_grapple_anchor_uid): return INVALID_TARGET
	if not game.BOARD_RECT.has_point(pointer): return INVALID_TARGET
	var target: Vector2i = game.player if card in game.UNTARGETED else target_cell()
	return target if game.can_commit_card(index, target) else INVALID_TARGET

func valid_target() -> bool:
	return preview_target() != INVALID_TARGET
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
		var p = preview_target()
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
