extends SceneTree
# Authored chapter-two armies and lifecycle boundaries, through real main hooks.
const E = preload("res://encounters.gd")
const C2 = preload("res://chapter_two.gd")
const R = preload("res://rules.gd")
var game
var checks = 0
var failures = 0

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
func config(id: String) -> Dictionary:
	return {"id": id, "tier": C2.TEMPLATES[id].tier, "chapter": 2, "rules": []}
func fixture(id: String = "c2_lone_guard", freeze: bool = true):
	game.tutorial.stop();game.player_skill = "king";game.new_run()
	game.enemies = [];game.next_enemy_uid = 1;game.encounter_state = {};game.lives = 100
	game.player = Vector2i(8, 9);game.turn = 1
	game.hand = [];game.hand_ids = [];game.deck = [];game.discard = [];game.pending_bleeds = []
	E.setup(game, config(id))
	if freeze:
		for enemy in game.enemies: enemy.cd = 999;enemy.period = 999
	game.clear_effects();game.navigation_lock = 0;game.phase = "play";game.screen = "game";game.history.clear()
func actor(uid: int) -> Dictionary:
	for enemy in game.enemies:
		if enemy.uid == uid: return enemy
	return {}
func index_of(uid: int) -> int:
	for index in game.enemies.size():
		if game.enemies[index].uid == uid: return index
	return -1
func guard() -> Dictionary:
	for enemy in game.enemies:
		if enemy.get("unyielding", false): return enemy
	return {}
func phase_to(target: int):
	while game.encounter_state.phases < target:
		E.finish_phase(game, 0.0);game.turn += 1
func turn():
	game.clear_effects();game.input_lock = 0;game.end_turn()
func remove_at(cell: Vector2i):
	for index in range(game.enemies.size() - 1, -1, -1):
		if game.enemies[index].pos == cell: game.enemies.remove_at(index)
func add(kind: String, cell: Vector2i) -> Dictionary:
	game.add_enemy(kind, cell, 999)
	if kind == "stake": game.enemies.back().permanent = true
	return game.enemies.back()
func defeat(enemy: Dictionary, start_bleed: bool = false):
	game.damage_enemy(index_of(enemy.uid), 0.0, 99, start_bleed)
func expect_valid(label: String): check(E.valid_state(game.encounter_state), label + " snapshot validates")

func check_authored_armies():
	var expected = {
		"c2_heavy_pawns": "g4@5,1 e4@3,1 p2@4,4 p1@6,4 p1@8,4",
		"c2_lone_guard": "g4@5,1 a2@4,1 e3@7,1 h2@2,3 p1@5,4 p1@7,4",
		"c2_cannon_fort": "g4@5,1 e3@7,1 c2@2,2 p2@2,4 h2@8,3 p1@5,4",
		"c2_palace_guard": "g6@5,1 a2@4,1 e4@7,1 r2@1,2 p2@4,4 p1@6,4",
		"c2_double_cannon": "g6@5,1 a2@6,1 e4@3,1 c2@2,2 c1@8,2 p2@2,4 p1@8,4",
		"c2_inner_city": "g9@5,1 a2@4,1 e4@7,1 e3@3,1 c2@8,2 r2@1,2 p2@8,4 p1@5,4"}
	var expected_waves = {"c2_heavy_pawns": "9:h2@8,1", "c2_lone_guard": "5:h2@8,1 9:p2@2,3", "c2_cannon_fort": "5:h2@8,1 9:h2@2,1", "c2_palace_guard": "5:h2@8,1 8:h2@2,1 11:p2@8,3", "c2_double_cannon": "5:h2@8,1 8:h2@2,1 11:h2@8,3", "c2_inner_city": "5:h2@8,1 9:h2@2,1 13:h2@8,3"}
	for id in expected:
		fixture(id, false)
		var actual: Array[String] = [];var cells = {};var generals = 0
		for enemy in game.enemies:
			actual.append("%s%d@%d,%d" % [enemy.kind, enemy.hp, enemy.pos.x + 1, enemy.pos.y + 1])
			check(enemy.hp == enemy.max_hp, id + " explicit full maxHP")
			check(enemy.cd == (2 if enemy.kind == "p" else 3) and enemy.period == enemy.cd, id + " ordinary cooldown by kind")
			check(R.inside(enemy.pos) and not cells.has(enemy.pos), id + " unique legal initial square")
			check(enemy.original_spawn == enemy.pos and enemy.kind in ["g", "a", "e", "r", "c", "h", "p"], id + " variants keep ordinary kind and original spawn")
			cells[enemy.pos] = true
			if enemy.kind == "g": generals += 1
			if enemy.get("heavy", false): check(E.enemy_tags(enemy).contains("厚血"), id + " heavy label visible")
			if enemy.get("unyielding", false): check(E.enemy_tags(enemy).contains("不屈"), id + " revival label visible")
		check(" ".join(actual) == expected[id], id + " exact authored army/HP/coordinates")
		check(generals == 1 and not R.threatened(Vector2i(4, 9), game.enemies), id + " one general and safe player spawn")
		actual.clear()
		for wave in C2.TEMPLATES[id].waves:
			actual.append("%d:%s%d@%d,%d" % [wave[0], wave[1][0], wave[1][3], wave[1][1], wave[1][2]])
		check(" ".join(actual) == expected_waves[id], id + " finite authored waves")
		check(E.valid_config(config(id)) and E.is_chapter_two(game), id + " chapter2 config accepted")
		check(E.summary(config(id)).contains("增援") and E.details(config(id)).contains("完整玩家回合") == (not guard().is_empty()), id + " chapter2 preview explains relevant mechanics")
		check(E.details(config(id)).length() < 210, id + " concise mobile rules")
		check(not E.uses_action_credits(game), id + " no inherited chapter1 boss credits")
		for rule in E.RULE_NAMES: check(not E.has_rule(game, rule), id + " no inherited rule " + rule)
		var before = game.enemies.duplicate(true)
		E.prepare_phase(game)
		check(game.enemies == before, id + " no hidden rotation or acceleration")
		expect_valid(id)
	var a = RandomNumberGenerator.new();var b = RandomNumberGenerator.new();a.seed = 113;b.seed = 113
	for row in 8:
		for kind in ["battle", "elite", "boss", "camp"]:
			var left = E.node_config(kind, row, a, 2);var right = E.node_config(kind, row, b, 2)
			check(left == right, "chapter2 map seed determinism")
			check(left.is_empty() if kind == "camp" else E.valid_config(left), "generated chapter2 configuration valid")
			if row == 0 and kind == "battle": check(left.id == "c2_heavy_pawns", "first chapter2 fight always 坚卒拦路")
	check(C2.NORMAL_POOL.count("c2_heavy_pawns") == 1 and C2.NORMAL_POOL.count("c2_lone_guard") == 2 and C2.NORMAL_POOL.count("c2_cannon_fort") == 2, "later normal encounters use authored 1:2:2 weights")
	var invalid = config("c2_lone_guard");invalid.rules = ["last_stand"]
	check(not E.valid_config(invalid), "chapter2 rejects chapter1 rules")
	invalid = config("c2_inner_city");invalid.tier = "battle"
	check(not E.valid_config(invalid), "chapter2 rejects wrong battle tier")
	invalid = config("c2_lone_guard");invalid.erase("chapter")
	check(not E.valid_config(invalid), "chapter2 requires explicit chapter")
	check(E.valid_config({"id": "three_pawns", "tier": "battle", "rules": []}), "legacy chapter1 config still valid")

func check_full_turn_timing():
	fixture();phase_to(3)
	var target = guard();var uid = target.uid;var home = target.original_spawn
	target.pos = Vector2i(4, 1)
	game.queue_bleed(index_of(uid), 1);game.queue_bleed(index_of(uid), 2)
	defeat(target)
	check(actor(uid).is_empty() and game.pending_bleeds.is_empty(), "defeat removes live piece and all queued bleeds")
	check(game.encounter_state.ghosts.size() == 1 and E.markers(game)[0].pos == home, "ghost stays at original spawn, not death square")
	check(game.encounter_state.ghosts[0].ready_phase == 6 and E.markers(game)[0].label == "归3", "mid-player4 defeat shows exact end-phase countdown and waits complete player5 and player6")
	expect_valid("mid-turn ghost")
	turn();check(actor(uid).is_empty() and game.turn == 5 and E.markers(game)[0].label == "归2", "partial player4 cannot count as full turn; visible countdown advances")
	turn();check(actor(uid).is_empty() and game.turn == 6 and E.markers(game)[0].label == "归1", "first full player5 still leaves ghost with one ending remaining")
	var next_uid = game.next_enemy_uid
	turn();target = actor(uid)
	check(not target.is_empty() and game.turn == 7 and target.pos == home, "second full player6 revives after enemy movement")
	check(target.hp == 2 and target.max_hp == 2 and target.cd == 3 and target.period == 3 and target.stun == 0, "revival restores own maxHP clean cooldown and no action on birth")
	check(game.next_enemy_uid == next_uid and game.encounter_state.ghosts.is_empty(), "revival preserves stable uid and consumes no new uid")
	turn();check(target.cd == 2 and target.pos == home, "revived guard counts down only on following phase")
	expect_valid("revived guard")
	# Real delayed bleed resolves after phase 3, with player4 not yet accepting input.
	fixture();phase_to(2);target = guard();uid = target.uid
	game.queue_bleed(index_of(uid), 2);turn()
	check(game.turn == 4 and actor(uid).is_empty() and game.encounter_state.ghosts[0].ready_phase == 5, "start-bleed4 includes the full upcoming player4")
	turn();check(actor(uid).is_empty(), "start-bleed waits player4 complete")
	turn();check(not actor(uid).is_empty() and actor(uid).cd == 3, "start-bleed revives end5 after player4 and5")
	# End-of-player4 damage before enemy phase completion follows the same
	# boundary as any card in player4: only player5 and player6 count in full.
	fixture();phase_to(3);target = guard();uid = target.uid
	defeat(target);E.finish_phase(game, 0.0);game.turn += 1
	phase_to(5);check(actor(uid).is_empty(), "end-player4 defeat does not count the ending partial turn")
	phase_to(6);check(not actor(uid).is_empty(), "end-player4 defeat revives end6")
	# Multiple incarnations keep their own initial spawn and don't carry stun.
	target = actor(uid);target.pos = Vector2i(4, 1);target.stun = 2;defeat(target)
	phase_to(9);target = actor(uid)
	check(not target.is_empty() and target.original_spawn == Vector2i(3, 0) and target.pos == Vector2i(3, 0) and target.hp == 2 and target.stun == 0, "repeated revival reuses original identity and clears stun")

func check_ghost_collision_and_blocking():
	fixture("c2_cannon_fort");var target = guard();var uid = target.uid
	defeat(target)
	var cell = Vector2i(6, 0)
	check(R.occupied(cell, game.enemies) == -1, "ghost is not an occupied target")
	check(R.blockers(Vector2i(5, 0), Vector2i(8, 0), game.enemies) == 0, "ghost is not a cannon screen or rook blocker")
	var horse = {"kind": "h", "pos": Vector2i(4, 1), "stun": 0}
	check(cell in R.moves(horse, game.enemies + [horse], game.player), "ordinary movement can land on ghost square")
	check(game.pending_bleeds.is_empty() and actor(uid).is_empty(), "ghost cannot carry a live damage target")
	for blocker in ["player", "p", "stake"]:
		fixture();phase_to(3);target = guard();uid = target.uid;cell = target.original_spawn
		defeat(target)
		if blocker == "player": game.player = cell
		else: add(blocker, cell)
		phase_to(6)
		check(actor(uid).is_empty() and game.encounter_state.ghosts[0].status == "blocked", blocker + " blocks ready revival")
		check(E.status(game).contains("复归受阻") and E.markers(game)[0].label == "归阻", blocker + " blocked status is visible")
		phase_to(8);check(actor(uid).is_empty(), blocker + " revival waits without timeout or duplicate")
		if blocker == "player": game.player = Vector2i(8, 9)
		else: remove_at(cell)
		phase_to(9)
		check(not actor(uid).is_empty() and actor(uid).pos == cell and actor(uid).cd == 3, blocker + " frees revival at next enemy-phase end")
		expect_valid(blocker + " revival retry")

func check_waves():
	fixture("c2_heavy_pawns");phase_to(7)
	check(E.markers(game).is_empty() and C2.living_reinforcements(game) == 0, "wave not announced prematurely")
	phase_to(8)
	check(E.markers(game).size() == 1 and E.markers(game)[0].pos == Vector2i(7, 0) and E.status(game).contains("下轮增援1"), "wave announces exact square one full player turn early")
	turn()
	var wave = game.encounter_state.waves[0];var target = actor(wave.uid)
	check(wave.status == "arrived" and target.kind == "h" and target.hp == 2 and target.pos == Vector2i(7, 0) and target.cd == 3, "authored wave appears at end9 without birth-phase action")
	check(E.markers(game).is_empty() and C2.living_reinforcements(game) == 1, "arrived wave marker clears and cap count increments")
	phase_to(20);check(C2.living_reinforcements(game) == 1, "finite wave never repeats")
	expect_valid("one finite wave")
	for blocker in ["player", "p", "stake", "cap"]:
		fixture();phase_to(4)
		if blocker == "player": game.player = Vector2i(7, 0)
		elif blocker == "cap":
			add("p", Vector2i(0, 8)).reinforcement = true
			add("h", Vector2i(1, 8)).reinforcement = true
		else: add(blocker, Vector2i(7, 0))
		phase_to(5);wave = game.encounter_state.waves[0]
		check(wave.status == "blocked" and wave.blocked_phases == 1, blocker + " first failed check postpones wave")
		check(E.status(game).contains("增援1受阻1/2") and E.markers(game)[0].label == "援阻", blocker + " delayed wave shown on HUD and board")
		expect_valid(blocker + " blocked wave")
		phase_to(6);check(wave.status == "blocked" and wave.blocked_phases == 2, blocker + " permits second delayed phase")
		phase_to(7);check(wave.status == "cancelled" and wave.uid == -1, blocker + " third failed check cancels permanently")
		if blocker == "player": game.player = Vector2i(8, 9)
		elif blocker == "cap":
			for index in range(game.enemies.size() - 1, -1, -1):
				if game.enemies[index].get("reinforcement", false): game.enemies.remove_at(index)
		else: remove_at(Vector2i(7, 0))
		phase_to(8);check(wave.status == "cancelled" and wave.uid == -1, blocker + " later opening cannot bank cancelled wave")
		check(E.status(game).contains("已取消1波"), blocker + " cancelled wave remains visible in status")
		expect_valid(blocker + " cancelled wave")
	# Clearing the obstruction during either permitted delay must still work.
	for free_after in [5, 6]:
		fixture();add("stake", Vector2i(7, 0));phase_to(free_after)
		remove_at(Vector2i(7, 0));phase_to(free_after + 1)
		wave = game.encounter_state.waves[0]
		check(wave.status == "arrived" and actor(wave.uid).cd == 3, "free square accepts wave on permitted delayed ending " + str(free_after + 1))
		expect_valid("delayed arrival")
	fixture("c2_palace_guard");phase_to(5);wave = game.encounter_state.waves[0];actor(wave.uid).pos = Vector2i(0, 8)
	phase_to(8);wave = game.encounter_state.waves[1];actor(wave.uid).pos = Vector2i(1, 8)
	phase_to(13)
	check(C2.living_reinforcements(game) == 2 and game.encounter_state.waves[2].status == "cancelled", "third finite wave respects all-kind live reinforcement cap")
	# The ordinary opening horse is deliberately not counted toward the cap.
	fixture();phase_to(5);actor(game.encounter_state.waves[0].uid).pos = Vector2i(0, 8)
	remove_at(Vector2i(1, 2));phase_to(9)
	wave = game.encounter_state.waves[1];target = actor(wave.uid)
	check(wave.status == "arrived" and target.kind == "p" and target.hp == 2 and target.heavy and target.cd == 2, "later heavy-pawn wave retains kind HP and ordinary pawn cadence")
	check(C2.living_reinforcements(game) == 2, "all reinforcement kinds count, opening army does not")

func check_expiring_stake_boundaries():
	fixture();phase_to(2)
	var target = guard();var uid = target.uid;var cell = target.original_spawn
	defeat(target);phase_to(4)
	var stake = add("stake", cell);stake.permanent = false;stake.ttl = 1
	var stake_uid = stake.uid
	turn()
	check(actor(stake_uid).is_empty() and not actor(uid).is_empty() and actor(uid).pos == cell and actor(uid).cd == 3, "ttl1 stake expires before same-ending ready revival checks occupancy")
	check(game.encounter_state.ghosts.is_empty(), "expiring stake never adds a spurious extra revival round")
	expect_valid("stake expiry and revival")
	fixture();phase_to(4)
	stake = add("stake", Vector2i(7, 0));stake.permanent = false;stake.ttl = 1;stake_uid = stake.uid
	turn()
	var wave = game.encounter_state.waves[0]
	check(actor(stake_uid).is_empty() and wave.status == "arrived" and wave.blocked_phases == 0, "ttl1 stake expires before same-ending wave arrival checks occupancy")
	check(actor(wave.uid).cd == 3 and actor(wave.uid).pos == Vector2i(7, 0), "wave still does not act when entering newly expired stake square")
	expect_valid("stake expiry and wave")

func check_revival_priority_and_cancellation():
	# Authored cells differ. This controlled internal fixture makes a ready
	# ghost share an announced wave entry to assert the fixed lifecycle order.
	fixture();phase_to(2)
	var target = guard();var uid = target.uid;defeat(target)
	game.encounter_state.ghosts[0].enemy.original_spawn = Vector2i(7, 0)
	game.encounter_state.ghosts[0].enemy.pos = Vector2i(7, 0)
	phase_to(5)
	check(actor(uid).pos == Vector2i(7, 0) and game.encounter_state.waves[0].status == "blocked", "ready revival wins shared square before reinforcement")
	fixture();phase_to(3);defeat(guard());phase_to(4)
	check(not game.encounter_state.ghosts.is_empty() and not E.markers(game).is_empty(), "cancellation fixture has a ghost and announced wave")
	defeat(game.enemies[0])
	check(game.encounter_state.cancelled and game.encounter_state.ghosts.is_empty() and E.markers(game).is_empty(), "general death immediately cancels ghosts and markers")
	for wave in game.encounter_state.waves: check(wave.status == "cancelled", "general death cancels every future wave")
	phase_to(20)
	check(C2.living_reinforcements(game) == 0 and game.encounter_state.ghosts.is_empty(), "general death never permits late resurrection or wave")
	E.cancel_pending(game);expect_valid("idempotent battle cancellation")
	fixture();defeat(guard());game.settle_victory()
	check(game.encounter_state.cancelled and game.encounter_state.ghosts.is_empty(), "debug/victory settlement also cancels pending lifecycle")

func check_snapshots_and_save_validation():
	fixture();phase_to(3)
	var target = guard();var uid = target.uid;defeat(target)
	var before = game.history.capture()
	for repeat in 5:
		E.markers(game);E.status(game);E.summary(game.encounter_state.config);E.details(game.encounter_state.config)
	check(game.history.capture() == before, "all chapter2 marker status and preview queries are read-only")
	turn();var after = game.history.capture()
	check(game.history.undo() and game.history.capture() == before, "undo restores full ghost and wave lifecycle")
	turn();check(game.history.capture() == after, "replayed phase yields identical lifecycle and RNG")
	phase_to(5);before = game.history.capture();turn();after = game.history.capture()
	check(not actor(uid).is_empty() and game.history.undo() and game.history.capture() == before, "undo resurrection restores nonblocking ghost and stable uid")
	turn();check(game.history.capture() == after, "resurrection replay exactly restores own HP UID and wave state")
	# Use a real chapter-two route node and native save/resume, not a detached
	# dictionary fixture. Node configuration remains the generated fixed config.
	game.new_expedition();game.route.generate(20261021, 2)
	game.route.state.nodes[0].encounter = config("c2_lone_guard")
	game.route.enter(0)
	for enemy in game.enemies: enemy.cd = 999;enemy.period = 999
	game.player = Vector2i(8, 9);game.lives = 100
	phase_to(3);uid = guard().uid;defeat(guard());phase_to(4)
	before = game.history.capture();var saved_route = game.route.state.duplicate(true)
	game.route.save();game.show_home()
	check(game.route.resume() and game.history.capture() == before and game.route.state == saved_route, "chapter2 save/resume retains pending ghost announced wave and exact identity")
	phase_to(6);check(not actor(uid).is_empty() and actor(uid).hp == 2, "resumed ghost restores correct own maxHP")
	var valid = game.encounter_state.duplicate(true)
	check(E.valid_state(valid), "resumed post-revival state validates")
	valid.waves[0].uid = -1;check(not E.valid_state(valid), "arrived wave needs stable positive uid")
	fixture();defeat(guard());valid = game.encounter_state.duplicate(true)
	valid.ghosts.append(valid.ghosts[0].duplicate(true));check(not E.valid_state(valid), "duplicate ghost rejected")
	valid = game.encounter_state.duplicate(true);valid.ghosts[0].ready_phase -= 1
	check(not E.valid_state(valid), "partial-turn early revival rejected by schema")
	valid = game.encounter_state.duplicate(true);valid.ghosts[0].enemy.max_hp = 999
	check(not E.valid_state(valid), "ghost cannot forge maximum HP")
	valid = game.encounter_state.duplicate(true);valid.cancelled = true
	check(not E.valid_state(valid), "cancelled encounter cannot retain ghosts")
	valid = game.encounter_state.duplicate(true);valid.waves[0].blocked_phases = 3
	check(not E.valid_state(valid), "wave cannot bank more than two postponed phases")
	valid = game.encounter_state.duplicate(true);valid.waves.remove_at(0)
	check(not E.valid_state(valid), "finite wave schedule cannot silently disappear")
	fixture("c2_inner_city");var general = game.enemies[0];game.damage_enemy(0, 0.0, 1)
	check(general.hp == 8 and not game.encounter_state.has("retaliated"), "chapter2 boss hit never activates chapter1 last stand")

func run():
	game = load("res://main.tscn").instantiate();root.add_child(game)
	check_authored_armies()
	check_full_turn_timing()
	check_ghost_collision_and_blocking()
	check_waves()
	check_expiring_stake_boundaries()
	check_revival_priority_and_cancellation()
	check_snapshots_and_save_validation()
	print("CHAPTER TWO MECHANICS RESULT ", checks - failures, " passed, ", failures, " failed")
	game.queue_free();quit(1 if failures else 0)
