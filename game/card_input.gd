extends RefCounted
var game
var uid = -1
var down = Vector2.ZERO
var pointer = Vector2.ZERO
var active = false
var dragging = false
var free_move = false
var source = ""
const DRAG_THRESHOLD = 12.0
func _init(owner): game = owner
func cancel():
	active = false;dragging = false;free_move = false;uid = -1;source = ""
func press(position: Vector2, kind: String = "mouse") -> bool:
	if game.screen != "game" or game.phase not in ["play", "discard"]: return false
	if game.can_emergency_pack() and game.pack_button_rect().has_point(position): return false
	if game.freecard.hit_test(position):


		if not game.free_card_available() or game.input_lock > 0 or game.navigation_lock > 0: return true
		uid = game.free_card_uid;free_move = true;down = position;pointer = position;active = true;dragging = false;source = kind
		return true
	var index = game.handui.hit_index(position)
	if index < 0: return false
	if game.input_lock > 0 or game.navigation_lock > 0: return true
	game.sync_hand_ids()
	uid = game.hand_ids[index];free_move = false;down = position;pointer = position;active = true;dragging = false;source = kind
	return true
func motion(position: Vector2):
	if not active: return
	pointer = position
	if position.distance_to(down) >= DRAG_THRESHOLD: dragging = true
func release(position: Vector2, canceled: bool = false):
	if not active: return
	pointer = position
	var chosen_uid = uid
	var chosen_free = free_move
	var was_dragging = dragging or position.distance_to(down) >= DRAG_THRESHOLD
	cancel()
	if canceled or game.screen != "game" or game.input_lock > 0 or game.navigation_lock > 0: return
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
	if not dragging or game.phase != "play" or not game.BOARD_RECT.has_point(pointer): return false
	if free_move:
		return uid == game.free_card_uid and game.free_card_available() and game.basic_legal(target_cell())
	var index = game.hand_ids.find(uid)
	if index < 0: return false
	var card: String = game.hand[index]
	return game.can_commit_card(index, game.player if card in game.UNTARGETED else target_cell())
func draw():
	if not dragging: return
	if free_move:
		_draw_free()
		return
	var index = game.hand_ids.find(uid)
	if index < 0: return
	var t: Transform2D = game.handui.card_transform(index)
	var scale = t.get_scale()
	t.x = Vector2(scale.x, 0);t.y = Vector2(0, scale.y)
	t.origin = pointer - game.handui.card_size() * scale * 0.5
	var over_board = game.BOARD_RECT.has_point(pointer)
	game.handui.draw_card(index, t, 0.2 if over_board else 0.9)
	var polygon = PackedVector2Array()
	var size = game.handui.card_size()
	for point in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y), Vector2.ZERO]: polygon.append(t * point)
	game.draw_polyline(polygon, game.GOLD if valid_target() else Color(0.6, 0.7, 0.7, 0.7), 2)
	if valid_target():
		var p = target_cell()
		if p.x >= 0:
			var danger = game.target_danger(game.hand[index], p)
			game.draw_arc(game.cell_pos(p), game.CELL * 0.42 + sin(game.tick * 8) * 2, 0, TAU, 32, game.RED if danger else game.GOLD, 3)

func _draw_free():
	if uid != game.free_card_uid or not game.free_card_available(): return
	var transform: Transform2D = game.handui.free_transform()
	var size = Vector2(transform.x.length(), transform.y.length()) * game.handui.card_size()
	var rect = Rect2(pointer - size * 0.5, size)
	var over_board: bool = game.BOARD_RECT.has_point(pointer)
	game.freecard.draw_card(rect, 0.2 if over_board else 0.9)
	var polygon = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), rect.position])
	var legal = valid_target()
	var color: Color = game.GOLD if legal else Color(0.6, 0.7, 0.7, 0.7)
	game.draw_polyline(polygon, color, 2)
	if legal:
		var target = target_cell()
		var danger: bool = game.R.threatened(target, game.enemies)
		game.draw_arc(game.cell_pos(target), game.CELL * 0.42 + sin(game.tick * 8) * 2, 0, TAU, 32, game.RED if danger else game.GOLD, 3)
