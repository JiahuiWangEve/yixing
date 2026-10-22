extends SceneTree
# Offline fixture driver. The exported build contains no QA API: browser tests
# replay these validated ordinary saves using real Continue/touch/reload inputs.
const OUT = "res://../verification/v0.14.0/chapter/"
const ROUTE_FIELDS = ["chapter", "current", "pending", "visited", "done", "prepared", "reward_debt", "reward_blocked", "pending_homework", "homework_awarded", "treasure_id", "treasure_claimed", "treasure_choices"]
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
	step("tap", "skip-reward-treasure-choice", [point(target)])
func enter(id: int):
	game.route.focus_current()
	var target = game.route.position(game.route.state.nodes[id])
	check(game.route.map_rect().has_point(target), "chosen map node is visible")
	var taps = [point(target)]
	game.route.click(target);game.route.tick(game.route.TRAVEL_SECONDS + 0.01);step("enter", "enter-first-battle", taps)
func rectangle(value: Rect2) -> Array:
	return [value.position.x, value.position.y, value.size.x, value.size.y]
func inspection_state() -> Dictionary:
	return {"battle": game.history.capture(), "route": game.route.state.duplicate(true), "selected": game.selected, "undo": game.history.entries.duplicate(true)}
func inspect_tag(tag: Dictionary, record_steps: bool):
	# Fixtures advance instantly; settle the normal presentation timer before input.
	game.presentation.tick(2.1)
	game.information.clear()
	var before = inspection_state()
	var pos: Vector2 = tag.anchor.get_center()
	var source = "touch" if game.mobile_layout else "mouse"
	var event
	if source == "touch":
		event = InputEventScreenTouch.new();event.index = 4;event.position = pos;event.pressed = true
		game._input(event)
	else:
		event = InputEventMouseMotion.new();event.position = pos;event.device = 0;game._gui_input(event)
	game.information.tick(0.41 if source == "touch" else 0.31)
	var popup = game.information
	check(popup.visible and popup.data.get("key") == tag.key, "actual tag input opens matching shared information popup")
	check(inspection_state() == before, "opening a mechanism tag preserves full battle, route, selection, RNG and undo state")
	check(popup.data.get("title") == tag.title and popup.data.get("lines") == tag.lines, "popup exposes every current mechanism rule without truncating content")
	check(Rect2(Vector2.ZERO, game.ui_size).encloses(popup.area), "actual mechanism popup fits viewport")
	check(not popup.area.intersects(tag.anchor), "mechanism popup leaves inspected tag visible")
	check(popup.font_size >= 12 and not popup.rows.is_empty(), "mechanism popup has readable nonempty text")
	check("".join(popup.rows) == "".join(tag.lines).replace("\n", ""), "wrapped popup rows preserve complete mechanism text")
	var title_width = game.FONT.get_string_size(tag.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	check(title_width <= popup.area.size.x - 28, "full mechanism title fits actual popup")
	var rows = []
	for index in popup.rows.size():
		var width = game.FONT.get_string_size(popup.rows[index], HORIZONTAL_ALIGNMENT_LEFT, -1, popup.font_size).x
		var baseline = 50 + index * (popup.font_size + 4)
		var top = baseline - game.FONT.get_ascent(popup.font_size)
		var bottom = baseline + game.FONT.get_descent(popup.font_size)
		check(width <= popup.area.size.x - 28 and top >= 0 and bottom <= popup.area.size.y, "complete mechanism row fits popup width and vertical bounds")
		rows.append({"text": popup.rows[index], "width": width, "top": top, "bottom": bottom})
	var action = {"kind": "inspect", "label": "mechanism-open-" + tag.key.trim_prefix("mechanism:"), "taps": [], "source": source, "target": point(pos), "popup": rectangle(popup.area), "title": tag.title, "lines": tag.lines.duplicate(), "rows": rows, "font_size": popup.font_size, "expected": summary()}
	if record_steps: steps.append(action)
	if source == "touch":
		event.pressed = false;game._input(event)
	else:
		event.position = game.ui_size - Vector2(4, 4);game._gui_input(event)
	check(not popup.visible, "release or pointer exit closes mechanism popup")
	check(inspection_state() == before, "inspection release cannot play cards, end turns, alter RNG or add undo entries")
	if record_steps:
		var closing = action.duplicate(true);closing.kind = "close_inspect";closing.label = "mechanism-close-" + tag.key.trim_prefix("mechanism:")
		closing.target = point(game.ui_size - Vector2(4, 4));steps.append(closing)
func rules_layout_checks():
	# Exercise the actual shared component for every authored chapter-two battle,
	# instead of measuring text in the obsolete, hidden encounter modal.
	for id in game.ENCOUNTERS.CHAPTER_TWO.TEMPLATES:
		prepare(2, id)
		var tags = game.board_info.tag_items()
		check(not tags.is_empty(), "authored chapter battle exposes mechanism tags: " + id)
		for tag in tags: inspect_tag(tag, false)
func mechanism_panels():
	var tags = game.board_info.tag_items()
	check(not tags.is_empty(), "chapter replay includes every active mechanism tag")
	for tag in tags: inspect_tag(tag, true)
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
func prepare(chapter: int, encounter_id: String = "") -> int:
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
	var expected_lives = 3
	if target < 0: clear_input();return expected_lives
	for id in path_to(target):
		game.route.enter(id)
		if id == target: break
		if game.screen == "game":
			expected_lives = mini(5, expected_lives + 1) if game.player_skill == "king" else expected_lives
			game.debug_skip();game.input_lock = 0;game.navigation_lock = 0;game.choose_reward(-1)
		else:
			var leave = -1
			for i in game.route.choices.size():
				if game.route.choices[i].action == "leave": leave = i;break
			check(leave >= 0, "transit event has leave choice")
			if leave >= 0: game.route.resolve(leave)
		check(game.lives == expected_lives, "fixture transit grants only king one capped life per victory and none at non-combat nodes")
	clear_input()
	return expected_lives
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
	var victory_lives = mini(5, initial_lives + 1) if game.player_skill == "king" else initial_lives
	var report = save_fixture("chapter_transition", size)
	victory("chapter-one-boss-reward")
	check(game.phase == "reward" and not game.route.state.done, "first boss offers rewards instead of ending run")
	reward_return()
	check(game.screen == "treasure_choice" and game.route.chapter() == 1 and game.route.state.treasure_choices == game.TREASURES.ids_for("king"), "first boss opens mandatory role treasure choice")
	reload_step()
	game.treasureui.sync()
	var treasure_target = game.treasureui.card_rect(0).intersection(game.treasureui.area()).get_center()
	check(game.treasureui.choice_at(treasure_target) == "longevity_seal", "chapter fixture treasure card is visible and correctly hit-tested")
	check(game.route.choose_treasure("longevity_seal"), "first boss treasure claim succeeds")
	step("tap", "choose-longevity-seal-next-chapter", [point(treasure_target)])
	check(game.route.state.treasure_id == "longevity_seal" and game.route.state.treasure_claimed, "chosen treasure persists in new chapter")
	check(game.route.state.chapter == 2 and game.screen == "map" and game.route.state.current == -1 and game.route.state.pending == -1, "first boss advances to fresh chapter two map")
	check(game.collection == initial_collection and game.lives == victory_lives, "chapter transition preserves deck and one-time king victory healing without an extra boundary heal")
	reload_step();enter(0);mechanism_panels()
	check(game.encounter_state.config.id == "c2_heavy_pawns", "chapter two begins with authored heavy-pawn encounter")
	check(game.collection == initial_collection and game.lives == victory_lives, "first battle retains chapter-transition progress without another triumph heal")
	report.steps = steps.duplicate(true);reports.append(report)
func final_boss(size: Vector2):
	prepare(2, "c2_inner_city")
	var report = save_fixture("final_boss", size)
	mechanism_panels()
	victory("chapter-two-boss-win")
	check(game.phase == "win" and game.route.state.done and game.route.state.chapter == 2, "second boss is the final victory")
	report.steps = steps.duplicate(true);reports.append(report)
func chapter_map(size: Vector2):
	prepare(2)
	var report = save_fixture("chapter_map", size)
	enter(0);mechanism_panels();reload_step();end_turn("heavy-pawns-first-turn")
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
	mechanism_panels()
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
	mechanism_panels();reload_step();end_turn("reinforcement-arrives")
	check(game.encounter_state.waves[0].status == "arrived", "announced boss reinforcement really arrives")
	var spawned_uid = game.encounter_state.waves[0].uid
	var spawned = {}
	for enemy in game.enemies:
		if enemy.uid == spawned_uid: spawned = enemy;break
	check(not spawned.is_empty() and spawned.get("reinforcement", false) and spawned.pos == Vector2i(7, 0) and spawned.normal_moves == 0 and spawned.cd == 3, "arriving reinforcement uses marked cell and cannot act on its arrival turn")
	report.steps = steps.duplicate(true);reports.append(report)
func general_guard(size: Vector2):
	var initial_lives = prepare(2, "c2_lone_guard")
	game.enemies = game.enemies.filter(func(enemy): return enemy.kind in ["g", "a"])
	game.enemies[0].cd = 1;game.enemies[1].pos = Vector2i(4, 1);game.enemies[1].cd = 99
	game.player = Vector2i(4, 2);game.hand = [];game.hand_ids = [];game.deck = [];game.discard = []
	var report = save_fixture("general_guard", size)
	end_turn("general-holds-behind-advisor")
	check(game.enemies[0].pos == Vector2i(4, 0) and game.enemies[0].normal_moves == 0, "ready general holds behind an actual advisor spear blocker")
	check(game.player == Vector2i(4, 2) and game.lives == initial_lives, "defensive hold preserves prior victory health without an illegal attack or player displacement")
	report.steps = steps.duplicate(true);reports.append(report)
func run():
	DirAccess.make_dir_recursive_absolute(OUT + "fixtures")
	game = load("res://main.tscn").instantiate();root.add_child(game);game.settings.set_debug_mode(true);FileAccess.open(OUT+"fixtures/settings.cfg",FileAccess.WRITE).store_string(FileAccess.get_file_as_string(game.settings.SAVE));game.set_process(false)
	for size in [Vector2(1280, 940), Vector2(390, 844), Vector2(360, 640), Vector2(844, 390)]:
		game.configure_layout(size);rules_layout_checks()
		if int(size.x) in [1280, 390]: transition(size);final_boss(size)
		if size.x != 1280: chapter_map(size);revival(size);reinforcement(size)
		if size.x == 390: general_guard(size)
	var file = FileAccess.open(OUT + "replays.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(reports, "  ") + "\n");file.close()
	print("CHAPTER WEB FIXTURES ", reports.size(), " replays, ", checks, " checks, ", failures, " failures")
	game.free();quit(1 if failures else 0)
