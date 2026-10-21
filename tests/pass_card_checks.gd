extends SceneTree
# Paid passes discard without playing a card. Generated free cards are hidden
# only for this turn, independently of the basic-movement quota.
# Run with disposable user:// storage, just like the other rule checks.
var game
var checks = 0
var failures = 0

func _initialize(): call_deferred("run")

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("PASS CARD: " + label)
	else: print("PASS ", label)

func settle():
	game.clear_effects()
	game.navigation_lock = 0.0

func fresh(cards: Array = ["sword"], identity: String = "king", energy: int = 5):
	game.player_skill = identity
	game.new_run()
	game.set_process(false)
	game.enemies = []
	game.add_enemy("g", Vector2i(4, 0), 999)
	game.enemies[0].hp = 99;game.enemies[0].max_hp = 99
	game.player = Vector2i(4, 8);game.lives = 4
	game.collection = cards.duplicate()
	game.hand = cards.duplicate();game.hand_ids = []
	game.deck = ["spear", "sword", "diagonal"]
	game.discard = [];game.energy = energy
	game.screen = "game";game.phase = "play"
	game.selected = -1;game.free_selected = false
	game.encounter_info_open = false
	game.sync_hand_ids();game.handui.reset()
	settle();game.history.clear()

func effect_state() -> Dictionary:
	var result = {}
	for key in ["player", "enemies", "lives", "basic_used", "card_move_used", "active_displacements", "shield_charges", "pending_bleeds", "reload_ready", "airdrop_recovery_turn", "artillery_mode", "deploy_draw_used", "tuna_turns", "tuna_active", "collection", "deck", "turn", "phase"]:
		var value = game.get(key)
		result[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	result.rng_state = game.rng.state
	return result

func expect_rejected(index: int, free: bool, label: String):
	var before = game.history.capture()
	var entries = game.history.entries.size()
	var selected = game.selected
	check(not game.can_pass_card(index, free), label + " eligibility is false")
	check(not game.pass_card(index, free), label + " returns false")
	# A rejection may explain itself through notice, but must not change rules,
	# consume a UID, write history, deselect a card, or mutate the log.
	var after = game.history.capture()
	before.erase("notice");after.erase("notice")
	check(after == before and game.history.entries.size() == entries and game.selected == selected, label + " is atomic")

func check_cost_and_no_target():
	fresh(["sword"])
	check(not game.can_commit_card(0, game.player), "fixture has no legal sword target")
	var before = effect_state()
	check(game.can_pass_card(0) and game.pass_card(0), "targeted card can be passed without a target")
	check(game.energy == 4 and game.hand.is_empty() and game.discard == ["sword"], "ordinary pass pays cost and discards one card")
	check(effect_state() == before, "ordinary pass neither attacks, moves, draws, nor advances the turn")
	check(game.history.entries.size() == 1, "one successful pass records exactly one undo entry")
	for mode in ["march", "attack"]:
		fresh(["cannon_shot"], "artillery")
		game.artillery_mode = mode;game.reload_ready = true
		var cost = 2 if mode == "march" else 1
		before = effect_state()
		check(game.card_cost("cannon_shot") == cost and game.pass_card(0), "cannon pass is accepted in " + mode + " stance")
		check(game.energy == 5 - cost and game.discard == ["cannon_shot"], "cannon pass uses current " + mode + " cost")
		check(effect_state() == before, "cannon pass preserves reload and all effects in " + mode)
		fresh(["cannon_shot"], "artillery", 1)
		game.artillery_mode = mode
		if mode == "march": expect_rejected(0, false, "unaffordable marching cannon")
		else: check(game.pass_card(0) and game.energy == 0, "attack stance permits exact-energy cannon pass")
	fresh(["life"]);game.lives = 5
	check(not game.can_commit_card(0, game.player) and game.pass_card(0), "full health blocks healing but not passing life")
	check(game.lives == 5 and game.energy == 3 and game.discard == ["life"], "passing unusable healing does not heal or exhaust")
	fresh(["horse"]);game.card_move_used = true
	before = effect_state()
	check(game.pass_card(0) and game.energy == 4, "used movement-card quota does not block paid pass")
	check(effect_state() == before, "passing movement never changes either movement quota or draws")
	fresh(["deploy"], "artillery");game.artillery_mode = "attack"
	check(not game.can_commit_card(0, game.player) and game.pass_card(0), "already-deployed stance blocks playing deploy but not passing it")
	fresh(["pack"], "artillery", 0)
	check(not game.can_commit_card(0, game.player) and game.pass_card(0) and game.energy == 0, "marching stance blocks playing pack but not its zero-cost pass")

func check_effects_and_recycling():
	for id in ["airdrop", "life", "breath", "deploy", "tuna", "guard", "permanent_stake", "suppress", "reload", "pierce", "fatigue", "pack"]:
		var identity = "artillery" if id in ["deploy", "permanent_stake", "reload", "pack"] else "king"
		fresh([id], identity)
		if id == "pack": game.artillery_mode = "attack"
		game.shield_charges = 1;game.active_displacements = 2
		game.tuna_turns = 2;game.reload_ready = true
		# A neighboring enemy would be affected by many actual card effects.
		game.add_enemy("p", Vector2i(4, 7), 999)
		game.enemies.back().hp = 5;game.enemies.back().max_hp = 5
		var before = effect_state()
		var cost = game.card_cost(id)
		check(game.pass_card(0), id + " pass succeeds")
		check(game.energy == 5 - cost and game.hand.is_empty() and game.discard == [id], id + " pays only its current cost and enters discard")
		check(effect_state() == before, id + " never applies play effects, draws, or changes the permanent deck")
		# Every unused consumable remains recyclable, rather than exhausting.
		if game.is_consumable(id):
			game.deck = [];game.draw_card()
			check(game.hand == [id] and game.discard.is_empty() and game.collection == [id], id + " can be redrawn in the same battle after passing")
	fresh(["airdrop"], "king", 3);game.lives = 1
	check(game.pass_card(0) and game.lives == 1 and game.phase == "play" and game.airdrop_recovery_turn == 0, "passing lethal airdrop neither sacrifices life nor schedules recovery")
	fresh(["breath"], "king", 0)
	check(game.pass_card(0) and game.energy == 0 and game.discard == ["breath"], "zero-cost consumable pass grants no energy and still recycles")
	fresh(["fatigue"], "king", 2)
	check(game.pass_card(0) and game.energy == 0 and game.discard == ["fatigue"], "fatigue pass costs two without refunding previous penalties")
	settle();game.end_turn()
	check(game.energy == 3 and game.hand.is_empty(), "passed fatigue no longer taxes the following turn or causes a redraw")

func check_free_card():
	for identity in ["king", "horse", "artillery"]:
		fresh(["sword"], identity, 0)
		var before = effect_state()
		var uid = game.free_card_uid
		check(game.free_card_available() and game.freecard.visible() and game.can_pass_card(-1, true), identity + " generated free card starts available")
		check(game.pass_card(-1, true), identity + " free pass succeeds at zero energy")
		check(not game.free_card_available() and not game.freecard.visible() and not game.basic_used, identity + " free pass hides the card without consuming basic movement")
		check(effect_state() == before and game.energy == 0 and game.hand == ["sword"] and game.discard.is_empty(), identity + " free pass never changes piles, resources, position or effects")
		expect_rejected(-1, true, identity + " duplicate free pass")
		settle();game.handui.reset()
		check(not game.free_card_available() and not game.freecard.visible(), identity + " redraw cannot regenerate the free card")
		game.end_turn();settle()
		check(game.turn == 2 and game.free_card_available() and game.freecard.visible() and not game.basic_used and game.free_card_uid != uid, identity + " next turn creates a new free card")
		undo_after_effects(game)
		check(game.turn == 1 and not game.free_card_available() and not game.freecard.visible() and not game.basic_used, identity + " undo turn restores the passed free-card state")
		undo_after_effects(game)
		check(game.free_card_available() and game.freecard.visible() and game.free_card_uid == uid and game.energy == 0 and not game.basic_used, identity + " undo free pass restores its original identity and quota")
	fresh(["deploy", "pack"], "artillery")
	check(game.pass_card(-1, true), "artillery free card can be passed before stance changes")
	settle();game.play_card(game.hand.find("deploy"), game.player);settle()
	check(game.artillery_mode == "attack" and not game.free_card_available() and not game.freecard.visible() and not game.basic_used, "deploy does not regenerate a passed free card")
	game.play_card(game.hand.find("pack"), game.player);settle()
	check(game.artillery_mode == "march" and not game.free_card_available() and not game.freecard.visible() and not game.basic_used, "pack does not regenerate a passed free card")
	fresh();game.basic_used = true
	expect_rejected(-1, true, "already-used free move")
	fresh();game.pass_card(-1, true);settle()
	check(game.basic_legal(Vector2i(4, 7)), "passing generated card leaves direct basic movement legal")
	game.basic_move(Vector2i(4, 7))
	check(game.player == Vector2i(4, 7) and game.basic_used and game.hand.size() == 2, "preserved basic-movement quota still moves and draws normally")

func check_rejections():
	fresh(["airdrop"], "king", 2)
	expect_rejected(0, false, "insufficient energy")
	fresh()
	for index in [-2, -1, 1, 99]: expect_rejected(index, false, "invalid hand index " + str(index))
	for blocked_phase in ["discard", "reward", "dead", "win"]:
		fresh();game.phase = blocked_phase
		expect_rejected(0, false, blocked_phase + " hand pass")
		expect_rejected(-1, true, blocked_phase + " free pass")
	for blocked_screen in ["home", "map", "tutorial_pause"]:
		fresh();game.screen = blocked_screen
		expect_rejected(0, false, blocked_screen + " hand pass")
		expect_rejected(-1, true, blocked_screen + " free pass")
	for field in ["input_lock", "navigation_lock"]:
		fresh();game.set(field, 0.3)
		expect_rejected(0, false, field + " hand pass")
		expect_rejected(-1, true, field + " free pass")
	fresh();game.airdrop_recovery_turn = game.turn
	expect_rejected(0, false, "airdrop recovery hand pass")
	expect_rejected(-1, true, "airdrop recovery free pass")
	fresh();game.encounter_info_open = true
	expect_rejected(0, false, "encounter modal hand pass")
	expect_rejected(-1, true, "encounter modal free pass")
	game.start_tutorial(0);settle()
	var step = game.tutorial.step_index
	expect_rejected(0, false, "guided tutorial hand pass")
	expect_rejected(-1, true, "guided tutorial free pass")
	check(game.tutorial.step_index == step and game.tutorial._pending_step < 0, "rejected pass never advances the guided lesson")

func check_identity_and_undo():
	fresh(["sword", "sword", "sword"])
	var ids = game.hand_ids.duplicate()
	var before = game.history.capture()
	check(ids[0] != ids[1] and ids[1] != ids[2] and ids[0] != ids[2], "identical physical copies have distinct UIDs")
	check(game.pass_card(1), "middle duplicate passes successfully")
	check(game.hand == ["sword", "sword"] and game.hand_ids == [ids[0], ids[2]] and game.discard == ["sword"], "pass removes only the selected duplicate UID")
	settle();check(game.pass_card(1), "remaining right duplicate can also pass")
	check(game.hand_ids == [ids[0]] and game.discard == ["sword", "sword"] and game.energy == 3, "repeated passes resolve current indices without substituting duplicate cards")
	undo_after_effects(game)
	check(game.hand_ids == [ids[0], ids[2]] and game.energy == 4 and game.discard == ["sword"], "one undo restores just the second passed copy")
	undo_after_effects(game)
	check(game.history.capture() == before and game.history.entries.is_empty(), "second undo restores exact original piles, UIDs, RNG, cost and effects")
	fresh(["airdrop"])
	before = game.history.capture()
	check(game.pass_card(0), "consumable pass records history")
	undo_after_effects(game)
	check(game.history.capture() == before and game.hand == ["airdrop"] and game.airdrop_recovery_turn == 0, "undo consumable pass restores the copy without generating its effect")

func touch(index: int, position: Vector2, pressed: bool, canceled: bool = false):
	var event = InputEventScreenTouch.new()
	event.index = index;event.position = position;event.pressed = pressed;event.canceled = canceled
	game._input(event)

func touch_drag(index: int, position: Vector2):
	var event = InputEventScreenDrag.new()
	event.index = index;event.position = position
	game._input(event)

func check_gestures():
	for size in [Vector2(1280, 940), Vector2(390, 844), Vector2(844, 390), Vector2(360, 640)]:
		fresh(["sword", "sword"]);game.configure_layout(size)
		var start: Vector2 = game.handui.exposed_point(0)
		var drop: Vector2 = game.pass_drop_rect().get_center()
		var ids = game.hand_ids.duplicate()
		check(game.handui.hit_index(start) == 0 and not game.BOARD_RECT.intersects(game.pass_drop_rect()), "side target is separate from board and source is hittable at " + str(size))
		check(game.gesture.press(start, "touch"), "pass gesture presses the actual hand at " + str(size))
		game.gesture.motion(drop)
		check(game.gesture.dragging and not game.gesture.valid_target(), "side pass is not a board-use preview at " + str(size))
		game.gesture.release(drop)
		check(game.hand_ids == [ids[1]] and game.discard == ["sword"] and game.energy == 4 and game.history.entries.size() == 1, "press-motion-release passes exactly the bound copy at " + str(size))
		game.gesture.release(drop)
		check(game.hand_ids == [ids[1]] and game.discard.size() == 1 and game.energy == 4 and game.history.entries.size() == 1, "duplicate release cannot commit twice at " + str(size))
		fresh();game.configure_layout(size)
		start = game.handui.exposed_point(0);drop = game.pass_drop_rect().get_center()
		var before = game.history.capture()
		game.gesture.press(start, "touch");game.gesture.motion(drop);game.gesture.release(drop, true)
		check(game.history.capture() == before and game.history.entries.is_empty() and not game.gesture.active, "canceled side release preserves the entire state at " + str(size))
		game.gesture.press(start, "touch");game.gesture.motion(drop);game.gesture.motion(start);game.gesture.release(start)
		check(game.history.capture() == before and game.selected == -1, "retreating from the pass zone cancels rather than passes or selects at " + str(size))
		game.gesture.press(game.handui.free_exposed_point(), "touch");game.gesture.motion(drop);game.gesture.release(drop)
		check(not game.free_card_available() and not game.basic_used and game.hand == ["sword"] and game.energy == 5 and game.discard.is_empty(), "free-card side gesture preserves quota and piles at " + str(size))
	# Actual input dispatch, including multi-touch ownership and synthetic mouse.
	fresh(["sword", "sword"]);game.configure_layout(Vector2(390, 844))
	var start: Vector2 = game.handui.exposed_point(0)
	var drop: Vector2 = game.pass_drop_rect().get_center()
	var ids = game.hand_ids.duplicate()
	touch(0, start, true);touch_drag(0, drop)
	touch(1, game.handui.exposed_point(1), true);touch_drag(1, drop);touch(1, drop, false)
	check(game.active_touch == 0 and game.gesture.uid == ids[0] and game.hand_ids == ids and game.history.entries.is_empty(), "secondary touch cannot replace or release the first touch's card")
	touch(0, drop, false);touch(0, drop, false)
	check(game.active_touch == -1 and game.hand_ids == [ids[1]] and game.energy == 4 and game.history.entries.size() == 1, "primary touch commits once after secondary touch was ignored")
	var mouse = InputEventMouseButton.new()
	mouse.device = -1;mouse.button_index = MOUSE_BUTTON_LEFT;mouse.position = drop
	mouse.pressed = true;game._gui_input(mouse);mouse.pressed = false;game._gui_input(mouse)
	check(game.hand_ids == [ids[1]] and game.history.entries.size() == 1 and game.energy == 4, "touch-generated synthetic mouse cannot repeat a side pass")
	fresh();game.configure_layout(Vector2(390, 844));start = game.handui.exposed_point(0);drop = game.pass_drop_rect().get_center()
	var before = game.history.capture()
	touch(0, start, true);touch_drag(0, drop);touch(0, drop, false, true);touch(0, drop, false)
	check(game.history.capture() == before and game.history.entries.is_empty() and game.active_touch == -1 and not game.gesture.active, "canceled OS touch followed by late release never passes")
	# Gesture identity survives a hand reindex, but never a removed physical copy.
	fresh(["sword", "sword", "sword"]);game.configure_layout(Vector2(390, 844))
	ids = game.hand_ids.duplicate();drop = game.pass_drop_rect().get_center()
	game.gesture.press(game.handui.exposed_point(1), "touch");game.gesture.motion(drop)
	game.hand.remove_at(0);game.hand_ids.remove_at(0);game.handui.sync()
	game.gesture.release(drop)
	check(game.hand_ids == [ids[2]] and game.discard == ["sword"] and game.energy == 4, "reindexed duplicate gesture follows its UID rather than original array index")
	fresh(["sword", "sword"]);game.configure_layout(Vector2(390, 844))
	drop = game.pass_drop_rect().get_center()
	game.gesture.press(game.handui.exposed_point(0), "touch");game.gesture.motion(drop)
	game.hand.remove_at(0);game.hand_ids.remove_at(0);game.handui.sync()
	before = game.history.capture();game.gesture.release(drop)
	check(game.history.capture() == before and game.history.entries.is_empty(), "stale removed-card gesture cannot pass its identical replacement")
	fresh();game.configure_layout(Vector2(390, 844));drop = game.pass_drop_rect().get_center()
	game.gesture.press(game.handui.free_exposed_point(), "touch");game.gesture.motion(drop)
	game.refresh_free_card();before = game.history.capture();game.gesture.release(drop)
	check(game.history.capture() == before and game.free_card_available() and game.history.entries.is_empty(), "stale free-card gesture cannot pass a newly issued identity")
	fresh(["airdrop"], "king", 2);game.configure_layout(Vector2(390, 844));drop = game.pass_drop_rect().get_center()
	before = game.history.capture()
	game.gesture.press(game.handui.exposed_point(0), "touch");game.gesture.motion(drop);game.gesture.release(drop)
	check(game.history.capture() == before and game.history.entries.is_empty(), "unaffordable side drop is atomic and never falls back to card play")

func overlap_source() -> Vector2:
	var area: Rect2 = game.pass_drop_rect()
	for x in range(int(area.position.x + 3), int(area.end.x - 32), 3):
		for y in range(int(area.position.y + 20), int(area.end.y - 20), 3):
			var p = Vector2(x, y)
			if game.handui.hit_index(p) >= 0: return p
	return Vector2.INF

func check_side_drop_intent():
	for size in [Vector2(390, 844), Vector2(844, 390), Vector2(360, 640), Vector2(320, 480)]:
		fresh(["sword", "sword", "sword", "sword", "sword", "sword"])
		game.configure_layout(size)
		var area: Rect2 = game.pass_drop_rect()
		check(Rect2(Vector2.ZERO, game.ui_size).encloses(area) and not area.intersects(game.BOARD_RECT) and not area.intersects(game.END_TURN_RECT), "side target stays on screen and clear of board/end-turn at " + str(size))
		var start = overlap_source()
		check(start.is_finite(), "fixture includes a hand card underneath the transient pass zone at " + str(size))
		if not start.is_finite(): continue
		var before = game.history.capture()
		game.gesture.press(start, "touch");game.gesture.motion(start + Vector2(0, -13));game.gesture.release(start + Vector2(0, -13))
		check(game.history.capture() == before and game.history.entries.is_empty(), "short upward drag from inside pass zone never spends a card at " + str(size))
		game.gesture.press(start, "touch");game.gesture.motion(start + Vector2(-13, 0));game.gesture.release(start + Vector2(-13, 0))
		check(game.history.capture() == before and game.history.entries.is_empty(), "short leftward drag cannot become a side pass at " + str(size))
		game.gesture.press(start, "touch");game.gesture.motion(start + Vector2(13, 0));game.gesture.release(start + Vector2(13, 0))
		check(game.history.capture() == before and game.history.entries.is_empty(), "minor rightward movement inside pass zone does not trigger pass at " + str(size))
		game.gesture.press(start, "touch");game.gesture.motion(start + Vector2(32, 0));game.gesture.release(start + Vector2(32, 0))
		check(game.hand.size() == 5 and game.energy == 4 and game.discard == ["sword"] and game.history.entries.size() == 1, "deliberate rightward drag can pass a card already under the zone at " + str(size))
		undo_after_effects(game);start = overlap_source()
		game.gesture.press(start, "touch")
		game.gesture.motion(Vector2(area.position.x - 20, start.y));game.gesture.motion(start);game.gesture.release(start)
		check(game.hand.size() == 5 and game.energy == 4 and game.discard == ["sword"], "leaving then deliberately re-entering the zone can pass its underlying card at " + str(size))

func mouse_click(position: Vector2):
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT;event.position = position;event.device = 0
	event.pressed = true;game._gui_input(event)
	event.pressed = false;game._gui_input(event)

func check_desktop_button():
	fresh();game.configure_layout(Vector2(1280, 940))
	var button: Rect2 = game.pass_button_rect()
	for other in [game.END_TURN_RECT, game.USE_RECT, game.full_hand_area(), game.BOARD_RECT, game.UNDO_RECT, game.RESTART_RECT, game.SOUND_RECT, game.home_rect(), game.debug_skip_rect()]:
		check(not button.intersects(other), "desktop pass button does not overlap another actionable region " + str(other))
	var before = game.history.capture()
	mouse_click(button.get_center())
	check(game.history.capture() == before and game.history.entries.is_empty(), "desktop pass button with no selection does not act or end turn")
	game.select_card(0);mouse_click(button.get_center())
	check(game.hand.is_empty() and game.discard == ["sword"] and game.energy == 4 and game.turn == 1, "desktop button passes selected attack instead of using it or ending turn")
	fresh(["breath"]);game.configure_layout(Vector2(1280, 940));game.select_card(0);mouse_click(button.get_center())
	check(game.hand.is_empty() and game.discard == ["breath"] and game.energy == 5 and game.turn == 1, "desktop button passes untargeted consumable instead of triggering use button")
	fresh(["airdrop"], "king", 2);game.configure_layout(Vector2(1280, 940));game.select_card(0)
	before = game.history.capture();mouse_click(button.get_center())
	check(game.history.capture() == before and game.selected == 0 and game.history.entries.is_empty(), "unaffordable desktop pass retains selection and every rule state")
	fresh();game.configure_layout(Vector2(1280, 940));game.select_free_card();mouse_click(button.get_center())
	check(not game.free_card_available() and not game.basic_used and game.energy == 5 and game.hand == ["sword"] and game.turn == 1, "desktop free pass has no effect on movement quota or turn")
	for size in [Vector2(390, 844), Vector2(844, 390), Vector2(320, 480)]:
		game.configure_layout(size)
		check(game.pass_button_rect().size == Vector2.ZERO, "mobile layout keeps desktop-only pass button inactive at " + str(size))

func check_pass_persistence():
	for identity in ["king", "horse", "artillery"]:
		game.player_skill = identity;game.new_expedition();game.route.enter(0);settle()
		game.hand = ["airdrop", "sword"];game.hand_ids = [];game.energy = 5
		game.sync_hand_ids();game.handui.reset()
		var permanent = game.collection.duplicate()
		check(game.pass_card(0) and game.pass_card(-1, true), identity + " paid and free pass can be saved together")
		var before = game.history.capture()
		check(game.route.valid_snapshot(game.route.state, before, game.screen), identity + " uid-zero passed free card remains a valid v5 snapshot")
		game.route.save()
		check(game.route.save_error == OK, identity + " writes passed-card state to disposable save")
		game.free();game = load("res://main.tscn").instantiate();root.add_child(game);game.settings.set_debug_mode(true);game.set_process(false)
		check(game.route.resume() and game.history.capture() == before, identity + " new scene restores paid/free pass state exactly")
		check(game.free_card_uid == 0 and not game.free_card_available() and not game.freecard.visible() and not game.basic_used and game.discard == ["airdrop"] and game.collection == permanent, identity + " reload neither reissues the passed free card nor exhausts its consumable")
		for enemy in game.enemies: enemy.cd = 999;enemy.period = 999
		game.end_turn();settle()
		check(game.free_card_available() and game.free_card_uid > 0 and not game.basic_used, identity + " turn after resume reissues a fresh generated free card")

func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.settings.set_debug_mode(true)
	check(game.has_method("can_pass_card") and game.has_method("pass_card"), "main exposes pass-card eligibility and commit APIs")
	if failures == 0:
		check_cost_and_no_target()
		check_effects_and_recycling()
		check_free_card()
		check_rejections()
		check_identity_and_undo()
		check_gestures()
		check_side_drop_intent()
		check_desktop_button()
		check_pass_persistence()
	print("PASS CARD RESULT ", checks - failures, " passed, ", failures, " failed")
	game.free();quit(1 if failures else 0)

# These rules tests model the completed-animation boundary before user input.
func undo_after_effects(owner) -> bool:
	owner.input_lock = 0;owner.navigation_lock = 0;owner.presentation.clear()
	return owner.undo_action()
