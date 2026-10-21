extends SceneTree
const CP = preload("res://cannon_planner.gd")
const R = preload("res://rules.gd")
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
func piece(uid: int, kind: String, x: int, y: int, cd: int = 3) -> Dictionary:
	return {"uid":uid,"kind":kind,"pos":Vector2i(x,y),"stun":0,"cd":cd,"period":3}
func apply(board: Array, player: Vector2i, plan: Dictionary) -> Array:
	var out = board.duplicate(true)
	for uid in plan.order:
		if not plan.targets.has(uid): continue
		var i = CP.by_uid(out,uid);var destination = plan.targets[uid]
		check(destination == out[i].pos or destination in R.moves(out[i],out,player), "sequential plan legality uid="+str(uid))
		out[i].pos = destination
	return out
func _initialize(): call_deferred("run")
func run():
	var fixtures = [
		[piece(1,"c",0,0),piece(2,"p",2,4),Vector2i(4,5)],
		[piece(1,"c",0,0),piece(2,"h",0,4),Vector2i(4,5)],
		[piece(1,"c",0,4),piece(2,"h",2,3),Vector2i(0,8)]]
	for n in fixtures.size():
		var f = fixtures[n];var board = [f[0],f[1]];var player = f[2]
		var solo = false
		for i in 2:
			for p in R.moves(board[i],board,player):
				var test = board.duplicate(true);test[i].pos = p
				if R.attacks(test[0],player,test): solo = true
		check(not solo,"joint fixture "+str(n)+" cannot solve alone")
		var plan = CP.plan(board,player,{1:true,2:true})
		var final_board = apply(board,player,plan)
		print("JOINT ",n," ",plan)
		check(R.attacks(final_board[0],player,final_board),"joint fixture "+str(n)+" produces direct threat")
		var reversed = board.duplicate(true);reversed.reverse()
		var reverse_plan = CP.plan(reversed,player,{1:true,2:true})
		check(plan.targets == reverse_plan.targets and plan.order == reverse_plan.order,"joint array order independence "+str(n))
	# Existing useful line, ready supporter must hold instead of destroying it.
	var hold_board = [piece(1,"c",0,0),piece(2,"h",0,3)]
	var hold = CP.plan(hold_board,Vector2i(0,8),{2:true})
	check(hold.targets.get(2,Vector2i(-1,-1)) == Vector2i(0,3),"ready supporter deliberately holds useful screen")
	var stable = CP.plan(hold_board,Vector2i(0,8),{1:true})
	check(stable.targets.get(1,Vector2i(-1,-1)) == Vector2i(0,0),"cannon holds useful stable line")
	var old_line = [piece(1,"c",0,8),piece(2,"stake",2,8),piece(3,"stake",2,1),piece(4,"g",4,0)]
	old_line[1].permanent = true;old_line[2].permanent = true
	var relocation = CP.plan(old_line,Vector2i(5,1),{1:true})
	var relocated = apply(old_line,Vector2i(5,1),relocation)
	check(relocated[0].pos != old_line[0].pos and R.attacks(relocated[0],Vector2i(5,1),relocated),"obsolete frontline relocates to relevant rear flank")
	# Real cooldowns determine second-stage eligibility, not generic two moves.
	var future_board = [piece(1,"c",0,0),piece(2,"p",2,4,1)]
	var future = CP.plan(future_board,Vector2i(4,5),{1:true})
	print("FUTURE ",future)
	check(future.targets.get(1,Vector2i(-1,-1)) == Vector2i(0,5),"two-stage cannon prepares next-phase pawn screen")
	check(CP.next_ready(future_board[1],false,{}) and not CP.next_ready(piece(2,"p",2,4,3),false,{}),"cooldown 1 vs 3 next-stage availability")
	var delayed = piece(2,"p",2,4,3);delayed.action_credits=1;delayed.action_credit_delay=2
	check(not CP.next_ready(delayed,false,{"credit_mode":true}),"delayed credit cannot teleport second-stage readiness")
	delayed.action_credit_delay=0
	check(CP.next_ready(delayed,false,{"credit_mode":true}),"available carry credit permits second-stage move")
	delayed.stun=2
	check(not CP.next_ready(delayed,false,{"credit_mode":true}),"freeze overrides carried credit")
	var ttl_board = [piece(1,"c",0,0),piece(2,"stake",0,3)]
	ttl_board[1].ttl=1
	var aim = {CP.key(Vector2i(0,8)):110.0}
	check(CP.value(ttl_board[0],ttl_board,aim,{}, {}) == 0,"expiring stake gives no next-attack threat")
	ttl_board[1].ttl=2
	check(CP.value(ttl_board[0],ttl_board,aim,{}, {}) > 0 and CP.value(ttl_board[0],ttl_board,aim,{}, {},1) == 0,"ttl2 useful now but not two-stage horizon")
	ttl_board[1].permanent=true
	check(CP.value(ttl_board[0],ttl_board,aim,{}, {},1) > 0,"permanent stake remains reliable")
	var double_board = hold_board.duplicate(true);double_board.append(piece(3,"p",0,5))
	check(CP.value(double_board[0],double_board,aim,{}, {}) == 0,"second blocker eliminates threat")
	check(not CP.legal(hold_board[0],Vector2i(0,5),hold_board,Vector2i(0,8)),"cannon may not jump occupied screen")
	var no_screen = [piece(1,"c",0,0)]
	var fallback = CP.plan(no_screen,Vector2i(8,9),{1:true})
	apply(no_screen,Vector2i(8,9),fallback)
	check(CP.value(no_screen[0],no_screen,aim,{}, {}) == 0,"no-screen lane never scores as cannon attack")
	# Repositioning invalidates an old useful line immediately, despite anti-return history.
	old_line[0].ai_recent=[Vector2i(0,1)]
	var emergency=CP.plan(old_line,Vector2i(5,1),{1:true})
	check(emergency.targets.get(1) == relocation.targets.get(1),"irrelevant old line overrides return inertia")
	check(CP.movement_penalty(hold_board[0],Vector2i(0,1),110,115,Vector2i(0,8),hold_board) < CP.movement_penalty({"kind":"c","pos":Vector2i(0,0),"ai_recent":[Vector2i(0,1)]},Vector2i(0,1),110,115,Vector2i(0,8),hold_board),"minor gain penalizes immediate return")
	var stable_screen=piece(2,"p",0,3,5)
	check(CP.reliability(stable_screen,{}, {},0) > CP.reliability(stable_screen,{2:true}, {},0),"ready moving screen less reliable than stationary screen")
	check(CP.reliability(stable_screen,{2:true}, {2:true},0) == 1.0,"explicit held screen restores reliability")
	var saved=old_line.duplicate(true)
	CP.plan(old_line,Vector2i(5,1),{1:true})
	check(old_line==saved,"planner never mutates live board or cooldowns")
	var dense = [piece(1,"c",0,0),piece(2,"c",8,0),piece(3,"c",0,9),piece(4,"c",8,9),piece(5,"p",2,4),piece(6,"p",6,4),piece(7,"h",2,2),piece(8,"h",6,2),piece(9,"g",4,0)]
	var ready = {};for e in dense: ready[e.uid]=true
	var start = Time.get_ticks_usec();var budget = CP.plan(dense,Vector2i(4,5),ready);var elapsed = Time.get_ticks_usec()-start
	print("MULTI_CANNON elapsed_us=",elapsed," stats=",budget.stats)
	check(budget.stats.evaluations <= CP.MAX_EVALUATIONS,"phase-global maximum evaluation budget")
	apply(dense,Vector2i(4,5),budget)
	var samples=[]
	for iteration in 5:
		start=Time.get_ticks_usec();CP.plan(dense,Vector2i(4,5),ready);samples.append(Time.get_ticks_usec()-start)
	samples.sort();print("MULTI_CANNON warm median_us=",samples[2]," max_us=",samples[4])
	extended_checks()
	integration_checks()
	print("CANNON PLANNER RESULT ",checks-failures," passed, ",failures," failed")
	quit(1 if failures else 0)

func integration_checks():
	var game = load("res://main.tscn").instantiate();root.add_child(game)
	game.tutorial.stop();game.player_skill="king";game.new_run()
	game.enemies=[];game.player=Vector2i(0,8);game.lives=100;game.hand=[];game.hand_ids=[];game.deck=[];game.discard=[]
	game.encounter_state={"config":{"id":"palace_final","tier":"boss","rules":[]},"phases":0,"guard_uids":[],"retaliated":false,"river_triggered":false,"signal_uid":-1,"cannon_uid":-1,"spawn_cell":Vector2i(-1,-1)}
	game.add_enemy("c",Vector2i(0,0),3);var cannon=game.enemies.back();cannon.cd=3
	game.add_enemy("h",Vector2i(0,3),3);var support=game.enemies.back();support.cd=3;support.action_credits=2;support.action_credit_delay=0
	game.shield_charges=1;game.clear_effects();game.navigation_lock=0;game.phase="play";game.screen="game"
	var before=game.history.capture()
	game.end_turn()
	check(support.pos == Vector2i(0,3),"integration ready screen holds")
	check(support.action_credits == 1 and support.cd == support.period,"voluntary hold consumes exactly one credit and resets cooldown")
	check(game.lives == 100 and game.player == Vector2i(0,8),"shield blocks existing attack before coordinated moves")
	var after=game.history.capture()
	check(game.history.undo() and game.history.capture() == before,"undo restores hold credit and board")
	game.end_turn()
	check(game.history.capture() == after,"undo replay produces same hold outcome")
	# Elite march now banks a credit instead of executing a second same-phase move.
	game.tutorial.stop();game.new_run();game.enemies=[];game.player=Vector2i(8,9);game.lives=100
	game.encounter_state={"config":{"id":"rook_pressure","tier":"elite","rules":["double_step"]},"phases":0,"guard_uids":[],"retaliated":false,"river_triggered":false,"signal_uid":-1,"cannon_uid":-1,"spawn_cell":Vector2i(-1,-1)}
	game.add_enemy("p",Vector2i(2,3),1);var marcher=game.enemies.back();marcher.cd=1;marcher.march_mark=true;marcher.normal_moves=1
	game.clear_effects();game.phase="play";game.screen="game";game.navigation_lock=0
	game.end_turn()
	var movement=[]
	for fx in game.effects:
		if fx.kind=="move" and fx.get("piece",{}).get("uid",-1)==marcher.uid: movement.append(fx)
	check(marcher.pos==Vector2i(2,4) and marcher.normal_moves==2 and movement.size()==1 and marcher.action_credits==1,"ordinary elite banks credit with exactly one movement")
	game.clear_effects();marcher.stun=1;marcher.cd=1;marcher.action_credits=3;var frozen_pos=marcher.pos
	game.end_turn()
	movement=[]
	for fx in game.effects:
		if fx.kind=="move" and fx.get("piece",{}).get("uid",-1)==marcher.uid: movement.append(fx)
	check(marcher.pos==frozen_pos and movement.is_empty() and marcher.stun==0,"freeze blocks ordinary elite normal and extra movement until next phase")
	# A newly assembled cannon formation attacks only on the following enemy phase.
	game.tutorial.stop();game.new_run();game.enemies=[];game.encounter_state={};game.player=Vector2i(4,5);game.lives=100
	game.add_enemy("c",Vector2i(0,0),3);game.enemies.back().cd=1
	game.add_enemy("p",Vector2i(2,4),3);game.enemies.back().cd=1
	game.clear_effects();game.phase="play";game.screen="game";game.navigation_lock=0
	game.end_turn()
	check(game.lives==100 and game.player==Vector2i(4,5) and R.attacks(game.enemies[0],game.player,game.enemies),"joint move establishes threat without move-and-shoot damage")
	game.end_turn()
	check(game.lives==99,"assembled cannon formation attacks next enemy phase")
	game.queue_free()

func extended_checks():
	var player=Vector2i(4,2)
	var rescue_board=[piece(1,"c",0,1),piece(2,"g",4,0)]
	var rescue=CP.plan(rescue_board,player,{1:true})
	var rescued=apply(rescue_board,player,rescue)
	check(rescued[0].pos == Vector2i(4,1),"real two-cell spear rescue takes blocking midpoint")
	check(CP.general_barrier(rescued,player)>0 and CP.general_barrier(rescue_board,player)==0,"new body is real general barrier")
	check(CP.general_barrier(rescued,player,{"player_skill":"artillery"})==0 and CP.general_barrier(rescued,player,{"player_skill":"horse"})>0,"same single screen is not rescue against artillery but blocks ordinary spear")
	var retained=CP.plan(rescued,player,{1:true})
	check(retained.targets.get(1)==Vector2i(4,1),"retain real barrier over optional reposition")
	check(CP.general_barrier(rescued,Vector2i(5,0))==0 and CP.general_barrier(rescued,Vector2i(5,1))==0,"adjacent or diagonal danger cannot invent screen rescue")
	var unblock=[piece(1,"c",0,0),piece(2,"h",0,1),piece(3,"stake",0,3),piece(4,"stake",1,0)]
	unblock[2].permanent=true;unblock[3].permanent=true
	var unblock_plan=CP.plan(unblock,Vector2i(0,8),{1:true,2:true})
	var unblocked=apply(unblock,Vector2i(0,8),unblock_plan)
	check(unblock_plan.order.find(2)<unblock_plan.order.find(1) and unblock_plan.targets.get(1)==Vector2i(0,0),"support unblocks before cannon newly legal hold")
	check(R.attacks(unblocked[0],Vector2i(0,8),unblocked),"unblocking removes second screen and preserves cannon threat")
	var actor=piece(1,"p",2,4,1);actor.stun=1
	var projected=CP.advance_projection([actor],{}, {},Vector2i(8,9))
	check(CP.next_ready(projected[0],false,{}) and not CP.moves(projected[0],projected,Vector2i(8,9)).is_empty(),"stun1 expires before next phase readiness and legal moves")
	actor.stun=2;projected=CP.advance_projection([actor],{}, {},Vector2i(8,9))
	check(not CP.next_ready(projected[0],false,{}),"stun2 still prevents next-phase action")
	actor.stun=0;actor.cd=3;actor.action_credits=1;actor.action_credit_delay=1
	projected=CP.advance_projection([actor],{}, {"credit_mode":true},Vector2i(8,9))
	check(not CP.next_ready(projected[0],false,{"credit_mode":true}),"post-decrement credit delay1 still suppresses next phase credit")
	actor.action_credit_delay=0
	projected=CP.advance_projection([actor],{}, {"credit_mode":true},Vector2i(8,9))
	check(CP.next_ready(projected[0],false,{"credit_mode":true}),"post-decrement delay0 allows next phase carried credit")
	var expiring=piece(2,"stake",2,5);expiring.ttl=1
	projected=CP.advance_projection([actor,expiring],{}, {},Vector2i(8,9))
	check(projected.size()==1 and Vector2i(2,5) in CP.moves(projected[0],projected,Vector2i(8,9)),"expired stake removed from future movement occupancy")
	# Occupancy after a successful action cannot erase the already spent credit.
	var boxed=[piece(1,"c",0,0),piece(2,"stake",1,0),piece(3,"stake",0,1)]
	boxed[0].action_credits=1;boxed[0].action_credit_delay=0;boxed[1].permanent=true;boxed[2].permanent=true
	check(CP.moves(boxed[0],boxed,Vector2i(8,9)).is_empty(),"projected final landing is genuinely boxed in")
	var spent_context={"credit_mode":true,"credit_ready":{1:true},"projected_spent":{1:true}}
	var spent=CP.advance_projection(boxed,{1:true},spent_context,Vector2i(8,9))
	var unspent=CP.advance_projection(boxed,{1:true},{"credit_mode":true,"credit_ready":{1:true}},Vector2i(8,9))
	check(spent[0].action_credits==0 and spent[0].cd==3 and not CP.next_ready(spent[0],false,spent_context),"executed move into boxed landing consumes final credit and prevents next-stage readiness")
	check(unspent[0].action_credits==1 and boxed[0].action_credits==1,"unexecuted blocked action retains credit and projection does not mutate source")
	var rng=RandomNumberGenerator.new();rng.seed=11003
	var equivalent=true;var compared=0
	for sample in 24:
		var board=[];var used={};player=Vector2i(rng.randi_range(0,8),rng.randi_range(0,9));used[CP.key(player)]=true
		for i in 12:
			var pos=Vector2i(rng.randi_range(0,8),rng.randi_range(0,9))
			while used.has(CP.key(pos)): pos=Vector2i(rng.randi_range(0,8),rng.randi_range(0,9))
			used[CP.key(pos)]=true
			var kind=["c","r","p","q","g","a","e","h","stake"][i%9]
			var e=piece(i+1,kind,pos.x,pos.y);e.stun=1 if sample%5==0 else 0;board.append(e)
		for e in board:
			var fast=CP.moves(e,board,player);var reference=R.moves(e,board,player)
			fast.sort();reference.sort();compared+=1
			if fast != reference:
				equivalent=false;push_error("fast moves mismatch "+str(e)+" fast="+str(fast)+" reference="+str(reference))
	check(equivalent,"fast moves match reference across "+str(compared)+" seeded occupied boards/actors")
	var stress=[piece(1,"c",0,0),piece(2,"c",8,0),piece(3,"c",0,9),piece(4,"c",8,9)]
	for spec in [["h",2,2],["h",6,2],["h",2,7],["h",6,7],["p",2,4],["p",6,4],["p",3,6],["p",5,6],["g",4,0]]:
		stress.append(piece(stress.size()+1,spec[0],spec[1],spec[2]))
	var ready={};var credit_ready={}
	for e in stress: e.period=1;e.cd=0;e.action_credits=3;e.action_credit_delay=0;ready[e.uid]=true;credit_ready[e.uid]=true
	var start=Time.get_ticks_usec();var plan=CP.plan(stress,Vector2i(4,5),ready,{"credit_mode":true,"credit_ready":credit_ready});var elapsed=Time.get_ticks_usec()-start
	print("STRESS four cannons period1 credits3 elapsed_us=",elapsed," stats=",plan.stats)
	check(plan.stats.evaluations<=CP.MAX_EVALUATIONS,"adversarial ready army respects hard phase budget")
	apply(stress,Vector2i(4,5),plan)
