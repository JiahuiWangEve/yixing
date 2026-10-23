extends SceneTree
# Presentation must identify the real attacker without becoming a second combat action.
# Run with disposable XDG directories, as scripts/verify.sh does.
const R = preload("res://rules.gd")
var game
var checks = 0
var failures = 0

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("ENEMY IMPACT: " + label)
func fresh(lives: int = 3, role: String = "king", treasure: String = ""):
	game.player_skill = role;game.seed_value = 158907
	if treasure.is_empty(): game.new_run()
	else:
		game.new_expedition();game.route.enter(0);game.route.state.treasure_id = treasure
	game.enemies = [];game.encounter_state = {};game.player = Vector2i(4, 5)
	game.lives = lives;game.energy = 20;game.stage = 1;game.turn = 1
	game.hand = [];game.hand_ids = [];game.deck = [];game.discard = [];game.pending_bleeds = []
	game.phase = "play";game.screen = "game";game.treasures.reset_battle()
	game.clear_effects();game.presentation.clear();game.card_picker.close();game.history.clear()
	game.input_lock = 0;game.navigation_lock = 0;game.sync_hand_views()
func add(kind: String = "p", cell: Vector2i = Vector2i(4, 4), period: int = 1) -> Dictionary:
	game.add_enemy(kind, cell, period)
	return game.enemies.back()
func fx_of(kind: String) -> Array:
	return game.effects.filter(func(fx): return fx.kind == kind)
func snapshot() -> Dictionary:
	var state: Dictionary = game.history.capture()
	state.erase("initial_threat")
	for enemy in state.enemies: enemy.erase("visual")
	return state
func cloned_rng() -> RandomNumberGenerator:
	var random = RandomNumberGenerator.new();random.state = game.rng.state
	return random
func finish():
	game._process(5.0)
	check(game.effects.is_empty() and game.input_lock <= 0, "complete playback releases effects and input lock")
func check_contact(fx: Dictionary, label: String):
	check(is_equal_approx(fx.duration, 0.34) and is_equal_approx(fx.impact_at, 0.14), label + " uses readable approach and return timing")
	check(not fx.has("piece") and fx.has("attacker_uid"), label + " stores stable identity instead of a mutable actor reference")
	check(fx.from.is_equal_approx(game.cell_pos(fx.origin_cell)) and fx.to.is_equal_approx(game.cell_pos(fx.target_cell)), label + " captures actual attack origin and target")

func run():
	game = load("res://main.tscn").instantiate();root.add_child(game)
	game.settings.set_debug_mode(true);game.set_process(false)
	check_normal_hits()
	check_attacker_types()
	check_guard_only()
	check_following_movement()
	check_guard_then_hit()
	check_lethal()
	check_talisman()
	check_no_recoil_destination()
	check_self_cost()
	check_stable_actor()
	check_clear_undo_restart()
	print("ENEMY IMPACT RESULT %d checks, %d failures" % [checks, failures])
	game.free();quit(1 if failures else 0)

func check_normal_hits():
	for role in ["king", "horse", "artillery"]:
		fresh(3, role)
		var actor = add();var origin: Vector2i = actor.pos;var target: Vector2i = game.player
		var random = cloned_rng();var safe = R.safe_recoil(target, game.enemies)
		var expected: Vector2i = safe[random.randi_range(0, safe.size() - 1)]
		game.end_turn()
		var impacts = fx_of("enemy_impact");var hits = fx_of("player_hit");var recoil = fx_of("recoil")
		check(impacts.size() == 1 and hits.size() == 1 and recoil.size() == 1, role + " real end_turn queues exactly one collision, hit and recoil")
		if impacts.is_empty() or hits.is_empty() or recoil.is_empty(): continue
		var fx: Dictionary = impacts[0];check_contact(fx, role)
		check(fx.attacker_uid == actor.uid and fx.origin_cell == origin and fx.target_cell == target, role + " effect identifies actual attacker before recoil")
		check(game.lives == 2 and game.player == expected and game.turn == 2 and game.phase == "play", role + " damage, destination and next turn settle synchronously")
		check(game.rng.state == random.state, role + " consumes only original single recoil RNG draw")
		check(actor.pos == origin and fx_of("move").is_empty(), role + " attacker collision is not an extra logical movement")
		check(actor.cd == actor.period, role + " ready attacker still spends its normal action without moving")
		check(is_equal_approx(hits[0].delay, 0.14) and is_equal_approx(hits[0].sound_at, hits[0].delay), role + " hit feedback and hurt cue wait for contact")
		check(is_equal_approx(recoil[0].delay, hits[0].delay) and is_equal_approx(game.input_lock, 0.48), role + " recoil starts at contact and remains input-locked to completion")
		var settled = snapshot();var start: Vector2 = game.cell_pos(origin);var end: Vector2 = game.cell_pos(target)
		game._process(0.07)
		check(not actor.visual.is_equal_approx(start) and actor.visual.distance_to(end) < start.distance_to(end), role + " correct piece visibly approaches player")
		check(game.player_visual.is_equal_approx(end) and game.displayed_lives() == 3 and not hits[0].sound_played, role + " player and displayed HP remain pre-hit during approach")
		game._process(0.07)
		check(game.displayed_lives() == 2 and hits[0].sound_played, role + " HP and hurt cue change at impact")
		check(is_equal_approx(actor.visual.distance_to(end), game.CELL * 0.75), role + " token reaches player contact rather than a logical destination")
		game._process(0.10)
		check(actor.visual.distance_to(start) > 0 and actor.visual.distance_to(start) < start.distance_to(end) - game.CELL * 0.75, role + " attacker returns along the same excursion")
		game._process(0.11)
		check(actor.visual.is_equal_approx(start) and game.input_lock > 0, role + " actor returns before recoil unlocks")
		finish()
		check(snapshot() == settled and game.player_visual.is_equal_approx(game.cell_pos(expected)), role + " playing frames changes no combat fields or RNG")

func check_attacker_types():
	var fixtures = [
		["p", Vector2i(4, 4), Vector2i(4, 5)], ["q", Vector2i(3, 5), Vector2i(4, 5)],
		["r", Vector2i(0, 5), Vector2i(4, 5)], ["h", Vector2i(2, 4), Vector2i(4, 5)],
		["a", Vector2i(3, 0), Vector2i(4, 1)], ["e", Vector2i(2, 2), Vector2i(4, 4)],
		["g", Vector2i(4, 0), Vector2i(4, 1)], ["c", Vector2i(4, 0), Vector2i(4, 5)]
	]
	for data in fixtures:
		fresh();game.player = data[2]
		var actor = add(data[0], data[1], 99)
		if data[0] == "c": add("stake", Vector2i(4, 2), 99)
		game.clear_effects();game.end_turn()
		var impacts = fx_of("enemy_impact")
		check(impacts.size() == 1 and impacts[0].attacker_uid == actor.uid, data[0] + " threat launches the actual piece even when countdown is not ready")
		check(actor.pos == data[1] and game.lives == 2, data[0] + " attack rules and logical origin stay unchanged")

func check_guard_only():
	fresh();var actor = add();var origin: Vector2i = game.player
	game.shield_charges = 1;var rng_state = game.rng.state;game.end_turn()
	var impacts = fx_of("enemy_impact");var guard = fx_of("guard")
	check(impacts.size() == 1 and guard.size() == 1 and fx_of("player_hit").is_empty() and fx_of("recoil").is_empty(), "guard still shows its attacker without false damage or recoil")
	if impacts.is_empty() or guard.is_empty(): return
	check(game.lives == 3 and game.player == origin and game.shield_charges == 0 and game.rng.state == rng_state, "shield expenditure settles once without damage or RNG")
	check(is_equal_approx(guard[0].delay, 0.14) and is_equal_approx(game.input_lock, 0.34), "guard flash waits for contact and input lock covers return")
	var settled = snapshot();game._process(0.07)
	check(not actor.visual.is_equal_approx(game.cell_pos(actor.pos)) and game.displayed_lives() == 3, "blocked piece visibly lunges with unchanged HP")
	finish();check(snapshot() == settled, "guard playback cannot attack twice or move the blocker")

func check_following_movement():
	for shielded in [false, true]:
		fresh();var actor = add();var ally = add("p", Vector2i(0, 0))
		var origin: Vector2i = ally.pos;game.shield_charges = 1 if shielded else 0
		game.end_turn();var movement = fx_of("move")
		check(movement.size() == 1 and movement[0].piece.uid == ally.uid, "only non-attacker receives its one normal move after impact")
		if movement.is_empty(): continue
		check(ally.pos != origin and ally.get("normal_moves", 0) == 1 and actor.get("normal_moves", 0) == 0, "collision adds no normal move or bonus movement count")
		check(is_equal_approx(movement[0].delay, 0.34 if shielded else 0.48), "other movement waits until blocked return or damaging recoil finishes")
		var settled = snapshot();game._process(0.07)
		check(ally.visual.is_equal_approx(game.cell_pos(origin)) and not actor.visual.is_equal_approx(game.cell_pos(actor.pos)), "queued mover holds origin while actual attacker approaches")
		finish();check(snapshot() == settled and ally.visual.is_equal_approx(game.cell_pos(ally.pos)), "normal movement and impact playback preserve one settled logical action")

func check_guard_then_hit():
	fresh();var blocked = add();var damaging = add("p", Vector2i(3, 5));var ignored = add("p", Vector2i(5, 5), 99)
	game.shield_charges = 1;var origin: Vector2i = game.player;game.end_turn()
	var impacts = fx_of("enemy_impact");var guard = fx_of("guard");var hits = fx_of("player_hit")
	check(impacts.size() == 2 and guard.size() == 1 and hits.size() == 1, "shield then real damage shows exactly two attackers")
	if impacts.size() != 2 or guard.is_empty() or hits.is_empty(): return
	check(impacts[0].attacker_uid == blocked.uid and impacts[1].attacker_uid == damaging.uid, "collisions preserve original enemy-list attack order")
	check(impacts.all(func(fx): return fx.attacker_uid != ignored.uid and fx.target_cell == origin), "first damaging hit stops attack resolution and both effects retain pre-recoil target")
	check(is_equal_approx(impacts[1].delay, impacts[0].delay + impacts[0].duration) and is_equal_approx(hits[0].delay, 0.48), "blocked return finishes before next attacker approaches")
	check(game.lives == 2 and game.shield_charges == 0 and is_equal_approx(game.input_lock, 0.82), "two ordered impacts preserve one damage and complete recoil lock")
	var settled = snapshot();game._process(0.07)
	check(not blocked.visual.is_equal_approx(game.cell_pos(blocked.pos)) and damaging.visual.is_equal_approx(game.cell_pos(damaging.pos)), "first attacker moves alone before blocked contact")
	game._process(0.31)
	check(blocked.visual.is_equal_approx(game.cell_pos(blocked.pos)) and not damaging.visual.is_equal_approx(game.cell_pos(damaging.pos)), "second attacker approaches only after first returns")
	check(game.displayed_lives() == 3 and game.player_visual.is_equal_approx(game.cell_pos(origin)), "pending damaging impact keeps original player and HP visible")
	game._process(0.11);check(game.displayed_lives() == 2 and hits[0].sound_played, "second contact releases actual damage feedback")
	finish();check(snapshot() == settled, "sequential playback cannot consume another shield, hit or RNG draw")

func check_lethal():
	fresh(1);var actor = add();var origin: Vector2i = game.player;var rng_state = game.rng.state
	game.end_turn();var hits = fx_of("player_hit")
	check(game.phase == "dead" and game.lives == 0 and game.turn == 1, "lethal damage still settles death synchronously")
	check(fx_of("enemy_impact").size() == 1 and hits.size() == 1 and fx_of("recoil").is_empty(), "lethal attack still shows collision and hit, not recoil")
	check(game.player == origin and game.rng.state == rng_state and game.input_lock >= 0.34, "lethal collision preserves original position/RNG and full return lock")
	var settled = snapshot();game._process(0.07)
	check(game.displayed_lives() == 1 and not actor.visual.is_equal_approx(game.cell_pos(actor.pos)), "lethal actor approaches before displayed HP reaches zero")
	game._process(0.08);check(game.displayed_lives() == 0, "lethal HP becomes visible at contact")
	finish();check(snapshot() == settled, "lethal playback never advances turn or repeats death")

func check_talisman():
	fresh(1, "king", "life_talisman");add();game.end_turn()
	check(game.lives == 1 and game.treasure_battle.talisman_used and game.phase == "play", "talisman still rescues lethal enemy attack immediately")
	check(fx_of("enemy_impact").size() == 1 and fx_of("player_hit").size() == 1 and fx_of("recoil").size() == 1, "rescued hit keeps full attacker and recoil presentation")
	var settled = snapshot();game._process(0.07)
	check(game.displayed_lives() == 1, "talisman approach never exposes impossible negative HP")
	finish();check(snapshot() == settled and game.treasure_battle.trigger_serial == 1, "talisman triggers once rather than again during contact")

func check_no_recoil_destination():
	fresh();var actor = add()
	for y in 10:
		for x in 9:
			var cell = Vector2i(x, y)
			if cell != game.player and cell != actor.pos: add("stake", cell, 99)
	var rng_state = game.rng.state;game.end_turn()
	check(game.phase == "dead" and game.lives == 2 and game.rng.state == rng_state, "no-safe-cell loss retains original damage and no RNG draw")
	check(fx_of("enemy_impact").size() == 1 and fx_of("player_hit").size() == 1 and fx_of("recoil").is_empty(), "blocked retreat still identifies attacker without fabricating movement")
	var settled = snapshot();finish();check(snapshot() == settled, "no-safe-cell collision is presentation only")

func check_self_cost():
	fresh();add("g", Vector2i(8, 0), 99);var victim = add();victim.hp = 8;victim.max_hp = 8
	game.hand = ["blood_edge"];game.collection = ["blood_edge"];game.sync_hand_views();game.shield_charges = 1
	var origin: Vector2i = game.player;var rng_state = game.rng.state
	game.play_card(0, victim.pos)
	check(game.lives == 2 and victim.hp == 6 and game.shield_charges == 1, "real blood-edge play still pays self-cost and deals damage")
	check(fx_of("enemy_impact").is_empty() and fx_of("player_hit").is_empty() and fx_of("recoil").is_empty(), "self-cost cannot invent an enemy collision")
	check(game.displayed_lives() == 2 and game.player == origin and game.rng.state == rng_state, "self-cost HP is immediate with no recoil or random change")

func check_stable_actor():
	fresh();var actor = add();var other = add("p", Vector2i(0, 0), 99);game.end_turn()
	var fx: Dictionary = fx_of("enemy_impact")[0];game.enemies.reverse();game._process(0.07)
	check(not actor.visual.is_equal_approx(game.cell_pos(actor.pos)) and other.visual.is_equal_approx(game.cell_pos(other.pos)), "reordering array cannot retarget collision to another piece")
	game.enemies.erase(actor);var replacement = add("p", fx.origin_cell, 99);game._process(0.01)
	check(game.impact_actor(fx).is_empty() and replacement.visual.is_equal_approx(game.cell_pos(replacement.pos)), "removed attacker cannot animate a same-square replacement")
	check(fx.attacker_uid != replacement.uid, "replacement has a distinct stable UID")
	fresh();actor = add();game.end_turn();fx = fx_of("enemy_impact")[0]
	actor.pos = Vector2i(1, 1);game._process(0.07)
	check(game.impact_actor(fx).is_empty() and actor.visual.is_equal_approx(game.cell_pos(actor.pos)), "stale origin cannot drag a logically relocated actor back into its old attack")

func check_clear_undo_restart():
	fresh();add();var before = snapshot();game.battle_restart.capture();game.end_turn();var after = snapshot()
	check(not game.undo_action() and not game.restart_battle(), "undo and restart are blocked during collision")
	game._process(0.07);game.clear_effects()
	check(game.effects.is_empty() and game.displayed_lives() == game.lives and game.player_visual.is_equal_approx(game.cell_pos(game.player)), "clear discards pending HP and player presentation without rewinding settled logic")
	check(game.enemies.all(func(e): return e.visual.is_equal_approx(game.cell_pos(e.pos))) and snapshot() == after, "clear restores each token to logical cell without second movement")
	check(game.undo_action() and snapshot() == before, "undo restores exact pre-hit logical state and RNG")
	check(game.effects.is_empty() and game.displayed_lives() == 3, "undo cannot leave stale collision or HP hold")
	game.end_turn();check(snapshot() == after, "replayed end_turn matches original damage, recoil, cooldown and RNG")
	finish();check(game.restart_battle() and snapshot() == before, "restart restores original battle snapshot after impact playback")
	check(game.effects.is_empty() and game.displayed_lives() == 3, "restart clears every impact and transient HP display")
	game._process(1.0);check(snapshot() == before, "post-restart frames cannot resume an abandoned attacker")
	game.end_turn();game._process(0.07);game.new_run()
	check(fx_of("enemy_impact").is_empty() and game.displayed_lives() == game.lives, "new run clears in-flight collision and pending life display")
