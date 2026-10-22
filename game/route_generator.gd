extends RefCounted
# Nine-depth, planar chapter graphs. Generation never touches combat RNG or UI.
# Dense integer IDs are saved identities, not coordinates; never reorder on load.
const PROFILES = preload("res://start_profiles.gd")
const ENCOUNTERS = preload("res://encounters.gd")
const VERSION = 1
const PATH_LENGTH = 9
const MAX_ATTEMPTS = 16
const MAX_ENCOUNTER_DRAWS = 48
const CHAPTER_SEED_SALT = 0x5bd1e995
const EVENT_IDS = ["herbalist", "merchant", "manual"]
const KINDS = ["battle", "elite", "camp", "workshop", "event", "boss"]
const SUPPORT = ["event", "camp", "workshop"]
const COMBAT = ["battle", "elite", "boss"]

static func chapter_seed(run_seed: int, chapter: int) -> int:
	return run_seed ^ (CHAPTER_SEED_SALT * (chapter - 1))

static func stream_seed(run_seed: int, chapter: int, domain: String, node_id: int = -1, attempt: int = 0) -> int:
	# Explicit positive 31-bit FNV-style mixing, independent of Dictionary.hash(),
	# draw order in other domains, frame count, viewport and Godot's global RNG.
	var value: int = 2166136261 & 0x7fffffff
	for byte in (str(run_seed) + ":" + str(chapter) + ":" + domain + ":" + str(node_id) + ":" + str(attempt)).to_utf8_buffer():
		value = ((value ^ int(byte)) * 16777619) & 0x7fffffff
	return value

static func _random(run_seed: int, chapter: int, domain: String, node_id: int = -1, attempt: int = 0) -> RandomNumberGenerator:
	var random = RandomNumberGenerator.new()
	random.seed = stream_seed(run_seed, chapter, domain, node_id, attempt)
	return random

static func generate(run_seed: int, chapter: int, identity: String) -> Dictionary:
	if chapter not in [1, 2] or identity not in PROFILES.DATA: return {}
	for attempt in MAX_ATTEMPTS:
		var graph = _candidate(run_seed, chapter, identity, attempt, false)
		if validate(graph, identity): return graph
	# A different, deliberately small blueprint, not another unbounded reroll.
	var fallback = fallback_graph(run_seed, chapter, identity)
	if validate(fallback, identity): return fallback
	push_error("The authored route fallback failed validation; refusing an unsafe map.")
	return {}

static func fallback_graph(run_seed: int, chapter: int, identity: String) -> Dictionary:
	if chapter not in [1, 2] or identity not in PROFILES.DATA: return {}
	return _candidate(run_seed, chapter, identity, MAX_ATTEMPTS, true)

static func _node(nodes: Array, row: int, lane: int, kind: String, band: String = "") -> int:
	var id = nodes.size()
	nodes.append({"id": id, "row": row, "lane": lane, "kind": kind, "next": [], "loot": [],
		"layout": clampi(row, 1, 5), "encounter": {}, "x": 0.5, "y": 1.0 - row / 8.0, "_band": band})
	return id

static func _support(random: RandomNumberGenerator, except: Array = []) -> String:
	var pool = SUPPORT.filter(func(kind): return kind not in except)
	return pool[random.randi_range(0, pool.size() - 1)]

static func _diamond(nodes: Array, anchor: int, start_row: int, branches: Array, merge_kind: String, merge_band: String = "") -> int:
	var length: int = branches[0].size()
	var ends: Array = []
	# Row-major allocation retains id==index and makes the boss the final ID.
	for offset in length:
		var row_ids: Array = []
		for branch in branches.size():
			var spec: Dictionary = branches[branch][offset]
			var lane = branch if branches.size() == 3 else branch * 2
			var id = _node(nodes, start_row + offset, lane, spec.kind, spec.get("band", ""))
			row_ids.append(id)
			if offset == 0: nodes[anchor].next.append(id)
			else: nodes[ends[branch]].next.append(id)
		ends = row_ids
	var merge = _node(nodes, start_row + length, 1, merge_kind, merge_band)
	for id in ends: nodes[id].next.append(merge)
	return merge

static func _spec(kind: String, band: String = "") -> Dictionary:
	return {"kind": kind, "band": band}

static func _candidate(run_seed: int, chapter: int, identity: String, attempt: int, fallback: bool) -> Dictionary:
	var random = _random(run_seed, chapter, "topology", -1, attempt)
	var first_length = 2 if fallback else random.randi_range(1, 2)
	var second_length = 4 - first_length
	var first_width = 2 if fallback or first_length == 1 else random.randi_range(2, 3)
	var second_width = 2 if fallback else random.randi_range(2, 3)
	var first: Array = []
	for branch in first_width:
		var line: Array = []
		if branch < 2:
			line.append(_spec("battle" if branch == 0 else "elite", "a_normal" if branch == 0 else "a_elite"))
			if first_length == 2: line.append(_spec("event" if fallback and branch == 0 else ("camp" if fallback else _support(random))))
		else:
			line.append(_spec(_support(random)));line.append(_spec("battle", "a_normal"))
		first.append(line)
	# Every second-diamond branch has one or two combats. First-node kinds are
	# genuinely different; an elite replaces a route, never becomes compulsory.
	var second: Array = []
	var used_first: Array = []
	for branch in second_width:
		var line: Array = []
		if branch == 0:
			line.append(_spec("battle", "b_first"))
			if second_length == 3: line.append(_spec(_support(random)))
			line.append(_spec("battle", "b_last"))
		elif chapter == 2 and branch == 1:
			line.append(_spec("elite", "b_elite"))
			for offset in second_length - 1: line.append(_spec("event" if fallback else _support(random)))
		else:
			var kind = "camp" if fallback else _support(random, used_first)
			line.append(_spec(kind));line.append(_spec("battle", "b_last"))
			if second_length == 3: line.append(_spec(_support(random)))
		used_first.append(line[0].kind)
		second.append(line)
	var nodes: Array = []
	_node(nodes, 0, 1, "battle", "opening")
	var middle = _diamond(nodes, 0, 1, first, "workshop" if fallback else _support(random))
	var prep_anchor = _diamond(nodes, middle, first_length + 2, second, "battle", "preparation")
	var boss = _diamond(nodes, prep_anchor, 7, [[_spec("camp")], [_spec("workshop")]], "boss", "boss")
	var graph = {"generator_version": VERSION, "run_seed": run_seed, "chapter": chapter,
		"seed": chapter_seed(run_seed, chapter), "entry": 0, "boss_id": boss, "path_length": PATH_LENGTH,
		"decor_seed": stream_seed(run_seed, chapter, "decor"), "layout_seed": stream_seed(run_seed, chapter, "layout"),
		"nodes": nodes, "generation_attempt": attempt, "fallback": fallback}
	_place(graph)
	if not _encounters(graph, attempt, fallback): return {}
	for node in nodes:
		node.erase("_band")
		var loot_random = _random(run_seed, chapter, "loot", node.id)
		node.loot = PROFILES.draw_rewards(identity, loot_random, 3 if node.kind == "elite" else 2)
		if node.kind == "event":
			var event_random = _random(run_seed, chapter, "event_type", node.id)
			node.event_id = EVENT_IDS[event_random.randi_range(0, 2)]
			node.offers = PROFILES.draw_rewards(identity, _random(run_seed, chapter, "event_offers", node.id))
			node.upgrade_seed = stream_seed(run_seed, chapter, "upgrade", node.id)
	return graph

static func _place(graph: Dictionary):
	var random = _random(graph.run_seed, graph.chapter, "layout")
	for row in PATH_LENGTH:
		var layer = graph.nodes.filter(func(node): return node.row == row)
		var drift = random.randf_range(-0.035, 0.035)
		for index in layer.size():
			var base = 0.5
			if layer.size() == 2: base = [0.28, 0.72][index]
			elif layer.size() == 3: base = [0.16, 0.5, 0.84][index]
			# ConfigFile writes about eight significant digits, so use 1/128 rather
			# than a finer binary grid: these fractions need at most seven digits.
			# Saving/loading must not slightly move a landmark or invalidate caches.
			layer[index].x = roundf((base + drift + random.randf_range(-0.012, 0.012)) * 128.0) / 128.0

static func _pick(kind: String, row: int, chapter: int, random: RandomNumberGenerator, exclude: Array = []) -> Dictionary:
	for draw in MAX_ENCOUNTER_DRAWS:
		var config = ENCOUNTERS.node_config(kind, row, random, chapter)
		if config.get("id", "") not in exclude: return config
	return {}

static func _encounters(graph: Dictionary, attempt: int, fallback: bool) -> bool:
	var random = _random(graph.run_seed, graph.chapter, "encounter", -1, attempt)
	var chapter: int = graph.chapter
	var configs: Dictionary = {}
	if fallback:
		# Freeze valid existing encounter IDs, not copies of armies or mechanics.
		var ids = {"opening": "three_pawns", "a_normal": "quick_pawns", "a_elite": "river_cannon", "b_first": "double_advisors", "b_last": "elephant_gap", "preparation": "pawn_cannon", "boss": "palace_final"}
		if chapter == 2:
			ids = {"opening": "c2_heavy_pawns", "a_normal": "c2_lone_guard", "a_elite": "c2_palace_guard", "b_first": "c2_cannon_fort", "b_last": "c2_heavy_pawns", "b_elite": "c2_double_cannon", "preparation": "c2_lone_guard", "boss": "c2_inner_city"}
		for band in ids:
			var kind = "boss" if band == "boss" else ("elite" if band in ["a_elite", "b_elite"] else "battle")
			var rules: Array = []
			if chapter == 1:
				if kind == "elite": rules = [ENCOUNTERS.RULE_FOR[ids[band]]]
				elif kind == "boss": rules = ["palace_rotation", "last_stand"]
			configs[band] = {"id": ids[band], "tier": kind, "rules": rules}
			if chapter == 2: configs[band].chapter = 2
	else:
		configs.opening = _pick("battle", 0, chapter, random)
		configs.a_normal = _pick("battle", 1, chapter, random, [configs.opening.id])
		configs.a_elite = _pick("elite", 1, chapter, random)
		if configs.a_normal.is_empty() or configs.a_elite.is_empty(): return false
		var previous = [configs.a_normal.id, configs.a_elite.id]
		configs.b_first = _pick("battle", 4, chapter, random, previous)
		if configs.b_first.is_empty(): return false
		configs.b_last = _pick("battle", 5, chapter, random, previous + [configs.b_first.id])
		if configs.b_last.is_empty(): return false
		var last = [configs.b_last.id]
		if chapter == 2:
			configs.b_elite = _pick("elite", 4, chapter, random, [configs.a_elite.id])
			if configs.b_elite.is_empty(): return false
			last.append(configs.b_elite.id)
		configs.preparation = _pick("battle", 6, chapter, random, last)
		configs.boss = _pick("boss", 8, chapter, random)
		if configs.preparation.is_empty(): return false
	for node in graph.nodes:
		if node.kind in COMBAT: node.encounter = configs[node._band].duplicate(true)
	return true

static func validate_structure(graph, identity: String = "") -> bool:
	return _structure_error(graph, identity).is_empty()

static func validate(graph, identity: String = "") -> bool:
	return validation_errors(graph, identity).is_empty()

static func validation_errors(graph, identity: String = "") -> Array:
	var error = _structure_error(graph, identity)
	if not error.is_empty(): return [error]
	var errors: Array = []
	var nodes: Array = graph.nodes
	var elite_count = 0
	var must: Dictionary = {}
	for id in range(nodes.size() - 1, -1, -1):
		var node: Dictionary = nodes[id]
		if node.kind == "elite": elite_count += 1
		var next_kinds: Array = []
		var common: Array = []
		for target in node.next:
			if nodes[target].kind in next_kinds: errors.append("fork children must have distinct route kinds")
			next_kinds.append(nodes[target].kind)
			if target == node.next[0]: common = must[target].duplicate()
			else: common = common.filter(func(value): return value in must[target])
		if node.next.size() > 1:
			var bounded_merge = false
			for target in common:
				if nodes[target].row - node.row in [2, 3, 4]: bounded_merge = true
			if not bounded_merge: errors.append("fork must reconverge after one to three interior nodes")
		if node.row == 6 and (next_kinds.size() != 2 or "camp" not in next_kinds or "workshop" not in next_kinds):
			errors.append("every approach must offer camp versus workshop immediately before boss")
		must[id] = [id] + common
	if elite_count > graph.chapter: errors.append("chapter elite node cap exceeded")
	var summaries: Array = []
	_check_paths(graph, graph.entry, [], summaries, errors)
	if not summaries.any(func(summary): return summary.elites == 0): errors.append("a zero-elite route is required")
	# Ordered endpoints and common layer heights guarantee noncrossing vertical-
	# tangent Beziers. Shared starts/ends are intentional split/merge junctions.
	for row in PATH_LENGTH - 1:
		var edges: Array = []
		for node in nodes:
			if node.row == row:
				for target in node.next: edges.append([node.id, target])
		for i in edges.size():
			for j in range(i + 1, edges.size()):
				var a: Array = edges[i];var b: Array = edges[j]
				if a[0] == b[0] or a[1] == b[1]: continue
				if (nodes[a[0]].x - nodes[b[0]].x) * (nodes[a[1]].x - nodes[b[1]].x) <= 0:
					errors.append("independent route edges cross or overlap")
	return errors

static func _structure_error(graph, identity: String) -> String:
	if not graph is Dictionary: return "graph must be a dictionary"
	for key in ["generator_version", "run_seed", "chapter", "seed", "entry", "boss_id", "path_length", "decor_seed", "layout_seed", "generation_attempt"]:
		if not graph.get(key) is int: return "missing integer graph metadata: " + key
	if graph.generator_version != VERSION or graph.chapter not in [1, 2] or graph.path_length != PATH_LENGTH: return "unsupported graph version, chapter or depth"
	if graph.seed != chapter_seed(graph.run_seed, graph.chapter): return "chapter seed mismatch"
	if graph.decor_seed != stream_seed(graph.run_seed, graph.chapter, "decor") or graph.layout_seed != stream_seed(graph.run_seed, graph.chapter, "layout"): return "independent seed metadata mismatch"
	if not graph.get("fallback") is bool or graph.generation_attempt < 0 or graph.generation_attempt > MAX_ATTEMPTS: return "invalid generation receipt"
	if graph.fallback != (graph.generation_attempt == MAX_ATTEMPTS): return "fallback receipt mismatch"
	if not identity.is_empty() and identity not in PROFILES.DATA: return "unknown reward identity"
	if not graph.get("nodes") is Array or graph.nodes.size() < PATH_LENGTH or graph.nodes.size() > 23: return "invalid graph size"
	var nodes: Array = graph.nodes
	if graph.entry != 0 or graph.boss_id != nodes.size() - 1: return "invalid stable entry or boss identity"
	var rows: Array = [[], [], [], [], [], [], [], [], []]
	for id in nodes.size():
		var node = nodes[id]
		if not node is Dictionary: return "node must be a dictionary"
		for key in ["id", "row", "lane", "layout"]:
			if not node.get(key) is int: return "invalid integer node field: " + key
		if node.id != id or node.row < 0 or node.row >= PATH_LENGTH or node.lane not in [0, 1, 2] or node.layout < 1 or node.layout > 5: return "invalid node identity or layer"
		if not node.get("kind") is String or node.kind not in KINDS: return "unknown node kind"
		for key in ["x", "y"]:
			if not (node.get(key) is float or node.get(key) is int) or not is_finite(float(node[key])) or node[key] < 0.0 or node[key] > 1.0: return "invalid normalized position"
		if not is_equal_approx(float(node.y), 1.0 - node.row / 8.0): return "position disagrees with layer"
		rows[node.row].append(id)
		if not node.get("next") is Array or node.next.size() > 3: return "invalid edge list"
		var seen: Array = []
		for target in node.next:
			if not target is int or target <= id or target >= nodes.size() or target in seen: return "invalid or repeated forward edge"
			seen.append(target)
		if not node.get("encounter") is Dictionary: return "encounter must be stored"
		if node.kind in COMBAT:
			if not ENCOUNTERS.valid_config(node.encounter) or node.encounter.tier != node.kind or node.encounter.get("chapter", 1) != graph.chapter: return "invalid chapter encounter"
		elif not node.encounter.is_empty(): return "non-combat node has an army"
		if not _valid_cards(node.get("loot"), 4 if node.kind == "elite" else 3, identity): return "invalid stored reward candidates"
		if node.kind == "event":
			if node.get("event_id", "") not in EVENT_IDS or not node.get("upgrade_seed") is int or not _valid_cards(node.get("offers"), 3, identity): return "invalid event payload"
	for row in PATH_LENGTH:
		if rows[row].is_empty() or rows[row].size() > 3: return "each layer requires one to three candidates"
		var previous_x = -1.0
		var lanes: Array = []
		for id in rows[row]:
			if nodes[id].x <= previous_x or nodes[id].lane in lanes: return "layer lanes must be strictly ordered"
			previous_x = nodes[id].x;lanes.append(nodes[id].lane)
	if rows[0] != [graph.entry] or rows[8] != [graph.boss_id] or nodes[0].kind != "battle" or nodes[graph.boss_id].kind != "boss": return "unique opening battle and final boss required"
	var reachable: Dictionary = {0: true}
	for node in nodes:
		if not reachable.has(node.id): return "node unreachable from opening"
		if node.id == graph.boss_id:
			if not node.next.is_empty(): return "boss cannot have outgoing edges"
		elif node.kind == "boss" or node.next.is_empty(): return "premature boss or dead end"
		for target in node.next:
			if nodes[target].row != node.row + 1: return "edges must advance exactly one layer"
			reachable[target] = true
	return ""

static func _valid_cards(cards, count: int, identity: String) -> bool:
	if not cards is Array or cards.size() != count: return false
	var allowed: Array = PROFILES.COMMON.duplicate()
	if identity.is_empty():
		for profile in PROFILES.DATA.values(): allowed.append_array(profile.rewards)
	else: allowed.append_array(PROFILES.DATA[identity].rewards)
	var seen: Array = []
	for card in cards:
		if not card is String or card not in allowed or card in seen: return false
		seen.append(card)
	return true

static func _check_paths(graph: Dictionary, id: int, path: Array, summaries: Array, errors: Array):
	var next_path = path + [id]
	var node: Dictionary = graph.nodes[id]
	if not node.next.is_empty():
		for target in node.next: _check_paths(graph, target, next_path, summaries, errors)
		return
	var combats = 0;var elites = 0;var services = 0;var last_encounter = "";var previous_kind = ""
	for target in next_path:
		var item: Dictionary = graph.nodes[target]
		if item.kind in COMBAT:
			if item.kind != "boss": combats += 1
			if item.encounter.id == last_encounter: errors.append("successive combats repeat an encounter template")
			last_encounter = item.encounter.id
		if item.kind == "elite":
			elites += 1
			if previous_kind == "elite": errors.append("adjacent elite nodes")
		if item.kind in ["camp", "workshop"]: services += 1
		previous_kind = item.kind
	if next_path.size() != PATH_LENGTH or id != graph.boss_id: errors.append("all complete paths must have nine nodes ending at boss")
	if combats < 4 or combats > 5: errors.append("each path needs four to five combats before the boss")
	if elites > graph.chapter: errors.append("per-path elite cap exceeded")
	if services < 1 or graph.nodes[next_path[-2]].kind not in ["camp", "workshop"]: errors.append("every path needs service and immediate boss preparation")
	summaries.append({"combats": combats, "elites": elites})
