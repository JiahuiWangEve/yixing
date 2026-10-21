extends RefCounted
# A bounded, phase-local joint planner. It never runs during rendering/player play.
const R = preload("res://rules.gd")
const GE = preload("res://general_evasion.gd")
const RT = preload("res://rook_tactics.gd")
const MAX_CANNONS = 4
const SUPPORT_LIMIT = 3
const CANNON_BEAM = 6
const SUPPORT_BEAM = 5
const SECOND_BEAM = 18
const MAX_EVALUATIONS = 800
const NONE = Vector2i(-1, -1)

static func key(p: Vector2i) -> int: return p.y * 9 + p.x
static func by_uid(board: Array, uid: int) -> int:
	for i in board.size():
		if board[i].get("uid", -1) == uid: return i
	return -1
static func occupancy(board: Array, horizon: int = -1) -> Dictionary:
	var out = {}
	for e in board:
		if horizon >= 0 and e.kind == "stake" and not e.get("permanent", false) and int(e.get("ttl", 3)) <= horizon + 1: continue
		out[key(e.pos)] = e
	return out
static func screen(from: Vector2i, target: Vector2i, occ: Dictionary) -> Dictionary:
	if from == target or (from.x != target.x and from.y != target.y): return {}
	var step = Vector2i(signi(target.x - from.x), signi(target.y - from.y))
	var cursor = from + step;var found = {}
	while cursor != target:
		if occ.has(key(cursor)):
			if not found.is_empty(): return {}
			found = occ[key(cursor)]
		cursor += step
	return found
static func moves(e: Dictionary, board: Array, player: Vector2i) -> Array:
	if e.get("stun",0)>0: return []
	var out = [];var occ = occupancy(board);occ[key(player)] = {"pos":player}
	if e.kind in ["c","r"]:
		for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var p: Vector2i = e.pos+d
			while R.inside(p) and not occ.has(key(p)):
				out.append(p);p += d
		return out
	var deltas = []
	match e.kind:
		"p","q":
			deltas = [Vector2i(0,1)]
			if e.pos.y>=5: deltas += [Vector2i.LEFT,Vector2i.RIGHT]
		"g": deltas = [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
		"a": deltas = [Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]
		"e": deltas = [Vector2i(2,2),Vector2i(2,-2),Vector2i(-2,2),Vector2i(-2,-2)]
		"h": deltas = [Vector2i(1,2),Vector2i(2,1),Vector2i(-1,2),Vector2i(-2,1),Vector2i(1,-2),Vector2i(2,-1),Vector2i(-1,-2),Vector2i(-2,-1)]
	var with_player = board.duplicate();with_player.append({"pos":player})
	for d in deltas:
		var p: Vector2i = e.pos+d
		if R.inside(p) and not occ.has(key(p)) and R.attacks(e,p,with_player): out.append(p)
	return out
static func legal(e: Dictionary, target: Vector2i, board: Array, player: Vector2i, allow_hold: bool = true) -> bool:
	if not R.inside(target) or e.get("stun", 0) > 0: return false
	if target == e.pos: return allow_hold and not moves(e, board, player).is_empty()
	if target == player or R.occupied(target, board) >= 0: return false
	var occupied_board = board.duplicate();occupied_board.append({"pos": player})
	if e.kind == "c": return R.blockers(e.pos, target, occupied_board) == 0
	return R.attacks(e, target, occupied_board)
static func placed(board: Array, uid: int, target: Vector2i) -> Array:
	var out = board.duplicate();var i = by_uid(board, uid)
	if i >= 0: out[i] = board[i].duplicate();out[i].pos = target
	return out
static func targets(board: Array, player: Vector2i, context: Dictionary) -> Dictionary:
	var out = {key(player): 110.0}
	var deltas = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	if context.get("player_skill", "king") == "horse":
		deltas += [Vector2i(1,2),Vector2i(2,1),Vector2i(-1,2),Vector2i(-2,1),Vector2i(1,-2),Vector2i(2,-1),Vector2i(-1,-2),Vector2i(-2,-1)]
	elif context.get("player_skill", "king") == "artillery" and context.get("artillery_mode", "march") != "attack":
		deltas += [Vector2i(0,2),Vector2i(0,-2),Vector2i(2,0),Vector2i(-2,0)]
	for d in deltas:
		var p = player + d
		if R.inside(p) and R.occupied(p, board) < 0:
			if maxi(abs(d.x), abs(d.y)) == 2:
				var leg = player + Vector2i(signi(d.x) if abs(d.x) == 2 else 0, signi(d.y) if abs(d.y) == 2 else 0)
				if R.occupied(leg, board) >= 0: continue
			out[key(p)] = 10.0
	for e in board:
		if e.kind != "g": continue
		var distance = absi(player.x - e.pos.x) + absi(player.y - e.pos.y)
		if distance > 5: continue
		for dy in range(-2,3):
			for dx in range(-2,3):
				var d = Vector2i(dx,dy)
				if d == Vector2i.ZERO or (abs(dx) == 2 and dy != 0) or (abs(dy) == 2 and dx != 0): continue
				var p = e.pos + d
				if not R.inside(p) or R.occupied(p,board) >= 0: continue
				# Only the player's side/reachable approach, not every palace-adjacent square.
				if (p-player).length_squared() > 13: continue
				var value = 38.0 if distance <= 2 else 20.0
				out[key(p)] = maxf(float(out.get(key(p),0)), value)
	return out
static func reliability(e: Dictionary, ready: Dictionary, locked: Dictionary, horizon: int) -> float:
	if e.kind == "stake": return 1.0
	if locked.has(e.get("uid", -1)): return 1.0
	if int(e.get("stun",0)) > horizon: return 1.0
	var upcoming = ready.has(e.get("uid",-1)) if horizon == 0 else int(e.get("cd",3)) <= horizon + 1 or (int(e.get("action_credits",0)) > 0 and int(e.get("action_credit_delay",0)) <= horizon)
	return 0.72 if upcoming else 1.0
static func value(cannon: Dictionary, board: Array, aim: Dictionary, ready: Dictionary, locked: Dictionary, horizon: int = 0) -> float:
	if cannon.get("stun",0) > horizon: return 0.0
	var occ = occupancy(board,horizon);var score = 0.0
	for cell in aim:
		var p = Vector2i(cell % 9, cell / 9)
		var support = screen(cannon.pos,p,occ)
		if support.is_empty(): continue
		var discount = 1.0
		# Cover different avenues instead of stacking all cannons on the same lane.
		for ally in board:
			if ally.kind == "c" and ally.get("uid",-1) != cannon.get("uid",-1) and ally.get("stun",0) <= horizon:
				if not screen(ally.pos,p,occ).is_empty(): discount = 0.65;break
		score += float(aim[cell]) * reliability(support,ready,locked,horizon) * discount
	return score
static func setup_value(cannon: Dictionary, board: Array, aim: Dictionary) -> float:
	# Hoist the screen-alignment scan out of the target loop.
	var aligned = false
	for ally in board:
		if ally.kind in ["c","g"] or ally.get("uid",-1) == cannon.get("uid",-1): continue
		if ally.kind == "stake" and not ally.get("permanent",false) and ally.get("ttl",3) <= 1: continue
		if cannon.pos.x == ally.pos.x or cannon.pos.y == ally.pos.y: aligned = true;break
	if not aligned: return 0.0
	var best = 0.0
	for cell in aim:
		var distance = abs(cannon.pos.x-cell%9)+abs(cannon.pos.y-cell/9)
		if distance > 1: best = maxf(best,5.0-minf(distance,12)*0.25)
	return best
static func general_barrier(board: Array, player: Vector2i, context: Dictionary = {}) -> float:
	# Public basic spear geometry only: a body really blocks this two-cell line.
	# Adjacent / diagonal danger cannot be 'rescued' by an imaginary screen.
	if context.get("player_skill","king") == "artillery": return 0.0
	for general in board:
		if general.kind != "g": continue
		var delta: Vector2i = general.pos-player
		if absi(delta.x)+absi(delta.y) != 2 or (delta.x != 0 and delta.y != 0): continue
		var midpoint = player+Vector2i(signi(delta.x),signi(delta.y))
		var i = R.occupied(midpoint,board)
		if i >= 0:
			var blocker = board[i]
			if blocker.kind == "stake" and not blocker.get("permanent",false) and blocker.get("ttl",3)<=1: continue
			return 220.0
	return 0.0
static func movement_penalty(e: Dictionary, target: Vector2i, current_value: float, new_value: float, player: Vector2i, board: Array) -> float:
	if target == e.pos: return 0.0
	var cost = 2.5
	# Strong tactical gains or an obsolete old line override inertia/anti-return.
	if current_value > 1.0 and new_value < current_value + 20.0:
		if target in e.get("ai_recent",[]): cost += 10.0
	for ally in board:
		if ally.kind == "g" and e.kind in ["a","e"] and (player-ally.pos).length_squared() <= 13:
			cost += maxf(0,float((target-ally.pos).length_squared()-(e.pos-ally.pos).length_squared()))*1.5
	return cost
static func ranked_options(e: Dictionary, board: Array, player: Vector2i, aim: Dictionary, limit: int) -> Array:
	var options = moves(e,board,player)
	if options.is_empty(): return []
	options.append(e.pos)
	var scored = []
	for p in options:
		var rough = 0.0
		for cell in aim:
			var goal = Vector2i(cell % 9,cell/9)
			if p.x == goal.x or p.y == goal.y: rough += float(aim[cell]) * 0.15
			rough = maxf(rough, 4.0 - float((p-goal).length_squared())*0.04)
		if p == e.pos: rough += 1.0
		scored.append({"pos":p,"score":rough})
	scored.sort_custom(func(a,b): return a.score > b.score if a.score != b.score else key(a.pos) < key(b.pos))
	var out = []
	for item in scored.slice(0,limit): out.append(item.pos)
	if e.pos not in out: out.append(e.pos)
	return out
static func next_ready(e: Dictionary, acted: bool, context: Dictionary) -> bool:
	if e.get("stun",0) > 0: return false
	var cd = int(e.get("period",3)) if acted else int(e.get("cd",3))
	var credits = int(e.get("action_credits",0))
	if context.get("next_rotation_uid",-1) == e.get("uid",-2): credits += 1
	return cd <= 1 or (context.get("credit_mode",false) and credits > 0 and int(e.get("action_credit_delay",0)) <= 0)
static func advance_projection(board: Array, ready: Dictionary, context: Dictionary, player: Vector2i) -> Array:
	var out = []
	for actor in board:
		var e = actor.duplicate()
		if e.kind == "stake" and not e.get("permanent",false):
			e.ttl = int(e.get("ttl",3))-1
			if e.ttl <= 0: continue
		if ready.has(e.get("uid",-1)):
			e.cd = int(e.get("period",3))
			if context.get("credit_ready",{}).get(e.uid,false) and (context.get("projected_spent",{}).get(e.uid,false) or not moves(e,board,player).is_empty()): e.action_credits = maxi(0,int(e.get("action_credits",0))-1)
		e.stun = maxi(0,int(e.get("stun",0))-1)
		out.append(e)
	return out
static func plan(board: Array, player: Vector2i, ready: Dictionary, context: Dictionary = {}) -> Dictionary:
	var result = {"order":[],"targets":{},"stats":{"evaluations":0,"joint":0,"lookahead":0,"rook_scores":0}}
	if ready.is_empty(): return result
	var projected = board.duplicate(true);var locked = {}
	# The general owns its defensive decision, including a deliberate hold. It is
	# never a disposable cannon screen, and uses only its existing ready action.
	for general in board:
		if general.kind != "g" or not ready.has(general.uid): continue
		var destination = GE.defend(general,moves(general,projected,player),projected,player,context)
		if destination == NONE: continue
		result.order.append(general.uid);result.targets[general.uid]=destination
		locked[general.uid]=true;projected=placed(projected,general.uid,destination)
	var aim = targets(projected,player,context)
	var cannons = []
	for e in board:
		if e.kind == "c" and e.get("stun",0) == 0: cannons.append(e.uid)
	cannons.sort()
	for cannon_uid in cannons.slice(0,MAX_CANNONS):
		if locked.has(cannon_uid): continue
		var limit = mini(MAX_EVALUATIONS, result.stats.evaluations + MAX_EVALUATIONS / MAX_CANNONS)
		var joint_limit = mini(limit, result.stats.evaluations + 100)
		var ci = by_uid(projected,cannon_uid)
		var cannon = projected[ci]
		var can_move = ready.has(cannon_uid)
		var current = value(cannon,projected,aim,ready,locked)
		var defense_before = GE.guard_state(projected,player,context)
		var choices = moves(cannon,projected,player) if can_move else []
		choices.append(cannon.pos)
		var candidates = [];var seen_pairs = {}
		var protected_lines = []
		var original_occ = occupancy(projected,0)
		for other in projected:
			if other.kind != "c" or other.uid == cannon_uid or other.get("stun",0)>0: continue
			for cell in aim:
				var goal = Vector2i(cell%9,cell/9)
				if not screen(other.pos,goal,original_occ).is_empty(): protected_lines.append({"from":other.pos,"to":goal,"weight":aim[cell]})
		for destination in choices:
			if result.stats.evaluations >= limit: break
			var candidate_board = placed(projected,cannon_uid,destination)
			if not GE.preserves_guard_state(defense_before,candidate_board,player,context): continue
			var fixed = locked.duplicate();fixed[cannon_uid] = true
			var v = value(candidate_board[ci],candidate_board,aim,ready,fixed)
			var score = v + general_barrier(candidate_board,player,context) + setup_value(candidate_board[ci],candidate_board,aim) - movement_penalty(cannon,destination,current,v,player,projected)
			candidates.append({"board":candidate_board,"score":score,"value":v,"steps":[{"uid":cannon_uid,"pos":destination}] if can_move else [],"fixed":fixed})
			result.stats.evaluations += 1
		# Combine with a single independently ready support, in BOTH legal orders.
		var supports = [];var future_supports = []
		for e in projected:
			if e.uid == cannon_uid or e.kind in ["stake","c","g"] or locked.has(e.uid): continue
			var priority = 20 if e.kind in ["p","q"] else (0 if e.kind in ["a","g"] else 10)
			priority -= absi(e.pos.x-cannon.pos.x)+absi(e.pos.y-cannon.pos.y)
			future_supports.append({"uid":e.uid,"score":priority})
			if ready.has(e.uid): supports.append({"uid":e.uid,"score":priority})
		supports.sort_custom(func(a,b): return a.score>b.score if a.score != b.score else a.uid<b.uid)
		future_supports.sort_custom(func(a,b): return a.score>b.score if a.score != b.score else a.uid<b.uid)
		var cannon_options = ranked_options(cannon,projected,player,aim,CANNON_BEAM) if can_move else [cannon.pos]
		for support_info in supports.slice(0,SUPPORT_LIMIT):
			if result.stats.evaluations >= joint_limit: break
			var si = by_uid(projected,support_info.uid);var support = projected[si]
			# A rook is not a disposable cannon screen: compare the joint landing
			# with its best independent one-stage control on this actual board.
			var rook_best = -INF;var rook_before = 0.0
			var barrier_before = general_barrier(projected,player,context)
			if support.kind == "r":
				var rook_options = moves(support,projected,player);rook_options.append(support.pos)
				if result.stats.evaluations+rook_options.size()>=joint_limit: continue
				for rp in rook_options:
					var rb = placed(projected,support.uid,rp)
					var rook_position_score = RT.position_score(rb[si],rb,player,context)
					rook_best = maxf(rook_best,rook_position_score)
					if rp==support.pos: rook_before=rook_position_score+RT.distance_cost(support,player)
					result.stats.evaluations+=1;result.stats.rook_scores+=1
			for support_first in [true,false]:
				if result.stats.evaluations >= joint_limit: break
				var first = support if support_first else cannon
				var first_options = ranked_options(first,projected,player,aim,SUPPORT_BEAM) if support_first else cannon_options
				for first_target in first_options:
					if result.stats.evaluations >= joint_limit: break
					if first.uid == cannon_uid and not can_move and first_target != cannon.pos: continue
					var intermediate = placed(projected,first.uid,first_target)
					if not GE.preserves_guard_state(defense_before,intermediate,player,context): continue
					var second = cannon if support_first else support
					var second_options = ranked_options(second,intermediate,player,aim,CANNON_BEAM if support_first else SUPPORT_BEAM) if second.uid != cannon_uid or can_move else [cannon.pos]
					for second_target in second_options:
						if result.stats.evaluations+(1 if support.kind=="r" else 0) >= joint_limit: break
						var cp: Vector2i = first_target if first.uid == cannon_uid else second_target
						var sp: Vector2i = first_target if first.uid == support.uid else second_target
						var layout_key = Vector3i(key(cp),support.uid,key(sp))
						if seen_pairs.has(layout_key): continue
						seen_pairs[layout_key]=true
						var trial = placed(intermediate,second.uid,second_target)
						if not GE.preserves_guard_state(defense_before,trial,player,context): continue
						var fixed = locked.duplicate();fixed[cannon_uid]=true;fixed[support.uid]=true
						var v = value(trial[ci],trial,aim,ready,fixed)
						var barrier_after = general_barrier(trial,player,context)
						var rook_after = RT.value(trial[si],trial,player,context) if support.kind=="r" else 0.0
						var support_cost = RT.move_cost(support,sp,rook_before,rook_after,barrier_after>barrier_before) if support.kind=="r" else movement_penalty(support,sp,current,v,player,projected)
						var score = v + barrier_after + setup_value(trial[ci],trial,aim) - movement_penalty(cannon,cp,current,v,player,projected) - support_cost - 1.5
						if support.kind == "r":
							score -= maxf(0.0,rook_best-(rook_after-RT.distance_cost(trial[si],player)))
							result.stats.evaluations+=1;result.stats.rook_scores+=1
							# Also retain other real firing formations; the cannon currently
							# being planned is not the only line a second screen can spoil.
							if not protected_lines.is_empty():
								var trial_occ = occupancy(trial,0)
								for line in protected_lines:
									if screen(line.from,line.to,trial_occ).is_empty(): score-=float(line.weight)*1.25
						var steps = []
						if ready.has(first.uid): steps.append({"uid":first.uid,"pos":first_target})
						if ready.has(second.uid): steps.append({"uid":second.uid,"pos":second_target})
						candidates.append({"board":trial,"score":score,"value":v,"steps":steps,"fixed":fixed})
						result.stats.evaluations += 1;result.stats.joint += 1
		candidates.sort_custom(func(a,b): return a.score > b.score)
		# Two enemy-stage beam: only actors actually ready next phase can relocate.
		var future_candidates = [];var seen_destinations = {}
		for candidate in candidates:
			# A useful immediate firing formation does not need speculative expansion.
			if candidates[0].value >= 110.0: break
			var destination_key = key(candidate.board[ci].pos)
			if seen_destinations.has(destination_key): continue
			seen_destinations[destination_key] = true;future_candidates.append(candidate)
			if future_candidates.size() >= SECOND_BEAM: break
		for candidate in future_candidates:
			if result.stats.evaluations >= limit: break
			var forecast_context = context.duplicate();var spent = {};var before_steps = projected
			for step in candidate.steps:
				var actor = before_steps[by_uid(before_steps,step.uid)]
				spent[step.uid] = step.pos != actor.pos or not moves(actor,before_steps,player).is_empty()
				before_steps = placed(before_steps,step.uid,step.pos)
			forecast_context.projected_spent = spent
			var future = advance_projection(candidate.board,ready,forecast_context,player)
			var future_defense = GE.guard_state(future,player,context)
			var fci = by_uid(future,cannon_uid);var future_cannon = future[fci]
			var future_ready = {}
			for actor in future:
				if actor.kind != "stake" and next_ready(actor,false,context) and not R.attacks(actor,player,future): future_ready[actor.uid]=true
			var future_fixed = {cannon_uid:true}
			var options = ranked_options(future_cannon,future,player,aim,3) if future_ready.has(cannon_uid) else []
			options.append(future_cannon.pos)
			var best_future = value(future_cannon,future,aim,future_ready,future_fixed,0)
			for p in options:
				if result.stats.evaluations >= limit: break
				var future_board = placed(future,cannon_uid,p)
				if not GE.preserves_guard_state(future_defense,future_board,player,context): continue
				best_future = maxf(best_future,value(future_board[fci],future_board,aim,future_ready,future_fixed,0))
				result.stats.evaluations += 1;result.stats.lookahead += 1
			# One support can establish the second-stage screen while cannon waits.
			for support_info in future_supports.slice(0,SUPPORT_LIMIT):
				if result.stats.evaluations >= limit: break
				var si = by_uid(future,support_info.uid)
				if si < 0: continue
				var support = future[si]
				if not future_ready.has(support.uid): continue
				for p in ranked_options(support,future,player,aim,2):
					if result.stats.evaluations >= limit: break
					var future_board = placed(future,support.uid,p)
					if not GE.preserves_guard_state(future_defense,future_board,player,context): continue
					var support_fixed = future_fixed.duplicate();support_fixed[support.uid]=true
					best_future = maxf(best_future,value(future_board[fci],future_board,aim,future_ready,support_fixed,0))
					result.stats.evaluations += 1;result.stats.lookahead += 1
			candidate.score += maxf(0.0,best_future-candidate.value)*0.6
			candidate.future = future;candidate.future_ready = future_ready;candidate.best_future = best_future
		# Give every retained destination its single-actor forecast before joint extensions.
		future_candidates.sort_custom(func(a,b): return a.score>b.score)
		for candidate in future_candidates.slice(0,3):
			if result.stats.evaluations >= limit or not candidate.has("future"): break
			var future = candidate.future;var future_ready = candidate.future_ready
			var future_defense = GE.guard_state(future,player,context)
			var fci = by_uid(future,cannon_uid);var future_cannon = future[fci]
			var best_future = candidate.best_future
			# A bounded second-stage joint pair, again checking BOTH sequential orders.
			# This is a forecast, not a reservation or a player-position commitment.
			if future_ready.has(cannon_uid):
				for support_info in future_supports.slice(0,2):
					if result.stats.evaluations >= limit: break
					var si = by_uid(future,support_info.uid)
					if si < 0 or not future_ready.has(support_info.uid): continue
					var support = future[si]
					for support_first in [true,false]:
						if result.stats.evaluations >= limit: break
						var first = support if support_first else future_cannon
						var second = future_cannon if support_first else support
						for first_target in ranked_options(first,future,player,aim,3):
							if result.stats.evaluations >= limit: break
							var intermediate = placed(future,first.uid,first_target)
							if not GE.preserves_guard_state(future_defense,intermediate,player,context): continue
							for second_target in ranked_options(second,intermediate,player,aim,3):
								if result.stats.evaluations >= limit: break
								var trial = placed(intermediate,second.uid,second_target)
								if not GE.preserves_guard_state(future_defense,trial,player,context): continue
								var fixed = {cannon_uid:true,support.uid:true}
								best_future = maxf(best_future,value(trial[fci],trial,aim,future_ready,fixed,0)-5.0)
								result.stats.evaluations += 1;result.stats.lookahead += 1
			candidate.score += maxf(0.0,best_future-candidate.best_future)*0.6
		candidates.sort_custom(func(a,b): return a.score>b.score)
		var best = candidates[0]
		# Irrelevant cannon lines may relocate; don't force unrelated pieces to hold.
		var executing = projected
		for step in best.steps:
			var original = executing[by_uid(executing,step.uid)]
			if step.pos == original.pos and moves(original,executing,player).is_empty(): continue
			result.order.append(step.uid);result.targets[step.uid]=step.pos;locked[step.uid]=true
			executing = placed(executing,step.uid,step.pos)
		projected = best.board
	# Resolve remaining actors after joint groups, preserving current valuable cannon lines.
	for e in board:
		if ready.has(e.uid) and e.uid not in result.order: result.order.append(e.uid)
	return result

static func remember(e: Dictionary, origin: Vector2i):
	var recent: Array = e.get("ai_recent",[]).duplicate()
	recent.push_front(origin)
	if recent.size()>2: recent.resize(2)
	e.ai_recent = recent
