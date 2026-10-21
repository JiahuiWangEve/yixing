extends RefCounted
# Chapter state lives outside battle undo snapshots. Forward-only edges and stored
# rewards make navigation deterministic, independently of combat RNG.
const LANDSCAPE = preload("res://assets/map/ink_landscape.png")
const LANDMARKS = preload("res://assets/map/military_landmarks.png")
const PAPER = Color("e8d6b6")
const PAPER_LIGHT = Color("f2e6cf")
const INK = Color("3d4037")
const MUTED = Color("716c58")
const RED = Color("9d4736")
const HISTORY = Color("3f665e")
# Pixel-exact regions of the supplied transparent two-row atlas. No redraws.
const ART_REGIONS = [Rect2(0, 48, 444, 465), Rect2(444, 48, 446, 465), Rect2(890, 80, 443, 433), Rect2(1333, 48, 441, 465), Rect2(0, 522, 444, 365), Rect2(444, 522, 446, 365), Rect2(890, 522, 443, 365), Rect2(1333, 522, 441, 365)]
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
	var ys = [0.94, 0.82, 0.79, 0.83, 0.69, 0.66, 0.56, 0.45, 0.43, 0.46, 0.33, 0.31, 0.20, 0.18, 0.21, 0.075]
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
	game.panel(rect, RED if primary else PAPER_LIGHT, RED if primary else Color("a08a66"))
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
func atlas_index(node: Dictionary) -> int:
	match node.kind:
		"elite": return 1
		"camp": return 2
		"workshop": return 3
		"event": return 4 if node.id == 1 else 7
		"outpost": return 5
		"boss": return 6
	return 0
func landmark_width() -> float:
	return 138.0 if not game.mobile_layout else (118.0 if game.compact_landscape else 108.0)
func art_rect(node: Dictionary) -> Rect2:
	var region = ART_REGIONS[atlas_index(node)]
	var width = landmark_width() * (1.18 if node.kind == "boss" else 1.0)
	var height = width * region.size.y / region.size.x
	return Rect2(position(node) - Vector2(width * 0.5, height - 10), Vector2(width, height))
func hit_rect(node: Dictionary) -> Rect2:
	var rect = art_rect(node)
	return Rect2(rect.position - Vector2(4, 2), rect.size + Vector2(8, 35))
func centered_text(point: Vector2, value: String, font_size: int, color: Color):
	var width = game.FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	game.text_at(point - Vector2(width * 0.5, 0), value, font_size, color)
func draw_route_edge(node: Dictionary, target: Dictionary):
	var traversed = node.id in state.visited and target.id in state.visited
	var available = node.id == state.current and target.id in legal()
	var selected = available and target.id == selected_node
	var points = PackedVector2Array()
	for step in 49: points.append(edge_point(position(node), position(target), step / 48.0))
	# Every visible road is a real directed edge; states share exactly this geometry.
	game.draw_polyline(points, Color("e4cda4"), 8 if selected else 6, true)
	game.draw_polyline(points, RED if available else (HISTORY if traversed else Color("b09b7d")), 3.0 if available or traversed else 1.6, true)
	if available:
		for t in [0.35, 0.64]:
			var p = edge_point(position(node), position(target), t)
			var q = edge_point(position(node), position(target), t + 0.025)
			var direction = (q - p).normalized()
			game.draw_line(p - direction.rotated(0.65) * 7, p, RED, 2, true)
			game.draw_line(p - direction.rotated(-0.65) * 7, p, RED, 2, true)
func draw_landmark(node: Dictionary):
	var point = position(node)
	var available = node.id in legal()
	var visited = node.id in state.visited
	var selected = node.id == selected_node
	var color = RED if available else (HISTORY if visited else MUTED)
	if selected:
		game.draw_circle(point + Vector2(0, -5), landmark_width() * 0.48, Color(0.98, 0.87, 0.65, 0.45))
		game.draw_arc(point + Vector2(0, -5), landmark_width() * 0.48, 0.12, PI - 0.12, 40, RED, 2, true)
	game.draw_texture_rect_region(LANDMARKS, art_rect(node), ART_REGIONS[atlas_index(node)], Color.WHITE if available or visited or selected else Color(0.84, 0.84, 0.78, 0.88))
	var label = {"battle":"军阵", "elite":"精锐", "camp":"营地", "workshop":"工坊", "event":"渡口" if node.id == 1 else "石桥", "outpost":"关隘", "boss":"终点城寨"}[node.kind]
	var label_width = 86.0 if node.kind == "boss" else 64.0
	game.panel(Rect2(point + Vector2(-label_width * 0.5, 13), Vector2(label_width, 25)), Color(0.95, 0.89, 0.76, 0.94), color if available or selected else Color.TRANSPARENT)
	centered_text(point + Vector2(0, 32), label, 17, color)
	if available or visited:
		var badge = point + Vector2(label_width * 0.5 + 7, 25)
		game.draw_circle(badge, 9, color)
		centered_text(badge + Vector2(0, 4), "✓" if visited else "·", 13, PAPER_LIGHT)
func draw_piece():
	var piece = march_point(clampf(travel_elapsed / TRAVEL_SECONDS, 0, 1)) if travel_target >= 0 else position(state.nodes[maxi(0, state.current)])
	# Lift the token slightly; its ground anchor follows the road's cubic exactly.
	piece += Vector2(0, -22)
	game.draw_circle(piece + Vector2(2, 6), 22, Color(0.18, 0.15, 0.1, 0.24))
	game.draw_circle(piece, 23, Color("ad7850"))
	game.draw_circle(piece - Vector2(0, 3), 22, PAPER_LIGHT)
	game.draw_arc(piece - Vector2(0, 3), 18, 0, TAU, 48, RED, 1.7, true)
	centered_text(piece + Vector2(0, 5), {"king":"帅", "horse":"马", "artillery":"炮"}.get(game.player_skill, "帅"), 25, RED)
func draw_map():
	var area = map_rect()
	game.draw_texture_rect(LANDSCAPE, Rect2(area.position - Vector2(0, scroll_y), Vector2(area.size.x, content_height())), false)
	for node in state.nodes:
		for next in node.next: draw_route_edge(node, state.nodes[next])
	# Back-to-front order lets nearer landmarks sit naturally over the path.
	for id in range(state.nodes.size() - 1, -1, -1): draw_landmark(state.nodes[id])
	draw_piece()
	# Fixed opaque masks provide a strict visual viewport for the immediate-mode canvas.
	game.draw_rect(Rect2(0, 0, game.ui_size.x, area.position.y), PAPER)
	game.draw_rect(Rect2(0, area.end.y, game.ui_size.x, game.ui_size.y - area.end.y), PAPER)
	game.draw_rect(Rect2(0, area.position.y, area.position.x, area.size.y), PAPER)
	game.draw_rect(Rect2(area.end.x, area.position.y, game.ui_size.x - area.end.x, area.size.y), PAPER)
	game.draw_rect(area, Color("937b58"), false, 2)
	game.draw_rect(area.grow(-5), Color(0.42, 0.35, 0.23, 0.30), false, 1)
	if scroll_limit() > 0:
		var track = Rect2(area.end.x - 6, area.position.y + 8, 3, area.size.y - 16)
		game.draw_rect(track, Color(0.27, 0.25, 0.20, 0.16))
		var thumb_h = maxf(24, track.size.y * area.size.y / content_height())
		game.draw_rect(Rect2(track.position + Vector2(0, (track.size.y - thumb_h) * scroll_y / scroll_limit()), Vector2(3, thumb_h)), Color("9d7850"))
func draw_header():
	button(home_rect(), "‹ 首页")
	var title_x = 146.0 if game.compact_landscape else 150.0
	game.text_at(Vector2(title_x, 47), "弈 行", 33, INK)
	var subtitle = "第一章 · 山河棋路"
	if game.compact_landscape:
		game.text_at(Vector2(265, 45), subtitle, 21, INK)
		game.text_at(Vector2(16, 78), "已行 %d / 8  ·  %s  ·  拖动山河查看前路" % [state.visited.size(), "敌将2命" if state.weakened else "敌将3命"], 16, MUTED)
	else:
		game.text_at(Vector2(26, 92), subtitle, 23, INK)
		game.text_at(Vector2(game.ui_size.x - (370 if not game.mobile_layout else 192), 91), "已行 %d / 8  ·  %s" % [state.visited.size(), "敌将2命" if state.weakened else "敌将3命"], 16, MUTED)
	if not game.mobile_layout:
		game.text_at(Vector2(290, 45), "一子入山河，百战成归途", 18, MUTED)
		game.text_at(Vector2(1050, 45), game.BUILD_VERSION + " · 手绘山河", 16, MUTED)
func draw_info():
	var info = info_rect()
	game.panel(info, PAPER_LIGHT, Color("baa17c"))
	var x = info.position.x + 16
	var y = info.position.y + 29
	var width = info.size.x - 32
	if selected_node >= 0:
		var node = state.nodes[selected_node]
		var reachable = selected_node in legal()
		var status = "可出发" if reachable else ("已行经" if selected_node in state.visited else "当前不可达")
		game.text_at(Vector2(x, y), TITLES[node.kind] + " · " + status, 20, RED if reachable else INK)
		game.wrapped_text(DETAILS[node.kind], Rect2(x, y + 8, width, 48), 16, MUTED)
		if side_layout():
			game.wrapped_text("选择只作查看。确认后，棋子沿真实道路行进；抵达才会进入节点。" if reachable else "只能沿当前地标相连的朱红道路前进，不能跳关或回头。", Rect2(x, y + 86, width, 90), 17, MUTED)
			if info.size.y > 600:
				var region = ART_REGIONS[atlas_index(node)]
				var art_size = Vector2(width - 30, (width - 30) * region.size.y / region.size.x)
				game.draw_texture_rect_region(LANDMARKS, Rect2(Vector2(x + 15, y + 195), art_size), region)
		button(cancel_rect(), "取消选择")
		if reachable: button(confirm_rect(), "确认出发  ↑", true)
	elif travel_target >= 0:
		game.text_at(Vector2(x, y), "沿途行军中…", 22, RED)
		game.wrapped_text("正在前往「%s」，抵达后进入。" % TITLES[state.nodes[travel_target].kind], Rect2(x, y + 13, width, 56), 16, MUTED)
		var progress = clampf(travel_elapsed / TRAVEL_SECONDS, 0, 1)
		game.draw_rect(Rect2(x, info.end.y - 30, width, 4), Color("cbbb9c"))
		game.draw_rect(Rect2(x, info.end.y - 30, width * progress, 4), RED)
	else:
		game.text_at(Vector2(x, y), "山河在前，择路而行", 22, INK)
		game.text_at(Vector2(x, y + 29), "先选地标查看，再确认出发", 16, MUTED)
		if side_layout():
			game.wrapped_text("从田野渡河，循山路攻入终点城寨。每次分路，都会改变这一局的牌组。", Rect2(x, y + 65, width, 84), 18, MUTED)
			game.text_at(Vector2(x, y + 180), "朱红 · 当前可达", 18, RED)
			game.text_at(Vector2(x, y + 215), "青墨 · 已经走过", 18, HISTORY)
			game.text_at(Vector2(x, y + 250), "淡墨 · 尚未行经", 18, MUTED)
			if info.size.y > 600:
				game.wrapped_text("滚轮 / 拖动查看山河
点击「回到当前」定位棋子", Rect2(x, y + 320, width, 80), 17, MUTED)
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
