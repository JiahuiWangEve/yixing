extends SceneTree
# v0.8.0 behavior, persistence, save-isolation and card-layout regressions.
# Always run with disposable user:// storage; scripts/verify.sh supplies it.
const R = preload("res://rules.gd")
const NEW_FIELDS = ["active_displacements", "shield_charges", "pending_bleeds", "next_enemy_uid", "reload_ready"]
const RETIRED = ["push", "stun", "swap"]
var game
var checks = 0
var failures = 0

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("CARD REBALANCE: " + label)
	else: print("PASS ", label)

func _initialize(): call_deferred("run")

func make_game():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)

func fresh(identity: String = "king", expedition: bool = false):
	game.player_skill = identity
	if expedition:
		game.new_expedition()
		game.route.enter(0)
	else: game.new_run()
	game.enemies = []
	game.add_enemy("g", Vector2i(4, 0), 99)
	game.enemies[0].hp = 99
	game.player = Vector2i(4, 5)
	game.lives = 5
	game.deck = ["sword", "spear", "diagonal", "sword", "spear", "sword", "sword", "spear"]
	game.discard = [];game.hand = [];game.hand_ids = []
	game.energy = 3;game.phase = "play"
	game.input_lock = 0;game.navigation_lock = 0

func hand(cards: Array, energy: int = 3):
	game.hand = cards.duplicate();game.hand_ids = []
	game.sync_hand_ids();game.energy = energy
	game.input_lock = 0;game.navigation_lock = 0

func enemy(kind: String, position: Vector2i, hp: int = 5, cd: int = 99) -> Dictionary:
	game.add_enemy(kind, position, cd)
	game.enemies.back().hp = hp
	game.enemies.back().max_hp = hp
	return game.enemies.back()

func uid_index(uid: int) -> int:
	for i in game.enemies.size():
		if int(game.enemies[i].get("uid", -1)) == uid: return i
	return -1

func no_retired(cards: Array) -> bool:
	for id in cards:
		if id in RETIRED: return false
	return true

func exact_cards(actual: Array, expected: Array) -> bool:
	var a = actual.duplicate();var b = expected.duplicate();a.sort();b.sort()
	return a == b

func check_profiles():
	var initial = {
		"king": ["sword", "sword", "spear", "life"],
		"horse": ["sword", "sword", "spear", "advance"],
		"artillery": ["sword", "stake", "cannon_shot", "deploy"]
	}
	for identity in initial:
		game.player_skill = identity;game.new_expedition()
		check(exact_cards(game.collection, initial[identity]) and game.hand.is_empty(), identity + " exact four-card collection and empty opening hand")
		var own: Array = game.PROFILES.DATA[identity].rewards
		var common: Array = game.PROFILES.COMMON
		var bad = false
		for node in game.route.state.nodes:
			var unique = {};var dedicated = 0;var shared = 0
			for card in node.loot:
				unique[card] = true
				if card in own: dedicated += 1
				if card in common: shared += 1
			if node.loot.size() != 3 or unique.size() != 3 or dedicated != 2 or shared != 1 or not no_retired(node.loot): bad = true
		check(not bad, identity + " route loot has two distinct identity cards and one common without retired cards")
		var state = game.route.state.duplicate(true)
		game.route.generate(game.seed_value)
		check(game.route.state == state, identity + " weighted route generation stays seeded and deterministic")
	fresh("horse")
	var frequency = {}
	for id in game.PROFILES.DATA.horse.rewards: frequency[id] = 0
	game.rng.seed = 137907
	for sample in 2400:
		game.roll_rewards()
		for id in game.rewards:
			if frequency.has(id): frequency[id] += 1
	var ordinary_total = 0
	for id in frequency:
		if id != "straight": ordinary_total += frequency[id]
	var ordinary_average = float(ordinary_total) / (frequency.size() - 1)
	check(frequency.straight > ordinary_average * 0.38 and frequency.straight < ordinary_average * 0.75, "straight has half-weight rarity, rather than equal weighting or exclusion")
	for id in RETIRED: check(not game.CARDS.has(id), id + " is removed from the demo card registry")
	check(not game.CARDS.has("pierce_plus") and not game.CARDS.has("sweep_plus"), "unused compatibility-only upgrades are absent")
	check(game.CARDS.pierce[0] == "流血" and game.card_cost("pierce") == 1, "pierce internal id displays bleed and costs one")
	check(game.card_cost("guard") == 2 and game.is_consumable("guard"), "guard costs two and exhausts")
	check(game.card_cost("suppress") == 3 and not game.is_consumable("suppress"), "suppress costs three and recycles")
	check(game.card_cost("chain_assault") == 2 and game.card_cost("permanent_stake") == 1 and game.is_consumable("permanent_stake"), "chain costs two; permanent stake costs one and exhausts")
	check(game.card_cost("reload") == 1 and not game.is_consumable("reload"), "reload costs one and recycles")

func check_guard():
	fresh();enemy("p", Vector2i(4, 4));hand(["guard"])
	var position = game.player;var cards = game.deck.duplicate()
	game.play_card(0, game.player)
	check(game.shield_charges == 1 and game.energy == 1 and game.discard.is_empty(), "guard arms one shield and exhausts")
	game.end_turn()
	check(game.lives == 5 and game.player == position and game.deck == cards and game.hand.is_empty(), "shield blocks a real attack without recoil, life loss, or draw")
	check(game.shield_charges == 0, "shield is consumed by the blocked attack")
	game.undo_action()
	check(game.shield_charges == 1 and game.turn == 1 and game.lives == 5, "undo enemy phase restores shield")
	game.undo_action()
	check(game.shield_charges == 0 and game.hand == ["guard"] and game.energy == 3, "undo guard restores exhausted card and energy")
	fresh();enemy("r", Vector2i(4, 3));enemy("r", Vector2i(2, 5));hand(["guard"])
	game.play_card(0, game.player);game.end_turn()
	check(game.lives == 4 and game.player != Vector2i(4, 5) and game.shield_charges == 0, "two attackers use one shield then cause one ordinary hit and recoil")
	fresh();hand(["guard"]);game.play_card(0, game.player);game.end_turn()
	check(game.shield_charges == 0 and game.lives == 5, "unused shield expires at next player start")
	enemy("p", game.player + Vector2i(0, -1));game.end_turn()
	check(game.lives == 4, "expired shield cannot absorb a later-turn hit")
	fresh();hand(["guard"], 1);game.play_card(0, game.player)
	check(game.shield_charges == 0 and game.hand == ["guard"] and game.energy == 1, "unaffordable guard is inert")

func check_bleed():
	fresh();var victim = enemy("e", Vector2i(4, 4), 5, 1)
	victim.intent = Vector2i(6, 2)
	var uid = int(victim.uid)
	hand(["pierce"]);game.play_card(0, Vector2i(4, 4))
	check(victim.hp == 5 and game.pending_bleeds.size() == 1 and game.energy == 2, "bleed queues two end-turn ticks without immediate damage")
	check(int(game.pending_bleeds[0].enemy_uid) == uid and int(game.pending_bleeds[0].amount) == 2, "bleed records stable enemy identity and remaining amount")
	game.end_turn()
	check(uid_index(uid) >= 0 and game.enemies[uid_index(uid)].pos == Vector2i(6, 2) and game.enemies[uid_index(uid)].hp == 4, "first end-turn tick deals one and surviving target may still move")
	check(game.pending_bleeds.size() == 1 and int(game.pending_bleeds[0].amount) == 1 and game.turn == 2, "next player start retains one damage instead of ticking twice")
	game.clear_effects();var after_first = game.history.capture()
	game.end_turn()
	check(game.enemies[uid_index(uid)].hp == 3 and game.pending_bleeds.is_empty() and game.turn == 3, "second end-turn tick follows moving uid and exhausts bleed")
	game.undo_action()
	check(game.history.capture() == after_first, "undo second tick exactly restores remaining tick and moved enemy")
	game.undo_action()
	check(game.pending_bleeds.size() == 1 and int(game.pending_bleeds[0].amount) == 2 and game.enemies[uid_index(uid)].hp == 5 and game.enemies[uid_index(uid)].pos == Vector2i(4, 4), "undo first tick restores full duration damage and movement")
	game.undo_action()
	check(game.pending_bleeds.is_empty() and game.hand == ["pierce"] and game.energy == 3, "undo bleed restores card and clears scheduled damage")
	fresh();victim = enemy("e", Vector2i(4, 4), 5)
	hand(["pierce", "pierce"]);game.play_card(0, victim.pos);game.play_card(0, victim.pos);game.end_turn()
	check(victim.hp == 3 and game.pending_bleeds.size() == 2 and game.pending_bleeds[0].amount == 1 and game.pending_bleeds[1].amount == 1, "two applications each tick once at current turn end")
	game.end_turn()
	check(victim.hp == 1 and game.pending_bleeds.is_empty(), "two applications finish their other two damage next turn end")
	fresh();victim = enemy("e", Vector2i(4, 4), 5)
	game.queue_bleed(1, 1);game.queue_bleed(1, 2);game.end_turn()
	check(victim.hp == 3 and game.pending_bleeds.size() == 1 and game.pending_bleeds[0].amount == 1, "single-tick legacy amount expires independently of two-tick application")
	game.end_turn();check(victim.hp == 2 and game.pending_bleeds.is_empty(), "mixed durations never repeat expired application")
	fresh();victim = enemy("e", Vector2i(4, 4), 5)
	hand(["pierce"]);game.play_card(0, victim.pos);game.end_turn()
	hand(["pierce"]);game.play_card(0, victim.pos);game.end_turn()
	check(victim.hp == 2 and game.pending_bleeds.size() == 1 and game.pending_bleeds[0].amount == 1, "staggered applications keep their own two ending windows")
	game.end_turn();check(victim.hp == 1 and game.pending_bleeds.is_empty(), "only newer staggered application ticks on third ending")
	fresh();victim = enemy("e", Vector2i(4, 4), 1);uid = victim.uid
	hand(["pierce", "sword"]);game.play_card(0, victim.pos);game.play_card(0, victim.pos)
	var replacement = enemy("e", Vector2i(4, 4), 5)
	check(replacement.uid != uid, "replacement at same cell receives a different enemy uid")
	game.end_turn()
	check(replacement.hp == 5 and game.pending_bleeds.is_empty(), "dead target bleed never transfers to replacement or stale array index")
	fresh();victim = enemy("e", Vector2i(4, 4), 1);var later = enemy("e", Vector2i(5, 5), 5)
	hand(["pierce", "sword"]);game.play_card(0, later.pos);game.play_card(0, victim.pos);game.end_turn()
	check(later.hp == 4 and game.pending_bleeds.size() == 1 and game.pending_bleeds[0].enemy_uid == later.uid, "array removal before first tick preserves later target uid")
	game.end_turn();check(later.hp == 3 and game.pending_bleeds.is_empty(), "remaining tick stays on later target after array removal")
	fresh();victim = enemy("e", Vector2i(4, 4), 1);later = enemy("e", Vector2i(5, 5), 5)
	game.queue_bleed(1, 2);game.queue_bleed(2, 2);game.end_turn()
	check(uid_index(victim.uid) == -1 and later.hp == 4 and game.pending_bleeds.size() == 1 and game.pending_bleeds[0].enemy_uid == later.uid, "death during bleed iteration neither skips nor retargets following application")
	game.end_turn();check(later.hp == 3 and game.pending_bleeds.is_empty(), "surviving application finishes after another bleeding target dies")

func check_bleed_phase_order():
	fresh();var victim = enemy("p", Vector2i(4, 4), 1, 1);var uid = victim.uid
	game.lives = 1;game.shield_charges = 1;game.queue_bleed(1, 2)
	game.clear_effects();game.end_turn()
	var attacks = 0;var movements = 0
	for fx in game.effects:
		if fx.kind in ["player_hit", "guard"]: attacks += 1
		if fx.kind == "move" and fx.get("piece", {}).get("uid", -1) == uid: movements += 1
	check(uid_index(uid) == -1 and game.lives == 1 and game.phase == "play" and game.pending_bleeds.is_empty(), "first tick kills adjacent attacker before it can hurt player")
	check(attacks == 0 and movements == 0, "bleed-killed enemy neither attacks into shield nor moves")
	fresh();victim = enemy("e", Vector2i(4, 4), 1, 1);uid = victim.uid
	game.queue_bleed(1, 2);game.clear_effects();game.end_turn();movements = 0
	for fx in game.effects:
		if fx.kind == "move" and fx.get("piece", {}).get("uid", -1) == uid: movements += 1
	check(uid_index(uid) == -1 and victim.pos == Vector2i(4, 4) and movements == 0, "lethal tick happens before a ready nonattacker's movement")
	fresh();victim = enemy("p", Vector2i(4, 4), 2, 99);uid = victim.uid
	game.queue_bleed(1, 2);game.end_turn()
	check(victim.hp == 1 and game.lives == 4 and game.turn == 2, "nonlethal first tick still allows ordinary enemy attack")
	game.player = Vector2i(4, 5);game.end_turn()
	check(uid_index(uid) == -1 and game.lives == 4 and game.turn == 3, "second tick kills before next enemy attack")
	fresh();game.player = Vector2i(4, 1);game.enemies[0].hp = 2;game.lives = 2
	hand(["pierce"]);game.play_card(0, Vector2i(4, 0))
	check(game.phase == "play" and game.enemies[0].hp == 2, "bleeding general does not grant victory when card is played")
	game.end_turn()
	check(game.phase == "play" and game.enemies[0].hp == 1 and game.lives == 1 and game.turn == 2, "general survives first tick and attacks before second player turn")
	game.end_turn()
	check(game.phase == "reward" and game.lives == 1 and game.turn == 2 and game.pending_bleeds.is_empty(), "second-tick general kill settles victory before attacks or turn increment")
	fresh();game.player = Vector2i(4, 1);game.enemies[0].hp = 2;game.lives = 1
	hand(["pierce"]);game.play_card(0, Vector2i(4, 0));game.end_turn()
	check(game.phase == "dead" and game.enemies[0].hp == 1 and game.pending_bleeds.is_empty(), "lethal enemy attack after first tick cancels remaining bleed")
	game.end_turn();check(game.phase == "dead" and game.enemies[0].hp == 1, "cancelled second tick cannot revive a dead player through victory")
	fresh();game.player = Vector2i(4, 1);game.enemies[0].hp = 1;game.lives = 1
	victim = enemy("p", Vector2i(0, 0), 5, 1);game.queue_bleed(0, 2);game.queue_bleed(1, 2)
	game.end_turn()
	check(game.phase == "reward" and game.lives == 1 and game.turn == 1 and victim.hp == 5 and victim.pos == Vector2i(0, 0), "first-tick general kill stops remaining damage and entire enemy phase")
	fresh();game.stage = 6;game.player = Vector2i(4, 1);game.enemies[0].hp = 2
	hand(["pierce", "guard"]);game.play_card(0, Vector2i(4, 0));game.play_card(0, game.player);game.end_turn()
	check(game.phase == "play" and game.enemies[0].hp == 1 and game.lives == 5 and game.shield_charges == 0, "shield protects first ending while final general survives one bleed tick")
	game.end_turn();check(game.phase == "win" and game.lives == 5 and game.turn == 2, "second tick produces final victory before another enemy phase")

func check_displacements():
	fresh();check(game.active_displacements == 0, "new battle starts with zero active displacements")
	game.basic_move(Vector2i(4, 4))
	check(game.active_displacements == 1, "successful free movement counts once")
	game.basic_move(Vector2i(3, 4));check(game.active_displacements == 1, "rejected second free move does not count")
	hand(["straight", "straight"]);game.play_card(0, Vector2i(4, 2))
	check(game.active_displacements == 2, "two-cell paid movement counts once rather than by distance")
	game.play_card(0, Vector2i(3, 2));check(game.active_displacements == 2, "rejected paid movement does not count")
	game.undo_action();check(game.active_displacements == 1 and game.player == Vector2i(4, 4), "undo paid movement restores displacement count")
	game.undo_action();check(game.active_displacements == 0 and game.player == Vector2i(4, 5), "undo free movement restores zero count")
	for id in ["advance", "knight_assault", "retreat_strike"]:
		for hp in [1, 3]:
			fresh("horse")
			var target = Vector2i(6, 4) if id == "knight_assault" else Vector2i(4, 4)
			enemy("e", target, hp);hand([id]);game.play_card(0, target)
			var expected = 1 if hp == 1 or id == "retreat_strike" else 0
			check(game.active_displacements == expected, id + " counts only an actual player displacement at hp=" + str(hp))
	fresh();enemy("e", Vector2i(4, 4));hand(["shock"]);game.play_card(0, Vector2i(4, 4))
	check(game.active_displacements == 0, "pushing an enemy does not count as player movement")
	fresh("artillery");hand(["deploy", "pack"]);game.play_card(0, game.player);game.play_card(0, game.player)
	check(game.active_displacements == 0, "stance changes and their draws do not count as movement")
	fresh();game.record_active_displacement(game.player)
	check(game.active_displacements == 0, "recording a stationary origin cannot increase movement count")
	enemy("p", Vector2i(4, 4));game.end_turn()
	check(game.player != Vector2i(4, 5) and game.active_displacements == 0, "forced recoil does not create active displacement in the new turn")
	fresh();game.basic_move(Vector2i(4, 4));game.end_turn()
	check(game.active_displacements == 0, "next player turn resets active displacement count")
	game.undo_action();check(game.active_displacements == 1, "undo turn restores prior-turn displacement count")
	game.start_stage();check(game.active_displacements == 0, "stage transition clears movement count")

func check_chain():
	for moves in [0, 1, 3]:
		fresh("horse");game.active_displacements = moves
		var target = enemy("e", Vector2i(5, 4), 10)
		var other = enemy("e", Vector2i(4, 4), 10)
		hand(["chain_assault"]);var cards = game.deck.duplicate()
		check(game.can_commit_card(0, target.pos), "chain accepts selected diagonal neighbor")
		game.play_card(0, target.pos)
		check(target.hp == 9 - moves and other.hp == 10 and game.player == Vector2i(4, 5), "chain hits only chosen target for 1 plus active moves=" + str(moves))
		check(game.active_displacements == moves and game.deck == cards and game.hand.is_empty() and game.energy == 1, "chain itself neither moves nor draws and costs two")
		game.undo_action();check(game.enemies[1].hp == 10 and game.active_displacements == moves and game.hand == ["chain_assault"], "undo chain restores selected damage and its state")
	fresh("horse");enemy("e", Vector2i(4, 3));enemy("stake", Vector2i(5, 4));hand(["chain_assault"])
	check(not game.can_commit_card(0, Vector2i(4, 3)) and not game.can_commit_card(0, Vector2i(5, 4)) and not game.can_commit_card(0, Vector2i(3, 5)), "chain rejects distance two, stake, and empty cell")
	game.play_card(0, Vector2i(4, 3));check(game.energy == 3 and game.hand == ["chain_assault"], "invalid chain target spends nothing")

func check_sweep_and_shock():
	fresh();var neighbors = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0: continue
			neighbors.append(enemy("e", game.player + Vector2i(dx, dy), 3))
	var distant = enemy("e", Vector2i(4, 3), 3)
	hand(["sweep"]);game.play_card(0, game.player)
	var all_hit = true
	for target in neighbors:
		if target.hp != 2: all_hit = false
	check(all_hit and distant.hp == 3 and game.energy == 1, "sweep deals one to all eight neighbors but not distance two")
	fresh();enemy("e", Vector2i(5, 4));hand(["sweep"])
	check(game.can_commit_card(0, game.player), "diagonal-only enemy enables sweep")
	game.play_card(0, game.player);check(game.enemies[1].hp == 4, "diagonal-only sweep is actually applied")
	fresh();enemy("stake", Vector2i(4, 4));hand(["sweep"]);game.play_card(0, game.player)
	check(game.hand == ["sweep"] and game.energy == 3 and game.enemies.size() == 2, "stakes alone neither enable nor suffer sweep")
	for delta in [Vector2i(1, 1), Vector2i(-1, -1), Vector2i(2, 0), Vector2i(0, -2)]:
		fresh();var target = enemy("e", game.player + delta, 3);var old_position: Vector2i = target.pos
		hand(["shock"]);check(game.can_commit_card(0, target.pos), "shock accepts expanded target " + str(delta))
		game.play_card(0, target.pos)
		check(target.hp == 2 and target.pos == old_position + Vector2i(signi(delta.x), signi(delta.y)) and game.player == Vector2i(4, 5), "shock damages and pushes outward one cell for " + str(delta))
	fresh();var target = enemy("e", Vector2i(4, 4), 3);var blocker = enemy("stake", Vector2i(4, 3))
	hand(["shock"]);game.play_card(0, target.pos)
	check(target.hp == 2 and target.pos == Vector2i(4, 4) and blocker.pos == Vector2i(4, 3), "occupied push destination prevents movement but not shock damage")
	fresh();game.player = Vector2i(1, 5);target = enemy("e", Vector2i(0, 5), 3)
	hand(["shock"]);game.play_card(0, target.pos)
	check(target.hp == 2 and target.pos == Vector2i(0, 5), "board edge prevents push without cancelling damage")
	fresh();enemy("e", Vector2i(6, 4));hand(["shock"])
	check(not game.can_commit_card(0, Vector2i(6, 4)), "shock excludes non-orthogonal distance-two extension")
	fresh();enemy("stake", Vector2i(4, 4));target = enemy("e", Vector2i(4, 3), 3);hand(["shock"])
	game.play_card(0, target.pos)
	check(target.hp == 2 and target.pos == Vector2i(4, 2), "shock selectable distance-two range ignores an intervening piece")

func check_suppress():
	fresh();var adjacent = enemy("p", Vector2i(4, 4), 5, 3)
	var diagonal = enemy("e", Vector2i(5, 4), 5, 4)
	var distant = enemy("e", Vector2i(4, 3), 5, 5)
	hand(["suppress", "sword", "sword", "sword", "sword", "sword", "sword"])
	var draws = game.deck.size();game.play_card(0, game.player)
	check(game.hand.size() == 7 and game.deck.size() == draws - 1 and game.phase == "discard", "suppress completes one draw and enters normal hand overflow")
	check(adjacent.cd == 5 and diagonal.cd == 4 and distant.cd == 5, "suppress increases only orthogonal adjacent movement timers by two")
	check(adjacent.hp == 5 and adjacent.stun == 0 and game.energy == 0 and game.discard == ["suppress"], "suppress neither damages nor stuns and spends three energy")
	game.undo_action();check(game.hand.size() == 7 and game.hand[0] == "suppress" and game.enemies[1].cd == 3 and game.deck.size() == draws, "undo suppress restores draw overflow timer and resources")
	fresh();adjacent = enemy("p", Vector2i(4, 4), 5, 99);hand(["suppress"])
	game.play_card(0, game.player);game.end_turn()
	check(game.lives == 4 and adjacent.cd == 100, "suppressed attacker can still attack and its timer ticks normally")
	fresh();hand(["suppress"]);game.play_card(0, game.player)
	check(game.energy == 0 and game.hand.size() == 1 and game.discard == ["suppress"], "suppress remains a legal draw with no adjacent target")

func check_stakes():
	fresh("artillery");hand(["stake", "permanent_stake"])
	game.play_card(0, Vector2i(4, 3));game.play_card(0, Vector2i(5, 4))
	var temporary = game.enemies[1];var permanent = game.enemies[2]
	check(temporary.ttl == 3 and int(permanent.get("ttl", -1)) < 0 and game.discard == ["stake"] and game.hand.is_empty(), "temporary stake has three phases; permanent stake exhausts and has no positive expiry")
	check(not game.basic_legal(Vector2i(4, 3)) and not game.card_legal("permanent_stake", Vector2i(5, 4)), "permanent and temporary stakes block movement and duplicate placement")
	game.end_turn();game.end_turn()
	check(R.occupied(Vector2i(4, 3), game.enemies) >= 0 and temporary.ttl == 1 and R.occupied(Vector2i(5, 4), game.enemies) >= 0, "both stake types survive first two enemy phases")
	game.end_turn()
	check(R.occupied(Vector2i(4, 3), game.enemies) == -1 and R.occupied(Vector2i(5, 4), game.enemies) >= 0, "third phase expires only ordinary stake")
	for turn_index in 4: game.end_turn()
	check(R.occupied(Vector2i(5, 4), game.enemies) >= 0, "permanent stake remains after seven enemy phases")
	fresh("artillery");hand(["permanent_stake"]);game.play_card(0, Vector2i(4, 3));game.undo_action()
	check(game.enemies.size() == 1 and game.hand == ["permanent_stake"] and game.energy == 3, "undo permanent stake restores exhausted card and removes piece")
	check(not game.card_legal("permanent_stake", game.player) and not game.card_legal("permanent_stake", Vector2i(4, 2)) and not game.card_legal("permanent_stake", Vector2i(-1, 5)), "permanent stake rejects player cell, beyond-range and off-board placements")
	game.collection = ["permanent_stake"];game.start_stage()
	check(game.deck == ["permanent_stake"] and game.enemies.all(func(e): return e.kind != "stake"), "stage transition removes structures and restores consumed permanent-stake copy")

func cannon_fixture(stance: String = "march", hp: int = 10):
	fresh("artillery");game.artillery_mode = stance
	enemy("stake", Vector2i(4, 4));enemy("e", Vector2i(4, 2), hp)

func check_reload():
	for stance in ["march", "attack"]:
		cannon_fixture(stance);hand(["reload", "cannon_shot"], 4)
		game.play_card(0, game.player)
		check(game.reload_ready and game.energy == 3 and game.discard == ["reload"], stance + " reload costs one and arms a single bonus")
		game.play_card(0, Vector2i(4, 2))
		check(game.enemies[2].hp == (8 if stance == "march" else 7) and not game.reload_ready, stance + " next successful cannon shot gains exactly one damage")
		check(game.energy == (1 if stance == "march" else 2), stance + " cannon cost is unchanged by reload")
		game.undo_action()
		check(game.reload_ready and game.enemies[2].hp == 10 and game.hand == ["cannon_shot"] and game.energy == 3, stance + " undo shot restores reload charge and damage")
		game.undo_action();check(not game.reload_ready and game.hand == ["reload", "cannon_shot"] and game.energy == 4, stance + " undo reload restores card and energy")
	cannon_fixture();hand(["reload", "cannon_shot"], 2);game.play_card(0, game.player)
	game.play_card(0, Vector2i(4, 2))
	check(game.reload_ready and game.hand == ["cannon_shot"] and game.enemies[2].hp == 10 and game.energy == 1, "unaffordable cannon does not consume reload")
	game.energy = 3;game.play_card(0, Vector2i(3, 2))
	check(game.reload_ready and game.hand == ["cannon_shot"] and game.energy == 3, "invalid cannon target does not consume reload")
	cannon_fixture("attack");hand(["reload", "cannon_shot"], 3);game.play_card(0, game.player)
	game.enemies.remove_at(1);game.play_card(0, Vector2i(4, 2))
	check(game.reload_ready and game.hand == ["cannon_shot"], "cannon without a screen preserves reload")
	cannon_fixture("march", 2);hand(["reload", "cannon_shot"])
	var cards = game.deck.duplicate();game.play_card(0, game.player);game.play_card(0, Vector2i(4, 2))
	check(game.enemies.size() == 2 and game.hand.size() == 1 and game.deck.size() == cards.size() - 1 and not game.reload_ready, "reload-powered kill draws exactly one card")
	var drawn = game.hand.duplicate();var drawn_ids = game.hand_ids.duplicate()
	game.undo_action();game.play_card(0, Vector2i(4, 2))
	check(game.hand == drawn and game.hand_ids == drawn_ids, "undo and replay reload kill draws same physical card identity")
	cannon_fixture("march", 10);hand(["reload", "reload", "cannon_shot", "cannon_shot"], 10)
	game.play_card(0, game.player);game.play_card(0, game.player)
	var shot_index = game.hand.find("cannon_shot");game.play_card(shot_index, Vector2i(4, 2))
	check(game.enemies[2].hp == 8 and not game.reload_ready, "multiple reload uses cannot stack damage")
	shot_index = game.hand.find("cannon_shot");game.play_card(shot_index, Vector2i(4, 2))
	check(game.enemies[2].hp == 7, "only first subsequent cannon is enhanced")
	cannon_fixture();hand(["reload"]);game.play_card(0, game.player);game.end_turn()
	check(not game.reload_ready, "unused reload expires at next turn")
	game.undo_action();check(game.reload_ready, "undo turn restores unspent reload")
	game.start_stage();check(not game.reload_ready, "stage transition clears reload")
	fresh("artillery");var target = enemy("e", Vector2i(4, 4), 3);hand(["reload", "sword"])
	game.play_card(0, game.player);game.play_card(0, target.pos)
	check(game.reload_ready and target.hp == 2, "ordinary attack neither spends reload nor receives its damage")

func check_new_save():
	for identity in ["king", "horse", "artillery"]:
		fresh(identity, true)
		var target = enemy("e", Vector2i(4, 4), 5)
		game.queue_bleed(1, 2)
		game.active_displacements = 3;game.shield_charges = 1;game.reload_ready = true
		var expected = game.history.capture();var target_uid = target.uid
		game.route.save()
		check(game.route.save_error == OK, identity + " new effects save successfully")
		game.free();make_game()
		check(game.route.resume() and game.history.capture() == expected, identity + " new-scene save round trip restores all new state and RNG")
		check(game.pending_bleeds[0].enemy_uid == target_uid and game.next_enemy_uid > target_uid, identity + " saved bleed identity cannot collide with next enemy")
		var next_uid = game.next_enemy_uid;enemy("e", Vector2i(5, 4))
		check(game.enemies.back().uid == next_uid, identity + " enemy IDs continue after resume")
		game.end_turn()
		check(game.active_displacements == 0 and game.shield_charges == 0 and not game.reload_ready and game.pending_bleeds.size() == 1 and game.pending_bleeds[0].amount == 1 and game.enemies[uid_index(target_uid)].hp == 4, identity + " resumed buffs expire while bleed retains exactly its second ending")

		var between_ticks = game.history.capture();game.route.save();game.free();make_game()
		check(game.route.resume() and game.history.capture() == between_ticks, identity + " save and fresh-scene resume preserve one remaining bleed tick")
		game.end_turn()
		check(game.enemies[uid_index(target_uid)].hp == 3 and game.pending_bleeds.is_empty(), identity + " resumed one-tick remainder resolves once at next ending")

func check_save_isolation():
	fresh("horse", true)
	game.route.save()
	var current = ConfigFile.new()
	check(current.load(game.route.SAVE) == OK and current.get_value("run", "version") == 5, "current saves use version five")
	check(game.route.SAVE == "user://route_run_v0100.cfg" and game.route.WEB_SAVE_KEY == "yixing.route_run.v0100", "native and Web save namespaces isolate this demo revision")
	var legacy = ConfigFile.new();legacy.parse(current.encode_to_text())
	legacy.set_value("run", "version", 1)
	var old_battle: Dictionary = legacy.get_value("run", "battle")
	for field in NEW_FIELDS: old_battle.erase(field)
	old_battle.hand = RETIRED.duplicate();old_battle.collection.append_array(RETIRED)
	for piece in old_battle.enemies: piece.erase("uid")
	legacy.set_value("run", "battle", old_battle)
	check(legacy.save("user://route_run.cfg") == OK, "old demo save fixture exists only in its retired namespace")
	var legacy_text = FileAccess.get_file_as_string("user://route_run.cfg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.route.SAVE))
	var before = game.history.capture();var before_route = game.route.state.duplicate(true)
	check(not game.route.resume(), "old v1 file is never loaded when current-format file is absent")
	check(game.history.capture() == before and game.route.state == before_route, "ignored old save does not mutate current run")
	check(FileAccess.get_file_as_string("user://route_run.cfg") == legacy_text, "ignored old save is not rewritten or migrated")
	game.route.save();game.show_home()
	check(game.route.resume() and game.history.capture() == before, "new-format save still resumes normally alongside an old file")
	check(FileAccess.get_file_as_string("user://route_run.cfg") == legacy_text, "normal new saving leaves retired namespace untouched")

func check_invalid_new_saves():
	fresh("king", true);enemy("e", Vector2i(4, 4));game.queue_bleed(1, 2)
	game.route.save()
	var good = ConfigFile.new();good.load(game.route.SAVE)
	var encoded = good.encode_to_text();var battle = game.history.capture()
	var route = game.route.state.duplicate(true)
	var invalid: Array = []
	for field in NEW_FIELDS:
		var config = ConfigFile.new();config.parse(encoded)
		var state = battle.duplicate(true);state.erase(field);config.set_value("run", "battle", state)
		invalid.append({"label": "missing required " + field, "config": config})
	for entry in [
		{"field": "active_displacements", "value": -1},
		{"field": "shield_charges", "value": 2},
		{"field": "reload_ready", "value": "armed"},
		{"field": "next_enemy_uid", "value": 0},
		{"field": "pending_bleeds", "value": [{"enemy_uid": 0, "amount": 2}]},
		{"field": "pending_bleeds", "value": [{"enemy_uid": 1, "amount": -1}]},
		{"field": "pending_bleeds", "value": ["not a bleed"]},
		{"field": "collection", "value": ["push"]},
		{"field": "hand", "value": ["stun"]},
		{"field": "deck", "value": ["swap"]}
	]:
		var config = ConfigFile.new();config.parse(encoded)
		var state = battle.duplicate(true);state[entry.field] = entry.value;config.set_value("run", "battle", state)
		invalid.append({"label": "invalid " + entry.field + " value " + str(entry.value), "config": config})
	var duplicate_uid = ConfigFile.new();duplicate_uid.parse(encoded)
	var duplicate_state = battle.duplicate(true);duplicate_state.enemies[1].uid = duplicate_state.enemies[0].uid
	duplicate_uid.set_value("run", "battle", duplicate_state)
	invalid.append({"label": "duplicate enemy IDs", "config": duplicate_uid})
	var missing_uid = ConfigFile.new();missing_uid.parse(encoded)
	var missing_state = battle.duplicate(true);missing_state.enemies[0].erase("uid")
	missing_uid.set_value("run", "battle", missing_state)
	invalid.append({"label": "missing enemy identity", "config": missing_uid})
	var stale_uid = ConfigFile.new();stale_uid.parse(encoded)
	var stale_state = battle.duplicate(true);stale_state.next_enemy_uid = stale_state.enemies[1].uid
	stale_uid.set_value("run", "battle", stale_state)
	invalid.append({"label": "next enemy identity would collide", "config": stale_uid})
	for version in [1, 99]:
		var config = ConfigFile.new();config.parse(encoded);config.set_value("run", "version", version)
		invalid.append({"label": "wrong save version " + str(version), "config": config})
	for fixture in invalid:
		fixture.config.save(game.route.SAVE)
		check(not game.route.resume(), "reject new-format " + fixture.label)
		check(game.history.capture() == battle and game.route.state == route, "reject " + fixture.label + " without live-state mutation")
	good.save(game.route.SAVE)
	check(game.route.resume() and game.history.capture() == battle, "valid current save still resumes after invalid fixtures")

func check_stage_cleanup_and_camp():
	fresh("king", true)
	game.active_displacements = 2;game.shield_charges = 1;game.reload_ready = true;game.queue_bleed(0, 2)
	game.debug_skip();game.choose_reward(-1)
	check(game.screen == "map" and game.active_displacements == 0 and game.shield_charges == 0 and not game.reload_ready and game.pending_bleeds.is_empty(), "map return clears every battle-only buff and delayed effect")
	game.route.enter(3);game.route.resolve(game.route.choices.size() - 1);game.route.enter(5);game.debug_skip();game.choose_reward(-1);game.route.enter(6)
	game.collection = ["sword", "spear", "pierce", "sweep", "guard", "permanent_stake", "reload", "chain_assault"]
	game.route.choice_mode = "upgrade"
	var options = game.route.options();var upgraded = []
	for option in options:
		if option.action == "upgrade": upgraded.append(game.collection[option.index])
	check(exact_cards(upgraded, ["sword", "spear"]), "workshop upgrades only sword and spear, with no accidental generic plus cards")

func check_text_layout():
	var ids = ["sweep", "shock", "pierce", "guard", "suppress", "chain_assault", "permanent_stake", "reload"]
	for size in [Vector2(1280, 940), Vector2(390, 844), Vector2(844, 390), Vector2(360, 640)]:
		fresh();game.configure_layout(size)
		for id in ids:
			hand([id]);game.selected = 0;game.handui.reset();game.handui.sync()
			for tick in 20: game.handui.tick(0.05)
			var transform = game.handui.card_transform(0)
			var dimensions = Vector2(transform.x.length(), transform.y.length()) * game.handui.card_size()
			var layout = game.handui.text_layout(0, dimensions, true)
			var last_baseline = float(layout.start_y) + maxf(0, layout.lines.size() - 1) * float(layout.line_height)
			if not bool(layout.complete): print("TEXT OVERFLOW ", id, " viewport=", size, " card=", dimensions, " font=", layout.font_size, " lines=", layout.lines.size(), "/", layout.available_lines)
			check(bool(layout.complete) and last_baseline <= dimensions.y - 4, id + " focused description fits card at " + str(size))

func run():
	make_game()
	check_profiles()
	check_guard()
	check_bleed()
	check_bleed_phase_order()
	check_displacements()
	check_chain()
	check_sweep_and_shock()
	check_suppress()
	check_stakes()
	check_reload()
	check_new_save()
	check_save_isolation()
	check_invalid_new_saves()
	check_stage_cleanup_and_camp()
	check_text_layout()
	print("CARD REBALANCE RESULT ", checks, " checks, ", failures, " failures")
	game.free();quit(1 if failures else 0)
