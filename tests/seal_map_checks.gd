extends SceneTree
const T = preload("res://../tests/route_test_helpers.gd")
# Visual state and geometry regression for the black-ink / red-seal campaign map.
# Run with the disposable save directory supplied by scripts/verify.sh.
var game
var checks = 0
var failures = 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
func _initialize(): call_deferred("run")
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.settings.set_debug_mode(true)
	var route = game.route
	for size in [Vector2(1280,940), Vector2(390,844), Vector2(844,390), Vector2(360,640)]:
		game.configure_layout(size);game.new_expedition();route.tick(0)
		check(route.stamp_node == -1, "fresh campaign has no completion animation")
		check(route.state.visited.is_empty(), "fresh campaign has no completed seals")
		var map = route.map_rect()
		for node in route.state.nodes:
			var hit = route.hit_rect(node)
			check(hit.size.x >= 44 and hit.size.y >= 44, "node touch target remains usable")
			check(hit.position.x >= map.position.x and hit.end.x <= map.end.x, "node and label fit horizontal map bounds")
			for other in route.state.nodes:
				if other.id > node.id: check(not hit.intersects(route.hit_rect(other)), "distinct node hitboxes never overlap")
		var decorations = route.decoration_layout().duplicate(true)
		check(decorations == route.decoration_layout(), "decoration placement deterministic for unchanged map")
		for decoration in decorations:
			check(decoration is Dictionary and decoration.has("rect") and decoration.has("kind"), "decoration shape valid")
			check(route.decoration_clear(decoration.rect), "scenery avoids labels, icons, stamps, and route corridors")
		var old_scroll = route.scroll_y
		route.scroll_y = 0
		check(decorations == route.decoration_layout(), "scrolling cannot rearrange scenery")
		route.scroll_y = old_scroll
		var blocked = route.hit_rect(route.state.nodes[0])
		blocked.position.y += route.scroll_y
		check(not route.decoration_clear(blocked), "scenery cannot occupy a node")
		var a = route.content_point(route.state.nodes[0])
		var b = route.content_point(route.state.nodes[route.state.nodes[0].next[0]])
		var middle = route.edge_point(a, b, 0.5)
		check(not route.decoration_clear(Rect2(middle - Vector2(8,8), Vector2(16,16))), "scenery cannot occupy a road")
		# Selection, blank-clear, and travelling must not create a completion seal.
		var start = route.position(route.state.nodes[0])
		var hover = InputEventMouseMotion.new();hover.position = start;hover.device = 0
		game._gui_input(hover)
		check(route.selected_node == 0 and route.stamp_node == -1 and route.travel_target == -1, "hover frame is not departure or completion")
		route.click(route.map_rect().position + Vector2(4, 4))
		check(route.selected_node == -1 and route.state.visited.is_empty(), "blank-clear preserves uncompleted map")
		route.click(start);route.tick(0.4)
		check(route.stamp_node == -1 and route.state.visited.is_empty(), "marching is not completion")
		route.tick(0.5)
		check(game.screen == "game" and route.state.pending == 0, "arrival still enters battle")
		game.debug_skip();game.choose_reward(-1);route.tick(0)
		check(game.screen == "map" and route.state.current == 0, "battle reward returns to completed map node")
		check(route.stamp_node == 0 and is_zero_approx(route.stamp_elapsed), "completion starts one stamp at zero")
		check(route.state.visited == [0], "completed seal comes from persisted visited state")
		route.tick(0.2)
		check(route.stamp_node == 0 and route.stamp_elapsed >= 0.19, "stamp advances without a march")
		route.tick(route.STAMP_SECONDS + 0.1)
		check(route.stamp_node == -1 or route.stamp_elapsed >= route.STAMP_SECONDS, "stamp finishes after its finite duration")
		check(route.state.visited == [0], "stamp finishing never changes gameplay progress")
		# Saving and resuming preserves the static seal, not its entrance animation.
		route.save();check(route.resume(), "completed map resumes")
		check(route.stamp_node == -1, "resume does not replay completion animation")
		check(route.state.visited == [0] and route.state.current == 0, "resume preserves static completed seal")
		route.tick(0)
		# An event can be completed too, including the no-upgrade 'leave' choice.
		var event_id = T.next_node(game, "event")
		var next = route.position(route.state.nodes[event_id]);route.click(next);route.tick(0.86)
		check(game.screen == "route_choice" and route.state.pending == event_id, "event arrival remains a choice, not automatic completion")
		check(route.stamp_node == -1 and route.state.visited == [0], "event preview has no premature seal")
		route.resolve(route.choices.size() - 1)
		check(route.stamp_node == event_id and route.state.visited == [0,event_id], "resolved event receives its own completion seal")
		route.reset_view()
		check(route.stamp_node == -1 and route.state.visited == [0,event_id], "reset view clears animation only")
		game.new_expedition();route.tick(0)
		check(route.stamp_node == -1 and route.state.visited.is_empty(), "new run never leaks previous seals")
	print("SEAL MAP RESULT ", checks, " checks, ", failures, " failures")
	game.free();quit(1 if failures else 0)
