extends SceneTree
const TRAINING = preload("res://training_ground.gd")
class WebStorageProbe extends TRAINING:
	var stored = ""
	var reject_write = false
	var write_result = false
	var read_result = true
	func write_presets() -> bool:
		return _write_web_presets({"version":SCHEMA,"presets":presets,"recent_id":recent_id})
	func _write_web_value(encoded: String):
		if not reject_write: stored = encoded
		return write_result
	func _read_web_value():
		return stored if read_result else null
var game
var training
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if not value: failures += 1;push_error("TRAINING EDITOR: "+label)
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	training = game.training;training.open();training.create_new()
	check(game.screen == "training_editor", "independent editor entry")
	check(training.validate_preset(training.state).is_empty(), "default configuration valid")
	check(training.state.free_step and not training.state.shuffle, "exact order and automatic free move defaults")
	check(training.state.hand == game.PROFILES.DATA.king.deck, "default starting cards use live profile definitions")
	var original = training.state.duplicate(true)
	training.place_index = 4;training.tool = "place";training.place_at(Vector2i(0,4));training.place_at(Vector2i(1,4))
	check(training.state.enemies.size() == 3 and training.state.enemies[1].ai_role == "outrider", "continuous placement preserves cavalry role")
	training.place_index = 5;training.place_at(Vector2i(2,4))
	check(training.state.enemies.back().ai_role == "guard_horse", "guard cavalry uses live horse identity")
	var board = training.state.enemies.duplicate(true);training.choose_role("artillery")
	check(training.state.enemies == board, "role changes never destroy board")
	training.place_at(Vector2i(0,4));training.place_at(Vector2i(0,5))
	check(training.state.enemies[1].pos == Vector2i(0,5) and training.state.enemies.size()==4, "selected piece moves instead of duplicating")
	training.tool = "player";training.place_at(Vector2i(3,8));check(training.state.player == Vector2i(3,8),"player independently relocates")
	training.place_at(Vector2i(0,5));check(training.state.player == Vector2i(3,8),"player cannot overlap enemy")
	training.tool = "erase";training.place_at(Vector2i(0,5));check(training.state.enemies.size()==3,"eraser removes exact target")
	training.create_new();training.card_pile = "hand";training.card_selected = "sword";training._activate("add_card")
	check(training.state.hand.size()==5 and training.state.hand.count("sword")==3,"duplicate cards are distinct physical copies")
	training._activate("upgrade")
	check(training.state.hand.back()=="sword_plus" and training.state.hand.count("sword")==2,"upgrade changes only selected physical copy")
	training._activate("pile_move:-1");check(training.state.hand[3]=="sword_plus","physical card reorder")
	training._activate("pile_remove");check(training.state.hand.size()==4,"physical card deletion")
	training.choose_role("king");training._activate("treasure:life_talisman");training._activate("treasure:tiger_tally")
	check(training.state.treasure_ids.size()==2,"multiple compatible treasures can be selected")
	training._activate("treasure:wind_horseshoe");check(training.state.treasure_ids.size()==2,"incompatible treasure is disabled")
	training.choose_role("horse");check(training.state.treasure_ids.is_empty(),"changing role removes incompatible treasures only")
	training._activate("treasure:decoy_tally");check(training.state.treasure_ids==["decoy_tally"],"shared decoy treasure is available to current role")
	training.card_selected="decoy_card";training._activate("add_card");training._activate("add_card")
	check(training.state.hand.count("decoy_card")==1,"generated decoy hand cap enforced")
	training.place_index=11;training.tool="place";training.place_at(Vector2i(0,6));training.place_at(Vector2i(1,6))
	check(training.state.enemies.filter(func(e): return e.kind=="decoy").size()==1,"board decoy cap enforced")
	for group in TRAINING.CATALOG.GROUPS.size():
		training.card_group = group
		for entry in training.available_cards(): check(game.CARDS.has(entry.id),"catalog only provides actual card identities")
	var invalid = training.state.duplicate(true);invalid.enemies.append(invalid.enemies[0].duplicate(true))
	check(not training.validate_preset(invalid).is_empty(),"overlap and duplicate UIDs rejected")
	invalid = training.state.duplicate(true);invalid.player = Vector2i(-1,9)
	check(not training.validate_preset(invalid).is_empty(),"out of board player rejected")
	invalid = training.state.duplicate(true);invalid.hand.append("not_a_real_card")
	check(not training.validate_preset(invalid).is_empty(),"unknown card rejected")
	invalid = training.state.duplicate(true);invalid.snapshot = {"rng_state":1}
	check(not training.validate_preset(invalid).is_empty(),"incomplete full snapshots rejected")
	for hp_max in [0,1,1000,999999]:
		invalid=training.state.duplicate(true);invalid.enemies[0].max_hp=hp_max
		check(not training.validate_preset(invalid).is_empty(),"unsafe max HP rejected: "+str(hp_max))
	invalid=training.state.duplicate(true);invalid.enemies[0].erase("max_hp")
	check(training.validate_preset(invalid).is_empty(),"optional max HP can be completed by runtime")
	training.presets = [];training.saved_id = "";training.create_new()
	check(training.save_named("测试：固定牌序"),"named independent save succeeds")
	var saved_id = training.saved_id;var saved = training.state.duplicate(true)
	training.state.hand.append("sword_plus")
	check(training.load_preset(saved_id) and training.state==saved,"loading gives detached state with exact order")
	check(training.save_named("副本",true) and training.presets.size()==2,"copy is a separate preset")
	check(training.save_named("改名") and training.presets.size()==2,"rename preserves identity")
	var current_id = training.saved_id
	check_web_storage_commits()
	var reloaded = TRAINING.new(game);reloaded.load_presets()
	check(reloaded.presets.size()==2 and reloaded.recent_id==current_id,"refresh preserves named presets and recent selection")
	check(training.delete_preset(current_id) and training.presets.size()==1,"delete only removes selected preset")
	for size in [Vector2(1280,940),Vector2(390,844),Vector2(360,640),Vector2(480,660),Vector2(844,390)]:
		game.configure_layout(size)
		game.screen="home"
		for index in 6:
			var home_button=game.frontend.button_rect(index)
			check(Rect2(Vector2.ZERO,game.ui_size).encloses(home_button),"all six home entries fit "+str(size))
			if game.mobile_layout and not game.compact_landscape:
				check(is_equal_approx(home_button.position.y,maxf(150,game.ui_size.y*0.25)+index*74) and home_button.size.y==60,"home preserves existing mobile coordinates "+str(size))
		game.screen="training_editor"
		var bounds = training.board_bounds();var panel = training.panel_rect()
		check(bounds.position.x>=0 and bounds.end.x<=game.ui_size.x and bounds.end.y<game.ui_size.y-90,"board fits viewport "+str(size))
		check(panel.position.y>80 and panel.end.y<=game.ui_size.y-80,"configuration panel leaves fixed action bar "+str(size))
		var grid = training.card_grid_rect();var last = training.card_grid_card_rect(training.card_grid_page_size()-1)
		check(grid.encloses(last),"all card-page hit targets stay inside grid "+str(size))
	training.create_new();training.open_name("save")
	var event = InputEventKey.new();event.pressed = true;event.keycode = KEY_A
	check(not training.handle_input(event),"name entry leaves ordinary keys for native LineEdit")
	var mouse=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_LEFT;mouse.position=training.name_edit.get_global_rect().get_center();mouse.pressed=true
	check(not training.handle_input(mouse),"name entry receives pointer focus and text selection")
	mouse.pressed=false;check(not training.handle_input(mouse),"name entry receives pointer release")
	training.hide_name_edit();training.modal = ""
	var before = training.state.duplicate(true)
	var touch = InputEventScreenTouch.new();touch.index=0;touch.position=training.board_geometry().origin+Vector2(0,200);touch.pressed=true;training.handle_input(touch)
	touch.pressed=false;touch.canceled=true;training.handle_input(touch)
	check(training.state==before,"canceled touch never places or moves")
	var board_point=training.board_geometry().origin+Vector2(0,4)*training.board_geometry().cell
	training.tool="place";training.place_index=8
	var mouse_press=InputEventMouseButton.new();mouse_press.button_index=MOUSE_BUTTON_LEFT;mouse_press.position=board_point;mouse_press.pressed=true
	training.handle_input(mouse_press);training.cancel_pointer();mouse_press.pressed=false;training.handle_input(mouse_press)
	check(training.state==before,"blur-canceled mouse release cannot place a piece")
	for id in [0,1]:
		var press=InputEventScreenTouch.new();press.index=id;press.position=board_point;press.pressed=true;training.handle_input(press)
	var release=InputEventScreenTouch.new();release.index=0;release.position=board_point;release.pressed=false;training.handle_input(release)
	var third=InputEventScreenTouch.new();third.index=2;third.position=board_point;third.pressed=true;training.handle_input(third)
	release.index=1;training.handle_input(release);third.pressed=false;training.handle_input(third)
	check(training.state==before,"multitouch cancellation lasts until all contacts lift")
	var next_touch=InputEventScreenTouch.new();next_touch.index=0;next_touch.position=board_point;next_touch.pressed=true;training.handle_input(next_touch)
	next_touch.pressed=false;training.handle_input(next_touch)
	check(training.state.enemies.size()==before.enemies.size()+1,"single-pointer interaction resumes after all contacts lift")
	training.create_new()
	training.create_new();training.state.finish_condition = "free"
	training.state.deck = ["sword_plus","spear_plus","sword"]
	var initial_editor = training.state.duplicate(true)
	check(training.play(),"real session accepts editor configuration")
	game.clear_effects();game.input_lock=0;game.navigation_lock=0
	game.draw_card();game.clear_effects();game.energy=7;game.shield_charges=1
	game.pending_bleeds=[{"enemy_uid":game.enemies[0].uid,"amount":2}]
	var exact = game.history.capture().duplicate(true)
	training.save_current_position()
	check(training.state==initial_editor,"save-current never mutates original editor scenario")
	var latest = training.presets.back()
	check(latest.data.has("snapshot") and latest.data.snapshot == exact,"save-current includes complete runtime, card UIDs and exact RNG")
	check(training.validate_preset(latest.data).is_empty(),"full runtime snapshot passes schema validation")
	training.return_to_editor();check(training.state==initial_editor,"return restores original editor without copying played board")
	check(training.load_preset(latest.id),"load full-position preset")
	check(training.play(),"full-position preset can be replayed")
	var replay = game.history.capture()
	for enemy in exact.enemies: enemy.erase("visual")
	for enemy in replay.enemies: enemy.erase("visual")
	check(replay==exact,"full-position replay restores every captured field")
	training.return_to_editor()
	training.presets=[];training.recent_id="";training.write_presets()
	print("TRAINING EDITOR: %d checks, %d failures" % [checks,failures])
	game.free();quit(1 if failures else 0)
func check_web_storage_commits():
	var probe = WebStorageProbe.new(game)
	var first = probe.new_state();first.name = "Original"
	var first_id = probe.persist_preset(first, "")
	check(not first_id.is_empty() and probe.presets.size() == 1,"committed web save succeeds despite false write return")
	for result in [false, null]:
		probe.write_result = result
		var next = first.duplicate(true);next.name = "Snapshot "+str(probe.presets.size())
		var previous_count = probe.presets.size()
		var id = probe.persist_preset(next, "")
		var stored = bytes_to_var(Marshalls.base64_to_raw(probe.stored))
		check(not id.is_empty() and probe.presets.size() == previous_count+1,"committed web write never rolls back memory for "+str(result))
		check(stored.presets == probe.presets and stored.recent_id == id,"consecutive web saves retain every independent preset for "+str(result))
		check(stored.presets[0].data.name == "Original","previously committed preset stays unchanged")
	var previous = probe.presets.duplicate(true);var previous_recent = probe.recent_id;var previous_payload = probe.stored
	probe.reject_write = true;probe.write_result = true
	var unsaved = first.duplicate(true);unsaved.name = "Rejected"
	check(probe.persist_preset(unsaved, "").is_empty(),"positive bridge result cannot hide rejected web write")
	check(probe.presets == previous and probe.recent_id == previous_recent and probe.stored == previous_payload,"actual rejected write restores memory without changing committed presets")
	probe.read_result = false
	check(probe.persist_preset(unsaved, "").is_empty(),"unverifiable web payload does not claim success")
	check(probe.presets == previous and probe.recent_id == previous_recent,"unverifiable rejected write leaves preset state unchanged")
