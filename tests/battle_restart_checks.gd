extends SceneTree
# Exercise the real route/save/UI entry points. Run with disposable XDG dirs,
# as scripts/verify.sh does: compatibility cases intentionally edit the save.
const T = preload("res://../tests/route_test_helpers.gd")
const PRESENTATION_FIELDS = ["logs", "notice", "initial_threat"]
var game
var checks = 0
var failures = 0

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("BATTLE RESTART: " + label)
func create_game():
	if is_instance_valid(game): game.free()
	game = load("res://main.tscn").instantiate()
	root.add_child(game);game.set_process(false)
	game.settings.set_debug_mode(false)
func ready_action():
	game.clear_effects();game.presentation.clear();game.card_picker.close()
	game.input_lock = 0.0;game.navigation_lock = 0.0;game.encounter_info_open = false
	game.cancel_gesture()
func battle_state() -> Dictionary:
	var result: Dictionary = game.history.capture()
	# Display feedback/coordinates may be refreshed without changing the battle.
	for key in PRESENTATION_FIELDS: result.erase(key)
	for enemy in result.enemies: enemy.erase("visual")
	return result
func save_text() -> String:
	return FileAccess.get_file_as_string(game.route.SAVE) if FileAccess.file_exists(game.route.SAVE) else ""
func saved_config() -> ConfigFile:
	var config = ConfigFile.new()
	check(config.load(game.route.SAVE) == OK, "route save exists and parses")
	return config
func immutable_state() -> Dictionary:
	return {"battle": battle_state(), "route": game.route.state.duplicate(true), "screen": game.screen,
		"budget": game.normal_undos_remaining, "history": game.history.entries.duplicate(true), "save": save_text()}
func fresh_route(role: String = "king", chapter: int = 1, treasure: String = "", prepared: bool = true, later: bool = true):
	game.player_skill = role;game.seed_value = 151100 + chapter
	game.new_expedition()
	if chapter == 2: game.route.generate(game.seed_value, 2)
	game.collection = ["sword_plus", "life", "breath", "guard", "spear_plus", "sword"]
	game.lives = 7 if treasure == "longevity_seal" else 2
	game.normal_undos_remaining = 2
	game.route.state.prepared = prepared
	game.route.state.reward_debt = 2
	game.route.state.pending_homework = ["spear_plus"]
	if not treasure.is_empty():
		game.route.state.treasure_id = treasure;game.route.state.treasure_claimed = true
	var target: int = T.kind_id(game.route, "elite") if later else 0
	T.before(game.route, target);game.route.enter(target);ready_action()
	check(game.screen == "game" and game.phase == "play", "fixture enters a real generated combat node")
	check(game.battle_restart.can_restart(), "completed battle entry has a restart checkpoint")
	check(game.hand.size() == (2 if prepared else 0), "entry includes prepared draws exactly once")
	check(not game.route.state.prepared, "prepared route benefit is already spent at entry")
func mutate_battle():
	game.history.record("before restart")
	game.player = Vector2i(3, 8);game.turn = 4;game.lives = 1;game.energy = 0
	game.deck.reverse();game.hand = ["sword"];game.hand_ids = [game.next_card_uid];game.next_card_uid += 1
	game.discard = ["spear_plus"];game.free_card_uid = 0;game.basic_used = true;game.card_move_used = true
	game.active_displacements = 2;game.shield_charges = 1;game.reload_ready = true
	game.artillery_mode = "attack";game.deploy_draw_used = true;game.tuna_turns = 2;game.tuna_active = true
	game.airdrop_recovery_turn = 5;game.reinforcement_turns = 3;game.reinforcement_pending = 1
	game.enemies[0].hp = maxi(1, int(game.enemies[0].hp) - 1)
	game.enemies[0].cd += 3;game.enemies[0].stun = 1
	game.pending_bleeds = [{"enemy_uid": game.enemies[0].uid, "amount": 1}]
	game.encounter_state.phases = int(game.encounter_state.get("phases", 0)) + 2
	game.treasure_battle.talisman_used = true;game.treasure_battle.tiger_moves = 2
	game.treasure_battle.spring_kills = 2;game.treasure_battle.trigger_serial += 2
	game.rng.randi();game.rng.randi()
	game.selected = 0;game.free_selected = true;game.hand_drawer = true;game.hand_page = 2
	game.normal_undos_remaining = 1
func check_exact_restart():
	for role in ["king", "horse", "artillery"]:
		fresh_route(role)
		var start = battle_state();var route = game.route.state.duplicate(true)
		var checkpoint = game.battle_restart.snapshot.duplicate(true)
		mutate_battle()
		check(game.battle_restart.snapshot == checkpoint, role + " live arrays cannot mutate the entry checkpoint")
		check(game.restart_battle(), role + " restarts the current battle")
		check(battle_state() == start, role + " restores exact health, cards/UIDs/order, RNG, enemy timers and effects")
		check(game.route.state == route, role + " preserves chapter, map, visited nodes, debt, homework and pending node")
		check(game.collection == start.collection and game.player_skill == role, role + " preserves upgraded permanent deck and role")
		check(game.history.entries.is_empty() and game.history.oldest_turn == 1, role + " clears undo history")
		check(game.normal_undos_remaining == 1, role + " does not replenish normal undo allowance")
		check(game.selected == -1 and not game.free_selected and not game.hand_drawer and game.hand_page == 0, role + " clears hand selection and drawer state")
		check(game.active_touch == -1 and not game.gesture.active, role + " cancels pointer state")
		var config = saved_config()
		check(config.get_value("run", "normal_undos_remaining", -1) == 1, role + " immediately persists spent undo allowance")
		check(config.get_value("run", "battle", {}).get("lives", -1) == 2 and config.get_value("run", "battle", {}).get("turn", -1) == 1, role + " immediately persists restarted battle")
		check(not config.get_value("run", "battle_start", {}).is_empty(), role + " persists the independent entry checkpoint")
		var after = immutable_state()
		check(not game.restart_battle() and not game.battle_restart.restart(), role + " duplicate direct restart is locked")
		game.handle_click(game.RESTART_RECT.get_center())
		check(immutable_state() == after, role + " duplicate button click cannot reroll or clear progress")
		ready_action();check(not game.undo_action() and game.normal_undos_remaining == 1, role + " cannot undo back into abandoned attempt")
		game.energy = 0
		game.handle_click(game.RESTART_RECT.get_center())
		check(battle_state() == start and game.screen == "game" and game.route.state == route, role + " visible battle button restarts combat, not the expedition")
		ready_action();game.phase = "discard";game.hand.append("sword");game.sync_hand_ids()
		check(game.restart_battle() and battle_state() == start, role + " discard phase may restart")
		ready_action();game.phase = "dead";game.lives = 0
		check(game.restart_battle() and battle_state() == start, role + " settled defeat restores entry health, not role maximum")
		ready_action();game.history.record("new attempt");game.energy = 0
		check(game.undo_action() and game.normal_undos_remaining == 0, role + " new attempt spends only remaining undo")
		ready_action();check(game.restart_battle() and game.normal_undos_remaining == 0, role + " exhausted undo allowance stays exhausted")
func check_rng_replay():
	fresh_route("king", 1, "", false)
	var start = battle_state()
	for i in 3: game.draw_card()
	ready_action();game.end_turn();ready_action()
	var first = battle_state()
	check(first != start, "draws and a real enemy phase change the battle")
	check(game.restart_battle(), "deterministic replay can restart")
	ready_action()
	for i in 3: game.draw_card()
	ready_action();game.end_turn();ready_action()
	check(battle_state() == first, "same draws and enemy phase reproduce card UIDs, RNG and enemy outcomes exactly")
	# Consume an actual single-use card, rather than only editing its flags.
	fresh_route("king", 1, "", false)
	start = battle_state()
	while not game.deck.is_empty(): game.draw_card();ready_action()
	var index: int = game.hand.find("breath")
	check(index >= 0, "consumable fixture draws breath")
	game.play_card(index, game.player);ready_action()
	check("breath" not in game.hand and "breath" not in game.discard and game.collection.has("breath"), "real consumable leaves the attempt but remains permanent")
	check(game.restart_battle() and battle_state() == start, "restart restores the consumed physical card to its entry pile")
func assert_blocked(label: String, button: bool = true):
	var before = immutable_state()
	check(not game.battle_restart.can_restart(), label + " reports unavailable")
	check(not game.restart_battle() and not game.battle_restart.restart(), label + " blocks wrapper and direct entry")
	if button: game.handle_click(game.RESTART_RECT.get_center())
	check(immutable_state() == before, label + " cannot mutate battle, route, history, RNG, budget or save")
func check_guards():
	fresh_route();game.history.record("retained history")
	game.input_lock = 1;assert_blocked("animation input lock");ready_action()
	game.navigation_lock = 1;assert_blocked("navigation lock");ready_action()
	game.effect("draw", Vector2.ZERO, Vector2.ZERO, 0.5);game.input_lock = 0
	assert_blocked("pending effects even without input lock");ready_action()
	game.presentation.victory();assert_blocked("victory presentation");ready_action()
	game.card_picker.active = true;assert_blocked("card picker overlay");ready_action()
	game.encounter_info_open = true;assert_blocked("encounter information overlay");ready_action()
	for phase in ["enemy", "reward", "win"]:
		game.phase = phase;assert_blocked(phase + " phase", phase != "win")
	game.phase = "play"
	game.end_turn()
	check(game.input_lock > 0, "real enemy phase holds the animation lock")
	assert_blocked("real enemy phase animation");ready_action()
	game.route.state.victory_recorded = true;assert_blocked("already settled route victory")
	game.route.state.victory_recorded = false
	game.screen = "map";assert_blocked("outside the battle screen", false);game.screen = "game"
	game.settings.set_debug_mode(true);game.input_lock = 1
	assert_blocked("debug mode cannot bypass restart safety");ready_action();game.settings.set_debug_mode(false)
func check_persistence():
	for treasure in ["life_talisman", "longevity_seal"]:
		fresh_route("king", 2, treasure)
		var start = battle_state();var route = game.route.state.duplicate(true)
		check(start.lives == (7 if treasure == "longevity_seal" else 2), treasure + " fixture has exact carried health")
		mutate_battle();game.selected = -1;game.free_selected = false
		game.route.save();var current = battle_state()
		create_game()
		check(game.route.resume(), treasure + " mid-attempt save resumes in a fresh game instance")
		check(battle_state() == current and game.normal_undos_remaining == 1, treasure + " resume retains current attempt and spent undo budget")
		check(game.battle_restart.can_restart(), treasure + " loaded entry checkpoint remains available")
		check(game.restart_battle() and battle_state() == start, treasure + " persisted checkpoint restores exact entry state, not save-time state")
		check(game.route.state == route and game.route.state.treasure_id == treasure, treasure + " route ownership and chapter remain unchanged")
		check(not game.treasure_battle.talisman_used and game.treasure_battle.spring_kills == 0, treasure + " per-battle treasure consumption resets to entry")
		ready_action();game.enemies[0].cd += 7;game.deck.reverse();game.lives = 1
		check(game.restart_battle() and battle_state() == start, treasure + " restored arrays do not alias and corrupt the checkpoint")
		ready_action();game.energy = 0;game.show_home()
		check(game.route.resume() and game.battle_restart.can_restart(), treasure + " home/resume keeps the original entry checkpoint")
		check(game.restart_battle() and battle_state() == start, treasure + " home/resume does not recapture the mid-battle state")
func check_legacy_and_identity():
	fresh_route("king", 1, "", false, false)
	game.turn = 3;game.lives = 1;game.energy = 1;game.normal_undos_remaining = 0;game.draw_card();ready_action();game.route.save()
	var legacy = battle_state();var route = game.route.state.duplicate(true)
	var config = saved_config();config.erase_section_key("run", "battle_start")
	check(config.save(game.route.SAVE) == OK, "writes an otherwise current save without optional entry checkpoint")
	check(game.route.resume(), "legacy save without entry checkpoint still resumes")
	check(battle_state() == legacy and game.route.state == route and game.normal_undos_remaining == 0, "legacy resume preserves existing progress exactly")
	assert_blocked("legacy save without a real entry checkpoint")
	game.route.save();check(game.route.resume() and not game.battle_restart.can_restart(), "saving/resuming legacy combat cannot invent an opening")
	game.settings.set_debug_mode(true);game.debug_skip();ready_action();game.choose_reward(-1);ready_action()
	check(game.screen == "map", "legacy combat can still finish normally")
	T.enter_next(game, "battle");ready_action()
	check(game.battle_restart.can_restart() and game.normal_undos_remaining == 0, "next actual battle creates a checkpoint without replenishing undo")
	game.settings.set_debug_mode(false)
	var other: Dictionary = saved_config().get_value("run", "battle_start", {}).duplicate(true)
	fresh_route("artillery", 2, "roving_axle")
	var current = battle_state();config = saved_config();config.set_value("run", "battle_start", other);config.save(game.route.SAVE)
	check(game.route.resume() and battle_state() == current, "unrelated entry checkpoint does not invalidate current run progress")
	assert_blocked("checkpoint from another role, chapter and node")
	config = saved_config();config.set_value("run", "battle_start", "not a snapshot");config.save(game.route.SAVE)
	check(game.route.resume() and battle_state() == current, "malformed optional checkpoint preserves otherwise valid run")
	assert_blocked("malformed optional checkpoint")
func check_tutorial_section():
	var campaign_save = save_text()
	game.start_tutorial(1);game.tutorial.skip_step();ready_action()
	var lesson: int = game.tutorial.lesson_index
	var section: int = game.tutorial._steps[game.tutorial.step_index].section
	var first_step: int = game.tutorial.step_index
	var start = battle_state()
	check(section > 0 and first_step > 0, "tutorial fixture starts in a later section, not the lesson opening")
	game.tutorial.step_index += 1;game.player = Vector2i(1, 8);game.hand = [];game.hand_ids = []
	game.lives = 0;game.phase = "dead";game.energy = 0;game.normal_undos_remaining = 1
	game.tutorial._retry_pending = true;game.tutorial._pending_step = first_step + 2
	check(game.restart_battle(), "tutorial restart reloads current exercise")
	check(game.tutorial.active and game.tutorial.lesson_index == lesson and game.tutorial.step_index == first_step, "tutorial restart retains lesson and returns to current section's first step")
	check(battle_state() == start, "tutorial restart restores that section's fixed board and cards")
	check(not game.tutorial._retry_pending and game.tutorial._pending_step == -1, "tutorial restart clears stale transition/retry state")
	check(game.normal_undos_remaining == 1 and game.history.entries.is_empty(), "tutorial restart does not replenish undo allowance")
	check(save_text() == campaign_save, "tutorial restart cannot overwrite the expedition save")
	check(not game.restart_battle(), "tutorial restart also rejects a duplicate immediate click")
func run():
	create_game()
	check_exact_restart();check_rng_replay();check_guards();check_persistence();check_legacy_and_identity();check_tutorial_section()
	print("BATTLE RESTART RESULT ", checks - failures, " passed, ", failures, " failed")
	game.free();quit(1 if failures else 0)
