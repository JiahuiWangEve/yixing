extends SceneTree
const T = preload("res://../tests/route_test_helpers.gd")
var game
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
func _initialize(): call_deferred("run")
func paths(id: int, path: Array, nodes: Array) -> Array:
	var next_path = path + [id]
	if nodes[id].next.is_empty(): return [next_path]
	var result = []
	for target in nodes[id].next: result.append_array(paths(target, next_path, nodes))
	return result
func skip_reward():
	game.input_lock = 0;game.navigation_lock = 0
	game.debug_skip();game.choose_reward(-1)
func act(action: String, index: int = -1):
	if action == "upgrade" and game.route.choice_mode == "root": act("select_upgrade")
	for i in game.route.choices.size():
		var choice = game.route.choices[i]
		if choice.action == action and (index < 0 or choice.get("index", -1) == index):
			game.route.resolve(i)
			return
	check(false, "missing route action: " + action)
func leave(): act("leave")
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.settings.set_debug_mode(true)
	for seed_number in 100:
		game.route.generate(seed_number)
		var saved = game.route.state.duplicate(true)
		game.route.generate(seed_number)
		check(saved == game.route.state, "seed deterministic")
		var nodes = saved.nodes
		check(nodes.size() >= 9, "at least nine nodes")
		var seen = []
		for path in paths(0, [], nodes):
			check(path.size() == 9 and nodes[path.back()].kind == "boss", "nine steps terminate at boss")
			var workshops = 0;var branches = 0
			for i in path.size():
				var n = nodes[path[i]]
				if n.id not in seen: seen.append(n.id)
				if n.kind in ["workshop", "camp"]: workshops += 1
				if n.next.size() > 1: branches += 1
				if i > 0: check(not (n.kind == "elite" and nodes[path[i-1]].kind == "elite"), "no consecutive elites")
			check(workshops > 0 and branches >= 3, "preparation and three branch decisions on every route")
		check(seen.size() == nodes.size(), "every node reachable")
	for identity in ["king", "horse", "artillery"]:
		game.player_skill = identity;game.new_expedition()
		check(game.screen == "map" and game.lives == game.PROFILES.DATA[identity].lives, "identity and health preserved")
		game.route.enter(0)
		game.phase = "discard";game.selected = 0;game.input_lock = 8
		game.debug_skip()
		check(game.phase == "reward" and game.selected == -1 and game.input_lock == 0, "skip clears pending UI and animation")
		var loot = game.rewards.duplicate();game.debug_skip()
		check(game.rewards == loot, "repeated skip does not reroll")
		check(game.route.resume() and game.phase == "reward" and game.rewards == loot, "reward reload persists")
		game.choose_reward(0);var count = game.collection.size();game.choose_reward(0)
		check(game.collection.size() == count and game.screen == "map" and game.route.state.visited == [0], "reward resolves once")
		check(game.hand.is_empty() and game.enemies.is_empty() and game.energy == 0 and game.tuna_turns == 0, "map clears battle state")
		T.enter_next(game, "camp")
		act("prepare");act("confirm")
		check(game.route.state.prepared, "rest prepares next battle")
		T.enter_next(game, "battle")
		check(game.screen == "game" and game.encounter_state.config.tier == "battle", "explicit ordinary battle fixture retains baseline tier")
		check(game.hand.size() == 2 and not game.route.state.prepared, "prepared two draws consumed once")
		skip_reward();T.enter_next(game, "workshop")
		act("upgrade", 0);act("confirm")
		check("sword_plus" in game.collection, "workshop upgrades single instance")
		T.enter_next(game, "battle")
		check("sword_plus" in game.deck + game.hand and not game.history.can_undo(), "upgrade crosses battle; map cannot undo")
		if identity == "artillery": check("deploy" in game.deck + game.hand, "consumable restored")
		game.player = Vector2i(4, 9);game.enemies = [];game.add_enemy("g", Vector2i(4, 8), 3)
		game.hand = ["sword_plus"];game.hand_ids = [];game.input_lock = 0;game.energy = 3;game.play_card(0, Vector2i(4, 8))
		check(game.enemies[0].hp == 1 and game.discard == ["sword_plus"], "upgraded damage and discard")
		undo_after_effects(game);check(game.hand == ["sword_plus"] and game.enemies[0].hp == 3, "upgraded undo")
		game.route.save();game.show_home();check(game.route.resume() and game.hand == ["sword_plus"], "battle reload")
		skip_reward();T.walk_before(game, T.kind_id(game.route, "boss"))
		game.route.enter(T.kind_id(game.route, "boss"));game.debug_skip();game.debug_skip()
		check(game.phase == "reward" and not game.route.state.done and game.skill_system.horse_unlocked, "first boss rewards and unlock before chapter transition")
		game.choose_reward(-1)
		check(game.screen == "treasure_choice" and game.route.chapter() == 1, "first boss requires one role treasure before chapter two")
		check(game.route.choose_treasure(game.TREASURES.ids_for(identity)[1]), "role treasure claim succeeds exactly once")
		check(game.screen == "map" and game.route.chapter() == 2 and game.route.state.visited.is_empty(), "first boss starts fresh chapter two after treasure")
		check(game.route.resume(), "second chapter can resume")
	game.new_expedition();game.route.enter(0);skip_reward();T.enter_next(game, "camp")
	game.collection = [];game.route.choices = game.route.options();leave()
	check(game.screen == "map" and game.collection.is_empty(), "empty rest can leave")
	T.enter_next(game, "battle");skip_reward();T.enter_next(game, "workshop");leave();T.enter_next(game, "camp")
	game.collection = ["sword_plus", "sword"];game.route.choices = game.route.options()
	act("select_remove");act("remove", 0);act("confirm")
	check(game.collection == ["sword"], "rest removes only selected upgraded instance once")
	T.walk_before(game, T.kind_id(game.route, "boss"));game.route.enter(T.kind_id(game.route, "boss"))
	check(game.enemies[0].hp == 9, "boss baseline remains nine without removed weakening event")
	game.new_expedition();check(game.route.state.visited.is_empty() and "weakened" not in game.route.state and "sword_plus" not in game.collection, "new run resets chapter")
	game.start_debug_stage(6)
	for i in 5: game.navigation_lock = 0;game.choose_reward(-1)
	game.debug_skip();check(game.phase == "win" and not game.route.active(), "legacy debug retained")
	game.start_tutorial(0);var phase = game.phase;game.debug_skip()
	check(game.phase == phase and game.tutorial.active and not game.route.active(), "tutorial isolated")
	for size in [Vector2(1280,940), Vector2(390,844), Vector2(844,390), Vector2(360,640)]:
		game.configure_layout(size)
		check(game.route.home_rect().end.y < 64, "map home button clears title in portrait and landscape")
		check(not game.debug_skip_rect().intersects(game.END_TURN_RECT) and not game.debug_skip_rect().intersects(game.BOARD_RECT), "skip button clear of board and end turn")
	print("ROUTE RESULT ", checks, " checks, ", failures, " failures")
	game.free();quit(1 if failures else 0)

# These rules tests model the completed-animation boundary before user input.
func undo_after_effects(owner) -> bool:
	owner.input_lock = 0;owner.navigation_lock = 0;owner.presentation.clear()
	return owner.undo_action()
