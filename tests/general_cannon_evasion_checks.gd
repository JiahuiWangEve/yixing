extends SceneTree
const R = preload("res://rules.gd")
const GE = preload("res://general_evasion.gd")
const AI = preload("res://enemy_ai.gd")
const CP = preload("res://cannon_planner.gd")
var n = 0
var failed = 0
var game
var ctx = {"player_skill":"artillery", "artillery_mode":"attack"}
func check(ok, label):
	n += 1
	if not ok: failed += 1;push_error(label)
func piece(kind, pos, uid, cd = 1):
	return {"kind":kind,"pos":pos,"uid":uid,"cd":cd,"period":3,"stun":0,"hp":3,"max_hp":3}
func _initialize(): call_deferred("run")
func run():
	var p=Vector2i(4,9)
	var g=piece("g",Vector2i(4,1),1)
	var board=[g,piece("p",Vector2i(4,5),2)]
	var opts=R.moves(g,board,p)
	var side=GE.choose(g,opts,board,p,ctx)
	check(side==Vector2i(3,1),"deployed one-screen general selects deterministic lateral safe step")
	check(GE.threatened(g,board,p,ctx),"one screen is a genuine player cannon threat")
	check(not GE.threatened(g,[g],p,ctx),"zero screens is not cannon threat")
	check(not GE.threatened(g,board+[piece("p",Vector2i(4,6),3)],p,ctx),"two screens is not cannon threat")
	check(not GE.threatened(g,board,p,{"player_skill":"artillery","artillery_mode":"march"}),"march posture not classified deployed threat")
	check(not GE.threatened(g,board,p,{"player_skill":"king","artillery_mode":"attack"}),"non-cannon character unaffected")
	var rng=RandomNumberGenerator.new();rng.seed=11
	for i in 20:
		check(AI.choose(g,opts,board,p,rng,ctx)==side,"ordinary AI escape outranks random proximity scoring")
	var blocked=board+[piece("a",Vector2i(3,1),3)]
	check(GE.choose(g,R.moves(g,blocked,p),blocked,p,ctx)==Vector2i(5,1),"occupied lateral square chooses other side")
	blocked.append(piece("a",Vector2i(5,1),4))
	check(GE.choose(g,R.moves(g,blocked,p),blocked,p,ctx)==Vector2i(-1,-1),"no safe legal option does not invent a move")
	var edge=piece("g",Vector2i(3,0),1);var ep=Vector2i(3,9);var eb=[edge,piece("p",Vector2i(3,5),2)]
	check(GE.choose(edge,[Vector2i(2,0)]+R.moves(edge,eb,ep),eb,ep,ctx)==Vector2i(4,0),"palace edge ignores injected illegal out-of-palace option")
	var horizontal=piece("g",Vector2i(4,1),1);var hp=Vector2i(0,1);var hb=[horizontal,piece("stake",Vector2i(2,1),2)]
	var hs=GE.choose(horizontal,R.moves(horizontal,hb,hp),hb,hp,ctx)
	check(hs.x==4 and hs.y!=1 and hs.y<=2,"horizontal cannon threat escapes vertically within palace")
	var frozen=g.duplicate();frozen.stun=1
	check(GE.choose(frozen,opts,[frozen,board[1]],p,ctx)==Vector2i(-1,-1),"frozen general never evades immediately")
	var mixed=board+[piece("c",Vector2i(0,1),3)]
	var plan=CP.plan(mixed,p,{1:true,2:true,3:true},ctx)
	check(plan.order[0]==1 and plan.targets[1]==side,"mixed cannon plan reserves threatened general first instead of support hold")
	check(plan.order.count(1)==1,"general is scheduled exactly once")
	var pending=CP.plan(mixed,p,{2:true,3:true},ctx)
	check(1 not in pending.order and not pending.targets.has(1),"general whose countdown is not ready cannot evade via planner")
	var noop=CP.plan(mixed,p,{},ctx)
	check(noop.order.is_empty(),"empty ready army does not trigger proactive evasion")
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	for state in ["ready","notready","frozen","noescape","mixed"]:
		game.tutorial.stop();game.player_skill="artillery";game.new_run();game.artillery_mode="attack"
		game.enemies=[];game.encounter_state={};game.player=p;game.lives=5
		game.hand=[];game.hand_ids=[];game.deck=[];game.discard=[];game.phase="play"
		game.add_enemy("g",Vector2i(4,1),3);var actual=game.enemies.back();actual.cd=1
		game.add_enemy("stake",Vector2i(4,5),99);game.enemies.back().ttl=99
		if state=="notready": actual.cd=2
		if state=="frozen": actual.stun=1
		if state=="noescape":
			game.add_enemy("a",Vector2i(3,1),99);game.add_enemy("a",Vector2i(5,1),99)
		if state=="mixed": game.add_enemy("c",Vector2i(0,1),1)
		game.clear_effects();game.end_turn()
		if state in ["ready","mixed"]:
			check(actual.pos.x!=4 and absi(actual.pos.x-4)+absi(actual.pos.y-1)==1,"end_turn legal single sidestep "+state)
			check(not GE.threatened(actual,game.enemies,p,ctx),"end_turn ends out of real cannon line "+state)
		elif state in ["notready","frozen"]: check(actual.pos==Vector2i(4,1),"end_turn respects eligibility "+state)
		else: check(actual.pos in R.moves(g,board+[piece("a",Vector2i(3,1),3),piece("a",Vector2i(5,1),4)],p),"no safe escape still uses only legal normal movement")
		check(game.lives==5,"evasion adds no attack after movement "+state)
	game.queue_free()
	print("GENERAL CANNON EVASION RESULT ",n-failed," passed, ",failed," failed")
	quit(1 if failed else 0)
