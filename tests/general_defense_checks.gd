extends SceneTree
const R = preload("res://rules.gd")
const GE = preload("res://general_evasion.gd")
const AI = preload("res://enemy_ai.gd")
const CP = preload("res://cannon_planner.gd")
var checks = 0
var failures = 0
var rng = RandomNumberGenerator.new()
const CANNON = {"player_skill":"artillery","artillery_mode":"attack"}
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
func piece(uid: int, kind: String, x: int, y: int) -> Dictionary:
	return {"uid":uid,"kind":kind,"pos":Vector2i(x,y),"stun":0,"cd":1,"period":3}
func choose(board: Array, player: Vector2i, context: Dictionary = {}) -> Vector2i:
	return AI.choose(board[0],R.moves(board[0],board,player),board,player,rng,context)
func apply(board: Array, player: Vector2i, plan: Dictionary) -> Array:
	var out = board.duplicate(true)
	for uid in plan.order:
		if not plan.targets.has(uid): continue
		var i = CP.by_uid(out,uid);var target = plan.targets[uid]
		check(CP.legal(out[i],target,out,player),"planner step uses an existing legal action")
		out[i].pos = target
	return out
func _initialize(): call_deferred("run")
func run():
	rng.seed = 13001
	# A healthy rear palace is not a reason to march toward the player.
	var rear = [piece(1,"g",4,0),piece(2,"a",3,0),piece(3,"a",5,0),piece(4,"e",2,0)]
	for i in 20:
		check(choose(rear,Vector2i(4,7)) == Vector2i(4,0),"guarded rear king deliberately holds without random drift")
	var guarded = [piece(1,"g",4,0),piece(2,"a",4,1)]
	var player = Vector2i(4,2)
	var state = GE.profile(guarded[0],guarded,player,{})
	check(not state.unsafe and state.shield,"a real short-spear blocker is effective cover")
	check(choose(guarded,player)==Vector2i(4,0),"king keeps its actual guardian barrier")
	check(GE.danger_at(Vector2i(4,0),[guarded[0]],player,{"player_skill":"artillery","artillery_mode":"march"}),"marching artillery still has public short-spear capability")
	check(GE.profile(guarded[0],guarded,player,{"player_skill":"artillery","artillery_mode":"march"}).shield,"real barrier also blocks marching artillery's public spear")
	# The very same advisor becomes a cannon screen, never imaginary armor.
	check(GE.threatened(guarded[0],guarded,player,CANNON),"advisor on one-screen line is cannon danger")
	var evade = choose(guarded,player,CANNON)
	check(evade != guarded[0].pos and evade.x != 4,"deployed cannon forces a safe lateral escape")
	check(not GE.danger_at(evade,GE.place(guarded[0],evade,guarded),player,CANNON),"cannon escape is genuinely safe rather than defended-but-exposed")
	var ranged = [piece(1,"g",4,1),piece(2,"p",4,5)]
	check(choose(ranged,Vector2i(4,9),CANNON)==Vector2i(3,1),"exact one-screen sidestep stays deterministic")
	check(not GE.threatened(ranged[0],[ranged[0]],Vector2i(4,9),CANNON),"zero screens does not invent a cannon attack")
	check(not GE.threatened(ranged[0],ranged+[piece(3,"p",4,6)],Vector2i(4,9),CANNON),"two screens block deployed cannon")
	check(not GE.threatened(ranged[0],ranged,Vector2i(4,9),{"player_skill":"artillery","artillery_mode":"march"}),"march posture is not deployed cannon threat")
	# The safest direction follows the intruding player, not a fixed north bias.
	var flank = [piece(1,"g",4,1)]
	check(choose(flank,Vector2i(2,1))==Vector2i(5,1),"left flank intrusion retreats right rather than toward top")
	check(choose(flank,Vector2i(6,1))==Vector2i(3,1),"right flank intrusion retreats left symmetrically")
	var upper = [piece(1,"g",4,1)]
	check(choose(upper,Vector2i(4,0))==Vector2i(4,2),"upper intrusion retreats down within palace")
	var frozen = flank.duplicate(true);frozen[0].stun=1
	check(choose(frozen,Vector2i(2,1))==GE.NONE,"frozen king receives no free defensive action")
	var fake = [piece(1,"g",4,0),piece(2,"a",3,0)]
	check(GE.profile(fake[0],fake,Vector2i(4,1),{}).unsafe,"nearby advisor cannot cancel adjacent damage")
	var diagonal = [piece(1,"g",4,0),piece(2,"a",3,1)]
	check(GE.profile(diagonal[0],diagonal,Vector2i(5,1),{}).unsafe,"nearby guardian cannot erase diagonal exposure")
	# Hold is included independently of cannons, and near-equal extra mobility
	# does not cause the general to walk out of a stable position.
	check(choose([piece(1,"g",4,0)],Vector2i(4,9))==Vector2i(4,0),"quiet king holds even without a cannon or barrier bonus")
	var legal = R.moves(rear[0],rear,Vector2i(4,7))
	check(GE.defend(rear[0],[Vector2i(0,0)]+legal,rear,Vector2i(4,7))==Vector2i(4,0),"injected illegal king candidate is ignored")
	var boxed = [piece(1,"g",3,0),piece(2,"a",4,0),piece(3,"a",3,1)]
	check(choose(boxed,Vector2i(8,9))==GE.NONE,"fully boxed general cannot manufacture a hold qualification")
	# Cannon coordination reserves the king's own choice, including a hold.
	var joint = rear.duplicate(true);joint.append(piece(5,"c",0,0))
	var saved = joint.duplicate(true)
	var plan = CP.plan(joint,Vector2i(4,7),{1:true,2:true,3:true,4:true,5:true})
	check(plan.targets.get(1)==Vector2i(4,0) and plan.order[0]==1 and plan.order.count(1)==1,"planner never drags safe king forward as a screen")
	apply(joint,Vector2i(4,7),plan)
	check(joint==saved,"defensive plan preserves source board and action counters")
	var essential = guarded.duplicate(true);essential.append(piece(3,"c",0,1))
	var barrier_before = GE.guard_state(essential,player,{})
	var unsafe = CP.placed(essential,2,Vector2i(3,2))
	check(not GE.preserves_guard_state(barrier_before,unsafe,player,{}),"planner rejects sacrificing essential guardian for firepower")
	var guardian_target = AI.choose(essential[1],R.moves(essential[1],essential,player),essential,player,rng)
	check(guardian_target==essential[1].pos,"ordinary ready guardian also holds instead of undoing king defense")
	plan = CP.plan(essential,player,{2:true,3:true})
	var after = apply(essential,player,plan)
	check(not GE.danger_at(after[0].pos,after,player,{}),"joint cannon/support plan retains real king safety")
	check(not plan.targets.has(1),"unready king is not given defensive movement")
	var artillery_safe = [piece(1,"g",4,0),piece(2,"c",0,3),piece(3,"a",3,0)]
	var artillery_before = GE.guard_state(artillery_safe,Vector2i(4,9),CANNON)
	check(not GE.preserves_guard_state(artillery_before,CP.placed(artillery_safe,2,Vector2i(4,3)),Vector2i(4,9),CANNON),"friendly cannon cannot create lethal one-screen exposure for king")
	plan = CP.plan(artillery_safe,Vector2i(4,9),{2:true,3:true},CANNON)
	after = apply(artillery_safe,Vector2i(4,9),plan)
	check(not GE.danger_at(after[0].pos,after,Vector2i(4,9),CANNON),"planner honors deployed artillery safety across joint/lookahead choices")
	check(plan.stats.evaluations<=CP.MAX_EVALUATIONS,"defense planning retains phase evaluation budget")
	var private_a = {"player_skill":"king","hand":["spear"],"deck":["sword"]}
	var private_b = {"player_skill":"king","hand":["life"],"deck":[]}
	check(choose(guarded,player,private_a)==choose(guarded,player,private_b),"decisions ignore hidden hand/deck fields")
	integration_checks()
	print("GENERAL DEFENSE RESULT ",checks-failures," passed, ",failures," failed")
	quit(1 if failures else 0)

func integration_checks():
	var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	game.tutorial.stop();game.player_skill="king";game.new_run()
	game.enemies=[];game.player=Vector2i(4,2);game.lives=100
	game.hand=[];game.hand_ids=[];game.deck=[];game.discard=[]
	game.encounter_state={"config":{"id":"palace_final","tier":"boss","rules":[]},"phases":0,"guard_uids":[],"retaliated":false,"river_triggered":false,"signal_uid":-1,"cannon_uid":-1,"spawn_cell":Vector2i(-1,-1)}
	game.add_enemy("g",Vector2i(4,0),3);var general=game.enemies.back()
	general.cd=3;general.action_credits=2;general.action_credit_delay=0
	game.add_enemy("a",Vector2i(4,1),99);game.enemies.back().cd=99
	game.clear_effects();game.phase="play";game.screen="game";game.navigation_lock=0
	game.end_turn()
	check(general.pos==Vector2i(4,0),"end_turn preserves guarded general's deliberate hold")
	check(general.action_credits==1 and general.cd==general.period,"general hold consumes exactly one credit and resets its cooldown")
	check(game.lives==100 and game.player==Vector2i(4,2),"defensive hold grants no extra attack or player displacement")
	var moves=0
	for fx in game.effects:
		if fx.kind=="move" and fx.get("piece",{}).get("uid",-1)==general.uid: moves+=1
	check(moves==0,"deliberate general hold has no phantom movement animation")
	game.queue_free()
