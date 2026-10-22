extends SceneTree
# Focused v0.14.8 regressions. Run with a disposable XDG_DATA_HOME.
const R = preload("res://rules.gd")
const SIZES = [Vector2(1280, 940), Vector2(390, 844), Vector2(360, 640), Vector2(844, 390)]
var game
var checks = 0
var failures = 0

func _initialize(): call_deferred("run")

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("TUTORIAL PATCH: " + label)
	else: print("PASS ", label)

func ready():
	game.clear_effects();game.navigation_lock = 0.0;game.presentation.clear()

func settle():
	ready();game.tutorial.tick(2.0)

func rules_snapshot() -> Dictionary:
	var result: Dictionary = game.history.capture()
	result.erase("notice")
	return result

func add_piece(kind: String, position: Vector2i, hp: int = 3):
	game.add_enemy(kind, position, 99)
	game.enemies.back().hp = hp;game.enemies.back().max_hp = hp

func fresh_assault():
	game.tutorial.stop();game.player_skill = "horse";game.new_run()
	game.enemies = [];add_piece("g", Vector2i(4, 0), 99)
	game.player = Vector2i(4, 5);game.lives = 3;game.energy = 3
	game.hand = ["knight_assault"];game.hand_ids = [];game.discard = []
	game.deck = ["sword", "spear"];game.selected = -1
	game.sync_hand_ids();game.handui.reset();game.handui.sync();game.history.clear();ready()

func check_assault_damage():
	for hp in [1, 2, 3]:
		for unsafe_landing in [false, true]:
			fresh_assault()
			var target = Vector2i(6, 4)
			add_piece("p", target, hp)
			if unsafe_landing: add_piece("r", Vector2i(6, 0), 3)
			var label = "assault HP%d landing danger %s" % [hp, str(unsafe_landing)]
			check(game.card_cost("knight_assault") == 2 and str(game.card_data("knight_assault")[2]).contains("2伤"), label + " card says two cost and two damage")
			check(game.can_commit_card(0, target), label + " legal knight target")
			var before = rules_snapshot()
			var preview: Dictionary = game.board_info.preview(0, target)
			check(preview.get("affected", []).size() == 1, label + " preview has one target")
			if preview.get("affected", []).size() != 1: continue
			var impact: Dictionary = preview.affected[0]
			check(impact.damage == 2 and impact.hp_before == hp and impact.hp_after == maxi(0, hp - 2) and impact.down == (hp <= 2), label + " preview predicts exact damage and defeat")
			var danger: bool = game.target_danger("knight_assault", target)
			check(danger == (unsafe_landing and hp <= 2), label + " danger uses two-damage kill displacement")
			check(rules_snapshot() == before, label + " preview never changes live state")
			game.play_card(0, target)
			var victim = R.occupied(target, game.enemies)
			check(victim < 0 if hp <= 2 else victim >= 0 and game.enemies[victim].hp == hp - 2, label + " actual damage matches preview")
			check(game.player == (target if hp <= 2 else Vector2i(4, 5)) and game.active_displacements == (1 if hp <= 2 else 0), label + " only a kill moves the player")
			check(game.energy == 1 and game.hand.is_empty() and game.discard == ["knight_assault"] and game.deck == ["sword", "spear"], label + " spends exactly two without drawing")
			check(not game.basic_used and not game.card_move_used and game.lives == 3, label + " attack does not consume either movement quota or life")
			check(R.threatened(game.player, game.enemies) == danger, label + " actual threat matches danger preview")
	for delta in [Vector2i(2, 1), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(-2, -1), Vector2i(1, 2), Vector2i(-1, 2), Vector2i(1, -2), Vector2i(-1, -2)]:
		fresh_assault()
		var target: Vector2i = game.player + delta
		var leg: Vector2i = game.player + Vector2i(signi(delta.x) if absi(delta.x) == 2 else 0, signi(delta.y) if absi(delta.y) == 2 else 0)
		add_piece("p", target, 2);add_piece("stake", leg, 1)
		var before = rules_snapshot()
		check(not game.can_commit_card(0, target) and game.board_info.preview(0, target).is_empty(), "blocked leg %s rejects card and preview" % str(delta))
		game.play_card(0, target)
		check(rules_snapshot() == before and game.history.entries.is_empty(), "blocked leg %s spends and damages nothing" % str(delta))
	fresh_assault();add_piece("p", Vector2i(6, 4), 2);game.energy = 1
	var before = rules_snapshot()
	game.play_card(0, Vector2i(6, 4))
	check(not game.can_commit_card(0, Vector2i(6, 4)) and rules_snapshot() == before, "assault requires the full two energy")

func enter_pass(size: Vector2 = Vector2(1280, 940)):
	game.start_tutorial(4);settle();game.tutorial.skip_step();settle()
	game.configure_layout(size);game.sync_hand_ids();game.handui.reset();game.handui.sync()
	game.cancel_gesture();game.touch_seen = false
	for frame in 20: game.handui.tick(0.05)
	check(game.tutorial.pass_step() and game.tutorial.step_index == 4 and game.tutorial.step_count() == 5, "skip reward exercise reaches the sole paid-pass step")
	check(game.hand == ["sword"] and game.deck == ["spear"] and game.discard.is_empty() and game.energy == 3 and game.stage == 1 and game.player == Vector2i(4, 9), "pass fixture has a deterministic safe one-card replacement")

func button(position: Vector2, pressed: bool, kind: String, canceled: bool = false):
	if kind == "touch":
		var event = InputEventScreenTouch.new()
		event.index = 0;event.position = position;event.pressed = pressed;event.canceled = canceled
		game._input(event)
	else:
		var event = InputEventMouseButton.new()
		event.device = 0;event.button_index = MOUSE_BUTTON_LEFT;event.position = position;event.pressed = pressed
		game._gui_input(event)

func motion(position: Vector2, kind: String):
	if kind == "touch":
		var event = InputEventScreenDrag.new();event.index = 0;event.position = position;game._input(event)
	else:
		var event = InputEventMouseMotion.new();event.device = 0;event.position = position;game._gui_input(event)

func tap(position: Vector2, kind: String):
	button(position, true, kind);button(position, false, kind)

func assert_pass_result(before: Dictionary, label: String):
	check(game.energy == 0 and game.hand == ["spear"] and game.deck.is_empty() and game.discard == ["sword"], label + " pays three and replaces exactly one card")
	for field in ["collection", "player", "enemies", "lives", "turn", "basic_used", "card_move_used", "active_displacements", "free_card_uid"]:
		check(game.get(field) == before[field], label + " preserves " + field)
	check(game.phase == "play" and not game.tutorial._retry_pending and game.tutorial._pending_step == game.tutorial.step_count(), label + " queues completion without retry")
	check(game.history.entries.is_empty() and not game.can_undo_action(), label + " tutorial does not create usable undo history")
	check(not game.pass_zone_visible() and not game.pass_card(0), label + " pending transition blocks a second pass")
	settle()
	check(game.tutorial.lesson_complete and game.tutorial.finished and not game.tutorial.pass_step(), label + " final lesson completes")

func check_pass_input():
	for size in SIZES:
		for kind in ["mouse", "touch"]:
			var label = str(size) + " " + kind
			enter_pass(size)
			var source: Vector2 = game.handui.exposed_point(0)
			var drop: Vector2 = game.pass_drop_rect().get_center()
			check(not game.pass_zone_visible(), label + " no unselected overlay")
			tap(source, kind)
			check(game.selected == 0 and game.pass_zone_visible() and game.gesture.pass_zone_state().enabled, label + " selected sword shows enabled pass zone")
			var capture: Dictionary = game.tutorial._before.duplicate(true)
			var action: String = game.tutorial._last_action
			for query in 4:
				game.can_pass_card(0);game.pass_zone_visible();game.gesture.pass_zone_state()
			check(game.tutorial._before == capture and game.tutorial._last_action == action and game.tutorial._pending_step < 0, label + " UI eligibility is a pure query")
			var before = rules_snapshot()
			button(drop, true, kind)
			check(game.energy == 3 and game.gesture.pass_pressed, label + " zone press alone cannot spend")
			button(drop, false, kind)
			assert_pass_result(before, label + " click")
			enter_pass(size)
			source = game.handui.exposed_point(0);drop = game.pass_drop_rect().get_center();before = rules_snapshot()
			button(source, true, kind);motion(drop, kind)
			check(game.gesture.pass_zone_state().highlighted and game.energy == 3, label + " drag shows paid target before release")
			button(drop, false, kind)
			assert_pass_result(before, label + " drag")

func reject_pass(index: int, free: bool, label: String):
	var before = rules_snapshot();var selected: int = game.selected
	var captured: Dictionary = game.tutorial._before.duplicate(true)
	var action: String = game.tutorial._last_action
	check(not game.can_pass_card(index, free) and not game.pass_card(index, free), label + " rejects pass")
	check(rules_snapshot() == before and game.selected == selected and game.history.entries.is_empty(), label + " changes no gameplay state")
	check(game.tutorial._before == captured and game.tutorial._last_action == action and game.tutorial._pending_step < 0 and not game.tutorial._retry_pending, label + " changes no tutorial progress")

func check_pass_rejections_and_cancellation():
	enter_pass()
	game.energy = 2;game.select_card(0)
	check(game.pass_zone_visible() and not game.gesture.pass_zone_state().enabled and game.gesture.pass_zone_state().hint == "能量不足", "unaffordable selected pass stays visible but disabled")
	reject_pass(0, false, "two-energy tutorial")
	game.energy = 3
	reject_pass(-1, true, "generated free movement card")
	for index in [-2, -1, 1, 99]: reject_pass(index, false, "invalid tutorial index " + str(index))
	game.hand = ["horse"]
	reject_pass(0, false, "wrong tutorial card")
	game.hand = ["sword"]
	game.cancel_selection()
	check(game.selected == -1 and not game.pass_zone_visible() and game.tutorial.pass_step(), "cancel selection keeps the pass lesson ready")
	game.select_card(0)
	check(game.selected == 0 and game.can_pass_card(0), "cancelled pass can be selected again")
	for kind in ["mouse", "touch"]:
		enter_pass(Vector2(390, 844))
		var source: Vector2 = game.handui.exposed_point(0)
		var drop: Vector2 = game.pass_drop_rect().get_center()
		var before = rules_snapshot()
		button(source, true, kind);motion(drop, kind);motion(source, kind);button(source, false, kind)
		check(rules_snapshot() == before and game.tutorial.pass_step() and not game.gesture.active, kind + " returning a drag cancels without spending")
		button(source, true, kind);motion(drop, kind)
		if kind == "touch": button(drop, false, kind, true)
		else:
			var escape = InputEventKey.new();escape.keycode = KEY_ESCAPE;escape.pressed = true;game._input(escape)
		button(drop, false, kind)
		check(rules_snapshot() == before and game.tutorial.pass_step() and not game.gesture.active, kind + " cancelled input and late release cannot commit")
		tap(source, kind);tap(drop, kind)
		assert_pass_result(before, kind + " resumes after cancellation")
	for lesson in 5:
		game.start_tutorial(lesson);settle()
		# Seed an ordinary selectable card so this checks tutorial gating, not bounds.
		game.hand = ["sword"];game.hand_ids = [];game.sync_hand_ids();game.selected = 0
		check(not game.pass_zone_visible(), "other step in lesson %d hides paid pass" % lesson)
		reject_pass(0, false, "other step in lesson " + str(lesson))
		reject_pass(-1, true, "other step free card in lesson " + str(lesson))
	game.tutorial.stop();game.tutorial._steps = [];game.tutorial.active = true
	check(not game.tutorial.pass_step() and not game.can_pass_card(0) and not game.pass_zone_visible(), "empty active tutorial safely rejects pass queries")
	game.tutorial.stop()

func check_restart_skip_and_save():
	game.player_skill = "king";game.new_expedition();game.route.enter(0);ready()
	game.normal_undos_remaining = 1;game.route.save()
	var saved_text = FileAccess.get_file_as_string(game.route.SAVE)
	var saved_state = game.history.capture();var saved_route: Dictionary = game.route.state.duplicate(true)
	check(not saved_text.is_empty() and game.route.save_error == OK, "formal expedition fixture is saved")
	enter_pass()
	var allowance: int = game.normal_undos_remaining
	check(not game.undo_action() and not game.history.undo() and game.normal_undos_remaining == allowance, "tutorial undo attempts never consume allowance")
	var before = rules_snapshot();game.pass_card(0)
	assert_pass_result(before, "saved expedition tutorial")
	check(game.normal_undos_remaining == allowance and FileAccess.get_file_as_string(game.route.SAVE) == saved_text, "completed tutorial does not spend normal undo or rewrite formal save")
	game.tutorial.restart();settle()
	check(game.tutorial.step_index == 0 and not game.tutorial.lesson_complete and game.hand == ["sword", "sword", "sword"], "replay restores the victory-and-reward opening")
	game.tutorial.skip_step();settle()
	check(game.tutorial.pass_step() and game.energy == 3 and game.hand == ["sword"] and game.deck == ["spear"], "replay pass fixture is replenished deterministically")
	game.tutorial.skip_step()
	check(game.tutorial.lesson_complete and game.tutorial.finished, "pass exercise can be skipped without soft lock")
	game.show_home()
	check(FileAccess.get_file_as_string(game.route.SAVE) == saved_text, "replay skip and exit preserve formal save bytes")
	check(game.route.resume() and game.normal_undos_remaining == 1, "formal expedition resumes its original undo allowance")
	check(game.history.capture() == saved_state and game.route.state == saved_route, "formal expedition resumes its exact battle and route")
	game.start_tutorial(2);settle()
	check(str(game.tutorial._steps[1].hint).contains("点击选中"), "paid movement tutorial explicitly teaches selecting the card")
	game.start_tutorial(4);settle()
	var contains_reinforcement = str(game.tutorial.LESSON_NAMES[4]).contains("援军")
	for step in game.tutorial._steps: contains_reinforcement = contains_reinforcement or str(step.hint).contains("援军")
	check(not contains_reinforcement and game.tutorial._steps[3].action == "reward", "only tutorial reinforcement is replaced and rewards remain")

func check_retry_and_normal_reinforcements():
	enter_pass()
	var before = rules_snapshot()
	game.end_turn();game.basic_move(Vector2i(4, 8));game.play_card(0, Vector2i(4, 0))
	check(rules_snapshot() == before and game.tutorial.pass_step(), "unrelated actions cannot escape the paid-pass exercise")
	# Inject a wrong draw to exercise the existing failed-observation recovery.
	game.deck = ["horse"]
	check(game.pass_card(0) and game.tutorial._retry_pending and game.tutorial._pending_step < 0, "incorrect observed replacement schedules a safe retry")
	settle()
	check(game.tutorial.pass_step() and game.hand == ["sword"] and game.deck == ["spear"] and game.energy == 3 and game.discard.is_empty(), "retry rebuilds the fixed pass fixture without a soft lock")
	before = rules_snapshot();game.pass_card(0);assert_pass_result(before, "pass after automatic retry")
	fresh_assault();game.stage = 3;game.player = Vector2i(4, 9)
	game.hand = [];game.hand_ids = [];game.reinforcement_turns = 0;game.reinforcement_pending = 0
	for phase in 2: game.end_turn();ready()
	check(game.enemies.size() == 1 and game.reinforcement_turns == 2, "normal stage three still waits two enemy phases")
	game.end_turn()
	check(game.enemies.size() == 2 and game.enemies.back().kind == "h" and game.enemies.back().pos.y == 0 and game.enemies.back().cd == 3 and game.lives == 3, "normal stage three still spawns its horse on the third phase")

func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	game.settings.set_debug_mode(false)
	check_assault_damage()
	check_pass_input()
	check_pass_rejections_and_cancellation()
	check_restart_skip_and_save()
	check_retry_and_normal_reinforcements()
	print("TUTORIAL PATCH RESULT ", checks, " checks, ", failures, " failures")
	game.queue_free();quit(1 if failures else 0)
