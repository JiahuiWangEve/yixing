extends RefCounted
# A neutral board object: it blocks and screens normally, but never attacks,
# expires, grants enemy-kill rewards, or consumes the player's damage budget.
const R = preload("res://rules.gd")
const CAVALRY = preload("res://cavalry_roles.gd")
const CARD = "decoy_card"
const TREASURE = "decoy_tally"
const NONE = Vector2i(-1, -1)
var game
func _init(owner): game = owner

static func is_offensive(piece: Dictionary) -> bool:
	return piece.get("kind", "") in ["p", "q", "h", "r", "c"] and CAVALRY.role(piece) != "guard_horse"
static func find(board: Array) -> Dictionary:
	for piece in board:
		if piece.get("kind", "") == "decoy" and int(piece.get("hp", 2)) > 0: return piece
	return {}
static func attackable(piece: Dictionary, decoy: Dictionary, board: Array, player: Vector2i) -> bool:
	if decoy.is_empty() or not is_offensive(piece): return false
	return R.captures_object(piece, decoy.pos, board, player)
func can_place(cell: Vector2i) -> bool:
	var delta: Vector2i = cell - game.player
	return R.inside(cell) and cell != game.player and absi(delta.x) <= 2 and absi(delta.y) <= 2 and R.occupied(cell, game.enemies) < 0 and find(game.enemies).is_empty()
func legal(cell: Vector2i) -> bool: return can_place(cell)
func place(cell: Vector2i) -> bool:
	if not can_place(cell): return false
	game.add_enemy("decoy", cell, 0)
	var object: Dictionary = game.enemies.back()
	object.hp = 2;object.max_hp = 2;object.neutral = true
	game.effect("stake_place", game.cell_pos(cell), game.cell_pos(cell), 0.3)
	game.log_line("草人落位：2血，持续本场战斗。")
	return true
func start_turn() -> bool:
	if not game.treasures.has(TREASURE) or int(game.turn) < 1 or (int(game.turn) - 1) % 3 != 0: return false
	if int(game.treasure_battle.get("decoy_last_turn", -1)) == int(game.turn): return false
	game.treasure_battle.decoy_last_turn = int(game.turn)
	if CARD in game.hand: return false
	# The shared insertion helper preserves stable hand UIDs and overflow flow;
	# CARD is deliberately NOT a temporary card and survives the end of a turn.
	game.treasures.generate_move(CARD)
	game.treasures.trigger("疑兵虎符：获得草木皆兵。", "draw", "", TREASURE)
	return true
func on_turn_start() -> bool: return start_turn()
func on_enemy_attack(piece: Dictionary, timeline: float) -> Dictionary:
	var result = {"consumed":false, "timeline":timeline, "moved":false, "destroyed":false, "target_uid":-1}
	if int(piece.get("decoy_attacked_turn", -1)) == int(game.turn):
		result.consumed = true
		return result
	var decoy = find(game.enemies)
	if not attackable(piece, decoy, game.enemies, game.player): return result
	var origin: Vector2i = piece.pos
	var target: Vector2i = decoy.pos
	piece.decoy_attacked_turn = int(game.turn)
	result.consumed = true;result.target_uid = decoy.uid
	decoy.hp = int(decoy.get("hp", 2)) - 1
	game.effect("hit", game.cell_pos(target), game.cell_pos(target), 0.24, timeline + 0.14, {"piece":decoy})
	if decoy.hp <= 0:
		# Legality was checked on the occupied board, including the actual player.
		# This is the one capture movement, not a subsequent empty-square move.
		game.enemies.erase(decoy)
		game.move_piece(piece, game.cell_pos(origin), game.cell_pos(target), timeline, piece.kind == "h")
		piece.pos = target
		var recent: Array = piece.get("ai_recent", []).duplicate()
		recent.push_front(origin)
		if recent.size() > 2: recent.resize(2)
		piece.ai_recent = recent
		game.effect("death", game.cell_pos(target), game.cell_pos(target), 0.42, timeline + 0.20, {"symbol":"草", "impact":timeline + 0.14})
		game.log_line("草人被击碎，%s进入原位。" % (CAVALRY.display_name(piece) if CAVALRY.is_variant(piece) else game.piece_name(piece.kind)))
		result.moved = true;result.destroyed = true;result.timeline = timeline + 0.28
	else:
		game.effect("enemy_impact", game.cell_pos(origin), game.cell_pos(target), 0.34, timeline, {"attacker_uid":piece.uid, "origin_cell":origin, "target_cell":target, "impact_at":0.14, "lives_before":game.lives, "decoy_target":true})
		game.log_line("草人受击，剩余%d血。" % decoy.hp)
		result.timeline = timeline + 0.34
	return result
func attack(piece: Dictionary, timeline: float) -> Dictionary: return on_enemy_attack(piece, timeline)

static func choose(piece: Dictionary, options: Array, board: Array, player: Vector2i, context: Dictionary = {}, allow_hold: bool = true) -> Vector2i:
	var decoy = find(board)
	if decoy.is_empty() or not is_offensive(piece) or int(piece.get("stun", 0)) > 0: return NONE
	var legal = R.moves(piece, board, player)
	var candidates = []
	for target in options:
		if target in legal and target not in candidates: candidates.append(target)
	if candidates.is_empty(): return NONE
	if allow_hold: candidates.append(piece.pos)
	var best: Vector2i = candidates[0];var best_score = -INF
	for target in candidates:
		var trial = CAVALRY.placed(piece, target, board)
		var moved = piece.duplicate();moved.pos = target
		var score = -float((target - decoy.pos).length_squared()) * 0.15
		# Threat creation, never a move onto the occupied bait. A cannon needs
		# exactly one screen on the real board, including the player's body.
		if attackable(moved, decoy, trial, player): score += 1000.0
		if CAVALRY.role(piece) == "outrider": score += CAVALRY.outrider_score(moved, trial, decoy.pos, context, true)
		if target == piece.pos: score += 0.25
		elif target in piece.get("ai_recent", []): score -= 0.75
		if score > best_score or (is_equal_approx(score, best_score) and target.y * 9 + target.x < best.y * 9 + best.x):
			best = target;best_score = score
	return best
