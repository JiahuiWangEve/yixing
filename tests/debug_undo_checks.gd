extends SceneTree
const T = preload("res://../tests/route_test_helpers.gd")
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
	else: print("PASS ", label)
func ready_action():
	game.input_lock = 0;game.navigation_lock = 0;game.presentation.clear()
func record():
	ready_action();game.history.record("test");game.energy += 1
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	DirAccess.remove_absolute(game.settings.SAVE)
	game.settings.load_settings()
	check(not game.settings.debug_mode, "missing settings defaults OFF")
	check(game.frontend.entries().size() == 6 and game.frontend.entries()[4] == "调试模式：关" and game.frontend.entries()[5] == "演武场 · 自由配置", "home toggle without old stage picker")
	for size in [Vector2(1280,940),Vector2(390,844),Vector2(390,660),Vector2(844,390)]:
		game.configure_layout(size)
		check(Rect2(Vector2.ZERO,game.ui_size).encloses(game.frontend.button_rect(4)), "toggle fits " + str(size))
	game.frontend.activate(4);game.settings.load_settings()
	check(game.settings.debug_mode, "home toggle ON persists")
	game.frontend.activate(4);game.settings.load_settings()
	check(not game.settings.debug_mode, "home toggle OFF persists")
	game.new_expedition();game.route.enter(0);ready_action()
	var before = game.history.capture()
	game.debug_skip()
	check(game.history.capture() == before and not game.presentation.active(), "OFF backend skip is inert")
	game.handle_click(game.debug_skip_rect().get_center())
	check(game.phase == "play", "OFF hidden skip hitbox is inert")
	check(not game.undo_action() and game.normal_undos_remaining == 3, "empty undo does not spend")
	record();game.input_lock = 1
	check(not game.undo_action() and game.normal_undos_remaining == 3, "animation lock does not spend")
	ready_action();game.navigation_lock = 1
	check(not game.history.undo() and game.normal_undos_remaining == 3, "direct undo cannot bypass navigation lock")
	ready_action();game.encounter_info_open = true
	check(not game.undo_action(), "rules overlay blocks undo")
	game.encounter_info_open = false
	game.presentation.victory()
	check(not game.undo_action() and game.normal_undos_remaining == 3, "presentation blocks undo without spending")
	game.presentation.clear()
	game.card_picker.active = true
	check(not game.undo_action() and game.normal_undos_remaining == 3, "picker blocks undo without spending")
	game.card_picker.close()
	check(game.undo_action() and game.normal_undos_remaining == 2, "successful normal undo spends one")
	var config = ConfigFile.new();config.load(game.route.SAVE)
	check(config.get_value("run","normal_undos_remaining") == 2, "successful undo saves immediately")
	record();var snapshot = game.history.capture()
	check(not snapshot.has("normal_undos_remaining"), "undo snapshot cannot restore budget")
	check(game.undo_action() and game.normal_undos_remaining == 1, "second undo spends once")
	record();game.settings.set_debug_mode(true)
	check(game.undo_action() and game.normal_undos_remaining == 1, "debug undo leaves normal allowance intact")
	for i in 5:
		record();check(game.undo_action(), "debug undo unlimited " + str(i))
	game.settings.set_debug_mode(false)
	record();check(game.undo_action() and game.normal_undos_remaining == 0, "switch OFF does not replenish")
	record();var history_size = game.history.entries.size()
	check(not game.undo_action() and game.history.entries.size() == history_size, "exhausted undo does not consume history")
	var key = InputEventKey.new();key.keycode = KEY_Z;key.ctrl_pressed = true;key.pressed = true
	game._input(key)
	check(game.normal_undos_remaining == 0 and game.history.entries.size() == history_size, "Ctrl Z shares budget guard")
	game.route.save();game.show_home();check(game.route.resume() and game.normal_undos_remaining == 0, "resume retains exhausted allowance")
	game.settings.set_debug_mode(true);ready_action();game.debug_skip()
	check(game.phase == "reward" and game.presentation.active(), "debug skip uses ordinary victory presentation")
	game.presentation.clear();game.choose_reward(-1);T.before(game.route, T.kind_id(game.route, "elite"));game.route.enter(T.kind_id(game.route, "elite"))
	check(game.normal_undos_remaining == 0, "next battle does not replenish")
	while game.route.chapter() == 1:
		if game.screen == "game":
			ready_action();game.debug_skip();game.presentation.clear();game.choose_reward(-1)
		elif game.screen == "route_choice": game.route.complete()
		elif game.screen == "treasure_choice":
			check(game.normal_undos_remaining == 0, "pending treasure does not replenish exhausted undo budget")
			check(game.route.choose_treasure(game.TREASURES.ids_for(game.player_skill)[1]), "actual chapter flow explicitly claims mandatory treasure")
		else: game.route.enter(game.route.legal()[0])
	check(game.normal_undos_remaining == 0, "actual chapter transition does not replenish")
	game.route.save()
	check(game.route.resume() and game.normal_undos_remaining == 0, "chapter save retains shared budget")
	config.load(game.route.SAVE);config.erase_section_key("run","normal_undos_remaining");config.save(game.route.SAVE)
	check(game.route.resume() and game.normal_undos_remaining == 3, "current saves without optional undo allowance default to three")
	config.load(game.route.SAVE);config.set_value("run","normal_undos_remaining", -1);config.save(game.route.SAVE)
	check(not game.route.resume() and game.normal_undos_remaining == 3, "malformed budget rejected without live mutation")
	game.normal_undos_remaining = 1;game.new_expedition()
	check(game.normal_undos_remaining == 3, "new expedition replenishes allowance")
	game.settings.set_debug_mode(false);game.start_tutorial(0);record()
	check(not game.undo_action() and game.normal_undos_remaining == 3, "tutorial does not spend")
	game.queue_free();print("DEBUG UNDO ", checks, " checks, ", failures, " failures");quit(1 if failures else 0)
