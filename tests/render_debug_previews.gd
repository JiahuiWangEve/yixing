extends Node
# Copy into game/_debug_visual_qa.gd with the companion scene for GUI F6 QA.
const OUT = "res://../verification/v0.14.4/debug/native/"
func _ready(): call_deferred("run")
func capture(viewport, game, name):
	game.queue_redraw()
	for frame in 4: await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(OUT + name + ".png")
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	for size in [Vector2i(1280,940),Vector2i(390,844),Vector2i(360,640),Vector2i(844,390)]:
		var viewport = SubViewport.new();viewport.size = size;viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS;add_child(viewport)
		var game = load("res://main.tscn").instantiate();viewport.add_child(game);game.set_process(false);game.configure_layout(Vector2(size))
		viewport.size_2d_override = Vector2i(game.ui_size);viewport.size_2d_override_stretch = true;game.size = game.ui_size
		game.settings.set_debug_mode(false);game.show_home()
		await capture(viewport,game,"home-off-"+str(size.x))
		game.frontend.activate(4)
		await capture(viewport,game,"home-on-"+str(size.x))
		game.frontend.activate(4);game.new_expedition();game.route.enter(0)
		await capture(viewport,game,"battle-off-three-"+str(size.x))
		for i in 3:
			game.input_lock = 0;game.navigation_lock = 0;game.history.record("preview");game.energy += 1;assert(game.undo_action())
		await capture(viewport,game,"battle-off-zero-"+str(size.x))
		game.show_home();game.frontend.activate(4);assert(game.route.resume())
		await capture(viewport,game,"battle-on-unlimited-"+str(size.x))
		game.settings.set_debug_mode(false);viewport.queue_free()
		await get_tree().process_frame
	FileAccess.open(OUT+"complete.txt",FileAccess.WRITE).store_string("20 native screenshots rendered")
	get_tree().quit()
