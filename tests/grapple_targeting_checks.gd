extends SceneTree
const GRAPPLE = preload("res://grapple_targeting.gd")
const SUPPORT = preload("res://test_support.gd")
const CATALOG = preload("res://card_catalog.gd")
var game
var checks = 0
var failures = 0

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("GRAPPLE: " + label)
func fresh(cards: Array = ["grappling_hook"], size: Vector2 = Vector2(1280, 940)):
	game.tutorial.stop();game.presentation.clear();game.card_picker.close();game.encounter_info_open = false
	game.player_skill = "king";game.new_run();game.configure_layout(size)
	game.enemies = [];game.encounter_state = {};game.player = Vector2i(4, 6)
	game.add_enemy("g", Vector2i(8, 0), 999)
	game.lives = 4;game.energy = 10;game.hand = cards.duplicate();game.hand_ids = []
	game.collection = cards.duplicate();game.deck = ["life", "breath"];game.discard = []
	game.screen = "game";game.phase = "play";game.selected = -1;game.free_selected = false
	game.clear_effects();game.input_lock = 0;game.navigation_lock = 0;game.initial_threat = 0
	game.sync_hand_ids();game.handui.reset();game.sync_hand_views();game.history.clear()
	game.cancel_gesture();game.touch_seen = false;game.information.clear()
	game.battle_touch_contacts.clear();game.battle_multitouch = false
	game.active_displacements = 0;game.player_visual = game.cell_pos(game.player)
func add(cell: Vector2i, kind: String = "p") -> Dictionary:
	game.add_enemy(kind, cell, 999)
	return game.enemies.back()
func pack() -> Dictionary:
	var battle: Dictionary = game.history.capture()
	# Instruction text, selected-card UI, and layout-space visuals are not rules.
	battle.erase("notice");battle.erase("free_selected")
	for piece in battle.enemies: piece.erase("visual")
	return {"battle": battle, "history": game.history.entries.duplicate(true), "effects": game.effects.duplicate(true), "rng": game.rng.state}
func button(position: Vector2, pressed: bool, kind: String = "mouse", canceled: bool = false):
	if kind == "touch":
		var event = InputEventScreenTouch.new();event.index = 0;event.position = position;event.pressed = pressed;event.canceled = canceled
		game._input(event)
	else:
		var event = InputEventMouseButton.new();event.device = 0;event.button_index = MOUSE_BUTTON_LEFT;event.position = position;event.pressed = pressed
		game._gui_input(event)
func motion(position: Vector2, kind: String):
	if kind == "touch":
		var event = InputEventScreenDrag.new();event.index = 0;event.position = position;game._input(event)
	else:
		var event = InputEventMouseMotion.new();event.device = 0;event.position = position;game._gui_input(event)
func tap(position: Vector2, kind: String):
	button(position, true, kind);button(position, false, kind)
func drag(position: Vector2, kind: String):
	var source: Vector2 = SUPPORT.card_point(game, 0)
	button(source, true, kind);motion(position, kind);button(position, false, kind)
func stage():
	add(Vector2i(6, 4));game.select_card(0);game.grapple_targets.choose(0, Vector2i(6, 4))
	check(game.grapple_targets.active, "diagonal anchor enters pending landing")

func check_geometry():
	var origin = Vector2i(4, 5)
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var anchor = origin + Vector2i(dx, dy)
			var pieces: Array = [{"pos": anchor, "kind": "stake", "uid": 1}]
			var actual = GRAPPLE.landing_candidates(origin, anchor, pieces)
			var expected: Array = []
			if Vector2i(dx, dy) != Vector2i.ZERO and maxi(absi(dx), absi(dy)) <= 2:
				var sx = -signi(dx);var sy = -signi(dy)
				var candidates: Array = [anchor + Vector2i(sx, sy)]
				if dx != 0 and dy != 0: candidates = [anchor + Vector2i(sx, 0), anchor + Vector2i(0, sy), anchor + Vector2i(sx, sy)]
				for cell in candidates:
					if cell != origin: expected.append(cell)
			check(actual == expected, "exact player-facing candidates " + str(Vector2i(dx, dy)))
			for cell in actual: pieces.append({"pos": cell, "kind": "p"})
			check(GRAPPLE.landing_candidates(origin, anchor, pieces).is_empty(), "fully occupied candidates invalidate anchor " + str(Vector2i(dx, dy)))
	for corner in [Vector2i(0, 0), Vector2i(8, 0), Vector2i(0, 9), Vector2i(8, 9)]:
		var delta = Vector2i(2 if corner.x == 0 else -2, 2 if corner.y == 0 else -2)
		var anchor = corner + delta
		var candidates = GRAPPLE.landing_candidates(corner, anchor, [{"pos": anchor}])
		check(candidates.size() == 3, "corner diagonal retains exactly three inward candidates")
		for cell in candidates: check(game.R.inside(cell) and cell != corner, "corner candidate stays inside")
	check(GRAPPLE.landing_candidates(origin, origin + Vector2i(2, 0), []).is_empty(), "empty anchor is invalid")
	check(GRAPPLE.landing_candidates(origin, Vector2i(-1, 5), [{"pos": Vector2i(-1, 5)}]).is_empty(), "off-board anchor is invalid")

func check_commit():
	for kind in ["p", "stake", "decoy"]:
		fresh();var anchor = add(Vector2i(4, 4), kind)
		var anchor_before = anchor.duplicate(true);var free_uid: int = game.free_card_uid
		var deck_before = game.deck.duplicate();game.card_move_used = true
		game.play_card(0, anchor.pos)
		check(game.player == Vector2i(4, 5) and game.energy == 9 and game.hand.is_empty(), "orthogonal hook moves player and pays exactly one " + kind)
		check(anchor == anchor_before and game.deck == deck_before and game.discard == ["grappling_hook"], "anchor unchanged; no damage, draw or consume " + kind)
		check(game.free_card_uid == free_uid and not game.basic_used and game.active_displacements == 1 and game.history.entries.size() == 1, "one displacement leaves free budget unchanged " + kind)
		check(not game.grapple_targets.active, "orthogonal direct commit clears stage")
	fresh();add(Vector2i(6, 4));var before = pack();game.select_card(0);game.grapple_targets.choose(0, Vector2i(6, 4))
	check(pack() == before, "anchor selection has no gameplay mutation")
	var view: Dictionary = game.grapple_targets.state(0)
	check(view.anchor == Vector2i(6, 4) and view.landing_cells == [Vector2i(5, 4), Vector2i(6, 5), Vector2i(5, 5)] and view.anchor_cells.is_empty(), "stage highlights only chosen anchor and exact landings")
	before = pack();var snapshot = view.duplicate(true)
	for repeat in 5: game.grapple_targets.state(0);game.grapple_targets.legal_target(Vector2i(5, 4))
	check(pack() == before and game.grapple_targets.state(0) == snapshot, "stage previews are read-only")
	check(not game.grapple_targets.choose(0, Vector2i(7, 4)) and pack() == before, "away-side empty cell rejected without expense")
	check(not game.grapple_targets.choose(0, Vector2i(4, 6)) and pack() == before, "origin rejected without expense")
	game.play_card(0, Vector2i(5, 4))
	check(game.player == Vector2i(5, 4) and game.energy == 9 and game.active_displacements == 1 and game.history.entries.size() == 1, "second explicit landing commits once")
	fresh();add(Vector2i(6, 4));add(Vector2i(5, 4), "stake");add(Vector2i(6, 5), "stake")
	before = pack();game.play_card(0, Vector2i(6, 4))
	check(game.grapple_targets.active and pack() == before, "sole surviving diagonal candidate still needs explicit click")
	game.play_card(0, Vector2i(5, 5));check(game.player == Vector2i(5, 5) and game.energy == 9, "sole diagonal landing commits on second choice")
	fresh();add(Vector2i(6, 4));add(Vector2i(5, 5), "stake")
	game.play_card(0, Vector2i(6, 4));game.play_card(0, Vector2i(5, 4))
	check(game.player == Vector2i(5, 4), "hook jumps intermediate obstacle")
	fresh();add(Vector2i(6, 4));add(Vector2i(5, 4), "stake");add(Vector2i(6, 5), "stake");add(Vector2i(5, 5), "stake")
	before = pack();game.play_card(0, Vector2i(6, 4))
	check(not game.grapple_targets.active and pack() == before, "no empty landing means invalid anchor, not paid failure")
	fresh();game.player_skill = "horse";game.route.state.treasure_id = "battle_tassel";game.treasures.reset_battle();game.active_displacements = 1
	add(Vector2i(4, 4));game.play_card(0, Vector2i(4, 4))
	check(game.active_displacements == 2 and game.treasure_battle.tassel_ready, "hook displacement triggers existing second-move treasure once")

func check_cancellation():
	for change in ["removed", "replaced", "moved", "origin", "turn", "card_removed", "card_replaced", "energy", "recovery", "phase", "screen", "input_lock", "navigation_lock", "picker", "encounter", "presentation"]:
		fresh();stage()
		match change:
			"removed": game.enemies.pop_back()
			"replaced": game.enemies.back().uid += 1000
			"moved": game.enemies.back().pos = Vector2i(5, 4)
			"origin": game.player = Vector2i(3, 6)
			"turn": game.turn += 1
			"card_removed": game.hand.clear();game.hand_ids.clear()
			"card_replaced": game.hand_ids[0] += 1000
			"energy": game.energy = 0
			"recovery": game.airdrop_recovery_turn = game.turn
			"phase": game.phase = "discard"
			"screen": game.screen = "home"
			"input_lock", "navigation_lock": game.set(change, 1.0)
			"picker": game.card_picker.open("view", "Cards", [0], Callable(), Callable())
			"encounter": game.encounter_info_open = true
			"presentation": game.presentation.start("victory")
		var before = pack();game.grapple_targets.tick()
		check(not game.grapple_targets.active and pack() == before, "stage canceled without transaction on " + change)
	fresh();stage();game.enemies.back().uid += 1000;var before = pack()
	check(not game.grapple_targets.choose(0, Vector2i(6, 4)) and not game.grapple_targets.active and pack() == before, "stale anchor click cannot automatically select replacement UID")
	for change in ["escape", "right_click", "resize", "focus", "web_cancel", "selection", "free_selection", "cancel_selection"]:
		fresh(["grappling_hook", "grappling_hook"]);stage();before = pack()
		match change:
			"escape":
				var event = InputEventKey.new();event.keycode = KEY_ESCAPE;event.pressed = true;game._input(event)
			"right_click":
				var event = InputEventMouseButton.new();event.button_index = MOUSE_BUTTON_RIGHT;event.pressed = true;game._gui_input(event)
			"resize": game.configure_layout(Vector2(390, 844))
			"focus": game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"web_cancel": game.on_web_input_cancel([])
			"selection": game.select_card(1)
			"free_selection": game.select_free_card()
			"cancel_selection": game.cancel_selection()
		check(not game.grapple_targets.active and pack() == before, "user cancellation clears stage with no gameplay mutation " + change)
	fresh();stage();game.request_end_turn();check(not game.grapple_targets.active and game.turn == 2, "turn end clears pending landing")
	fresh();game.history.record("move");game.player = Vector2i(4, 5);stage();game.settings.debug_mode = true
	check(game.undo_action() and not game.grapple_targets.active and game.player == Vector2i(4, 6), "undo clears staged landing before restoring board")
	fresh();stage();game.restart_battle();check(not game.grapple_targets.active, "restart clears pending landing")

func check_input():
	for size in [Vector2(1280, 940), Vector2(390, 844), Vector2(360, 640), Vector2(844, 390)]:
		for kind in ["mouse", "touch"]:
			fresh(["grappling_hook"], size);add(Vector2i(6, 4));var before = pack()
			drag(game.cell_pos(Vector2i(6, 4)), kind)
			check(game.grapple_targets.active and pack() == before, "board drag stages anchor without expense " + str(size) + kind)
			tap(game.cell_pos(Vector2i(5, 4)), kind)
			check(game.player == Vector2i(5, 4) and game.energy == 9 and game.hand.is_empty(), "tap second-stage landing commits " + str(size) + kind)
			fresh(["grappling_hook"], size);add(Vector2i(4, 4));before = pack()
			drag(Vector2(game.full_hand_area().position.x + 40, game.full_hand_area().position.y - 32), kind)
			check(pack() == before and not game.grapple_targets.active, "upward hook never auto-selects even unique anchor " + str(size) + kind)
			fresh(["grappling_hook"], size);add(Vector2i(4, 4));drag(game.pass_drop_rect().get_center(), kind)
			check(game.player == Vector2i(4, 6) and game.energy == 7 and game.hand.size() == 1 and game.hand[0] == "breath" and not game.grapple_targets.active, "side discard retains priority and three-fee replacement " + str(size) + kind)
			fresh(["grappling_hook"], size);stage();var source: Vector2 = SUPPORT.card_point(game, 0)
			button(source, true, kind);motion(game.cell_pos(Vector2i(5, 4)), kind);before = pack()
			if kind == "touch": button(game.cell_pos(Vector2i(5, 4)), false, kind, true)
			else: game._notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
			button(game.cell_pos(Vector2i(5, 4)), false, kind)
			check(pack() == before and not game.grapple_targets.active, "canceled second-stage gesture cannot commit on late release " + str(size) + kind)
			fresh(["grappling_hook"], size);add(Vector2i(6, 5));game.play_card(0, Vector2i(6, 5))
			source = SUPPORT.card_point(game, 0);button(source, true, kind);motion(game.cell_pos(Vector2i(6, 6)), kind)
			game.enemies.pop_back();add(Vector2i(6, 6));game.grapple_targets.tick();before = pack()
			button(game.cell_pos(Vector2i(6, 6)), false, kind)
			check(pack() == before and not game.grapple_targets.active, "invalidated landing drag never retargets a new occupied orthogonal anchor " + str(size) + kind)

func check_catalog_and_repeated_moves():
	fresh(["straight", "straight"])
	game.play_card(0, Vector2i(4, 5));game.clear_effects();game.input_lock = 0
	check(game.can_commit_card(0, Vector2i(4, 4)), "second paid move remains legal in same turn")
	game.play_card(0, Vector2i(4, 4))
	check(game.player == Vector2i(4, 4) and game.energy == 8 and game.active_displacements == 2 and not game.basic_used, "paid moves retain individual fee/draw and do not consume free move")
	check(game.hand == ["breath", "life"] and game.deck.is_empty(), "each ordinary movement still draws exactly one")
	for id in ["horse", "straight", "grappling_hook"]:
		check(not game.descriptions.data(id)[4].contains("每回合") and not game.descriptions.data(id)[4].contains("最多1张"), "ordinary move description has no once-per-turn limit " + id)
	check(game.descriptions.data("__free_king")[4].contains("每回合1次"), "free basic generated card still once per turn")
	var special: Array = CATALOG.entries_for("special", game.CARDS).map(func(entry): return entry.id)
	check("grappling_hook" in special and game.CARDS.grappling_hook[1] == 1 and game.CARDS.grappling_hook[3] == "移" and not game.is_consumable("grappling_hook"), "hook is one-fee movement, nonconsumable, special catalog")
	for role in ["king", "horse", "artillery"]:
		check("grappling_hook" not in game.PROFILES.DATA[role].deck and "grappling_hook" not in game.PROFILES.DATA[role].rewards and "grappling_hook" not in game.PROFILES.COMMON, "hook absent from formal deck and reward pools " + role)

func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	check_geometry();check_commit();check_cancellation();check_input();check_catalog_and_repeated_moves()
	game.free();print("GRAPPLE TARGETING: %d checks; %d failures" % [checks, failures]);quit(1 if failures else 0)
