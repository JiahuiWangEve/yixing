extends Node
# Run with a real renderer, never --headless.
# Copy this script and its scene into game as _card_visual_qa.gd/.tscn;
# run that scene, then remove those copies. Do not export the QA scene.
const OUT = "res://../verification/v0.8.0/"
const PREVIEWS = ["sweep", "shock", "pierce", "guard", "suppress", "chain_assault", "permanent_stake", "reload", "cannon_shot_march", "cannon_shot_attack"]
var reports: Array = []
var screenshots = 0
var incomplete = 0

func _ready(): call_deferred("run")

func capture(viewport: SubViewport, game, name: String):
	game.clear_effects()
	game.handui.reset();game.sync_hand_ids();game.handui.sync()
	for frame in 30: game.handui.tick(0.05)
	game.queue_redraw()
	for frame in 3: await RenderingServer.frame_post_draw
	var image = viewport.get_texture().get_image()
	assert(not image.is_empty())
	assert(image.save_png(OUT + name + ".png") == OK)
	screenshots += 1

func fixture(game, identity: String):
	game.player_skill = identity;game.new_run()
	game.player = Vector2i(4, 5);game.enemies = [];game.hand_ids = []
	game.add_enemy("g", Vector2i(4, 0), 99)
	for position in [Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 3)]:
		game.add_enemy("e", position, 3)
		game.enemies.back().hp = 5;game.enemies.back().max_hp = 5
	game.phase = "play";game.energy = 3;game.lives = 3
	game.input_lock = 0;game.navigation_lock = 0;game.initial_threat = 0
	game.mouse_pos = Vector2(-100, -100);game.hover = Vector2i(-1, -1)
	game.discard = [];game.selected = -1;game.free_selected = false

func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	for size in [Vector2i(1280, 940), Vector2i(390, 844), Vector2i(844, 390), Vector2i(360, 640)]:
		var viewport = SubViewport.new()
		viewport.size = size
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var game = load("res://main.tscn").instantiate()
		viewport.add_child(game);game.set_process(false)
		game.configure_layout(Vector2(size))
		viewport.size_2d_override = Vector2i(game.ui_size)
		viewport.size_2d_override_stretch = true
		game.size = game.ui_size
		var suffix = "-" + str(size.x)
		var report = {"viewport": [size.x, size.y], "logical_size": [game.ui_size.x, game.ui_size.y], "previews": [], "hand_screens": 3}
		for identity in ["king", "horse", "artillery"]:
			fixture(game, identity)
			match identity:
				"king": game.hand = ["sweep", "shock", "pierce", "guard", "suppress", "life"]
				"horse": game.hand = ["straight", "advance", "retreat_strike", "knight_assault", "chain_assault", "pursuit"]
				"artillery": game.hand = ["stake", "cannon_shot", "deploy", "pack", "permanent_stake", "reload"]
			await capture(viewport, game, "native-cards-" + identity + suffix)
		for entry in PREVIEWS:
			var id = str(entry).trim_suffix("_march").trim_suffix("_attack")
			var identity = "horse" if id == "chain_assault" else ("artillery" if id in ["permanent_stake", "reload", "cannon_shot"] else "king")
			fixture(game, identity)
			game.hand = ["sword", "spear", id, "diagonal", "breath", "sword"]
			game.selected = 2
			if id == "chain_assault": game.active_displacements = 2
			if id == "guard": game.shield_charges = 1
			if id == "pierce": game.queue_bleed(1, 2)
			if id == "reload": game.reload_ready = true
			if id == "permanent_stake":
				game.TACTICS.apply(game, "permanent_stake", Vector2i(3, 5), -1)
				game.TACTICS.apply(game, "stake", Vector2i(3, 6), -1)
			if id == "cannon_shot":
				game.reload_ready = true
				game.artillery_mode = "attack" if str(entry).ends_with("_attack") else "march"
				game.enemies[1].kind = "stake";game.enemies[1].permanent = true
			await capture(viewport, game, "native-card-preview-" + str(entry) + suffix)
			var transform = game.handui.card_transform(2)
			var dimensions = Vector2(transform.x.length(), transform.y.length()) * game.handui.card_size()
			var layout = game.handui.text_layout(2, dimensions, true)
			var complete = bool(layout.complete)
			if not complete: incomplete += 1
			report.previews.append({"card": entry, "card_size": [dimensions.x, dimensions.y], "font_size": layout.font_size, "text_lines": layout.lines.size(), "available_lines": layout.available_lines, "complete": complete})
		reports.append(report)
		game.free();viewport.free()
	var file = FileAccess.open(OUT + "native-card-render.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"screenshots": screenshots, "incomplete_previews": incomplete, "viewports": reports}, "  ") + "\n")
	file.close()
	print("NATIVE CARD CAPTURE: four viewports, ", screenshots, " screenshots, ", incomplete, " incomplete previews")
	get_tree().quit(1 if incomplete else 0)
