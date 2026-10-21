extends RefCounted
# Defensive decisions use public identity/posture and real board geometry only.
# They never read the player's hand, draw pile, planned card, or future position.
const R = preload("res://rules.gd")
const NONE = Vector2i(-1, -1)
const DIRECTIONS = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const HOLD_MARGIN = 2.0

static func threatened(general: Dictionary, board: Array, player: Vector2i, context: Dictionary) -> bool:
	return general.get("kind", "") == "g" and context.get("player_skill", "king") == "artillery" and context.get("artillery_mode", "march") == "attack" and general.pos != player and R.blockers(player, general.pos, board) == 1

static func danger_at(pos: Vector2i, board: Array, player: Vector2i, context: Dictionary) -> bool:
	var d = pos - player
	# These are public attack envelopes, not a claim that a card is in hand.
	# An ally covering the attacker does not make an already exposed king safe.
	if absi(d.x) <= 1 and absi(d.y) <= 1: return true
	if context.get("player_skill", "king") == "artillery" and context.get("artillery_mode", "march") == "attack" and R.blockers(player, pos, board) == 1: return true
	return absi(d.x) + absi(d.y) == 2 and R.blockers(player, pos, board) == 0

static func legal_steps(general: Dictionary, board: Array, player: Vector2i) -> Array:
	var out = []
	if general.get("stun", 0) > 0: return out
	for d in DIRECTIONS:
		var p: Vector2i = general.pos + d
		if p != player and R.occupied(p, board) < 0 and R.attacks(general, p, board): out.append(p)
	return out

static func place(general: Dictionary, target: Vector2i, board: Array) -> Array:
	var out = board.duplicate()
	for i in out.size():
		if out[i].get("uid", -1) == general.get("uid", -2) or out[i] == general:
			out[i] = out[i].duplicate();out[i].pos = target;break
	return out

static func lasting_board(board: Array) -> Array:
	var out = []
	for e in board:
		# A screen expiring at the end of this enemy phase is not future cover.
		if e.kind == "stake" and not e.get("permanent", false) and int(e.get("ttl", 3)) <= 1: continue
		out.append(e)
	return out

static func player_approaches(board: Array, player: Vector2i, context: Dictionary) -> Array:
	var out = [];var deltas: Array = DIRECTIONS.duplicate()
	var identity = context.get("player_skill", "king")
	if identity == "horse":
		deltas = [Vector2i(1,2),Vector2i(2,1),Vector2i(-1,2),Vector2i(-2,1),Vector2i(1,-2),Vector2i(2,-1),Vector2i(-1,-2),Vector2i(-2,-1)]
	elif identity == "artillery" and context.get("artillery_mode", "march") != "attack":
		deltas += [Vector2i(0,2),Vector2i(0,-2),Vector2i(2,0),Vector2i(-2,0)]
	for d in deltas:
		var p: Vector2i = player + d
		if not R.inside(p) or R.occupied(p, board) >= 0: continue
		if identity == "horse":
			var leg = player + Vector2i(signi(d.x) if absi(d.x) == 2 else 0, signi(d.y) if absi(d.y) == 2 else 0)
			if R.occupied(leg, board) >= 0: continue
		elif R.blockers(player, p, board) != 0: continue
		out.append(p)
	return out

static func approach_cover(general: Dictionary, board: Array, player: Vector2i, context: Dictionary) -> Dictionary:
	var covered = 0;var exposed = 0
	# No basic move/short weapon can bridge this distance. Artillery is ranged.
	if context.get("player_skill", "king") != "artillery" and absi(general.pos.x-player.x)+absi(general.pos.y-player.y) > 5:
		return {"covered":0,"exposed":0}
	for approach in player_approaches(board, player, context):
		if not danger_at(general.pos, board, approach, context): continue
		var guarded = false
		for ally in board:
			if ally.kind in ["g", "stake"]: continue
			if R.attacks(ally, approach, board): guarded = true;break
		if guarded: covered += 1
		else: exposed += 1
	return {"covered":covered,"exposed":exposed}

static func profile(general: Dictionary, board: Array, player: Vector2i, context: Dictionary) -> Dictionary:
	var lasting = lasting_board(board)
	var unsafe = danger_at(general.pos, lasting, player, context)
	var cover = approach_cover(general, lasting, player, context)
	var shield = false
	var d: Vector2i = general.pos - player
	# A body is a shield only where it actually interrupts a short spear line.
	# In particular, a lone advisor on a deployed cannon line is a liability.
	if not unsafe and absi(d.x)+absi(d.y) == 2 and (d.x == 0 or d.y == 0):
		shield = R.blockers(player, general.pos, lasting) > 0
	var exits = 0
	for target in legal_steps(general, board, player):
		if not danger_at(target, place(general, target, lasting), player, context): exits += 1
	# Two safe exits suffice. Extra empty squares alone must not lure a safely
	# guarded general toward the player merely to maximize palace mobility.
	var protection = (12.0 if shield else 0.0) + cover.covered * 4.0 - cover.exposed * 12.0 + mini(exits, 2) * 1.5
	return {"unsafe":unsafe,"shield":shield,"covered":cover.covered,"exposed":cover.exposed,"exits":exits,"protection":protection}

static func position_score(general: Dictionary, board: Array, player: Vector2i, context: Dictionary = {}) -> float:
	var state = profile(general, board, player, context)
	return (-10000.0 if state.unsafe else 0.0) + state.protection

static func defend(general: Dictionary, options: Array, board: Array, player: Vector2i, context: Dictionary = {}, allow_hold: bool = true) -> Vector2i:
	if general.get("kind", "") != "g" or general.get("stun", 0) > 0: return NONE
	var legal = legal_steps(general, board, player)
	var candidates = []
	for target in options:
		if target in legal and target not in candidates: candidates.append(target)
	if candidates.is_empty(): return NONE
	# Holding is a genuine action only when movement was available. Main owns its
	# cooldown/credit accounting; no readiness or extra action is granted here.
	if allow_hold: candidates.append(general.pos)
	var old = profile(general, board, player, context)
	var old_distance = absi(general.pos.x-player.x)+absi(general.pos.y-player.y)
	var best = NONE;var best_score = -INF
	for target in candidates:
		var trial = place(general, target, board)
		var moved = general.duplicate();moved.pos = target
		var state = profile(moved, trial, player, context)
		var score = (-10000.0 if state.unsafe else 0.0) + state.protection
		if target == general.pos: score += HOLD_MARGIN
		else:
			# Retreat is relative to the player, including a flank/upper intrusion.
			# Distance alone never makes a safe, guarded king march out of cover.
			if old.unsafe or old.exposed > 0:
				var distance = absi(target.x-player.x)+absi(target.y-player.y)
				score += clampf(float(distance-old_distance), -1.0, 1.0) * 0.75
			if threatened(general, board, player, context) and not threatened(moved, trial, player, context):
				var lateral = (general.pos.x == player.x and target.x != general.pos.x) or (general.pos.y == player.y and target.y != general.pos.y)
				if lateral: score += 0.5
			if target in general.get("ai_recent", []): score -= 0.5
		if score > best_score or (is_equal_approx(score, best_score) and target.y*9+target.x < best.y*9+best.x):
			best = target;best_score = score
	return best

static func guard_state(board: Array, player: Vector2i, context: Dictionary) -> Array:
	var out = [];var lasting = lasting_board(board)
	for general in lasting:
		if general.kind != "g": continue
		var cover = approach_cover(general, lasting, player, context)
		out.append({"uid":general.uid,"unsafe":danger_at(general.pos,lasting,player,context),"exposed":cover.exposed})
	return out

static func preserves_guard_state(before: Array, board: Array, player: Vector2i, context: Dictionary) -> bool:
	if before.is_empty(): return true
	var after = guard_state(board, player, context)
	for previous in before:
		for current in after:
			if current.uid != previous.uid: continue
			if not previous.unsafe and current.unsafe: return false
			# Never buy cannon firepower by opening an unguarded public approach.
			# A real immediate rescue may legitimately change the surrounding lanes.
			if previous.unsafe and not current.unsafe: continue
			if current.exposed > previous.exposed: return false
	return true

static func choose(general: Dictionary, options: Array, board: Array, player: Vector2i, context: Dictionary) -> Vector2i:
	# Retain the narrow deployed-cannon escape API used by existing callers.
	if general.get("stun", 0) > 0 or not threatened(general, board, player, context): return NONE
	var best = defend(general, options, board, player, context, false)
	if best == NONE: return NONE
	var moved = general.duplicate();moved.pos = best
	return best if not threatened(moved, place(general, best, board), player, context) else NONE
