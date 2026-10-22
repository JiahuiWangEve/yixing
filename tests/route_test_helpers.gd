extends RefCounted
# Offline test support only. All fixtures retain generated IDs, rows, geometry,
# and edges, and are persisted through the ordinary production save validator.
static func kind_id(route, kind: String) -> int:
	for node in route.state.nodes:
		if node.kind == kind: return node.id
	assert(false, "Generated map has no " + kind)
	return -1

static func path_to(route, target: int, start: int = 0) -> Array:
	var queue = [[start]]
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		if path.back() == target: return path
		for next in route.state.nodes[path.back()].next:
			queue.append(path + [next])
	assert(false, "No generated route to node " + str(target))
	return []

static func before(route, target: int):
	# Set an explicit test's progress to a real prefix, never an invented edge.
	var path = path_to(route, target)
	path.pop_back()
	route.state.visited = path
	route.state.current = -1 if path.is_empty() else path.back()
	route.state.pending = -1
	route.reset_view()

static func configure_node(game, id: int, kind: String, event_id: String = "manual") -> int:
	var node = game.route.state.nodes[id]
	assert(node.row > 0 and node.kind != "boss", "Do not replace root or final boss")
	node.kind = kind
	var random = RandomNumberGenerator.new();random.seed = int(game.route.state.seed) ^ (id * 7919)
	node.loot = game.PROFILES.draw_rewards(game.player_skill, random, 3 if kind == "elite" else 2)
	node.encounter = game.ENCOUNTERS.node_config(kind, node.row, random, game.route.chapter())
	if kind == "event":
		node.event_id = event_id
		node.offers = game.PROFILES.draw_rewards(game.player_skill, random)
		node.upgrade_seed = random.randi()
	else:
		for key in ["event_id", "offers", "upgrade_seed"]: node.erase(key)
	return id

static func next_node(game, kind: String, event_id: String = "manual") -> int:
	assert(game.screen == "map" and not game.route.legal().is_empty())
	return configure_node(game, game.route.legal()[0], kind, event_id)

static func enter_next(game, kind: String, event_id: String = "manual") -> int:
	var id = next_node(game, kind, event_id)
	game.route.enter(id)
	return id

static func finish(game):
	game.input_lock = 0;game.navigation_lock = 0;game.presentation.clear()
	if game.screen == "game":
		game.debug_skip();game.choose_reward(-1)
	else:
		for i in game.route.choices.size():
			if game.route.choices[i].action == "leave": game.route.resolve(i);return

static func walk_before(game, target: int):
	var path = path_to(game.route, target, maxi(0, game.route.state.current))
	if game.route.state.current >= 0: path.pop_front()
	path.pop_back()
	for id in path:
		game.route.enter(id);finish(game)
