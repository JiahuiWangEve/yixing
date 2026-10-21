extends SceneTree
const RT = preload("res://rook_tactics.gd")
const AI = preload("res://enemy_ai.gd")
const CP = preload("res://cannon_planner.gd")
const R = preload("res://rules.gd")
var checks = 0
var failures = 0
var game
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
func piece(uid: int, kind: String, x: int, y: int, cd: int = 3) -> Dictionary:
	return {"uid":uid,"kind":kind,"pos":Vector2i(x,y),"stun":0,"cd":cd,"period":3}
func cells(targets: Dictionary, player: Vector2i) -> Array:
	var out = targets.keys();out.erase(player);out.sort();return out
func same_cells(actual: Array, expected: Array) -> bool:
	var ordered = expected.duplicate();ordered.sort();return actual == ordered
func choice(board: Array, player: Vector2i, options: Array = [], context: Dictionary = {}, allow_hold: bool = true) -> Vector2i:
	var rng = RandomNumberGenerator.new();rng.seed = 77123
	return AI.choose(board[0],R.moves(board[0],board,player) if options.is_empty() else options,board,player,rng,context,allow_hold)
func reach_checks():
	var player = Vector2i(4,5)
	var board = [piece(1,"r",0,0),piece(2,"stake",5,5),piece(3,"stake",4,4),piece(4,"stake",3,7)]
	check(same_cells(cells(RT.targets(board,player),player),[Vector2i(3,5),Vector2i(4,6)]),"king exits respect occupied destinations")
	check(same_cells(cells(RT.targets(board,player,{"player_skill":"horse"}),player),[Vector2i(5,7),Vector2i(2,6),Vector2i(2,4)]),"horse exits contain only actual jumps and respect both legs and destinations")
	check(same_cells(cells(RT.targets(board,player,{"player_skill":"artillery","artillery_mode":"march"}),player),[Vector2i(3,5),Vector2i(2,5),Vector2i(4,6),Vector2i(4,7)]),"march artillery exits respect every traversed square")
	check(same_cells(cells(RT.targets(board,player,{"player_skill":"artillery","artillery_mode":"attack"}),player),[Vector2i(3,5),Vector2i(4,6)]),"attack artillery has only one-cell exits")
	board = [piece(1,"r",0,9),piece(2,"g",4,0)];player = Vector2i(4,3)
	check(RT.targets(board,player).get(Vector2i(4,2),0) > RT.targets(board,player).get(Vector2i(3,3),0),"reachable unobstructed general approach has extra weight")
	board.append(piece(3,"stake",4,1))
	check(RT.targets(board,player).get(Vector2i(4,2),0) == RT.targets(board,player).get(Vector2i(3,3),0),"blocked spear approach has no imaginary general threat")
	var artillery={"player_skill":"artillery","artillery_mode":"attack"}
	board=[piece(1,"r",0,9),piece(2,"g",4,0)];player=Vector2i(4,3)
	check(RT.targets(board,player,artillery).get(Vector2i(4,2),0)==28.0,"artillery does not invent an unscreened two-cell spear")
	board.append(piece(3,"stake",4,2));player=Vector2i(4,4)
	check(RT.targets(board,player,artillery).get(Vector2i(4,3),0)==42.0,"artillery general approach recognizes a real one-screen shot beyond two cells")
	board.append(piece(4,"stake",4,1))
	check(RT.targets(board,player,artillery).get(Vector2i(4,3),0)==28.0,"second blocker removes artillery general-approach bonus")
	board=[piece(1,"r",0,9),piece(2,"g",4,0)];player=Vector2i(4,2)
	check(RT.targets(board,player,artillery).get(Vector2i(4,1),0)==42.0,"artillery still recognizes its public adjacent sword approach")
	# Cross-check every public free-move rule against the real game implementation.
	var rng = RandomNumberGenerator.new();rng.seed = 99413
	var matched = true;var comparisons = 0
	for sample in 12:
		game.player = Vector2i(rng.randi_range(0,8),rng.randi_range(0,9));game.enemies=[];game.basic_used=false
		for i in 8:
			var p = Vector2i(rng.randi_range(0,8),rng.randi_range(0,9))
			while p == game.player or R.occupied(p,game.enemies) >= 0: p = Vector2i(rng.randi_range(0,8),rng.randi_range(0,9))
			game.enemies.append(piece(i+1,"stake",p.x,p.y))
		for profile in [["king","march"],["horse","march"],["artillery","march"],["artillery","attack"]]:
			game.player_skill=profile[0];game.artillery_mode=profile[1]
			var aim=RT.targets(game.enemies,game.player,{"player_skill":profile[0],"artillery_mode":profile[1]})
			for y in 10:
				for x in 9:
					var p=Vector2i(x,y)
					if p == game.player: continue
					comparisons+=1
					if aim.has(p) != game.basic_legal(p): matched=false
	check(matched,"rook reachable targets equal real public moves across "+str(comparisons)+" seeded profile/cell comparisons")
func control_checks():
	var player=Vector2i(4,5);var board=[piece(1,"r",0,0)]
	var options=[Vector2i(4,0),Vector2i(0,5)]
	check(choice(board,player,options)==Vector2i(4,0),"equivalent control prefers the farther safe firing lane")
	var reversed_options=options.duplicate();reversed_options.reverse()
	check(choice(board,player,reversed_options)==Vector2i(4,0),"safe-distance tie is independent of candidate order")
	board.append(piece(2,"r",4,9))
	check(choice(board,player,options)==Vector2i(0,5),"second rook adds uncovered exits instead of duplicating an allied file")
	var saved=board.duplicate(true);var decision=choice(board,player)
	check(board==saved,"rook decision does not mutate board history cooldown or credits")
	board.reverse()
	var rng=RandomNumberGenerator.new();rng.seed=9
	check(AI.choose(board[1],R.moves(board[1],board,player),board,player,rng)==decision,"marginal coverage does not depend on allied array order")
	var interception=[piece(1,"r",2,7),piece(2,"r",4,9)]
	check(choice(interception,Vector2i(4,2),[Vector2i(4,7),Vector2i(2,2)])==Vector2i(2,2),"interposing on an allied rook lane does not falsely create marginal coverage")
	board=[piece(1,"r",0,0),piece(2,"p",4,3)]
	check(choice(board,player,options)==Vector2i(0,5),"blocked file earns no fictitious beyond-blocker coverage")
	board=[piece(1,"r",3,4),piece(2,"r",4,9),piece(3,"h",6,3)]
	check(choice(board,player)==Vector2i(3,4),"useful complementary exit coverage deliberately holds")
	check(choice(board,player,[],{},false)!=Vector2i(3,4),"explicit no-hold action cannot become voluntary hold")
	board[0].stun=1
	check(choice(board,player)==Vector2i(-1,-1) and RT.value(board[0],board,player)==0,"frozen rook neither acts nor contributes threat")
	board=[piece(1,"r",0,9),piece(2,"g",4,0)];player=Vector2i(4,2)
	board[0].ai_recent=[Vector2i(0,2)]
	check(choice(board,player)==Vector2i(0,2),"obsolete frontline relocates to newly useful row despite old return history")
	var bare=piece(1,"r",0,0)
	check(RT.move_cost(bare,Vector2i(4,0),0,100)==0,"zero-value old line receives no inertia penalty")
	bare.ai_recent=[Vector2i(4,0)]
	check(RT.move_cost(bare,Vector2i(4,0),40,45)>RT.move_cost(bare,Vector2i(4,0),40,100),"small repeated gain penalized but meaningful improvement overrides return inertia")
func barrier_and_cannon_checks():
	var board=[piece(1,"r",0,1),piece(2,"g",4,0)];var player=Vector2i(4,2)
	check(choice(board,player)==Vector2i(4,1),"rook chooses legal true spear-blocking midpoint")
	var rescued=CP.placed(board,1,Vector2i(4,1))
	check(CP.general_barrier(rescued,player)>0,"real rook body provides a two-cell general barrier")
	check(CP.general_barrier(rescued,player,{"player_skill":"artillery"})==0,"single body is not a rescue against artillery")
	check(CP.general_barrier(rescued,Vector2i(5,0))==0 and CP.general_barrier(rescued,Vector2i(5,1))==0,"adjacent and diagonal general danger have no imagined blocking square")
	board.append(piece(3,"stake",2,1))
	var destination=choice(board,player)
	check(destination!=Vector2i(4,1) and (destination==board[0].pos or destination in R.moves(board[0],board,player)),"rook cannot teleport through blocker to rescue general")
	board=[piece(3,"r",8,5),piece(1,"c",0,0),piece(2,"h",0,3)];player=Vector2i(0,8)
	check(choice(board,player,[Vector2i(0,5),Vector2i(8,8)])==Vector2i(8,8),"rook preserves existing cannon shot instead of becoming a second screen")
	var original=board.duplicate(true);var plan=CP.plan(board,player,{3:true});var sequential=true
	for uid in plan.order:
		if not plan.targets.has(uid): continue
		var i=CP.by_uid(board,uid);var target=plan.targets[uid]
		if target!=board[i].pos and target not in R.moves(board[i],board,player): sequential=false
		board=CP.placed(board,uid,target)
	check(sequential,"mixed cannon-rook plan remains sequentially legal")
	var ci=CP.by_uid(board,1)
	check(R.attacks(board[ci],player,board),"cannon coordination retains established real firing formation")
	check(original[0].pos==Vector2i(8,5),"cannon coordination does not mutate original rook object")
func fast_and_budget_checks():
	var rng=RandomNumberGenerator.new();rng.seed=829921
	var matched=true;var comparisons=0
	for sample in 10:
		var board=[]
		for i in 12:
			var p=Vector2i(rng.randi_range(0,8),rng.randi_range(0,9))
			while R.occupied(p,board)>=0: p=Vector2i(rng.randi_range(0,8),rng.randi_range(0,9))
			var actor=piece(i+1,["r","c","h","p","q","a","e","g","stake"][i%9],p.x,p.y)
			actor.stun=1 if (i+sample)%7==0 else 0;board.append(actor)
		var occ=RT.occupancy(board)
		for actor in board:
			for y in range(-1,11):
				for x in range(-1,10):
					var p=Vector2i(x,y);comparisons+=1
					if RT.attacks(actor,p,board,occ)!=R.attacks(actor,p,board): matched=false
	check(matched,"fast rook threat geometry equals R.attacks across "+str(comparisons)+" occupied in/out-of-bounds cells")
	var stress=[piece(1,"c",0,0),piece(2,"c",8,0),piece(3,"c",0,9),piece(4,"c",8,9),piece(5,"r",2,2),piece(6,"r",6,2),piece(7,"r",2,7),piece(8,"r",6,7),piece(9,"p",2,4),piece(10,"p",6,4),piece(11,"p",3,6),piece(12,"p",5,6),piece(13,"g",4,0)]
	var ready={};var credit_ready={}
	for e in stress: e.period=1;e.cd=0;e.action_credits=3;e.action_credit_delay=0;ready[e.uid]=true;credit_ready[e.uid]=true
	var samples=[];var plan={}
	for repetition in 3:
		var start=Time.get_ticks_usec();plan=CP.plan(stress,Vector2i(4,5),ready,{"credit_mode":true,"credit_ready":credit_ready});samples.append(Time.get_ticks_usec()-start)
	samples.sort();print("MIXED ROOK CANNON median_us=",samples[1]," max_us=",samples[2]," stats=",plan.stats)
	check(plan.stats.evaluations<=CP.MAX_EVALUATIONS and plan.stats.get("rook_scores",0)>0,"mixed four-cannon four-rook planning counts rook scores inside hard phase budget")
	var moved={};var legal=true;var projected=stress.duplicate(true)
	for uid in plan.order:
		if moved.has(uid): legal=false
		moved[uid]=true
		if not plan.targets.has(uid): continue
		var i=CP.by_uid(projected,uid);var target=plan.targets[uid]
		if target!=projected[i].pos and target not in R.moves(projected[i],projected,Vector2i(4,5)): legal=false
		projected=CP.placed(projected,uid,target)
	check(legal,"budgeted mixed plan remains legal with at most one reserved action per actor")
func runtime_fixture(player: Vector2i):
	game.tutorial.stop();game.player_skill="king";game.new_run()
	game.enemies=[];game.player=player;game.lives=100;game.hand=[];game.hand_ids=[];game.deck=[];game.discard=[]
	game.encounter_state={"config":{"id":"palace_final","tier":"boss","rules":[]},"phases":0,"guard_uids":[],"retaliated":false,"river_triggered":false,"signal_uid":-1,"cannon_uid":-1,"spawn_cell":Vector2i(-1,-1)}
	game.clear_effects();game.navigation_lock=0;game.phase="play";game.screen="game";game.history.clear();game.rng.seed=321
func add(kind: String, pos: Vector2i, period: int = 3) -> Dictionary:
	game.add_enemy(kind,pos,period);return game.enemies.back()
func movement_count(uid: int) -> int:
	var count=0
	for fx in game.effects:
		if fx.kind=="move" and fx.get("piece",{}).get("uid",-1)==uid: count+=1
	return count
func runtime_checks():
	runtime_fixture(Vector2i(4,5))
	var rook=add("r",Vector2i(3,4));rook.cd=3;rook.action_credits=2;rook.action_credit_delay=0
	add("r",Vector2i(4,9),999);add("h",Vector2i(6,3),999);game.shield_charges=1
	var before=game.history.capture();game.end_turn()
	check(rook.pos==Vector2i(3,4) and movement_count(rook.uid)==0,"runtime ready rook deliberately holds useful complementary coverage")
	check(rook.action_credits==1 and rook.cd==rook.period,"rook hold consumes exactly one boss credit and resets cooldown")
	check(game.player==Vector2i(4,5) and game.lives==100,"shield preserves current-player fixture while existing attacker does not move")
	var after=game.history.capture()
	check(game.history.undo() and game.history.capture()==before,"undo restores rook hold board credits and RNG")
	game.end_turn();check(game.history.capture()==after,"hold replay deterministically reproduces exact state")
	runtime_fixture(Vector2i(4,5));rook=add("r",Vector2i(0,0));rook.action_credits=3;rook.action_credit_delay=0
	game.end_turn()
	check(movement_count(rook.uid)==1 and rook.action_credits==2,"three banked boss credits still permit only one rook move in a phase")
	check(game.lives==100 and R.attacks(rook,game.player,game.enemies),"rook establishes new threat without moving and shooting in same phase")
	game.clear_effects();game.end_turn()
	check(game.lives==99 and movement_count(rook.uid)==0 and rook.action_credits==2,"existing rook attack takes precedence over move and preserves credit")
	runtime_fixture(Vector2i(4,5));rook=add("r",Vector2i(0,0));rook.action_credits=2;rook.stun=1
	game.end_turn();check(rook.pos==Vector2i(0,0) and rook.action_credits==2 and rook.stun==0,"freeze prevents rook action and preserves credits until next phase")
	runtime_fixture(Vector2i(8,9));rook=add("r",Vector2i(0,0));rook.action_credits=2
	var right=add("stake",Vector2i(1,0),999);right.permanent=true
	var down=add("stake",Vector2i(0,1),999);down.permanent=true
	game.end_turn();check(rook.pos==Vector2i(0,0) and rook.action_credits==2 and movement_count(rook.uid)==0,"boxed rook cannot count inability to move as a paid hold")
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game)
	reach_checks();control_checks();barrier_and_cannon_checks();fast_and_budget_checks();runtime_checks()
	print("ROOK TACTICS RESULT ",checks-failures," passed, ",failures," failed")
	game.queue_free();quit(1 if failures else 0)
