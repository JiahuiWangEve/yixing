extends Node
# Run this scene with a real rendering driver (not --headless).
# Copy this script and the companion scene into game as _map_visual_qa.*,
# open _map_visual_qa.tscn, and run the current scene. Remove the two copies after.
const OUT = "res://../verification/v0.7.0/"
var reports = []
func _ready(): call_deferred("run")
func capture(viewport: SubViewport, game, name: String):
	game.queue_redraw()
	for i in 3: await RenderingServer.frame_post_draw
	var image = viewport.get_texture().get_image()
	assert(not image.is_empty())
	assert(image.save_png(OUT + name + ".png") == OK)
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	for size in [Vector2i(1280, 940), Vector2i(390, 844), Vector2i(844, 390), Vector2i(360, 640)]:
		var viewport = SubViewport.new()
		viewport.size = size
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var game = load("res://main.tscn").instantiate()
		viewport.add_child(game)
		game.set_process(false)
		game.configure_layout(Vector2(size))
		viewport.size_2d_override = Vector2i(game.ui_size)
		viewport.size_2d_override_stretch = true
		game.size = game.ui_size
		game.new_expedition()
		var route = game.route
		route.tick(0)
		var suffix = "-" + str(size.x)
		await capture(viewport, game, "native-map" + suffix)
		var p = route.position(route.state.nodes[0])
		route.pointer_press(p, 0);route.pointer_release(p, 0)
		assert(route.selected_node == 0 and route.state.pending == -1)
		await capture(viewport, game, "native-preview" + suffix)
		route.click(route.cancel_rect().get_center())
		assert(route.selected_node == -1)
		route.click(p);route.confirm();route.tick(0.86)
		assert(game.screen == "game" and route.state.pending == 0)
		await capture(viewport, game, "native-battle" + suffix)
		game.debug_skip();game.choose_reward(-1);route.tick(0)
		assert(game.screen == "map" and route.state.current == 0)
		await capture(viewport, game, "native-returned" + suffix)
		route.selected_node = 1;route.confirm();route.tick(0.4)
		await capture(viewport, game, "native-march" + suffix)
		route.tick(0.5)
		assert(game.screen == "route_choice" and route.state.pending == 1)
		await capture(viewport, game, "native-event" + suffix)
		route.resolve(route.choices.size() - 1);route.tick(0)
		route.scroll_y = 0;route.selected_node = 15
		await capture(viewport, game, "native-summit" + suffix)
		route.selected_node = -1;route.deck_view = true
		await capture(viewport, game, "native-deck" + suffix)
		reports.append({"viewport": [size.x, size.y], "logical_size": [game.ui_size.x, game.ui_size.y], "state_assertions": 5, "rendered_screens": 8})
		game.free();viewport.free()
	var file = FileAccess.open(OUT + "native-render.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(reports, "  ") + "\n");file.close()
	print("NATIVE MAP CAPTURE: four viewports, 20 state assertions, 32 screenshots")
	get_tree().quit()
