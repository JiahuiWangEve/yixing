extends SceneTree
const T = preload("res://../tests/route_test_helpers.gd")
var game
var picker
var failures = 0
var checks = 0
var confirmed_indices = []
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("CARD PICKER: " + label)
func _initialize(): call_deferred("run")
func selected(index: int): confirmed_indices.append(index)
func fresh(size: Vector2):
	if picker.active: picker.close()
	game.new_expedition();game.configure_layout(size)
	game.route.enter(0);game.route.complete();T.enter_next(game, "camp")
	game.collection = []
	for i in 24: game.collection.append(["sword", "sword_plus", "spear", "fatigue", "airdrop", "cannon_shot"][i % 6])
	game.route.refresh_choices()
func open(kind: String = "remove"):
	picker.open(kind, "选择卡牌", game.route.UPGRADES.eligible_indices(game.collection) if kind == "upgrade" else range(game.collection.size()), selected, func(): pass)
func key(code: int):
	var event = InputEventKey.new();event.keycode = code;event.pressed = true;game._input(event)
func tap(pos: Vector2):
	var event = InputEventScreenTouch.new();event.position = pos;event.pressed = true;event.index = 1;game._input(event)
	event = InputEventScreenTouch.new();event.position = pos;event.pressed = false;event.index = 1;game._input(event)
func action(name: String):
	for n in game.route.choices.size():
		if game.route.choices[n].action == name: game.route.resolve(n);return
	check(false, "action exists " + name)
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);picker = game.card_picker
	for size in [Vector2(1280,940), Vector2(390,844), Vector2(360,640), Vector2(844,390)]:
		fresh(size);open()
		check(picker.indices.size() == 24, "24 physical copies not collapsed")
		check(picker.columns() == (5 if size.x == 1280 else (4 if size.x == 844 else 2)), "responsive columns")
		check(picker.scroll_limit() > 0, "large deck scrolls")
		var before = game.collection.duplicate();var first = picker.card_rect(0).get_center()
		tap(first);check(picker.selected == 0 and game.collection == before, "tap selects without mutation")
		var turn_before = game.turn;key(KEY_SPACE);check(game.turn == turn_before and picker.active, "space cannot end turn")
		picker.press(first, 1);picker.motion(first - Vector2(0,100), 1);picker.release(first - Vector2(0,100), 1)
		check(picker.scroll_y > 0 and picker.selected == 0 and game.collection == before, "drag scroll never selects or commits")
		picker.scroll_y = picker.scroll_limit();picker.refresh()
		var last = picker.card_rect(23).get_center();check(picker.grid_rect().has_point(last), "bottom card reachable")
		tap(last);check(picker.selected == 23, "bottom duplicated card exact index")
		game.configure_layout(Vector2(390,844) if size.x > 800 else Vector2(844,390))
		check(picker.selected == 23 and picker.scroll_y <= picker.scroll_limit(), "rotate preserves chosen instance and clamps scroll")
		picker.confirm();picker.confirm();check(confirmed_indices.back() == 23 and not picker.active, "one-shot confirmation exact index")
		open();tap(picker.card_rect(0).get_center());key(KEY_ESCAPE)
		check(not picker.active and game.collection == before, "Escape cancels no mutation")
		open();picker.selected = 0;game.collection[0] = "spear";picker.confirm()
		check(picker.active and not picker.selected_valid(), "stale snapshot blocked even same length")
		picker.close();game.collection = before
		open("upgrade");check(picker.indices.size() == 8 and 1 not in picker.indices and 3 not in picker.indices, "registry-only upgrade eligibility")
		picker.close()
		# Real rest transaction; only target physical copy is removed.
		game.route.choice_mode = "root";game.route.refresh_choices();action("select_remove")
		check(picker.active, "rest opens shared picker")
		picker.selected = 1;picker.confirm();before.remove_at(1)
		check(game.collection == before and game.screen == "map", "rest deletion commits only upgraded second instance")
	# Book immediate and homework use same selection and preserve upgraded identity.
	for mode in ["focus", "homework"]:
		fresh(Vector2(390,844));picker.close();T.configure_node(game, game.route.state.pending, "event", "manual");game.route.state.nodes[game.route.state.pending].upgrade_seed = 42
		game.collection = ["sword", "sword_plus", "fatigue"];game.route.choice_mode = "root";game.route.refresh_choices();action("select_" + mode)
		check(picker.active and picker.indices == [0,1,2], "book includes upgraded and fatigue")
		picker.selected = 1;picker.confirm()
		if mode == "focus": check(game.collection == ["sword", "sword_plus", "fatigue", "sword_plus", "fatigue"], "copy exact upgrade plus fatigue")
		else: check(game.collection == ["sword", "sword_plus", "fatigue"] and game.route.state.pending_homework == ["sword_plus"], "homework exact upgraded copy delayed")
	fresh(Vector2(390,844));T.configure_node(game, game.route.state.pending, "workshop");game.collection = ["sword", "sword", "sword_plus"]
	game.route.choice_mode = "root";game.route.refresh_choices();action("select_upgrade")
	check(picker.indices == [0,1], "workshop entry filters only eligible physical cards")
	picker.selected = 1;check(picker.description().contains("淬锋"), "upgrade result preview")
	picker.confirm();check(game.collection == ["sword", "sword_plus", "sword_plus"], "workshop only second copy changes")
	fresh(Vector2(390,844));game.collection = ["fatigue"];game.route.refresh_choices();action("select_remove");picker.selected = 0;picker.confirm()
	check(game.collection.is_empty(), "existing zero-card lower bound preserved")
	fresh(Vector2(390,844));game.screen = "game";game.phase = "reward";game.rewardui.reset();game.navigation_lock = 0;game.input_lock = 0
	game.rewardui.click(game.rewardui.choice_rect(1).get_center());check(picker.active, "battle reward uses same picker")
	var turn_before = game.turn;key(KEY_SPACE);check(game.turn == turn_before, "reward picker space safe")
	picker.cancel();check(game.rewardui.mode == "choice" and not picker.active, "reward cancel returns reward choices")
	game.queue_free();print("CARD PICKER RESULT %d checks, %d failures" % [checks, failures]);quit(1 if failures else 0)
