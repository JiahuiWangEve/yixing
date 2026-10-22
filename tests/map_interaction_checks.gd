extends SceneTree
const T = preload("res://../tests/route_test_helpers.gd")
var game
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
func _initialize(): call_deferred("run")
func check_generated_geometry():
	var route = game.route
	for seed_number in range(-8, 16):
		game.seed_value = seed_number;game.new_expedition()
		var generated = route.state.duplicate(true)
		for size in [Vector2(1280,940), Vector2(390,844), Vector2(844,390), Vector2(360,640)]:
			game.configure_layout(size);route.tick(0)
			check(route.state == generated, "resizing never mutates seeded topology, coordinates, rewards or encounter payloads")
			var map = route.map_rect()
			for node in route.state.nodes:
				var hit = route.hit_rect(node)
				check(hit.size.x >= 44 and hit.size.y >= 44, "every seeded node retains accessible touch target")
				check(hit.position.x >= map.position.x and hit.end.x <= map.end.x, "every seeded landmark fits horizontally")
				for other in route.state.nodes:
					if other.id > node.id: check(not hit.intersects(route.hit_rect(other)), "seeded node hitboxes do not overlap in any viewport")
			route.scroll_y = 0
			var boss = route.state.nodes[T.kind_id(route, "boss")]
			check(map.encloses(route.hit_rect(boss)), "full terminal boss hitbox is visible at the summit")
			route.focus_current()
			check(map.encloses(route.hit_rect(route.state.nodes[0])), "full entrance hitbox is visible at initial focus")
			route.selected_node = 0
			var before = route.state.duplicate(true)
			game.configure_layout(Vector2(390,844) if size.x > 800 else Vector2(844,390));route.tick(0)
			check(route.selected_node == 0 and route.state == before, "rotation preserves selected node and exact generated graph")

func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.settings.set_debug_mode(true)
	game.set_process(false)
	var route = game.route
	for size in [Vector2(1280,940), Vector2(390,844), Vector2(844,390), Vector2(360,640)]:
		game.configure_layout(size);game.new_expedition();route.tick(0)
		var map = route.map_rect()
		check(is_equal_approx(map.size.x, minf(game.ui_size.x - 28, 1000)), "map uses full available centered width up to 1000")
		check(is_equal_approx(map.get_center().x, game.ui_size.x * 0.5), "map is horizontally centered with equal margins")
		check(is_equal_approx(map.position.y, 90 if game.compact_landscape else 112), "map starts below compact header")
		check(is_equal_approx(map.end.y, game.ui_size.y - 14), "map reaches bottom margin without redundant footer")
		check(not route.has_method("info_rect") and not route.has_method("confirm_rect") and not route.has_method("cancel_rect") and not route.has_method("center_rect"), "obsolete sidebar and travel control hit areas are removed")
		check(route.map_rect().has_point(route.position(route.state.nodes[0])), "initial node visible")
		var start = route.position(route.state.nodes[0])
		route.pointer_press(start, 0);route.pointer_motion(start - Vector2(0, 70), 0);route.pointer_release(start, 0)
		check(route.selected_node == -1 and game.screen == "map", "drag returning to origin is not a tap")
		route.focus_current();start = route.position(route.state.nodes[0])
		route.pointer_press(start, 0);route.pointer_release(start, 0, true)
		check(route.selected_node == -1, "canceled touch not selected")
		route.pointer_press(start, 0);route.pointer_press(start, 1);route.pointer_release(start, 1)
		check(route.selected_node == -1, "second pointer ignored")
		route.pointer_release(start, 0)
		check(route.selected_node == 0 and route.state.pending == -1 and game.screen == "map", "tap previews only")
		var before_scroll = route.scroll_y
		var before_deck = game.collection.duplicate()
		check(not route.deck_rect().intersects(map) and not route.deck_rect().intersects(route.home_rect()) and route.deck_rect().end.x <= game.ui_size.x - 14, "deck entry remains independent in upper-right header")
		route.click(route.deck_rect().get_center())
		check(game.card_picker.active and game.card_picker.action == "view" and game.card_picker.indices.size() == game.collection.size(), "selected node opens complete readonly deck")
		game.card_picker.selected = 0;game.card_picker.confirm()
		check(game.card_picker.active and game.collection == before_deck, "view never mutates collection")
		game.card_picker.cancel()
		check(route.selected_node == 0 and route.scroll_y == before_scroll, "closing deck preserves selection and scroll")
		route.tick(30)
		check(route.selected_node == 0 and route.travel_target == -1, "selection has no double-click timeout or automatic departure")
		route.click(start)
		check(route.travel_target == 0 and route.state.pending == -1, "same-node second click after deck return and long delay starts transient travel")
		route.click(route.deck_rect().get_center());check(not game.card_picker.active, "march disables deck input")
		route.click(route.home_rect().get_center());route.click(start);route.pointer_press(start, 0)
		check(route.travel_target == 0 and route.pointer_id == -2 and game.screen == "map", "animation rejects home duplicate and pointer")
		route.tick(0.4);route.save();check(route.resume(), "mid-march reload supported")
		check(game.screen == "map" and route.state.pending == -1 and route.travel_target == -1, "reload cancels uncommitted march")
		route.tick(0);start = route.position(route.state.nodes[0])
		route.click(route.deck_rect().get_center());check(game.card_picker.active, "unselected map opens deck")
		game.card_picker.cancel()
		route.click(start);route.click(map.position + Vector2(4, 4))
		check(route.selected_node == -1 and route.state.pending == -1 and route.travel_target == -1, "blank map clears selection without progress")
		route.click(start);check(route.selected_node == 0 and route.travel_target == -1, "first click after blank-clear only selects again")
		route.click(start);route.tick(0.86)
		check(game.screen == "game" and route.state.pending == 0, "arrival enters once")
		route.tick(2);check(route.state.pending == 0, "extra frames do not enter twice")
		game.debug_skip();game.choose_reward(-1);route.tick(0)
		check(route.state.current == 0 and route.map_rect().has_point(route.position(route.state.nodes[0])), "reward returns to current node")
		var alternatives = route.legal()
		check(alternatives.size() >= 2, "opening fork has alternative reachable nodes")
		var next_a = route.position(route.state.nodes[alternatives[0]]);var next_b = route.position(route.state.nodes[alternatives[1]])
		route.click(next_a);route.click(next_b)
		check(route.selected_node == alternatives[1] and route.travel_target == -1, "clicking a different reachable node changes selection without departing")
		route.scroll_y = 0
		var boss = T.kind_id(route, "boss")
		var unreachable = route.position(route.state.nodes[boss])
		route.click(unreachable);route.click(unreachable)
		check(route.selected_node == boss and route.travel_target == -1 and route.state.pending == -1, "repeated unreachable-node clicks never travel")
		route.focus_current();route.click(map.position + Vector2(4, 4))
		for target in route.legal():
			var target_pos = route.position(route.state.nodes[target]);route.click(target_pos);route.click(target_pos)
			check(route.march_point(0).is_equal_approx(route.position(route.state.nodes[0])), "march starts at current node")
			check(route.march_point(1).is_equal_approx(route.position(route.state.nodes[target])), "march ends at target")
			check(route.march_point(0.5).is_equal_approx(route.edge_point(route.position(route.state.nodes[0]), route.position(route.state.nodes[target]), 0.5)), "piece follows rendered edge")
			route.travel_target = -1
		for node in route.state.nodes:
			for next in node.next: check(route.state.nodes[next].row == node.row + 1, "original forward topology")
	# A normal victory must use the same return/focus path as a debug skip.
	game.new_expedition();route.enter(0)
	game.player = Vector2i(4, 9);game.enemies = [];game.add_enemy("g", Vector2i(4, 8), 3);game.enemies[0].hp = 1
	game.hand = ["sword"];game.hand_ids = [];game.input_lock = 0;game.energy = 3
	game.play_card(0, Vector2i(4, 8))
	check(game.phase == "reward", "normal combat enters reward")
	game.input_lock = 0;game.navigation_lock = 0;game.choose_reward(-1);route.tick(0)
	check(game.screen == "map" and route.state.current == 0 and route.state.pending == -1, "normal combat reward returns to map")
	check(route.map_rect().has_point(route.position(route.state.nodes[0])), "normal return focuses current position")
	# Exercise actual event dispatch, including emulated mouse suppression.
	game.configure_layout(Vector2(390,844));game.new_expedition();route.tick(0)
	var p = route.position(route.state.nodes[0])
	var event = InputEventScreenTouch.new();event.index = 0;event.position = p;event.pressed = true
	game._input(event);event.pressed = false;game._input(event)
	check(route.selected_node == 0 and route.state.pending == -1, "real touch dispatch previews")
	var mouse = InputEventMouseButton.new();mouse.device = -1;mouse.button_index = MOUSE_BUTTON_LEFT;mouse.position = p;mouse.pressed = true
	game._gui_input(mouse);mouse.pressed = false;game._gui_input(mouse)
	check(route.travel_target == -1, "synthetic mouse cannot turn first touch selection into departure")
	check_generated_geometry()
	print("MAP INTERACTION RESULT ", checks, " checks, ", failures, " failures")
	game.free();quit(1 if failures else 0)
