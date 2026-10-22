extends SceneTree
# End-to-end route ownership, receipt persistence and migration. Run only with
# disposable XDG directories, as in scripts/verify.sh; no runtime QA API is used.
const T = preload("res://../tests/route_test_helpers.gd")
const TS = preload("res://treasure_system.gd")
const ROLES = ["king", "horse", "artillery"]
var game
var route
var checks = 0
var failures = 0

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("TREASURE ROUTE: " + label)
func settle():
	game.clear_effects();game.presentation.clear();game.input_lock = 0;game.navigation_lock = 0
func fresh(role: String = "king"):
	game.player_skill = role;game.seed_value = 150015;game.new_expedition();settle()
func file_text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
func snapshot() -> Dictionary:
	return {"route": route.state.duplicate(true), "battle": game.history.capture(), "screen": game.screen,
		"undos": game.normal_undos_remaining, "settings": [game.settings.debug_mode, game.settings.audio_muted],
		"save": file_text(route.SAVE), "settings_save": file_text(game.settings.SAVE)}
func enter_boss(role: String, mode: String):
	fresh(role)
	game.collection = ["sword_plus", "sword", "fatigue", "deploy"]
	game.lives = 2;game.normal_undos_remaining = 2
	if mode == "homework":
		route.state.pending_homework = ["spear_plus", "spear_plus"]
		route.state.reward_debt = 1
	var boss = T.kind_id(route, "boss");T.before(route, boss);route.enter(boss);settle()
	check(not route.choose_treasure(TS.ids_for(role)[0]), "boss combat cannot grant treasure before victory")
func pending_choice(role: String = "king", mode: String = "skip"):
	enter_boss(role, mode);game.debug_skip();settle()
	check(game.phase == "reward" and game.screen == "game" and route.chapter() == 1, "boss card receipt precedes mandatory treasure: " + role + "/" + mode)
	game.choose_reward(0 if mode == "normal" else -1);settle()
	check(game.screen == "treasure_choice" and route.chapter() == 1 and not route.state.done, "reward resolution pauses before chapter two: " + role + "/" + mode)
func assert_choice_immutable(id: String, label: String):
	var before = snapshot()
	check(not route.choose_treasure(id), label + " rejects claim")
	check(snapshot() == before, label + " has no route, battle, RNG, save, undo or settings effect")
func assert_rejected(saved: Dictionary, battle: Dictionary, screen: String, label: String):
	var before = snapshot()
	check(not route.valid_snapshot(saved, battle, screen), label + " fails pure validation")
	check(snapshot() == before, label + " validation is read-only")
	var config = ConfigFile.new();config.load(route.SAVE)
	config.set_value("run", "route", saved);config.set_value("run", "battle", battle);config.set_value("run", "screen", screen)
	check(config.save(route.SAVE) == OK, label + " writes isolated malformed fixture")
	var invalid_before = snapshot()
	check(not route.resume(), label + " cannot resume")
	check(snapshot() == invalid_before, label + " rejected resume is atomic")
	FileAccess.open(route.SAVE, FileAccess.WRITE).store_string(before.save)

func check_role_rewards():
	check(TS.DATA.size() == 9, "nine treasures are the complete catalog")
	var all = []
	for role in ROLES:
		var ids = TS.ids_for(role)
		check(ids.size() == 3, "each role has exactly three mandatory choices: " + role)
		for id in ids:
			check(id not in all and TS.DATA[id].role == role, "role treasure identity is unique: " + id);all.append(id)
		for mode_index in 3:
			var mode = ["normal", "skip", "homework"][mode_index]
			enter_boss(role, mode)
			var deck = game.collection.duplicate()
			var old_seed = route.state.seed;var run_seed = route.state.run_seed
			game.debug_skip();settle()
			var victory_lives = 3 if role == "king" else 2
			if mode == "homework": deck.append_array(["spear_plus", "spear_plus"])
			check(game.collection == deck and game.lives == victory_lives, "boss settles exact homework and health once: " + role + "/" + mode)
			check(route.rewards_blocked() == (mode == "homework"), "homework only blocks ordinary card rewards")
			check(game.rewards.is_empty() if mode == "homework" else not game.rewards.is_empty(), "normal reward pool matches boss receipt")
			var reward_state = snapshot()
			check(route.resume() and game.collection == deck and game.lives == victory_lives, "boss receipt resumes before treasure")
			game.debug_skip();route.battle_victory()
			check(snapshot() == reward_state, "replayed victory cannot change homework, healing, RNG or save")
			if mode == "normal": deck.append(game.rewards[0])
			game.choose_reward(0 if mode == "normal" else -1);settle()
			check(game.screen == "treasure_choice" and route.chapter() == 1, "every reward path requires treasure choice")
			check(route.state.treasure_choices == ids and route.state.treasure_id.is_empty() and not route.state.treasure_claimed, "exact unclaimed role choices are persisted")
			check(route.state.pending == -1 and route.state.current == T.kind_id(route, "boss") and route.legal().is_empty(), "old boss is completed, with no playable route behind treasure modal")
			check(game.collection == deck and game.lives == victory_lives and not game.history.can_undo(), "pending treasure preserves exact permanent cards and life, clears undo")
			check(game.normal_undos_remaining == 2 and game.settings.debug_mode and game.settings.audio_muted, "pending treasure preserves normal undo budget and independent settings")
			var pending = snapshot()
			check(route.resume() and snapshot() == pending, "pending treasure save resumes exactly without rerolling")
			game.show_home();check(route.resume() and snapshot() == pending, "home then Continue returns to mandatory pending selection")
			assert_choice_immutable("missing_treasure", "unknown treasure")
			assert_choice_immutable(TS.ids_for("horse" if role != "horse" else "king")[0], "other role treasure")
			game.choose_reward(-1);game.delete_reward(0);route.complete();route.enter(0)
			check(snapshot() == pending, "repeat reward actions and route entry cannot skip or duplicate pending choice")
			var id = ids[mode_index]
			check(route.choose_treasure(id), "role treasure claims atomically: " + id)
			check(game.screen == "map" and route.chapter() == 2 and not route.state.done, "one claim creates chapter two")
			check(route.state.treasure_id == id and route.state.treasure_claimed and route.state.treasure_choices.is_empty(), "claim stores one identity and removes pending choices")
			check(route.state.current == -1 and route.state.pending == -1 and route.state.visited.is_empty() and route.legal() == [0], "claim creates clean second chapter progress")
			check(route.state.seed != old_seed and route.state.run_seed == run_seed and game.seed_value == run_seed, "claim keeps expedition seed and chooses deterministic second map")
			check(game.collection == deck and game.lives == victory_lives and game.player_skill == role, "treasure acquisition never adds life/cards or changes role")
			check(game.normal_undos_remaining == 2 and game.settings.debug_mode and game.settings.audio_muted, "claim leaves budget and settings untouched")
			check(game.hand.is_empty() and game.enemies.is_empty() and game.encounter_state.is_empty() and not game.history.can_undo(), "chapter claim has no stale battle or cross-chapter undo")
			var claimed = snapshot()
			check(route.resume() and snapshot() == claimed, "claimed treasure and clean chapter resume exactly")
			for duplicate in ids: assert_choice_immutable(duplicate, "already claimed " + duplicate)
			route.enter(0);settle()
			check(game.treasures.active_id() == id and route.state.treasure_id == id and game.collection == deck and game.lives == victory_lives, "next real battle activates the owned treasure without acquisition healing")
			route.save();var battle = snapshot();check(route.resume() and snapshot() == battle, "active treasure battle save resumes exactly")

func check_pending_validation():
	pending_choice()
	var saved = route.state.duplicate(true);var battle = game.history.capture()
	check(route.valid_snapshot(saved, battle, "treasure_choice"), "well-formed pending reward validates")
	for value in [[], ["longevity_seal"], ["longevity_seal", "longevity_seal", "tiger_tally"], ["wind_horseshoe", "battle_tassel", "spring_bit"], ["longevity_seal", "life_talisman", "missing"], "longevity_seal"]:
		var invalid = saved.duplicate(true);invalid.treasure_choices = value
		assert_rejected(invalid, battle, "treasure_choice", "malformed pending choice list " + str(value))
	for pair in [["treasure_id", "longevity_seal"], ["treasure_id", 1], ["treasure_claimed", true], ["treasure_claimed", "false"]]:
		var invalid = saved.duplicate(true);invalid[pair[0]] = pair[1]
		assert_rejected(invalid, battle, "treasure_choice", "invalid pending ownership " + str(pair))
	var invalid = saved.duplicate(true);invalid.erase("treasure_choices")
	assert_rejected(invalid, battle, "treasure_choice", "missing pending treasure list")
	invalid = saved.duplicate(true);invalid.visited.pop_back();invalid.current = invalid.visited.back()
	assert_rejected(invalid, battle, "treasure_choice", "treasure offered before first boss completion")
	invalid = saved.duplicate(true);invalid.treasure_choices = []
	assert_rejected(invalid, battle, "map", "pending treasure hidden by map screen")
	for phase in ["reward", "win", "dead", "discard"]:
		var invalid_battle = battle.duplicate(true);invalid_battle.phase = phase
		assert_rejected(saved, invalid_battle, "treasure_choice", "pending selection with stale phase " + phase)
	var invalid_battle = battle.duplicate(true);invalid_battle.lives = 0
	assert_rejected(saved, invalid_battle, "treasure_choice", "dead expedition cannot claim treasure")
	check(route.choose_treasure("life_talisman"), "valid pending save still claims after all rejected fixtures")
	saved = route.state.duplicate(true);battle = game.history.capture()
	for pair in [["treasure_id", "wind_horseshoe"], ["treasure_id", "missing"], ["treasure_id", ""], ["treasure_claimed", false], ["treasure_choices", ["longevity_seal", "life_talisman", "tiger_tally"]]]:
		invalid = saved.duplicate(true);invalid[pair[0]] = pair[1]
		assert_rejected(invalid, battle, "map", "invalid chapter-two ownership " + str(pair))
	assert_rejected(saved, battle, "treasure_choice", "chapter two cannot offer a second treasure")

func check_tutorial_and_new_run():
	pending_choice()
	game.tutorial.active = true
	assert_choice_immutable("longevity_seal", "active tutorial cannot acquire treasure")
	game.tutorial.active = false;check(route.choose_treasure("longevity_seal"), "normal expedition claim remains available after tutorial guard")
	var saved = file_text(route.SAVE)
	game.start_tutorial(0)
	check(game.tutorial.active and not route.active() and game.treasures.active_id().is_empty(), "tutorial has no expedition treasure effects")
	assert_choice_immutable("longevity_seal", "tutorial fixture has no claim path")
	check(file_text(route.SAVE) == saved, "tutorial leaves expedition treasure save untouched")
	check(route.resume() and route.state.treasure_id == "longevity_seal" and not game.tutorial.active, "Continue restores expedition treasure after tutorial")
	fresh("king")
	check(route.state.treasure_id.is_empty() and not route.state.treasure_claimed and route.state.treasure_choices.is_empty() and not game.unlimited_lives(), "new expedition removes previous run ownership")

func check_longevity_herbalist():
	pending_choice();game.lives = 5
	check(route.choose_treasure("longevity_seal") and game.lives == 5, "long-lived seal acquisition never heals")
	route.enter(0);settle();game.debug_skip();settle();game.choose_reward(-1);settle()
	check(game.lives == 6, "king victory with seal heals above ordinary maximum")
	T.enter_next(game, "event", "herbalist")
	var healing = -1
	for i in route.choices.size():
		if route.choices[i].action == "heal": healing = i
	check(healing >= 0 and "无上限" in route.choices[healing].label, "herbalist offers unlimited healing above five")
	if healing >= 0:
		route.resolve(healing);check(game.lives == 6 and route.choice_mode == "confirm", "herbalist preview remains read-only")
		route.resolve(0)
	check(game.lives == 7 and game.screen == "map" and game.can_heal(), "confirmed herbalist heals above five exactly once")
	route.resolve(0);check(game.lives == 7, "duplicate herbalist confirmation cannot heal again")
	route.save();check(route.resume() and game.lives == 7 and game.unlimited_lives(), "save preserves seven lives and run treasure")

func check_legacy_saves():
	for chapter in [1, 2]:
		for screen in ["map", "game"]:
			fresh("horse")
			if chapter == 2: route.generate(game.seed_value, 2)
			if screen == "game": route.enter(0);settle()
			game.normal_undos_remaining = 1;route.save()
			var config = ConfigFile.new();check(config.load(route.SAVE) == OK, "legacy fixture loads current envelope")
			check(config.get_value("run", "version") == 6, "treasure update preserves version six")
			var saved = config.get_value("run", "route");var battle = config.get_value("run", "battle")
			for key in ["treasure_id", "treasure_claimed", "treasure_choices"]: saved.erase(key)
			battle.erase("treasure_battle")
			config.set_value("run", "route", saved);config.set_value("run", "battle", battle);config.save(route.SAVE)
			var deck = game.collection.duplicate();var life = game.lives;var rng_state = game.rng.state
			game.treasure_battle = {"talisman_used": true, "tiger_moves": 2}
			check(route.resume(), "pre-treasure current-version save remains resumable: %d/%s" % [chapter, screen])
			check(game.screen == screen and route.chapter() == chapter and game.treasure_battle == {} and game.treasures.active_id().is_empty(), "missing optional treasure battle defaults safely without inventing ownership")
			check(game.collection == deck and game.lives == life and game.rng.state == rng_state and game.normal_undos_remaining == 1, "legacy migration preserves exact cards, life, RNG and undo budget")
			check(game.settings.debug_mode and game.settings.audio_muted, "legacy resume preserves independent settings")
			route.save();check(route.resume(), "migrated save re-saves and resumes normally")

func check_active_save_state():
	for id in TS.DATA:
		pending_choice(TS.DATA[id].role)
		check(route.choose_treasure(id), "counter save fixture owns treasure: " + id)
		route.enter(0);settle()
		match id:
			"longevity_seal": game.heal_lives(8)
			"life_talisman":
				game.lives = 1;game.lose_lives(1)
				check(game.treasure_battle.talisman_used and game.lives == 1, "save fixture consumes actual rescue")
			"tiger_tally":
				for i in 4: game.treasures.on_displacement()
				check(game.treasure_battle.tiger_moves == 1 and "treasure_king_step" in game.hand, "save fixture retains movement remainder and temporary step")
			"wind_horseshoe", "battle_tassel":
				game.active_displacements = 2;game.treasures.on_displacement()
			"spring_bit":
				game.treasures.on_enemy_defeated({"kind": "p"})
				check(game.treasure_battle.spring_kills == 1, "save fixture consumes first spring heal")
			"gate_cannon_seal":
				game.artillery_mode = "attack";game.treasures.start_turn();game.treasures.begin_card("cannon_shot");game.treasures.end_card()
			"roving_axle":
				game.treasures.on_stance_change("attack", "march")
				check(game.treasure_battle.axle_used and "treasure_transfer" in game.hand, "save fixture retains spent axle and temporary transfer")
		game.sync_hand_ids();route.save()
		var expected = snapshot()
		check(route.valid_snapshot(route.state, game.history.capture(), "game"), "active treasure counters are valid save data: " + id)
		check(route.resume() and snapshot() == expected, "resume preserves exact treasure counters, temporary hand IDs and RNG: " + id)
		var battle = game.history.capture();var saved = route.state.duplicate(true)
		if id == "tiger_tally":
			for pile in ["collection", "deck", "discard", "rewards"]:
				var invalid = battle.duplicate(true);invalid[pile].append("treasure_king_step")
				assert_rejected(saved, invalid, "game", "temporary card cannot persist in " + pile)
			for key in ["pending_homework", "homework_awarded"]:
				var invalid = saved.duplicate(true);invalid[key].append("treasure_king_step")
				assert_rejected(invalid, battle, "game", "temporary card cannot persist in " + key)
			for pair in [["tiger_moves", 3], ["spring_kills", -1], ["talisman_used", 1], ["trigger_serial", -1], ["tassel_ready", true], ["attack_bonus", 2]]:
				var invalid = battle.duplicate(true);invalid.treasure_battle[pair[0]] = pair[1]
				assert_rejected(saved, invalid, "game", "malformed treasure battle counter " + str(pair))
			var invalid = battle.duplicate(true);invalid.treasure_battle.erase("tiger_moves")
			assert_rejected(saved, invalid, "game", "partial treasure battle state is rejected")

func check_final_boss():
	for role in ROLES:
		pending_choice(role)
		var treasure = TS.ids_for(role)[1]
		check(route.choose_treasure(treasure), "final-boss fixture obtains real chapter reward")
		var boss = T.kind_id(route, "boss");T.before(route, boss);route.enter(boss);settle()
		var deck = game.collection.duplicate();game.debug_skip();settle()
		check(game.phase == "win" and route.state.done and route.chapter() == 2 and game.screen != "treasure_choice", "second boss finishes run without second treasure")
		check(route.state.treasure_id == treasure and route.state.treasure_claimed and route.state.treasure_choices.is_empty() and game.collection == deck, "ending preserves single claim without duplicate rewards")
		for id in TS.ids_for(role): assert_choice_immutable(id, "final boss cannot claim " + id)
		game.choose_reward(-1);route.complete();check(route.state.done and game.phase == "win", "repeat final actions cannot reopen treasure selection")
		check(not route.resume(), "completed expedition cannot resume to reissue treasure")

func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);route = game.route
	game.settings.set_debug_mode(true);game.settings.set_audio_muted(true)
	check_role_rewards();check_pending_validation();check_tutorial_and_new_run();check_longevity_herbalist();check_legacy_saves();check_active_save_state();check_final_boss()
	print("TREASURE ROUTE RESULT %d checks, %d failures" % [checks, failures])
	game.free();quit(1 if failures else 0)
