extends RefCounted
const R = preload("res://rules.gd")
const CP = preload("res://cannon_planner.gd")

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
		if i >= 0 and board[i].kind in ["p", "q"]: score += 3.0
		cursor += direction
	return score

static func candidate_score(piece: Dictionary, target: Vector2i, enemies: Array, player: Vector2i) -> float:
	var board = enemies.duplicate(true)
	var index = R.occupied(piece.pos, board)
	if index < 0: return -INF
	board[index].pos = target
	var moved: Dictionary = board[index]
	var score = -float((target - player).length_squared()) * 0.025
	if R.attacks(moved, player, board): score += 4.0
	if piece.kind == "c":
		score += cannon_line_score(moved, board, player)
		# A cannon follows advanced pawn screens, but only along legal R.moves.
		var advanced = false
		for ally in board:
			if ally.kind in ["p", "q"] and ally.pos.y >= 5:
				advanced = true
				if target.x == ally.pos.x and target.y < ally.pos.y: score += 2.0
		if advanced and target.y >= 5: score += 2.5
	elif piece.kind in ["p", "q", "h", "r"]:
		for ally in board:
			if ally.kind == "c" and ally.get("stun", 0) == 0: score += cannon_line_score(ally, board, player)
			if piece.kind in ["p", "q"] and ally.kind == "r" and ally.pos.x == target.x and ally.pos.y < target.y:
				# Adjacent files keep the rook's firing line free instead of blindly blocking it.
				score -= 1.0
			if piece.kind == "r" and ally.kind in ["p", "q"] and abs(target.x - ally.pos.x) == 1: score += 0.9
	elif piece.kind in ["a", "e"]:
		for ally in board:
			if ally.kind != "g": continue
			score -= float((target - ally.pos).length_squared()) * 0.35
			# Prefer squares covering legal approaches to the general.
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if R.attacks(moved, ally.pos + direction, board): score += 1.1
	return score

static func choose(piece: Dictionary, options: Array, enemies: Array, player: Vector2i, rng: RandomNumberGenerator, context: Dictionary = {}, allow_hold: bool = true) -> Vector2i:
	if options.is_empty(): return Vector2i(-1, -1)
	var candidates = options.duplicate()
	var aim = CP.targets(enemies,player,context)
	var cannon_value = 0.0
	for ally in enemies:
		if ally.kind == "c": cannon_value += CP.value(ally,enemies,aim,{}, {})
	var barrier = CP.general_barrier(enemies,player,context) if allow_hold else 0.0
	if allow_hold and (cannon_value > 0.0 or barrier > 0.0): candidates.append(piece.pos)
	var best: Vector2i = options[0]
	var best_score = -INF
	for target in candidates:
		var score = candidate_score(piece, target, enemies, player) + rng.randf_range(0.0, 0.35)
		var trial = CP.placed(enemies,piece.uid,target)
		if allow_hold: score += CP.general_barrier(trial,player,context)-barrier
		if cannon_value > 0.0:
			var after = 0.0
			for ally in trial:
				if ally.kind == "c": after += CP.value(ally,trial,aim,{}, {})
			score += (after-cannon_value)*1.5
			if target == piece.pos: score += 1.0
		if target in piece.get("ai_recent",[]): score -= 1.0
		if score > best_score: best_score = score;best = target
	return best
