extends SceneTree
# Pure generation tests: no scene, save namespace, viewport, or battle state.
const GENERATOR = preload("res://route_generator.gd")
const PROFILES = preload("res://start_profiles.gd")
var checks = 0
var failures = 0

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		if failures <= 25: push_error("ROUTE GENERATOR: " + label)

func _initialize(): call_deferred("run")

func paths(nodes: Array, id: int = 0, path: Array = []) -> Array:
	var complete = path + [id]
	if nodes[id].next.is_empty(): return [complete]
	var result: Array = []
	for target in nodes[id].next: result.append_array(paths(nodes, target, complete))
	return result

func projection(graph: Dictionary, topology_only: bool = false) -> Array:
	var result: Array = []
	for node in graph.nodes:
		var item = [node.id, node.row, node.lane, node.kind, node.next]
		if not topology_only: item.append_array([node.x, node.y, node.encounter, node.get("event_id", ""), node.get("upgrade_seed", -1)])
		result.append(item)
	return result

func independent_paths(graph: Dictionary):
	var seen: Dictionary = {}
	var zero_elite = false
	var all_paths = paths(graph.nodes)
	check(all_paths.size() >= 8 and all_paths.size() <= 18, "bounded serial forks produce eight to eighteen complete routes")
	for path in all_paths:
		var combat = 0;var elite = 0;var service = 0;var branches = 0;var last_encounter = "";var previous_kind = ""
		check(path.size() == 9 and path[0] == 0 and path[-1] == graph.boss_id, "nine actual choices include opening and boss")
		for id in path:
			var node: Dictionary = graph.nodes[id]
			seen[id] = true
			if node.kind in ["battle", "elite", "boss"]:
				if node.kind != "boss": combat += 1
				check(last_encounter != node.encounter.id, "successive combat templates differ even across intervening support")
				last_encounter = node.encounter.id
			if node.kind == "elite":
				elite += 1
				check(previous_kind != "elite", "elite nodes are never adjacent")
			if node.kind in ["camp", "workshop"]: service += 1
			if node.next.size() > 1: branches += 1
			previous_kind = node.kind
		check(combat in [4, 5], "four or five pre-boss combats, including opening and elites")
		check(elite <= graph.chapter and service > 0 and branches == 3, "each path has chapter elite cap, service and three decisions")
		check(graph.nodes[path[-2]].kind in ["camp", "workshop"], "last pre-boss node is preparation, not another battle")
		if elite == 0: zero_elite = true
	check(zero_elite and seen.size() == graph.nodes.size(), "zero-elite path exists and all generated nodes participate")

func check_generation():
	var topologies: Dictionary = {}
	var edge_shapes: Dictionary = {}
	var event_counts = {"herbalist": 0, "merchant": 0, "manual": 0}
	var repeated_event = false
	var fallback_count = 0
	var attempts: Dictionary = {}
	var started = Time.get_ticks_usec()
	for seed_number in range(-20, 980):
		for chapter in [1, 2]:
			var identity: String = ["king", "horse", "artillery"][absi(seed_number) % 3]
			var graph = GENERATOR.generate(seed_number, chapter, identity)
			check(not graph.is_empty(), "valid inputs always generate a graph")
			if graph.is_empty(): continue
			check(GENERATOR.validate(graph, identity), "all generated paths satisfy strict validation: " + str(GENERATOR.validation_errors(graph, identity)))
			check(graph.nodes.size() >= 14 and graph.nodes.size() <= 18, "bounded node count")
			check(graph.generation_attempt <= GENERATOR.MAX_ATTEMPTS, "finite generation receipt")
			attempts[graph.generation_attempt] = attempts.get(graph.generation_attempt, 0) + 1
			if graph.fallback: fallback_count += 1
			if seed_number < 108: check(graph == GENERATOR.generate(seed_number, chapter, identity), "same inputs reproduce full graph and payloads")
			topologies[str(projection(graph, true))] = true
			edge_shapes[str(graph.nodes.map(func(node): return [node.row, node.lane, node.next]))] = true
			independent_paths(graph)
			var events: Array = []
			for node in graph.nodes:
				check(node.loot.size() == (4 if node.kind == "elite" else 3), "only elite reward candidate count increases")
				var own = node.loot.filter(func(card): return card in PROFILES.DATA[identity].rewards)
				check(own.size() == (3 if node.kind == "elite" else 2), "three exclusive elite choices; ordinary remains two")
				if node.kind != "event": continue
				event_counts[node.event_id] += 1
				if node.event_id in events: repeated_event = true
				events.append(node.event_id)
				check(node.offers.size() == 3 and node.offers != [], "merchant offers remain three independent saved choices")
			if chapter == 2: check(graph.nodes[0].encounter.id == "c2_heavy_pawns", "chapter two still opens with authored heavy-pawn introduction")
	check(topologies.size() > 100, "seed changes actual node types and topology, not just payloads")
	check(edge_shapes.size() == 6, "all six distinct fork-depth and width shapes occur")
	var total: int = event_counts.herbalist + event_counts.merchant + event_counts.manual
	for id in event_counts:
		check(absf(float(event_counts[id]) / total - 1.0 / 3.0) < 0.035, "event sampling is equal thirds over actual event count: " + id)
	check(repeated_event, "independent event sampling allows repeated identities")
	check(fallback_count < 20, "constructive grammar does not rely on fallback in routine generation")
	print("GENERATOR SAMPLE graphs=2000 topologies=", topologies.size(), " events=", event_counts, " attempts=", attempts, " ms=", (Time.get_ticks_usec() - started) / 1000.0)

func check_streams():
	for seed_number in [-9223372036854775807, -1, 0, 1, 9182, 9223372036854775807]:
		for chapter in [1, 2]:
			var graph = GENERATOR.generate(seed_number, chapter, "king")
			check(not graph.is_empty(), "negative and full-width seeds are supported")
			var domains: Array = []
			for domain in ["topology", "encounter", "event_type", "event_offers", "upgrade", "loot", "layout", "decor"]:
				var derived = GENERATOR.stream_seed(seed_number, chapter, domain)
				check(derived not in domains, "independent RNG domains have distinct sampled seeds")
				domains.append(derived)
			for identity in ["horse", "artillery"]:
				var other = GENERATOR.generate(seed_number, chapter, identity)
				check(projection(graph) == projection(other), "profile reward weights cannot perturb topology, encounters, events or geometry")
				check(graph.decor_seed == other.decor_seed and graph.layout_seed == other.layout_seed, "presentation streams ignore reward identity")
			seed(1739)
			var expected = randi()
			seed(1739)
			GENERATOR.generate(seed_number, chapter, "king")
			check(randi() == expected, "generation leaves the global RNG untouched")
			var other_chapter = GENERATOR.generate(seed_number, 3 - chapter, "king")
			check(graph.seed != other_chapter.seed and graph.decor_seed != other_chapter.decor_seed, "chapters have independent seed identities")
	check(GENERATOR.generate(0, 0, "king").is_empty() and GENERATOR.generate(0, 1, "unknown").is_empty(), "invalid generator inputs fail without retry loops")

func check_fallback():
	for seed_number in [-1, 0, 17, 9182]:
		for chapter in [1, 2]:
			for identity in ["king", "horse", "artillery"]:
				var graph = GENERATOR.fallback_graph(seed_number, chapter, identity)
				check(graph.fallback and graph.generation_attempt == GENERATOR.MAX_ATTEMPTS and graph.nodes.size() == 14, "fallback has finite receipt and independent fourteen-node blueprint")
				check(GENERATOR.validate(graph, identity), "fallback passes the identical complete validator")
				check(graph == GENERATOR.fallback_graph(seed_number, chapter, identity), "fallback payloads are deterministic, not emergency rerolls")
				independent_paths(graph)

func rejected(graph: Dictionary, label: String):
	check(not GENERATOR.validate_structure(graph, "king"), "reject unsafe stored graph: " + label)
	check(not GENERATOR.validate(graph, "king"), "strict validation also rejects: " + label)

func check_validation():
	var original = GENERATOR.fallback_graph(719, 1, "king")
	for key in ["generator_version", "nodes", "entry", "boss_id", "path_length", "run_seed", "seed", "decor_seed", "fallback"]:
		var broken = original.duplicate(true);broken.erase(key);rejected(broken, "missing " + key)
	for field in ["id", "row", "lane", "x", "y", "kind", "next", "encounter", "loot"]:
		var broken = original.duplicate(true);broken.nodes[1].erase(field);rejected(broken, "missing node " + field)
	var invalid_values = [
		{"field": "id", "value": 0}, {"field": "row", "value": 9}, {"field": "lane", "value": 4},
		{"field": "x", "value": NAN}, {"field": "y", "value": 0.7}, {"field": "kind", "value": "secret"},
		{"field": "next", "value": [999]}, {"field": "next", "value": [0]}, {"field": "next", "value": [3, 3]},
		{"field": "next", "value": []}, {"field": "next", "value": ["3"]}, {"field": "encounter", "value": {}},
		{"field": "loot", "value": ["sword", "sword", "sword"]}]
	for change in invalid_values:
		var broken = original.duplicate(true);broken.nodes[1][change.field] = change.value;rejected(broken, change.field + "=" + str(change.value))
	var disconnected = original.duplicate(true);disconnected.nodes[0].next = [1];rejected(disconnected, "unreachable branch")
	var wrong_chapter = original.duplicate(true);wrong_chapter.nodes[1].encounter = {"id": "c2_heavy_pawns", "tier": "battle", "rules": [], "chapter": 2};rejected(wrong_chapter, "foreign chapter encounter")
	var no_budget = original.duplicate(true)
	for node in no_budget.nodes:
		if node.id not in [0, no_budget.boss_id] and node.kind in ["battle", "elite"]:
			node.kind = "camp";node.encounter = {};node.loot = original.nodes[0].loot.duplicate()
	check(GENERATOR.validate_structure(no_budget, "king") and not GENERATOR.validate(no_budget, "king"), "safe isolated fixtures may vary content, but generation rejects invalid combat budget")
	var repeated = original.duplicate(true);repeated.nodes[1].encounter = repeated.nodes[0].encounter.duplicate(true)
	check(GENERATOR.validate_structure(repeated, "king") and not GENERATOR.validate(repeated, "king"), "saved known armies remain readable; generator rejects repeated combat")
	var crossing = original.duplicate(true);crossing.nodes[1].next = [4];crossing.nodes[2].next = [3]
	check(GENERATOR.validate_structure(crossing, "king") and not GENERATOR.validate(crossing, "king"), "crossing paths are rejected by generation without unsafe load indexing")
	check(original == GENERATOR.fallback_graph(719, 1, "king"), "validation never mutates input or seed streams")
	var config = ConfigFile.new();config.set_value("graph", "actual", original)
	var loaded = ConfigFile.new()
	check(loaded.parse(config.encode_to_text()) == OK, "actual graph serializes in existing ConfigFile format")
	var restored = loaded.get_value("graph", "actual", {})
	check(GENERATOR.validate(restored, "king") and projection(restored) == projection(original), "stored graph resumes with same IDs, payloads and normalized positions")
	check(config.save("user://route_generator_roundtrip.cfg") == OK, "actual graph writes to disposable user storage")
	var disk = ConfigFile.new()
	check(disk.load("user://route_generator_roundtrip.cfg") == OK and disk.get_value("graph", "actual", {}) == original, "real file save/load preserves graph exactly")
	check(disk.save("user://route_generator_roundtrip.cfg") == OK, "resumed graph can be saved without regeneration")
	var twice = ConfigFile.new()
	check(twice.load("user://route_generator_roundtrip.cfg") == OK and twice.get_value("graph", "actual", {}) == original, "two complete save/load cycles preserve exact graph and coordinates")

func run():
	check_generation()
	check_streams()
	check_fallback()
	check_validation()
	print("ROUTE GENERATOR RESULT ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
