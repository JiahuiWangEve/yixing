extends SceneTree
# Real key-event regressions for the desktop Space end-turn shortcut.
# Run with disposable user:// storage, as supplied by scripts/verify.sh.
var game
var checks = 0
var failures = 0

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("SPACE SHORTCUT: " + label)
	else:
		print("PASS ", label)

func _initialize(): call_deferred("run")

func key(code: int, pressed: bool = true, echo: bool = false):
	var event = InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	game._input(event)

func fresh():
	game.player_skill = "king"
	game.new_run()
	game.enemies = []
	game.add_enemy("g", Vector2i(4, 0), 99)
	game.enemies[0].hp = 99
	game.player = Vector2i(4, 5)
	game.lives = 3
	game.deck = [];game.discard = [];game.hand = [];game.hand_ids = []
	game.phase = "play";game.energy = 1
	game.selected = -1;game.free_selected = false
	game.clear_effects();game.navigation_lock = 0.0
	game.history.clear()

func unchanged_state() -> Dictionary:
	return {
		"battle": game.history.capture(),
		"history": game.history.entries.duplicate(true),
		"screen": game.screen,
		"selected": game.selected,
		"input_lock": game.input_lock,
		"navigation_lock": game.navigation_lock
	}

func check_combat_keys():
	fresh()
	var before = unchanged_state()
	key(KEY_ENTER);key(KEY_KP_ENTER)
	check(unchanged_state() == before, "Enter and keypad Enter no longer end a combat turn")
	key(KEY_SPACE, false);key(KEY_SPACE, true, true)
	check(unchanged_state() == before, "Space release and auto-repeat are inert before the first press")
	var turn = game.turn
	key(KEY_SPACE)
	check(game.turn == turn + 1 and game.energy == 3 and game.phase == "play", "one Space press ends exactly one active play turn")
	check(game.history.entries.size() == 1 and game.history.entries[0].action == "end_turn", "Space records one undoable end-turn action")
	check(game.enemies[0].cd == 98, "Space runs the enemy phase exactly once")
	before = unchanged_state()
	for repeat in 5:
		key(KEY_SPACE)
		key(KEY_SPACE, true, true)
	key(KEY_SPACE, false)
	check(unchanged_state() == before, "animation lock rejects rapid extra presses as well as held-key repeats")
	game.clear_effects();game.navigation_lock = 0.0
	before = unchanged_state()
	for repeat in 5: key(KEY_SPACE, true, true)
	key(KEY_SPACE, false)
	check(unchanged_state() == before, "held Space cannot end another turn after animation lock expires")
	key(KEY_SPACE)
	check(game.turn == turn + 2 and game.history.entries.size() == 2, "a fresh Space press after release can end the next turn once")

func check_context_guards():
	for screen in ["home", "skill_selection", "debug_menu", "tutorial_menu", "tutorial_pause", "tutorial_complete", "route_choice"]:
		fresh();game.screen = screen
		var before = unchanged_state()
		key(KEY_SPACE)
		check(unchanged_state() == before, "Space is inert on " + screen)
	for phase in ["reward", "discard", "dead", "win"]:
		fresh();game.phase = phase
		game.hand = ["life"];game.sync_hand_ids();game.selected = 0
		var before = unchanged_state()
		key(KEY_SPACE)
		check(unchanged_state() == before, "Space neither ends a turn nor confirms a card in " + phase)
	for lock in ["input_lock", "navigation_lock"]:
		fresh();game.set(lock, 0.25)
		var before = unchanged_state()
		key(KEY_SPACE)
		check(unchanged_state() == before, "Space respects " + lock)
	# A live lesson may reject end-turn even while the battle screen is open.
	game.start_tutorial(0)
	game.clear_effects();game.navigation_lock = 0.0
	var turn = game.turn
	var hand = game.hand.duplicate()
	var player = game.player
	var step = game.tutorial.step_index
	key(KEY_SPACE)
	check(game.turn == turn and game.hand == hand and game.player == player and game.tutorial.step_index == step and game.tutorial._pending_step == -1, "Space cannot bypass a tutorial's current non-end-turn objective")
	game.tutorial.lesson_complete = true
	key(KEY_SPACE)
	check(game.turn == turn and game.tutorial.step_index == step, "Space cannot bypass a completed tutorial's transition gate")

func check_selected_cards():
	# The shared on-screen confirm/end-turn rectangle must not turn Space into
	# a card-confirm shortcut, including consumable and draw cards.
	for card in game.UNTARGETED:
		fresh()
		game.hand = [card];game.sync_hand_ids();game.selected = 0
		var turn = game.turn
		var lives = game.lives
		key(KEY_SPACE)
		check(game.turn == turn + 1 and game.hand == [card] and game.discard.is_empty() and game.lives == lives and game.selected == -1, "Space ends turn without playing selected " + card)
		check(game.history.entries.size() == 1 and game.history.entries[0].action == "end_turn", card + " selection produces no extra play action")

func check_map_confirmation():
	for confirm_key in [KEY_ENTER, KEY_KP_ENTER]:
		fresh();game.new_expedition();game.clear_effects();game.navigation_lock = 0.0
		var route = game.route
		route.tick(0)
		var state = route.state.duplicate(true)
		var turn = game.turn
		key(KEY_SPACE)
		check(game.screen == "map" and route.selected_node == -1 and route.travel_target == -1 and route.state == state and game.turn == turn, "Space on an unselected map neither ends a turn nor starts travel")
		route.selected_node = 0
		key(KEY_SPACE);key(KEY_SPACE, true, true);key(KEY_SPACE, false)
		check(game.screen == "map" and route.selected_node == 0 and route.travel_target == -1 and route.state == state and game.turn == turn, "Space does not confirm a valid map selection")
		key(confirm_key, false);key(confirm_key, true, true)
		check(route.travel_target == -1 and route.state == state, "map Enter release and auto-repeat remain inert")
		key(confirm_key)
		check(route.travel_target == 0 and route.state.pending == -1 and game.screen == "map", "map " + str(confirm_key) + " still confirms valid selection into transient travel")
		key(KEY_SPACE);key(confirm_key);key(confirm_key, true, true)
		check(route.travel_target == 0 and route.state == state and game.turn == turn, "keys during map travel cannot duplicate confirmation or end a turn")
		route.tick(route.TRAVEL_SECONDS + 0.01)
		check(game.screen == "game" and route.state.pending == 0 and game.turn == 1, "confirmed map travel enters battle once without ending its first turn")

func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	check_combat_keys()
	check_context_guards()
	check_selected_cards()
	check_map_confirmation()
	print("SPACE SHORTCUT RESULT ", checks, " checks, ", failures, " failures")
	game.free()
	quit(1 if failures else 0)
