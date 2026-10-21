extends SceneTree
# Current-version transaction regression, using disposable save storage via verify.sh.
const U = preload("res://card_upgrades.gd")
var game
var route
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("CAMPAIGN EVENT: " + label)
func _initialize(): call_deferred("run")
func fresh(identity: String = "king"):
	game.player_skill = identity;game.new_expedition()
func action_index(action: String, index: int = -1, offer: int = -1) -> int:
	for n in route.choices.size():
		var c = route.choices[n]
		if c.action == action and (index < 0 or c.get("index", -1) == index) and (offer < 0 or c.get("offer", -1) == offer): return n
	return -1
func act(action: String, index: int = -1, offer: int = -1):
	var found = action_index(action, index, offer)
	check(found >= 0, "available action " + action)
	if found >= 0: route.resolve(found)
func confirmed(action: String, index: int = -1):
	act(action, index);act("confirm")
func win_and_return():
	game.input_lock = 0;game.navigation_lock = 0;game.debug_skip();game.choose_reward(-1)
func event_fixture(id: String, identity: String = "king"):
	fresh(identity);route.enter(0);win_and_return()
	# Fixed valid node identity, independent from probability tests below.
	route.state.nodes[1].event_id = id;route.enter(1)
func camp_fixture():
	fresh();route.enter(0);win_and_return();route.enter(3)
func workshop_fixture():
	camp_fixture();act("leave");route.enter(5);win_and_return();route.enter(6)
func deck_counts(cards: Array) -> Dictionary:
	var result = {}
	for card in cards: result[card] = result.get(card, 0) + 1
	return result
func check_generation():
	var counts = {"herbalist": 0, "merchant": 0, "manual": 0}
	var repeated = false
	for seed_number in 3000:
		route.generate(seed_number)
		var before = route.state.duplicate(true)
		if seed_number < 100:
			route.generate(seed_number)
			check(route.state == before, "seed reproduces topology, identity, offers and upgrade seed")
		var elites = 0
		for node in route.state.nodes:
			if node.kind == "elite": elites += 1
			check(node.kind != "outpost", "no retired weakening event category")
			if node.kind != "event": continue
			check(node.event_id in counts, "only three approved event identities")
			counts[node.event_id] += 1
			check(node.offers.size() == 3 and node.offers[0] != node.offers[1] and node.offers[0] != node.offers[2] and node.offers[1] != node.offers[2], "stored merchant offers have three distinct card types")
			check(node.offers[0] in game.PROFILES.DATA[game.player_skill].rewards and node.offers[1] in game.PROFILES.DATA[game.player_skill].rewards and node.offers[2] in game.PROFILES.COMMON, "offers remain two exclusive plus one common")
		check(elites == 2 and route.state.nodes[5].kind == "battle", "removed outpost does not inflate elite density")
		check(route.state.nodes[3].kind == "camp" and route.state.nodes[6].kind == "workshop", "old functionality positions retain their new names")
		if route.state.nodes[1].event_id == route.state.nodes[10].event_id: repeated = true
	for id in counts: check(abs(counts[id] - 2000) < 180, "independent equal thirds distribution: " + id + "=" + str(counts[id]))
	check(repeated, "independent sampling permits repeated event types")
	check(route.SYMBOLS.elite.resource_path.ends_with("outpost.svg") and route.TITLES.elite == "关隘", "elite uses gate image and label")
	check(route.SYMBOLS.battle.resource_path.ends_with("battle.svg"), "ordinary battle icon unchanged")
	print("EVENT DISTRIBUTION ", counts)
func check_upgrade_registry():
	check(U.can_upgrade("sword") and U.upgraded_id("sword") == "sword_plus", "short sword registry entry")
	check(U.can_upgrade("spear") and U.upgraded_id("spear") == "spear_plus", "long spear registry entry")
	for id in ["sword_plus", "spear_plus", "deploy", "life", "unknown_future_card"]:
		check(not U.can_upgrade(id) and U.upgraded_id(id) == id, "unsupported upgrade is a no-op: " + id)
	check(U.eligible_indices(["sword", "sword", "life", "spear_plus", "spear"]) == [0,1,4], "eligibility retains physical duplicate indices")
	workshop_fixture();game.collection = ["sword", "sword", "spear", "life"];route.refresh_choices()
	var before = game.collection.duplicate();act("upgrade", 1)
	check(game.collection == before, "workshop preview is not an upgrade")
	act("back");check(game.collection == before, "workshop cancel is lossless")
	confirmed("upgrade", 1)
	check(game.collection == ["sword", "sword_plus", "spear", "life"], "workshop upgrades exactly selected physical card")
	check(route.resume() and game.collection[1] == "sword_plus", "workshop result resumes exactly")
func check_herbalist():
	event_fixture("herbalist");game.lives = 4;route.refresh_choices()
	act("heal");check(game.lives == 4, "heal preview does not mutate health")
	act("back");check(game.lives == 4, "heal cancellation does not mutate health")
	confirmed("heal");check(game.lives == 5 and game.screen == "map", "heal adds exactly one up to cap")
	route.resolve(0);check(game.lives == 5, "duplicate event click cannot heal again")
	check(route.resume() and game.lives == 5, "heal persists across reload")
	event_fixture("herbalist");game.lives = 5;route.refresh_choices()
	check(action_index("heal") == -1 and action_index("disabled") >= 0 and action_index("breath") >= 0, "full-health event disables heal but keeps card choice")
	var before = game.collection.duplicate();act("disabled")
	check(game.lives == 5 and game.collection == before and game.screen == "route_choice", "disabled full-health action cannot mutate")
	confirmed("breath");before.append("breath")
	check(game.collection == before and game.lives == 5, "herbalist supplies one breath without heal")
	event_fixture("herbalist");var life = game.lives;before = game.collection.duplicate();act("leave")
	check(game.collection == before and game.lives == life and route.state.current == 1, "leave gives no benefit and completes node")
func check_merchant():
	for identity in ["king", "horse", "artillery"]:
		event_fixture("merchant", identity)
		var before = game.collection.duplicate();var offers = route.state.nodes[1].offers.duplicate()
		check(route.choices.size() == 4, "all three merchant offers visible before selection")
		act("select_exchange", -1, 1)
		check(game.collection == before, "selecting offer costs nothing")
		act("exchange", 0);check(game.collection == before, "choosing surrendered card remains preview")
		act("back");check(game.collection == before and route.state.nodes[1].offers == offers, "merchant cancel preserves deck and fixed offers")
		act("select_exchange", -1, 2);act("exchange", 1);route.save()
		check(route.resume() and game.collection == before and route.state.nodes[1].offers == offers and route.choice_mode == "root", "reload cancels unconfirmed trade without reroll")
		act("select_exchange", -1, 2);act("exchange", 1);act("confirm")
		before[1] = offers[2]
		check(game.collection == before and game.collection.size() == 4, "confirmed trade replaces one card without changing count")
		route.resolve(0);check(game.collection == before, "trade cannot be repeated by stale click")
		check(route.resume() and game.collection == before, "trade persists atomically")
	event_fixture("merchant");game.collection = [];route.refresh_choices();act("select_exchange", -1, 0)
	check(route.choices.size() == 1 and route.choices[0].action == "back", "empty deck has no generated free movement card to trade")
	act("back");act("leave");check(game.collection.is_empty(), "empty merchant can leave safely")
func check_manual_copy():
	event_fixture("manual");game.collection = ["sword_plus", "sword_plus", "sword_plus", "deploy", "spear_plus"];route.refresh_choices()
	var before = game.collection.duplicate();act("select_copy")
	check(route.choices.size() == before.size() + 1, "copy lists every permanent physical card and no free movement")
	act("copy", 0);check(game.collection == before and route.state.reward_debt == 0, "copy preview gives neither card nor debt")
	act("back");act("select_copy");act("copy", 4);route.save()
	check(route.resume() and game.collection == before and route.state.reward_debt == 0, "unconfirmed copy reload is lossless")
	act("select_copy");confirmed("copy", 0);before.append("sword_plus")
	check(game.collection == before and route.state.reward_debt == 2, "copy preserves upgrade and allows fourth same-name copy")
	check(route.resume() and game.collection == before and route.state.reward_debt == 2, "card and penalty persist together")
	route.resolve(0);game.undo_action()
	check(game.collection == before and route.state.reward_debt == 2, "duplicate click and combat undo cannot replay event")
	event_fixture("manual", "artillery");game.collection = ["deploy"];route.state.reward_debt = 1;route.refresh_choices()
	act("select_copy");confirmed("copy", 0)
	check(game.collection == ["deploy", "deploy"] and route.state.reward_debt == 3, "consumable copy allowed and outstanding debt accumulates +2")
func check_manual_random():
	event_fixture("manual");game.collection = ["sword", "sword", "spear", "life"];route.refresh_choices()
	var counts = [0,0,0]
	for seed_number in 3000:
		route.state.nodes[1].upgrade_seed = seed_number
		var index = route.random_upgrade_index()
		check(index >= 0 and index < 3, "random upgrade never selects unsupported card")
		counts[index] += 1
	for count in counts: check(abs(count - 1000) < 120, "uniform physical-copy upgrade distribution")
	var before = game.collection.duplicate();var target = route.random_upgrade_index()
	act("random_upgrade");check(game.collection == before and route.random_upgrade_index() == target, "random preview keeps hidden fixed result and no mutation")
	act("back");check(route.random_upgrade_index() == target, "cancel cannot reroll upgrade target")
	route.save();check(route.resume() and route.random_upgrade_index() == target, "reload retains random upgrade seed and target")
	confirmed("random_upgrade");before[target] = U.upgraded_id(before[target])
	check(game.collection == before and route.state.reward_debt == 0, "mnemonic randomly upgrades exactly one eligible copy without penalty")
	event_fixture("manual");game.collection = ["sword_plus", "deploy", "life"];route.refresh_choices()
	check(action_index("random_upgrade") < 0 and action_index("disabled") >= 0 and action_index("select_copy") >= 0, "no eligible upgrade disables mnemonic but copy stays valid")
	act("leave");check(game.screen == "map", "manual with no eligible upgrades can leave")
	print("UPGRADE PHYSICAL COPY DISTRIBUTION ", counts)
func check_rest():
	camp_fixture();var before = game.collection.duplicate();act("select_remove");act("remove", 1)
	check(game.collection == before, "rest deletion requires confirmation")
	act("back");check(game.collection == before, "rest deletion cancel keeps card")
	act("select_remove");confirmed("remove", 1);before.remove_at(1)
	check(game.collection == before and not route.state.prepared, "lighten load deletes just one permanent card")
	camp_fixture();confirmed("prepare")
	check(route.state.prepared and route.resume() and route.state.prepared, "preparation survives map resume")
	route.enter(5)
	check(game.hand.size() == 2 and not route.state.prepared, "rest gives exactly two opening cards in next battle")
	var hand = game.hand.duplicate();route.save();check(route.resume() and game.hand == hand and not route.state.prepared, "battle reload cannot consume preparation twice")
	game.undo_action();check(game.hand == hand and not route.state.prepared, "opening prep cannot be undone into extra draws")
	camp_fixture();route.state.prepared = true;route.refresh_choices()
	check(action_index("prepare") == -1 and action_index("select_remove") >= 0, "prepared state visibly disables stacking, leaves removal available")
	act("leave");check(route.state.prepared, "leaving rest preserves earlier preparation")
	camp_fixture();game.collection = ["sword"];route.refresh_choices();act("select_remove");confirmed("remove", 0)
	check(game.collection.is_empty(), "existing delete-to-empty policy retained")
func check_reward_debt():
	event_fixture("manual");act("select_copy");confirmed("copy", 0)
	var deck = game.collection.duplicate()
	route.enter(4);check(route.state.reward_debt == 2, "entering battle does not spend reward debt")
	route.save();check(route.resume() and route.state.reward_debt == 2, "active battle reload keeps debt")
	# Real card kill, rather than only debug skip.
	game.player = Vector2i(4, 9);game.enemies = [];game.add_enemy("g", Vector2i(4, 8), 3);game.enemies[0].hp = 1
	game.hand = ["sword"];game.hand_ids = [];game.energy = 3;game.input_lock = 0;game.play_card(0, Vector2i(4, 8))
	check(game.phase == "reward" and route.rewards_blocked() and route.state.reward_debt == 1 and game.rewards.is_empty(), "normal victory suppresses reward and spends one debt")
	check(not game.history.can_undo(), "victory clears undo before penalty can be rewound")
	game.choose_reward(0);game.delete_reward(0)
	check(game.collection == deck and game.screen == "game", "blocked victory cannot add or remove cards through direct handlers")
	game.debug_skip();route.battle_victory()
	check(route.state.reward_debt == 1, "repeated victory cannot spend debt twice")
	check(route.resume() and route.rewards_blocked() and route.state.reward_debt == 1, "blocked victory reload persists exact debt and suppression")
	game.choose_reward(-1);check(game.screen == "map" and route.state.current == 4 and game.collection == deck, "blocked victory still advances route")
	route.enter(6);act("leave");route.enter(9)
	check(game.enemies[0].hp == 5 and route.state.reward_debt == 1, "elite encounter preserves five-health general and outstanding penalty")
	game.debug_skip();check(route.rewards_blocked() and route.state.reward_debt == 0 and game.rewards.is_empty(), "debug-skip elite victory spends second penalty without prize")
	game.delete_reward(0);check(game.collection == deck, "second blocked battle cannot use delete reward loophole")
	game.choose_reward(-1);route.enter(11);game.debug_skip()
	check(not route.rewards_blocked() and game.rewards.size() == 3, "third battle restores fixed normal rewards")
	var reward = game.rewards[0];game.choose_reward(0);deck.append(reward)
	check(game.collection == deck and route.state.current == 11, "restored reward is actually granted")
	route.enter(14);act("leave");route.state.reward_debt = 2;route.enter(15)
	check(game.enemies[0].hp == 9 and route.state.reward_debt == 2, "boss health stays nine and entering costs no debt")
	game.debug_skip();check(game.phase == "win" and route.state.done and route.state.reward_debt == 1 and route.rewards_blocked(), "boss victory consumes one debt while still completing chapter")
	game.debug_skip();check(route.state.reward_debt == 1, "duplicate boss debug skip cannot consume extra debt")
func check_save_validation():
	fresh();var good = ConfigFile.new();check(good.load(route.SAVE) == OK, "current schema snapshot written")
	check(good.get_value("run", "version") == 4, "event state uses explicit version four envelope")
	var original_route = route.state.duplicate(true);var original_battle = game.history.capture()
	for key in ["reward_debt", "reward_blocked", "victory_recorded"]:
		var changed = original_route.duplicate(true);changed.erase(key)
		var bad = ConfigFile.new();bad.parse(good.encode_to_text());bad.set_value("run", "route", changed);bad.save(route.SAVE)
		check(not route.resume() and route.state == original_route and game.history.capture() == original_battle, "missing event accounting field rejected atomically: " + key)
	var legacy = ConfigFile.new();legacy.parse(good.encode_to_text());legacy.set_value("run", "version", 3);legacy.save(route.SAVE)
	check(not route.resume() and route.state == original_route, "old demo map schema is rejected without modifying live state")
	good.save(route.SAVE);check(route.resume(), "valid save survives rejection tests")
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);route = game.route
	check_generation();check_upgrade_registry();check_herbalist();check_merchant();check_manual_copy();check_manual_random();check_rest();check_reward_debt();check_save_validation()
	print("CAMPAIGN EVENT RESULT ", checks, " checks, ", failures, " failures")
	game.free();quit(1 if failures else 0)
