extends Node
const OUT = "res://../verification/v0.10.0/native/"
var screenshots = 0
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
func _ready(): call_deferred("run")
func capture(viewport: SubViewport, game, name: String):
	game.clear_effects();game.handui.reset();game.queue_redraw()
	for frame in 3: await RenderingServer.frame_post_draw
	var image = viewport.get_texture().get_image()
	check(not image.is_empty(), "nonempty rendered image")
	check(image.save_png(OUT + name + ".png") == OK, "save rendered image")
	screenshots += 1
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	for size in [Vector2i(1280, 940), Vector2i(390, 844), Vector2i(844, 390), Vector2i(360, 640)]:
		var viewport = SubViewport.new();viewport.size = size;viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var game = load("res://main.tscn").instantiate();viewport.add_child(game);game.set_process(false)
		game.configure_layout(Vector2(size));viewport.size_2d_override = Vector2i(game.ui_size);viewport.size_2d_override_stretch = true;game.size = game.ui_size
		var suffix = "-" + str(size.x)
		for id in ["quick_pawns", "river_cannon", "rook_pressure", "horse_cannon", "palace_guard", "two_wings", "palace_final"]:
			game.new_expedition()
			var node = game.route.state.nodes[0]
			node.kind = "boss" if id == "palace_final" else ("battle" if id == "quick_pawns" else "elite")
			node.encounter = {"id": id, "tier": node.kind, "rules": ["palace_rotation", "last_stand"] if id == "palace_final" else ([] if id == "quick_pawns" else [game.ENCOUNTERS.RULE_FOR[id]])}
			game.route.enter(0)
			if id == "horse_cannon": game.encounter_state.phases = 4;game.encounter_state.spawn_cell = Vector2i(0, 0)
			if id == "two_wings": game.damage_enemy(0, 0, 1)
			game.hover = Vector2i(4, 0);game.mouse_pos = Vector2(-100, -100)
			await capture(viewport, game, id + suffix)
			if id == "rook_pressure":
				for enemy in game.enemies:
					if enemy.kind == "r":
						enemy.cd = 1;game.hover = enemy.pos;game.mouse_pos = game.cell_pos(enemy.pos)
				game.plan_intents()
				await capture(viewport, game, "ready-rook-selected" + suffix)
			check(not game.encounter_rules_rect().intersects(game.BOARD_RECT) if game.mobile_layout else true, "rules button outside board")
			check(not game.encounter_rules_rect().intersects(game.END_TURN_RECT) if game.mobile_layout else true, "rules button outside end turn")
			if id == "palace_final" and game.mobile_layout:
				game.encounter_info_open = true;game.queue_redraw()
				for frame in 3: await RenderingServer.frame_post_draw
				check(viewport.get_texture().get_image().save_png(OUT + "rules-modal" + suffix + ".png") == OK, "modal saved")
				screenshots += 1
		game.free();viewport.free()
	var file = FileAccess.open(OUT + "render-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"screenshots": screenshots, "checks": checks, "failures": failures}, "  ") + "\n");file.close()
	print("ENEMY RENDER ", screenshots, " screenshots; ", checks, " checks; ", failures, " failures")
	get_tree().quit(1 if failures else 0)
