extends Node
# Native GUI renderer, no debug shipping hook. Parent may copy into a temporary
# scene under game/ and open it with F6. No X server is started by this fixture.
const T = preload("res://treasure_system.gd")
const ROUTE_TEST = preload("res://../tests/route_test_helpers.gd")
const OUT = "res://../verification/v0.15.0/treasure-ui/native/"
func _ready(): call_deferred("run")
func capture(viewport, game, name: String):
	game.queue_redraw()
	for frame in 4: await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(OUT + name + ".png")
func pending_choice(game, role: String):
	game.player_skill = role;game.new_expedition()
	var boss = ROUTE_TEST.kind_id(game.route, "boss");ROUTE_TEST.before(game.route, boss);game.route.enter(boss)
	game.settle_victory();game.presentation.clear();game.input_lock = 0;game.navigation_lock = 0;game.choose_reward(-1)
	game.treasureui.tick(0)
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	for size in [Vector2i(1280,940),Vector2i(390,844),Vector2i(360,640),Vector2i(844,390)]:
		var viewport = SubViewport.new();viewport.size = size;viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS;add_child(viewport)
		var game = load("res://main.tscn").instantiate();viewport.add_child(game);game.set_process(false);game.tutorial.stop();game.configure_layout(Vector2(size))
		viewport.size_2d_override = Vector2i(game.ui_size);viewport.size_2d_override_stretch = true;game.size = game.ui_size
		var suffix = "-" + str(size.x)
		game.show_home();await capture(viewport,game,"home" + suffix)
		game.frontend.activate(0);await capture(viewport,game,"role-selection" + suffix)
		game.show_home();game.frontend.activate(2);await capture(viewport,game,"settings" + suffix)
		game.player_skill = "king";game.new_expedition();game.route.enter(0);game.route.complete()
		ROUTE_TEST.enter_next(game,"event","merchant");await capture(viewport,game,"merchant-offers" + suffix)
		for role in ["king", "horse", "artillery"]:
			pending_choice(game,role)
			await capture(viewport,game,"choice-" + role + suffix)
			if game.treasureui.scroll_limit() > 0:
				game.treasureui.scroll_y = game.treasureui.scroll_limit();await capture(viewport,game,"choice-" + role + "-bottom" + suffix)
		pending_choice(game,"king");game.route.choose_treasure("tiger_tally")
		game.treasure_battle.tiger_moves = 2;game.route.tick(0);game.treasureui.tick(0)
		await capture(viewport,game,"map-icon" + suffix)
		game.information.candidate(game.treasureui.icon_rect().get_center(), "mouse");game.information.tick(0.31)
		await capture(viewport,game,"map-tooltip" + suffix);game.information.clear()
		game.route.enter(0);game.presentation.clear();game.input_lock = 0;game.navigation_lock = 0;game.clear_effects();game.initial_threat = 0
		game.treasure_battle.tiger_moves = 2;game.player_visual = game.cell_pos(game.player);game.hover = Vector2i(-1,-1)
		await capture(viewport,game,"battle-tiger-progress" + suffix)
		game.information.candidate(game.treasureui.icon_rect().get_center(), "mouse");game.information.tick(0.31)
		await capture(viewport,game,"battle-tooltip" + suffix);game.information.clear()
		for spec in [["wind_horseshoe","wind_used"],["battle_tassel","tassel_ready"],["spring_bit","spring_kills"],["gate_cannon_seal","gate_ready"],["roving_axle","axle_used"],["life_talisman","talisman_used"]]:
			game.player_skill = T.DATA[spec[0]].role;game.route.state.treasure_id = spec[0];game.treasures.reset_battle();game.active_displacements = 1
			game.treasure_battle[spec[1]] = 1 if spec[1] == "spring_kills" else true
			await capture(viewport,game,"battle-" + spec[0] + suffix)
			if spec[0] == "life_talisman":
				game.treasureui.trigger("revive");game.treasureui.tick(0.25);await capture(viewport,game,"battle-revival-pulse" + suffix);game.treasureui.tick(1)
		viewport.queue_free();await get_tree().process_frame
	FileAccess.open(OUT + "complete.txt",FileAccess.WRITE).store_string("Four native sizes: three profession choices, map and battle icon/tooltips, trigger badges and revival pulse.\n")
	get_tree().quit()
