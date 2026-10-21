extends RefCounted
# One-stage, public-board control only. No hand/deck inspection or path search.
const R = preload("res://rules.gd")
const ORTHOGONAL = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const HORSE = [Vector2i(1,2),Vector2i(2,1),Vector2i(-1,2),Vector2i(-2,1),Vector2i(1,-2),Vector2i(2,-1),Vector2i(-1,-2),Vector2i(-2,-1)]

static func occupancy(board: Array) -> Dictionary:
	var out={}
	for e in board: out[e.pos]=true
	return out

static func line_blockers(a: Vector2i, b: Vector2i, occ: Dictionary) -> int:
	if a==b or (a.x!=b.x and a.y!=b.y): return 99
	var step=Vector2i(signi(b.x-a.x),signi(b.y-a.y))
	var cursor=a+step;var count=0
	while cursor!=b:
		if occ.has(cursor): count+=1
		cursor+=step
	return count

static func attacks(e: Dictionary, p: Vector2i, board: Array, occ: Dictionary) -> bool:
	if not R.inside(p) or e.get("stun",0)>0 or e.pos==p: return false
	if e.kind in ["r","c"]: return line_blockers(e.pos,p,occ)==(1 if e.kind=="c" else 0)
	return R.attacks(e,p,board)

static func targets(board: Array, player: Vector2i, context: Dictionary = {}, occ: Dictionary = {}) -> Dictionary:
	if occ.is_empty(): occ=occupancy(board)
	var out = {player: 110.0}
	var skill = context.get("player_skill","king")
	var deltas = HORSE.duplicate() if skill == "horse" else ORTHOGONAL.duplicate()
	if skill == "artillery" and context.get("artillery_mode","march") != "attack":
		for d in ORTHOGONAL: deltas.append(d*2)
	for d in deltas:
		var p: Vector2i = player+d
		if not R.inside(p) or occ.has(p): continue
		if maxi(absi(d.x),absi(d.y))==2:
			var leg = player+Vector2i(signi(d.x) if absi(d.x)==2 else 0,signi(d.y) if absi(d.y)==2 else 0)
			if occ.has(leg): continue
		var weight = 28.0
		# Emphasize reachable squares from which a public basic attack reaches the
		# general. Far palace squares and squares beyond blockers are not coverage.
		for e in board:
			if e.kind != "g": continue
			var delta: Vector2i = e.pos-p
			var distance = absi(delta.x)+absi(delta.y)
			if delta.x==0 or delta.y==0:
				var blockers=line_blockers(p,e.pos,occ)
				var attack = (distance in [1,2] and blockers==0) if skill!="artillery" else (distance==1 or blockers==1)
				if attack: weight=42.0
		out[p]=weight
	return out

static func value(rook: Dictionary, board: Array, player: Vector2i, context: Dictionary = {}) -> float:
	if rook.get("stun",0)>0: return 0.0
	var score=0.0
	var occ=occupancy(board)
	var aim=targets(board,player,context,occ)
	# Remove the evaluating rook from the ally baseline. Otherwise stepping in
	# front of an allied rook would hide its ray and falsely claim fresh cover.
	var allies=[]
	for ally in board:
		if ally.get("uid",-1)!=rook.get("uid",-1): allies.append(ally)
	var ally_occ=occ.duplicate();ally_occ.erase(rook.pos)
	for p in aim:
		if not attacks(rook,p,board,occ): continue
		var covered=false
		for ally in allies:
			if ally.kind=="stake": continue
			if attacks(ally,p,allies,ally_occ): covered=true;break
		# Threatening the player still matters, but sealing a genuinely new exit
		# is substantially better than duplicating a horse's existing control.
		score+=float(aim[p])*(0.3 if covered else 1.0)
	return score

static func distance_cost(rook: Dictionary, player: Vector2i) -> float:
	var d: Vector2i=rook.pos-player
	var distance=absi(d.x)+absi(d.y)
	# Public sword/spear geometry, not the player's actual hand. Bounded so
	# distance is a preference, never a reason to abandon meaningful control.
	if distance==1: return 12.0
	if distance==2 and (d.x==0 or d.y==0): return 5.0
	return 1.0/float(maxi(1,distance))

static func position_score(rook: Dictionary, board: Array, player: Vector2i, context: Dictionary = {}) -> float:
	return value(rook,board,player,context)-distance_cost(rook,player)

static func move_cost(rook: Dictionary, target: Vector2i, old_value: float, new_value: float, emergency: bool = false) -> float:
	if target==rook.pos: return 0.0
	var cost=1.5 if old_value>0 else 0.0
	if not emergency and old_value>0 and new_value<old_value+20 and target in rook.get("ai_recent",[]): cost+=6.0
	return cost
