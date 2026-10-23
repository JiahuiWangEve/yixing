extends RefCounted
# Both variants are ordinary horses. Roles change public-board evaluation only,
# never horse legs, attack geometry, damage, readiness, or the player's inputs.
const R = preload("res://rules.gd")
const GE = preload("res://general_evasion.gd")
const NONE = Vector2i(-1, -1)
const ROLES = ["outrider", "guard_horse"]

static func role(piece: Dictionary) -> String:
	return str(piece.get("ai_role", "")) if piece.get("kind", "") == "h" else ""
static func is_variant(piece: Dictionary) -> bool: return role(piece) in ROLES
static func configure(piece: Dictionary, identity: String) -> Dictionary:
	if identity not in ROLES: return piece
	piece.kind = "h";piece.ai_role = identity;piece.hp = 2;piece.max_hp = 2
	return piece
static func display_name(piece: Dictionary) -> String:
	return {"outrider":"游骑", "guard_horse":"近卫骑"}.get(role(piece), "马")
static func role_text(piece: Dictionary) -> String:
	if role(piece) == "outrider": return "游骑：按马步移动，优先封锁撤退空位，避开友军重复控制。"
	if role(piece) == "guard_horse": return "近卫骑：按马步移动，守住敌将附近；不追逐草人，不提供无敌。"
	return ""
static func placed(piece: Dictionary, target: Vector2i, board: Array) -> Array:
	return GE.place(piece, target, board)
static func general(board: Array) -> Dictionary:
	for ally in board:
		if ally.kind == "g": return ally
	return {}
static func covered_by_others(piece: Dictionary, cell: Vector2i, board: Array) -> bool:
	for ally in board:
		if ally.get("uid", -1) == piece.get("uid", -2) or ally.kind in ["stake", "decoy"]: continue
		if R.attacks(ally, cell, board): return true
	return false
static func escape_cells(board: Array, target: Vector2i, context: Dictionary, bait: bool = false) -> Array:
	if not bait: return GE.player_approaches(board, target, context)
	var result = []
	for direction in GE.DIRECTIONS:
		var cell: Vector2i = target + direction
		if R.inside(cell) and R.occupied(cell, board) < 0: result.append(cell)
	return result
static func outrider_score(piece: Dictionary, board: Array, player: Vector2i, context: Dictionary = {}, bait: bool = false) -> float:
	var score = -float((piece.pos - player).length_squared()) * 0.02
	# The valuable job is fresh coverage, not a second horse on the same lane.
	for cell in escape_cells(board, player, context, bait):
		if R.attacks(piece, cell, board): score += 1.5 if covered_by_others(piece, cell, board) else 9.0
	if R.attacks(piece, player, board): score += 2.0
	return score
static func guard_score(piece: Dictionary, board: Array, player: Vector2i, context: Dictionary = {}) -> float:
	var king = general(board)
	if king.is_empty(): return 0.0
	var distance: int = (piece.pos - king.pos).length_squared()
	var score = -float(distance) * 2.0
	# Long-range chase is never a substitute for the post around the general.
	if distance > 13: score -= 80.0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var cell: Vector2i = king.pos + Vector2i(dx, dy)
			if not R.inside(cell) or cell == king.pos or R.occupied(cell, board) >= 0: continue
			if R.attacks(piece, cell, board): score += 3.0
	for cell in GE.player_approaches(board, player, context):
		if (cell - king.pos).length_squared() <= 8 and R.attacks(piece, cell, board): score += 10.0
	if (player - king.pos).length_squared() <= 13 and R.attacks(piece, player, board): score += 8.0
	return score
static func choose(piece: Dictionary, options: Array, board: Array, player: Vector2i, context: Dictionary = {}, allow_hold: bool = true) -> Vector2i:
	if not is_variant(piece) or int(piece.get("stun", 0)) > 0: return NONE
	var legal = R.moves(piece, board, player)
	var candidates = []
	for target in options:
		if target in legal and target not in candidates: candidates.append(target)
	if candidates.is_empty(): return NONE
	if allow_hold: candidates.append(piece.pos)
	var before = GE.guard_state(board, player, context)
	var best: Vector2i = piece.pos if allow_hold else candidates[0]
	var best_score = -INF
	for target in candidates:
		var trial = placed(piece, target, board)
		if not GE.preserves_guard_state(before, trial, player, context): continue
		var moved = piece.duplicate();moved.pos = target
		var score = guard_score(moved, trial, player, context) if role(piece) == "guard_horse" else outrider_score(moved, trial, player, context)
		if target == piece.pos: score += 1.0
		elif target in piece.get("ai_recent", []): score -= 0.75
		if score > best_score or (is_equal_approx(score, best_score) and target.y * 9 + target.x < best.y * 9 + best.x):
			best = target;best_score = score
	return best
