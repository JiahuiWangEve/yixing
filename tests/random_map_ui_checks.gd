extends SceneTree
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("RANDOM MAP UI: " + label)
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	var route = game.route
	for size in [Vector2(1280,940), Vector2(390,844), Vector2(360,640), Vector2(844,390)]:
		for chapter in [1,2]:
			for seed_number in [0,1,42,149,4242,99991]:
				game.configure_layout(size);game.player_skill = "king";game.new_expedition()
				var rng_before = game.rng.state
				route.generate(seed_number, chapter);route.tick(0)
				check(game.rng.state == rng_before, "map generation does not consume combat RNG")
				var original: Dictionary = route.state.duplicate(true)
				var scale_factor = minf(size.x / game.ui_size.x, size.y / game.ui_size.y)
				var area: Rect2 = route.map_rect()
				var paper = Rect2(area.position, Vector2(area.size.x, route.content_height()))
				var hits: Array = []
				for node in route.state.nodes:
					var hit: Rect2 = route.hit_rect(node);hit.position.y += route.scroll_y
					var art: Rect2 = route.art_rect(node);art.position.y += route.scroll_y
					var stamp: Rect2 = route.stamp_rect(node);stamp.position.y += route.scroll_y
					check(paper.encloses(hit) and paper.encloses(art) and paper.encloses(stamp), "node, label, and victory seal fit the scrollable paper")
					check(hit.size.x * scale_factor >= 44 and hit.size.y * scale_factor >= 44, "touch targets retain at least 44 physical pixels")
					for previous in hits: check(not hit.intersects(previous), "node touch targets never overlap")
					hits.append(hit)
					if node.row == 8: check(art.position.y >= area.position.y + 8, "boss art has safe top padding")
				route.ensure_road_cache();var builds = route.road_cache_builds
				var decorations: Array = route.decoration_layout().duplicate(true)
				for decor in decorations: check(route.decoration_clear(decor.rect), "background remains clear of labels, seals, nodes, and road corridors")
				for frame in 8:
					route.scroll_y = route.scroll_limit() * frame / 7.0;route.selected_node = frame % route.state.nodes.size()
					route.ensure_road_cache();check(route.decoration_layout() == decorations, "scroll and selection never reroll scenery")
				check(route.road_cache_builds == builds, "scroll and selection reuse road geometry")
				check(route.state == original and game.rng.state == rng_before, "presentation cannot mutate routes, encounters, rewards, events, or RNG")
				# Browsing clears transient inspection but preserves the camera and map.
				route.selected_node = 0;route.scroll_y = route.scroll_limit() * 0.4
				var scroll = route.scroll_y
				route.click(route.deck_rect().get_center())
				check(game.card_picker.active and game.card_picker.action == "view", "header always opens the existing read-only grid")
				check(route.selected_node == -1 and not game.information.visible, "opening the deck clears transient map inspection")
				game.card_picker.cancel()
				check(route.selected_node == -1 and route.scroll_y == scroll and route.state == original, "deck close preserves scroll and generated content without restoring inspection")
				# Resizing preserves the content center, not a forced jump to current.
				route.selected_node = 0
				var center_fraction = (route.scroll_y + area.size.y * 0.5) / route.content_height()
				var other = Vector2(844,390) if size.x < size.y else Vector2(390,844)
				game.configure_layout(other);route.tick(0)
				var expected = clampf(center_fraction * route.content_height() - route.map_rect().size.y * 0.5, 0, route.scroll_limit())
				check(absf(route.scroll_y - expected) < 0.01 and route.selected_node == -1, "rotation keeps relative map center and clears transient inspection")
				check(route.state == original, "rotation is layout-only, not regeneration")
				route.save();check(route.resume() and route.state == original, "saved graph resumes byte-equivalent logical content")
	game.queue_free();print("RANDOM MAP UI RESULT %d checks, %d failures" % [checks, failures]);quit(1 if failures else 0)
