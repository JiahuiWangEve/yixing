extends SceneTree
var game
var training
var checks = 0
var failures = 0
var baseline: Dictionary
func _initialize(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if not value: failures += 1;push_error("TRAINING SESSION: "+label)
func bytes_at(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
func clean():
	game.presentation.clear();game.clear_effects();game.card_picker.close();game.input_lock=0.0;game.navigation_lock=0.0
func state() -> Dictionary:
	var snap = game.history.capture()
	for enemy in snap.enemies: enemy.erase("visual")
	return snap
func formal_files() -> Dictionary:
	return {"route":bytes_at(game.route.SAVE),"unlock":bytes_at(game.skill_system.SAVE_PATH),"settings":bytes_at(game.settings.SAVE)}
func start_config(role: String = "king", goal: String = "free", free: bool = true):
	training.create_new();training.state.player_skill=role;training.state.lives=7;training.state.energy=8
	training.state.free_step=free;training.state.finish_condition=goal;training.state.seed=742113
	training.state.hand=["sword_plus","sword_plus","spear","breath"]
	training.state.deck=["spear_plus","sword","fatigue","sword_plus"]
	training.state.enemies=[training.make_piece(0,Vector2i(4,0),1)]
	check(training.play(),role+" valid trial starts");clean()
func stop_config():
	training.return_to_editor()
	check(not training.is_playing() and game.screen=="training_editor","return enters editor and clears playing flag")
	check(formal_files()==baseline.files,"formal save/unlock/settings files unchanged")
	check(game.route.state==baseline.route,"formal route object restored")
	check(game.normal_undos_remaining==baseline.budget,"formal undo budget restored")
	check(game.skill_system.horse_unlocked==baseline.unlocked,"formal unlock unchanged")
	check(game.battle_restart.snapshot==baseline.checkpoint,"formal restart checkpoint restored")
	check(state()==baseline.battle,"entire formal battle and RNG restored")
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);training=game.training
	game.settings.set_debug_mode(false);game.player_skill="king";game.seed_value=881103
	game.new_expedition();game.route.enter(0);clean();game.normal_undos_remaining=1;game.route.save();game.show_home()
	baseline={"files":formal_files(),"route":game.route.state.duplicate(true),"budget":game.normal_undos_remaining,
		"unlocked":game.skill_system.horse_unlocked,"checkpoint":game.battle_restart.snapshot.duplicate(true),"battle":state()}
	training.open()
	check(formal_files()==baseline.files and game.route.state==baseline.route,"editor opening is read-only to formal progress")
	for role in ["king","horse","artillery"]:
		start_config(role)
		check(game.hand==training.state.hand,"exact initial hand not drawn or shuffled "+role)
		var expected=training.state.deck.duplicate();expected.reverse()
		check(game.deck==expected,"configured top-first draw order "+role)
		check(game.player_skill==role and game.lives==7 and game.energy==8,"role and numeric debug configuration exact "+role)
		check(game.free_card_available(),"free move defaults enabled "+role)
		var initial=state();var initial_editor=training.state.duplicate(true)
		game.draw_card();clean();check(game.hand.back()=="spear_plus","first draw comes from configured top "+role)
		game.draw_card();clean();check(game.hand.back()=="sword","second draw preserves configured ordering "+role)
		game.rng.randi();game.shield_charges=1;game.pending_bleeds=[{"enemy_uid":game.enemies[0].uid,"amount":2}]
		check(game.reset_training(),"reset accepts settled trial "+role);clean()
		check(state()==initial,"reset exact RNG, entities, hands, statuses "+role)
		var expected_roll=game.rng.randi();check(game.reset_training(),"repeat reset accepted "+role);clean()
		check(game.rng.randi()==expected_roll,"reset deterministically reproduces RNG "+role)
		check(training.state==initial_editor,"trial runtime cannot alias original configuration "+role)
		for i in 6:
			game.history.record("debug check");var energy=game.energy;game.energy=energy-1;clean()
			check(game.undo_action() and game.energy==energy,"unlimited undo attempt %d %s" % [i,role])
			check(game.normal_undos_remaining==baseline.budget,"undo never spends formal allowance "+role)
		game.route.save();check(formal_files()==baseline.files,"explicit route.save is suppressed in trial "+role)
		game.debug_skip();check(game.phase=="win","debug skip finishes trial only "+role)
		stop_config()
	start_config("artillery","free",false)
	check(game.free_card_uid==0 and not game.free_card_available(),"free move disabled initially")
	game.end_turn();clean();check(game.free_card_uid==0 and not game.free_card_available(),"free move remains disabled next turn")
	stop_config()
	start_config("king","free")
	training.state.shuffle=true
	training.return_to_editor();check(training.play(),"shuffle trial starts");clean()
	var shuffled=state();game.draw_card();clean();game.rng.randi()
	check(game.reset_training(),"shuffled trial reset accepted");clean();check(state()==shuffled,"shuffle reset preserves exact shuffled deck and RNG")
	stop_config()
	for goal in ["general","clear","free"]:
		training.create_new();training.state.finish_condition=goal;training.state.lives=5;training.state.hand=["sword_plus","sword_plus"]
		training.state.enemies=[training.make_piece(0,Vector2i(4,8),1),training.make_piece(8,Vector2i(3,9),2),training.make_piece(11,Vector2i(0,0),3)]
		training.state.enemies[0].hp=1
		check(training.play(),goal+" battle starts");clean()
		game.play_card(0,Vector2i(4,8));clean()
		check(game.phase==("win" if goal=="general" else "play"),goal+" handles general defeat correctly")
		if goal!="general":
			game.play_card(0,Vector2i(3,9));clean()
			check(game.phase==("win" if goal=="clear" else "play"),goal+" handles last real enemy defeat correctly")
			check(game.enemies.size()==1 and game.enemies[0].kind=="decoy","neutral decoy does not count as enemy")
		stop_config()
	for goal in ["clear","free"]:
		training.create_new();training.state.finish_condition=goal;training.state.enemies=[]
		check(training.play(),goal+" permits no-general scenario");clean();stop_config()
	training.create_new();training.state.enemies=[]
	check(not training.play() and not training.is_playing(),"general goal rejects missing general before runtime mutation")
	check(formal_files()==baseline.files,"invalid trial does not mutate formal files")
	training.create_new();training.state.finish_condition="free";training.state.treasure_ids=["life_talisman","tiger_tally","decoy_tally"]
	check(training.play(),"multi-treasure trial starts");clean()
	check(game.treasures.active_ids().size()==3,"role treasures and shared treasure simultaneously active")
	check(game.hand.count("decoy_card")==1,"shared treasure generates only one opening decoy card")
	game.treasure_battle.tiger_moves=2;game.energy=1;game.discard=["spear_plus"];game.pending_bleeds=[{"enemy_uid":game.enemies[0].uid,"amount":2}]
	var captured=state();var original=training.state.duplicate(true)
	training.save_current_position();var saved=training.presets.back()
	check(saved.data.snapshot.rng_state==captured.rng_state and saved.data.snapshot.discard==captured.discard,"save-current persists RNG and non-board card piles")
	check(training.state==original,"save-current preserves original editor preset")
	stop_config()
	check(training.load_preset(saved.id) and training.play(),"saved full trial loads and starts");clean()
	check(state()==captured,"saved full trial restores every captured field including treasure progress")
	stop_config()
	print("TRAINING SESSION: %d checks, %d failures" % [checks,failures])
	game.free();quit(1 if failures else 0)
