extends Node
# Copy this script and its scene into game as _seal_visual_qa.gd/.tscn.
# Run the scene with a real rendering driver; --headless cannot validate visuals.
const OUT = "res://../verification/v0.9.2/native/"
var reports = []
var assertions = 0
func _ready(): call_deferred("run")
func check(ok: bool):
	assertions += 1
	assert(ok)
func capture(viewport: SubViewport, game, name: String):
	game.queue_redraw()
	for i in 3: await RenderingServer.frame_post_draw
	var image = viewport.get_texture().get_image()
	check(not image.is_empty())
	check(image.save_png(OUT + name + ".png") == OK)
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	for size in [Vector2i(1280,940), Vector2i(390,844), Vector2i(844,390), Vector2i(360,640)]:
		var before = assertions
		var viewport = SubViewport.new()
		viewport.size = size;viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var game = load("res://main.tscn").instantiate()
		viewport.add_child(game);game.settings.set_debug_mode(true);game.set_process(false);game.configure_layout(Vector2(size))
		viewport.size_2d_override = Vector2i(game.ui_size);viewport.size_2d_override_stretch = true;game.size = game.ui_size
		game.new_expedition();var route = game.route;route.tick(0)
		var suffix = "-" + str(size.x)
		await capture(viewport, game, "map" + suffix)
		var p = route.position(route.state.nodes[0])
		route.pointer_press(p, 0);route.pointer_release(p, 0)
		check(route.selected_node == 0 and route.state.pending == -1)
		await capture(viewport, game, "selected" + suffix)
		route.click(route.map_rect().position + Vector2(4, 4));check(route.selected_node == -1)
		route.click(p);route.click(p);route.tick(0.86)
		check(game.screen == "game" and route.state.pending == 0)
		await capture(viewport, game, "battle" + suffix)
		game.debug_skip();game.choose_reward(-1);route.tick(0)
		check(game.screen == "map" and route.state.current == 0 and route.stamp_node == 0)
		await capture(viewport, game, "stamp-start" + suffix)
		route.tick(0.2)
		await capture(viewport, game, "stamp-press" + suffix)
		route.tick(route.STAMP_SECONDS + 0.1)
		await capture(viewport, game, "stamp-static" + suffix)
		route.save();check(route.resume());check(route.stamp_node == -1)
		route.tick(0);var next = route.position(route.state.nodes[1]);route.click(next);route.click(next);route.tick(0.4)
		await capture(viewport, game, "march" + suffix)
		route.tick(0.5);check(game.screen == "route_choice" and route.state.pending == 1)
		await capture(viewport, game, "event" + suffix)
		route.resolve(route.choices.size() - 1);route.tick(1)
		route.scroll_y = 0;route.selected_node = 15
		await capture(viewport, game, "summit" + suffix)
		route.selected_node = -1;route.click(route.deck_rect().get_center())
		await capture(viewport, game, "deck" + suffix)
		reports.append({"viewport": [size.x,size.y], "logical_size": [game.ui_size.x,game.ui_size.y], "assertions": assertions - before, "rendered_screens": 10})
		game.free();viewport.free()
	var file = FileAccess.open(OUT + "native-render.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"viewports":reports,"assertions":assertions,"screenshots":40}, "  ") + "\n");file.close()
	print("NATIVE SEAL MAP CAPTURE: four viewports, ", assertions, " assertions, 40 screenshots")
	get_tree().quit()
