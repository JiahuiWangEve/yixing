extends SceneTree
# Enemy mechanics and route integration. Run only against the final v0.10 source.
const R = preload("res://rules.gd")
const E = preload("res://encounters.gd")
var game
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
func _initialize(): call_deferred("run")
func config(id: String, tier: String = "elite", rules: Array = []) -> Dictionary:
	return {"id": id, "tier": tier, "rules": rules}
func fixture(id: String = "three_pawns", tier: String = "battle", rules: Array = []):
	game.tutorial.stop();game.player_skill = "king";game.new_run()
	game.enemies = [];game.encounter_state = {};game.lives = 100
	game.player = Vector2i(8, 9);game.hand = [];game.hand_ids = [];game.deck = [];game.discard = []
	E.setup(game, config(id, tier, rules))
	for enemy in game.enemies: enemy.cd = 999;enemy.period = 999;enemy.intent = Vector2i(-1, -1)
	game.clear_effects();game.navigation_lock = 0;game.phase = "play"
func add(kind: String, pos: Vector2i, period: int = 1) -> Dictionary:
	game.add_enemy(kind, pos, period)
	return game.enemies.back()
func piece(kind: String, pos: Vector2i) -> Dictionary:
	return {"kind": kind, "pos": pos, "stun": 0}
func index_of(uid: int) -> int:
	for i in game.enemies.size():
		if game.enemies[i].uid == uid: return i
	return -1
func count_relay() -> int:
	var n = 0
	for enemy in game.enemies:
		if enemy.kind == "h" and enemy.get("reinforcement", false): n += 1
	return n
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game)
	check_rules()
	check_templates()
	check_double_step()
	check_relay()
	check_river()
	check_rotation_and_retaliation()
	check_round_trips()
	check_actual_modifiers()
	check_modal_and_geometry()
	check_invalid_encounters()
	check_new_glyphs()
	check_ai_strategy()
	check_reactive_decision()
	fixture()
	var actor = game.enemies[1]
	var start = game.cell_pos(Vector2i(2, 3))
	var middle = game.cell_pos(Vector2i(2, 4))
	var finish = game.cell_pos(Vector2i(2, 5))
	game.move_piece(actor, start, middle, 0.2, false)
	game.move_piece(actor, middle, finish, 0.48, false)
	actor.pos = Vector2i(2, 5)
	game._process(0.1)
	check(actor.visual.is_equal_approx(start), "queued bonus holds initial origin before first step")
	game._process(0.24)
	check(actor.visual.y > start.y and actor.visual.y < middle.y, "queued bonus preserves first moving step")
	game._process(0.28)
	check(actor.visual.y > middle.y and actor.visual.y < finish.y, "queued bonus animates second step in order")
	game._process(0.3)
	check(actor.visual.is_equal_approx(finish), "queued bonus ends on actual board square")

	print("ENEMY ENCOUNTER RESULT ", checks - failures, " passed, ", failures, " failed")
	game.queue_free();quit(1 if failures else 0)
func check_rules():
	for kind in ["p", "q"]:
		for y in [0, 4, 5, 9]:
			var pawn = piece(kind, Vector2i(4, y))
			for target in [Vector2i(4, y + 1), Vector2i(3, y), Vector2i(5, y), Vector2i(4, y - 1), Vector2i(3, y + 1)]:
				var d = target - pawn.pos
				var expected = R.inside(target) and (d == Vector2i(0, 1) or (y >= 5 and abs(d.x) == 1 and d.y == 0))
				check(R.attacks(pawn, target, [pawn]) == expected, kind + " pawn directions " + str(pawn.pos) + " -> " + str(target))
	var advisor = piece("a", Vector2i(3, 0))
	check(R.moves(advisor, [advisor], Vector2i(8, 9)) == [Vector2i(4, 1)], "corner advisor has only palace diagonal")
	advisor.pos = Vector2i(4, 1)
	var legal = R.moves(advisor, [advisor], Vector2i(8, 9))
	check(legal.size() == 4, "center advisor has four diagonals")
	for target in legal: check(target.x >= 3 and target.x <= 5 and target.y >= 0 and target.y <= 2 and abs(target.x - 4) == 1 and abs(target.y - 1) == 1, "advisor remains in palace")
	check(not R.attacks(advisor, Vector2i(4, 2), [advisor]), "advisor cannot move straight")
	check(Vector2i(3, 0) not in R.moves(advisor, [advisor, piece("p", Vector2i(3, 0))], Vector2i(8, 9)), "advisor cannot land on ally")
	var elephant = piece("e", Vector2i(2, 4))
	check(not R.attacks(elephant, Vector2i(4, 6), [elephant]), "elephant cannot cross river")
	check(not R.attacks(elephant, Vector2i(4, 2), [elephant, piece("p", Vector2i(3, 3))]), "elephant eye blocks")
	var horse = piece("h", Vector2i(4, 4))
	check(not R.attacks(horse, Vector2i(6, 5), [horse, piece("p", Vector2i(5, 4))]), "horse leg blocks")
	var cannon = piece("c", Vector2i(4, 0));var screen = piece("p", Vector2i(4, 3))
	check(not R.attacks(cannon, Vector2i(4, 6), [cannon]), "cannon attack requires screen")
	check(R.attacks(cannon, Vector2i(4, 6), [cannon, screen]), "cannon attack has exactly one screen")
	check(not R.attacks(cannon, Vector2i(4, 6), [cannon, screen, piece("p", Vector2i(4, 4))]), "two screens block cannon")
	check(Vector2i(4, 4) not in R.moves(cannon, [cannon, screen], Vector2i(8, 9)), "cannon movement cannot jump screen")
func check_templates():
	for id in E.TEMPLATES:
		for tier in ["battle", "elite", "boss"]:
			fixture(id, tier)
			var seen = {};var general = 0
			for enemy in game.enemies:
				check(R.inside(enemy.pos) and not seen.has(enemy.pos), id + " unique on-board spawn")
				seen[enemy.pos] = true
				var expected = 2 if enemy.kind == "h" else (3 if enemy.kind == "e" else (9 if tier == "boss" else (5 if tier == "elite" else 3)) if enemy.kind == "g" else 1)
				check(enemy.hp == expected and enemy.max_hp == expected, id + " " + tier + " HP " + enemy.kind)
				if enemy.kind == "g": general += 1
				if enemy.kind == "a": check(enemy.pos.x >= 3 and enemy.pos.x <= 5 and enemy.pos.y <= 2, "advisor spawns in palace")
				if enemy.kind == "e": check(enemy.pos.y <= 4, "elephant spawns behind river")
				var options = R.moves(enemy, game.enemies, game.player)
				var before = game.enemies.duplicate(true)
				var choice = game.ENEMY_AI.choose(enemy, options, game.enemies, game.player, game.rng)
				check(choice in options or (options.is_empty() and choice == Vector2i(-1, -1)), "AI chooses legal option " + id + " " + enemy.kind)
				check(game.enemies == before, "AI scoring is read-only")
			check(general == 1 and not R.threatened(Vector2i(4, 9), game.enemies), id + " safe opening and one general")
	var a = RandomNumberGenerator.new();var b = RandomNumberGenerator.new();a.seed = 9381;b.seed = 9381
	for row in 8:
		for tier in ["battle", "elite", "boss", "camp"]:
			var left = E.node_config(tier, row, a);var right = E.node_config(tier, row, b)
			check(left == right, "node config fixed by independent map seed")
			check(left.is_empty() if tier == "camp" else E.valid_config(left), "generated config valid")
	fixture("quick_pawns")
	game.enemies = [];E.setup(game, config("quick_pawns", "battle"))
	for enemy in game.enemies:
		if enemy.kind == "q": check(enemy.period == 1, "quick pawn cadence one")
		if enemy.kind == "p": check(enemy.period == 2, "normal pawn cadence two")
func check_double_step():
	fixture("rook_pressure", "elite", ["double_step"]);game.enemies = [game.enemies[0]]
	var pawn = add("p", Vector2i(2, 0));pawn.march_mark = true;pawn.normal_moves = 0;pawn.intent = Vector2i(2, 1)
	game.end_turn()
	check(pawn.pos == Vector2i(2, 1) and pawn.normal_moves == 1, "first normal movement has no bonus")
	pawn.intent = Vector2i(2, 2);game.end_turn()
	check(pawn.pos == Vector2i(2, 3) and pawn.normal_moves == 2, "second successful movement adds one step only")
	pawn.intent = Vector2i(2, 4);pawn.cd = 2;game.end_turn()
	check(pawn.pos == Vector2i(2, 3) and pawn.normal_moves == 2, "bonus cannot skip countdown")
	pawn.stun = 1;pawn.cd = 1;game.end_turn()
	check(pawn.pos == Vector2i(2, 3) and pawn.normal_moves == 2 and pawn.cd == 1, "stun prevents movement and counter advancement")
	fixture("rook_pressure", "elite", ["double_step"]);game.enemies = [game.enemies[0]]
	pawn = add("p", Vector2i(2, 0));pawn.march_mark = true;pawn.normal_moves = 1;pawn.intent = Vector2i(2, 1)
	add("p", Vector2i(2, 1), 99);game.end_turn()
	check(pawn.pos == Vector2i(2, 0) and pawn.normal_moves == 1, "blocked normal move does not count or get bonus")
	for shield in [false, true]:
		fixture("rook_pressure", "elite", ["double_step"]);game.enemies = [game.enemies[0]]
		pawn = add("p", Vector2i(2, 0));pawn.march_mark = true;pawn.normal_moves = 1;pawn.intent = Vector2i(2, 1)
		game.player = Vector2i(2, 1);game.shield_charges = 1 if shield else 0
		var old_lives = game.lives;game.end_turn()
		check(pawn.pos == Vector2i(2, 0) and pawn.normal_moves == 1, "attacker remains still even with bonus and shield=" + str(shield))
		check(game.lives == old_lives - (0 if shield else 1), "attack phase damage/shield unchanged")
	fixture("rook_pressure", "elite", ["double_step"]);game.enemies = [game.enemies[0]]
	pawn = add("p", Vector2i(2, 0));pawn.march_mark = true;pawn.normal_moves = 1;pawn.intent = Vector2i(2, 1)
	game.player = Vector2i(2, 3);var old_lives = game.lives;game.end_turn()
	check(pawn.pos == Vector2i(2, 2) and game.lives == old_lives and R.threatened(game.player, game.enemies), "bonus move creates next-turn threat, never immediate attack")
func check_relay():
	fixture("horse_cannon", "elite", ["horse_relay"])
	for i in 4: E.finish_phase(game, 0)
	check(count_relay() == 0 and game.encounter_state.spawn_cell == Vector2i(0, 0), "wave one announced after phase four")
	var before = game.enemies.size();game.end_turn()
	check(game.enemies.size() == before + 1 and count_relay() == 1, "wave one spawns after fifth phase")
	var horse = game.enemies.back()
	check(horse.pos == Vector2i(0, 0) and horse.cd == 3 and horse.hp == 2 and horse.max_hp == 2, "new horse has two HP and no birth-phase move/countdown")
	game.encounter_state.phases = 9;game.encounter_state.spawn_cell = Vector2i(8, 0);E.finish_phase(game, 0)
	check(count_relay() == 2, "second wave permits two reinforcement horses independently of initial horse")
	game.encounter_state.phases = 14;game.encounter_state.spawn_cell = Vector2i(0, 0)
	game.enemies[index_of(horse.uid)].pos = Vector2i(0, 2);E.finish_phase(game, 0)
	check(count_relay() == 2, "third wave does not exceed two living reinforcement horses")
	for kind in ["p", "stake", "player"]:
		fixture("horse_cannon", "elite", ["horse_relay"])
		game.encounter_state.phases = 4;game.encounter_state.spawn_cell = Vector2i(0, 0)
		if kind == "player": game.player = Vector2i(0, 0)
		else: add(kind, Vector2i(0, 0), 99)
		E.finish_phase(game, 0)
		check(count_relay() == 0 and game.encounter_state.spawn_cell == Vector2i(-1, -1), kind + " blocks announced wave")
		game.player = Vector2i(8, 9)
		for i in range(game.enemies.size() - 1, -1, -1):
			if game.enemies[i].pos == Vector2i(0, 0): game.enemies.remove_at(i)
		E.finish_phase(game, 0);check(count_relay() == 0, "missed wave never banked")
	fixture("horse_cannon", "elite", ["horse_relay"]);game.encounter_state.phases = 4;game.encounter_state.spawn_cell = Vector2i(0, 0)
	game.enemies.remove_at(0);E.finish_phase(game, 0);check(count_relay() == 0, "no general means no reinforcement")
func check_river():
	fixture("river_cannon", "elite", ["river_signal"])
	var pawn = game.enemies[index_of(game.encounter_state.signal_uid)]
	var cannon = game.enemies[index_of(game.encounter_state.cannon_uid)]
	pawn.pos = Vector2i(2, 5);E.after_normal_move(game, pawn, Vector2i(2, 4))
	check(game.encounter_state.river_triggered and cannon.bonus_pending, "designated pawn crossing arms paired cannon")
	check(not E.wants_bonus(game, cannon), "river signal cannot add a move in the same enemy phase")
	game.encounter_state.phases += 1
	check(E.wants_bonus(game, cannon), "river bonus becomes eligible from next enemy phase")
	cannon.bonus_pending = false;E.after_normal_move(game, pawn, Vector2i(2, 4))
	check(not cannon.bonus_pending, "river signal triggers only once")
	fixture("river_cannon", "elite", ["river_signal"])
	var other = add("p", Vector2i(6, 5));E.after_normal_move(game, other, Vector2i(6, 4))
	check(not game.encounter_state.river_triggered, "other pawn cannot trigger signal")
	var uid = game.encounter_state.signal_uid;game.enemies.remove_at(index_of(uid))
	other = add("p", Vector2i(2, 5));E.after_normal_move(game, other, Vector2i(2, 4))
	check(not game.encounter_state.river_triggered, "replacement on signal square cannot inherit UID trigger")
func check_rotation_and_retaliation():
	fixture("palace_guard", "elite", ["palace_rotation"])
	var selected = E.selected_guard(game)
	for enemy in game.enemies:
		check(E.wants_bonus(game, enemy) == (enemy.uid == selected), "only selected guard receives rotation bonus")
	game.encounter_state.phases += 1;check(E.selected_guard(game) != selected, "rotation advances with completed phase")
	fixture("two_wings", "elite", ["last_stand"])
	var general = game.enemies[0];var before = game.enemies.duplicate(true)
	game.damage_enemy(0, 0, 1)
	check(game.encounter_state.retaliated and general.hp == 4, "first surviving general damage activates last stand")
	for i in game.enemies.size():
		var enemy = game.enemies[i]
		check(enemy.pos == before[i].pos, "retaliation never moves during player card")
		check(enemy.get("bonus_pending", false) == (enemy.kind in ["a", "e", "p", "q"]), "retaliation marks only existing guards and pawns")
		if enemy.kind in ["a", "e", "p", "q"]: enemy.bonus_pending = false
	game.damage_enemy(0, 0, 1)
	for enemy in game.enemies: check(not enemy.get("bonus_pending", false), "later hit cannot rearm last stand")
	var newcomer = add("p", Vector2i(0, 3));check(not newcomer.get("bonus_pending", false), "later spawn does not inherit retaliation")
	fixture("two_wings", "elite", ["last_stand"]);game.damage_enemy(0, 0, 99)
	check(not game.encounter_state.retaliated, "lethal general damage grants no retaliation")
func check_round_trips():
	fixture("rook_pressure", "elite", ["double_step"]);game.enemies = [game.enemies[0]]
	var pawn = add("p", Vector2i(2, 0));pawn.march_mark = true;pawn.normal_moves = 1;pawn.intent = Vector2i(2, 1)
	var before = game.history.capture();game.end_turn();var after = game.history.capture()
	check(game.history.undo() and game.history.capture() == before, "undo restores modifier counters positions and RNG")
	game.end_turn();check(game.history.capture() == after, "replay produces same modifier result and RNG")
	game.new_expedition();game.route.enter(0);game.debug_skip();game.input_lock = 0;game.choose_reward(-1);game.route.enter(2)
	var saved = game.history.capture();var saved_route = game.route.state.duplicate(true)
	game.route.save();game.show_home()
	check(game.route.resume() and game.history.capture() == saved and game.route.state == saved_route, "elite encounter and fixed node config survive save/resume")
	check(game.route.WEB_SAVE_KEY == "yixing.route_run.v0100", "new encounter schema isolated from old demo runs")
	game.debug_skip();game.input_lock = 0;game.choose_reward(-1)
	check(game.encounter_state.is_empty(), "map completion clears battle-only encounter state")

func move_effects(uid: int) -> int:
	var count = 0
	for fx in game.effects:
		if fx.kind == "move" and fx.get("piece", {}).get("uid", -1) == uid: count += 1
	return count
func check_actual_modifiers():
	fixture("palace_final", "boss", ["palace_rotation", "last_stand"])
	var guard = game.enemies[index_of(E.selected_guard(game))]
	game.damage_enemy(0, 0, 1);game.clear_effects()
	guard.cd = 1;guard.period = 1;guard.intent = Vector2i(4, 1)
	game.end_turn()
	check(move_effects(guard.uid) == 2 and guard.normal_moves == 1 and not guard.bonus_pending, "rotation and retaliation together grant two total movements, not three")
	check(guard.pos.x >= 3 and guard.pos.x <= 5 and guard.pos.y <= 2, "both guard steps stay within palace")
	fixture("palace_guard", "elite", ["palace_rotation"])
	guard = game.enemies[index_of(E.selected_guard(game))];guard.cd = 2;guard.period = 2
	game.end_turn();check(move_effects(guard.uid) == 0 and guard.cd == 1, "rotation cannot bypass normal countdown")
	fixture("two_wings", "elite", ["last_stand"]);game.enemies = [game.enemies[0]]
	var pawn = add("p", Vector2i(2, 0));pawn.intent = Vector2i(2, 1)
	game.damage_enemy(0, 0, 1);game.clear_effects();game.end_turn()
	check(pawn.pos == Vector2i(2, 2) and move_effects(pawn.uid) == 2 and not pawn.bonus_pending, "retaliation consumed by next successful normal action")
	game.clear_effects();pawn.intent = Vector2i(2, 3);game.end_turn()
	check(pawn.pos == Vector2i(2, 3) and move_effects(pawn.uid) == 1, "retaliation never repeats")
	fixture("two_wings", "elite", ["last_stand"]);game.enemies = [game.enemies[0]]
	pawn = add("p", Vector2i(2, 0));pawn.intent = Vector2i(2, 1)
	game.queue_bleed(0, 1);game.clear_effects();game.end_turn()
	check(pawn.pos == Vector2i(2, 1) and pawn.bonus_pending and game.encounter_state.retaliated, "delayed general bleed arms after movement, without retroactive bonus")
	game.clear_effects();pawn.intent = Vector2i(2, 2);game.end_turn()
	check(pawn.pos == Vector2i(2, 3) and move_effects(pawn.uid) == 2, "bleed retaliation applies next normal action")
	fixture("two_wings", "elite", ["last_stand"]);game.enemies = [game.enemies[0]]
	pawn = add("p", Vector2i(2, 0));pawn.intent = Vector2i(2, 1)
	var blocker = add("p", Vector2i(2, 2), 99)
	game.damage_enemy(0, 0, 1);game.clear_effects();game.end_turn()
	check(pawn.pos == Vector2i(2, 1) and not pawn.bonus_pending and move_effects(pawn.uid) == 1, "no legal bonus step consumes pending on successful normal action")
	game.enemies.remove_at(index_of(blocker.uid));game.clear_effects();pawn.intent = Vector2i(2, 2);game.end_turn()
	check(pawn.pos == Vector2i(2, 2) and move_effects(pawn.uid) == 1, "blocked extra step never accumulates")
	fixture("river_cannon", "elite", ["river_signal"])
	pawn = game.enemies[index_of(game.encounter_state.signal_uid)]
	var cannon = game.enemies[index_of(game.encounter_state.cannon_uid)]
	game.enemies = [game.enemies[0], pawn, cannon]
	pawn.cd = 1;pawn.period = 2;pawn.intent = Vector2i(2, 5)
	cannon.pos = Vector2i(0, 2);cannon.cd = 1;cannon.period = 1;cannon.intent = Vector2i(1, 2)
	game.clear_effects();game.end_turn()
	check(game.encounter_state.river_triggered and move_effects(cannon.uid) == 1 and cannon.bonus_pending, "pawn before cannon in array still cannot grant same-phase river bonus")
	game.clear_effects();cannon.intent = Vector2i(1, 3);game.end_turn()
	check(move_effects(cannon.uid) == 2 and not cannon.bonus_pending, "river cannon consumes bonus next phase")
	fixture("horse_cannon", "elite", ["horse_relay"]);game.encounter_state.phases = 4;game.encounter_state.spawn_cell = Vector2i(0, 0)
	var saved = game.history.capture();game.end_turn();var spawned = game.history.capture()
	check(game.history.undo() and game.history.capture() == saved and count_relay() == 0, "undo wave removes horse and restores forecast/UID")
	game.end_turn();check(game.history.capture() == spawned and count_relay() == 1, "replay wave spawns identical horse exactly once")
func press_key(code: int):
	var event = InputEventKey.new();event.pressed = true;event.keycode = code;game._input(event)
func mouse_click(pos: Vector2, button: int = MOUSE_BUTTON_LEFT):
	var event = InputEventMouseButton.new();event.pressed = true;event.position = pos;event.button_index = button;game._gui_input(event)
	event.pressed = false;game._gui_input(event)
func touch_click(pos: Vector2):
	var event = InputEventScreenTouch.new();event.index = 0;event.position = pos;event.pressed = true;game._input(event)
	event.pressed = false;game._input(event)
func check_modal_and_geometry():
	for size in [Vector2(1280, 940), Vector2(390, 844), Vector2(844, 390), Vector2(360, 640)]:
		fixture("palace_final", "boss", ["palace_rotation", "last_stand"]);game.configure_layout(size)
		var surface = Rect2(Vector2.ZERO, game.ui_size)
		var panel_rect = game.encounter_panel_rect();var close_rect = game.encounter_close_rect()
		check(surface.encloses(panel_rect) and panel_rect.encloses(close_rect), "rule modal/close fit viewport " + str(size))
		if game.mobile_layout:
			var button = game.encounter_rules_rect()
			check(surface.encloses(button) and not button.intersects(game.debug_skip_rect()) and not button.intersects(game.END_TURN_RECT), "rules button avoids debug and end turn " + str(size))
			game.handle_click(button.get_center());check(game.encounter_info_open, "rules button opens modal")
		else: game.encounter_info_open = true
		var before = game.history.capture();var entries = game.history.entries.duplicate(true)
		press_key(KEY_SPACE);press_key(KEY_ENTER)
		check(game.encounter_info_open and game.history.capture() == before and game.history.entries == entries, "keyboard cannot pass through rules modal " + str(size))
		mouse_click(game.END_TURN_RECT.get_center())
		check(game.history.capture() == before, "mouse close/outside click does not end turn " + str(size))
		game.encounter_info_open = true;touch_click(game.END_TURN_RECT.get_center())
		check(game.history.capture() == before, "touch close/outside click does not end turn " + str(size))
		game.encounter_info_open = true;touch_click(close_rect.get_center())
		check(not game.encounter_info_open and game.history.capture() == before, "close control is safe for touch " + str(size))
		game.encounter_info_open = true;press_key(KEY_ESCAPE)
		check(not game.encounter_info_open and game.history.capture() == before, "Escape safely closes rule modal")
		var hp_size = 12 if game.mobile_layout else 14
		var hp_width = game.FONT.get_string_size("9/9", HORIZONTAL_ALIGNMENT_LEFT, -1, hp_size).x + 6
		check(hp_width <= game.CELL, "nine-HP numeric badge fits one board cell " + str(size))
		# No hidden-state card mutation through the modal's right-click path.
		game.hand = ["sword"];game.hand_ids = [];game.sync_hand_ids();game.selected = 0
		game.encounter_info_open = true;mouse_click(game.cell_pos(game.player), MOUSE_BUTTON_RIGHT)
		check(game.selected == 0, "right click does not reach underlying selected card while modal open")
func check_invalid_encounters():
	game.new_expedition();game.route.enter(0)
	var route = game.route.state.duplicate(true);var battle = game.history.capture()
	var screen = game.screen
	for bad_config in [null, "bad", {}, {"id": "missing", "tier": "battle", "rules": []}, config("three_pawns", "boss"), config("rook_pressure", "elite", ["double_step", "double_step"]), config("three_pawns", "battle", ["double_step"]), config("horse_cannon", "elite", ["unknown"])]:
		var bad_route = route.duplicate(true);bad_route.nodes[0].encounter = bad_config
		check(not game.route.valid_snapshot(bad_route, battle, screen), "reject malformed node encounter " + str(bad_config))
	for patch in [{"phases": -1}, {"phases": "5"}, {"retaliated": 1}, {"river_triggered": "yes"}, {"signal_uid": -2}, {"signal_uid": 0}, {"cannon_uid": "2"}, {"guard_uids": [1, 1]}, {"guard_uids": [-1]}, {"spawn_cell": Vector2i(9, 0)}, {"spawn_cell": Vector2i(0, 0)}]:
		var bad_battle = battle.duplicate(true)
		for key in patch: bad_battle.encounter_state[key] = patch[key]
		check(not game.route.valid_snapshot(route, bad_battle, screen), "reject malformed battle encounter " + str(patch))
	var mismatch = battle.duplicate(true);mismatch.encounter_state.config = config("quick_pawns", "battle")
	check(not game.route.valid_snapshot(route, mismatch, screen), "battle encounter must match fixed pending node config")
	mismatch = battle.duplicate(true);mismatch.encounter_state = {}
	check(not game.route.valid_snapshot(route, mismatch, screen), "combat save cannot silently omit its encounter")
	game.route.save();var original = ConfigFile.new();original.load(game.route.SAVE)
	var corrupted = ConfigFile.new();corrupted.parse(original.encode_to_text());corrupted.set_value("run", "battle", mismatch);corrupted.save(game.route.SAVE)
	check(not game.route.resume() and game.history.capture() == battle and game.route.state == route, "malformed encounter resume leaves live state untouched")
	original.save(game.route.SAVE)
func check_new_glyphs():
	var font = game.FONT.duplicate();font.allow_system_fallback = false
	var text = "士 急行卒 疾 援马 2/2 3/3 5/5 9/9 军阵规则 关闭 返回棋盘"
	for id in E.TEMPLATES: text += E.TEMPLATES[id].name
	for id in E.RULE_NAMES: text += E.RULE_NAMES[id] + E.RULE_TEXT[id]
	for glyph in text:
		if glyph not in [" ", "\n", "\t"]: check(font.has_char(glyph.unicode_at(0)), "new encounter glyph supported " + glyph)
func check_ai_strategy():
	var ai = game.ENEMY_AI
	# Pawn can preserve a cannon screen rather than advance into the cannon's row.
	var pawn = piece("p", Vector2i(4, 5));var cannon = piece("c", Vector2i(4, 0))
	var board = [pawn, cannon];var player = Vector2i(4, 9)
	check(ai.candidate_score(pawn, Vector2i(4, 6), board, player) > ai.candidate_score(pawn, Vector2i(3, 5), board, player), "pawn values keeping its cannon screen")
	# An advanced friendly pawn permits a legal cannon crossing even before alignment.
	cannon = piece("c", Vector2i(0, 1));pawn = piece("q", Vector2i(6, 6));board = [cannon, pawn]
	check(ai.candidate_score(cannon, Vector2i(0, 5), board, Vector2i(8, 9)) > ai.candidate_score(cannon, Vector2i(0, 3), board, Vector2i(8, 9)), "cannon follows advanced quick pawn across river")
	var general = piece("g", Vector2i(4, 0));var advisor = piece("a", Vector2i(4, 1));board = [general, advisor]
	check(ai.candidate_score(advisor, Vector2i(3, 0), board, Vector2i(4, 9)) > ai.candidate_score(advisor, Vector2i(3, 2), board, Vector2i(4, 9)), "advisor prefers guarding general over blindly chasing player")
	var rook = piece("r", Vector2i(0, 0));pawn = piece("p", Vector2i(4, 5));board = [rook, pawn]
	check(ai.candidate_score(rook, Vector2i(3, 0), board, Vector2i(4, 9)) > ai.candidate_score(rook, Vector2i(2, 0), board, Vector2i(4, 9)), "rook values adjacent file of pawn pressure")
	var horse = piece("h", Vector2i(2, 2));cannon = piece("c", Vector2i(4, 0));board = [horse, cannon]
	check(ai.candidate_score(horse, Vector2i(4, 3), board, Vector2i(4, 9)) > ai.candidate_score(horse, Vector2i(0, 3), board, Vector2i(4, 9)), "horse can form a cannon screen in coordinated attack")

func cloned_rng() -> RandomNumberGenerator:
	var result = RandomNumberGenerator.new();result.seed = game.rng.seed;result.state = game.rng.state;return result
func isolated_mover(kind: String, pos: Vector2i) -> Dictionary:
	fixture();game.enemies = [game.enemies[0]];game.encounter_state = {}
	return add(kind, pos)
func alternative_legal(mover: Dictionary, avoid: Vector2i) -> Vector2i:
	for option in R.moves(mover, game.enemies, game.player):
		if option != avoid: return option
	return Vector2i(-1, -1)
func check_reactive_decision():
	var rook = isolated_mover("r", Vector2i(0, 0));game.player = Vector2i(7, 8)
	rook.intent = Vector2i(0, 5)
	var old_rng = game.rng.state;var board = game.enemies.duplicate(true)
	game.plan_intents()
	check(game.rng.state == old_rng, "planning warning never consumes decision RNG")
	for enemy in game.enemies: check(enemy.get("intent", Vector2i(-1, -1)) == Vector2i(-1, -1), "warning contains no destination")
	for repeat in 4: game.plan_intents()
	check(game.rng.state == old_rng, "repeated warning refresh never rerolls future movement")
	var random = cloned_rng();var expected = game.ENEMY_AI.choose(rook, R.moves(rook, game.enemies, game.player), game.enemies, game.player, random)
	rook.intent = alternative_legal(rook, expected)
	check(rook.intent != expected and rook.intent in R.moves(rook, game.enemies, game.player), "stale rook destination remains legal but differs from fresh decision")
	game.end_turn()
	check(rook.pos == expected, "end-turn rook ignores still-legal stale destination")
	check(game.rng.state == random.state, "only actual mover decision consumes RNG, not next-turn warnings")
	# Both ordinary and horse player movement happen after the previous warning.
	for identity in ["king", "horse"]:
		rook = isolated_mover("r", Vector2i(0, 0));game.player_skill = identity;game.player = Vector2i(4, 6)
		var target = Vector2i(4, 7) if identity == "king" else Vector2i(6, 7)
		game.basic_move(target);check(game.player == target, identity + " active move fixture succeeds")
		random = cloned_rng();expected = game.ENEMY_AI.choose(rook, R.moves(rook, game.enemies, game.player), game.enemies, game.player, random)
		rook.intent = alternative_legal(rook, expected);game.end_turn()
		check(rook.pos == expected, identity + " enemy decisions use final player location after free movement")
	# An attack that kills then enters the target square must also affect reaction.
	rook = isolated_mover("r", Vector2i(0, 0));game.player = Vector2i(4, 6)
	add("p", Vector2i(5, 6), 99);game.hand = ["advance"];game.hand_ids = [];game.energy = 3
	game.play_card(0, Vector2i(5, 6));check(game.player == Vector2i(5, 6), "attack displacement fixture succeeds")
	random = cloned_rng();expected = game.ENEMY_AI.choose(rook, R.moves(rook, game.enemies, game.player), game.enemies, game.player, random)
	rook.intent = alternative_legal(rook, expected);game.end_turn()
	check(rook.pos == expected, "reaction uses player location after attack displacement")
	# Recoil occurs before movement and changes the location the remaining army reacts to.
	rook = isolated_mover("r", Vector2i(0, 0));game.player = Vector2i(4, 4)
	var attacker = add("p", Vector2i(4, 3), 1)
	game.enemies = [game.enemies[0], attacker, rook]
	random = cloned_rng();var safe = R.safe_recoil(game.player, game.enemies)
	var destination: Vector2i = safe[random.randi_range(0, safe.size() - 1)]
	expected = game.ENEMY_AI.choose(rook, R.moves(rook, game.enemies, destination), game.enemies, destination, random)
	rook.intent = alternative_legal(rook, expected);game.end_turn()
	check(game.player == destination and rook.pos == expected, "post-hit movement reacts to recoil destination with deterministic RNG")
	check(attacker.pos == Vector2i(4, 3), "attacker stays in place while others react")
	check(game.rng.state == random.state, "attacker consumes no hidden movement RNG after recoil")
	# Later pieces evaluate the board left by earlier pieces, not one global snapshot.
	rook = isolated_mover("r", Vector2i(0, 1));game.player = Vector2i(4, 4)
	var second = add("r", Vector2i(8, 1));random = cloned_rng()
	board = game.enemies.duplicate(true)
	var first_copy: Dictionary = board[1];var second_copy: Dictionary = board[2]
	var first_target = game.ENEMY_AI.choose(first_copy, R.moves(first_copy, board, game.player), board, game.player, random)
	first_copy.pos = first_target
	var second_target = game.ENEMY_AI.choose(second_copy, R.moves(second_copy, board, game.player), board, game.player, random)
	rook.intent = Vector2i(0, 2);second.intent = first_target
	game.end_turn()
	check(rook.pos == first_target and second.pos == second_target and rook.pos != second.pos, "later rook reacts to earlier rook occupancy")
	# A pawn screen changes the hypothetical cannon position scores before cannon acts.
	fixture();game.enemies = [game.enemies[0]];game.encounter_state = {};game.enemies[0].pos = Vector2i(3, 0);game.player = Vector2i(4, 9)
	var pawn = add("p", Vector2i(4, 3), 1);var cannon = add("c", Vector2i(0, 0), 1)
	random = cloned_rng();board = game.enemies.duplicate(true)
	var pawn_copy: Dictionary = board[1];var cannon_copy: Dictionary = board[2]
	pawn_copy.pos = game.ENEMY_AI.choose(pawn_copy, R.moves(pawn_copy, board, game.player), board, game.player, random)
	var cannon_target = game.ENEMY_AI.choose(cannon_copy, R.moves(cannon_copy, board, game.player), board, game.player, random)
	cannon.intent = alternative_legal(cannon, cannon_target);game.end_turn()
	check(pawn.pos == pawn_copy.pos and cannon.pos == cannon_target, "cannon reacts to current friendly screen position")
	# Frozen and unready pieces do not make a hidden random decision.
	rook = isolated_mover("r", Vector2i(0, 0));rook.cd = 2;rook.intent = Vector2i(0, 5)
	old_rng = game.rng.state;game.end_turn();check(rook.pos == Vector2i(0, 0) and game.rng.state == old_rng, "not-ready piece neither moves nor rolls a destination")
	rook.stun = 1;rook.cd = 1;old_rng = game.rng.state;game.end_turn()
	check(rook.pos == Vector2i(0, 0) and game.rng.state == old_rng, "frozen piece neither moves nor rolls a destination")
	# Replay restores the input position and RNG, and computes the same fresh reaction.
	rook = isolated_mover("r", Vector2i(0, 0));rook.intent = Vector2i(0, 5);game.player = Vector2i(7, 8)
	var before = game.history.capture();game.end_turn();var after = game.history.capture()
	check(game.history.undo() and game.history.capture() == before, "undo restores pre-reaction state and legacy stale intent without using it")
	game.end_turn();check(game.history.capture() == after, "reactive decisions replay exactly after undo")
	# Persist a legal, incorrect old intent; resume must still use current state.
	game.new_expedition();game.route.enter(0)
	game.enemies = [game.enemies[0]];game.enemies[0].cd = 999
	game.player = Vector2i(7, 8);rook = add("r", Vector2i(0, 0), 1)
	random = cloned_rng();expected = game.ENEMY_AI.choose(rook, R.moves(rook, game.enemies, game.player), game.enemies, game.player, random)
	rook.intent = alternative_legal(rook, expected);var uid = rook.uid
	game.route.save();game.show_home();check(game.route.resume(), "reactive fixture resumes")
	game.end_turn();check(game.enemies[index_of(uid)].pos == expected, "resumed stale intent cannot override fresh enemy decision")
	var source = FileAccess.get_file_as_string("res://main.gd")
	check(not 'var intent: Vector2i = inspected.get("intent"' in source, "board inspection no longer draws future destination")
