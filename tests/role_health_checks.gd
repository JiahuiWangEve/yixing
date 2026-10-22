extends SceneTree
# Run with disposable XDG paths. Exercise real new-run, save/resume and undo APIs.
const CAPS = {"king": 5, "horse": 3, "artillery": 3}
var game
var checks = 0
var failures = 0
var settings_bytes = ""
var unlock_bytes = ""

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("ROLE HEALTH: " + label)
func settle():
	game.clear_effects();game.presentation.clear();game.input_lock = 0;game.navigation_lock = 0
func fresh(role: String):
	game.player_skill = role;game.seed_value = 153005;game.new_expedition();settle()
func personal_data_unchanged(label: String):
	check(FileAccess.get_file_as_string(game.settings.SAVE) == settings_bytes, label + " preserves settings bytes")
	check(FileAccess.get_file_as_string(game.skill_system.SAVE_PATH) == unlock_bytes, label + " preserves unlock bytes")
	check(game.settings.debug_mode and game.settings.audio_muted and game.skill_system.horse_unlocked, label + " preserves in-memory preferences and unlocks")
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	game.settings.set_debug_mode(true);game.settings.set_audio_muted(true);game.skill_system.unlock_horse()
	settings_bytes = FileAccess.get_file_as_string(game.settings.SAVE)
	unlock_bytes = FileAccess.get_file_as_string(game.skill_system.SAVE_PATH)
	check_starts_and_heals();check_legacy_saves();check_uncapped_save();check_undo();check_tutorials()
	personal_data_unchanged("all health operations")
	print("ROLE HEALTH RESULT ", checks - failures, " passed, ", failures, " failed")
	game.free();quit(1 if failures else 0)

func check_starts_and_heals():
	for role in CAPS:
		fresh(role)
		var cap: int = CAPS[role]
		check(game.lives == cap and game.life_limit() == cap, role + " formal start and cap")
		check(game.PROFILES.DATA[role].max_lives == cap, role + " profile owns maximum")
		check(not game.can_heal() and game.heal_lives(1) == 0 and game.lives == cap, role + " full health is a no-op")
		game.lives = cap - 1
		check(game.can_heal() and game.heal_lives(1) == 1 and game.lives == cap, role + " injured heals exactly one")
		game.lives = 1
		check(game.heal_lives(100) == cap - 1 and game.lives == cap, role + " large healing cannot exceed cap")
		check(game.heal_lives(0) == 0 and game.heal_lives(-1) == 0 and game.lives == cap, role + " nonpositive healing does not damage")
		game.lives = cap - 1;game.start_stage()
		check(game.lives == cap - 1, role + " next battle preserves current injury")
		game.new_run()
		check(game.lives == cap, role + " standalone formal run uses same opening health")
		personal_data_unchanged(role + " new runs")

func check_legacy_saves():
	check(game.route.SAVE == "user://route_run_v0149.cfg" and game.route.WEB_SAVE_KEY == "yixing.route_run.v0149", "health patch retains existing save namespace")
	for role in CAPS:
		for battle_screen in [false, true]:
			for health in [0, 1, 2, 3, 5, 8]:
				fresh(role)
				if battle_screen: game.route.enter(0);settle()
				game.lives = health
				if health == 0: game.phase = "dead"
				game.normal_undos_remaining = 2
				var expected: Dictionary = game.history.capture()
				expected.lives = mini(health, CAPS[role])
				var expected_route: Dictionary = game.route.state.duplicate(true)
				game.route.save()
				var config = ConfigFile.new();check(config.load(game.route.SAVE) == OK, "legacy fixture saved")
				check(config.get_value("run", "version") == 6, "health patch retains envelope version")
				# Emulate pre-treasure saves without discarding any user-owned state.
				var saved: Dictionary = config.get_value("run", "route")
				for field in ["treasure_id", "treasure_claimed", "treasure_choices"]: saved.erase(field);expected_route.erase(field)
				var battle: Dictionary = config.get_value("run", "battle");battle.erase("treasure_battle");expected.treasure_battle = {}
				config.set_value("run", "route", saved);config.set_value("run", "battle", battle);config.save(game.route.SAVE)
				# Deliberately stale opposite role catches a clamp before restoration.
				game.player_skill = "horse" if role == "king" else "king"
				game.lives = 99;game.route.state = {};game.screen = "home"
				var label = "%s legacy life %d screen %s" % [role, health, battle_screen]
				check(game.route.resume(), label + " resumes")
				check(game.history.capture() == expected, label + " changes only over-cap life, not cards/RNG/battle state")
				check(game.route.state == expected_route and game.normal_undos_remaining == 2, label + " preserves route and undo budget")
				check(game.screen == ("game" if battle_screen else "map"), label + " restores screen")
				game.route.save();check(game.route.resume() and game.history.capture() == expected, label + " normalization is stable on second load")
	personal_data_unchanged("legacy resume")

func uncapped_fixture():
	fresh("king");game.route.generate(game.seed_value, 2)
	game.route.state.treasure_id = "longevity_seal";game.route.state.treasure_claimed = true
	game.lives = 5
func check_uncapped_save():
	uncapped_fixture()
	check(game.lives == 5 and game.life_limit() == -1 and game.can_heal(), "seal removes cap without healing")
	check(game.heal_lives(3) == 3 and game.lives == 8, "seal allows life above five")
	var expected: Dictionary = game.history.capture();var owned: Dictionary = game.route.state.duplicate(true)
	game.route.save();game.route.state = {};game.player_skill = "horse";game.lives = 1
	check(game.route.resume() and game.lives == 8 and game.life_limit() == -1, "resume restores role and treasure before cap normalization")
	check(game.history.capture() == expected and game.route.state == owned, "uncapped resume preserves exact state")
	game.route.save();check(game.route.resume() and game.lives == 8, "uncapped second resume preserves eight lives")
	game.player_skill = "horse"
	check(not game.unlimited_lives() and game.life_limit() == 3, "wrong-role seal never uncaps horse")
	personal_data_unchanged("uncapped resume")

func check_undo():
	for role in CAPS:
		fresh(role);game.route.enter(0);settle()
		game.lives = 1;game.history.record("health before healing")
		check(game.heal_lives(1) == 1, role + " heal before undo")
		check(game.undo_action() and game.lives == 1, role + " undo restores exact injured life")
		game.lives = 8;game.history.record("pre-resume above-cap snapshot");game.route.save()
		check(not game.history.entries.is_empty(), role + " stale in-memory history fixture exists")
		game.player_skill = "horse" if role == "king" else "king"
		check(game.route.resume() and game.player_skill == role and game.lives == CAPS[role], role + " resume clamps legacy health after role restoration")
		check(game.history.entries.is_empty() and not game.undo_action(), role + " resume discards stale history instead of restoring over-cap snapshots")
		var normalized: Dictionary = game.history.capture()
		game.history.record("normalized post-resume state");game.lose_lives(1);settle()
		check(game.undo_action() and game.history.capture() == normalized and game.lives <= game.life_limit(), role + " post-resume undo restores exact normalized state within cap")
	uncapped_fixture();game.route.enter(0);settle();game.lives = 8;game.history.record("uncapped health")
	game.lives = 1;game.player_skill = "horse"
	check(game.undo_action() and game.player_skill == "king" and game.lives == 8 and game.unlimited_lives(), "uncapped undo preserves above-five life after role restoration")

func check_tutorials():
	for lesson in game.tutorial.LESSON_NAMES.size():
		game.start_tutorial(lesson)
		check(game.tutorial.active and game.player_skill == "king" and game.lives == 1, "tutorial lesson %d keeps dedicated one-life preset" % lesson)
		game.clamp_lives_to_limit()
		check(game.lives == 1, "normalization never fills tutorial health")
		game.lives = 8;game.clamp_lives_to_limit()
		check(game.lives == 8, "active tutorial normalization is explicitly bypassed")
		game.tutorial.restart()
		check(game.lives == 1, "tutorial restart restores dedicated preset")
	game.tutorial.stop();fresh("king")
	check(game.lives == 5, "leaving tutorial restores formal opening rules")
