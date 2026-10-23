extends SceneTree
# Ordinary validated production saves for exported-Web input and pixel checks.
# This driver is test-only; the exported game has no fixture or gameplay API.
const OUT = "res://../verification/v0.15.5/enemy-impact/"
const CASES = ["cannon_hit", "rook_hit", "shield_block", "lethal_hit"]
var game
var checks = 0
var failures = 0

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("ENEMY IMPACT FIXTURE: " + label)
func point(value) -> Array: return [value.x, value.y]
func rectangle(value: Rect2) -> Array: return [value.position.x, value.position.y, value.size.x, value.size.y]
func normalized() -> Dictionary:
	var state: Dictionary = game.history.capture();state.erase("initial_threat")
	for enemy in state.enemies: enemy.erase("visual")
	return state
func save_fixture(filename: String):
	check(game.route.valid_snapshot(game.route.state, game.history.capture(), "game"), filename + " validates under unchanged production rules")
	game.route.save()
	var file = FileAccess.open(OUT + "fixtures/" + filename, FileAccess.WRITE)
	check(file != null, filename + " can be written")
	if file != null:
		file.store_string(FileAccess.get_file_as_string(game.route.SAVE));file.close()
func add(kind: String, cell: Vector2i) -> Dictionary:
	game.add_enemy(kind, cell, 3)
	var enemy: Dictionary = game.enemies.back()
	enemy.normal_moves = 0;enemy.march_normal_moves = 0;enemy.bonus_pending = false
	enemy.action_credits = 0;enemy.action_credit_delay = 0
	return enemy
func setup(name: String) -> Dictionary:
	game.player_skill = "king";game.seed_value = 155501;game.new_expedition();game.route.enter(0)
	game.enemies = [];game.next_enemy_uid = 1
	# Keep the generated, reachable route and its authentic encounter state.
	# Positions are deterministic board fixtures saved through the normal format.
	game.player = Vector2i(4, 5)
	var actor = add("c" if name == "cannon_hit" else "r", Vector2i(4, 0) if name == "cannon_hit" else Vector2i(0, 5))
	if name == "cannon_hit": add("p", Vector2i(4, 2))
	add("g", Vector2i(3, 0))
	game.lives = 1 if name == "lethal_hit" else 3
	game.shield_charges = 1 if name == "shield_block" else 0
	game.hand = [];game.hand_ids = [];game.deck = [];game.discard = [];game.logs = []
	game.screen = "game";game.phase = "play";game.turn = 1;game.notice = "";game.initial_threat = 0
	game.navigation_lock = 0;game.input_lock = 0;game.hover = Vector2i(-1, -1);game.mouse_pos = Vector2(-100, -100)
	game.clear_effects();game.presentation.clear();game.card_picker.close();game.history.clear()
	game.plan_intents();game.refresh_free_card();game.sync_hand_views();game.battle_restart.capture()
	check(game.battle_restart.available(), name + " has a real restart checkpoint")
	check(game.R.attacks(actor, game.player, game.enemies), name + " actual rules identify intended attacker")
	check(game.enemies.filter(func(enemy): return game.R.attacks(enemy, game.player, game.enemies)).size() == 1, name + " has exactly one attacker")
	return actor
func run():
	DirAccess.make_dir_recursive_absolute(OUT + "fixtures")
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	game.settings.set_debug_mode(false)
	var reports = []
	for size in [Vector2(1280, 940), Vector2(390, 844)]:
		game.configure_layout(size)
		for name in CASES:
			var actor: Dictionary = setup(name)
			var stem: String = name + "-" + str(int(size.x))
			var report = {"name": name, "stem": stem, "viewport": point(size), "logical_size": point(game.ui_size),
				"initial": stem + "-initial.cfg", "after": stem + "-after.cfg",
				"end_turn": point(game.END_TURN_RECT.get_center()), "source": point(game.cell_pos(actor.pos)),
				"target": point(game.cell_pos(game.player)), "cell_size": game.CELL,
				"board_rect": rectangle(game.BOARD_RECT), "token_scale": minf(1.0, game.CELL / 54.0) if game.mobile_layout else 1.0,
				"attacker_uid": actor.uid, "attacker_kind": actor.kind, "duration": 0.34, "impact_at": 0.14}
			game.screen = "home";report.resume = point(game.frontend.button_rect(3).get_center());game.screen = "game"
			save_fixture(report.initial)
			var before = normalized();var checkpoint = game.battle_restart.snapshot.duplicate(true)
			check(game.route.resume() and normalized() == before, stem + " initial fixture resumes exactly through production save loader")
			check(game.battle_restart.snapshot == checkpoint, stem + " resume preserves immutable restart checkpoint")
			game.end_turn()
			var impacts = game.effects.filter(func(fx): return fx.kind == "enemy_impact")
			check(impacts.size() == 1 and impacts[0].attacker_uid == report.attacker_uid, stem + " produces exactly the intended collision")
			check(game.effects.filter(func(fx): return fx.kind == "move").is_empty(), stem + " keeps other board pieces stationary")
			check(game.lives == (3 if name == "shield_block" else (0 if name == "lethal_hit" else 2)), stem + " has the expected single damage or block")
			check(game.turn == (1 if name == "lethal_hit" else 2), stem + " resolves exactly one turn")
			check(game.phase == ("dead" if name == "lethal_hit" else "play"), stem + " reaches correct real outcome")
			var settled = normalized();game._process(5.0)
			check(normalized() == settled and game.effects.is_empty(), stem + " animation changes no combat state or RNG")
			save_fixture(report.after)
			check(game.route.resume() and normalized() == settled and game.effects.is_empty(), stem + " settled fixture resumes without replaying collision")
			reports.append(report)
	var file = FileAccess.open(OUT + "replays.json", FileAccess.WRITE)
	check(file != null, "replay manifest can be written")
	if file != null:
		file.store_string(JSON.stringify({"schema": 1, "web_save_key": game.route.WEB_SAVE_KEY, "checks": checks, "failures": failures, "replays": reports}, "  ") + "\n");file.close()
	print("ENEMY IMPACT FIXTURES %d checks, %d failures, %d replays" % [checks, failures, reports.size()])
	game.free();quit(1 if failures else 0)
