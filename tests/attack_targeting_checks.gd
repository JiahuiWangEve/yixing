extends SceneTree
# Production legality, pure targeting, and real mouse/touch release paths.
const TARGETING = preload("res://attack_targeting.gd")
const SUPPORT = preload("res://test_support.gd")
const INVALID = Vector2i(-1, -1)
var game
var checks = 0
var failures = 0

func _initialize(): call_deferred("run")

func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("ATTACK TARGETING: " + label)

func fresh(cards: Array = ["sword"], size: Vector2 = Vector2(1280, 940)):
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
	game.player_visual = game.cell_pos(game.player)

func add(cell: Vector2i, kind: String = "p", hp: int = 5) -> Dictionary:
	game.add_enemy(kind, cell, 999)
	game.enemies.back().hp = hp;game.enemies.back().max_hp = hp
	return game.enemies.back()

func pack() -> Dictionary:
	return {"battle": game.history.capture(), "selected": game.selected, "history": game.history.entries.duplicate(true), "effects": game.effects.duplicate(true), "route": game.route.state.duplicate(true), "tutorial_action": game.tutorial._last_action, "tutorial_before": game.tutorial._before.duplicate(true)}

func button(position: Vector2, pressed: bool, kind: String = "mouse", finger: int = 0, canceled: bool = false):
	if kind == "touch":
		var event = InputEventScreenTouch.new()
		event.index = finger;event.position = position;event.pressed = pressed;event.canceled = canceled
		game._input(event)
	else:
		var event = InputEventMouseButton.new()
		event.device = 0;event.button_index = MOUSE_BUTTON_LEFT;event.position = position;event.pressed = pressed
		game._gui_input(event)

func motion(position: Vector2, kind: String = "mouse", finger: int = 0):
	if kind == "touch":
		var event = InputEventScreenDrag.new();event.index = finger;event.position = position
		game._input(event)
	else:
		var event = InputEventMouseMotion.new();event.device = 0;event.position = position
		game._gui_input(event)

func begin(index: int = 0, kind: String = "mouse") -> Vector2:
	var source: Vector2 = SUPPORT.card_point(game, index)
	button(source, true, kind)
	check(game.gesture.active and game.gesture.uid == game.hand_ids[index], "pointer down captures exact UID")
	return source

func upward() -> Vector2:
	return Vector2(game.full_hand_area().position.x + 40, game.full_hand_area().position.y - 32)

func drop(position: Vector2, kind: String = "mouse", index: int = 0):
	begin(index, kind);motion(position, kind);button(position, false, kind)

func check_classification_and_all_attacks():
	fresh()
	for id in game.CARDS:
		check(game.attack_targets.is_attack(id) == (game.CARDS[id][3] == "攻"), "classification follows actual type " + id)
	for id in ["suppress", "horse", "straight", "treasure_king_step", "treasure_transfer", "__free_king", "missing"]:
		check(not game.attack_targets.is_attack(id), "no extra attack shortcut " + id)
	for id in game.board_info.ATTACKS:
		fresh([id])
		var target = Vector2i(4, 5)
		if id in ["cannon", "cannon_shot"]:
			target = Vector2i(4, 3);add(Vector2i(4, 4), "stake")
		elif id == "diagonal": target = Vector2i(5, 5)
		elif id == "knight_assault": target = Vector2i(5, 4)
		var victim = add(Vector2i(5, 5) if id == "airdrop" else target)
		if id == "cannon_shot": game.player_skill = "artillery";game.artillery_mode = "attack";game.reload_ready = true
		if id in ["sweep", "blood_break"]: target = game.player
		var before = pack()
		var state: Dictionary = game.attack_targets.state(0)
		check(not state.actions.is_empty(), "every existing legal attack enumerated " + id)
		check(game.attack_targets.resolve_release(0, target, true) == target, "explicit existing legality preserved " + id)
		check(pack() == before, "enumeration and resolution are pure " + id)
		if id == "airdrop":
			check(state.mode == "landing" and state.range_cells.is_empty() and state.enemy_cells.is_empty() and state.auto_target == INVALID, "airdrop never exposes generic range or auto action")
		else:
			check(victim.pos in state.enemy_cells and victim.uid in state.enemy_uids and not state.range_cells.is_empty(), "range and eligible victim available " + id)
			check(game.attack_targets.resolve_release(0, INVALID, false) != INVALID, "one distinct action can auto-resolve " + id)
		if id == "pierce":
			var preview: Dictionary = game.board_info.preview(0, target)
			check(preview.affected[0].damage == 0 and preview.affected[0].delayed and state.actions.size() == 1, "zero immediate damage does not hide delayed pierce")

func check_single_choices_and_geometry():
	fresh();var state: Dictionary = game.attack_targets.state(0)
	check(state.actions.is_empty() and state.range_cells.is_empty() and state.auto_target == INVALID, "no enemy means no available single attack")
	var first = add(Vector2i(4, 5));state = game.attack_targets.state(0)
	check(state.actions.size() == 1 and state.auto_target == first.pos and state.enemy_cells == [first.pos], "one legal single victim is unique")
	check(Vector2i(3, 6) in state.range_cells and Vector2i(5, 5) not in state.range_cells, "sword geometry includes empty orthogonal cells only")
	add(Vector2i(5, 6));state = game.attack_targets.state(0)
	check(state.actions.size() == 2 and state.auto_target == INVALID, "two single victims require explicit aim")
	check(game.attack_targets.resolve_release(0, Vector2i(4, 5), true) == Vector2i(4, 5), "explicit target allowed amid ambiguity")
	fresh();add(Vector2i(4, 5));add(Vector2i(6, 6))
	check(game.attack_targets.resolve_release(0, Vector2i(6, 6), true) == INVALID, "invalid aimed enemy cannot fall back to sole legal enemy")
	add(Vector2i(5, 6), "stake")
	check(game.attack_targets.resolve_release(0, Vector2i(5, 6), true) == INVALID, "aimed stake cannot fall back")
	fresh(["spear"]);add(Vector2i(4, 4));add(Vector2i(4, 5), "stake");add(Vector2i(3, 6))
	state = game.attack_targets.state(0)
	check(Vector2i(4, 4) not in state.target_cells and Vector2i(4, 4) not in state.range_cells and Vector2i(5, 5) not in state.range_cells, "spear blockers and orthogonal geometry")
	fresh(["shock"]);add(Vector2i(5, 5));state = game.attack_targets.state(0)
	check(Vector2i(5, 5) in state.target_cells and Vector2i(4, 4) in state.range_cells and Vector2i(6, 5) not in state.range_cells, "shock uses Manhattan radius two, including adjacent diagonals")
	fresh(["cannon"]);add(Vector2i(4, 5), "stake");add(Vector2i(4, 3));add(Vector2i(4, 1));state = game.attack_targets.state(0)
	check(state.target_cells == [Vector2i(4, 3)] and Vector2i(4, 4) in state.range_cells and Vector2i(4, 1) not in state.range_cells, "cannon counts exactly one screen and stops after next occupied cell")
	fresh(["retreat_strike"]);add(Vector2i(4, 5));add(Vector2i(4, 7), "stake")
	check(game.attack_targets.state(0).actions.is_empty(), "retreat-strike blocked reverse square cannot auto-play")
	fresh(["knight_assault"]);add(Vector2i(5, 4));add(Vector2i(4, 5), "stake")
	check(game.attack_targets.state(0).actions.is_empty(), "knight attack respects blocked leg")
	fresh(["chain_assault"]);add(Vector2i(5, 5));add(Vector2i(3, 5));state = game.attack_targets.state(0)
	check(state.mode == "single" and state.actions.size() == 2 and state.auto_target == INVALID, "3x3 chain assault remains single target")

func check_aoe_and_directions():
	for id in ["sweep", "blood_break"]:
		fresh([id]);add(Vector2i(4, 5), "stake")
		check(game.attack_targets.state(0).actions.is_empty(), "stakes do not enable self AoE " + id)
		add(Vector2i(5, 6));add(Vector2i(3, 6))
		var state: Dictionary = game.attack_targets.state(0)
		check(state.mode == "self_aoe" and state.actions.size() == 1 and state.auto_target == game.player and state.target_cells == [game.player], "self AoE uses one player anchor " + id)
		check(state.enemy_cells.size() == 2 and Vector2i(4, 5) not in state.enemy_cells, "self AoE emphasizes enemies rather than stakes " + id)
		if id == "blood_break": check(Vector2i(4, 4) in state.range_cells and Vector2i(5, 5) not in state.range_cells, "blood break is four length-two rays")
	fresh(["blood_edge"]);add(Vector2i(4, 5), "stake");add(Vector2i(4, 4));add(Vector2i(4, 3))
	var state: Dictionary = game.attack_targets.state(0)
	check(state.mode == "direction" and state.actions.size() == 1 and state.target_cells.size() == 3 and state.enemy_cells.size() == 2, "blood edge groups three anchors and multiple enemies into one direction")
	check(state.auto_target == Vector2i(4, 5) and Vector2i(4, 5) in state.range_cells, "blood edge may choose empty or stake direction anchor and pierces blockers")
	check(game.attack_targets.resolve_release(0, Vector2i(5, 6), true) == INVALID, "explicit empty wrong direction never redirects")
	add(Vector2i(6, 6));state = game.attack_targets.state(0)
	check(state.actions.size() == 2 and state.auto_target == INVALID, "two blood directions are ambiguous even with three victims")
	check(game.attack_targets.resolve_release(0, Vector2i(4, 4), true) == Vector2i(4, 4), "explicit blood direction preserved")
	fresh(["airdrop"]);var target = Vector2i(0, 9)
	check(game.can_commit_card(0, target) and game.board_info.preview(0, target).affected.is_empty(), "airdrop landing with no victims remains legal")
	check(game.attack_targets.resolve_release(0, target, true) == target and game.attack_targets.resolve_release(0, INVALID, false) == INVALID, "airdrop always requires explicit empty landing")
	add(target)
	check(game.attack_targets.resolve_release(0, target, true) == INVALID and game.attack_targets.resolve_release(0, game.player, true) == INVALID, "airdrop cannot land on enemy or self")
	fresh(["airdrop"]);game.enemies = []
	for y in 10:
		for x in 9:
			var cell = Vector2i(x, y)
			if cell != game.player and cell != target: add(cell, "stake")
	state = game.attack_targets.state(0)
	check(state.actions.size() == 1 and state.auto_target == INVALID and game.attack_targets.resolve_release(0, INVALID, false) == INVALID, "even the sole empty airdrop landing is never auto-selected")

func check_pure_gates():
	for gate in ["energy", "input_lock", "navigation_lock", "recovery", "screen", "phase", "picker", "presentation", "encounter"]:
		fresh();add(Vector2i(4, 5))
		match gate:
			"energy": game.energy = 0
			"input_lock", "navigation_lock": game.set(gate, 1.0)
			"recovery": game.airdrop_recovery_turn = game.turn
			"screen": game.screen = "home"
			"phase": game.phase = "discard"
			"picker": game.card_picker.open("view", "Cards", [0], Callable(), Callable())
			"presentation": game.presentation.start("victory")
			"encounter": game.encounter_info_open = true
		var before = pack()
		check(game.attack_targets.state(0).actions.is_empty() and game.attack_targets.resolve_release(0, Vector2i(4, 5), true) == INVALID, "pure helper gate " + gate)
		check(pack() == before, "gate evaluation does not mutate " + gate)
	fresh(["cannon_shot"]);add(Vector2i(4, 5), "stake");add(Vector2i(4, 3));game.player_skill = "artillery";game.artillery_mode = "march";game.energy = 1
	check(game.attack_targets.state(0).actions.is_empty(), "current march cost enforced")
	game.artillery_mode = "attack"
	check(game.attack_targets.state(0).actions.size() == 1, "current attack stance cost recomputed")
	fresh(["blood_edge"]);add(Vector2i(4, 5));game.lives = 1;game.route.state.treasure_id = "life_talisman"
	var rescue_before = pack()
	check(game.treasures.rescue_ready() and game.attack_targets.state(0).actions.size() == 1, "ready talisman does not change target eligibility")
	check(pack() == rescue_before, "target query never spends talisman rescue")
	for id in ["blood_edge", "blood_break", "last_stand", "airdrop", "pierce"]:
		fresh([id]);var victim = add(Vector2i(4, 5));victim.unyielding = true;game.lives = 1
		var before = pack()
		for iteration in 12:
			game.attack_targets.state(0)
			game.attack_targets.resolve_release(0, Vector2i(4, 5), true)
		check(pack() == before, "repeated preview preserves life/RNG/history/unyielding " + id)
		check(not game.attack_targets.state(0).actions.is_empty(), "self-defeat and delayed effects are not eligibility filters " + id)
	fresh();add(Vector2i(4, 5));add(Vector2i(5, 6))
	game.tutorial.game = game;game.tutorial.active = true;game.tutorial._steps = [{"action": "play", "card": "sword", "target": Vector2i(5, 6), "hint": "Target"}];game.tutorial.step_index = 0
	var before = pack();var state: Dictionary = game.attack_targets.state(0)
	check(state.target_cells == [Vector2i(5, 6)] and state.range_cells == [Vector2i(5, 6)] and state.auto_target == Vector2i(5, 6), "tutorial exact allowed target filters options and range")
	check(game.attack_targets.resolve_release(0, Vector2i(4, 5), true) == INVALID and pack() == before, "tutorial rejection never captures state or rewrites notice")
	game.tutorial._steps[0].action = "select"
	check(game.attack_targets.state(0).actions.is_empty(), "select-only tutorial step never offers play")
	game.tutorial.stop()

func check_real_releases():
	for size in [Vector2(1280, 940), Vector2(390, 844), Vector2(360, 640), Vector2(844, 390)]:
		for kind in ["mouse", "touch"]:
			for board_drop in [false, true]:
				fresh(["sword"], size);var victim = add(Vector2i(4, 5));var uid: int = game.hand_ids[0]
				var destination: Vector2 = game.cell_pos(Vector2i(0, 9)) if board_drop else upward()
				begin(0, kind);motion(destination, kind)
				var preview_before = pack()
				check(game.gesture.valid_target() and game.gesture.preview_target() == victim.pos, "generic release preview resolves actual unique victim " + str(size) + kind)
				check(pack() == preview_before, "gesture auto-target preview remains read-only")
				button(destination, false, kind)
				check(not game.hand_ids.has(uid) and victim.hp == 4 and game.energy == 9 and game.history.entries.size() == 1, "unique attack release commits exactly once " + str(size) + kind)
				var after = pack();button(destination, false, kind)
				check(pack() == after, "duplicate release cannot replay attack")
			for count in [0, 2]:
				fresh(["sword"], size)
				if count == 2: add(Vector2i(4, 5));add(Vector2i(5, 6))
				var before = pack();drop(upward(), kind)
				check(pack() == before, "generic release with zero or multiple victims is inert " + str(count))
			fresh(["sword"], size);var first = add(Vector2i(4, 5));var other = add(Vector2i(5, 6))
			drop(game.cell_pos(other.pos), kind)
			check(first.hp == 5 and other.hp == 4 and game.hand.is_empty(), "explicit target works among multiple victims")
			fresh(["sword"], size);add(Vector2i(4, 5));var invalid = add(Vector2i(6, 6));var before = pack()
			drop(game.cell_pos(invalid.pos), kind)
			check(pack() == before, "explicit invalid enemy does not fall back on release")
			for id in ["sweep", "blood_break", "blood_edge"]:
				fresh([id], size);first = add(Vector2i(4, 5));other = add(Vector2i(5, 5) if id == "sweep" else Vector2i(4, 4))
				drop(upward(), kind)
				check(game.hand.is_empty() and first.hp < 5 and other.hp < 5 and game.history.entries.size() == 1, "unambiguous multi-victim action releases " + id)
			fresh(["blood_edge"], size);add(Vector2i(4, 5));add(Vector2i(6, 6));before = pack();drop(upward(), kind)
			check(pack() == before, "ambiguous blood directions need explicit selection")
			first = game.enemies[1];other = game.enemies[2];drop(game.cell_pos(Vector2i(4, 4)), kind)
			check(first.hp == 3 and other.hp == 5 and game.hand.is_empty(), "explicit blood direction affects only that ray")
			fresh(["blood_edge"], size);add(Vector2i(4, 5));before = pack();drop(game.cell_pos(Vector2i(5, 6)), kind)
			check(pack() == before, "aimed empty invalid blood direction never redirects")
			fresh(["blood_edge"], size);add(Vector2i(4, 5));add(Vector2i(6, 5));before = pack();drop(game.cell_pos(Vector2i(6, 5)), kind)
			check(pack() == before, "aimed invalid diagonal blood victim never redirects")
			fresh(["airdrop"], size);before = pack();drop(upward(), kind)
			check(pack() == before, "airdrop upward release never chooses landing")
			drop(game.cell_pos(Vector2i(0, 9)), kind)
			check(game.player == Vector2i(0, 9) and game.lives == 3 and game.hand.is_empty(), "airdrop explicit empty landing preserves existing effect")
			for id in ["sweep", "blood_break"]:
				fresh([id], size);add(Vector2i(4, 5), "stake");before = pack();drop(upward(), kind)
				check(pack() == before, "no-enemy self AoE release remains inert " + id)

func check_interruption_and_identity():
	for kind in ["mouse", "touch"]:
		for mutation in ["energy", "input_lock", "navigation_lock", "recovery", "phase", "turn", "removed", "replaced", "changed", "picker", "presentation", "encounter", "screen"]:
			fresh();add(Vector2i(4, 5));begin(0, kind);var destination = upward();motion(destination, kind)
			match mutation:
				"energy": game.energy = 0
				"input_lock", "navigation_lock": game.set(mutation, 1.0)
				"recovery": game.airdrop_recovery_turn = game.turn
				"phase": game.phase = "discard"
				"turn": game.turn += 1
				"removed": game.hand.remove_at(0);game.hand_ids.remove_at(0)
				"replaced": game.hand_ids[0] = game.next_card_uid;game.next_card_uid += 1
				"changed": game.hand[0] = "spear"
				"picker": game.card_picker.open("view", "Cards", [0], Callable(), Callable())
				"presentation": game.presentation.start("victory")
				"encounter": game.encounter_info_open = true
				"screen": game.screen = "home"
			var before = pack();button(destination, false, kind)
			check(pack() == before, "release revalidates current state " + mutation + kind)
		fresh(["cannon_shot"]);add(Vector2i(4, 5), "stake");add(Vector2i(4, 3));game.player_skill = "artillery";game.artillery_mode = "attack";game.energy = 1
		begin(0, kind);var stance_destination = upward();motion(stance_destination, kind);game.artillery_mode = "march"
		var stance_before = pack();button(stance_destination, false, kind)
		check(pack() == stance_before, "release revalidates increased stance-dependent cost")
		fresh(["sword", "sword"]);var victim = add(Vector2i(4, 5));var chosen_uid: int = game.hand_ids[1]
		begin(1, kind);game.hand.remove_at(0);game.hand_ids.remove_at(0);game.handui.sync();var destination = upward();motion(destination, kind);button(destination, false, kind)
		check(not game.hand_ids.has(chosen_uid) and victim.hp == 4 and game.energy == 9, "same physical UID survives reindex " + kind)
		for cancellation in ["back", "micro", "cancel", "focus", "web_cancel", "side_disabled", "side_enabled"]:
			fresh();add(Vector2i(4, 5))
			if cancellation == "side_disabled": game.energy = 1
			var before = pack();var source = begin(0, kind);destination = upward()
			match cancellation:
				"back": motion(destination, kind);destination = source
				"micro": destination = source + Vector2(0, -18)
				"side_disabled", "side_enabled": destination = game.pass_drop_rect().get_center()
			motion(destination, kind)
			match cancellation:
				"cancel":
					if kind == "touch": button(destination, false, kind, 0, true)
					else: game.gesture.release(destination, true)
				"focus": game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
				"web_cancel": game.on_web_input_cancel([])
			button(destination, false, kind)
			if cancellation == "side_enabled":
				check(game.energy == 7 and game.hand.size() == 1 and game.hand[0] == "breath" and game.enemies[1].hp == 5, "side zone takes precedence over attack shortcut")
			else: check(pack() == before, "canceled/back/micro/disabled-side release is inert " + cancellation + kind)
	fresh(["treasure_king_step"]);var before = pack();drop(upward())
	check(pack() == before, "temporary movement has no attack auto-use shortcut")

func check_multitouch():
	for ordering in [[0, 1, 2], [2, 0, 1], [1, 2, 0]]:
		fresh();add(Vector2i(4, 5));var before = pack();var source = begin(0, "touch");var destination = upward()
		motion(destination, "touch", 0);button(source, true, "touch", 1)
		check(not game.gesture.active and game.battle_multitouch, "second finger cancels first card drag")
		button(source, true, "touch", 2);motion(destination, "touch", 2)
		check(not game.gesture.active, "third finger cannot restart canceled multitouch drag")
		for finger in ordering: button(destination, false, "touch", finger)
		check(pack() == before and game.battle_touch_contacts.is_empty() and not game.battle_multitouch, "all multitouch releases are consumed in any order")
		drop(destination, "touch")
		check(game.hand.is_empty() and game.energy == 9, "fresh gesture works only after every finger lifted")

func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	game.attack_targets = TARGETING.new(game)
	check_classification_and_all_attacks();check_single_choices_and_geometry();check_aoe_and_directions();check_pure_gates()
	check_real_releases();check_interruption_and_identity();check_multitouch()
	game.free()
	print("ATTACK TARGETING: %d checks; %d failures" % [checks, failures]);quit(1 if failures else 0)
