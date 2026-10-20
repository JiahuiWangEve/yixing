extends RefCounted
const R = preload("res://rules.gd")

static func cannon_line_score(cannon: Dictionary, board: Array, player: Vector2i) -> float:
	if cannon.pos == player: return 0.0
	if cannon.pos.x != player.x and cannon.pos.y != player.y: return 0.0
	var count = R.blockers(cannon.pos, player, board)
	if count == 0: return 1.5
	if count != 1: return 0.0
	var score = 12.0
	var direction = Vector2i(signi(player.x - cannon.pos.x), signi(player.y - cannon.pos.y))
	var cursor: Vector2i = cannon.pos + direction
	while cursor != player:
		var i = R.occupied(cursor, board)
		if i >= 0 and board[i].kind == "p": score += 3.0
		cursor += direction
	return score
static func candidate_score(piece: Dictionary, target: Vector2i, enemies: Array, player: Vector2i) -> float:
	var board = enemies.duplicate(true)
	var index = R.occupied(piece.pos, board)
	if index < 0: return - INF
	board[index].pos = target
	var moved: Dictionary = board[index]
	var score = - float((target - player).length_squared()) * 0.025
	if piece.kind == "c": score += cannon_line_score(moved, board, player)
	elif piece.kind == "p":
		for ally in board:
			if ally.kind == "c" and ally.get("stun", 0) == 0: score += cannon_line_score(ally, board, player)
		if R.attacks(moved, player, board): score += 4.0
	return score
static func choose(piece: Dictionary, options: Array, enemies: Array, player: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	if options.is_empty(): return Vector2i(-1, -1)
	var cooperative = piece.kind == "c"
	if piece.kind == "p":
		for ally in enemies:
			if ally.kind == "c" and ally.get("stun", 0) == 0: cooperative = true
	if not cooperative:
		var ordered = options.duplicate()
		ordered.sort_custom( func(a, b): return (a - player).length_squared() < (b - player).length_squared())
		return ordered[rng.randi_range(0, mini(3, ordered.size()) - 1)]
	var best: Vector2i = options[0]
	var best_score = - INF
	for target in options:
		var score = candidate_score(piece, target, enemies, player) + rng.randf_range(0.0, 0.7)
		if score > best_score: best_score = score;best = target
	return best
