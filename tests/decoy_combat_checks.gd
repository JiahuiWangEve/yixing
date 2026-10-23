extends SceneTree
const R = preload("res://rules.gd")
const CAV = preload("res://cavalry_roles.gd")
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("DECOY COMBAT: " + label)
func fresh():
	game.training.playing=false;game.training.state={}
	game.tutorial.stop();game.player_skill="king";game.seed_value=9127;game.new_run()
	game.enemies=[];game.encounter_state={};game.player=Vector2i(8,9)
	game.stage=1;game.turn=1;game.lives=20;game.energy=20
	game.hand=[];game.hand_ids=[];game.deck=[];game.discard=[];game.collection=[]
	game.pending_bleeds=[];game.phase="play";game.screen="game"
	game.treasures.reset_battle();game.clear_effects();game.presentation.clear();game.card_picker.close();game.history.clear()
	game.input_lock=0;game.navigation_lock=0;game.sync_hand_views()
func add(kind: String, pos: Vector2i, cd: int = 99) -> Dictionary:
	game.add_enemy(kind,pos,cd)
	var result: Dictionary=game.enemies.back()
	if kind=="decoy": result.hp=2;result.max_hp=2;result.neutral=true
	return result
func moves_for(uid: int) -> Array:
	return game.effects.filter(func(fx): return fx.kind=="move" and fx.get("piece",{}).get("uid",-1)==uid)
func impacts() -> Array: return game.effects.filter(func(fx): return fx.kind=="enemy_impact")
func snapshot() -> Dictionary:
	var result: Dictionary=game.history.capture();result.erase("initial_threat")
	for actor in result.enemies: actor.erase("visual")
	return result
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.settings.set_debug_mode(true)
	priority_and_capture()
	independent_damage_cap()
	credit_checks()
	neutral_and_persistence()
	generated_card_and_undo()
	info_read_only()
	print("DECOY COMBAT RESULT %d checks, %d failures" % [checks,failures])
	game.free();quit(1 if failures else 0)
func priority_and_capture():
	fresh();game.player=Vector2i(6,5)
	var actor=add("h",Vector2i(4,4),1);var decoy=add("decoy",Vector2i(2,5))
	check(R.attacks(actor,game.player,game.enemies) and R.captures_object(actor,decoy.pos,game.enemies,game.player), "fixture can legally attack player and bait")
	var rng_state=game.rng.state;game.end_turn()
	check(decoy.hp==1 and game.lives==20 and game.player==Vector2i(6,5), "offensive horse chooses legal decoy over simultaneous player hit")
	check(actor.pos==Vector2i(4,4) and moves_for(actor.uid).is_empty(), "surviving bait consumes the actor's movement for the phase")
	check(game.rng.state==rng_state and game.turn==2, "decoy-only attack does not sample recoil RNG")
	check(impacts().size()==1 and impacts()[0].decoy_target and game.displayed_lives()==20, "decoy impact targets bait without changing displayed lives")
	var settled=snapshot();game._process(0.07)
	check(not actor.visual.is_equal_approx(game.cell_pos(actor.pos)), "surviving decoy makes actual attacker visibly bump")
	game._process(1.0);check(snapshot()==settled and actor.visual.is_equal_approx(game.cell_pos(actor.pos)), "decoy bump returns without a second combat action")
	fresh()
	var first=add("h",Vector2i(2,4),1);var second=add("h",Vector2i(6,4),1)
	var later=add("r",Vector2i(8,5),1);decoy=add("decoy",Vector2i(4,5))
	var clone=RandomNumberGenerator.new();clone.state=game.rng.state
	# The recoil board after bait capture is the actual final occupied geometry.
	var recoil_board=game.enemies.duplicate(true);recoil_board.erase(recoil_board.back())
	recoil_board[1].pos=decoy.pos
	var safe=R.safe_recoil(game.player,recoil_board)
	var expected: Vector2i=safe[clone.randi_range(0,safe.size()-1)]
	game.end_turn()
	check(game.enemies.all(func(e): return e.kind!="decoy") and second.pos==Vector2i(4,5), "second legal hit destroys bait and captures its cell")
	check(moves_for(first.uid).is_empty() and moves_for(second.uid).size()==1 and moves_for(later.uid).is_empty(), "capture consumes one movement, no attacker gets an extra countdown move")
	check(second.cd==second.period and first.cd==first.period, "bait attackers' ready cooldowns are reset")
	check(game.lives==19 and game.player==expected and game.rng.state==clone.state, "later enemy reselects player after capture, with exactly original recoil draw")
	check(impacts().size()==2 and impacts()[0].attacker_uid==first.uid and impacts()[1].attacker_uid==later.uid, "attack order is preserved across bait destruction")
	check(game.treasure_battle.spring_kills==0, "neutral destruction never awards true enemy kill")
func independent_damage_cap():
	fresh();game.player=Vector2i(4,5)
	var player_attacker=add("p",Vector2i(4,4),1)
	var first=add("p",Vector2i(0,7),1);var second=add("p",Vector2i(1,8),1)
	add("decoy",Vector2i(0,8))
	game.end_turn()
	check(game.lives==19, "one player damage remains capped for the phase")
	check(game.enemies.all(func(e): return e.kind!="decoy") and second.pos==Vector2i(0,8), "later decoy hits continue after player's single damage")
	check(moves_for(player_attacker.uid).is_empty() and moves_for(first.uid).is_empty() and moves_for(second.uid).size()==1, "each actor attacks once and capture moves once after player recoil")
	fresh();game.player=Vector2i(6,5)
	var guard=add("h",Vector2i(4,4),1);CAV.configure(guard,"guard_horse")
	var decoy=add("decoy",Vector2i(2,5));add("g",Vector2i(4,0))
	game.end_turn()
	check(game.lives==19 and decoy.hp==2, "defensive guard horse prioritizes player threat rather than abandoning defense for bait")
func neutral_and_persistence():
	fresh();game.player=Vector2i(4,5)
	var decoy=add("decoy",Vector2i(4,4));add("g",Vector2i(4,0))
	check(not game.card_legal("sword",decoy.pos) and not game.card_legal("pierce",decoy.pos), "neutral object is not a player weapon target")
	check(not game.damage_enemy(0,0,10) and decoy.hp==2, "ordinary enemy damage cannot damage neutral bait")
	game.queue_bleed(0,2)
	check(game.pending_bleeds.is_empty(), "neutral bait cannot acquire enemy bleed")
	check(not game.treasures.true_defeat(decoy), "neutral bait never counts as true defeat")
	for i in 6:
		game.clear_effects();game.end_turn()
	check(decoy in game.enemies and decoy.hp==2 and not decoy.has("ttl") and decoy.cd==99, "unattacked bait persists indefinitely without countdown actions")
func credit_checks():
	for survives in [true,false]:
		for delayed in [true,false]:
			fresh();game.training.playing=true;game.training.state={"treasure_ids":[],"finish_condition":"free"}
			var actor=add("h",Vector2i(2,4),3);actor.action_credits=3;actor.action_credit_delay=2 if delayed else 0
			var decoy=add("decoy",Vector2i(4,5));decoy.hp=2 if survives else 1
			game.end_turn()
			var expected_credits=3 if survives or delayed else 2
			check(actor.action_credits==expected_credits, "capture spends one available credit only, preserving overflow and delayed credits")
			check(actor.action_credit_delay==(1 if delayed else 0), "bait attack advances credit delay by ordinary phase timing")
			check(moves_for(actor.uid).size()==(0 if survives else 1), "credits never grant an additional move after bait attack")
	game.training.playing=false
func generated_card_and_undo():
	fresh();game.training.playing=true;game.training.state={"treasure_ids":["decoy_tally"],"finish_condition":"free"}
	game.treasures.reset_battle()
	check(game.decoys.start_turn() and game.hand==["decoy_card"], "training treasure generates first-turn zero-fee card")
	check(game.card_cost("decoy_card")==0 and game.treasure_battle.trigger_serials.get("decoy_tally",0)==1, "generated card is free and feedback identifies its own treasure")
	game.player=Vector2i(4,5);game.clear_effects()
	var before=snapshot();game.play_card(0,Vector2i(2,3))
	check(game.enemies.size()==1 and game.enemies[0].kind=="decoy" and game.hand.is_empty() and game.discard.is_empty(), "playing generated card creates one decoy without recycling into discard")
	game.clear_effects();check(game.undo_action() and snapshot()==before, "undo restores exact card UID, board, generation schedule, and RNG")
	game.clear_effects();game.end_turn()
	check("decoy_card" in game.hand, "generated decoy card survives turn-end cleanup")
	game.clear_effects();game.end_turn();game.clear_effects();game.end_turn()
	check(game.turn==4 and game.hand.count("decoy_card")==1, "turn-four generation never duplicates held card")
	game.training.playing=false
func info_read_only():
	fresh();var decoy=add("decoy",Vector2i(4,5));decoy.hp=1
	var scout=add("h",Vector2i(2,3));CAV.configure(scout,"outrider")
	var guard=add("h",Vector2i(4,2));CAV.configure(guard,"guard_horse")
	var before=snapshot();var state=game.rng.state
	for i in 10:
		var info: Dictionary=game.board_info.enemy_info(decoy)
		check(info.title=="草人 · 1/2血" and not str(info.lines).contains("倒计时"), "decoy tooltip states actual HP and no fake movement intent")
		check(game.board_info.enemy_info(scout).title.begins_with("游骑") and game.board_info.enemy_info(guard).title.begins_with("近卫骑"), "cavalry tooltip exposes actual role rather than generic horse name")
	check(game.board_info.hp_segments(decoy)==[true,false], "decoy shows current two-segment HP")
	check(snapshot()==before and game.rng.state==state, "inspection never mutates combat or samples future intentions")
	game.training.playing=true;game.training.state={"treasure_ids":[],"finish_condition":"free"}
	game.encounter_state={"config":{"id":"training","chapter":2,"tier":"training","rules":[]},"ghosts":[],"waves":[],"phases":0,"cancelled":false,"guard_uids":[]}
	scout.heavy=true;guard.unyielding=true
	var tags: Array=game.board_info.mechanism_tags()
	check(tags.any(func(tag): return tag.key=="heavy") and tags.any(func(tag): return tag.key=="unyielding"), "template-free training safely exposes actual configured traits")
	check(not tags.any(func(tag): return tag.key=="waves"), "training never invents chapter template reinforcements")
	game.board_info.begin_battle()
	check(not game.board_info.cue.contains("增援"), "training opening cue does not promise nonexistent waves")
	game.training.playing=false
