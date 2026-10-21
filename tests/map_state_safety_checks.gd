extends SceneTree
# Non-visual event/state regression. Run with a disposable XDG_DATA_HOME so that
# intentionally incomplete save fixtures cannot replace a player's real run.
var game
var route
var checks = 0
var failures = 0

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error("MAP SAFETY: " + label)

func _initialize(): call_deferred("run")

func create_game():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	route = game.route

func fresh(size: Vector2 = Vector2(390, 844), identity: String = "king"):
	game.configure_layout(size)
	game.player_skill = identity
	game.new_expedition()
	route.tick(0)

func touch(pos: Vector2, pressed: bool, index: int = 0, canceled: bool = false):
	var event = InputEventScreenTouch.new()
	event.position = pos;event.index = index
	event.pressed = pressed;event.canceled = canceled
	game._input(event)

func drag(pos: Vector2, index: int = 0):
	var event = InputEventScreenDrag.new()
	event.position = pos;event.index = index
	game._input(event)

func mouse(pos: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT, device: int = 0):
	var event = InputEventMouseButton.new()
	event.position = pos;event.button_index = button
	event.pressed = pressed;event.device = device
	game._gui_input(event)

func key(code: int, pressed: bool = true, echo: bool = false):
	var event = InputEventKey.new()
	event.keycode = code;event.pressed = pressed;event.echo = echo
	game._input(event)

func tap(pos: Vector2, index: int = 0):
	touch(pos, true, index);touch(pos, false, index)

func saved_config() -> ConfigFile:
	var config = ConfigFile.new()
	check(config.load(route.SAVE) == OK, "native ConfigFile exists and parses")
	return config

func check_pointer_events(size: Vector2):
	fresh(size)
	var initial = route.state.duplicate(true)
	var p = route.position(route.state.nodes[0])
	touch(p, true)
	check(route.selected_node == -1 and route.state == initial, "press alone never selects or commits")
	drag(p + Vector2(35, 0));drag(p)
	touch(p, false)
	check(route.selected_node == -1 and route.state == initial, "drag out and back never becomes a tap")
	touch(p, true);touch(p + Vector2(12, 0), false)
	check(route.selected_node == -1, "release at drag threshold is not a tap without a motion event")
	touch(p, true);touch(p, false, 0, true)
	check(route.selected_node == -1 and route.pointer_id == -2, "canceled primary touch releases capture without selecting")
	touch(p, true, 4)
	var scroll = route.scroll_y
	touch(p, true, 7);drag(p + Vector2(0, 140), 7);touch(p, false, 7, true)
	check(route.pointer_id == 4 and is_equal_approx(route.scroll_y, scroll), "secondary touch cannot move or cancel primary capture")
	touch(p, false, 4)
	check(route.selected_node == 0 and route.state == initial, "primary touch still previews exactly once after secondary cancellation")
	var confirm_pos = route.confirm_rect().get_center()
	mouse(confirm_pos, true, MOUSE_BUTTON_LEFT, -1);mouse(confirm_pos, false, MOUSE_BUTTON_LEFT, -1)
	check(route.travel_target == -1, "emulated mouse after real touch cannot confirm a preview")
	touch(confirm_pos, true);touch(confirm_pos, false, 0, true)
	check(route.travel_target == -1 and route.selected_node == 0, "canceled confirm preserves preview without traveling")
	key(KEY_ENTER, true, true);key(KEY_ENTER, false)
	check(route.travel_target == -1 and route.state == initial, "Enter repeat and key release cannot start travel")
	key(KEY_ESCAPE)
	check(route.selected_node == -1 and route.state == initial, "Escape dismisses a preview without progress")
	mouse(p, true);mouse(p, false)
	check(route.selected_node == 0, "physical mouse still works after touch input")
	tap(route.cancel_rect().get_center())
	check(route.selected_node == -1 and route.state == initial, "cancel footer leaves persistent route unchanged")
	# Cancellation must invalidate the pending release, not just the preview.
	touch(p, true);key(KEY_ESCAPE);touch(p, false)
	check(route.selected_node == -1 and route.pointer_id == -2, "Escape during a press prevents release from reopening preview")
	route.reset_view();route.tick(0);p = route.position(route.state.nodes[0])
	for notification in [Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT, Control.NOTIFICATION_WM_MOUSE_EXIT]:
		touch(p, true, 3)
		game._notification(notification)
		check(route.pointer_id == -2, "window focus/exit cancels map pointer capture")
		touch(p, false, 3)
		check(route.selected_node == -1, "release after focus/exit cannot select a node")
		route.reset_view();route.tick(0)
		tap(p, 5)
		check(route.selected_node == 0, "fresh input works after lost-focus cancellation")
		route.reset_view();route.tick(0)
	# A resized canvas must not reinterpret a press in the previous coordinates.
	touch(p, true)
	game.configure_layout(Vector2(844, 390) if not game.compact_landscape else Vector2(390, 844))
	route.tick(0);touch(p, false)
	check(route.pointer_id == -2 and route.selected_node == -1, "layout change invalidates old pointer capture")

func check_scroll_and_overlays():
	fresh()
	var center = route.map_rect().get_center()
	route.scroll_y = route.scroll_limit() * 0.5
	touch(center, true);drag(center + Vector2(0, 10000));touch(center, false)
	check(is_zero_approx(route.scroll_y), "drag clamps at top of map")
	touch(center, true);drag(center - Vector2(0, 10000));touch(center, false)
	check(is_equal_approx(route.scroll_y, route.scroll_limit()), "drag clamps at bottom of map")
	var scroll = route.scroll_y
	mouse(route.home_rect().get_center(), true, MOUSE_BUTTON_WHEEL_UP)
	check(is_equal_approx(route.scroll_y, scroll), "wheel outside map never scrolls map")
	mouse(center, true, MOUSE_BUTTON_WHEEL_UP)
	check(route.scroll_y < scroll, "physical wheel inside map scrolls")
	route.focus_current()
	tap(route.footer_rect(0).get_center())
	check(route.deck_view, "deck footer opens deck overlay")
	var p = route.position(route.state.nodes[0])
	scroll = route.scroll_y
	tap(p);mouse(center, true, MOUSE_BUTTON_WHEEL_UP)
	check(route.selected_node == -1 and is_equal_approx(route.scroll_y, scroll), "deck overlay blocks hidden node selection and map scroll")
	key(KEY_ESCAPE)
	check(not route.deck_view, "Escape closes deck overlay")

func check_travel_and_reload():
	fresh()
	var before = route.state.duplicate(true)
	tap(route.position(route.state.nodes[0]));key(KEY_KP_ENTER)
	check(route.travel_target == 0 and route.pointer_id == -2 and route.state == before, "keypad Enter begins transient travel, not arrival")
	var scroll = route.scroll_y
	tap(route.home_rect().get_center());key(KEY_ESCAPE);key(KEY_ENTER)
	mouse(route.map_rect().get_center(), true, MOUSE_BUTTON_WHEEL_UP)
	check(game.screen == "map" and route.travel_target == 0 and is_equal_approx(route.scroll_y, scroll), "travel rejects home, cancel, repeated confirmation, and scroll")
	route.tick(route.TRAVEL_SECONDS * 0.5)
	route.save()
	check(route.save_error == OK, "in-flight snapshot is persisted")
	var snapshot = saved_config()
	check(snapshot.get_value("run", "screen") == "map" and snapshot.get_value("run", "route") == before, "in-flight save stores no uncommitted destination")
	# A fresh scene proves this is a disk round trip, not reuse of route objects.
	game.free();create_game()
	check(route.resume(), "fresh scene resumes saved in-flight run")
	route.tick(0)
	check(game.screen == "map" and route.state == before and route.travel_target == -1 and route.selected_node == -1, "relaunch discards transient march and preview")
	check(route.pointer_id == -2 and route.map_rect().has_point(route.position(route.state.nodes[0])), "relaunch clears pointer and focuses current route")
	tap(route.position(route.state.nodes[0]));key(KEY_ENTER)
	route.tick(route.TRAVEL_SECONDS - 0.01)
	check(game.screen == "map" and route.state.pending == -1, "arrival does not commit before animation threshold")
	route.tick(0.02)
	check(game.screen == "game" and route.state.pending == 0 and route.state.current == -1, "arrival atomically enters pending battle")
	var battle = game.history.capture()
	route.tick(100)
	check(game.history.capture() == battle, "large later tick cannot start same battle twice")
	check(route.resume() and game.screen == "game" and game.history.capture() == battle, "arrival save restores exact battle and RNG")

func defeat_general():
	game.player = Vector2i(4, 9);game.enemies = []
	game.add_enemy("g", Vector2i(4, 8), 3);game.enemies[0].hp = 1
	game.hand = ["sword"];game.hand_ids = []
	game.energy = 3;game.input_lock = 0;game.navigation_lock = 0
	game.play_card(0, Vector2i(4, 8))

func check_battle_phase_round_trips():
	for identity in ["king", "horse", "artillery"]:
		fresh(Vector2(390, 844), identity);route.enter(0)
		game.basic_move(Vector2i(3, 7) if identity == "horse" else Vector2i(4, 8))
		game.draw_card();game.draw_card()
		if identity == "artillery":
			# Stakes intentionally lack hp/max_hp; they are valid persisted pieces.
			game.TACTICS.apply(game, "stake", Vector2i(3, 8), -1)
		var expected = game.history.capture()
		route.save();game.show_home()
		check(route.resume() and game.history.capture() == expected, "active battle restores full hand/deck, piece, skill, and RNG state")
		check(game.player_skill == identity and route.state.pending == 0, "battle profile and pending route survive return from home")
		while game.hand.size() < 7: game.draw_card()
		check(game.phase == "discard", "overfull-hand fixture enters discard phase")
		expected = game.history.capture();route.save()
		check(route.resume() and game.history.capture() == expected, "discard phase resumes without losing or duplicating cards")
		game.discard_hand(0)
		game.player = Vector2i(4, 9);game.lives = 1;game.enemies = []
		game.add_enemy("g", Vector2i(4, 0), 3);game.add_enemy("r", Vector2i(4, 8), 3)
		game.input_lock = 0;game.navigation_lock = 0;game.end_turn()
		check(game.phase == "dead", "lethal enemy attack enters dead phase")
		expected = game.history.capture();route.save();game.show_home()
		check(route.resume() and game.screen == "game" and game.phase == "dead" and game.history.capture() == expected, "defeated but unfinished chapter remains resumable")

func check_reward_return():
	for identity in ["king", "horse", "artillery"]:
		for use_debug in [false, true]:
			for reward_action in ["add", "remove", "skip"]:
				fresh(Vector2(390, 844), identity)
				route.enter(0)
				if use_debug: game.debug_skip()
				else: defeat_general()
				var expected_loot = route.state.nodes[0].loot.duplicate()
				check(game.phase == "reward" and game.rewards == expected_loot, "normal/debug victory uses deterministic node loot")
				check(not game.history.can_undo(), "victory cannot undo across route reward boundary")
				check(route.resume() and game.phase == "reward" and game.rewards == expected_loot, "unresolved reward persists without reroll")
				var cards = game.collection.duplicate()
				if reward_action == "add":
					game.choose_reward(0);cards.append(expected_loot[0])
				elif reward_action == "remove":
					game.delete_reward(0);cards.remove_at(0)
				else: game.choose_reward(-1)
				route.tick(0)
				check(game.screen == "map" and route.state.current == 0 and route.state.pending == -1 and route.state.visited == [0], "each reward mode returns to completed node exactly once")
				check(game.collection == cards and game.hand.is_empty() and game.enemies.is_empty(), "reward deck result persists and combat residue is cleared")
				check(route.map_rect().has_point(route.position(route.state.nodes[0])), "normal/debug return focuses completed node")
				game.choose_reward(0);game.delete_reward(0);route.complete()
				check(game.collection == cards and route.state.visited == [0], "duplicate reward or completion cannot duplicate progress")
				check(route.resume() and game.screen == "map" and game.collection == cards and route.state.visited == [0], "completed reward survives disk round trip")
				check(route.legal() == route.state.nodes[0].next, "next legal branches are preserved after reward reload")

func check_choice_resume():
	fresh();route.enter(0);game.debug_skip();game.choose_reward(-1)
	route.enter(1)
	var original_choices = route.choices.duplicate(true)
	var cards = game.collection.duplicate()
	check(game.screen == "route_choice" and route.resume() and route.choices == original_choices, "choice screen and deterministic options survive resume")
	var choice_pos = route.row_rect(1).get_center()
	touch(choice_pos, true);drag(choice_pos + Vector2(20, 0));drag(choice_pos);touch(choice_pos, false)
	check(game.screen == "route_choice" and game.collection == cards, "drag across choice cannot activate it")
	touch(choice_pos, true);touch(choice_pos, false, 0, true)
	check(game.screen == "route_choice" and route.state.pending == 1, "canceled choice touch cannot resolve node")
	tap(choice_pos);cards.append("spear")
	check(game.screen == "map" and route.state.current == 1 and game.collection == cards, "choice resolves on release exactly once")
	touch(choice_pos, false)
	check(game.collection == cards and route.state.visited == [0, 1], "late duplicate choice release cannot grant another card")
	check(route.resume() and route.state.current == 1 and game.collection == cards, "resolved event persists without replay")

func check_invalid_save_rejection():
	fresh()
	var good = saved_config()
	var encoded = good.encode_to_text()
	var before_route = route.state.duplicate(true)
	var before_battle = game.history.capture()
	var invalid = []
	var wrong_version = ConfigFile.new();wrong_version.parse(encoded);wrong_version.set_value("run", "version", 99)
	invalid.append({"label": "unknown version", "config": wrong_version})
	var missing_route = ConfigFile.new();missing_route.parse(encoded);missing_route.erase_section_key("run", "route")
	invalid.append({"label": "missing route", "config": missing_route})
	var finished = ConfigFile.new();finished.parse(encoded)
	var done_route = before_route.duplicate(true);done_route.done = true;finished.set_value("run", "route", done_route)
	invalid.append({"label": "finished chapter", "config": finished})
	var missing_battle = ConfigFile.new();missing_battle.parse(encoded);missing_battle.erase_section_key("run", "battle")
	invalid.append({"label": "missing battle snapshot", "config": missing_battle})
	var missing_rng = ConfigFile.new();missing_rng.parse(encoded)
	var incomplete_battle = before_battle.duplicate(true);incomplete_battle.erase("rng_state");missing_rng.set_value("run", "battle", incomplete_battle)
	invalid.append({"label": "missing RNG state", "config": missing_rng})
	var invalid_screen = ConfigFile.new();invalid_screen.parse(encoded);invalid_screen.set_value("run", "screen", "unexpected_screen")
	invalid.append({"label": "unknown saved screen", "config": invalid_screen})
	var invalid_route_type = ConfigFile.new();invalid_route_type.parse(encoded);invalid_route_type.set_value("run", "route", ["not a route"])
	invalid.append({"label": "wrong route container", "config": invalid_route_type})
	var invalid_battle_type = ConfigFile.new();invalid_battle_type.parse(encoded);invalid_battle_type.set_value("run", "battle", ["not a snapshot"])
	invalid.append({"label": "wrong battle container", "config": invalid_battle_type})
	var missing_field = ConfigFile.new();missing_field.parse(encoded)
	var fieldless_battle = before_battle.duplicate(true);fieldless_battle.erase("collection");missing_field.set_value("run", "battle", fieldless_battle)
	invalid.append({"label": "missing required battle field", "config": missing_field})
	var invalid_current = ConfigFile.new();invalid_current.parse(encoded)
	var current_route = before_route.duplicate(true);current_route.current = 999;invalid_current.set_value("run", "route", current_route)
	invalid.append({"label": "out-of-range current node", "config": invalid_current})
	var invalid_pending = ConfigFile.new();invalid_pending.parse(encoded)
	var pending_route = before_route.duplicate(true);pending_route.pending = 999;invalid_pending.set_value("run", "route", pending_route)
	invalid.append({"label": "out-of-range pending node", "config": invalid_pending})
	var invalid_map_pending = ConfigFile.new();invalid_map_pending.parse(encoded)
	var map_pending_route = before_route.duplicate(true);map_pending_route.pending = 0;invalid_map_pending.set_value("run", "route", map_pending_route)
	invalid.append({"label": "map screen with an unresolved pending node", "config": invalid_map_pending})
	var invalid_battle_pending = ConfigFile.new();invalid_battle_pending.parse(encoded);invalid_battle_pending.set_value("run", "screen", "game")
	invalid.append({"label": "battle screen without a pending node", "config": invalid_battle_pending})
	var invalid_choice_pending = ConfigFile.new();invalid_choice_pending.parse(encoded);invalid_choice_pending.set_value("run", "screen", "route_choice")
	invalid.append({"label": "choice screen without a pending node", "config": invalid_choice_pending})
	var invalid_edge = ConfigFile.new();invalid_edge.parse(encoded)
	var edge_route = before_route.duplicate(true);edge_route.nodes[0].next.append(999);invalid_edge.set_value("run", "route", edge_route)
	invalid.append({"label": "out-of-range outgoing edge", "config": invalid_edge})
	for fixture in invalid:
		fixture.config.save(route.SAVE)
		var accepted = route.resume()
		check(accepted == false, "reject " + fixture.label)
		check(game.screen == "map" and route.state == before_route and game.history.capture() == before_battle, "reject " + fixture.label + " without changing live run")
		good.save(route.SAVE)
		check(route.resume(), "valid save remains resumable after rejected fixture")

func run():
	create_game()
	for size in [Vector2(1280, 940), Vector2(390, 844), Vector2(844, 390), Vector2(360, 640)]:
		check_pointer_events(size)
	check_scroll_and_overlays()
	check_travel_and_reload()
	check_battle_phase_round_trips()
	check_reward_return()
	check_choice_resume()
	check_invalid_save_rejection()
	print("MAP STATE SAFETY RESULT ", checks, " checks, ", failures, " failures")
	game.free()
	quit(1 if failures else 0)
