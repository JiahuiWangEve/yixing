extends SceneTree
# Generates only ordinary production training presets and a formal save. The
# exported game receives no test API. Browser assertions read user-created saves.
const OUT = "res://../verification/v0.16.0/training/"
const SIZES = [Vector2(1280,940),Vector2(390,844),Vector2(844,390)]
const T = preload("res://treasure_system.gd")
const D = preload("res://decoy_system.gd")
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("TRAINING WEB FIXTURE: " + label)
func point(value) -> Array: return [value.x,value.y]
func rect(value: Rect2) -> Array: return [value.position.x,value.position.y,value.size.x,value.size.y]
func json_value(value):
	if value is Vector2 or value is Vector2i: return point(value)
	if value is Array:
		var result = []
		for item in value: result.append(json_value(item))
		return result
	if value is Dictionary:
		var result = {}
		for key in value: result[str(key)] = json_value(value[key])
		return result
	return value
func normalized() -> Dictionary:
	var value = game.history.capture().duplicate(true)
	# Only render interpolation and user-facing save notices are omitted. Cards,
	# exact RNG, counters, logs, enemy state and all other gameplay stay compared.
	value.erase("initial_threat");value.erase("notice")
	for enemy in value.enemies: enemy.erase("visual")
	return json_value(value)
func settle():
	game.clear_effects();game.presentation.clear();game.input_lock = 0;game.navigation_lock = 0
	game.mouse_pos = Vector2(-100,-100);game.hover = Vector2i(-1,-1);game.handui.tick(2)
func write_text(name: String, value: String):
	var file = FileAccess.open(OUT + "fixtures/" + name,FileAccess.WRITE)
	check(file != null,"can write " + name)
	if file != null: file.store_string(value);file.close()
func make_preset() -> Dictionary:
	var value = game.training.new_state()
	value.name = "Web联动演武";value.player = Vector2i(4,5);value.lives = 5;value.energy = 3
	value.hand = ["grappling_hook"];value.deck = ["sword"];value.free_step = true
	value.treasure_ids = T.training_ids_for("king");value.seed = 1572026;value.finish_condition = "free"
	value.enemies = [game.training.make_piece(0,Vector2i(4,0),1),game.training.make_piece(4,Vector2i(0,0),2),game.training.make_piece(5,Vector2i(8,0),3)]
	for piece in value.enemies: piece.cd = 99;piece.period = 99
	return value
func editor_geometry() -> Dictionary:
	var panel: Rect2 = game.training.panel_rect();var tabs = []
	for index in 4:
		var width = (panel.size.x-18)/4
		tabs.append(point(Vector2(panel.position.x+index*(width+6)+width/2,game.training.tabs_y()+(16 if not game.mobile_layout else 0)+19)))
	var mobile = game.mobile_layout
	var foot = game.ui_size.y-66
	return {"board":rect(game.training.board_bounds()),"panel":rect(panel),"tabs":tabs,"portrait":mobile and not game.compact_landscape,
		"recent":point(Rect2(184,54,96,32).get_center() if mobile else Rect2(244,62,114,34).get_center()),
		"presets":point(Rect2(92,54,84,32).get_center() if mobile else Rect2(132,62,102,34).get_center()),
		"save":point(Rect2(16,foot,126,50).get_center()),"play":point(Rect2(284,foot,game.ui_size.x-300,50).get_center()),
		"home":point(Rect2(game.ui_size.x-92,14,76,42).get_center()),"close":point(Rect2(game.ui_size.x-100,14,84,42).get_center()),
		"rename":point(Rect2(24,game.ui_size.y-70,(game.ui_size.x-64)/3,48).get_center()),
		"name_input":point(Rect2(36,game.ui_size.y*0.4,game.ui_size.x-72,52).get_center()),
		"name_confirm":point(Rect2(36,game.ui_size.y*0.4+70,game.ui_size.x-72,48).get_center())}
func run():
	DirAccess.make_dir_recursive_absolute(OUT + "fixtures")
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	game.settings.set_debug_mode(false)
	var reports = []
	for size in SIZES:
		game.training.playing = false;game.training_session.backup = {};game.training_session.entry = {}
		game.configure_layout(size);game.player_skill = "king";game.seed_value = 157000;game.new_expedition();game.route.enter(0);settle()
		game.route.save()
		check(game.route.save_error == OK and game.route.valid_snapshot(game.route.state,game.history.capture(),"game"),"formal seed validates")
		var stem = "training-" + str(int(size.x));var formal = stem+"-formal.cfg"
		var formal_raw = FileAccess.get_file_as_string(game.route.SAVE);write_text(formal,formal_raw)
		game.show_home();var home_entry = point(game.frontend.button_rect(5).get_center());var resume = point(game.frontend.button_rect(3).get_center())
		game.training.presets = [];game.training.saved_id = "";game.training.recent_id = "";game.training.load_error = false;game.training.loaded = true
		game.training.state = make_preset();game.training.open()
		check(game.training.validate_preset(game.training.state).is_empty(),"coupled decoy/hook preset validates")
		check(game.training.save_named(game.training.state.name),"ordinary named preset save")
		var preset_id = game.training.saved_id
		var envelope = {"version":game.training.SCHEMA,"presets":game.training.presets.duplicate(true),"recent_id":game.training.recent_id}
		var encoded = Marshalls.raw_to_base64(var_to_bytes(envelope))
		write_text(stem+"-presets.b64",encoded)
		write_text(stem+"-presets.json",JSON.stringify(json_value(envelope),"  ")+"\n")
		var report = {"stem":stem,"viewport":point(size),"logical_size":point(game.ui_size),"formal":formal,
			"presets":stem+"-presets.b64","presets_json":stem+"-presets.json","preset_id":preset_id,
			"saved_name":"QA-training-"+str(int(size.x)),"home_entry":home_entry,"resume":resume,"editor":editor_geometry()}
		check(game.training.play(),"ordinary editor starts actual trial")
		settle();var initial = normalized()
		check(game.hand == ["grappling_hook","decoy_card"],"treasure generates actual decoy card alongside hook")
		var board: Rect2 = game.BOARD_RECT
		var energy_rect = Rect2(550,583,106,32)
		if game.compact_landscape: energy_rect = Rect2(200,474,108,32)
		elif game.mobile_layout: energy_rect = Rect2(150,board.end.y+10,90,32)
		report.battle = {"board":rect(board),"hand":rect(game.full_hand_area()),"energy_rect":rect(energy_rect),
			"save":point(game.training_save_rect().get_center()),"return":point(game.home_rect().get_center()),
			"undo":point(game.UNDO_RECT.get_center()),"restart":point(game.RESTART_RECT.get_center()),
			"decoy_card":point(game.handui.exposed_point(game.hand.find("decoy_card"))),"target":point(game.cell_pos(Vector2i(6,3))),
			"origin":point(game.cell_pos(game.player)),"landing":point(game.cell_pos(Vector2i(5,4))),
			"landing_rect":rect(Rect2(game.cell_pos(Vector2i(5,4))-Vector2.ONE*game.CELL*0.44,Vector2.ONE*game.CELL*0.88)),
			"cell_size":game.CELL,"treasures":[]}
		for index in game.treasures.active_ids().size(): report.battle.treasures.append(rect(game.treasureui.icon_rect(index)))
		game.training.save_current_position();settle()
		game.select_card(game.hand.find("decoy_card"));game.handle_click(game.cell_pos(Vector2i(6,3)));settle()
		var after_decoy = normalized();var decoy = D.find(game.enemies)
		check(not decoy.is_empty() and decoy.pos == Vector2i(6,3) and decoy.hp == 2,"real card transaction places two-health decoy")
		report.battle.hook_card = point(game.handui.exposed_point(game.hand.find("grappling_hook")))
		game.training.save_current_position();settle()
		game.select_card(game.hand.find("grappling_hook"));game.handle_click(game.cell_pos(Vector2i(6,3)))
		check(game.grapple_targets.active and game.player == Vector2i(4,5) and game.energy == 3,"diagonal anchor leaves separate landing choice without spending")
		check(normalized() == after_decoy,"first hook stage changes no captured gameplay")
		game.handle_click(game.cell_pos(Vector2i(5,4)));settle()
		var after_hook = normalized()
		check(game.player == Vector2i(5,4) and game.energy == 2 and game.hand.is_empty() and game.deck == ["sword"] and game.active_displacements == 1,"landing commits one-cost hook without automatic draw")
		game.training.save_current_position();settle()
		var samples = {"version":game.training.SCHEMA,"presets":game.training.presets.duplicate(true),"recent_id":game.training.recent_id}
		report.snapshot_samples = stem+"-snapshots.b64";report.snapshot_samples_json = stem+"-snapshots.json"
		write_text(report.snapshot_samples,Marshalls.raw_to_base64(var_to_bytes(samples)))
		write_text(report.snapshot_samples_json,JSON.stringify(json_value(samples),"  ")+"\n")
		check(game.undo_action(),"actual undo restores post-decoy trial")
		check(normalized() == after_decoy,"undo restores exact pre-hook state")
		settle();check(game.reset_training(),"actual restart restores initial trial");settle()
		check(normalized() == initial,"restart restores complete initial trial")
		game.training.return_to_editor()
		check(game.training.state == envelope.presets[0].data,"return restores original editor preset")
		check(FileAccess.get_file_as_string(game.route.SAVE) == formal_raw,"all trial operations preserve formal save byte-for-byte")
		report.expected = {"initial":initial,"after_decoy":after_decoy,"after_hook":after_hook}
		reports.append(report)
	write_text("../replays.json",JSON.stringify({"schema":1,"formal_key":game.route.WEB_SAVE_KEY,"training_key":game.training.WEB_SAVE_KEY,
		"checks":checks,"failures":failures,"replays":reports},"  ")+"\n")
	print("TRAINING WEB FIXTURES %d checks, %d failures, %d replays" % [checks,failures,reports.size()])
	game.free();quit(1 if failures else 0)
