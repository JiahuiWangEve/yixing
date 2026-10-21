extends SceneTree
# Test-only valid saves plus real UI replay coordinates; no production hooks.
const OUT = "res://../verification/v0.14.1/airdrop/"
const ROUTE_FIELDS = ["chapter", "current", "pending", "visited", "done", "prepared", "reward_debt", "reward_blocked", "pending_homework", "homework_awarded", "victory_recorded"]
const BATTLE_FIELDS = ["phase", "turn", "lives", "energy", "collection", "deck", "hand", "discard", "rewards", "player", "encounter_state", "airdrop_recovery_turn", "basic_used", "card_move_used"]
var game
var steps = []
var reports = []
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
func point(p): return [p.x, p.y]
func json_value(value):
	if value is Vector2 or value is Vector2i: return point(value)
	if value is Array:
		var result = []
		for item in value: result.append(json_value(item))
		return result
	if value is Dictionary:
		var result = {}
		for key in value: result[key] = json_value(value[key])
		return result
	return value
func summary():
	var result = {"screen": game.screen, "recovery_active": game.recovery_active()}
	for key in ROUTE_FIELDS: result[key] = game.route.state[key]
	for key in BATTLE_FIELDS: result[key] = game.get(key)
	result.encounters = []
	for node in game.route.state.nodes: result.encounters.append(node.encounter)
	result.enemies = []
	for enemy in game.enemies:
		var piece = enemy.duplicate(true);piece.erase("visual");result.enemies.append(piece)
	return json_value(result)
func settle():
	game.clear_effects();game.input_lock = 0;game.navigation_lock = 0;game.initial_threat = 0
	game.handui.reset();game.route.save()
func step(kind: String, label: String, inputs: Array):
	# Record actual production animation/navigation lock before clearing native
	# effects. Web input needs this boundary as well as the persisted state.
	var wait_ms = ceili(maxf(game.input_lock, game.navigation_lock) * 1000.0) + 100
	settle();steps.append({"kind": kind, "label": label, "inputs": inputs, "wait_ms": wait_ms, "expected": summary()})
func taps(positions: Array) -> Array:
	var result = []
	for position in positions: result.append({"action": "tap", "point": point(position)})
	return result
func attack(index: int, target: Vector2i, label: String, drag: bool = false):
	var from = game.handui.exposed_point(index);var to = game.cell_pos(target)
	var inputs = [{"action": "drag", "from": point(from), "to": point(to)}] if drag else taps([from, to])
	game.play_card(index, target);step("action", label, inputs)
func fresh(size: Vector2, lethal: bool = false):
	game.configure_layout(size);game.seed_value = 14141;game.player_skill = "king";game.new_expedition();game.route.enter(0)
	game.enemies = [];game.next_enemy_uid = 1;game.add_enemy("g", Vector2i(4, 0), 999)
	game.enemies[0].hp = 3 if lethal else 9;game.enemies[0].max_hp = game.enemies[0].hp
	if not lethal:
		for spec in [[3, 5, 4], [5, 5, 3], [4, 4, 4], [0, 4, 4]]:
			game.add_enemy("p", Vector2i(spec[0], spec[1]), 999)
			game.enemies.back().hp = spec[2];game.enemies.back().max_hp = spec[2]
	game.collection = ["airdrop", "breath", "spear"]
	game.hand = ["airdrop"] if lethal else game.collection.duplicate();game.hand_ids = [];game.deck = [];game.discard = [];game.rewards = []
	game.energy = 3 if lethal else 4;game.lives = 1 if lethal else 4;game.player = Vector2i(4, 9)
	if lethal:
		game.route.state.pending_homework = ["spear_plus"];game.route.state.reward_debt = 1
	game.plan_intents();settle();steps = []
func save_fixture(name: String, size: Vector2):
	check(game.route.valid_snapshot(game.route.state, game.history.capture(), "game"), name + " is a valid ordinary save")
	var filename = name + "-" + str(int(size.x)) + ".cfg"
	var file = FileAccess.open(OUT + "fixtures/" + filename, FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(game.route.SAVE));file.close()
	game.screen = "home";var resume = point(game.frontend.button_rect(3).get_center());game.screen = "game"
	return {"name": name, "fixture": filename, "viewport": point(size), "logical_size": point(game.ui_size), "resume": resume, "initial": summary()}
func survive(size: Vector2):
	fresh(size)
	var report = save_fixture("survive_recovery", size)
	attack(0, Vector2i(4, 5), "airdrop-lands-and-exhausts", game.mobile_layout)
	check(game.player == Vector2i(4, 5) and game.lives == 3 and game.energy == 1, "real landing charges exactly three energy and one life")
	check(game.enemies.size() == 4 and game.enemies[1].hp == 1 and game.enemies[2].hp == 1 and game.enemies[3].hp == 4, "3x3 deals exactly three per enemy without touching outside")
	check("airdrop" not in game.hand and "airdrop" not in game.discard and "airdrop" in game.collection, "airdrop exhausts only this battle copy")
	check(game.airdrop_recovery_turn == 2 and not game.recovery_active(), "recovery is pending, not immediate")
	var inputs = taps([game.handui.exposed_point(0), game.END_TURN_RECT.get_center()])
	game.play_card(0, game.player);step("action", "current-turn-can-still-play", inputs)
	check(game.energy == 2 and game.hand == ["spear"], "current-turn breath still resolves")
	inputs = taps([game.cell_pos(Vector2i(4, 6))]);game.basic_move(Vector2i(4, 6));step("action", "current-turn-can-still-move", inputs)
	check(game.player == Vector2i(4, 6) and game.lives == 3, "current-turn unused free move remains available")
	game.end_turn();step("action", "next-turn-recovery-lock", taps([game.END_TURN_RECT.get_center()]))
	check(game.turn == 2 and game.recovery_active() and not game.free_card_available(), "following player turn locks actions")
	var before = summary();var card = game.handui.exposed_point(0)
	inputs = taps([card, game.cell_pos(Vector2i(4, 4)), game.cell_pos(Vector2i(5, 6))])
	inputs.append({"action": "drag", "from": point(card), "to": point(game.cell_pos(Vector2i(4, 4)))})
	game.select_card(0);game.play_card(0, Vector2i(4, 4));game.basic_move(Vector2i(5, 6))
	check(not game.gesture.press(card, "touch"), "recovery rejects card drag start")
	step("blocked", "recovery-rejects-card-drag-and-free-step", inputs)
	check(summary() == before, "recovery attempts cannot mutate saved gameplay state")
	if game.mobile_layout:
		game.route.save();check(game.route.resume(), "recovery save resumes")
		step("reload", "reload-preserves-recovery", [])
		check(game.recovery_active(), "recovery lock persists across Continue")
	inputs = taps([game.END_TURN_RECT.get_center()]) if game.mobile_layout else [{"action": "key", "key": "Space"}]
	game.end_turn();step("action", "skip-recovery-with-button" if game.mobile_layout else "skip-recovery-with-space", inputs)
	check(game.turn == 3 and not game.recovery_active() and game.airdrop_recovery_turn == 0, "one skipped turn restores actions")
	attack(0, Vector2i(4, 4), "card-works-after-recovery")
	check(game.energy == 1 and game.R.occupied(Vector2i(4, 4), game.enemies) < 0, "formerly blocked spear now resolves")
	inputs = taps([game.cell_pos(Vector2i(5, 6))]);game.basic_move(Vector2i(5, 6));step("action", "free-step-works-after-recovery", inputs)
	check(game.player == Vector2i(5, 6) and game.lives == 3, "free move also restored with remaining life intact")
	report.steps = steps.duplicate(true);reports.append(report)
func sacrifice(size: Vector2):
	fresh(size, true)
	var report = save_fixture("one_life_general_kill", size)
	attack(0, Vector2i(4, 1), "zero-life-loses-despite-general-kill", true)
	check(game.lives == 0 and game.phase == "dead" and not game.general_alive(), "simultaneous general death cannot override sacrifice loss")
	check(not game.route.state.victory_recorded and game.rewards.is_empty() and game.route.state.pending_homework == ["spear_plus"] and game.route.state.reward_debt == 1 and game.collection == ["airdrop", "breath", "spear"], "no reward or homework is awarded on zero-life defeat")
	report.steps = steps.duplicate(true);reports.append(report)
func run():
	DirAccess.make_dir_recursive_absolute(OUT + "fixtures")
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	for size in [Vector2(1280, 940), Vector2(390, 844)]: survive(size)
	sacrifice(Vector2(390, 844))
	var file = FileAccess.open(OUT + "replays.json", FileAccess.WRITE);file.store_string(JSON.stringify(reports, "  ") + "\n");file.close()
	print("AIRDROP WEB FIXTURES ", reports.size(), " replays, ", checks, " checks, ", failures, " failures")
	game.free();quit(1 if failures else 0)
