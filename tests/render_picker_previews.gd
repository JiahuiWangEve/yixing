extends Node
const OUT = "res://../verification/v0.14.3/picker/native/"
func _ready(): call_deferred("run")
func capture(viewport, game, name):
	game.card_picker.refresh();game.queue_redraw()
	for frame in 4: await RenderingServer.frame_post_draw
	var picture = viewport.get_texture().get_image()
	picture.save_png(OUT + name + ".png")
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	for size in [Vector2i(1280,940), Vector2i(390,844), Vector2i(360,640), Vector2i(844,390)]:
		var viewport = SubViewport.new();viewport.size = size;viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS;add_child(viewport)
		var game = load("res://main.tscn").instantiate();viewport.add_child(game);game.set_process(false);game.configure_layout(Vector2(size))
		viewport.size_2d_override = Vector2i(game.ui_size);viewport.size_2d_override_stretch = true;game.size = game.ui_size
		game.new_expedition();game.route.enter(0);game.route.complete();game.route.enter(3)
		game.collection = []
		for i in 24: game.collection.append(["sword", "sword_plus", "spear", "fatigue", "airdrop", "cannon_shot"][i % 6])
		game.route.refresh_choices();game.route.resolve(0)
		await capture(viewport, game, "grid-" + str(size.x))
		game.card_picker.scroll_y = game.card_picker.scroll_limit();game.card_picker.selected = 23
		await capture(viewport, game, "bottom-selected-" + str(size.x))
		game.card_picker.close()
		game.card_picker.open("view", "全部永久牌组", range(game.collection.size()), Callable(), Callable())
		await capture(viewport, game, "view-" + str(size.x))
		game.card_picker.close();game.route.picker_cancel()
		game.route.state.nodes[3].kind = "event";game.route.state.nodes[3].event_id = "manual";game.route.state.nodes[3].upgrade_seed = 42
		game.route.refresh_choices();game.route.resolve(2);game.route.resolve(0);game.presentation.elapsed = 0.2
		await capture(viewport, game, "upgrade-before-" + str(size.x))
		game.presentation.elapsed = 0.9
		await capture(viewport, game, "upgrade-after-" + str(size.x))
		game.presentation.clear();game.new_expedition();game.route.enter(0);game.debug_skip();game.presentation.elapsed = 0.5
		await capture(viewport, game, "victory-stamp-" + str(size.x))
		game.presentation.clear();viewport.queue_free()
		await get_tree().process_frame
	FileAccess.open(OUT + "complete.txt", FileAccess.WRITE).store_string("24 native screenshots rendered")
	get_tree().quit()
