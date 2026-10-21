extends SceneTree
# Boss acceleration is banked across phases, never a second movement in one phase.
const E = preload("res://encounters.gd")
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
func fixture(rules: Array = ["palace_rotation", "last_stand"]):
	game.tutorial.stop();game.player_skill = "king";game.new_run()
	game.enemies = [];game.encounter_state = {};game.lives = 100
	game.player = Vector2i(8, 9);game.hand = [];game.hand_ids = [];game.deck = [];game.discard = []
	game.rng.seed = 42
	E.setup(game, {"id": "palace_final", "tier": "boss", "rules": rules})
	for enemy in game.enemies: enemy.cd = 999;enemy.period = 999;enemy.intent = Vector2i(-1, -1)
	game.clear_effects();game.navigation_lock = 0;game.phase = "play";game.screen = "game"
	game.history.clear()
func add(kind: String, pos: Vector2i, period: int = 3) -> Dictionary:
	game.add_enemy(kind, pos, period)
	return game.enemies.back()
func actor(uid: int) -> Dictionary:
	for enemy in game.enemies:
		if enemy.uid == uid: return enemy
	return {}
func movement_count(uid: int) -> int:
	var count = 0
	for fx in game.effects:
		if fx.kind == "move" and fx.get("piece", {}).get("uid", -1) == uid: count += 1
	return count
func turn():
	game.clear_effects();game.input_lock = 0;game.end_turn()
func pawn_fixture(credits: int, countdown: int = 3) -> Dictionary:
	fixture(["last_stand"])
	game.enemies = [game.enemies[0]];game.encounter_state.guard_uids = []
	var pawn = add("p", Vector2i(2, 0), 3)
	pawn.cd = countdown;pawn.action_credits = credits
	return pawn
func check_dual_trigger():
	fixture()
	var guard = actor(E.selected_guard(game));var uid = guard.uid
	guard.cd = 3;guard.period = 3
	game.damage_enemy(0, 0, 1)
	check(guard.get("action_credits", 0) == 1, "retaliation grants one durable action credit immediately")
	var origin = guard.pos
	turn()
	check(movement_count(uid) == 1 and guard.pos != origin, "rotation plus retaliation executes only one first-phase movement")
	check(guard.get("action_credits", 0) == 1 and guard.cd == 3, "first movement resets ordinary timer without deleting overflow")
	origin = guard.pos
	turn()
	check(movement_count(uid) == 1 and guard.pos != origin, "remaining credit grants immediate following-phase movement despite period three")
	check(guard.get("action_credits", 0) == 0 and guard.cd == 3, "second phase consumes only last credit")
	turn()
	check(movement_count(uid) == 0 and guard.cd == 2, "ordinary countdown resumes after credit exhaustion")
func check_three_credits_and_natural_readiness():
	var pawn = pawn_fixture(3)
	for phase in 3:
		turn()
		check(movement_count(pawn.uid) == 1 and pawn.pos == Vector2i(2, phase + 1), "three credits grant one movement on successive phase " + str(phase))
		check(pawn.action_credits == 2 - phase and pawn.cd == 3, "credit balance survives countdown reset " + str(phase))
	turn();check(movement_count(pawn.uid) == 0 and pawn.cd == 2, "no fourth forced movement")
	turn();check(movement_count(pawn.uid) == 0 and pawn.cd == 1, "normal second cooldown phase")
	turn();check(movement_count(pawn.uid) == 1 and pawn.action_credits == 0, "normal movement eventually fires with nonnegative zero balance")
	pawn = pawn_fixture(2, 1)
	turn();check(movement_count(pawn.uid) == 1 and pawn.action_credits == 1, "natural readiness and credit never double-move")
	turn();check(movement_count(pawn.uid) == 1 and pawn.action_credits == 0, "natural readiness does not erase excess credit")
func check_freeze_block_and_attack():
	var pawn = pawn_fixture(2)
	pawn.stun = 2
	turn();check(movement_count(pawn.uid) == 0 and pawn.action_credits == 2 and pawn.stun == 1, "freeze preserves credits first phase")
	turn();check(movement_count(pawn.uid) == 0 and pawn.action_credits == 2 and pawn.stun == 0, "freeze preserves credits second phase")
	turn();check(movement_count(pawn.uid) == 1 and pawn.action_credits == 1, "unfrozen pawn consumes one stored credit")
	pawn = pawn_fixture(2)
	var blocker = add("stake", Vector2i(2, 1), 999)
	turn();check(movement_count(pawn.uid) == 0 and pawn.action_credits == 2, "no legal move retains full credit balance")
	game.enemies.erase(blocker)
	turn();check(movement_count(pawn.uid) == 1 and pawn.action_credits == 1, "credit works once blocked square opens")
	pawn = pawn_fixture(2)
	game.player = Vector2i(2, 1)
	var before = game.lives
	turn();check(game.lives == before - 1 and movement_count(pawn.uid) == 0 and pawn.action_credits == 2, "attacker cannot also move or consume credits on attack phase")
	game.player = Vector2i(8, 9)
	turn();check(movement_count(pawn.uid) == 1 and pawn.action_credits == 1, "attacker's preserved credit works in later safe phase")
	pawn = pawn_fixture(2)
	game.player = Vector2i(2, 1);game.shield_charges = 1
	turn();check(movement_count(pawn.uid) == 0 and pawn.action_credits == 2, "shield-blocked attacker also retains credits without moving")
func check_legacy_and_isolation():
	var pawn = pawn_fixture(0)
	pawn.erase("action_credits");pawn.bonus_pending = true
	turn();check(movement_count(pawn.uid) == 1 and pawn.get("action_credits", 0) == 0 and not pawn.bonus_pending, "legacy pending bonus converts once into an immediate boss action")
	turn();check(movement_count(pawn.uid) == 0 and pawn.get("action_credits", 0) == 0, "legacy conversion cannot repeat")
	pawn = pawn_fixture(0)
	pawn.erase("action_credits");pawn.erase("bonus_pending")
	turn();check(movement_count(pawn.uid) == 0 and pawn.get("action_credits", 0) == 0, "old save without optional fields keeps ordinary countdown")
	pawn = pawn_fixture(2)
	var dead_uid = pawn.uid;game.enemies.erase(pawn)
	var newcomer = add("p", Vector2i(2, 0), 3)
	check(newcomer.uid != dead_uid and newcomer.get("action_credits", 0) == 0, "replacement enemy does not inherit removed enemy credits")
	turn();check(movement_count(newcomer.uid) == 0, "new enemy cannot spend removed enemy credit")
	fixture()
	var guard = actor(E.selected_guard(game));guard.action_credits = 3
	game.new_run()
	for enemy in game.enemies: check(enemy.get("action_credits", 0) == 0, "new battle clears previous living guard credit")
func check_undo_and_reload():
	var pawn = pawn_fixture(2)
	var uid = pawn.uid;var before = game.history.capture()
	turn();var after = game.history.capture()
	check(game.history.undo() and game.history.capture() == before, "undo restores credit balance countdown and RNG")
	turn();check(game.history.capture() == after, "replay spends same one credit and reaches same position")
	check(actor(uid).action_credits == 1, "replayed actor retains remaining credit")
	game.new_expedition()
	game.route.state.visited = [0, 2, 4, 6, 7, 10, 13]
	game.route.state.current = 13
	game.route.enter(15)
	check(game.screen == "game" and E.uses_action_credits(game), "real route enters accelerated boss")
	guard_for_save(3, false)
	var saved = game.history.capture();var saved_route = game.route.state.duplicate(true)
	game.route.save();game.show_home()
	check(game.route.resume() and game.history.capture() == saved and game.route.state == saved_route, "real save resume preserves credits without new schema wipe")
	var saved_guard = actor(E.selected_guard(game));var guard_uid = saved_guard.uid
	saved_guard.erase("action_credits");saved_guard.bonus_pending = true
	game.route.save();game.show_home()
	check(game.route.resume(), "legacy v0100 boss save missing credit field remains readable")
	turn()
	check(movement_count(guard_uid) == 1 and actor(guard_uid).get("action_credits", 0) == 1 and not actor(guard_uid).bonus_pending, "resumed legacy retaliation and rotation combine into preserved overflow")
func guard_for_save(credits: int, pending: bool):
	var guard = actor(E.selected_guard(game))
	guard.action_credits = credits;guard.bonus_pending = pending;guard.period = 3;guard.cd = 3
func check_delayed_bleed():
	var pawn = pawn_fixture(0, 1)
	game.queue_bleed(0, 1)
	turn()
	check(movement_count(pawn.uid) == 1 and pawn.pos == Vector2i(2, 1), "delayed damage does not add retroactive movement")
	check(game.encounter_state.retaliated and pawn.action_credits == 1, "bleed at phase end banks retaliation for next phase")
	turn();check(movement_count(pawn.uid) == 1 and pawn.pos == Vector2i(2, 2) and pawn.action_credits == 0, "late retaliation acts next phase despite reset cooldown")
func check_control_and_warning():
	var pawn = pawn_fixture(2)
	check(E.available_action_credits(game, pawn) == 2 and E.effective_countdown(game, pawn) == 1, "banked credits show imminent action")
	var snapshot = game.history.capture()
	for repetition in 5:
		E.available_action_credits(game, pawn, true);E.effective_countdown(game, pawn)
	check(game.history.capture() == snapshot, "warning queries are pure and never grant or consume credits")
	game.player = Vector2i(1, 0);game.energy = 3
	game.hand = ["suppress"];game.hand_ids = [];game.sync_hand_ids()
	game.play_card(0, game.player)
	check(pawn.action_credits == 2 and pawn.get("action_credit_delay", 0) == 2 and pawn.cd == 5, "suppression postpones credits and normal cooldown without deleting balance")
	check(E.effective_countdown(game, pawn) == 3, "suppression warning shows three phases until credited movement")
	game.player = Vector2i(8, 9)
	turn();check(movement_count(pawn.uid) == 0 and pawn.action_credit_delay == 1 and pawn.action_credits == 2, "first suppression phase preserves credits")
	turn();check(movement_count(pawn.uid) == 0 and pawn.action_credit_delay == 0 and pawn.action_credits == 2, "second suppression phase preserves credits")
	turn();check(movement_count(pawn.uid) == 1 and pawn.action_credits == 1, "delayed credits resume after suppression")
	pawn = pawn_fixture(1);pawn.action_credit_delay = 2;pawn.stun = 1
	turn();check(pawn.action_credit_delay == 2 and pawn.action_credits == 1, "freeze does not run down credit delay")
	fixture()
	var guard = actor(E.selected_guard(game))
	guard.cd = 3;guard.period = 3
	check(E.effective_countdown(game, guard) == 1 and E.available_action_credits(game, guard, true) == 1, "rotation-selected guard displays imminent movement before phase prepares")
	check(guard.get("action_credits", 0) == 0, "rotation preview does not grant actual credit")
	var legacy = pawn_fixture(0);legacy.erase("action_credits");legacy.bonus_pending = true
	check(E.available_action_credits(game, legacy) == 1 and E.effective_countdown(game, legacy) == 1, "legacy pending acceleration is visible before conversion")
	check(not legacy.has("action_credits") and legacy.bonus_pending, "legacy warning leaves conversion untouched")
func check_many_phases_and_other_elites():
	for seed_value in range(12):
		fixture();game.rng.seed = seed_value
		for enemy in game.enemies: enemy.cd = 3;enemy.period = 3
		if seed_value % 2 == 0: game.damage_enemy(0, 0, 1)
		for phase in range(8):
			turn()
			for enemy in game.enemies:
				check(movement_count(enemy.uid) <= 1, "boss movement cap seed %d phase %d uid %d" % [seed_value, phase, enemy.uid])
				check(enemy.get("action_credits", 0) >= 0, "credit never negative")
	fixture()
	game.encounter_state.config = {"id": "rook_pressure", "tier": "elite", "rules": ["double_step"]}
	game.enemies = [game.enemies[0]];game.encounter_state.guard_uids = []
	var pawn = add("p", Vector2i(2, 0), 1)
	pawn.march_mark = true;pawn.normal_moves = 1
	turn();check(pawn.pos == Vector2i(2, 2) and movement_count(pawn.uid) == 2, "explicit marked double-step elite remains double movement")
	fixture()
	game.encounter_state.config = {"id": "two_wings", "tier": "elite", "rules": ["last_stand"]}
	game.enemies = [game.enemies[0]];game.encounter_state.guard_uids = []
	pawn = add("p", Vector2i(2, 0), 1)
	game.damage_enemy(0, 0, 1);turn()
	check(pawn.pos == Vector2i(2, 2) and movement_count(pawn.uid) == 2, "non-boss retaliation elite behavior is unchanged")
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game)
	check_dual_trigger()
	check_three_credits_and_natural_readiness()
	check_freeze_block_and_attack()
	check_legacy_and_isolation()
	check_undo_and_reload()
	check_delayed_bleed()
	check_control_and_warning()
	check_many_phases_and_other_elites()
	print("BOSS ACTION CREDIT RESULT ", checks - failures, " passed, ", failures, " failed")
	game.queue_free();quit(1 if failures else 0)
