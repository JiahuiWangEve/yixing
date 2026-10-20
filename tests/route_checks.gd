extends SceneTree
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
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game)
	for seed_number in 100:
		game.route.generate(seed_number)
		var saved = game.route.state.duplicate(true)
		game.route.generate(seed_number)
		check(saved == game.route.state, "seed deterministic")
		var nodes = saved.nodes
		check(nodes.size() == 16, "16 nodes")
		var seen = []
		for path in paths(0, [], nodes):
			check(path.size() == 8 and nodes[path.back()].kind == "boss", "eight steps terminate at boss")
			var camps = 0;var branches = 0
			for i in path.size():
				var n = nodes[path[i]]
				if n.id not in seen: seen.append(n.id)
				if n.kind == "camp": camps += 1
				if n.next.size() > 1: branches += 1
				if i > 0: check(not (n.kind == "elite" and nodes[path[i-1]].kind == "elite"), "no consecutive elites")
			check(camps > 0 and branches >= 3, "camp and three branch decisions on every route")
		check(seen.size() == 16, "every node reachable")
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
		game.route.enter(1);game.route.resolve(0);game.route.resolve(0)
		check(game.route.state.visited.size() == 2 and game.route.state.prepared, "event once")
		game.route.enter(4)
		check(game.hand.size() == 1 and not game.route.state.prepared, "prepared draw consumed once")
		skip_reward();game.route.enter(6)
		game.route.resolve(0)
		check("sword_plus" in game.collection, "camp upgrades single instance")
		game.route.enter(7)
		check("sword_plus" in game.deck and not game.history.can_undo(), "upgrade crosses battle; map cannot undo")
		if identity == "artillery": check("deploy" in game.deck, "consumable restored")
		game.player = Vector2i(4, 9);game.enemies = [];game.add_enemy("g", Vector2i(4, 8), 3)
		game.hand = ["sword_plus"];game.hand_ids = [];game.input_lock = 0;game.energy = 3;game.play_card(0, Vector2i(4, 8))
		check(game.enemies[0].hp == 1 and game.discard == ["sword_plus"], "upgraded damage and discard")
		game.undo_action();check(game.hand == ["sword_plus"] and game.enemies[0].hp == 3, "upgraded undo")
		game.route.save();game.show_home();check(game.route.resume() and game.hand == ["sword_plus"], "battle reload")
		skip_reward();game.route.enter(10);game.route.resolve(0);game.route.enter(12);game.route.resolve(game.route.choices.size()-2)
		game.route.enter(15);game.debug_skip();game.debug_skip()
		check(game.phase == "win" and game.route.state.done and game.skill_system.horse_unlocked, "boss chapter win and unlock")
		check(not game.route.resume(), "finished run cannot replay rewards")
	game.new_expedition();game.route.enter(0);skip_reward();game.route.enter(3)
	game.collection = [];game.route.choices = game.route.options();game.route.resolve(0)
	check(game.screen == "map" and game.collection.is_empty(), "empty workshop can leave")
	game.route.enter(5);game.route.resolve(0)
	check(game.route.state.weakened, "outpost sets visible defense reduction")
	game.route.enter(6);game.route.resolve(0);game.route.enter(8)
	game.collection = ["sword_plus", "sword"];game.route.choices = game.route.options();game.route.resolve(0);game.route.resolve(0)
	check(game.collection == ["sword"], "workshop removes only selected upgraded instance once")
	game.route.enter(10);game.route.resolve(0);game.route.enter(12);game.route.resolve(0);game.route.enter(15)
	check(game.enemies[0].hp == 2, "boss defense actually weakened")
	game.new_expedition();check(game.route.state.visited.is_empty() and not game.route.state.weakened and "sword_plus" not in game.collection, "new run resets chapter")
	game.start_debug_stage(6)
	for i in 5: game.navigation_lock = 0;game.choose_reward(-1)
	game.debug_skip();check(game.phase == "win" and not game.route.active(), "legacy debug retained")
	game.start_tutorial(0);var phase = game.phase;game.debug_skip()
	check(game.phase == phase and game.tutorial.active and not game.route.active(), "tutorial isolated")
	for size in [Vector2(1280,940), Vector2(390,844), Vector2(844,390), Vector2(360,640)]:
		game.configure_layout(size)
		check(not game.debug_skip_rect().intersects(game.END_TURN_RECT) and not game.debug_skip_rect().intersects(game.BOARD_RECT), "skip button clear of board and end turn")
	print("ROUTE RESULT ", checks, " checks, ", failures, " failures")
	game.free();quit(1 if failures else 0)
