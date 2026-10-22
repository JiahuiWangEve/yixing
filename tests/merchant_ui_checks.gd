extends SceneTree
# Focused two-step merchant regression and ordinary-save browser fixtures.
# Run with disposable XDG_DATA_HOME/XDG_CONFIG_HOME/XDG_CACHE_HOME, as verify.sh does.
const T = preload("res://../tests/route_test_helpers.gd")
const OUT = "res://../verification/v0.14.11/merchant/"
const SIZES = [Vector2(1280, 940), Vector2(390, 844), Vector2(360, 640), Vector2(844, 390)]
var game
var route
var picker
var merchant
var checks = 0
var failures = 0
var reports: Array = []

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("MERCHANT UI: " + label)
func point(pos: Vector2) -> Array: return [pos.x, pos.y]
func summary() -> Dictionary:
	return {"screen": game.screen, "current": route.state.current, "pending": route.state.pending, "visited": route.state.visited.duplicate(), "prepared": route.state.prepared, "reward_debt": route.state.reward_debt, "reward_blocked": route.state.reward_blocked, "pending_homework": route.state.pending_homework.duplicate(), "homework_awarded": route.state.homework_awarded.duplicate(), "energy": game.energy, "turn": game.turn, "deck": game.deck.duplicate(), "discard": game.discard.duplicate(), "collection": game.collection.duplicate(), "hand": game.hand.duplicate(), "rewards": game.rewards.duplicate(), "lives": game.lives, "phase": game.phase}
func fresh(size: Vector2, empty: bool = false):
	if picker.active: picker.close()
	game.player_skill = "king";game.seed_value = 141143;game.new_expedition();game.configure_layout(size)
	route.enter(0);route.complete();T.enter_next(game, "event", "merchant")
	game.collection = []
	if not empty:
		# Both duplicated basic IDs and duplicated upgraded IDs remain physical cards.
		for i in 20: game.collection.append(["sword", "sword", "sword_plus", "fatigue", "sword_plus"][i % 5])
	route.refresh_choices();merchant.scroll_y = 0;merchant.sync()
	game.input_lock = 0;game.navigation_lock = 0;game.presentation.clear()
func key(code: int):
	var event = InputEventKey.new();event.keycode = code;event.pressed = true;game._input(event)
func touch(pos: Vector2, pressed: bool, canceled: bool = false):
	var event = InputEventScreenTouch.new();event.position = pos;event.pressed = pressed;event.index = 1;event.canceled = canceled;game._input(event)
func tap(pos: Vector2): touch(pos, true);touch(pos, false)
func drag(from: Vector2, to: Vector2, canceled: bool = false):
	touch(from, true)
	for fraction in [0.25, 0.5, 0.75, 1.0]:
		var event = InputEventScreenDrag.new();event.position = from.lerp(to, fraction);event.index = 1;game._input(event)
	touch(to, false, canceled)
func scroll_positions(area: Rect2) -> Array:
	return [Vector2(area.get_center().x, area.end.y - 15), Vector2(area.get_center().x, area.position.y + 15)]
func offers() -> Array: return route.state.nodes[route.state.pending].offers.duplicate()
func check_shortcuts(before: Dictionary, label: String):
	var selected_before = game.selected
	for code in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_KP_1, KEY_KP_7, KEY_SPACE]: key(code)
	check(summary() == before and game.selected == selected_before, label + " consumes battle shortcuts 1-7 and space")

func check_transaction(size: Vector2):
	fresh(size)
	var before = summary();var fixed = offers();var pending = route.state.pending
	check(merchant.active() and not picker.active, "root shows merchant offers, not old-card picker")
	check(fixed.size() == 3 and route.choices.size() == 4, "three stored offers plus leave")
	check(fixed[0] != fixed[1] and fixed[0] != fixed[2] and fixed[1] != fixed[2], "existing distinct offer IDs preserved")
	check(fixed[0] in game.PROFILES.DATA.king.rewards and fixed[1] in game.PROFILES.DATA.king.rewards and fixed[2] in game.PROFILES.COMMON, "existing own-card/common offer pools preserved")
	check_shortcuts(before, "offer screen")
	var positions = scroll_positions(merchant.area());drag(positions[0], positions[1])
	check(merchant.active() and not picker.active and summary() == before and offers() == fixed, "offer drag/release cannot choose or exchange")
	merchant.scroll_y = 0
	for offer_index in 3:
		var offer_pos = merchant.card_rect(offer_index).get_center()
		if not merchant.area().has_point(offer_pos): merchant.scroll_y = merchant.scroll_limit();offer_pos = merchant.card_rect(offer_index).get_center()
		check(merchant.area().has_point(offer_pos), "offer card reachable")
		tap(offer_pos)
		check(picker.active and picker.action == "exchange" and not merchant.active(), "offer opens exchange picker")
		check(picker.incoming_card == fixed[offer_index] and picker.has_incoming_preview(), "incoming preview is actual selected offer")
		check(picker.indices == range(20) and picker.snapshot == before.collection, "all 20 physical cards eligible including duplicate upgrades")
		check(summary() == before and not picker.selected_valid(), "offer preview costs nothing and confirmation starts disabled")
		check(not picker.grid_rect().intersects(picker.incoming_preview_rect()), "fixed incoming face does not overlap old-card grid")
		tap(picker.card_rect(1).get_center())
		check(picker.selected == 1 and summary() == before, "old-card tap is preview only")
		check(picker.description().contains(game.CARDS[fixed[offer_index]][0]) and picker.description().contains(game.CARDS[before.collection[1]][0]) and picker.description().contains("→"), "footer names exact old-to-new exchange")
		check_shortcuts(before, "exchange picker")
		key(KEY_ESCAPE)
		check(not picker.active and merchant.active() and route.choice_mode == "root" and summary() == before and offers() == fixed, "cancel returns fixed offers without mutation or reroll")
		merchant.scroll_y = 0
	# Real touch drag, including canceled touch, must not select or confirm.
	tap(merchant.card_rect(0).get_center());positions = scroll_positions(picker.grid_rect())
	drag(positions[0], positions[1], true);tap(picker.confirm_rect().get_center())
	check(picker.active and picker.selected == -1 and summary() == before, "canceled drag cannot commit")
	picker.scroll_y = 0;picker.refresh();drag(positions[0], positions[1])
	check(picker.scroll_y > 0 and picker.selected == -1 and summary() == before, "normal touch scroll releases without a transaction")
	picker.scroll_y = picker.scroll_limit();picker.refresh()
	check(picker.grid_rect().has_point(picker.card_rect(19).get_center()), "20th physical card reachable at bottom")
	tap(picker.card_rect(19).get_center());check(picker.selected == 19, "select exact last upgraded duplicate")
	var expected = before.collection.duplicate();expected[19] = fixed[0]
	var confirm_pos = picker.confirm_rect().get_center();tap(confirm_pos);picker.confirm();route.picker_confirm(19)
	check(game.collection == expected and game.collection.size() == 20 and game.screen == "map" and not picker.active, "confirmation replaces only last chosen index once and preserves deck count")
	check(route.state.pending == -1 and route.state.current == pending and pending in route.state.visited, "exchange completes merchant node once")
	check(route.state.nodes[pending].offers == fixed, "committed offers remain fixed")
	check(route.resume() and game.collection == expected and game.screen == "map", "confirmed exact instance survives ordinary save/resume")

func check_stale_context():
	for kind in ["collection", "pending", "phase", "screen"]:
		fresh(Vector2(390, 844));tap(merchant.card_rect(0).get_center());picker.selected = 2
		match kind:
			"collection": game.collection[0] = "spear"
			"pending": route.state.pending = -1
			"phase": game.phase = "reward"
			"screen": game.screen = "map"
		var unchanged = game.collection.duplicate();var current = route.state.current
		check(not picker.selected_valid(), kind + " stale context disables confirmation")
		picker.confirm()
		check(game.collection == unchanged and route.state.current == current, kind + " stale context cannot exchange")
		key(KEY_ENTER);check(not picker.active and game.collection == unchanged, kind + " stale context safely closes on input")

func check_empty(size: Vector2):
	fresh(size, true);var before = summary();var fixed = offers()
	tap(merchant.card_rect(0).get_center())
	check(not picker.active and merchant.active() and summary() == before and offers() == fixed, "empty deck disables offer clicks without mutation")
	# Existing route-level entry still has no valid card and no free/generated card.
	route.resolve(0)
	check(picker.active and picker.indices.is_empty() and not picker.selected_valid(), "empty exchange picker cannot invent eligible cards")
	picker.confirm();check(summary() == before, "empty confirmation cannot commit")
	picker.cancel();tap(merchant.leave_rect().get_center())
	check(game.screen == "map" and game.collection.is_empty(), "empty merchant always permits safe leave")

func check_debt_text():
	fresh(Vector2(390, 844));var before = summary()
	for debt in [0, 1, 2, 9]:
		route.state.reward_debt = debt
		check(route.reward_debt_text() == ("" if debt == 0 else "无收益·剩%d场" % debt), "debt badge is empty at zero and compact only when positive")
		check(route.state.reward_debt == debt, "debt label does not consume reward debt")
	route.state.reward_debt = 0
	check(summary() == before, "debt formatting is pure")
	var source = FileAccess.get_file_as_string("res://route_map.gd")
	check(not source.contains("每个节点只选一次"), "redundant every-node-once subtitle removed")
	check(not source.contains("无收益剩%d场"), "old always-visible debt label removed")

func fixture(size: Vector2, empty: bool):
	fresh(size, empty);route.save()
	var name = ("empty" if empty else "exchange") + "-" + str(int(size.x))
	check(route.valid_snapshot(route.state, game.history.capture(), "route_choice"), name + " ordinary save validates")
	var filename = name + ".cfg"
	FileAccess.open(OUT + "fixtures/" + filename, FileAccess.WRITE).store_string(FileAccess.get_file_as_string(route.SAVE))
	var report = {"name": name, "empty": empty, "viewport": point(size), "logical_size": point(game.ui_size), "fixture": filename, "initial": summary(), "offers": offers(), "offer_points": [], "leave": point(merchant.leave_rect().get_center()), "node": route.state.pending}
	game.screen = "home";report.resume = point(game.frontend.button_rect(3).get_center());game.screen = "route_choice"
	for i in 3: report.offer_points.append(point(merchant.card_rect(i).get_center()))
	var positions = scroll_positions(merchant.area());report.offer_drag_from = point(positions[0]);report.offer_drag_to = point(positions[1])
	if empty:
		tap(merchant.leave_rect().get_center())
	else:
		tap(merchant.card_rect(0).get_center())
		report.first = point(picker.card_rect(0).get_center());report.cancel = point(picker.cancel_rect().get_center());report.confirm = point(picker.confirm_rect().get_center())
		positions = scroll_positions(picker.grid_rect());report.drag_from = point(positions[0]);report.drag_to = point(positions[1])
		report.swipes = ceili(picker.scroll_limit() / (positions[0].y - positions[1].y)) + 1
		picker.scroll_y = picker.scroll_limit();picker.refresh();report.last = point(picker.card_rect(19).get_center());report.target_index = 19
		check(picker.grid_rect().has_point(picker.card_rect(19).get_center()), name + " fixture bottom target visible")
		tap(picker.card_rect(19).get_center());picker.confirm()
	report.expected = summary();reports.append(report)

func run():
	DirAccess.make_dir_recursive_absolute(OUT + "fixtures")
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	route = game.route;picker = game.card_picker;merchant = route.merchant_ui
	for size in SIZES: check_transaction(size);check_empty(size)
	check_stale_context();check_debt_text()
	for size in SIZES:
		fixture(size, false);fixture(size, true)
	FileAccess.open(OUT + "replays.json", FileAccess.WRITE).store_string(JSON.stringify(reports, "  "))
	game.queue_free();print("MERCHANT UI RESULT %d checks, %d failures, %d fixtures" % [checks, failures, reports.size()]);quit(1 if failures else 0)
