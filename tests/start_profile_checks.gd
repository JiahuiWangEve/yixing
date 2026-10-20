extends SceneTree
# Behavior-level checks for the three start profiles. Run with an isolated user://.
const R = preload("res://rules.gd")
const COMMON = ["sword", "spear", "diagonal", "push", "stun", "breath"]
const DEDICATED = {
	"king": ["life", "sweep", "pierce", "shock", "tuna"],
	"horse": ["straight", "swap", "pursuit", "advance", "retreat_strike", "knight_assault"],
	"artillery": ["stake", "cannon_shot", "deploy", "pack"]
}
const INITIAL = {
	"king": ["sword", "sword", "sword", "spear", "spear", "horse", "life", "stun"],
	"horse": ["sword", "sword", "sword", "spear", "spear", "straight", "pursuit", "stun"],
	"artillery": ["sword", "spear", "straight", "stake", "cannon_shot", "cannon_shot", "deploy", "pack"]
}
var game
var passed = 0
var failed = 0

func check(ok: bool, label: String):
	if ok:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		push_error("FAIL " + label)

func same_cards(actual: Array, expected: Array) -> bool:
	var a = actual.duplicate()
	var b = expected.duplicate()
	a.sort()
	b.sort()
	return a == b

func reset(identity: String = "king"):
	game.player_skill = identity
	game.new_run()
	game.enemies = []
	game.add_enemy("g", Vector2i(4, 0), 9999)
	game.deck = ["sword", "spear", "horse", "sword", "spear", "horse"]
	game.hand = []
	game.hand_ids = []
	game.discard = []
	game.input_lock = 0.0
	game.navigation_lock = 0.0

func set_hand(cards: Array):
	game.hand = cards.duplicate()
	game.hand_ids = []
	game.sync_hand_ids()

func _initialize():
	call_deferred("run_checks")

func run_checks():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	check_profiles_and_rewards()
	check_movement_and_cannon()
	check_horse_attacks()
	check_stance_quota()
	check_deployment()
	check_consumption()
	check_tuna()
	check_undo_determinism()
	check_progress_and_tutorial()
	print("PROFILE RESULT ", passed, " passed, ", failed, " failed")
	game.queue_free()
	quit(1 if failed else 0)

func check_profiles_and_rewards():
	for identity in INITIAL:
		game.player_skill = identity
		game.new_run()
		check(game.lives == (2 if identity == "king" else 1), identity + " initial health")
		check(same_cards(game.collection, INITIAL[identity]) and same_cards(game.deck, INITIAL[identity]), identity + " exact eight-card starting deck")
		check(game.hand.is_empty() and game.discard.is_empty() and game.energy == 3, identity + " retains empty opening hand and three energy")
		var all_legal = COMMON + DEDICATED[identity]
		check(same_cards(game.reward_pool(), all_legal), identity + " available pool contains only common and own cards")
		var rewards_valid = true
		for sample in 80:
			game.roll_rewards()
			var unique = {}
			var own_count = 0
			for id in game.rewards:
				unique[id] = true
				if id not in all_legal: rewards_valid = false
				if id in DEDICATED[identity]: own_count += 1
			if game.rewards.size() != 3 or unique.size() != 3 or own_count != 2: rewards_valid = false
		check(rewards_valid, identity + " rewards are two distinct dedicated and one common across repeated rolls")
		game.phase = "reward"
		game.input_lock = 0.0
		game.navigation_lock = 0.0
		var chosen = game.rewards[0]
		var count = game.collection.count(chosen)
		game.choose_reward(0)
		check(game.stage == 2 and game.collection.count(chosen) == count + 1 and game.deck.count(chosen) == count + 1, identity + " chosen reward persists into next-stage deck")
		game.new_run()
		check(same_cards(game.collection, INITIAL[identity]) and game.stage == 1, identity + " restart clears previous rewards")
		game.roll_rewards()
		game.phase = "reward"
		game.choose_reward(-1)
		check(game.stage == 2 and same_cards(game.collection, INITIAL[identity]), identity + " skipping reward preserves collection")
		game.input_lock = 0.0
		game.navigation_lock = 0.0
		game.roll_rewards()
		game.phase = "reward"
		var removed_card = game.collection[0]
		var previous_count = game.collection.count(removed_card)
		game.delete_reward(0)
		check(game.stage == 3 and game.collection.size() == 7 and game.collection.count(removed_card) == previous_count - 1 and same_cards(game.deck, game.collection), identity + " removing reward deletes one permanent copy")
	reset("artillery")
	game.artillery_mode = "attack"
	check(same_cards(game.reward_pool(), COMMON + DEDICATED.artillery), "artillery rewards depend on identity rather than stance")

func check_movement_and_cannon():
	reset("artillery")
	check(game.artillery_mode == "march", "artillery starts in marching stance")
	game.player = Vector2i(4, 5)
	check(game.basic_legal(Vector2i(4, 4)) and game.basic_legal(Vector2i(4, 3)) and game.basic_legal(Vector2i(2, 5)), "march permits orthogonal one or two cells")
	check(not game.basic_legal(Vector2i(5, 4)) and not game.basic_legal(Vector2i(4, 2)) and not game.basic_legal(Vector2i(4, 5)) and not game.basic_legal(Vector2i(-1, 5)), "march rejects diagonal excessive stationary and off-board moves")
	game.add_enemy("stake", Vector2i(4, 4), 0)
	check(not game.basic_legal(Vector2i(4, 3)) and not game.basic_legal(Vector2i(4, 4)), "march cannot jump over or land on a stake")
	game.basic_move(Vector2i(2, 5))
	check(game.player == Vector2i(2, 5) and game.hand.size() == 1 and game.basic_used and game.energy == 3, "two-cell marching move consumes free quota and draws exactly one")
	game.basic_used = false
	game.artillery_mode = "attack"
	check(game.basic_legal(Vector2i(2, 4)) and not game.basic_legal(Vector2i(2, 3)) and not game.basic_legal(Vector2i(3, 4)), "attack stance permits only one orthogonal free step")
	game.input_lock = 0
	game.select_free_card()
	check(game.free_selected and game.artillery_mode == "attack", "attack movement card selects movement instead of packing")
	game.basic_move(Vector2i(2, 4))
	check(game.player == Vector2i(2, 4) and game.basic_used and game.hand.size() == 2 and game.artillery_mode == "attack" and not game.can_emergency_pack(), "attack step draws one stays deployed and shares quota with pack")
	game.undo_action()
	check(game.player == Vector2i(2, 5) and not game.basic_used and game.artillery_mode == "attack" and game.hand.size() == 1, "undo attack step restores position draw and quota")
	game.input_lock = 0
	check(not game.gesture.press(game.pack_button_rect().get_center(), "mouse"), "pack button bypasses card gesture interception")
	game.handle_click(game.pack_button_rect().get_center())
	check(game.artillery_mode == "march" and game.basic_used and game.hand.size() == 1, "dedicated pack button remains usable without drawing")
	reset("artillery")
	game.player = Vector2i(4, 4)
	game.add_enemy("p", Vector2i(4, 1), 99)
	game.add_enemy("stake", Vector2i(4, 3), 0)
	set_hand(["cannon_shot"])
	game.enemies[1].hp = 3
	game.play_card(0, Vector2i(4, 1))
	check(game.enemies[1].hp == 2 and game.energy == 1 and game.discard == ["cannon_shot"], "march cannon costs two and deals one")
	set_hand(["cannon_shot"])
	game.artillery_mode = "attack"
	check(game.card_cost("cannon_shot") == 1 and game.card_data("cannon_shot")[1] == 1 and game.can_commit_card(0, Vector2i(4, 1)), "attack cannon UI and affordability use one energy")
	game.play_card(0, Vector2i(4, 1))
	check(game.enemies.size() == 2 and game.energy == 0, "attack cannon costs one and deals two")
	game.undo_action()
	check(game.enemies[1].hp == 2 and game.energy == 1 and game.hand == ["cannon_shot"], "undo cannon restores damage resources and card")
	game.artillery_mode = "march"
	game.play_card(0, Vector2i(4, 1))
	check(game.energy == 1 and game.hand == ["cannon_shot"] and game.enemies[1].hp == 2, "unaffordable march shot changes nothing")
	reset("artillery")
	game.artillery_mode = "attack"
	game.player = Vector2i(4, 4)
	game.add_enemy("p", Vector2i(4, 1), 99)
	check(not game.card_legal("cannon_shot", Vector2i(4, 1)), "cannon shot rejects zero screens")
	game.add_enemy("stake", Vector2i(4, 3), 0)
	game.add_enemy("p", Vector2i(4, 2), 99)
	check(not game.card_legal("cannon_shot", Vector2i(4, 1)) and not game.card_legal("cannon_shot", Vector2i(4, 3)), "cannon shot rejects two screens and direct stake target")
	game.add_enemy("p", Vector2i(3, 1), 99)
	check(not game.card_legal("cannon_shot", Vector2i(3, 1)), "cannon shot rejects diagonal targets")
	reset("artillery")
	game.artillery_mode = "attack"
	game.player = Vector2i(2, 4)
	game.lives = 2
	game.add_enemy("p", Vector2i(2, 3), 99)
	game.end_turn()
	check(game.lives == 1 and game.artillery_mode == "attack" and not R.threatened(game.player, game.enemies), "surviving recoil preserves attack stance without movement draw")
	reset("horse")
	game.player = Vector2i(4, 5)
	check(game.basic_legal(Vector2i(6, 4)) and not game.basic_legal(Vector2i(4, 4)), "horse keeps knight-step free movement")
	game.add_enemy("stake", Vector2i(5, 5), 0)
	check(not game.basic_legal(Vector2i(6, 4)), "horse free movement respects blocked leg")
	set_hand(["straight", "horse"])
	game.play_card(0, Vector2i(4, 3))
	var after_move = game.player
	var after_energy = game.energy
	game.play_card(0, Vector2i(6, 2))
	check(game.player == after_move and game.energy == after_energy and game.card_move_used, "horse still has only one paid movement quota")

func check_deployment():
	reset("artillery")
	set_hand(["deploy"])
	var original_deck = game.deck.duplicate()
	var random_before = game.rng.state
	game.play_card(0, game.player)
	check(game.artillery_mode == "attack" and game.energy == 2 and game.hand.size() == 3 and game.deck.size() == 3 and game.deploy_draw_used, "deploy costs one switches stance and draws three immediately")
	check("deploy" not in game.discard, "deploy exhausts instead of entering discard")
	game.undo_action()
	check(game.artillery_mode == "march" and game.energy == 3 and game.hand == ["deploy"] and game.deck == original_deck and not game.deploy_draw_used and game.rng.state == random_before, "undo deploy restores stance hand deck quota energy and RNG")
	reset("artillery")
	set_hand(["deploy"])
	game.energy = 0
	game.play_card(0, game.player)
	check(game.hand == ["deploy"] and game.artillery_mode == "march" and not game.deploy_draw_used and game.deck.size() == 6, "unaffordable deploy does not consume or draw")
	game.energy = 3
	game.artillery_mode = "attack"
	game.play_card(0, game.player)
	check(game.hand == ["deploy"] and game.energy == 3 and not game.deploy_draw_used, "deploy is rejected in attack stance")
	reset("artillery")
	set_hand(["deploy", "pack", "deploy"])
	game.play_card(0, game.player)
	game.play_card(0, game.player)
	check(game.artillery_mode == "march" and not game.basic_used and not game.card_move_used and game.energy == 2, "pack costs zero and preserves both movement quotas")
	var cards_before_second_deploy = game.deck.size()
	game.play_card(0, game.player)
	check(game.artillery_mode == "attack" and game.deck.size() == cards_before_second_deploy and game.hand.size() == 3 and game.energy == 1, "second deployment in same turn does not draw again")
	game.end_turn()
	check(game.artillery_mode == "attack" and not game.deploy_draw_used and game.hand.size() == 3, "new turn resets deployment trigger without passive stance draw")
	set_hand(["pack", "deploy"])
	game.play_card(0, game.player)
	game.play_card(0, game.player)
	check(game.deploy_draw_used and game.hand.size() == 3, "deployment draws again on a later turn")
	reset("artillery")
	game.artillery_mode = "attack"
	check(game.can_emergency_pack(), "fixed emergency pack is available without a hand card")
	game.emergency_pack()
	check(game.artillery_mode == "march" and game.basic_used and not game.card_move_used and game.energy == 3 and game.hand.is_empty(), "emergency pack uses free action without energy or draw")
	check(not game.can_emergency_pack() and not game.basic_legal(Vector2i(4, 8)), "emergency pack does not refresh free movement")
	set_hand(["straight"])
	game.play_card(0, Vector2i(4, 7))
	check(game.player == Vector2i(4, 7) and game.card_move_used and game.hand.size() == 1, "paid movement remains available after emergency pack")
	game.undo_action()
	game.undo_action()
	check(game.artillery_mode == "attack" and not game.basic_used and game.hand.is_empty(), "undo emergency pack restores stance and free action")
	reset("artillery")
	set_hand(["deploy", "sword", "sword", "sword", "sword", "sword"])
	game.play_card(0, game.player)
	check(game.hand.size() == 8 and game.phase == "discard", "deployment draws all three before resolving hand overflow")
	game.discard_hand(0)
	check(game.hand.size() == 7 and game.phase == "discard", "overflow remains in discard phase above six")
	game.discard_hand(0)
	check(game.hand.size() == 6 and game.phase == "play", "overflow ends only after enough cards were discarded")
	reset("artillery")
	game.artillery_mode = "attack"
	game.deploy_draw_used = true
	game.stage = 2
	game.start_stage()
	check(game.artillery_mode == "march" and not game.deploy_draw_used, "new stage resets artillery stance and deployment trigger")

func check_consumption():
	reset()
	check(game.is_consumable("life") and game.is_consumable("breath") and game.is_consumable("deploy") and game.is_consumable("tuna") and not game.is_consumable("sword"), "consumption property covers four cards only")
	game.lives = 1
	set_hand(["life", "life"])
	game.energy = 6
	game.play_card(0, game.player)
	game.play_card(0, game.player)
	check(game.lives == 3 and game.hand.is_empty() and game.discard.is_empty() and game.energy == 2, "duplicate consumables can each be used once")
	reset()
	game.lives = 5
	set_hand(["life"])
	game.play_card(0, game.player)
	check(game.hand == ["life"] and game.energy == 3 and game.discard.is_empty(), "full-health life card is not consumed")
	reset()
	game.deck = []
	set_hand(["breath", "sword", "sword", "sword", "sword", "sword", "sword"])
	game.phase = "discard"
	game.discard_hand(0)
	check(game.discard == ["breath"], "discarding a consumable does not exhaust it")
	game.hand = []
	game.hand_ids = []
	game.draw_card()
	check(game.hand == ["breath"] and game.discard.is_empty(), "discarded consumable can be recycled and redrawn")
	game.play_card(0, game.player)
	game.draw_card()
	check(game.hand.is_empty() and game.deck.is_empty() and game.discard.is_empty(), "used consumable cannot re-enter current-stage draw cycle")
	reset()
	set_hand(["life"])
	game.lives = 1
	game.play_card(0, game.player)
	game.stage = 2
	game.start_stage()
	check(game.deck.count("life") == 1 and game.collection.count("life") == 1 and game.lives == 2, "next stage restores exhausted life card while retaining health")

func check_tuna():
	reset()
	set_hand(["tuna"])
	game.play_card(0, game.player)
	check(game.energy == 0 and game.tuna_turns == 3 and game.discard.is_empty(), "tuna costs three exhausts and schedules three future bonuses")
	game.end_turn()
	check(game.energy == 4 and game.tuna_turns == 2, "first future turn receives four energy")
	game.end_turn()
	check(game.energy == 4 and game.tuna_turns == 1, "second future turn receives four energy")
	game.end_turn()
	check(game.energy == 4 and game.tuna_turns == 0, "third future turn receives four energy")
	game.end_turn()
	check(game.energy == 3 and game.tuna_turns == 0, "fourth future turn returns to three energy")
	reset()
	set_hand(["tuna", "tuna"])
	game.energy = 6
	game.play_card(0, game.player)
	game.play_card(0, game.player)
	check(game.tuna_turns == 6 and game.energy == 0, "two tuna copies extend duration to six turns")
	game.end_turn()
	check(game.energy == 4 and game.tuna_turns == 5, "stacking tuna does not increase per-turn bonus above one")
	game.undo_action()
	check(game.tuna_turns == 6 and game.energy == 0 and game.turn == 1, "undo turn restores pending tuna duration and energy")
	game.undo_action()
	check(game.tuna_turns == 3 and game.hand == ["tuna"] and game.energy == 3, "undo tuna restores consumed copy and pending duration")
	game.stage = 2
	game.start_stage()
	check(game.tuna_turns == 0 and not game.tuna_active and game.energy == 3, "tuna duration and current bonus clear between stages")
	reset()
	set_hand(["tuna"])
	game.energy = 2
	game.play_card(0, game.player)
	check(game.hand == ["tuna"] and game.energy == 2 and game.tuna_turns == 0, "unaffordable tuna does not consume or grant duration")

	reset()
	set_hand(["tuna", "tuna"])
	game.play_card(0, game.player)
	game.end_turn()
	game.play_card(0, game.player)
	check(game.energy == 1 and game.tuna_turns == 5 and game.tuna_active, "using tuna during an active bonus extends future duration without refund")
	game.end_turn()
	check(game.energy == 4 and game.tuna_turns == 4, "active-turn extension keeps one extra energy per future turn")

func check_undo_determinism():
	reset("artillery")
	set_hand(["deploy", "sword"])
	game.deck = ["cannon_shot"]
	game.discard = ["stake", "pack"]
	var ids_before = game.hand_ids.duplicate()
	var next_uid_before = game.next_card_uid
	var random_before = game.rng.state
	game.play_card(0, game.player)
	var expected_hand = game.hand.duplicate()
	var expected_ids = game.hand_ids.duplicate()
	var unique_ids = {}
	for id in game.hand_ids: unique_ids[id] = true
	check(game.hand.size() == 4 and game.hand_ids.size() == 4 and unique_ids.size() == 4 and game.deck.is_empty() and game.discard.is_empty(), "deploy draws across discard shuffle with unique card instance IDs")
	game.undo_action()
	check(game.hand == ["deploy", "sword"] and game.hand_ids == ids_before and game.next_card_uid == next_uid_before and game.deck == ["cannon_shot"] and game.discard == ["stake", "pack"] and game.rng.state == random_before, "undo restores card IDs and pre-shuffle piles exactly")
	game.play_card(0, game.player)
	check(game.hand == expected_hand and game.hand_ids == expected_ids, "replaying deployment after undo yields identical drawn cards and IDs")
	reset()
	game.player = Vector2i(4, 1)
	game.enemies[0].hp = 1
	set_hand(["sword"])
	game.play_card(0, Vector2i(4, 0))
	var rolled_rewards = game.rewards.duplicate()
	check(game.phase == "reward", "winning attack reaches reward state for deterministic undo")
	game.undo_action()
	check(game.phase == "play" and game.enemies.size() == 1 and game.enemies[0].hp == 1 and game.hand == ["sword"], "undo winning attack restores combat state")
	game.play_card(0, Vector2i(4, 0))
	check(game.rewards == rolled_rewards, "replaying winning attack after undo cannot reroll reward choices")

func check_progress_and_tutorial():
	game.skill_system.horse_unlocked = false
	check(game.skill_system.is_unlocked("king") and not game.skill_system.is_unlocked("horse") and not game.skill_system.is_unlocked("artillery"), "fresh progress offers only king")
	game.player_skill = "king"
	check(not game.skill_system.choose("artillery") and game.player_skill == "king", "locked artillery cannot be selected")
	game.skill_system.horse_unlocked = true
	check(game.skill_system.is_unlocked("horse") and game.skill_system.is_unlocked("artillery"), "existing horse unlock also grants artillery")
	game.skill_system.unlock_horse()
	game.skill_system.horse_unlocked = false
	game.skill_system.load_progress()
	check(game.skill_system.is_unlocked("artillery"), "saved legacy horse key preserves artillery access after reload")
	game.start_tutorial(0)
	check(game.tutorial.active and game.player_skill == "king" and game.lives == 1, "tutorial keeps explicit one-life teaching fixture")
	game.tutorial.stop()

func check_horse_attacks():
	for id in ["advance", "knight_assault", "retreat_strike"]:
		for hp in [1, 2]:
			reset("horse")
			game.player = Vector2i(4, 5)
			var target = Vector2i(6, 4) if id == "knight_assault" else Vector2i(4, 4)
			game.add_enemy("e", target, 99)
			game.enemies.back().hp = hp
			game.basic_used = true
			game.card_move_used = true
			set_hand([id])
			var deck_before = game.deck.duplicate()
			check(game.can_commit_card(0, target), id + " available after both movement quotas")
			game.play_card(0, target)
			var expected = Vector2i(4, 6) if id == "retreat_strike" else (target if hp == 1 else Vector2i(4, 5))
			check(game.player == expected and game.enemies.size() == (1 if hp == 1 else 2), id + " movement follows kill or retreat rule")
			check(game.energy == 3 - game.card_cost(id) and game.hand.is_empty() and game.deck == deck_before and game.discard == [id] and game.basic_used and game.card_move_used, id + " consumes energy without drawing or changing quotas")
			if hp == 2: check(game.enemies.back().hp == 1, id + " deals exactly one damage")
			game.undo_action()
			check(game.player == Vector2i(4, 5) and game.hand == [id] and game.energy == 3 and game.enemies.back().hp == hp, id + " undo restores position target and hand")
	reset("horse")
	game.player = Vector2i(4, 5)
	game.add_enemy("p", Vector2i(6, 4), 99)
	game.add_enemy("stake", Vector2i(5, 5), 0)
	set_hand(["knight_assault"])
	game.play_card(0, Vector2i(6, 4))
	check(game.hand == ["knight_assault"] and game.energy == 3 and game.player == Vector2i(4, 5), "blocked horse leg rejects attack without spending")
	reset("horse")
	game.player = Vector2i(4, 5)
	game.add_enemy("p", Vector2i(4, 4), 99)
	game.add_enemy("stake", Vector2i(4, 6), 0)
	set_hand(["retreat_strike"])
	game.play_card(0, Vector2i(4, 4))
	check(game.hand == ["retreat_strike"] and game.energy == 3 and game.enemies[1].hp == 1, "blocked retreat rejects before damage or cost")
	game.player = Vector2i(4, 9)
	game.add_enemy("p", Vector2i(4, 8), 99)
	check(not game.card_legal("retreat_strike", Vector2i(4, 8)), "retreat cannot leave board")
	check(not game.card_legal("advance", Vector2i(4, 6)), "attack cannot target stake")

func check_stance_quota():
	reset("artillery")
	game.player = Vector2i(4, 5)
	game.basic_move(Vector2i(4, 3))
	set_hand(["deploy", "pack"])
	game.play_card(0, game.player)
	check(game.artillery_mode == "attack" and not game.basic_legal(Vector2i(4, 2)), "deploy after march movement does not refresh free step")
	game.play_card(0, game.player)
	check(game.artillery_mode == "march" and not game.basic_legal(Vector2i(4, 1)), "pack after movement does not refresh marching quota")
	reset("artillery")
	game.artillery_mode = "attack"
	game.player = Vector2i(4, 5)
	game.add_enemy("stake", Vector2i(4, 4), 0)
	check(not game.basic_legal(Vector2i(4, 4)), "attack step cannot land on occupied square")
	for size in [Vector2(1280, 940), Vector2(480, 720), Vector2(900, 450)]:
		game.configure_layout(size)
		var rect: Rect2 = game.pack_button_rect()
		check(not rect.intersects(game.END_TURN_RECT) and not rect.intersects(game.BOARD_RECT) and not rect.intersects(game.full_hand_area()), "pack button avoids board hand and end-turn at " + str(size))
