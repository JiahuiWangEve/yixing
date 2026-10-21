extends RefCounted
# Public posture + board geometry only. Never inspect the player's hand or deck.
const R = preload("res://rules.gd")

static func threatened(general: Dictionary, board: Array, player: Vector2i, context: Dictionary) -> bool:
	return general.get("kind", "") == "g" and context.get("player_skill", "king") == "artillery" and context.get("artillery_mode", "march") == "attack" and general.pos != player and R.blockers(player, general.pos, board) == 1

static func choose(general: Dictionary, options: Array, board: Array, player: Vector2i, context: Dictionary) -> Vector2i:
	if general.get("stun", 0) > 0 or not threatened(general, board, player, context): return Vector2i(-1, -1)
	var best = Vector2i(-1, -1)
	var best_score = -INF
	var legal = R.moves(general, board, player)
	for target in options:
		# Revalidate rather than trusting a caller's candidate list.
		if target not in legal: continue
		var trial = board.duplicate(true)
		var index = R.occupied(general.pos, trial)
		if index < 0: continue
		trial[index].pos = target
		if threatened(trial[index], trial, player, context): continue
		# A sidestep leaves the firing axis; prefer it over moving along the gun line.
		var lateral = (general.pos.x == player.x and target.x != general.pos.x) or (general.pos.y == player.y and target.y != general.pos.y)
		var score = (100.0 if lateral else 0.0) + float((target - player).length_squared()) * 0.01
		var key = target.y * 9 + target.x
		var old_key = best.y * 9 + best.x
		if score > best_score or (is_equal_approx(score, best_score) and key < old_key):
			best = target;best_score = score
	return best
