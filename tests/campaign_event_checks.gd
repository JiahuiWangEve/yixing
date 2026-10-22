extends SceneTree
const T = preload("res://../tests/route_test_helpers.gd")
# Current-version transaction regression, using disposable save storage via verify.sh.
const U = preload("res://card_upgrades.gd")
var game
var route
var checks = 0
var failures = 0
var fixture_node = -1
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
	if action == "upgrade" and route.choice_mode == "root": act("select_upgrade")
	var found = action_index(action, index, offer)
	check(found >= 0, "available action " + action)
	if found >= 0: route.resolve(found)
func confirmed(action: String, index: int = -1):
	act(action, index);act("confirm")
func win_and_return():
	game.input_lock = 0;game.navigation_lock = 0;game.debug_skip();game.choose_reward(-1)
func event_fixture(id: String, identity: String = "king"):
	fresh(identity);route.enter(0);win_and_return()
	# A real reachable node with an explicit transaction payload isolates RNG.
	fixture_node = T.enter_next(game, "event", id)
func camp_fixture():
	fresh();route.enter(0);win_and_return();fixture_node = T.enter_next(game, "camp")
func workshop_fixture():
	fresh();route.enter(0);win_and_return();fixture_node = T.enter_next(game, "workshop")
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
		var elites = 0;var event_types = []
		for node in route.state.nodes:
			if node.kind == "elite": elites += 1
			check(node.kind != "outpost", "no retired weakening event category")
			if node.kind != "event": continue
			check(node.event_id in counts, "only three approved event identities")
			counts[node.event_id] += 1
			event_types.append(node.event_id)
			check(node.offers.size() == 3 and node.offers[0] != node.offers[1] and node.offers[0] != node.offers[2] and node.offers[1] != node.offers[2], "stored merchant offers have three distinct card types")
			check(node.offers[0] in game.PROFILES.DATA[game.player_skill].rewards and node.offers[1] in game.PROFILES.DATA[game.player_skill].rewards and node.offers[2] in game.PROFILES.COMMON, "offers remain two exclusive plus one common")
		check(elites == 1, "first chapter has one optional elite")
		check(T.kind_id(route, "camp") >= 0 and T.kind_id(route, "workshop") >= 0, "final preparation offers both camp and workshop")
		for id in event_types:
			if event_types.count(id) > 1: repeated = true
	var expected = (counts.herbalist + counts.merchant + counts.manual) / 3.0
	check(expected > 0, "generated sample contains events")
	for id in counts: check(abs(counts[id] - expected) < maxf(40, expected * 0.09), "independent equal thirds distribution: " + id + "=" + str(counts[id]))
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
	check(game.collection == before and game.lives == life and route.state.current == fixture_node, "leave gives no benefit and completes node")
func check_merchant():
	for identity in ["king", "horse", "artillery"]:
		event_fixture("merchant", identity)
		var before = game.collection.duplicate();var offers = route.state.nodes[fixture_node].offers.duplicate()
		check(route.choices.size() == 4, "all three merchant offers visible before selection")
		act("select_exchange", -1, 1)
		check(game.collection == before, "selecting offer costs nothing")
		act("exchange", 0);check(game.collection == before, "choosing surrendered card remains preview")
		act("back");check(game.collection == before and route.state.nodes[fixture_node].offers == offers, "merchant cancel preserves deck and fixed offers")
		act("select_exchange", -1, 2);act("exchange", 1);route.save()
		check(route.resume() and game.collection == before and route.state.nodes[fixture_node].offers == offers and route.choice_mode == "root", "reload cancels unconfirmed trade without reroll")
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
	check(action_index("select_focus") >= 0 and action_index("select_homework") >= 0 and action_index("random_upgrade") < 0, "manual exposes focus and homework independently of upgrade eligibility")
	var before = game.collection.duplicate();act("select_focus")
	check(route.choices.size() == before.size() + 1, "focus lists all permanent copies and no generated movement")
	act("focus", 0);check(game.collection == before and route.state.reward_debt == 0, "focus preview gives neither card nor negative card")
	act("back");act("select_focus");act("focus", 4);route.save()
	check(route.resume() and game.collection == before and route.state.reward_debt == 0, "unconfirmed focus reload is lossless")
	act("select_focus");confirmed("focus", 0);before.append_array(["sword_plus", "fatigue"])
	check(game.collection == before and route.state.reward_debt == 0, "focus copies upgraded fourth same-name card plus exactly one fatigue, no reward debt")
	check(route.resume() and game.collection == before, "copy and fatigue persist together")
	route.resolve(0);undo_after_effects(game);check(game.collection == before, "duplicate click and undo cannot replay focus")
	event_fixture("manual", "artillery");game.collection = ["deploy"];route.refresh_choices();act("select_focus");confirmed("focus", 0)
	check(game.collection == ["deploy", "deploy", "fatigue"], "focus permits consumable copies")
	event_fixture("manual");game.collection = ["fatigue"];route.refresh_choices();act("select_focus");confirmed("focus", 0)
	check(game.collection == ["fatigue", "fatigue", "fatigue"], "copying fatigue grants its copy and the additional fatigue cost")
	event_fixture("manual");game.collection = ["sword_plus", "life"];route.refresh_choices();before = game.collection.duplicate()
	act("select_homework");act("homework", 0)
	check(game.collection == before and route.state.pending_homework.is_empty(), "homework preview queues nothing")
	act("back");act("select_homework");confirmed("homework", 0)
	check(game.collection == before and route.state.pending_homework == ["sword_plus"] and route.state.reward_debt == 1, "homework captures exact upgraded ID without immediate copy or fatigue")
	check(route.resume() and game.collection == before and route.state.pending_homework == ["sword_plus"], "homework selection survives resume")
	event_fixture("manual");route.state.pending_homework = ["deploy"];route.state.reward_debt = 1;act("select_homework");confirmed("homework", 0)
	check(route.state.pending_homework == ["deploy", "sword"] and route.state.reward_debt == 1, "hypothetical multiple homework jobs share next battle rather than accumulating extra skipped battles")
func check_manual_random():
	event_fixture("manual");game.collection = ["sword", "sword", "spear", "life"];route.refresh_choices()
	var counts = [0,0,0]
	for seed_number in 3000:
		route.state.nodes[fixture_node].upgrade_seed = seed_number
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
	check(action_index("random_upgrade") < 0 and action_index("disabled") >= 0 and action_index("select_focus") >= 0 and action_index("select_homework") >= 0, "no eligible upgrade disables mnemonic but copy stays valid")
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
	T.enter_next(game, "battle")
	check(game.hand.size() == 2 and not route.state.prepared, "rest gives exactly two opening cards in next battle")
	var hand = game.hand.duplicate();route.save();check(route.resume() and game.hand == hand and not route.state.prepared, "battle reload cannot consume preparation twice")
	undo_after_effects(game);check(game.hand == hand and not route.state.prepared, "opening prep cannot be undone into extra draws")
	camp_fixture();route.state.prepared = true;route.refresh_choices()
	check(action_index("prepare") == -1 and action_index("select_remove") >= 0, "prepared state visibly disables stacking, leaves removal available")
	act("leave");check(route.state.prepared, "leaving rest preserves earlier preparation")
	camp_fixture();game.collection = ["sword"];route.refresh_choices();act("select_remove");confirmed("remove", 0)
	check(game.collection.is_empty(), "existing delete-to-empty policy retained")
func check_reward_debt():
	event_fixture("manual");game.collection = ["sword_plus", "spear"];route.refresh_choices();act("select_homework");confirmed("homework", 0)
	var deck = game.collection.duplicate()
	var battle_node = T.enter_next(game, "battle");check(route.state.reward_debt == 1 and route.state.pending_homework == ["sword_plus"] and game.collection == deck, "homework copy is unavailable in next battle")
	route.save();check(route.resume() and route.state.reward_debt == 1 and game.collection == deck, "battle reload preserves pending homework")
	game.player = Vector2i(4, 9);game.enemies = [];game.add_enemy("g", Vector2i(4, 8), 3);game.enemies[0].hp = 1
	game.hand = ["sword"];game.hand_ids = [];game.energy = 3;game.input_lock = 0;game.play_card(0, Vector2i(4, 8));deck.append("sword_plus")
	check(game.phase == "reward" and route.rewards_blocked() and route.state.reward_debt == 0 and game.rewards.is_empty(), "real victory suppresses next battle reward exactly once")
	check(game.collection == deck and route.state.pending_homework.is_empty() and route.state.homework_awarded == ["sword_plus"], "real victory awards exact homework copy without ordinary rewards")
	check(not game.history.can_undo(), "victory clears undo before delivery can be replayed")
	game.choose_reward(0);game.delete_reward(0)
	check(game.collection == deck and game.screen == "game", "homework victory cannot add normal rewards or remove cards")
	game.debug_skip();route.battle_victory();check(game.collection == deck and route.state.reward_debt == 0, "repeated victory does not deliver copy twice")
	check(route.resume() and route.rewards_blocked() and game.collection == deck and route.state.homework_awarded == ["sword_plus"], "victory reload keeps delivery receipt without duplicate")
	game.choose_reward(-1);check(game.screen == "map" and route.state.current == battle_node and game.collection == deck, "homework victory still advances route")
	T.enter_next(game, "workshop");act("leave");T.enter_next(game, "elite");game.debug_skip()
	check(not route.rewards_blocked() and game.rewards.size() == 4, "immediately following second battle restores rewards")
	var reward = game.rewards[0];game.choose_reward(0);deck.append(reward)
	check(game.collection == deck, "restored elite reward is granted normally")
	# Explicitly exercise queued delivery with each tier and debug victory.
	for tier in ["battle", "elite", "boss"]:
		fresh();route.state.pending_homework = ["spear_plus", "deploy"];route.state.reward_debt = 1
		var target = T.kind_id(route, tier);T.before(route, target);route.enter(target)
		deck = game.collection.duplicate();game.debug_skip();deck.append_array(["spear_plus", "deploy"])
		check(game.collection == deck and route.state.reward_debt == 0 and route.state.pending_homework.is_empty() and route.rewards_blocked(), "debug homework delivers each queued copy once in " + tier)
		game.debug_skip();check(game.collection == deck, "duplicate debug cannot deliver again in " + tier)
		if tier == "boss":
			check(game.phase == "reward" and not route.state.done, "first boss homework receipt precedes chapter transition")
			game.choose_reward(-1)
			check(route.chapter() == 2 and game.collection == deck, "boss copied cards survive chapter transition")
		else: check(route.resume() and game.collection == deck, "debug homework reward receipt survives reload in " + tier)
func fatigue_fixture(identity: String = "king"):
	fresh(identity);route.enter(0);game.enemies = [];game.add_enemy("g", Vector2i(4,0), 9)
	game.hand = [];game.hand_ids = [];game.deck = [];game.discard = [];game.energy = 3;game.input_lock = 0;game.navigation_lock = 0
func check_fatigue():
	for identity in ["king", "horse", "artillery"]:
		check("fatigue" not in game.PROFILES.DATA[identity].deck and "fatigue" not in game.PROFILES.DATA[identity].rewards and "fatigue" not in game.PROFILES.COMMON, "fatigue absent from starter/reward pools for " + identity)
	check(game.CARDS.fatigue[1] == 2 and "fatigue" in game.UNTARGETED and not game.is_consumable("fatigue"), "fatigue is targetless cost-two non-exhaust card")
	for initial in [0,1,3]:
		fatigue_fixture();game.energy = initial;game.deck = ["fatigue"];game.draw_card()
		check(game.energy == maxi(0, initial - 1) and game.hand == ["fatigue"], "fatigue draw reduces current energy with zero floor from " + str(initial))
	fatigue_fixture();game.deck = ["fatigue", "fatigue", "fatigue", "fatigue"]
	for i in 4: game.draw_card()
	check(game.energy == 0 and game.hand.size() == 4, "each fatigue copy triggers immediately, never negative")
	game.hand.append("breath");game.hand_ids = [];game.input_lock = 0;game.play_card(4, game.player)
	check(game.energy == 1, "zero-energy skipped fatigue creates no debt against later energy gain")
	fatigue_fixture();game.energy = 3;game.hand = ["fatigue"];game.hand_ids = [];game.play_card(0, game.player)
	check(game.energy == 1 and game.hand.is_empty() and game.discard == ["fatigue"], "paying two removes fatigue from hand into discard, not exhaust")
	check(undo_after_effects(game) and game.energy == 3 and game.hand == ["fatigue"] and game.discard.is_empty(), "fatigue play undo restores energy and exact card zones")
	game.input_lock = 0;game.play_card(0, game.player);game.draw_card()
	check(game.energy == 0 and game.hand == ["fatigue"] and game.discard.is_empty(), "same-turn recycled fatigue triggers again on redraw")
	fatigue_fixture();game.energy = 1;game.hand = ["fatigue"];game.hand_ids = [];game.play_card(0, game.player)
	check(game.energy == 1 and game.hand == ["fatigue"] and game.discard.is_empty(), "insufficient energy cannot play fatigue")
	fatigue_fixture();game.hand = ["fatigue", "fatigue", "sword"];game.hand_ids = [];game.energy = 0;game.end_turn()
	check(game.energy == 1 and game.hand == ["fatigue", "fatigue", "sword"], "retained fatigue deducts once each at next player turn")
	var after = game.history.capture();check(undo_after_effects(game) and game.energy == 0, "turn undo restores pre-fatigue state")
	game.end_turn();check(game.history.capture() == after, "replayed turn fatigue deduction is deterministic")
	game.hand = ["fatigue", "fatigue", "fatigue", "fatigue"];game.hand_ids = [];game.input_lock = 0;game.end_turn()
	check(game.energy == 0, "four retained fatigue cards cannot make next-turn energy negative")
	fatigue_fixture();game.hand = ["fatigue"];game.hand_ids = [];game.energy = 0;game.tuna_turns = 1;game.end_turn()
	check(game.energy == 3, "fatigue deducts after boosted turn energy is established")
	fatigue_fixture("artillery");game.hand = ["deploy"];game.hand_ids = [];game.deck = ["fatigue", "sword", "fatigue"];game.energy = 3;game.play_card(0, game.player)
	check(game.artillery_mode == "attack" and game.hand.size() == 3 and game.energy == 0 and game.hand.count("fatigue") == 2, "deploy three-card draw charges each fatigue immediately after deploy cost")
	var exact = game.history.capture();route.save();check(route.resume() and game.history.capture() == exact, "fatigue hand and energy resume without charging draw again")
	fatigue_fixture();game.hand = ["fatigue", "sword", "sword", "sword", "sword", "sword", "sword"];game.hand_ids = [];game.phase = "discard";game.energy = 2;game.discard_hand(0)
	check(game.energy == 2 and "fatigue" not in game.hand and game.discard == ["fatigue"], "forced discard removes fatigue without refund or extra cost")
func check_save_validation():
	fresh();var good = ConfigFile.new();check(good.load(route.SAVE) == OK, "current schema snapshot written")
	check(good.get_value("run", "version") == 6, "event state uses explicit version six envelope")
	var original_route = route.state.duplicate(true);var original_battle = game.history.capture()
	for key in ["reward_debt", "reward_blocked", "victory_recorded", "pending_homework", "homework_awarded"]:
		var changed = original_route.duplicate(true);changed.erase(key)
		var bad = ConfigFile.new();bad.parse(good.encode_to_text());bad.set_value("run", "route", changed);bad.save(route.SAVE)
		check(not route.resume() and route.state == original_route and game.history.capture() == original_battle, "missing event accounting field rejected atomically: " + key)
	var legacy = ConfigFile.new();legacy.parse(good.encode_to_text());legacy.set_value("run", "version", 5);legacy.save(route.SAVE)
	check(not route.resume() and route.state == original_route, "old demo map schema is rejected without modifying live state")
	good.save(route.SAVE);check(route.resume(), "valid save survives rejection tests")
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.settings.set_debug_mode(true);game.set_process(false);route = game.route
	check_generation();check_upgrade_registry();check_herbalist();check_merchant();check_manual_copy();check_manual_random();check_rest();check_reward_debt();check_fatigue();check_save_validation()
	print("CAMPAIGN EVENT RESULT ", checks, " checks, ", failures, " failures")
	game.free();quit(1 if failures else 0)

# These rules tests model the completed-animation boundary before user input.
func undo_after_effects(owner) -> bool:
	owner.input_lock = 0;owner.navigation_lock = 0;owner.presentation.clear()
	return owner.undo_action()
