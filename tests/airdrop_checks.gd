extends SceneTree
# The card's sacrifice, exhaustion and one-turn recovery share normal snapshots.
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("AIRDROP: " + label)
func fresh():
	game.player_skill = "king";game.new_run();game.enemies = [];game.add_enemy("g", Vector2i(4, 0), 999)
	game.enemies[0].hp = 9;game.enemies[0].max_hp = 9
	game.collection = ["airdrop", "airdrop", "sword", "fatigue"]
	game.hand = ["airdrop", "sword"];game.hand_ids = [];game.deck = [];game.discard = []
	game.energy = 5;game.lives = 4;game.player = Vector2i(4, 9)
	game.screen = "game";game.phase = "play";game.clear_effects();game.navigation_lock = 0;game.history.clear()
func next_turn():
	game.clear_effects();game.navigation_lock = 0;game.end_turn()
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.settings.set_debug_mode(true)
	check(game.CARDS.airdrop[1] == 3 and game.is_consumable("airdrop"), "three energy and per-copy exhaust")
	for identity in game.PROFILES.DATA:
		check(("airdrop" in game.PROFILES.DATA[identity].rewards) == (identity == "king"), "only king reward pool " + identity)
		check("airdrop" not in game.PROFILES.DATA[identity].deck, "not a starter " + identity)
	check("airdrop" not in game.PROFILES.COMMON, "not common reward")
	fresh();game.lives = 1;check(game.target_danger("airdrop", Vector2i(0,0)) and "失败" in game.card_data("airdrop")[2], "one-life landing is warned as lethal")
	check_legal()
	check_area_and_current_turn()
	check_sacrifice_priority()
	check_recovery()
	check_recovery_bleed()
	check_persistence_and_reset()
	check_chapter_window()
	print("AIRDROP RESULT ", checks - failures, " passed, ", failures, " failed")
	game.free();quit(1 if failures else 0)
func check_legal():
	fresh()
	for x in 9:
		for y in 10:
			var p = Vector2i(x, y)
			check(game.card_legal("airdrop", p) == (p != game.player and game.R.occupied(p, game.enemies) < 0), "any empty board cell " + str(p))
	game.add_enemy("stake", Vector2i(3, 3), 3)
	for p in [Vector2i(-1,0), Vector2i(9,9), game.player, Vector2i(4,0), Vector2i(3,3)]:
		var before = game.history.capture();game.play_card(0, p)
		check(game.energy == before.energy and game.hand == before.hand and game.lives == before.lives and game.player == before.player, "invalid target spends nothing " + str(p))
	for identity in ["horse", "artillery"]:
		game.player_skill = identity
		check(not game.card_legal("airdrop", Vector2i(0,0)), "other role cannot play " + identity)
	fresh();game.energy = 2;game.play_card(0, Vector2i(0,0))
	check(game.energy == 2 and game.hand.has("airdrop") and game.lives == 4, "insufficient energy is atomic")
func check_area_and_current_turn():
	for landing in [Vector2i(4,5), Vector2i(0,0), Vector2i(8,9)]:
		fresh();game.enemies[0].pos = Vector2i(4,0)
		var affected = []
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var target = landing + Vector2i(dx,dy)
				if target == landing or not game.R.inside(target): continue
				game.add_enemy("p", target, 999);var enemy = game.enemies.back();enemy.hp = 4;enemy.max_hp = 4;affected.append(enemy)
		game.shield_charges = 1;game.card_move_used = true
		game.play_card(0, landing)
		check(game.player == landing and game.lives == 3 and game.energy == 2, "land and exact costs " + str(landing))
		check(game.shield_charges == 1 and game.active_displacements == 1, "self cost no shield/recoil and displacement once")
		check(game.card_move_used and not game.basic_used and game.hand == ["sword"] and game.discard.is_empty(), "no draw, no movement refresh, consumed copy only")
		check(game.airdrop_recovery_turn == 2 and not game.recovery_active(), "only next turn is restricted")
		for enemy in affected: check(enemy.hp == 1, "every enemy in clipped 3x3 takes three")
		check(game.enemies[0].hp == 9, "outside target survives unchanged")
		var safe_step = landing + Vector2i(0, 2)
		if game.R.inside(safe_step): check(game.card_legal("airdrop", safe_step), "current turn can still target next copy")
	fresh();game.play_card(0, Vector2i(4,6));game.clear_effects();game.basic_move(Vector2i(4,7))
	check(game.player == Vector2i(4,7), "current turn retains unused free move")
	fresh();game.hand = ["airdrop", "breath"];game.play_card(0, Vector2i(4,6));game.play_card(0, game.player)
	check(game.energy == 3 and game.hand.is_empty(), "current turn may still play cards")
func check_sacrifice_priority():
	fresh();game.new_expedition();game.route.enter(0)
	game.enemies = [];game.add_enemy("g", Vector2i(4,0),3)
	game.hand = ["airdrop"];game.hand_ids = [];game.energy = 3;game.lives = 1
	game.route.state.pending_homework = ["spear_plus"];game.route.state.reward_debt = 1
	var collection = game.collection.duplicate()
	game.play_card(0, Vector2i(4,1))
	check(game.phase == "dead" and game.lives == 0 and not game.general_alive(), "self sacrifice loses even with simultaneous general death")
	check(game.collection == collection and not game.route.state.victory_recorded and game.route.state.reward_debt == 1, "no victory rewards/homework before self-loss")
	game.debug_skip();check(game.phase == "dead", "debug victory cannot escape already dead")
	undo_after_effects(game);check(game.lives == 1 and game.phase == "play" and game.general_alive() and game.hand == ["airdrop"] and game.airdrop_recovery_turn == 0, "undo restores whole sacrifice before action")
	game.lives = 2;game.play_card(0, Vector2i(4,1))
	check(game.lives == 1 and game.phase == "reward" and game.airdrop_recovery_turn == 0, "surviving general kill wins and clears recovery")
func check_recovery():
	fresh();game.hand = ["airdrop", "fatigue", "breath", "sword"];game.tuna_turns = 2
	game.play_card(0, Vector2i(4,6));next_turn()
	check(game.turn == 2 and game.recovery_active() and game.energy == 3 and game.tuna_turns == 1, "next turn blocked but tuna/fatigue settle normally")
	check(not game.free_card_available() and not game.basic_legal(Vector2i(4,7)), "free move unavailable")
	var before = game.history.capture()
	for i in game.hand.size():
		check(not game.can_commit_card(i,game.player), "no commit path during recovery")
		game.play_card(i,game.player);game.select_card(i)
	game.basic_move(Vector2i(4,7));game.select_free_card()
	check(game.player == before.player and game.hand == before.hand and game.energy == before.energy and game.selected == -1 and not game.free_selected, "direct click/play/movement paths blocked")
	check(not game.gesture.press(game.handui.bounds(0).get_center()), "drag start blocked")
	undo_after_effects(game)
	check(game.turn == 1 and game.airdrop_recovery_turn == 2 and not game.recovery_active(), "undo enemy phase restores pending recovery rather than discarding it")
	next_turn();check(game.recovery_active(), "replaying the turn re-enters recovery")
	game.clear_effects();var space = InputEventKey.new();space.pressed = true;space.keycode = KEY_SPACE;game._input(space)
	check(game.turn == 3 and not game.recovery_active() and game.airdrop_recovery_turn == 0 and game.energy == 3, "space ends exactly one skipped turn; no bonus energy")
	check(game.basic_legal(Vector2i(4,7)) and game.can_commit_card(1,game.player), "actions return next turn")
func check_recovery_bleed():
	fresh();game.add_enemy("e", Vector2i(0, 2), 999)
	var target = game.enemies.back();target.hp = 5;target.max_hp = 5
	game.queue_bleed(1, 2);game.play_card(0, Vector2i(4, 6));next_turn()
	check(game.recovery_active() and target.hp == 4 and game.pending_bleeds.size() == 1 and game.pending_bleeds[0].amount == 1, "airdrop ending deals first tick before restricted recovery begins")
	var uid = target.uid;var before = game.history.capture()
	next_turn()
	check(not game.recovery_active() and target.hp == 3 and game.pending_bleeds.is_empty() and game.turn == 3, "skipped recovery turn still deals exactly the second ending tick")
	undo_after_effects(game)
	check(game.history.capture() == before and game.recovery_active(), "undo skipped recovery restores one bleed tick and recovery lock together")
	next_turn()
	var restored = {}
	for enemy in game.enemies:
		if enemy.uid == uid: restored = enemy
	check(not restored.is_empty() and restored.hp == 3 and game.pending_bleeds.is_empty(), "replaying recovery ending neither loses nor duplicates remaining tick")

func check_persistence_and_reset():
	fresh();game.new_expedition();game.route.enter(0)
	game.hand = ["airdrop"];game.hand_ids = [];game.energy = 3;game.lives = 4
	game.play_card(0,Vector2i(0,8));next_turn();game.route.save()
	check(game.route.resume() and game.recovery_active() and not game.free_card_available(), "save and resume retains recovery lock")
	var cfg = ConfigFile.new();cfg.load(game.route.SAVE)
	var snapshot = cfg.get_value("run","battle");snapshot.erase("airdrop_recovery_turn");cfg.set_value("run","battle",snapshot);cfg.save(game.route.SAVE)
	check(game.route.resume() and game.airdrop_recovery_turn == 0, "pre-card version-five saves default to no recovery")
	fresh();game.hand = ["airdrop","airdrop"];game.energy = 6
	game.play_card(0,Vector2i(0,8));game.play_card(0,Vector2i(8,8))
	check(game.hand.is_empty() and game.discard.is_empty() and game.lives == 2 and game.airdrop_recovery_turn == 2, "multiple copies exhaust independently and same next turn only")
	game.start_stage()
	check((game.deck+game.hand).count("airdrop") == 2 and game.airdrop_recovery_turn == 0, "next battle restores copies and clears recovery")
func check_chapter_window():
	fresh();game.route.generate(1414,2);game.screen = "map"
	game.route.state.nodes[0].encounter = {"id":"c2_lone_guard","tier":"battle","chapter":2,"rules":[]}
	game.route.enter(0);game.lives = 100
	for enemy in game.enemies: enemy.cd = 999;enemy.period = 999
	game.hand = ["airdrop"];game.hand_ids = [];game.energy = 3
	game.play_card(0,Vector2i(3,1))
	check(game.encounter_state.ghosts.size() == 1 and game.encounter_state.ghosts[0].ready_phase == 3, "airdrop defeat schedules ordinary full-turn revival window")
	next_turn();check(game.recovery_active() and game.encounter_state.ghosts.size() == 1, "recovery is first complete window")
	next_turn();check(not game.recovery_active() and game.encounter_state.ghosts.size() == 1, "no early revival when recovery turn ends")
	game.player = Vector2i(8,9);next_turn()
	check(game.encounter_state.ghosts.is_empty(), "second complete window permits normal end-phase revival")

# These rules tests model the completed-animation boundary before user input.
func undo_after_effects(owner) -> bool:
	owner.input_lock = 0;owner.navigation_lock = 0;owner.presentation.clear()
	return owner.undo_action()
