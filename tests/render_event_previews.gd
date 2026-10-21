extends Node
# Copy this script and scene into a disposable game copy as _event_visual_qa.*.
# Open _event_visual_qa.tscn and Run Current Scene with a real rendering driver.
# Do not export this scene. The disposable project must be under the workspace.
const OUT = "res://../verification/v0.13.0/events/native/"
var screenshots = 0
var assertions = 0
var reports = []
func _ready(): call_deferred("run")
func check(ok: bool):
	assertions += 1
	assert(ok)
func capture(viewport: SubViewport, game, name: String):
	game.clear_effects();game.queue_redraw()
	for i in 3: await RenderingServer.frame_post_draw
	var image = viewport.get_texture().get_image()
	check(not image.is_empty())
	check(image.save_png(OUT + name + ".png") == OK)
	screenshots += 1
func root_fixture(game, event_id: String):
	game.player_skill = "king";game.seed_value = 1313;game.new_expedition()
	game.route.enter(0);game.route.complete()
	game.collection = ["sword_plus", "sword", "spear", "life", "sword_plus"]
	game.lives = 4;game.rewards = [];game.navigation_lock = 0;game.input_lock = 0
	game.route.state.nodes[1].event_id = event_id
	game.route.enter(1)
	check(game.screen == "route_choice")
func choose(game, action: String, index: int = -1):
	for i in game.route.choices.size():
		var choice = game.route.choices[i]
		if choice.action == action and (index < 0 or choice.get("index", -1) == index):
			game.route.resolve(i);return
	check(false)
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	for size in [Vector2i(1280, 940), Vector2i(390, 844), Vector2i(844, 390), Vector2i(360, 640)]:
		var before = assertions
		var viewport = SubViewport.new();viewport.size = size
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS;add_child(viewport)
		var game = load("res://main.tscn").instantiate();viewport.add_child(game);game.settings.set_debug_mode(true)
		game.set_process(false);game.configure_layout(Vector2(size))
		viewport.size_2d_override = Vector2i(game.ui_size)
		viewport.size_2d_override_stretch = true;game.size = game.ui_size
		var suffix = "-" + str(size.x)
		game.new_expedition();game.route.tick(0)
		await capture(viewport, game, "map" + suffix)
		root_fixture(game, "herbalist")
		await capture(viewport, game, "herbalist" + suffix)
		root_fixture(game, "merchant")
		await capture(viewport, game, "merchant-offers" + suffix)
		choose(game, "select_exchange");choose(game, "exchange", 0)
		check(game.route.choice_mode == "confirm")
		await capture(viewport, game, "merchant-confirm" + suffix)
		root_fixture(game, "manual")
		await capture(viewport, game, "manual-options" + suffix)
		choose(game, "select_focus");choose(game, "focus", 0)
		check(game.route.choice_mode == "confirm")
		await capture(viewport, game, "manual-focus-confirm" + suffix)
		choose(game, "confirm");game.route.tick(1)
		check(game.collection.count("sword_plus") == 3 and game.collection.count("fatigue") == 1 and game.route.state.reward_debt == 0)
		await capture(viewport, game, "focus-result-map" + suffix)
		root_fixture(game, "manual")
		choose(game, "select_homework");choose(game, "homework", 0)
		await capture(viewport, game, "manual-homework-confirm" + suffix)
		choose(game, "confirm");game.route.tick(1)
		check(game.collection.count("sword_plus") == 2 and game.route.state.pending_homework == ["sword_plus"])
		await capture(viewport, game, "homework-result-map" + suffix)
		game.route.enter(4);game.debug_skip()
		check(game.phase == "reward" and game.route.rewards_blocked() and game.route.state.reward_debt == 0 and game.collection.count("sword_plus") == 3)
		await capture(viewport, game, "reward-homework-delivered" + suffix)
		game.choose_reward(-1);game.route.enter(6)
		check(game.route.state.nodes[6].kind == "workshop")
		await capture(viewport, game, "workshop" + suffix)
		game.new_expedition();game.route.enter(0);game.route.complete();game.route.enter(3)
		check(game.route.state.nodes[3].kind == "camp")
		await capture(viewport, game, "rest" + suffix)
		reports.append({"viewport": [size.x, size.y], "logical_size": [game.ui_size.x, game.ui_size.y], "assertions": assertions - before, "screenshots": 12})
		game.free();viewport.free()
	var file = FileAccess.open(OUT + "render-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"viewports": reports, "assertions": assertions, "screenshots": screenshots}, "  ") + "\n");file.close()
	print("NATIVE EVENT CAPTURE: ", screenshots, " screenshots, ", assertions, " assertions")
	get_tree().quit()
