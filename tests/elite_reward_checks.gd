extends SceneTree
# Elite rewards enlarge the offer, not the number of cards received.
const PROFILES = preload("res://start_profiles.gd")
const SIZES = [Vector2(1280, 940), Vector2(390, 844), Vector2(360, 640), Vector2(844, 390)]
var game
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("ELITE REWARD: " + label)
func _initialize(): call_deferred("run")
func unique(cards: Array) -> bool:
	var seen = {}
	for id in cards: seen[id] = true
	return seen.size() == cards.size()
func own_count(identity: String, cards: Array) -> int:
	var count = 0
	for id in cards:
		if id in PROFILES.DATA[identity].rewards: count += 1
	return count
func legal(identity: String, cards: Array) -> bool:
	for id in cards:
		if not game.CARDS.has(id) or id not in PROFILES.DATA[identity].rewards + PROFILES.COMMON: return false
	return unique(cards)
func check_draws():
	var random = RandomNumberGenerator.new();random.seed = 149
	for identity in PROFILES.DATA:
		for quota in [2, 3]:
			var valid = true
			for sample in 400:
				var cards = PROFILES.draw_rewards(identity, random, quota)
				valid = valid and cards.size() == quota + 1 and legal(identity, cards) and own_count(identity, cards) == quota
			check(valid, identity + " distinct own/common quota " + str(quota))
		check(PROFILES.draw_rewards(identity, random).size() == 3, "default normal/boss/merchant offer stays three")
		var counts = {"straight": 0, "pursuit": 0}
		for sample in 12000:
			var first: String = PROFILES.draw_rewards("horse", random, 3)[0]
			if first in counts: counts[first] += 1
		check(counts.pursuit > counts.straight * 1.75 and counts.pursuit < counts.straight * 2.25, "horse movement retains half attack-card draw weight")
		check(PROFILES.reward_weight("horse", "straight") == 1 and PROFILES.reward_weight("horse", "pursuit") == 2, "exact horse weights unchanged")
	var cards = PROFILES._draw_rewards_from_pools("horse", random, 3, ["straight", "straight", "sword", "unknown", "life", "sword_plus"], ["sword", "sword", "spear", "diagonal", "breath", "unknown"])
	check(cards.size() == 4 and legal("horse", cards) and own_count("horse", cards) == 1, "short own pool fills unique common, rejects duplicate/foreign/unknown/upgraded IDs")
	cards = PROFILES._draw_rewards_from_pools("horse", random, 3, ["straight", "pursuit", "advance", "retreat_strike"], [])
	check(cards.size() == 4 and legal("horse", cards) and own_count("horse", cards) == 4, "missing common fills from remaining own cards")
	cards = PROFILES._draw_rewards_from_pools("horse", random, 3, [], PROFILES.COMMON)
	check(cards.size() == 4 and legal("horse", cards) and own_count("horse", cards) == 0, "empty own pool fills common only")
	cards = PROFILES._draw_rewards_from_pools("horse", random, 3, ["straight", "straight"], ["sword", "sword"])
	check(cards.size() == 2 and legal("horse", cards), "total shortage returns only available distinct legal candidates")
	check(PROFILES._draw_rewards_from_pools("horse", random, 3, [], []).is_empty(), "empty pools do not draw an invalid index")
	cards = PROFILES.draw_rewards("unknown", random, 3)
	check(cards.size() == 4 and unique(cards) and cards.all(func(id): return id in PROFILES.COMMON), "unknown identity safely uses only known common cards")
func check_route_generation():
	for identity in PROFILES.DATA:
		game.player_skill = identity
		for chapter in [1, 2]:
			game.route.generate(149, chapter)
			var expected = game.route.state.duplicate(true)
			game.route.generate(149, chapter)
			check(game.route.state == expected, "same seed reproduces all fixed offers in both chapters")
			for node in game.route.state.nodes:
				var quota = 3 if node.kind == "elite" else 2
				check(node.loot.size() == quota + 1 and legal(identity, node.loot) and own_count(identity, node.loot) == quota, "node " + node.kind + " keeps correct unique reward quota")
				if node.kind == "event": check(node.offers.size() == 3 and legal(identity, node.offers) and own_count(identity, node.offers) == 2, "merchant remains two own plus one common")
func fresh_reward(size: Vector2, blocked: bool = false):
	game.tutorial.stop();game.player_skill = "king";game.new_expedition();game.configure_layout(size)
	game.route.enter(0);game.route.complete()
	var elite = -1
	for id in game.route.legal():
		if game.route.state.nodes[id].kind == "elite": elite = id;break
	check(elite >= 0, "opening fork includes optional elite")
	if elite < 0: return
	game.route.state.nodes[elite].loot = ["life", "airdrop", "blood_break", "breath"]
	if blocked:
		game.route.state.reward_debt = 1;game.route.state.pending_homework = ["sword_plus"]
	game.route.enter(elite);game.settle_victory();game.presentation.clear();game.input_lock = 0;game.navigation_lock = 0
func check_layout_and_claims():
	for size in SIZES:
		fresh_reward(size)
		var before = game.collection.duplicate()
		game.rewardui.click(game.rewardui.choice_rect(0).get_center())
		check(game.rewardui.mode == "add" and game.collection == before and game.rewards.size() == 4, "opening four-card offer awards nothing")
		for i in 4:
			var rect = game.rewardui.add_rect(i)
			check(Rect2(Vector2.ZERO, game.ui_size).encloses(rect) and not rect.intersects(game.rewardui.back_rect()), "candidate " + str(i) + " fully visible away from fixed return")
			check(game.rewardui.add_hit_index(rect.get_center()) == i, "all four candidate indices are hittable")
			for j in range(i): check(not rect.intersects(game.rewardui.add_rect(j)), "candidate faces never overlap")
			for identity in PROFILES.DATA:
				for id in PROFILES.DATA[identity].rewards + PROFILES.COMMON:
					var layout = game.rewardui.face.text_layout(game.CARDS[id], rect.size, false, game.is_consumable(id))
					check(layout.complete and layout.font_size >= 16, "legal reward text is readable without clipping: " + id)
		game.rewardui.click(game.rewardui.back_rect().get_center())
		check(game.rewardui.mode == "choice" and game.collection == before and game.phase == "reward", "return from four offers is lossless")
		for i in 4:
			fresh_reward(size);before = game.collection.duplicate();var id: String = game.rewards[i]
			game.rewardui.click(game.rewardui.choice_rect(0).get_center())
			game.rewardui.click(game.rewardui.add_rect(i).get_center())
			before.append(id)
			check(game.collection == before and game.screen == "map", "click candidate " + str(i) + " receives exactly one, including last index")
			game.choose_reward(i);game.rewardui.click(game.rewardui.add_rect(i).get_center())
			check(game.collection == before, "duplicate reward taps cannot claim twice")
			check(game.route.resume() and game.collection == before, "claimed card persists including consumable identity")
		fresh_reward(size);game.rewards = game.rewards.slice(0, 3);game.rewardui.mode = "add"
		for i in 3:
			var expected: Rect2
			if not game.mobile_layout: expected = Rect2(220 + i * 285, 310, 260, 190)
			elif game.compact_landscape: expected = Rect2(24 + i * 312, 150, 288, 180)
			else: expected = Rect2(24, 142 + i * (130 if game.ui_size.y < 700 else 150), 432, 122 if game.ui_size.y < 700 else 138)
			check(game.rewardui.add_rect(i) == expected, "normal three-candidate geometry unchanged")
func check_no_extra_rewards():
	fresh_reward(Vector2(390, 844), true)
	var before = game.collection.duplicate()
	check(game.route.rewards_blocked() and game.rewards.is_empty() and before.count("sword_plus") == 1, "homework delivers exact recorded copy and no elite choices")
	game.route.battle_victory();game.choose_reward(0);game.delete_reward(0)
	game.rewardui.click(game.rewardui.choice_rect(0).get_center());game.rewardui.click(game.rewardui.choice_rect(1).get_center())
	check(game.collection == before and not game.card_picker.active and game.rewards.is_empty(), "homework still rejects add/delete and repeated settlement")
	game.choose_reward(-1)
	check(game.screen == "map" and game.collection == before, "blocked victory advances with no extra reward")
	fresh_reward(Vector2(390, 844));game.collection = ["sword", "sword", "sword_plus"]
	game.rewardui.click(game.rewardui.choice_rect(1).get_center())
	check(game.card_picker.active and game.card_picker.indices == [0, 1, 2], "deletion eligibility still includes all physical copies")
	game.card_picker.selected = 1;game.card_picker.confirm()
	check(game.collection == ["sword", "sword_plus"] and game.screen == "map", "delete alternative remains one exact copy and no extra card")
	fresh_reward(Vector2(390, 844));before = game.collection.duplicate();game.rewardui.click(game.rewardui.choice_rect(2).get_center())
	check(game.collection == before and game.screen == "map", "skip remains no card or other extra reward")
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	check_draws();check_route_generation();check_layout_and_claims();check_no_extra_rewards()
	game.queue_free();print("ELITE REWARD RESULT %d checks, %d failures" % [checks, failures]);quit(1 if failures else 0)
