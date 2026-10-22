extends SceneTree
# Ordinary production saves and real input coordinates. No runtime QA hooks.
const OUT = "res://../verification/v0.14.5/pass/"
const ROUTE_FIELDS = ["chapter", "current", "pending", "visited", "done", "prepared", "reward_debt", "reward_blocked", "pending_homework", "homework_awarded", "treasure_id", "treasure_claimed", "treasure_choices", "victory_recorded"]
const BATTLE_FIELDS = ["phase", "turn", "lives", "energy", "collection", "deck", "hand", "discard", "rewards", "player", "encounter_state", "airdrop_recovery_turn", "basic_used", "card_move_used", "free_card_uid", "hand_ids", "next_card_uid", "active_displacements", "shield_charges", "pending_bleeds", "reload_ready", "artillery_mode", "deploy_draw_used", "tuna_turns", "tuna_active", "treasure_battle"]
var game
var checks = 0
var failures = 0
var reports = []
var steps = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("PASS WEB: " + label)
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
	var result = {"screen": game.screen}
	for key in ROUTE_FIELDS: result[key] = game.route.state[key]
	for key in BATTLE_FIELDS: result[key] = game.get(key)
	result.rng_state = str(game.rng.state) # Keep all 64 bits through JSON/browser tooling.
	result.encounters = []
	for node in game.route.state.nodes: result.encounters.append(node.encounter)
	result.enemies = []
	for enemy in game.enemies:
		var piece = enemy.duplicate(true);piece.erase("visual");result.enemies.append(piece)
	return json_value(result)
func settle():
	game.clear_effects();game.input_lock = 0;game.navigation_lock = 0;game.initial_threat = 0
	game.handui.reset();game.sync_hand_ids();game.handui.sync();game.route.save()
func step(label: String, inputs: Array, kind: String = "action"):
	settle();steps.append({"kind": kind, "label": label, "inputs": inputs, "wait_ms": 400, "expected": summary()})
func touch(pos: Vector2, pressed: bool, index: int = 1, canceled: bool = false):
	var event = InputEventScreenTouch.new();event.position = pos;event.pressed = pressed;event.index = index;event.canceled = canceled
	game._input(event)
func move(pos: Vector2, index: int = 1):
	var event = InputEventScreenDrag.new();event.position = pos;event.index = index
	game._input(event)
func tap(pos: Vector2): touch(pos, true);touch(pos, false)
func input_tap(pos: Vector2): return {"action": "tap", "point": point(pos)}
func drag(index: int, label: String, mode: String = "release", free: bool = false, allowed: bool = true):
	var from: Vector2 = game.handui.free_exposed_point() if free else game.handui.exposed_point(index)
	var to: Vector2 = game.pass_drop_rect().get_center()
	var preview: Vector2 = Vector2(game.pass_drop_rect().position.x - 50, to.y)
	var second: Vector2 = game.cell_pos(Vector2i(0, 0))
	var action = {"action": "drag", "from": point(from), "preview": point(preview), "to": point(to), "second": point(second), "mode": mode, "highlight": "allowed" if allowed else "blocked"}
	var before = game.history.capture()
	var before_history = game.history.entries.duplicate(true)
	touch(from, true);move(preview);move(to)
	check(game.gesture.dragging and game.pass_drop_rect().has_point(game.gesture.pointer), label + " holds over side zone")
	check(game.can_pass_card(index, free) == allowed, label + " eligibility matches highlight")
	if mode == "multitouch":
		touch(second, true, 2);touch(second, false, 2)
		check(not game.gesture.active and game.battle_multitouch and game.history.capture() == before and game.history.entries == before_history, label + " second touch cancels without gameplay or history changes")
		touch(second, true, 3);move(to, 3);touch(to, false, 3)
		check(not game.gesture.active and game.battle_multitouch and game.history.capture() == before and game.history.entries == before_history, label + " third touch cannot restart while primary remains held")
		touch(to, false)
	elif mode == "cancel": touch(to, false, 1, true)
	else: touch(to, false)
	var blocked = mode in ["cancel", "multitouch"] or not allowed
	if blocked: check(game.history.capture() == before and game.history.entries == before_history, label + " all releases preserve complete state, RNG and undo history")
	step(label, [action], "blocked" if blocked else "action")
func pass_input(index: int, label: String, free: bool = false, allowed: bool = true, mode: String = "release"):
	if mode != "select":
		drag(index, label, mode, free, allowed)
	else:
		var from: Vector2 = game.handui.free_exposed_point() if free else game.handui.exposed_point(index)
		var button: Vector2 = game.pass_button_rect().get_center()
		tap(from)
		check(game.pass_zone_visible() and game.gesture.pass_zone_state().enabled == allowed, label + " selection displays the shared zone")
		var selection = input_tap(from);selection.selected_zone = true
		tap(button)
		step(label, [selection, input_tap(button)], "action" if allowed else "blocked")
func fresh(size: Vector2):
	game.configure_layout(size);game.seed_value = 14242;game.player_skill = "king";game.new_expedition();game.route.enter(0)
	game.enemies = [];game.next_enemy_uid = 1;game.add_enemy("g", Vector2i(4, 0), 999)
	game.enemies[0].hp = 9;game.enemies[0].max_hp = 9
	game.collection = ["airdrop", "spear", "breath", "sword", "spear", "fatigue"]
	game.hand = ["airdrop", "spear", "breath"];game.hand_ids = [];game.deck = ["fatigue", "spear", "sword"];game.discard = [];game.rewards = []
	game.energy = 3;game.lives = 3;game.player = Vector2i(4, 9)
	game.plan_intents();settle();steps = []
func replay(size: Vector2):
	fresh(size)
	var name = "pass_cards"
	check(game.route.valid_snapshot(game.route.state, game.history.capture(), "game"), "fixture is a valid ordinary save")
	var filename = name + "-" + str(int(size.x)) + ".cfg"
	var file = FileAccess.open(OUT + "fixtures/" + filename, FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(game.route.SAVE));file.close()
	game.screen = "home";var resume = point(game.frontend.button_rect(3).get_center());game.screen = "game"
	var zone: Rect2 = game.pass_drop_rect()
	var report = {"name": name, "fixture": filename, "viewport": point(size), "logical_size": point(game.ui_size), "resume": resume, "zone": [zone.position.x, zone.position.y, zone.size.x, zone.size.y], "initial": summary()}
	var before = summary()
	drag(0, "cancel-held-drag-keeps-card", "cancel")
	check(summary() == before, "touch cancel leaves every compared gameplay field unchanged")
	pass_input(0, "pass-consumable-draws-one-no-effect", false, true, "select")
	check(game.hand == ["spear", "breath", "sword"] and game.discard == ["airdrop"] and game.deck == ["fatigue", "spear"], "passing pays three, replaces exactly the selected copy and never exhausts")
	check(game.energy == 0 and game.lives == 3 and game.player == Vector2i(4, 9) and game.airdrop_recovery_turn == 0 and game.enemies[0].hp == 9, "passing pays three without any airdrop effect")
	before = summary();pass_input(0, "insufficient-energy-no-change", false, false)
	check(summary() == before, "insufficient energy changes no compared gameplay field")
	pass_input(-1, "unaffordable-generated-pass-no-change", true, false)
	check(summary() == before, "generated card also requires three energy")
	var end_turn = game.END_TURN_RECT.get_center()
	tap(end_turn);step("next-turn-before-printed-zero-pass", [input_tap(end_turn)])
	before = summary();pass_input(1, "zero-cost-pass-multitouch-canceled", false, true, "multitouch")
	check(summary() == before and game.energy == 3 and game.hand == ["spear", "breath", "sword"] and game.discard == ["airdrop"] and game.deck == ["fatigue", "spear"], "multitouch spends nothing, draws nothing and preserves the printed-zero card")
	pass_input(1, "zero-cost-pass-after-multitouch-cancel")
	check(game.energy == 0 and game.hand == ["spear", "sword", "spear"] and game.discard == ["airdrop", "breath"] and game.deck == ["fatigue"], "printed-zero card still pays three and draws once without resolving breath or double-committing")
	tap(end_turn);step("next-turn-before-generated-pass", [input_tap(end_turn)])
	pass_input(-1, "free-card-pass-keeps-basic-quota", true)
	check(game.free_card_uid == 0 and not game.basic_used and game.energy == 0 and game.hand == ["spear", "sword", "spear", "fatigue"] and game.deck.is_empty(), "passing generated card costs three, draws fatigue at zero floor, and preserves basic quota")
	game.route.save();check(game.route.resume(), "post-pass production save resumes")
	step("reload-preserves-free-card-removal", [], "reload")
	check(game.free_card_uid == 0 and not game.basic_used and game.discard == ["airdrop", "breath"], "reload does not resurrect passed free or consumed cards")
	var target = game.cell_pos(Vector2i(5, 9));tap(target)
	step("basic-move-still-available", [input_tap(target)])
	check(game.player == Vector2i(5, 9) and game.basic_used and game.hand.size() == 5 and game.hand[-1] in ["airdrop", "breath"] and game.deck.size() == 1 and game.discard.is_empty() and game.energy == 0, "preserved basic move normally reshuffles passed cards and draws one")
	report.steps = steps.duplicate(true);reports.append(report)
func run():
	DirAccess.make_dir_recursive_absolute(OUT + "fixtures")
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	for size in [Vector2(1280, 940), Vector2(390, 844), Vector2(360, 780), Vector2(844, 390)]: replay(size)
	var file = FileAccess.open(OUT + "replays.json", FileAccess.WRITE);file.store_string(JSON.stringify(reports, "  ") + "\n");file.close()
	print("PASS WEB FIXTURES ", reports.size(), " replays, ", checks, " checks, ", failures, " failures")
	game.free();quit(1 if failures else 0)
