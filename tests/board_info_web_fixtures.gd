extends SceneTree
# Valid production saves and coordinates only; no runtime QA interface is exported.
const OUT = "res://../verification/v0.14.7/board-info/"
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
func point(p) -> Array: return [p.x, p.y]
func rectangle(r: Rect2) -> Array: return [r.position.x, r.position.y, r.size.x, r.size.y]
func path_to(target: int) -> Array:
	var paths = [[0]]
	while not paths.is_empty():
		var path: Array = paths.pop_front()
		if path.back() == target: return path
		for next in game.route.state.nodes[path.back()].next:
			var branch = path.duplicate();branch.append(next);paths.append(branch)
	return []
func prepare():
	game.player_skill = "king";game.seed_value = 14747;game.new_expedition();game.route.generate(game.seed_value, 2)
	game.collection = ["sword_plus", "pierce", "sword"];game.lives = 3;game.screen = "map"
	for id in path_to(15):
		game.route.enter(id)
		if id == 15: break
		if game.screen == "game":
			game.debug_skip();game.input_lock = 0;game.navigation_lock = 0;game.choose_reward(-1)
		else:
			var leave = -1
			for i in game.route.choices.size():
				if game.route.choices[i].action == "leave": leave = i;break
			check(leave >= 0, "transit event can leave")
			if leave >= 0: game.route.resolve(leave)
	game.presentation.clear();game.clear_effects();game.input_lock = 0;game.navigation_lock = 0;game.initial_threat = 0
	game.enemies[0].cd = 3
	# Use real defeat/bleed hooks to create authentic, persisted statuses.
	for index in range(game.enemies.size() - 1, -1, -1):
		if game.enemies[index].kind == "a": game.damage_enemy(index, 0, 99)
	for index in game.enemies.size():
		if game.enemies[index].get("heavy", false) and game.enemies[index].kind == "e":
			game.damage_enemy(index, 0, 1);game.queue_bleed(index, 2);game.enemies[index].stun = 1
	game.player = Vector2i(6, 1);game.player_visual = game.cell_pos(game.player)
	game.hand = ["sword_plus", "pierce"];game.hand_ids = [];game.deck = [];game.discard = [];game.energy = 3
	game.clear_effects();game.handui.reset();game.sync_hand_views();game.selected = -1;game.free_selected = false
	game.board_info.cue_left = 0;game.history.clear()
func expected_popup(info: Dictionary, source: String) -> Rect2:
	# This is the same public component used by production main, not browser injection.
	var popup = load("res://information_popup.gd").new(game)
	popup.data = info;popup.source = source;popup.position = info.anchor.get_center();popup.layout()
	return popup.area
func item(pos: Vector2, source: String) -> Dictionary:
	var info: Dictionary = game.board_info.inspect_at(pos)
	check(not info.is_empty(), "inspection target exists")
	return {"point": point(pos), "key": info.key, "title": info.title, "popup": rectangle(expected_popup(info, source)), "lines": info.lines}
func run():
	DirAccess.make_dir_recursive_absolute(OUT + "fixtures")
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.settings.set_debug_mode(true)
	var reports = []
	for size in [Vector2(1280, 940), Vector2(390, 844), Vector2(360, 640), Vector2(844, 390)]:
		game.configure_layout(size);prepare()
		var suffix = str(int(size.x));var source = "mouse" if size.x == 1280 else "touch"
		game.route.save();check(game.route.valid_snapshot(game.route.state, game.history.capture(), game.screen), "ordinary fixture validates")
		FileAccess.open(OUT + "fixtures/board-" + suffix + ".cfg", FileAccess.WRITE).store_string(FileAccess.get_file_as_string(game.route.SAVE))
		var report = {"viewport": point(size), "logical_size": point(game.ui_size), "fixture": "board-" + suffix + ".cfg", "source": source}
		game.screen = "home";report.resume = point(game.frontend.button_rect(3).get_center());game.screen = "game"
		report.enemy = item(game.cell_pos(Vector2i(6, 0)), source)
		report.ghost = item(game.cell_pos(Vector2i(3, 0)), source)
		report.tag = item(game.board_info.tag_items()[1].anchor.get_center(), source)
		report.one_hp = point(game.cell_pos(Vector2i(4, 3)));report.full_hp = point(game.cell_pos(Vector2i(4, 0)))
		report.cell = game.CELL;report.card = point(game.handui.exposed_point(0));report.blank = [game.ui_size.x - 5, game.ui_size.y - 5]
		game.selected = 0
		report.preview = game.board_info.preview(0, Vector2i(6, 0))
		check(report.preview.affected.size() == 1 and report.preview.affected[0].damage == 2 and not report.preview.affected[0].down, "preview exact two damage, not down")
		report.attack_popup = rectangle(expected_popup(game.board_info.inspect_at(game.cell_pos(Vector2i(6, 0))), source))
		game.play_card(0, Vector2i(6, 0));game.clear_effects();game.route.save()
		FileAccess.open(OUT + "fixtures/board-" + suffix + "-after.cfg", FileAccess.WRITE).store_string(FileAccess.get_file_as_string(game.route.SAVE))
		report.after_fixture = "board-" + suffix + "-after.cfg";reports.append(report)
	FileAccess.open(OUT + "replays.json", FileAccess.WRITE).store_string(JSON.stringify(reports, "  "))
	game.free();print("BOARD WEB FIXTURES: %d checks; %d failures" % [checks, failures]);quit(1 if failures else 0)
