extends RefCounted
# Chapter state lives outside battle undo snapshots. Forward-only edges and stored
# rewards make navigation deterministic, independently of combat RNG.
const SAVE = "user://route_run.cfg"
const LABELS = {"battle": "战", "elite": "精", "camp": "营", "workshop": "坊", "event": "事", "outpost": "寨", "boss": "帅"}
var game
var state: Dictionary = {}
var choices: Array = []
var deck_view = false
var save_error = OK
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
			var dedicated: Array = game.PROFILES.DATA[game.player_skill].rewards.duplicate()
			var common: Array = game.PROFILES.COMMON.duplicate()
			var loot = []
			for i in 2: loot.append(dedicated.pop_at(random.randi_range(0, dedicated.size() - 1)))
			loot.append(common[random.randi_range(0, common.size() - 1)])
			state.nodes.append({"id": state.nodes.size(), "row": row, "lane": rows[row][col], "kind": types[row][col], "next": [], "loot": loot, "layout": clampi(row + random.randi_range(0, 1), 1, 5)})
	for node in state.nodes:
		for target in state.nodes:
			if target.row == node.row + 1 and (abs(target.lane - node.lane) <= 1 or rows[node.row].size() == 1 or rows[target.row].size() == 1): node.next.append(target.id)
	choices = [];deck_view = false
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
	game.selected = -1;game.free_selected = false;game.handui.reset();game.reinforcement_pending = 0
	game.phase = "play";game.screen = "map";choices = [];page = 0
	save()
func save():
	if not active(): return
	var config = ConfigFile.new()
	config.set_value("run", "version", 1)
	config.set_value("run", "route", state)
	config.set_value("run", "battle", game.history.capture())
	config.set_value("run", "screen", game.screen if game.screen in ["game", "map", "route_choice"] else "map")
	save_error = config.save(SAVE)
func resume() -> bool:
	var config = ConfigFile.new()
	if config.load(SAVE) != OK or config.get_value("run", "version", 0) != 1: return false
	var saved = config.get_value("run", "route", {})
	if saved.is_empty() or saved.get("done", false): return false
	game.tutorial.stop();game.history.clear();game.cancel_gesture();game.clear_effects()
	state = saved
	var battle = config.get_value("run", "battle")
	for key in game.HISTORY.FIELDS: game.set(key, battle[key])
	game.rng.state = battle.rng_state
	game.screen = config.get_value("run", "screen", "map")
	game.input_lock = 0;game.navigation_lock = 0;game.selected = -1;game.free_selected = false
	game.rewardui.reset();game.handui.reset();page = 0;deck_view = false
	choices = options() if game.screen == "route_choice" else []
	return true
func position(node: Dictionary) -> Vector2:
	if game.compact_landscape: return Vector2(80 + node.row * 112, 215 + node.lane * 70)
	var width = minf(game.ui_size.x - 100, 700)
	return Vector2(game.ui_size.x * 0.5 + (node.lane - 1) * width * 0.43, 155 + (7 - node.row) * (game.ui_size.y - 285) / 7)
func button(rect: Rect2, label: String):
	game.panel(rect, game.THEME.BUTTON, game.THEME.BORDER)
	game.text_at(rect.position + Vector2(12, 28), label, 16)
var page = 0
func row_rect(index: int) -> Rect2: return Rect2(24, 166 + index * 54, game.ui_size.x - 48, 46)
func capacity() -> int: return maxi(1, int((game.ui_size.y - 260) / 54))
func footer_rect(i: int) -> Rect2: return Rect2(24 + i * 145, game.ui_size.y - 65, 136, 42)
func click(pos: Vector2):
	if game.home_rect().has_point(pos): game.show_home();return
	if game.screen == "map":
		if footer_rect(0).has_point(pos): deck_view = not deck_view;return
		if not deck_view:
			for id in legal():
				if position(state.nodes[id]).distance_to(pos) <= 25: enter(id);return
	else:
		if footer_rect(0).has_point(pos): page = maxi(0, page - 1);return
		if footer_rect(1).has_point(pos): page = mini(maxi(0, (choices.size() - 1) / capacity()), page + 1);return
		for i in capacity():
			if row_rect(i).has_point(pos): resolve(page * capacity() + i);return
func draw():
	game.draw_rect(Rect2(Vector2.ZERO, game.ui_size), game.THEME.BACKGROUND)
	button(game.home_rect(), "首页")
	game.text_at(Vector2(24, 92), "山河棋路 · 第一章", 28, game.THEME.HEADING)
	game.text_at(Vector2(24, 120), "种子 %d · 已行 %d / 8 · %s" % [state.seed, state.visited.size(), "敌将2命" if state.weakened else "敌将3命"], 16, game.THEME.LIGHT)
	if game.screen == "route_choice":
		var kind = state.nodes[state.pending].kind
		game.text_at(Vector2(24, 148), {"camp": "营地 · 升级或整备，只可选一次", "workshop": "工坊 · 永久删一张牌，或离开", "outpost": "关隘据点 · 破寨可削弱敌将防御", "event": "渡口偶遇 · 结果确定，二选一"}.get(kind, "选择"), 16, game.THEME.LIGHT)
		for i in capacity():
			var index = page * capacity() + i
			if index < choices.size(): button(row_rect(i), choices[index].label)
		button(footer_rect(0), "上一页")
		button(footer_rect(1), "下一页 %d" % (page + 1))
		return
	game.panel(Rect2(18, 133, game.ui_size.x - 36, game.ui_size.y - 225), game.THEME.PAPER, game.THEME.BORDER)
	var river_y = position(state.nodes[6]).y + 24
	game.draw_line(Vector2(30, river_y), Vector2(game.ui_size.x - 30, river_y), Color("9bbdb4"), 8)
	for node in state.nodes:
		for next in node.next:
			var traversed = node.id in state.visited and next in state.visited
			var available = node.id == state.current and next in legal()
			game.draw_line(position(node), position(state.nodes[next]), game.THEME.SAFE if traversed else (game.THEME.INK if available else Color("b9aa94")), 4 if traversed or available else 2)
	for node in state.nodes:
		var point = position(node)
		var available = node.id in legal()
		game.draw_circle(point, 23, game.THEME.PAPER_SELECTED if available else game.THEME.PAPER)
		game.draw_arc(point, 23, 0, TAU, 32, game.THEME.SAFE if node.id in state.visited else (game.THEME.INK if available else game.THEME.BORDER), 3)
		game.text_at(point + Vector2(-10, 8), LABELS[node.kind], 21, game.THEME.INK if available else game.THEME.GRID)
	button(footer_rect(0), "收起牌组" if deck_view else "查看牌组")
	game.text_at(Vector2(172, game.ui_size.y - 38), "深可走 · 绿已走 · 淡不可走", 14, game.THEME.LIGHT)
	game.text_at(Vector2(24, game.ui_size.y - 80), "战/精战斗 · 营升级 · 坊删牌 · 事事件 · 寨减防", 14, game.THEME.LIGHT)
	if deck_view:
		game.panel(Rect2(24, 145, game.ui_size.x - 48, game.ui_size.y - 245), game.THEME.PAPER)
		var counts = {}
		for id in game.collection: counts[id] = counts.get(id, 0) + 1
		var lines = "永久牌组（消耗每战恢复）\n"
		for id in counts: lines += "%s × %d  " % [game.CARDS[id][0], counts[id]]
		game.wrapped_text(lines, Rect2(40, 160, game.ui_size.x - 80, game.ui_size.y - 285), 18)
	if save_error != OK: game.text_at(Vector2(24, game.ui_size.y - 8), "本地存档失败，请勿关闭页面", 14, game.THEME.HEADING)
