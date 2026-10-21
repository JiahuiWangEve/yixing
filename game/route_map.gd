extends RefCounted
# Chapter state lives outside battle undo snapshots. Forward-only edges and stored
# rewards make navigation deterministic, independently of combat RNG.
# Flat, transparent woodcut symbols: the paper remains visible through the ink gaps.
const SYMBOLS = {
	"battle": preload("res://assets/map/seals/battle.svg"),
	"elite": preload("res://assets/map/seals/elite.svg"),
	"camp": preload("res://assets/map/seals/camp.svg"),
	"workshop": preload("res://assets/map/seals/workshop.svg"),
	"event": preload("res://assets/map/seals/event.svg"),
	"outpost": preload("res://assets/map/seals/outpost.svg"),
	"boss": preload("res://assets/map/seals/boss.svg")
}
const VICTORY_SEAL = preload("res://assets/map/seals/victory_seal.svg")
const PAPER = Color("f3f0e7")
const PAPER_LIGHT = Color("f8f5ed")
const INK = Color("161713")
const MUTED = Color("706f66")
const RED = Color("b32922")
const STAMP_SECONDS = 0.42
var stamp_node = -1
var stamp_elapsed = STAMP_SECONDS
var decoration_cache: Array = []
var decoration_key = ""
const SAVE = "user://route_run_v080.cfg"
const WEB_SAVE_KEY = "yixing.route_run.v080"
const LABELS = {"battle": "战", "elite": "精", "camp": "营", "workshop": "坊", "event": "事", "outpost": "寨", "boss": "帅"}
var game
var state: Dictionary = {}
var choices: Array = []
var deck_view = false
var save_error = OK
# Presentation state is deliberately transient: reload never commits an unfinished march.
var selected_node = -1
var travel_target = -1
var travel_elapsed = 0.0
const TRAVEL_SECONDS = 0.85
var scroll_y = 0.0
var focus_needed = true
var pointer_id = -2
var pointer_start = Vector2.ZERO
var pointer_last = Vector2.ZERO
var pointer_dragged = false
var pointer_scroll = false
var layout_size = Vector2.ZERO
const TITLES = {"battle": "军旗阵地", "elite": "精锐军阵", "camp": "行军营地", "workshop": "山间工坊", "event": "渡口偶遇", "outpost": "关隘据点", "boss": "终点城寨"}
const DETAILS = {"battle": "战胜守军后选择战利品。", "elite": "较强敌阵；胜利后选择战利品。", "camp": "升级一张剑或枪，或为下一战整备。", "workshop": "永久删除一张牌，也可直接离开。", "event": "借渡整备，或访师获得一张长枪。", "outpost": "破寨可将本章敌将生命由3降为2。", "boss": "击败敌将即完成本章。"}

func reset_view():
	selected_node = -1;travel_target = -1;travel_elapsed = 0.0
	stamp_node = -1;stamp_elapsed = STAMP_SECONDS
	pointer_id = -2;pointer_dragged = false;focus_needed = true
func side_layout() -> bool: return not game.mobile_layout or game.compact_landscape
func map_rect() -> Rect2:
	if not game.mobile_layout: return Rect2(24, 116, 850, 800)
	if game.compact_landscape: return Rect2(14, 90, game.ui_size.x - 334, game.ui_size.y - 104)
	return Rect2(14, 112, game.ui_size.x - 28, game.ui_size.y - 282)
func info_rect() -> Rect2:
	if side_layout(): return Rect2(map_rect().end.x + 20, map_rect().position.y, game.ui_size.x - map_rect().end.x - 44, map_rect().size.y)
	return Rect2(14, game.ui_size.y - 158, game.ui_size.x - 28, 144)
func content_height() -> float:
	# Three to four chapter layers in portrait; desktop keeps generous art spacing.
	if not game.mobile_layout: return 1240.0
	if game.compact_landscape: return 1160.0
	return map_rect().size.y * 2.4
func scroll_limit() -> float: return maxf(0, content_height() - map_rect().size.y)
func content_point(node: Dictionary) -> Vector2:
	# Uneven terrain, not a centered ladder. Topology is unchanged in generate().
	var xs = [0.46, 0.15, 0.50, 0.85, 0.22, 0.76, 0.53, 0.13, 0.48, 0.86, 0.24, 0.73, 0.15, 0.49, 0.84, 0.79]
	var ys = [0.94, 0.82, 0.79, 0.83, 0.69, 0.66, 0.56, 0.45, 0.43, 0.46, 0.33, 0.33, 0.20, 0.18, 0.21, 0.075]
	var margin = 28.0 if game.mobile_layout else 42.0
	return Vector2(map_rect().position.x + margin + xs[node.id] * (map_rect().size.x - margin * 2), map_rect().position.y + 32 + ys[node.id] * (content_height() - 80))
func focus_current():
	if not active(): return
	var node = state.nodes[maxi(0, state.current)]
	scroll_y = clampf(content_point(node).y - map_rect().position.y - map_rect().size.y * 0.73, 0, scroll_limit())
	focus_needed = false
func edge_point(from: Vector2, to: Vector2, progress: float) -> Vector2:
	var dy = (to.y - from.y) * 0.48
	return from.bezier_interpolate(from + Vector2(0, dy), to - Vector2(0, dy), to, progress)
func march_point(progress: float) -> Vector2:
	var target = position(state.nodes[travel_target])
	if state.current < 0: return target
	return edge_point(position(state.nodes[state.current]), target, progress)
func confirm_rect() -> Rect2:
	var info = info_rect()
	if side_layout(): return Rect2(info.position.x + 16, info.end.y - 80, info.size.x - 32, 64)
	return Rect2(game.ui_size.x - 190, game.ui_size.y - 78, 166, 60)
func cancel_rect() -> Rect2:
	var info = info_rect()
	if side_layout(): return Rect2(info.position.x + 16, info.end.y - 150, info.size.x - 32, 58)
	return Rect2(24, game.ui_size.y - 78, 126, 60)
func center_rect() -> Rect2:
	if side_layout(): return Rect2(info_rect().position.x + 16, info_rect().end.y - 150, info_rect().size.x - 32, 58)
	return Rect2(game.ui_size.x - 190, game.ui_size.y - 78, 166, 60)
func confirm():
	if travel_target >= 0 or selected_node not in legal(): return
	travel_target = selected_node;selected_node = -1;travel_elapsed = 0.0;pointer_id = -2
func tick(delta: float):
	if game.screen != "map": return
	stamp_elapsed = minf(STAMP_SECONDS, stamp_elapsed + delta)
	if layout_size != game.ui_size:
		layout_size = game.ui_size;focus_needed = true;pointer_id = -2
	if focus_needed: focus_current()
	if travel_target >= 0:
		travel_elapsed += delta
		if travel_elapsed >= TRAVEL_SECONDS:
			var target = travel_target
			travel_target = -1
			enter(target)
func cancel_pointer():
	pointer_id = -2;pointer_dragged = false;pointer_scroll = false
func pointer_press(pos: Vector2, id: int):
	if travel_target >= 0 or pointer_id != -2: return
	pointer_id = id;pointer_start = pos;pointer_last = pos;pointer_dragged = false
	pointer_scroll = game.screen == "map" and not deck_view and map_rect().has_point(pos)
func pointer_motion(pos: Vector2, id: int):
	if pointer_id != id: return
	if pos.distance_to(pointer_start) >= 12: pointer_dragged = true
	if pointer_scroll and pointer_dragged: scroll_y = clampf(scroll_y - (pos.y - pointer_last.y), 0, scroll_limit())
	pointer_last = pos
func pointer_release(pos: Vector2, id: int, canceled: bool = false):
	if pointer_id != id: return
	var tap = not canceled and not pointer_dragged and pos.distance_to(pointer_start) < 12
	pointer_id = -2
	if tap: click(pos)
func input_event(event) -> bool:
	if game.screen not in ["map", "route_choice"]: return false
	if event is InputEventScreenTouch:
		game.touch_seen = true
		if event.pressed: pointer_press(event.position, event.index)
		else: pointer_release(event.position, event.index, event.canceled)
		return true
	if event is InputEventScreenDrag:
		pointer_motion(event.position, event.index);return true
	if event is InputEventMouse:
		if event.device == -1 and game.touch_seen: return true
		if event is InputEventMouseMotion: pointer_motion(event.position, -1)
		elif event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed: pointer_press(event.position, -1)
				else: pointer_release(event.position, -1)
			elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and travel_target < 0 and map_rect().has_point(event.position) and not deck_view:
				scroll_y = clampf(scroll_y + (100 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -100), 0, scroll_limit())
		return true
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE and travel_target < 0: selected_node = -1;deck_view = false;cancel_pointer()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not event.echo: confirm()
		return true
	return false
func _init(owner): game = owner
func active() -> bool: return not state.is_empty()
func generate(seed_number: int):
	var random = RandomNumberGenerator.new()
	random.seed = seed_number
	state = {"seed": seed_number, "nodes": [], "current": -1, "visited": [], "pending": -1, "prepared": false, "weakened": false, "done": false}
	var rows = [[1], [0, 1, 2], [0, 2], [1], [0, 1, 2], [0, 2], [0, 1, 2], [1]]
	var types = [["battle"], ["event", "elite", "workshop"], ["battle", "outpost"], ["camp"], ["battle", "workshop", "elite"], ["event", "battle"], ["camp", "battle", "workshop"], ["boss"]]
	for row in rows.size():
		for col in rows[row].size():
			var loot = game.PROFILES.draw_rewards(game.player_skill, random)
			state.nodes.append({"id": state.nodes.size(), "row": row, "lane": rows[row][col], "kind": types[row][col], "next": [], "loot": loot, "layout": clampi(row + random.randi_range(0, 1), 1, 5)})
	for node in state.nodes:
		for target in state.nodes:
			if target.row == node.row + 1 and (abs(target.lane - node.lane) <= 1 or rows[node.row].size() == 1 or rows[target.row].size() == 1): node.next.append(target.id)
	choices = [];deck_view = false;reset_view()
func legal() -> Array:
	if not active() or state.done or state.pending >= 0: return []
	return [0] if state.current < 0 else state.nodes[state.current].next
func enter(id: int):
	if game.screen != "map" or id not in legal(): return
	state.pending = id
	var node = state.nodes[id]
	deck_view = false;choices = []
	if node.kind in ["battle", "elite", "boss"]:
		game.stage = 6 if node.kind == "boss" else (maxi(4, node.layout) if node.kind == "elite" else node.layout)
		game.screen = "game";game.start_stage()
		if node.kind == "boss" and state.weakened:
			for enemy in game.enemies:
				if enemy.kind == "g": enemy.hp = 2;enemy.max_hp = 2
		if state.prepared:
			state.prepared = false;game.draw_card()
	else:
		game.screen = "route_choice"
		choices = options()
	save()
func options() -> Array:
	var kind = state.nodes[state.pending].kind
	var result = []
	if kind == "camp":
		for i in game.collection.size():
			if game.collection[i] in ["sword", "spear"]: result.append({"label": "升级「%s」第%d张 · 伤害+1" % [game.CARDS[game.collection[i]][0], i + 1], "action": "upgrade", "index": i})
		result.append({"label": "整备 · 下一战初始额外抽1张", "action": "prepare"})
	elif kind == "workshop":
		for i in game.collection.size(): result.append({"label": "删除「%s」第%d张" % [game.CARDS[game.collection[i]][0], i + 1], "action": "remove", "index": i})
	elif kind == "outpost":
		result.append({"label": "破寨 · 本章敌将生命由3降为2", "action": "weaken"})
	else:
		result.append({"label": "借渡 · 下一战初始额外抽1张", "action": "prepare"})
		result.append({"label": "访师 · 获得一张长枪", "action": "card"})
	result.append({"label": "离开 · 保持牌组", "action": "leave"})
	return result
func resolve(index: int):
	if game.screen != "route_choice" or state.pending < 0 or index < 0 or index >= choices.size(): return
	var choice = choices[index]
	match choice.action:
		"upgrade": game.collection[choice.index] += "_plus"
		"prepare": state.prepared = true
		"remove": game.collection.remove_at(choice.index)
		"weaken": state.weakened = true
		"card": game.collection.append("spear")
	complete()
func complete():
	if not active() or state.pending < 0: return
	state.current = state.pending;state.visited.append(state.pending);state.pending = -1
	game.history.clear();game.cancel_gesture();game.clear_effects();game.rewardui.reset()
	game.hand = [];game.hand_ids = [];game.deck = [];game.discard = [];game.enemies = [];game.energy = 0;game.tuna_turns = 0;game.tuna_active = false
	game.clear_battle_card_effects()
	game.selected = -1;game.free_selected = false;game.handui.reset();game.reinforcement_pending = 0
	game.phase = "play";game.screen = "map";choices = [];page = 0;reset_view()
	stamp_node = state.current;stamp_elapsed = 0.0
	save()
func save():
	if not active(): return
	var config = ConfigFile.new()
	config.set_value("run", "version", 2)
	config.set_value("run", "route", state)
	config.set_value("run", "battle", game.history.capture())
	config.set_value("run", "screen", game.screen if game.screen in ["game", "map", "route_choice"] else "map")
	save_error = config.save(SAVE)
	# IndexedDB flushes asynchronously; a same-format synchronous snapshot keeps
	# a refresh immediately after arrival/reward from loading the prior state.
	if OS.has_feature("web"):
		var encoded = JSON.stringify(config.encode_to_text())
		var stored = JavaScriptBridge.eval("(function(){try{localStorage.setItem('" + WEB_SAVE_KEY + "'," + encoded + ");return true;}catch(e){return false;}})()")
		if stored == true: save_error = OK
func resume() -> bool:
	var config = ConfigFile.new()
	var loaded = false
	if OS.has_feature("web"):
		var snapshot = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('" + WEB_SAVE_KEY + "')||'';}catch(e){return '';}})()")
		if snapshot is String and not snapshot.is_empty(): loaded = config.parse(snapshot) == OK
	if not loaded: loaded = config.load(SAVE) == OK
	if not loaded or config.get_value("run", "version", 0) != 2: return false
	var saved = config.get_value("run", "route", {})
	var battle = config.get_value("run", "battle", {})
	var saved_screen = config.get_value("run", "screen", "map")
	if not valid_snapshot(saved, battle, saved_screen): return false
	game.tutorial.stop();game.history.clear();game.cancel_gesture();game.clear_effects()
	state = saved.duplicate(true)
	for key in game.HISTORY.FIELDS: game.set(key, battle[key])
	game.rng.state = battle.rng_state
	game.screen = config.get_value("run", "screen", "map")
	game.input_lock = 0;game.navigation_lock = 0;game.selected = -1;game.free_selected = false
	game.rewardui.reset();game.handui.reset();page = 0;deck_view = false;reset_view()
	choices = options() if game.screen == "route_choice" else []
	return true
func valid_snapshot(saved, battle, saved_screen) -> bool:
	# Validate the entire current-version envelope before touching live state.
	if not saved is Dictionary or not battle is Dictionary: return false
	if saved_screen not in ["map", "game", "route_choice"]: return false
	for key in ["seed", "nodes", "current", "visited", "pending", "prepared", "weakened", "done"]:
		if not saved.has(key): return false
	if not saved.nodes is Array or saved.nodes.size() != 16 or not saved.visited is Array: return false
	if not saved.current is int or not saved.pending is int or not saved.seed is int: return false
	if saved.current < -1 or saved.current >= 16 or saved.pending < -1 or saved.pending >= 16: return false
	for key in ["prepared", "weakened", "done"]:
		if not saved[key] is bool: return false
	if saved.done: return false
	var kinds = ["battle", "event", "elite", "workshop", "battle", "outpost", "camp", "battle", "workshop", "elite", "event", "battle", "camp", "battle", "workshop", "boss"]
	var rows = [0, 1, 1, 1, 2, 2, 3, 4, 4, 4, 5, 5, 6, 6, 6, 7]
	var lanes = [1, 0, 1, 2, 0, 2, 1, 0, 1, 2, 0, 2, 0, 1, 2, 1]
	for id in 16:
		var node = saved.nodes[id]
		if not node is Dictionary: return false
		for key in ["id", "row", "lane", "kind", "next", "loot", "layout"]:
			if not node.has(key): return false
		if node.id != id or node.row != rows[id] or node.lane != lanes[id] or node.kind != kinds[id]: return false
		if not node.next is Array or not node.loot is Array or not node.layout is int or node.layout < 1 or node.layout > 5: return false
		var expected = []
		for target in 16:
			if rows[target] == rows[id] + 1 and (abs(lanes[target] - lanes[id]) <= 1 or rows[id] in [0, 3, 7] or rows[target] in [0, 3, 7]): expected.append(target)
		if node.next != expected: return false
		for card in node.loot:
			if card not in game.CARDS: return false
	var previous = -1
	for id in saved.visited:
		if not id is int or id < 0 or id >= 16: return false
		if (previous < 0 and id != 0) or (previous >= 0 and id not in saved.nodes[previous].next): return false
		previous = id
	if previous != saved.current: return false
	if saved.pending >= 0:
		if saved.pending not in ([0] if saved.current < 0 else saved.nodes[saved.current].next): return false
		if saved_screen == "map": return false
		var combat = saved.nodes[saved.pending].kind in ["battle", "elite", "boss"]
		if (saved_screen == "game") != combat: return false
	elif saved_screen != "map": return false
	if not battle.has("rng_state") or not battle.rng_state is int: return false
	for key in game.HISTORY.FIELDS:
		if not battle.has(key): return false
		var current_value = game.get(key)
		if typeof(battle[key]) != typeof(current_value):
			# ConfigFile preserves numeric values; runtime counters can begin as ints.
			if not ((battle[key] is int or battle[key] is float) and (current_value is int or current_value is float)): return false
	if battle.player_skill not in game.PROFILES.DATA or battle.phase not in ["play", "discard", "reward", "win", "dead"]: return false
	for key in ["collection", "deck", "discard", "hand", "rewards"]:
		for card in battle[key]:
			if card not in game.CARDS: return false
	if battle.active_displacements < 0 or battle.shield_charges not in [0, 1] or battle.next_enemy_uid < 1: return false
	var ids = {}
	for enemy in battle.enemies:
		if not enemy is Dictionary or not enemy.has("kind") or not enemy.has("pos") or not enemy.pos is Vector2i: return false
		if not enemy.get("uid") is int or enemy.uid < 1 or ids.has(enemy.uid) or enemy.uid >= battle.next_enemy_uid: return false
		ids[enemy.uid] = true
	for bleed in battle.pending_bleeds:
		if not bleed is Dictionary or not bleed.get("enemy_uid") is int or not bleed.get("amount") is int: return false
		if bleed.enemy_uid < 1 or bleed.amount < 1: return false
	return true
func position(node: Dictionary) -> Vector2:
	return content_point(node) - Vector2(0, scroll_y)
func home_rect() -> Rect2: return Rect2(24, 12, 100, 44)
func button(rect: Rect2, label: String, primary: bool = false):
	game.panel(rect, INK if primary else PAPER_LIGHT, INK if primary else Color("aaa89c"))
	var text_size = 18 if rect.size.y >= 58 else 16
	var width = game.FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	game.text_at(rect.get_center() + Vector2(-width * 0.5, text_size * 0.36), label, text_size, PAPER_LIGHT if primary else INK)
var page = 0
func row_rect(index: int) -> Rect2: return Rect2(24, 166 + index * 54, game.ui_size.x - 48, 46)
func capacity() -> int: return maxi(1, int((game.ui_size.y - 260) / 54))
func footer_rect(i: int) -> Rect2:
	if game.screen == "map":
		if side_layout(): return Rect2(info_rect().position.x + 16, info_rect().end.y - 80, info_rect().size.x - 32, 64)
		return Rect2(24, game.ui_size.y - 78, 142, 60)
	return Rect2(24 + i * 145, game.ui_size.y - 65, 136, 48)
func click(pos: Vector2):
	if travel_target >= 0: return
	if home_rect().has_point(pos): game.show_home();return
	if game.screen == "map":
		if selected_node >= 0:
			if confirm_rect().has_point(pos): confirm();return
			if cancel_rect().has_point(pos): selected_node = -1;return
		elif footer_rect(0).has_point(pos): deck_view = not deck_view;return
		elif center_rect().has_point(pos): focus_current();return
		if not deck_view and map_rect().has_point(pos):
			for id in range(state.nodes.size()):
				if hit_rect(state.nodes[id]).has_point(pos): selected_node = id;return
	else:
		if footer_rect(0).has_point(pos): page = maxi(0, page - 1);return
		if footer_rect(1).has_point(pos): page = mini(maxi(0, (choices.size() - 1) / capacity()), page + 1);return
		for i in capacity():
			if row_rect(i).has_point(pos): resolve(page * capacity() + i);return
func landmark_width() -> float:
	return 102.0 if not game.mobile_layout else (92.0 if game.compact_landscape else 88.0)
func art_rect(node: Dictionary) -> Rect2:
	var width = landmark_width() * (1.2 if node.kind == "boss" else 1.0)
	return Rect2(position(node) - Vector2(width * 0.5, width - 10), Vector2(width, width))
func hit_rect(node: Dictionary) -> Rect2:
	var rect = art_rect(node)
	return Rect2(rect.position - Vector2(6, 3), rect.size + Vector2(12, 36))
func stamp_rect(node: Dictionary) -> Rect2:
	var rect = art_rect(node)
	var side = landmark_width() * 0.50
	return Rect2(Vector2(rect.end.x - side * 0.25, rect.position.y + 3), Vector2(side, side))
func centered_text(point: Vector2, value: String, font_size: int, color: Color):
	var width = game.FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	game.text_at(point - Vector2(width * 0.5, 0), value, font_size, color)
func decoration_clear(rect: Rect2) -> bool:
	# Decoration uses unscrolled content coordinates, never the current viewport.
	var bounds = Rect2(map_rect().position + Vector2(14, 14), Vector2(map_rect().size.x - 28, content_height() - 28))
	if not bounds.encloses(rect): return false
	for node in state.nodes:
		var reserved = hit_rect(node).merge(stamp_rect(node)).grow(24)
		reserved.position.y += scroll_y
		if reserved.intersects(rect): return false
		for next in node.next:
			for step in 41:
				var point = edge_point(content_point(node), content_point(state.nodes[next]), step / 40.0)
				if rect.grow(18).has_point(point): return false
	return true
func decoration_layout() -> Array:
	var key = str(state.get("seed", 0)) + ":" + str(game.ui_size)
	if key == decoration_key: return decoration_cache
	decoration_key = key;decoration_cache = []
	if not active(): return decoration_cache
	var random = RandomNumberGenerator.new();random.seed = int(state.seed) + 1409
	for attempt in 160:
		var size = Vector2(random.randf_range(52, 92), random.randf_range(25, 40))
		var rect = Rect2(map_rect().position + Vector2(random.randf_range(18, map_rect().size.x - size.x - 18), random.randf_range(25, content_height() - size.y - 25)), size)
		if not decoration_clear(rect): continue
		var separate = true
		for existing in decoration_cache:
			if existing.rect.grow(90).intersects(rect): separate = false
		if not separate: continue
		decoration_cache.append({"rect": rect, "kind": ["mountains", "river", "fields"][decoration_cache.size() % 3]})
		if decoration_cache.size() == 5: break
	return decoration_cache
func draw_paper():
	var area = map_rect()
	game.draw_rect(area, PAPER_LIGHT)
	# Restrained neutral fibres, not brown vignette, burnt edges or parchment curls.
	var random = RandomNumberGenerator.new();random.seed = 9631
	for i in 420:
		var p = area.position + Vector2(random.randf() * area.size.x, random.randf() * area.size.y)
		var q = p + Vector2(random.randf_range(1, 5), random.randf_range(-2, 2))
		game.draw_line(p, q, Color(0.35, 0.34, 0.29, 0.045), 0.7, true)
	for item in decoration_layout():
		var r: Rect2 = item.rect
		r.position.y -= scroll_y
		var c = Color(0.20, 0.21, 0.18, 0.11)
		if item.kind == "mountains":
			for offset in [0.0, 0.32, 0.60]:
				game.draw_polyline(PackedVector2Array([r.position + r.size * Vector2(offset, 0.9), r.position + r.size * Vector2(offset + 0.16, 0.1 + offset * 0.3), r.position + r.size * Vector2(offset + 0.36, 0.9)]), c, 1.1, true)
		elif item.kind == "river":
			for row in 3:
				var points = PackedVector2Array()
				for step in 20: points.append(r.position + Vector2(step * r.size.x / 19.0, r.size.y * (0.2 + row * 0.25) + sin(step * 0.42) * 2))
				game.draw_polyline(points, c, 1.0, true)
		else:
			for row in 4: game.draw_line(r.position + Vector2(0, row * r.size.y / 4), r.position + Vector2(r.size.x, row * r.size.y / 4 + 4), c, 1, true)
			for col in 5: game.draw_line(r.position + Vector2(col * r.size.x / 5, 0), r.position + Vector2(col * r.size.x / 5 + 8, r.size.y), c, 1, true)
func draw_route_edge(node: Dictionary, target: Dictionary):
	var traversed = node.id in state.visited and target.id in state.visited
	var available = node.id == state.current and target.id in legal()
	var selected = available and target.id == selected_node
	var color = INK if available or traversed else Color("a5a399")
	var from = position(node);var to = position(target)
	# Roads stop outside the symbols and their permanent labels. No opaque icon backing.
	for step in 80:
		if not traversed and step % 6 >= 4: continue
		var p = edge_point(from, to, step / 80.0)
		var q = edge_point(from, to, (step + 1) / 80.0)
		var hidden = false
		for obstacle in state.nodes:
			if hit_rect(obstacle).grow(3).has_point(p) or hit_rect(obstacle).grow(3).has_point(q): hidden = true;break
			if obstacle.id in state.visited and (stamp_rect(obstacle).grow(5).has_point(p) or stamp_rect(obstacle).grow(5).has_point(q)): hidden = true;break
		if not hidden: game.draw_line(p, q, color, 2.4 if selected else (1.9 if available or traversed else 1.3), true)
	if available:
		var p = edge_point(from, to, 0.52)
		var q = edge_point(from, to, 0.54)
		var direction = (q - p).normalized()
		game.draw_line(p - direction.rotated(0.65) * 7, p, INK, 1.8, true)
		game.draw_line(p - direction.rotated(-0.65) * 7, p, INK, 1.8, true)
func draw_stamp(node: Dictionary):
	var rect = stamp_rect(node)
	var progress = clampf(stamp_elapsed / STAMP_SECONDS, 0, 1) if stamp_node == node.id else 1.0
	var scale = 1.0 + 0.48 * pow(1.0 - progress, 3)
	var color = Color.WHITE;color.a = minf(0.94, progress * 4.0)
	game.draw_set_transform(rect.get_center(), -0.13, Vector2.ONE * scale)
	game.draw_texture_rect(VICTORY_SEAL, Rect2(-rect.size * 0.5, rect.size), false, color)
	game.draw_set_transform(Vector2.ZERO)
func draw_landmark(node: Dictionary):
	var point = position(node)
	var available = node.id in legal()
	var selected = node.id == selected_node
	var rect = art_rect(node)
	if selected:
		var frame = hit_rect(node).grow(3)
		for corner in [frame.position, Vector2(frame.end.x, frame.position.y), frame.end, Vector2(frame.position.x, frame.end.y)]:
			var direction = (frame.get_center() - corner).sign()
			game.draw_line(corner, corner + Vector2(direction.x * 13, 0), INK, 1.8, true)
			game.draw_line(corner, corner + Vector2(0, direction.y * 13), INK, 1.8, true)
	game.draw_texture_rect(SYMBOLS[node.kind], rect, false)
	var label = {"battle":"战斗", "elite":"精英", "camp":"休整", "workshop":"工坊", "event":"奇遇", "outpost":"关隘", "boss":"决战"}[node.kind]
	centered_text(point + Vector2(0, 31), label, 19, INK)
	if available:
		game.draw_line(point + Vector2(-22, 36), point + Vector2(22, 36), INK, 1.2, true)
		game.draw_circle(point + Vector2(-30, 25), 2.5, INK)
	if node.id in state.visited: draw_stamp(node)
func draw_piece():
	var piece: Vector2
	if travel_target >= 0:
		piece = march_point(clampf(travel_elapsed / TRAVEL_SECONDS, 0, 1)) - Vector2(0, 15)
	else:
		var rect = art_rect(state.nodes[maxi(0, state.current)])
		piece = Vector2(rect.position.x - 18, rect.get_center().y + 8)
	# A flat vermilion commander mark, not a wooden chess-piece sticker.
	game.draw_circle(piece, 21, PAPER_LIGHT)
	game.draw_arc(piece, 21, 0, TAU, 48, RED, 2.5, true)
	centered_text(piece + Vector2(0, 9), "帅", 27, RED)
func draw_map():
	var area = map_rect()
	draw_paper()
	for node in state.nodes:
		for next in node.next: draw_route_edge(node, state.nodes[next])
	for id in range(state.nodes.size() - 1, -1, -1): draw_landmark(state.nodes[id])
	draw_piece()
	# Fixed opaque masks provide a strict visual viewport for the immediate-mode canvas.
	game.draw_rect(Rect2(0, 0, game.ui_size.x, area.position.y), PAPER)
	game.draw_rect(Rect2(0, area.end.y, game.ui_size.x, game.ui_size.y - area.end.y), PAPER)
	game.draw_rect(Rect2(0, area.position.y, area.position.x, area.size.y), PAPER)
	game.draw_rect(Rect2(area.end.x, area.position.y, game.ui_size.x - area.end.x, area.size.y), PAPER)
	game.draw_rect(area, Color("c4c1b5"), false, 1)
	if scroll_limit() > 0:
		var track = Rect2(area.end.x - 6, area.position.y + 8, 3, area.size.y - 16)
		game.draw_rect(track, Color(0.27, 0.25, 0.20, 0.12))
		var thumb_h = maxf(24, track.size.y * area.size.y / content_height())
		game.draw_rect(Rect2(track.position + Vector2(0, (track.size.y - thumb_h) * scroll_y / scroll_limit()), Vector2(3, thumb_h)), MUTED)
func draw_header():
	button(home_rect(), "‹ 首页")
	var title_x = 146.0 if game.compact_landscape else 150.0
	game.text_at(Vector2(title_x, 47), "弈 行", 33, INK)
	var subtitle = "第一章 · 朱印行军"
	if game.compact_landscape:
		game.text_at(Vector2(265, 45), subtitle, 21, INK)
		game.text_at(Vector2(16, 78), "已行 %d / 8  ·  %s  ·  拖动军图查看前路" % [state.visited.size(), "敌将2命" if state.weakened else "敌将3命"], 16, MUTED)
	else:
		game.text_at(Vector2(26, 92), subtitle, 23, INK)
		game.text_at(Vector2(game.ui_size.x - (370 if not game.mobile_layout else 192), 91), "已行 %d / 8  ·  %s" % [state.visited.size(), "敌将2命" if state.weakened else "敌将3命"], 16, MUTED)
	if not game.mobile_layout:
		game.text_at(Vector2(290, 45), "一子入山河，百战成归途", 18, MUTED)
		game.text_at(Vector2(1050, 45), game.BUILD_VERSION + " · 朱印军符", 16, MUTED)
func draw_info():
	var info = info_rect()
	game.panel(info, PAPER_LIGHT, Color("c4c1b5"))
	var x = info.position.x + 16
	var y = info.position.y + 29
	var width = info.size.x - 32
	if selected_node >= 0:
		var node = state.nodes[selected_node]
		var reachable = selected_node in legal()
		var status = "可出发" if reachable else ("已行经" if selected_node in state.visited else "当前不可达")
		game.text_at(Vector2(x, y), TITLES[node.kind] + " · " + status, 20, INK)
		game.wrapped_text(DETAILS[node.kind], Rect2(x, y + 8, width, 48), 16, MUTED)
		if side_layout():
			game.wrapped_text("选择只作查看。确认后，棋子沿真实道路行进；抵达才会进入节点。" if reachable else "只能沿当前地标相连的深墨箭头前进，不能跳关或回头。", Rect2(x, y + 86, width, 90), 17, MUTED)
			if info.size.y > 600:
				var side = minf(width - 50, 210)
				game.draw_texture_rect(SYMBOLS[node.kind], Rect2(Vector2(x + (width - side) * 0.5, y + 195), Vector2.ONE * side), false)
		button(cancel_rect(), "取消选择")
		if reachable: button(confirm_rect(), "确认出发  ↑", true)
	elif travel_target >= 0:
		game.text_at(Vector2(x, y), "沿途行军中…", 22, INK)
		game.wrapped_text("正在前往「%s」，抵达后进入。" % TITLES[state.nodes[travel_target].kind], Rect2(x, y + 13, width, 56), 16, MUTED)
		var progress = clampf(travel_elapsed / TRAVEL_SECONDS, 0, 1)
		game.draw_rect(Rect2(x, info.end.y - 30, width, 4), Color("cbbb9c"))
		game.draw_rect(Rect2(x, info.end.y - 30, width * progress, 4), RED)
	else:
		game.text_at(Vector2(x, y), "山河在前，择路而行", 22, INK)
		game.text_at(Vector2(x, y + 29), "先选地标查看，再确认出发", 16, MUTED)
		if side_layout():
			game.wrapped_text("我方执红，黑印标记前路。通关盖下将军朱印，分路决定牌组。", Rect2(x, y + 65, width, 84), 18, MUTED)
			game.text_at(Vector2(x, y + 180), "墨线箭头 · 当前可达", 18, INK)
			game.text_at(Vector2(x, y + 215), "将军朱印 · 已经走过", 18, RED)
			game.text_at(Vector2(x, y + 250), "黑色军符 · 节点类别", 18, INK)
			if info.size.y > 600:
				game.wrapped_text("滚轮或拖动查看军图；点击「回到当前」定位棋子。", Rect2(x, y + 320, width, 80), 17, MUTED)
		button(footer_rect(0), "收起牌组" if deck_view else "查看牌组")
		button(center_rect(), "回到当前")
func draw_deck():
	var area = map_rect().grow(-12)
	game.panel(area, PAPER_LIGHT, Color("a08a66"))
	var counts = {}
	for id in game.collection: counts[id] = counts.get(id, 0) + 1
	game.text_at(area.position + Vector2(16, 32), "永久牌组", 24, INK)
	game.text_at(area.position + Vector2(16, 60), "消耗牌每战恢复", 16, MUTED)
	var text = ""
	for id in counts: text += "%s × %d   " % [game.CARDS[id][0], counts[id]]
	game.wrapped_text(text, Rect2(area.position + Vector2(16, 88), area.size - Vector2(32, 108)), 18, INK)
func draw():
	game.draw_rect(Rect2(Vector2.ZERO, game.ui_size), PAPER)
	if game.screen == "route_choice":
		draw_header()
		var kind = state.nodes[state.pending].kind
		game.text_at(Vector2(24, 148), {"camp": "营地 · 升级或整备，只可选一次", "workshop": "工坊 · 永久删一张牌，或离开", "outpost": "关隘据点 · 破寨可削弱敌将防御", "event": "渡口偶遇 · 结果确定，二选一"}.get(kind, "选择"), 16, INK)
		for i in capacity():
			var index = page * capacity() + i
			if index < choices.size(): button(row_rect(i), choices[index].label)
		button(footer_rect(0), "上一页")
		button(footer_rect(1), "下一页 %d" % (page + 1))
		return
	draw_map();draw_header();draw_info()
	if deck_view: draw_deck()
	if save_error != OK: game.text_at(Vector2(24, game.ui_size.y - 2), "本地存档失败，请勿关闭页面", 14, RED)
