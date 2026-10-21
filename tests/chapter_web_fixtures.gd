extends SceneTree
# Offline fixture driver. The exported build contains no QA API: browser tests
# replay these validated ordinary saves using real Continue/touch/reload inputs.
const OUT = "res://../verification/v0.14.0/chapter/"
const ROUTE_FIELDS = ["chapter", "current", "pending", "visited", "done", "prepared", "reward_debt", "reward_blocked", "pending_homework", "homework_awarded"]
const BATTLE_FIELDS = ["phase", "turn", "lives", "energy", "collection", "deck", "hand", "discard", "rewards", "player", "encounter_state"]
var game
var steps: Array = []
var reports: Array = []
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
func point(value): return [value.x, value.y]
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
func summary() -> Dictionary:
	var result = {"screen": game.screen}
	for key in ROUTE_FIELDS: result[key] = game.route.state[key]
	for key in BATTLE_FIELDS: result[key] = game.get(key)
	result.encounters = []
	for node in game.route.state.nodes: result.encounters.append(node.encounter)
	result.enemies = []
	for enemy in game.enemies:
		var piece = enemy.duplicate(true);piece.erase("visual");result.enemies.append(piece)
	return json_value(result)
func step(kind: String, label: String, taps: Array = [], wait_ms: int = -1):
	# In production this is called by autosave after input/animation settles.
	game.clear_effects();game.input_lock = 0;game.navigation_lock = 0;game.route.save()
	var value = {"kind": kind, "label": label, "taps": taps, "expected": summary()}
	if wait_ms >= 0: value.wait_ms = wait_ms
	steps.append(value)
func reload_step():
	game.route.save();check(game.route.resume(), "fixture resumes from real saved state")
	step("reload", "reload-continue")
func end_turn(label: String):
	game.input_lock = 0;game.navigation_lock = 0;game.end_turn()
	step("combat", label, [point(game.END_TURN_RECT.get_center())], 3000)
func victory(label: String):
	game.debug_skip();step("tap", label, [point(game.debug_skip_rect().get_center())], 1600)
func reward_return():
	var target = game.rewardui.confirm_rect().get_center() if game.route.rewards_blocked() else game.rewardui.choice_rect(2).get_center()
	game.input_lock = 0;game.navigation_lock = 0;game.choose_reward(-1)
	step("tap", "skip-reward-next-chapter", [point(target)])
func enter(id: int):
	game.route.focus_current()
	var target = game.route.position(game.route.state.nodes[id])
	check(game.route.map_rect().has_point(target), "chosen map node is visible")
	var taps = [point(target), point(game.route.confirm_rect().get_center())]
	game.route.enter(id);step("enter", "enter-first-battle", taps)
func text_height(value: String, width: float, font_size: int) -> float:
	var line = "";var height = float(font_size)
	for letter in value:
		if letter == "\n": line = "";height += font_size + 3;continue
		if not line.is_empty() and game.FONT.get_string_size(line + letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			line = "";height += font_size + 3
		line += letter
	return height
func rules_text_checks():
	for id in game.ENCOUNTERS.CHAPTER_TWO.TEMPLATES:
		var template = game.ENCOUNTERS.CHAPTER_TWO.TEMPLATES[id]
		var config = {"id": id, "tier": template.tier, "rules": [], "chapter": 2}
		var desc = game.ENCOUNTERS.details(config)
		var width = 318.0;var height = 150.0;var font_size = 15
		if game.mobile_layout:
			var area = game.encounter_panel_rect()
			width = area.size.x - 32;height = area.size.y - 148;font_size = 18
		var required = text_height(desc, width, font_size)
		print("CHAPTER RULE METRIC ", id, " ", game.ui_size, " needs=", required, " available=", height)
		check(required <= height, "full " + id + " rules fit " + str(game.ui_size) + " without clipping")
func rules_panel():
	if not game.mobile_layout: return
	var area = game.encounter_panel_rect()
	var desc = game.ENCOUNTERS.details(game.encounter_state.config)
	check(text_height(desc, area.size.x - 32, 18) <= area.size.y - 148, "complete chapter rules fit the mobile panel without clipping")
	# Opening/closing is transient, deliberately excluded from persisted saves.
	steps.append({"kind": "panel", "label": "rules-open", "taps": [point(game.encounter_rules_rect().get_center())], "expected": summary()})
	steps.append({"kind": "close_panel", "label": "rules-close", "taps": [point(game.encounter_close_rect().get_center())], "expected": summary()})
func clear_input():
	game.clear_effects();game.input_lock = 0;game.navigation_lock = 0;game.initial_threat = 0
	game.selected = -1;game.free_selected = false;game.handui.reset();game.plan_intents()
func path_to(target: int) -> Array:
	var paths = [[0]]
	while not paths.is_empty():
		var path: Array = paths.pop_front()
		if path.back() == target: return path
		for next in game.route.state.nodes[path.back()].next:
			var branch = path.duplicate();branch.append(next);paths.append(branch)
	return []
func prepare(chapter: int, encounter_id: String = ""):
	# Choose a generated, reachable authored encounter, rather than fabricating a
	# route or weakening production save validation for the test.
	var target = -1
	for attempt in 100:
		game.seed_value = 1414 + attempt;game.player_skill = "king";game.new_expedition()
		if chapter == 2: game.route.generate(game.seed_value, 2)
		game.collection = ["sword_plus", "sword", "spear", "life", "sword_plus"]
		game.lives = 3;game.screen = "map"
		if encounter_id.is_empty(): break
		for node in game.route.state.nodes:
			if node.encounter.get("id", "") == encounter_id: target = node.id;break
		if target >= 0: break
	check(encounter_id.is_empty() or target >= 0, "generated encounter exists: " + encounter_id)
	if target < 0: clear_input();return
	for id in path_to(target):
		game.route.enter(id)
		if id == target: break
		if game.screen == "game":
			game.debug_skip();game.input_lock = 0;game.navigation_lock = 0;game.choose_reward(-1)
		else:
			var leave = -1
			for i in game.route.choices.size():
				if game.route.choices[i].action == "leave": leave = i;break
			check(leave >= 0, "transit event has leave choice")
			if leave >= 0: game.route.resolve(leave)
	clear_input()
func save_fixture(name: String, size: Vector2):
	clear_input();game.route.save();steps = []
	check(game.route.valid_snapshot(game.route.state, game.history.capture(), game.screen), name + " valid ordinary saved game")
	var filename = name + "-" + str(int(size.x)) + ".cfg"
	var file = FileAccess.open(OUT + "fixtures/" + filename, FileAccess.WRITE)
	check(file != null, "open fixture " + filename)
	if file != null: file.store_string(FileAccess.get_file_as_string(game.route.SAVE));file.close()
	var previous_screen = game.screen;game.screen = "home"
	var resume = point(game.frontend.button_rect(3).get_center());game.screen = previous_screen
	return {"fixture": filename, "name": name, "viewport": point(size), "logical_size": point(game.ui_size), "resume": resume, "initial": summary()}
func transition(size: Vector2):
	prepare(1, "palace_final")
	var initial_collection = game.collection.duplicate();var initial_lives = game.lives
	var report = save_fixture("chapter_transition", size)
	victory("chapter-one-boss-reward")
	check(game.phase == "reward" and not game.route.state.done, "first boss offers rewards instead of ending run")
	reward_return()
	check(game.route.state.chapter == 2 and game.screen == "map" and game.route.state.current == -1 and game.route.state.pending == -1, "first boss advances to fresh chapter two map")
	check(game.collection == initial_collection and game.lives == initial_lives, "chapter transition preserves deck and current lives without healing")
	reload_step();enter(0)
	check(game.encounter_state.config.id == "c2_heavy_pawns", "chapter two begins with authored heavy-pawn encounter")
	check(game.collection == initial_collection and game.lives == initial_lives, "first battle retains chapter-transition progress")
	report.steps = steps.duplicate(true);reports.append(report)
func final_boss(size: Vector2):
	prepare(2, "c2_inner_city")
	var report = save_fixture("final_boss", size)
	victory("chapter-two-boss-win")
	check(game.phase == "win" and game.route.state.done and game.route.state.chapter == 2, "second boss is the final victory")
	report.steps = steps.duplicate(true);reports.append(report)
func chapter_map(size: Vector2):
	prepare(2)
	var report = save_fixture("chapter_map", size)
	enter(0);rules_panel();reload_step();end_turn("heavy-pawns-first-turn")
	check(game.turn == 2 and game.encounter_state.config.id == "c2_heavy_pawns", "second chapter first battle is playable after Continue")
	report.steps = steps.duplicate(true);reports.append(report)
func revival(size: Vector2):
	prepare(2, "c2_lone_guard")
	# A controlled two-piece battle isolates the authored unyielding advisor.
	# Actual card damage creates its ghost; no ghost is fabricated in the save.
	game.enemies = game.enemies.filter(func(enemy): return enemy.kind in ["g", "a"])
	game.enemies[0].cd = 99
	game.player = Vector2i(3, 1);game.hand = ["sword_plus"];game.hand_ids = [];game.deck = [];game.discard = []
	var advisor_uid = game.enemies[1].uid
	var report = save_fixture("revival", size)
	rules_panel()
	var taps = [point(game.handui.exposed_point(0)), point(game.cell_pos(Vector2i(3, 0)))]
	check(game.card_legal("sword_plus", Vector2i(3, 0)), "revival fixture uses a legal real card attack")
	game.play_card(0, Vector2i(3, 0));step("combat", "advisor-defeated-ghost-visible", taps)
	check(game.encounter_state.ghosts.size() == 1 and game.R.occupied(Vector2i(3, 0), game.enemies) < 0, "defeated advisor leaves a non-occupying ghost")
	reload_step()
	end_turn("partial-turn-ghost-waits")
	check(game.encounter_state.ghosts.size() == 1, "partial defeat turn is not a complete player turn")
	end_turn("first-full-turn-ghost-waits")
	check(game.encounter_state.ghosts.size() == 1, "ghost waits through first complete player turn")
	end_turn("second-full-turn-advisor-revives")
	check(game.encounter_state.ghosts.is_empty(), "ghost disappears on real revival")
	var revived = game.enemies.back()
	check(revived.uid == advisor_uid and revived.hp == revived.max_hp and revived.pos == Vector2i(3, 0) and revived.normal_moves == 0 and revived.cd == 3, "advisor revives at full health in its original cell without acting")
	report.steps = steps.duplicate(true);reports.append(report)
func reinforcement(size: Vector2):
	prepare(2, "c2_inner_city")
	# Keep the full authored army. Reach the preview using real enemy phases,
	# rather than constructing a wave with inconsistent phase/counter state.
	game.lives = 5
	for phase_index in 3:
		game.input_lock = 0;game.end_turn();clear_input()
	var report = save_fixture("reinforcement", size)
	check(game.phase == "play" and game.encounter_state.phases == 3, "boss reinforcement fixture is still playable")
	end_turn("next-turn-reinforcement-marker")
	check(game.encounter_state.waves[0].status == "announced", "wave preview is announced exactly one phase early")
	rules_panel();reload_step();end_turn("reinforcement-arrives")
	check(game.encounter_state.waves[0].status == "arrived", "announced boss reinforcement really arrives")
	var spawned_uid = game.encounter_state.waves[0].uid
	var spawned = {}
	for enemy in game.enemies:
		if enemy.uid == spawned_uid: spawned = enemy;break
	check(not spawned.is_empty() and spawned.get("reinforcement", false) and spawned.pos == Vector2i(7, 0) and spawned.normal_moves == 0 and spawned.cd == 3, "arriving reinforcement uses marked cell and cannot act on its arrival turn")
	report.steps = steps.duplicate(true);reports.append(report)
func general_guard(size: Vector2):
	prepare(2, "c2_lone_guard")
	game.enemies = game.enemies.filter(func(enemy): return enemy.kind in ["g", "a"])
	game.enemies[0].cd = 1;game.enemies[1].pos = Vector2i(4, 1);game.enemies[1].cd = 99
	game.player = Vector2i(4, 2);game.hand = [];game.hand_ids = [];game.deck = [];game.discard = []
	var report = save_fixture("general_guard", size)
	end_turn("general-holds-behind-advisor")
	check(game.enemies[0].pos == Vector2i(4, 0) and game.enemies[0].normal_moves == 0, "ready general holds behind an actual advisor spear blocker")
	check(game.player == Vector2i(4, 2) and game.lives == 3, "defensive hold adds no illegal attack or player displacement")
	report.steps = steps.duplicate(true);reports.append(report)
func run():
	DirAccess.make_dir_recursive_absolute(OUT + "fixtures")
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	for size in [Vector2(1280, 940), Vector2(390, 844), Vector2(360, 640), Vector2(844, 390)]:
		game.configure_layout(size);rules_text_checks()
		if int(size.x) in [1280, 390]: transition(size);final_boss(size)
		if size.x != 1280: chapter_map(size);revival(size);reinforcement(size)
		if size.x == 390: general_guard(size)
	var file = FileAccess.open(OUT + "replays.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(reports, "  ") + "\n");file.close()
	print("CHAPTER WEB FIXTURES ", reports.size(), " replays, ", checks, " checks, ", failures, " failures")
	game.free();quit(1 if failures else 0)
