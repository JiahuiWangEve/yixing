extends SceneTree
const E=preload("res://encounters.gd")
const CP=preload("res://cannon_planner.gd")
var game
var checks=0
var failures=0
func check(ok,label):
 checks+=1
 if not ok: failures+=1;push_error(label)
func _initialize(): call_deferred("run")
func fixture(id="rook_pressure",rules=["double_step"]):
 game.tutorial.stop();game.new_run();game.enemies=[];game.hand=[];game.hand_ids=[];game.deck=[];game.discard=[];game.lives=100
 E.setup(game,{"id":id,"tier":"elite","rules":rules})
 game.enemies=[game.enemies[0]];game.enemies[0].cd=999;game.player=Vector2i(8,9)
 game.clear_effects();game.phase="play";game.screen="game";game.navigation_lock=0
func step():
 game.clear_effects();game.end_turn()
 var counts={}
 for fx in game.effects:
  if fx.kind=="move" and not fx.get("piece",{}).is_empty():
   var uid=fx.piece.uid;counts[uid]=counts.get(uid,0)+1
 for uid in counts: check(counts[uid]<=1,"at most one move per actor")
func run():
 game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
 fixture();game.add_enemy("p",Vector2i(2,0),2);var pawn=game.enemies.back();pawn.cd=1;pawn.march_mark=true;pawn.march_normal_moves=1;pawn.normal_moves=1
 step();check(pawn.pos==Vector2i(2,1) and pawn.action_credits==1 and pawn.march_normal_moves==2,"second natural step banks credit, does not double move")
 step();check(pawn.pos==Vector2i(2,2) and pawn.action_credits==0 and pawn.march_normal_moves==2,"credit step consumes without generating march progress")
 step();check(pawn.pos==Vector2i(2,2),"credit chain stops and normal cooldown resumes")
 pawn.action_credits=2;pawn.stun=1;step();check(pawn.action_credits==2 and pawn.pos==Vector2i(2,2),"frozen credit retained")
 game.add_enemy("p",Vector2i(2,3),99);step();check(pawn.action_credits==2 and pawn.pos==Vector2i(2,2),"blocked credit retained")
 game.enemies.pop_back();pawn.action_credit_delay=2;pawn.cd=5
 step();check(pawn.action_credits==2 and pawn.pos==Vector2i(2,2),"delay first phase")
 step();check(pawn.action_credits==2 and pawn.pos==Vector2i(2,2),"delay second phase")
 step();check(pawn.action_credits==1 and pawn.pos==Vector2i(2,3),"delayed credit resumes once")
 step();check(pawn.action_credits==0 and pawn.pos==Vector2i(2,4),"overflow consumed next phase only")
 fixture("river_cannon",["river_signal"]);game.add_enemy("c",Vector2i(2,3),3);var cannon=game.enemies.back();game.encounter_state.cannon_uid=cannon.uid
 cannon.bonus_pending=true;cannon.bonus_after_phase=2;cannon.cd=9;game.encounter_state.phases=1
 check(E.effective_countdown(game,cannon)==2,"legacy pending countdown reflects due phase")
 E.prepare_phase(game);check(cannon.bonus_pending and cannon.action_credits==0,"future legacy pending not prematurely consumed")
 game.encounter_state.phases=2;E.prepare_phase(game);E.prepare_phase(game)
 check(not cannon.bonus_pending and cannon.action_credits==1,"legacy pending converts exactly once")
 fixture("two_wings",["last_stand"]);game.add_enemy("p",Vector2i(2,0),3);pawn=game.enemies.back();pawn.action_credits=1
 E.on_general_damage(game,game.enemies[0]);E.on_general_damage(game,game.enemies[0])
 check(pawn.action_credits==2,"retaliation stacks once")
 step();check(pawn.action_credits==1 and pawn.pos==Vector2i(2,1),"first stacked credit")
 step();check(pawn.action_credits==0 and pawn.pos==Vector2i(2,2),"second stacked credit")
 # Planner sees only next-phase credit, and does not reproduce march credits from accelerated moves.
 var actor={"uid":3,"kind":"p","pos":Vector2i(2,5),"cd":1,"period":3,"stun":0,"march_mark":true,"march_normal_moves":1,"action_credits":0}
 var context={"credit_mode":true,"encounter_state":{"config":{"rules":["double_step"]}},"projected_origins":{3:Vector2i(2,4)},"projected_spent":{3:true},"credit_ready":{}}
 var projected=CP.advance_projection([actor],{3:true},context,Vector2i(8,9))
 check(projected[0].action_credits==1 and CP.next_ready(projected[0],false,context),"planner forecasts next march credit")
 context.credit_ready={3:true};actor.action_credits=1
 projected=CP.advance_projection([actor],{3:true},context,Vector2i(8,9))
 check(projected[0].action_credits==0 and not CP.next_ready(projected[0],false,context),"planner credit movement never self-generates")
 print("ELITE ACTION CREDITS ",checks-failures," passed, ",failures," failed")
 quit(1 if failures else 0)
