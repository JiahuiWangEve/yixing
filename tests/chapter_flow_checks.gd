extends SceneTree
const T = preload("res://../tests/route_test_helpers.gd")
# Full expedition boundaries, deterministic maps, receipts, and save migration.
# Run with the disposable XDG directories used by scripts/verify.sh.
var game
var route
var checks = 0
var failures = 0

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("CHAPTER FLOW: " + label)

func _initialize(): call_deferred("run")

func fresh(identity: String = "king", seed_number: int = 84721):
	game.player_skill = identity;game.seed_value = seed_number
	game.new_expedition()
	game.input_lock = 0;game.navigation_lock = 0

func paths(id: int, path: Array, nodes: Array) -> Array:
	var next_path = path + [id]
	if nodes[id].next.is_empty(): return [next_path]
	var result = []
	for target in nodes[id].next: result.append_array(paths(target, next_path, nodes))
	return result

func leave_node():
	for i in route.choices.size():
		if route.choices[i].action == "leave": route.resolve(i);return
	check(false, "non-combat node has a leave action")

func finish_combat(reward_index: int = -1):
	game.input_lock = 0;game.navigation_lock = 0
	game.debug_skip()
	if game.phase == "reward": game.choose_reward(reward_index)

func march_to_boss() -> int:
	var expected_lives = game.lives
	var boss = T.kind_id(route, "boss")
	var path = T.path_to(route, boss);path.pop_back()
	for id in path:
		check(id in route.legal(), "path advances legally to node " + str(id))
		route.enter(id)
		if game.screen == "game":
			expected_lives = mini(5, expected_lives + 1) if game.player_skill == "king" else expected_lives
			finish_combat()
		else: leave_node()
		check(game.lives == expected_lives, "each victory grants only king one capped life; non-combat nodes do not heal")
	check(route.legal() == [boss], "all nine-step routes lead to the boss")
	return expected_lives

func check_generation():
	fresh()
	for seed_number in range(-4, 64):
		var map_seeds = []
		for chapter_number in [1, 2]:
			route.generate(seed_number, chapter_number)
			var saved = route.state.duplicate(true)
			route.generate(seed_number, chapter_number)
			check(route.state == saved, "seed and chapter reproduce the whole map")
			check(saved.chapter == chapter_number and saved.run_seed == seed_number, "map keeps chapter and expedition seed")
			check(saved.seed not in map_seeds, "chapters have different deterministic map identities")
			map_seeds.append(saved.seed)
			check(saved.nodes.size() >= 9 and saved.visited.is_empty() and route.legal() == [0], "fresh map has at least nine unvisited nodes and one entrance")
			var seen = []
			for path in paths(0, [], saved.nodes):
				check(path.size() == 9 and saved.nodes[path.back()].kind == "boss", "each chapter has nine-step routes ending at its boss")
				var workshops = 0
				for i in path.size():
					var node = saved.nodes[path[i]]
					if node.id not in seen: seen.append(node.id)
					if node.kind in ["workshop", "camp"]: workshops += 1
					if i > 0: check(node.kind != "elite" or saved.nodes[path[i - 1]].kind != "elite", "no forced back-to-back elites")
				check(workshops > 0, "every route offers a camp or workshop")
			check(seen.size() == saved.nodes.size(), "every generated node remains reachable")
			for node in saved.nodes:
				if node.kind in ["battle", "elite", "boss"]:
					check(game.ENCOUNTERS.valid_config(node.encounter), "generated encounter is valid")
					check(node.encounter.get("chapter", 1) == chapter_number, "encounters belong to their map chapter")
			if chapter_number == 2:
				check(saved.nodes[0].encounter.id == "c2_heavy_pawns", "second chapter always introduces heavy pawns first")
				check(game.ENCOUNTERS.title(saved.nodes[0].encounter) == "坚卒拦路", "second entrance uses the new battle title")
				check("坚城" in route.chapter_title(), "second map identifies the chapter")
			var elite = T.kind_id(route, "elite")
			route.scroll_y = clampf(route.content_point(saved.nodes[elite]).y - route.map_rect().get_center().y, 0, route.scroll_limit())
			var information = route.inspect_at(route.position(saved.nodes[elite]))
			check(not information.is_empty() and information.title == "关隘", "elite map information describes its route nature")
			var visible_text = "\n".join(information.get("lines", []))
			check("血" not in visible_text and game.ENCOUNTERS.title(saved.nodes[elite].encounter) not in visible_text, "elite map information does not reveal HP or hidden encounter identity")

func check_elite_health():
	# Moving details out of map previews must not change combat difficulty.
	for seed_number in [-4, 0, 17, 63]:
		for chapter_number in [1, 2]:
			fresh("king", seed_number);route.generate(seed_number, chapter_number)
			var elite = T.kind_id(route, "elite");T.before(route, elite)
			route.enter(elite)
			check(game.screen == "game" and route.state.pending == elite, "elite fixture enters actual battle")
			var generals = game.enemies.filter(func(enemy): return enemy.kind == "g")
			check(generals.size() == 1, "elite encounter has exactly one general")
			if generals.size() == 1:
				var expected = 6 if chapter_number == 2 else 5
				check(generals[0].hp == expected and generals[0].max_hp == expected, "chapter elite retains real %d-HP general" % expected)

func check_transition():
	for identity in ["king", "horse", "artillery"]:
		fresh(identity)
		game.collection = ["sword_plus", "sword", "fatigue", "deploy"]
		game.lives = 2
		var entering_lives = march_to_boss()
		var victory_lives = mini(5, entering_lives + 1) if identity == "king" else entering_lives
		var deck = game.collection.duplicate()
		var first_map_seed = route.state.seed
		var run_seed = route.state.run_seed
		route.state.pending_homework = ["spear_plus"]
		route.state.reward_debt = 1
		route.enter(T.kind_id(route, "boss"))
		check(game.lives == entering_lives and game.player_skill == identity, "entering first boss preserves accumulated victory health and identity")
		game.debug_skip();deck.append("spear_plus")
		check(game.phase == "reward" and not route.state.done and route.chapter() == 1, "first boss waits for reward resolution instead of ending the run")
		check(game.collection == deck and route.state.pending_homework.is_empty(), "boss victory awards the exact queued card before chapter transition")
		check(route.rewards_blocked() and game.rewards.is_empty() and route.state.reward_debt == 0, "homework suppresses only the first boss reward")
		check(game.skill_system.horse_unlocked, "first chapter victory still unlocks the horse")
		check(not game.history.can_undo(), "first boss receipt cannot be undone")
		check(route.resume() and game.collection == deck and route.state.homework_awarded == ["spear_plus"], "boss receipt resumes without reissuing homework")
		game.debug_skip();route.battle_victory()
		check(game.collection == deck and game.lives == victory_lives, "repeated victory cannot duplicate boss homework or capped triumph healing")
		game.choose_reward(0);game.delete_reward(0)
		check(game.collection == deck and route.chapter() == 1, "suppressed reward cannot grant a card or prematurely advance")
		game.choose_reward(-1)
		check(game.screen == "treasure_choice" and route.chapter() == 1 and route.state.treasure_choices == game.TREASURES.ids_for(identity), "boss reward resolution waits for the mandatory role treasure")
		check(route.choose_treasure(game.TREASURES.ids_for(identity)[1]), "one role treasure advances the chapter")
		check(game.screen == "map" and route.chapter() == 2 and not route.state.done, "treasure claim opens a fresh second map")
		check(route.state.current == -1 and route.state.pending == -1 and route.state.visited.is_empty() and route.legal() == [0], "chapter boundary clears old progress and seals")
		check(route.state.seed != first_map_seed and route.state.run_seed == run_seed and game.seed_value == run_seed, "chapter boundary changes map seed without changing run seed")
		check(game.collection == deck and game.lives == victory_lives and game.player_skill == identity, "chapter boundary preserves exact cards, fatigue, character and one-time victory health without extra healing")
		check(not route.state.prepared and route.state.pending_homework.is_empty() and route.state.reward_debt == 0 and not route.rewards_blocked(), "settled commitments do not leak into second chapter")
		check(game.enemies.is_empty() and game.hand.is_empty() and game.encounter_state.is_empty() and not game.history.can_undo(), "chapter boundary clears battle and undo state")
		check(route.stamp_node == -1 and route.selected_node == -1 and route.travel_target == -1, "new map has no old victory animation or pending march")
		check(route.resume() and route.chapter() == 2 and game.collection == deck and game.lives == victory_lives, "second map immediately resumes with persistent expedition state and no repeated healing")
		game.input_lock = 0;game.navigation_lock = 0
		route.enter(0)
		check(game.screen == "game" and game.encounter_state.config.id == "c2_heavy_pawns", "second entrance starts the promised new encounter")
		check("fatigue" in game.deck + game.hand and not game.history.can_undo(), "fatigue persists into second battle without cross-chapter undo")
		game.debug_skip()
		check(game.phase == "reward" and game.rewards.size() == 3 and not route.rewards_blocked(), "first second-chapter battle has ordinary rewards again")
		game.choose_reward(-1)
		check(route.state.visited == [0], "second chapter stamps only its own completed battle")

func check_pending_carry():
	fresh()
	march_to_boss();route.enter(T.kind_id(route, "boss"));game.debug_skip()
	# Model a still-unconsumed future effect at the reward boundary. No transition
	# is allowed to reinterpret or discard it just because the map is replaced.
	route.state.prepared = true;route.state.reward_debt = 1;route.state.pending_homework = ["spear_plus"]
	game.collection = ["sword_plus", "fatigue", "spear_plus"]
	game.lives = 1
	game.choose_reward(-1)
	check(game.screen == "treasure_choice" and route.chapter() == 1, "pending effects wait through the mandatory treasure choice")
	check(route.choose_treasure("life_talisman"), "claim treasure before testing carried effects")
	check(route.chapter() == 2 and route.state.prepared and route.state.reward_debt == 1 and route.state.pending_homework == ["spear_plus"], "all still-pending expedition effects cross the boundary")
	check(route.resume() and route.state.prepared and route.state.pending_homework == ["spear_plus"], "carried preparation and exact homework survive save")
	var deck = game.collection.duplicate()
	route.enter(0)
	check(game.hand.size() == 2 and not route.state.prepared and game.collection == deck and game.lives == 1, "carried preparation is consumed exactly once without healing or early copy")
	game.debug_skip();deck.append("spear_plus")
	check(game.collection == deck and route.rewards_blocked() and route.state.reward_debt == 0, "carried homework settles once on the first actual next battle")
	game.choose_reward(-1)
	check(route.resume() and not route.state.prepared and route.state.pending_homework.is_empty(), "consumed chapter-two effects do not reappear after reload")

func check_final_boss():
	fresh()
	route.generate(game.seed_value, 2)
	game.lives = 2
	var entering_lives = march_to_boss()
	var victory_lives = mini(5, entering_lives + 1) if game.player_skill == "king" else entering_lives
	route.state.pending_homework = ["sword_plus"];route.state.reward_debt = 1
	var deck = game.collection.duplicate()
	route.enter(T.kind_id(route, "boss"))
	check(game.encounter_state.config.id == "c2_inner_city", "second map ends at the inner-city encounter")
	game.debug_skip();deck.append("sword_plus")
	check(game.phase == "win" and route.state.done and route.chapter() == 2, "second boss reaches the final ending")
	check(game.collection == deck and game.lives == victory_lives and route.state.pending_homework.is_empty(), "final victory settles homework and only king gains one capped triumph life")
	game.debug_skip();route.complete()
	check(route.state.done and game.phase == "win" and game.collection == deck and game.lives == victory_lives, "ending cannot reset the map or duplicate final rewards or triumph healing")
	check(not route.resume(), "finished expedition cannot replay rewards on resume")

func check_saves():
	fresh()
	var current = route.state.duplicate(true)
	var snapshot = game.history.capture()
	var config = ConfigFile.new();check(config.load(route.SAVE) == OK, "new-schema save exists")
	check(config.get_value("run", "version") == 6, "random-map runs use version six")
	var current_text = config.encode_to_text()
	config.set_value("run", "version", 5)
	check(config.save(route.SAVE) == OK and not route.resume(), "legacy fixed-map version five is rejected")
	check(route.state == current and game.history.capture() == snapshot, "legacy rejection preserves live route and battle atomically")
	config.parse(current_text);config.save(route.SAVE)
	check(route.resume() and route.state == current, "new-schema save resumes after rejected legacy load")
	var legacy = current.duplicate(true)
	legacy.erase("generator_version");legacy.erase("path_length");legacy.erase("boss_id")
	check(not route.valid_snapshot(legacy, snapshot, "map"), "missing generated-map metadata cannot masquerade as current schema")
	fresh();route.generate(game.seed_value, 2)
	var saved = route.state.duplicate(true);snapshot = game.history.capture()
	check(route.valid_snapshot(saved, snapshot, "map"), "fresh second-chapter snapshot validates")
	for value in [0, 3, "2", false]:
		var invalid = saved.duplicate(true);invalid.chapter = value
		check(not route.valid_snapshot(invalid, snapshot, "map"), "invalid chapter marker rejected")
	var no_origin = saved.duplicate(true);no_origin.erase("run_seed")
	check(not route.valid_snapshot(no_origin, snapshot, "map"), "chapter-two map needs its original seed")
	var wrong_seed = saved.duplicate(true);wrong_seed.seed += 1
	check(not route.valid_snapshot(wrong_seed, snapshot, "map"), "wrong chapter seed identity rejected")
	var wrong_chapter = saved.duplicate(true);wrong_chapter.chapter = 1;wrong_chapter.seed = wrong_chapter.run_seed
	check(not route.valid_snapshot(wrong_chapter, snapshot, "map"), "second-chapter encounters cannot masquerade as first-chapter save")
	route.enter(0)
	check(route.valid_snapshot(route.state, game.history.capture(), "game"), "second-chapter battle and new encounter state validate")
	route.save();check(route.resume() and game.encounter_state.config.id == "c2_heavy_pawns", "second-chapter battle resumes with exact encounter")

func check_uid_safety():
	fresh();route.generate(game.seed_value, 2)
	route.state.nodes[0].encounter = {"id": "c2_lone_guard", "tier": "battle", "rules": [], "chapter": 2}
	route.enter(0)
	for i in game.enemies.size():
		if game.enemies[i].get("unyielding", false):
			game.damage_enemy(i, 0, game.enemies[i].hp);break
	var snapshot = game.history.capture()
	check(snapshot.encounter_state.ghosts.size() == 1 and route.valid_snapshot(route.state, snapshot, "game"), "valid unyielding ghost preserves a dead, allocated UID")
	var invalid = snapshot.duplicate(true)
	invalid.encounter_state.ghosts[0].enemy.uid = invalid.next_enemy_uid
	check(not route.valid_snapshot(route.state, invalid, "game"), "ghost cannot reserve a not-yet-allocated UID")
	invalid = snapshot.duplicate(true)
	invalid.encounter_state.ghosts[0].enemy.uid = invalid.enemies[0].uid
	check(not route.valid_snapshot(route.state, invalid, "game"), "ghost cannot share identity with a living defender")
	route.save();check(route.resume() and game.encounter_state.ghosts.size() == 1, "ghost save resumes without reviving early")
	fresh();route.generate(game.seed_value, 2);route.enter(0)
	game.encounter_state.phases = 8
	game.ENCOUNTERS.finish_phase(game, 0)
	snapshot = game.history.capture()
	check(snapshot.encounter_state.waves[0].status == "arrived" and route.valid_snapshot(route.state, snapshot, "game"), "arrived reinforcement and its allocated UID validate")
	invalid = snapshot.duplicate(true)
	invalid.encounter_state.waves[0].uid = invalid.next_enemy_uid
	check(not route.valid_snapshot(route.state, invalid, "game"), "wave cannot reference a future UID")
	invalid = snapshot.duplicate(true)
	invalid.encounter_state.waves[0].uid = invalid.enemies[0].uid
	check(not route.valid_snapshot(route.state, invalid, "game"), "wave cannot reuse a live original defender UID")
	var spawned_uid = snapshot.encounter_state.waves[0].uid
	for key in ["reinforcement", "kind", "max_hp", "original_spawn", "heavy", "unyielding"]:
		invalid = snapshot.duplicate(true)
		for enemy in invalid.enemies:
			if enemy.uid != spawned_uid: continue
			match key:
				"reinforcement": enemy.reinforcement = false
				"kind": enemy.kind = "p"
				"max_hp": enemy.max_hp = 999
				"original_spawn": enemy.original_spawn = Vector2i(0, 0)
				"heavy": enemy.heavy = true
				"unyielding": enemy.unyielding = true
		check(not route.valid_snapshot(route.state, invalid, "game"), "wave live identity rejects mismatched " + key)
	for i in range(game.enemies.size() - 1, -1, -1):
		if game.enemies[i].uid == spawned_uid: game.damage_enemy(i, 0, game.enemies[i].hp)
	check(route.valid_snapshot(route.state, game.history.capture(), "game"), "arrived wave receipt remains valid after its reinforcement dies")

func check_map_cache():
	for size in [Vector2(1280, 940), Vector2(390, 844), Vector2(844, 390), Vector2(360, 640)]:
		fresh();game.configure_layout(size);route.tick(0);route.ensure_road_cache()
		var builds = route.road_cache_builds
		route.generate(game.seed_value, 2);route.tick(0);route.ensure_road_cache()
		check(route.road_cache_builds == builds + 1, "new chapter rebuilds geometry once")
		builds = route.road_cache_builds
		var work = route.road_segment_tests
		for frame in 30:
			route.scroll_y = route.scroll_limit() * frame / 29.0;route.selected_node = frame % route.state.nodes.size();route.ensure_road_cache()
		check(route.road_cache_builds == builds and route.road_segment_tests == work, "second chapter retains cached scrolling and selection")
		route.redraw_key = 0;check(route.needs_redraw() and not route.needs_redraw(), "second map settles to an idle frame")
		for node in route.state.nodes:
			check(route.SYMBOLS.has(node.kind), "second chapter reuses the black-ink map symbol registry")
			for other in route.state.nodes:
				if other.id > node.id: check(not route.hit_rect(node).intersects(route.hit_rect(other)), "second chapter hit targets never overlap")

func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.settings.set_debug_mode(true);game.set_process(false)
	route = game.route
	check_generation();check_elite_health();check_transition();check_pending_carry();check_final_boss();check_saves();check_uid_safety();check_map_cache()
	print("CHAPTER FLOW RESULT ", checks, " checks, ", failures, " failures")
	game.free();quit(1 if failures else 0)
