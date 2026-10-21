extends Node
# GUI-only QA: copy this and its companion scene to game/_patch_visual_qa.*,
# open that scene in the independent project and press F6. Do not commit copies.
const OUT = "res://../verification/v0.14.5/native/"
var images = 0
var backups = {}
func _ready(): call_deferred("run")
func capture(viewport, game, name):
	game.queue_redraw()
	for frame in 4: await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().save_png(OUT + name + ".png") == OK)
	images += 1
func touch(game, pos, pressed):
	var event = InputEventScreenTouch.new();event.index = 0;event.position = pos;event.pressed = pressed
	game._input(event)
func tap(game, pos): touch(game, pos, true);touch(game, pos, false)
func battle(game):
	game.new_run();game.screen = "game";game.phase = "play";game.enemies = []
	game.add_enemy("g", Vector2i(4,0), 99);game.player = Vector2i(4,8)
	game.hand = ["sword", "spear", "breath"];game.hand_ids = [];game.deck = ["diagonal"];game.discard = [];game.energy = 4
	game.clear_effects();game.navigation_lock = 0;game.sync_hand_ids();game.handui.reset()
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	for path in [preload("res://route_map.gd").SAVE, preload("res://game_settings.gd").SAVE]:
		backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	for size in [Vector2i(1280,940),Vector2i(390,844),Vector2i(360,640),Vector2i(844,390)]:
		var viewport = SubViewport.new();viewport.size = size;viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS;add_child(viewport)
		var game = load("res://main.tscn").instantiate();viewport.add_child(game);game.set_process(false);game.configure_layout(Vector2(size))
		viewport.size_2d_override = Vector2i(game.ui_size);viewport.size_2d_override_stretch = true;game.size = game.ui_size
		var suffix = "-" + str(size.x)
		game.settings.set_debug_mode(false);game.audio_system.set_muted(false);game.show_home()
		await capture(viewport,game,"home"+suffix)
		tap(game,game.frontend.button_rect(2).get_center());assert(game.screen == "settings")
		await capture(viewport,game,"settings-sound-on"+suffix)
		tap(game,game.frontend.button_rect(0).get_center());assert(game.audio_system.muted)
		await capture(viewport,game,"settings-sound-off"+suffix)
		battle(game)
		var from = game.handui.exposed_point(0);var zone = game.pass_drop_rect().get_center()
		tap(game,from);assert(game.pass_zone_visible())
		await capture(viewport,game,"tap-selected-zone"+suffix)
		game.energy = 2
		await capture(viewport,game,"tap-selected-disabled"+suffix)
		battle(game);from = game.handui.exposed_point(0)
		touch(game,from,true);assert(game.pass_zone_visible() and not game.gesture.dragging)
		await capture(viewport,game,"held-before-drag"+suffix)
		var drag = InputEventScreenDrag.new();drag.index = 0;drag.position = zone;game._input(drag)
		assert(game.gesture.pass_zone_state().highlighted)
		await capture(viewport,game,"drag-hover-zone"+suffix)
		game.energy = 2;assert(not game.gesture.pass_zone_state().enabled)
		await capture(viewport,game,"drag-hover-disabled"+suffix)
		game.cancel_gesture();game.cancel_selection();game.presentation.upgrade("sword","sword_plus",0)
		game.presentation.tick(0.3)
		await capture(viewport,game,"upgrade-old-030s"+suffix)
		game.presentation.tick(1.2)
		await capture(viewport,game,"upgrade-new-150s"+suffix)
		game.presentation.tick(0.49);assert(game.presentation.active())
		game.presentation.tick(0.02);assert(not game.presentation.active())
		viewport.queue_free();await get_tree().process_frame
	for path in backups:
		if backups[path] == null: DirAccess.remove_absolute(path)
		else: FileAccess.open(path,FileAccess.WRITE).store_buffer(backups[path])
	FileAccess.open(OUT+"complete.txt",FileAccess.WRITE).store_string("%d native GUI screenshots rendered; upgrade visible through 1.99s, closed by 2.01s. No physical listening test.\n" % images)
	get_tree().quit()
