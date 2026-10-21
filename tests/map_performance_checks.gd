extends SceneTree
var game
var checks = 0
var failures = 0
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1;push_error(message)
func _initialize(): call_deferred("run")
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.settings.set_debug_mode(true);game.set_process(false)
	var route = game.route
	for size in [Vector2(1280,940), Vector2(390,844), Vector2(844,390), Vector2(360,640)]:
		game.configure_layout(size);game.new_expedition();route.tick(0)
		route.ensure_road_cache()
		var builds = route.road_cache_builds
		var work = route.road_segment_tests
		var original_scroll = route.scroll_y
		for frame in 120:
			route.scroll_y = route.scroll_limit() * frame / 119.0
			route.selected_node = frame % 16
			route.ensure_road_cache()
		check(route.road_cache_builds == builds, "scroll and selection do not rebuild road geometry")
		check(route.road_segment_tests == work, "scroll and selection do zero repeated obstacle tests")
		route.scroll_y = original_scroll;route.selected_node = -1
		for visited in [[], [0], [0, 1, 4, 6, 7, 10, 12, 15]]:
			route.state.visited = visited
			route.ensure_road_cache()
			var rects: Array[Rect2] = []
			for node in route.state.nodes:
				var hit = route.hit_rect(node).grow(3);hit.position.y += route.scroll_y;rects.append(hit)
				if node.id in visited:
					var stamp = route.stamp_rect(node).grow(5);stamp.position.y += route.scroll_y;rects.append(stamp)
			for node in route.state.nodes:
				for next in node.next:
					var solid = PackedVector2Array();var dashed = PackedVector2Array()
					var from = route.content_point(node);var to = route.content_point(route.state.nodes[next])
					for step in 80:
						var p = route.edge_point(from,to,step / 80.0);var q = route.edge_point(from,to,(step+1) / 80.0)
						var hidden = false
						for rect in rects:
							if rect.has_point(p) or rect.has_point(q): hidden = true;break
						if not hidden:
							solid.append(p);solid.append(q)
							if step % 6 < 4: dashed.append(p);dashed.append(q)
					var cached = route.road_cache[Vector2i(node.id,next)]
					check(cached.solid == solid, "cached solid roads exactly match original clipping")
					check(cached.dashed == dashed, "cached dashed roads exactly match original clipping")
		game.new_expedition();route.tick(0);route.ensure_road_cache()
		route.redraw_key = 0
		check(route.needs_redraw(), "new map needs its first draw")
		for frame in 120: check(not route.needs_redraw(), "idle map does not request continuous redraw")
		route.selected_node = 0;check(route.needs_redraw(), "selection redraws")
		check(not route.needs_redraw(), "selection settles after one redraw")
		route.selected_node = -1;check(route.needs_redraw(), "cleared selection redraws")
		route.deck_view = true;check(route.needs_redraw(), "deck opens")
		route.deck_view = false;check(route.needs_redraw(), "deck closes")
		route.scroll_y = 0;check(route.needs_redraw(), "scroll redraws")
		route.focus_current();check(route.needs_redraw(), "focus current redraws")
		route.stamp_node = 0;route.stamp_elapsed = 0;check(route.needs_redraw(), "stamp begins")
		route.tick(0.2);check(route.needs_redraw(), "stamp animates")
		route.tick(1);check(route.needs_redraw(), "stamp final static frame redraws")
		check(not route.needs_redraw(), "finished stamp does not redraw forever")
		var start = route.position(route.state.nodes[0]);route.click(start);route.click(start);check(route.needs_redraw(), "second node click begins march redraw")
		route.tick(0.4);check(route.needs_redraw(), "march redraws while active")
		route.tick(0.5);check(game.screen == "game", "march enters battle once")
		game.debug_skip();game.choose_reward(-1);route.tick(0)
		check(route.needs_redraw(), "return from battle redraws")
		route.ensure_road_cache();builds = route.road_cache_builds
		game.ui_size += Vector2(1,0);route.ensure_road_cache()
		check(route.road_cache_builds == builds + 1, "resize invalidates cached roads")
		game.ui_size -= Vector2(1,0);route.ensure_road_cache();builds = route.road_cache_builds
		route.state.nodes[0].next = [2];route.ensure_road_cache()
		check(route.road_cache_builds == builds + 1, "topology change invalidates cached roads")
		check(route.road_cache.has(Vector2i(0,2)) and not route.road_cache.has(Vector2i(0,1)), "changed topology uses only current edges")
		builds = route.road_cache_builds
		route.generate(int(route.state.seed) + 1);route.ensure_road_cache()
		check(route.road_cache_builds == builds + 1, "new campaign seed invalidates geometry")
	game.new_expedition();game.route.tick(1)
	game.route.redraw_key = 0;game._process(0)
	check(game.route.redraw_key != 0, "process requests initial map frame")
	var stable_key = game.route.redraw_key;game._process(0)
	check(game.route.redraw_key == stable_key, "idle process preserves stable redraw key")
	game.screen = "home";game._process(0)
	check(game.route.redraw_key == 0, "leaving map invalidates retained screen")
	game.screen = "map";game._process(0)
	check(game.route.redraw_key != 0, "returning map redraws even unchanged state")
	game.screen = "route_choice";check(route.needs_redraw(), "choice screen redraws")
	route.page += 1;check(route.needs_redraw(), "choice pagination redraws")
	route.save_error = ERR_CANT_CREATE;check(route.needs_redraw(), "save status redraws")
	print("MAP PERFORMANCE RESULT ", checks, " checks, ", failures, " failures")
	game.free();quit(1 if failures else 0)
