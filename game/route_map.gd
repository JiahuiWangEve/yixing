extends RefCounted
const Palette = preload("res://palette.gd")
# Chapter state lives outside battle undo snapshots. Forward-only edges and stored
# rewards make navigation deterministic, independently of combat RNG.
# Flat, transparent woodcut symbols: the paper remains visible through the ink gaps.
const SYMBOLS = {
	"battle": preload("res://assets/map/seals/battle.svg"),
	"elite": preload("res://assets/map/seals/outpost.svg"),
	"camp": preload("res://assets/map/seals/camp.svg"),
	"workshop": preload("res://assets/map/seals/workshop.svg"),
	"event": preload("res://assets/map/seals/event.svg"),
	"boss": preload("res://assets/map/seals/boss.svg")
}
const VICTORY_SEAL = preload("res://assets/map/seals/victory_seal.svg")
const PAPER = Color("f3efe5")
const PAPER_LIGHT = Color("fcf9f1")
const INK = Color("292723")
const MUTED = Color("625e55")
const RED = Color("a6382d")
const STAMP_SECONDS = 0.42
var stamp_node = -1
var stamp_elapsed = STAMP_SECONDS
var decoration_cache: Array = []
var decoration_key = ""
# Geometry is in content coordinates: dragging only translates cached ink.
var road_cache: Dictionary = {}
var road_cache_key = 0
var road_cache_builds = 0
var scenery_obstacles: Array[Rect2] = []
var scenery_roads = PackedVector2Array()
var road_segment_tests = 0
var paper_lines = PackedVector2Array()
var paper_size = Vector2.ZERO
var redraw_key = 0
func needs_redraw() -> bool:
	var key = [game.screen, game.ui_size, game.mobile_layout, game.compact_landscape, save_error, state.hash(), choices.hash(), game.collection.hash(), selected_node, travel_target, stamp_node, travel_elapsed if travel_target >= 0 else 0.0, stamp_elapsed if stamp_node >= 0 and stamp_elapsed < STAMP_SECONDS else STAMP_SECONDS, scroll_y, deck_view, page].hash()
	if key == redraw_key: return false
	redraw_key = key
	return true
func ensure_road_cache():
	var key = [game.ui_size, game.mobile_layout, game.compact_landscape, state.get("seed", 0), state.get("nodes", []).hash(), state.get("visited", []).hash()].hash()
	if key == road_cache_key: return
	road_cache_key = key;road_cache.clear();road_cache_builds += 1
	scenery_obstacles.clear();scenery_roads.clear()
	if not active(): return
	var obstacles: Array[Rect2] = []
	for node in state.nodes:
		var reserved = hit_rect(node).merge(stamp_rect(node)).grow(24);reserved.position.y += scroll_y
		scenery_obstacles.append(reserved)
		var hit = hit_rect(node).grow(3);hit.position.y += scroll_y
		obstacles.append(hit)
		if node.id in state.visited:
			var stamp = stamp_rect(node).grow(5);stamp.position.y += scroll_y
			obstacles.append(stamp)
	for node in state.nodes:
		for next in node.next:
			var target = state.nodes[next]
			var from = content_point(node);var to = content_point(target)
			for step in 41: scenery_roads.append(edge_point(from, to, step / 40.0))
			var solid = PackedVector2Array();var dashed = PackedVector2Array()
			for step in 80:
				var p = edge_point(from, to, step / 80.0)
				var q = edge_point(from, to, (step + 1) / 80.0)
				var hidden = false
				for obstacle in obstacles:
					road_segment_tests += 1
					if obstacle.has_point(p) or obstacle.has_point(q): hidden = true;break
				if not hidden:
					solid.append(p);solid.append(q)
					if step % 6 < 4: dashed.append(p);dashed.append(q)
			road_cache[Vector2i(node.id, next)] = {"solid": solid, "dashed": dashed, "from": from, "to": to, "bounds": Rect2(from, Vector2.ZERO).expand(to).grow(8)}
const GENERATOR = preload("res://route_generator.gd")
const SAVE = "user://route_run_v0149.cfg"
const WEB_SAVE_KEY = "yixing.route_run.v0149"
const LAST_CHAPTER = 2
const CHAPTER_SEED_SALT = 0x5bd1e995
const UPGRADES = preload("res://card_upgrades.gd")
const EVENT_IDS = ["herbalist", "merchant", "manual"]
const EVENT_TITLES = {"herbalist": "药庐", "merchant": "行商", "manual": "兵书"}
var choice_mode = "root"
var pending_choice: Dictionary = {}
var merchant_offer = -1
var merchant_ui
const LABELS = {"battle": "战", "elite": "关", "camp": "营", "workshop": "坊", "event": "事", "boss": "帅"}
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
var pointer_node = -1
# A second finger cancels the entire sequence, not only that finger.
var touch_contacts: Dictionary = {}
var touch_sequence_blocked = false
var layout_size = Vector2.ZERO
var layout_content_height = 0.0
var layout_view_height = 0.0
const TITLES = {"battle": "军旗阵地", "elite": "关隘", "camp": "休整", "workshop": "工坊", "event": "奇遇", "boss": "终点城寨"}
const DETAILS = {"battle": "战胜守军后选择战利品。", "elite": "精英战斗；战胜后4张候选选1。", "camp": "轻装上阵：删一张牌；休养：回1命；养精蓄锐：随机获得一张牌。", "workshop": "强化一张可强化的永久牌，或删除一张永久牌。", "event": "药庐、行商、兵书各有三分之一概率，生成后固定。", "boss": "敌将9血；击败敌将即完成本章。"}

func reset_view():
	selected_node = -1;travel_target = -1;travel_elapsed = 0.0
	stamp_node = -1;stamp_elapsed = STAMP_SECONDS
	cancel_pointer();focus_needed = true
func side_layout() -> bool: return not game.mobile_layout or game.compact_landscape
func map_rect() -> Rect2:
	var width = minf(game.ui_size.x - 28, 1000)
	var top = 90.0 if game.compact_landscape else 112.0
	return Rect2((game.ui_size.x - width) * 0.5, top, width, game.ui_size.y - top - 14)
func content_height() -> float:
	# Nine layers retain legible seals and room for the selected-node cue.
	if not game.mobile_layout: return 1520.0
	if game.compact_landscape: return 1440.0
	return maxf(1440.0, map_rect().size.y * 2.4)
func scroll_limit() -> float: return maxf(0, content_height() - map_rect().size.y)
func content_point(node: Dictionary) -> Vector2:
	# Generated coordinates are saved. Resizing only projects them onto the paper.
	var margin = 28.0 if game.mobile_layout else 42.0
	return Vector2(map_rect().position.x + margin + float(node.x) * (map_rect().size.x - margin * 2), map_rect().position.y + 160 + float(node.y) * (content_height() - 220))
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
func confirm():
	if game.screen != "map" or travel_target >= 0 or selected_node not in legal(): return
	var target = selected_node
	cancel_pointer()
	travel_target = target;travel_elapsed = 0.0
func tick(delta: float):
	if game.screen != "map": return
	stamp_elapsed = minf(STAMP_SECONDS, stamp_elapsed + delta)
	if layout_size != game.ui_size:
		if not focus_needed and layout_content_height > 0:
			var center_fraction = (scroll_y + layout_view_height * 0.5) / layout_content_height
			scroll_y = clampf(center_fraction * content_height() - map_rect().size.y * 0.5, 0, scroll_limit())
		layout_size = game.ui_size;layout_content_height = content_height();layout_view_height = map_rect().size.y;cancel_pointer()
	if focus_needed: focus_current()
	if travel_target >= 0:
		travel_elapsed += delta
		if travel_elapsed >= TRAVEL_SECONDS:
			var target = travel_target
			travel_target = -1
			enter(target)
func cancel_pointer(keep_frame: bool = false, keep_touches: bool = false):
	if merchant_ui != null: merchant_ui.cancel_pointer()
	pointer_id = -2;pointer_dragged = false;pointer_scroll = false;pointer_node = -1
	if not keep_touches:
		touch_contacts.clear();touch_sequence_blocked = false
	if not keep_frame:
		selected_node = -1
		if game.information != null: game.information.clear()
func finish_inspection(id: int, keep_frame: bool = false):
	# A consumed map hold bypasses main.cancel_gesture(), which would erase the
	# intentionally sticky information. Its release can never become a click.
	touch_contacts.erase(id)
	cancel_pointer(keep_frame, true)
	if touch_contacts.is_empty(): touch_sequence_blocked = false
func node_at(pos: Vector2) -> int:
	if game.screen != "map" or not active() or deck_view or travel_target >= 0 or not map_rect().has_point(pos): return -1
	if game.card_picker.active or game.presentation.active() or game.encounter_info_open: return -1
	for node in state.nodes:
		if hit_rect(node).has_point(pos): return node.id
	return -1
func pointer_press(pos: Vector2, id: int):
	if travel_target >= 0: return
	if pointer_id != -2:
		if pointer_id != id: cancel_pointer()
		return
	pointer_id = id;pointer_start = pos;pointer_last = pos;pointer_dragged = false
	pointer_scroll = game.screen == "map" and not deck_view and map_rect().has_point(pos)
	pointer_node = node_at(pos)
	if game.screen == "map": selected_node = pointer_node
func pointer_motion(pos: Vector2, id: int):
	if pointer_id != id: return
	if pos.distance_to(pointer_start) >= 12: pointer_dragged = true
	# Even a small exit across a hit-rect edge invalidates the original press.
	if pointer_node >= 0 and node_at(pos) != pointer_node: pointer_dragged = true
	if pointer_dragged:
		selected_node = -1
		if game.information != null: game.information.dismiss_map_drag()
	if pointer_scroll and pointer_dragged: scroll_y = clampf(scroll_y - (pos.y - pointer_last.y), 0, scroll_limit())
	pointer_last = pos
func pointer_release(pos: Vector2, id: int, canceled: bool = false):
	if pointer_id != id: return
	var tap = not canceled and not pointer_dragged and pos.distance_to(pointer_start) < 12
	if game.screen == "map" and pointer_node != node_at(pos): tap = false
	pointer_id = -2;pointer_scroll = false;pointer_node = -1
	if tap: click(pos)
	else: cancel_pointer()
func input_event(event) -> bool:
	if merchant_ui.input_event(event): return true
	if game.screen not in ["map", "route_choice"]: return false
	if event is InputEventScreenTouch:
		game.touch_seen = true
		if event.pressed:
			touch_contacts[event.index] = true
			if touch_sequence_blocked or touch_contacts.size() > 1:
				cancel_pointer(false, true);touch_sequence_blocked = true
			else: pointer_press(event.position, event.index)
		else:
			touch_contacts.erase(event.index)
			if touch_sequence_blocked:
				if touch_contacts.is_empty(): touch_sequence_blocked = false
			else: pointer_release(event.position, event.index, event.canceled)
		return true
	if event is InputEventScreenDrag:
		if not touch_sequence_blocked: pointer_motion(event.position, event.index)
		return true
	if event is InputEventMouse:
		if (event.device == -1 and game.touch_seen) or not touch_contacts.is_empty(): return true
		if event is InputEventMouseMotion:
			if pointer_id == -1: pointer_motion(event.position, -1)
			elif event.button_mask == 0: selected_node = node_at(event.position)
		elif event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed: pointer_press(event.position, -1)
				else: pointer_release(event.position, -1)
			elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and travel_target < 0 and map_rect().has_point(event.position) and not deck_view:
				cancel_pointer()
				scroll_y = clampf(scroll_y + (100 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -100), 0, scroll_limit())
		return true
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE and travel_target < 0: deck_view = false;cancel_pointer()
		# Hover and touch frames are not a keyboard selection or departure gate.
		return true
	return false
func _init(owner):
	game = owner;merchant_ui = preload("res://merchant_offers.gd").new(owner)
func active() -> bool: return not state.is_empty()
func chapter() -> int: return state.get("chapter", 1)
func chapter_title() -> String: return "第二章 · 坚城" if chapter() == 2 else "第一章 · 朱印行军"
func chapter_seed(run_seed: int, chapter_number: int) -> int:
	# XOR retains the whole run seed and guarantees a different map identity.
	return run_seed ^ (CHAPTER_SEED_SALT * (chapter_number - 1))
func generate(seed_number: int, chapter_number: int = 1):
	game.battle_restart.clear()
	state = GENERATOR.generate(seed_number, clampi(chapter_number, 1, LAST_CHAPTER), game.player_skill)
	state.merge({"treasure_id": "", "treasure_claimed": false, "treasure_choices": [], "current": -1, "visited": [], "pending": -1, "prepared": false, "reward_debt": 0, "pending_homework": [], "homework_awarded": [], "reward_blocked": false, "victory_recorded": false, "last_result": "", "done": false})
	choices = [];deck_view = false;choice_mode = "root";pending_choice = {};merchant_offer = -1;page = 0;reset_view()
	# Chapter geometry and scenery must never reuse the previous map's cache.
	road_cache_key = 0;road_cache.clear();decoration_key = "";decoration_cache.clear();redraw_key = 0
func legal() -> Array:
	if not active() or state.done or state.pending >= 0: return []
	return [0] if state.current < 0 else state.nodes[state.current].next
func enter(id: int):
	if game.screen != "map" or id not in legal(): return
	state.pending = id
	var node = state.nodes[id]
	deck_view = false;choices = [];choice_mode = "root";pending_choice = {};merchant_offer = -1;page = 0
	if node.kind in ["battle", "elite", "boss"]:
		game.stage = 6 if node.kind == "boss" else (maxi(4, node.layout) if node.kind == "elite" else node.layout)
		state.reward_blocked = false;state.victory_recorded = false;state.homework_awarded = []
		game.screen = "game";game.start_stage()
		if state.prepared:
			state.prepared = false;game.draw_card();game.draw_card()
			game.notice = "养精蓄锐：开战额外抽2张牌。"
		game.battle_restart.capture()
	else:
		game.screen = "route_choice"
		choices = options()
	save()
func event_title(node: Dictionary) -> String:
	return EVENT_TITLES.get(node.get("event_id", ""), "奇遇") if node.kind == "event" else TITLES[node.kind]
func refresh_choices():
	page = 0;choices = options()
func card_label(index: int) -> String:
	return "「%s」第%d张" % [game.CARDS[game.collection[index]][0], index + 1]
func random_upgrade_index() -> int:
	var eligible = UPGRADES.eligible_indices(game.collection)
	if eligible.is_empty(): return -1
	var random = RandomNumberGenerator.new()
	random.seed = state.nodes[state.pending].upgrade_seed
	return eligible[random.randi_range(0, eligible.size() - 1)]
func camp_card() -> String:
	# A node-local roll never advances combat RNG, including previews and reloads.
	if state.pending < 0 or state.nodes[state.pending].kind != "camp": return ""
	var pool: Array = []
	for id in game.PROFILES.COMMON + game.PROFILES.DATA[game.player_skill].rewards:
		if id in game.CARDS and id not in game.TREASURES.TEMPORARY and id != "fatigue" and id not in pool: pool.append(id)
	if pool.is_empty(): return ""
	var random = RandomNumberGenerator.new()
	random.seed = int(state.seed) ^ (int(state.pending + 1) * 0x45d9f3b)
	return pool[random.randi_range(0, pool.size() - 1)]
func heal_label(prefix: String) -> String:
	var cap = game.life_limit()
	if not game.can_heal(): return "生命已达上限%d · 无需疗养" % cap
	return prefix + (" · 生命+1（无上限）" if cap < 0 else " · 生命+1（上限%d）" % cap)
func options() -> Array:
	var node = state.nodes[state.pending]
	var result = []
	if choice_mode == "confirm":
		return [{"label": "确认 · " + pending_choice.label, "action": "confirm"}, {"label": "取消 · 不作改变", "action": "back"}]
	if choice_mode in ["remove", "focus", "homework", "exchange", "upgrade"]:
		for i in game.collection.size():
			if choice_mode == "upgrade" and not UPGRADES.can_upgrade(game.collection[i]): continue
			var action = choice_mode
			var label = {"remove": "删除", "focus": "专注抄写", "homework": "课后作业", "exchange": "交出", "upgrade": "强化"}[action] + card_label(i)
			if action == "focus": label += " · 立即复制并加入疲惫"
			if action == "homework": label += " · 下一战无奖励，胜利后获得副本"
			if action == "exchange": label += " → " + game.CARDS[node.offers[merchant_offer]][0]
			result.append({"label": label, "action": action, "index": i, "offer": merchant_offer})
		result.append({"label": "取消 · 返回选项", "action": "back"})
		return result
	if node.kind == "workshop":
		result.append({"label": "强化卡牌" if not UPGRADES.eligible_indices(game.collection).is_empty() else "没有可强化的牌", "action": "select_upgrade" if not UPGRADES.eligible_indices(game.collection).is_empty() else "disabled"})
		result.append({"label": "删除一张永久牌" if not game.collection.is_empty() else "牌组已空 · 无法删牌", "action": "select_remove" if not game.collection.is_empty() else "disabled"})
	elif node.kind == "camp":
		result.append({"label": "轻装上阵 · 删除一张永久牌" if not game.collection.is_empty() else "轻装上阵 · 牌组已空", "action": "select_remove" if not game.collection.is_empty() else "disabled"})
		result.append({"label": heal_label("休养生息"), "action": "heal" if game.can_heal() else "disabled"})
		result.append({"label": "养精蓄锐 · 随机获得一张永久牌", "action": "prepare" if not camp_card().is_empty() else "disabled"})
	elif node.event_id == "herbalist":
		result.append({"label": heal_label("药庐疗养"), "action": "heal" if game.can_heal() else "disabled"})
		result.append({"label": "取调息方 · 获得一张调息", "action": "breath"})
	elif node.event_id == "merchant":
		for i in node.offers.size():
			result.append({"label": "换取「%s」· 交出一张永久牌" % game.CARDS[node.offers[i]][0], "action": "select_exchange", "offer": i})
	elif node.event_id == "manual":
		result.append({"label": "专注抄写 · 立即复制一张牌，并加入一张疲惫" if not game.collection.is_empty() else "专注抄写 · 牌组已空，无法复制", "action": "select_focus" if not game.collection.is_empty() else "disabled"})
		result.append({"label": "课后作业 · 下一战无奖励，胜利后获得复制牌" if not game.collection.is_empty() else "课后作业 · 牌组已空，无法复制", "action": "select_homework" if not game.collection.is_empty() else "disabled"})
		result.append({"label": "只记口诀 · 随机强化一张可强化牌" if random_upgrade_index() >= 0 else "只记口诀 · 没有可强化的牌", "action": "random_upgrade" if random_upgrade_index() >= 0 else "disabled"})
	result.append({"label": "离开 · 保持现状", "action": "leave"})
	return result
func resolve(index: int):
	if game.screen != "route_choice" or state.pending < 0 or index < 0 or index >= choices.size(): return
	var choice = choices[index]
	if choice.action == "disabled": return
	if choice.action == "back":
		if game.card_picker.active: game.card_picker.close()
		choice_mode = "root";pending_choice = {};refresh_choices();return
	if choice.action in ["select_remove", "select_focus", "select_homework", "select_exchange", "select_upgrade"]:
		choice_mode = choice.action.trim_prefix("select_");merchant_offer = choice.get("offer", -1);refresh_choices();open_card_picker();return
	if choice.action == "leave":
		state.last_result = "已离开" + event_title(state.nodes[state.pending]);complete();return
	if choice.action != "confirm":
		pending_choice = choice.duplicate(true);choice_mode = "confirm";refresh_choices();return
	# Mutate only after confirmation; no gameplay state changes in previews/cancel.
	choice = pending_choice
	var i = choice.get("index", -1)
	if choice.action in ["upgrade", "remove", "focus", "homework", "exchange"] and (i < 0 or i >= game.collection.size()): return
	var outcome = ""
	var upgraded_from = ""
	var upgraded_to = ""
	match choice.action:
		"upgrade":
			if not UPGRADES.can_upgrade(game.collection[i]): return
			game.collection[i] = UPGRADES.upgraded_id(game.collection[i]);outcome = "已强化" + card_label(i)
		"random_upgrade":
			i = random_upgrade_index()
			if i < 0: return
			upgraded_from = game.collection[i];upgraded_to = UPGRADES.upgraded_id(upgraded_from)
			game.collection[i] = upgraded_to;outcome = "口诀领悟：已强化" + card_label(i)
		"prepare":
			var card = camp_card()
			if card.is_empty(): return
			game.collection.append(card);outcome = "养精蓄锐：已获得「%s」×1" % game.CARDS[card][0]
		"remove":
			if game.collection.is_empty(): return
			outcome = "已删除" + card_label(i);game.collection.remove_at(i)
		"focus":
			# Card implementation is supplied by the combat module.
			if not game.CARDS.has("fatigue"): return
			outcome = "已复制" + card_label(i) + "，并加入一张疲惫"
			game.collection.append(game.collection[i]);game.collection.append("fatigue")
		"homework":
			state.pending_homework.append(game.collection[i]);state.reward_debt = maxi(1, state.reward_debt)
			outcome = "已记下" + card_label(i) + "：下一战无奖励，胜利后获得副本"
		"exchange":
			if choice.offer < 0 or choice.offer >= state.nodes[state.pending].offers.size(): return
			game.collection[i] = state.nodes[state.pending].offers[choice.offer];outcome = "换得" + game.CARDS[game.collection[i]][0]
		"heal":
			if not game.can_heal(): return
			game.heal_lives(1);outcome = "疗养：生命+1，现有%d" % game.lives
		"breath": game.collection.append("breath");outcome = "已获得一张调息"
	state.last_result = outcome
	complete()
	if not upgraded_from.is_empty(): game.presentation.upgrade(upgraded_from, upgraded_to, i)
func open_card_picker():
	var eligible: Array = UPGRADES.eligible_indices(game.collection) if choice_mode == "upgrade" else range(game.collection.size())
	var heading = {"upgrade": "工坊 · 强化卡牌", "remove": "休整 · 轻装上阵", "focus": "兵书 · 专注抄写", "homework": "兵书 · 课后作业", "exchange": "行商 · 选择交出的牌"}[choice_mode]
	if choice_mode == "remove" and state.nodes[state.pending].kind == "workshop": heading = "工坊 · 删除卡牌"
	if choice_mode == "exchange" and merchant_offer >= 0:
		heading = "行商 · 换取" + game.CARDS[state.nodes[state.pending].offers[merchant_offer]][0]
	game.card_picker.open(choice_mode, heading, eligible, picker_confirm, picker_cancel, state.nodes[state.pending].offers[merchant_offer] if choice_mode == "exchange" else "")
func picker_cancel():
	choice_mode = "root";pending_choice = {};refresh_choices();game.queue_redraw()
func picker_confirm(index: int):
	for n in choices.size():
		if choices[n].get("index", -1) == index and choices[n].action == choice_mode:
			resolve(n)
			if choice_mode == "confirm": resolve(0)
			return
func battle_victory() -> bool:
	if not active() or state.pending < 0 or state.nodes[state.pending].kind not in ["battle", "elite", "boss"]: return false
	if state.victory_recorded: return state.reward_blocked
	state.victory_recorded = true
	state.reward_blocked = state.reward_debt > 0
	if state.reward_blocked: state.reward_debt -= 1
	# Every assignment refers to this next battle, not extra later battles.
	# Deliver the committed card identity exactly once, even after it left the deck.
	state.homework_awarded = state.pending_homework.duplicate()
	for card in state.homework_awarded: game.collection.append(card)
	state.pending_homework.clear()
	return state.reward_blocked
func homework_summary() -> String:
	if not active() or state.homework_awarded.is_empty(): return ""
	var names = PackedStringArray()
	for card in state.homework_awarded: names.append(game.CARDS[card][0])
	return "课后作业已交付：" + "、".join(names)
func rewards_blocked() -> bool:
	return active() and state.get("reward_blocked", false)
func complete():
	if game.card_picker.active: game.card_picker.close()
	if not active() or state.pending < 0 or state.done: return
	game.battle_restart.clear()
	var completed_boss = state.nodes[state.pending].kind == "boss"
	if completed_boss and chapter() == LAST_CHAPTER:
		state.done = true;game.phase = "win"
		game.history.clear();game.cancel_gesture();game.rewardui.reset();save()
		return
	if state.nodes[state.pending].kind in ["battle", "elite", "boss"]:
		state.last_result = "战斗胜利；本场无常规奖励。" if state.reward_blocked else "战斗胜利，继续行军。"
		if not state.homework_awarded.is_empty(): state.last_result += homework_summary()
	state.current = state.pending;state.visited.append(state.pending);state.pending = -1
	state.reward_blocked = false;state.victory_recorded = false;state.homework_awarded = [];choice_mode = "root";pending_choice = {};merchant_offer = -1
	game.history.clear();game.cancel_gesture();game.clear_effects();game.rewardui.reset()
	game.hand = [];game.hand_ids = [];game.deck = [];game.discard = [];game.enemies = [];game.energy = 0;game.tuna_turns = 0;game.tuna_active = false
	game.clear_battle_card_effects();game.encounter_state = {}
	game.selected = -1;game.free_selected = false;game.handui.reset();game.reinforcement_pending = 0
	game.phase = "play";game.screen = "map";choices = [];page = 0;reset_view()
	if completed_boss:
		# The card reward and homework delivery have already settled. Persist
		# this separate, mandatory chapter reward before showing its choices.
		state.treasure_choices = game.TREASURES.ids_for(game.player_skill)
		game.screen = "treasure_choice"
	else:
		stamp_node = state.current;stamp_elapsed = 0.0
	save()
func choose_treasure(id: String) -> bool:
	if game.screen != "treasure_choice" or game.tutorial.active or not active(): return false
	if chapter() != 1 or state.get("treasure_claimed", false) or not state.get("treasure_id", "").is_empty(): return false
	if id not in state.get("treasure_choices", []) or id not in game.TREASURES.ids_for(game.player_skill): return false
	if state.pending != -1 or state.current < 0 or state.nodes[state.current].kind != "boss": return false
	var carry = {"prepared": state.prepared, "reward_debt": state.reward_debt, "pending_homework": state.pending_homework.duplicate(), "last_result": state.last_result}
	var run_seed = state.get("run_seed", state.seed)
	# One synchronous transaction: no intermediate save can grant twice.
	generate(run_seed, 2)
	for key in ["prepared", "reward_debt", "pending_homework"]: state[key] = carry[key]
	state.treasure_id = id;state.treasure_claimed = true;state.treasure_choices = []
	state.last_result = "获得" + game.TREASURES.DATA[id].name + "，进入第二章 · 坚城。" + carry.last_result
	game.treasure_battle = {};game.screen = "map";game.phase = "play"
	game.cancel_gesture();game.information.clear();reset_view();save();game.queue_redraw()
	return true

func save():
	if not active(): return
	var config = ConfigFile.new()
	config.set_value("run", "version", 6)
	config.set_value("run", "normal_undos_remaining", game.normal_undos_remaining)
	config.set_value("run", "route", state)
	config.set_value("run", "battle", game.history.capture())
	config.set_value("run", "screen", game.screen if game.screen in ["game", "map", "route_choice", "treasure_choice"] else "map")
	config.set_value("run", "battle_start", game.battle_restart.snapshot)
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
	if not loaded or config.get_value("run", "version", 0) != 6: return false
	var saved = config.get_value("run", "route", {})
	var battle = config.get_value("run", "battle", {})
	var saved_screen = config.get_value("run", "screen", "map")
	# New optional run fields do not invalidate an otherwise valid demo save.
	if battle is Dictionary and not battle.has("treasure_battle"): battle.treasure_battle = {}
	if not valid_snapshot(saved, battle, saved_screen): return false
	var remaining = config.get_value("run", "normal_undos_remaining", game.NORMAL_UNDO_LIMIT)
	if not remaining is int or remaining < 0 or remaining > game.NORMAL_UNDO_LIMIT: return false
	game.normal_undos_remaining = remaining
	game.card_picker.close();game.presentation.clear()
	game.tutorial.stop();game.history.clear();game.cancel_gesture();game.clear_effects()
	state = saved.duplicate(true)
	for key in game.HISTORY.FIELDS: game.set(key, battle[key])
	# Role, treasure and all battle fields must be restored before applying the cap.
	game.clamp_lives_to_limit()
	game.rng.state = battle.rng_state
	game.screen = config.get_value("run", "screen", "map")
	game.input_lock = 0;game.navigation_lock = 0;game.selected = -1;game.free_selected = false
	game.rewardui.reset();game.handui.reset();page = 0;deck_view = false;reset_view()
	choice_mode = "root";pending_choice = {};merchant_offer = -1
	choices = options() if game.screen == "route_choice" else []
	game.battle_restart.clear()
	if game.screen == "game": game.battle_restart.load_snapshot(config.get_value("run", "battle_start", {}))
	return true
func valid_snapshot(saved, battle, saved_screen) -> bool:
	# Validate the entire current-version envelope before touching live state.
	if not saved is Dictionary or not battle is Dictionary: return false
	if saved_screen not in ["map", "game", "route_choice", "treasure_choice"]: return false
	for key in ["seed", "nodes", "current", "visited", "pending", "prepared", "reward_debt", "pending_homework", "homework_awarded", "reward_blocked", "victory_recorded", "last_result", "done"]:
		if not saved.has(key): return false
	if not saved.nodes is Array or saved.nodes.size() < 9 or saved.nodes.size() > 40 or not saved.visited is Array: return false
	if not saved.current is int or not saved.pending is int or not saved.seed is int: return false
	if saved.current < -1 or saved.current >= saved.nodes.size() or saved.pending < -1 or saved.pending >= saved.nodes.size(): return false
	var saved_chapter = saved.get("chapter", 1)
	if not saved_chapter is int or saved_chapter not in [1, 2]: return false
	if saved_chapter > 1 and not saved.has("run_seed"): return false
	if saved.has("run_seed"):
		if not saved.run_seed is int or saved.seed != chapter_seed(saved.run_seed, saved_chapter): return false
	for key in ["prepared", "reward_blocked", "victory_recorded", "done"]:
		if not saved[key] is bool: return false
	if not saved.reward_debt is int or saved.reward_debt < 0 or not saved.last_result is String: return false
	for key in ["pending_homework", "homework_awarded"]:
		if not saved[key] is Array: return false
		for card in saved[key]:
			if card not in game.CARDS or card in game.TREASURES.TEMPORARY: return false
	if saved.done: return false
	if not GENERATOR.validate_structure(saved): return false
	for node in saved.nodes:
		if node.kind in ["battle", "elite", "boss"]:
			if not game.ENCOUNTERS.valid_config(node.encounter) or node.encounter.tier != node.kind: return false
			if node.encounter.get("chapter", 1) != saved_chapter: return false
		elif node.encounter != {}: return false
		if node.kind == "event":
			if node.get("event_id", "") not in EVENT_IDS or not node.get("upgrade_seed") is int: return false
			if not node.get("offers") is Array or node.offers.size() != 3: return false
			var unique = {}
			for offer in node.offers:
				if offer not in game.CARDS or offer in game.TREASURES.TEMPORARY or unique.has(offer): return false
				unique[offer] = true
		for card in node.loot:
			if card not in game.CARDS or card in game.TREASURES.TEMPORARY: return false
	var previous = -1
	for id in saved.visited:
		if not id is int or id < 0 or id >= saved.nodes.size(): return false
		if (previous < 0 and id != 0) or (previous >= 0 and id not in saved.nodes[previous].next): return false
		previous = id
	if previous != saved.current: return false
	if saved.pending >= 0:
		if saved.pending not in ([0] if saved.current < 0 else saved.nodes[saved.current].next): return false
		if saved_screen == "map": return false
		var combat = saved.nodes[saved.pending].kind in ["battle", "elite", "boss"]
		if (saved_screen == "game") != combat: return false
	elif saved_screen not in ["map", "treasure_choice"]: return false
	var treasure_id = saved.get("treasure_id", "")
	if not treasure_id is String or (not treasure_id.is_empty() and treasure_id not in game.TREASURES.DATA): return false
	if not saved.get("treasure_claimed", false) is bool or not saved.get("treasure_choices", []) is Array: return false
	if not treasure_id.is_empty():
		if saved_chapter != 2 or not saved.get("treasure_claimed", false): return false
		if game.TREASURES.DATA[treasure_id].role != battle.get("player_skill", ""): return false
	elif saved.get("treasure_claimed", false): return false
	if saved_screen == "treasure_choice":
		if saved_chapter != 1 or saved.current < 0 or saved.nodes[saved.current].kind != "boss" or not treasure_id.is_empty(): return false
		if battle.get("phase", "") != "play" or battle.get("lives", 0) <= 0: return false
		if saved.get("treasure_choices", []) != game.TREASURES.ids_for(battle.get("player_skill", "")): return false
	elif not saved.get("treasure_choices", []).is_empty(): return false
	if saved_screen == "map" and saved_chapter == 1 and saved.current >= 0 and saved.nodes[saved.current].kind == "boss": return false
	if not battle.has("rng_state") or not battle.rng_state is int: return false
	if not game.TREASURES.valid_battle_state(battle.get("treasure_battle", {})): return false
	if not str(battle.get("treasure_battle", {}).get("active_card", "")).is_empty(): return false
	for key in game.HISTORY.FIELDS:
		if not battle.has(key): return false
		var current_value = game.get(key)
		if typeof(battle[key]) != typeof(current_value):
			# ConfigFile preserves numeric values; runtime counters can begin as ints.
			if not ((battle[key] is int or battle[key] is float) and (current_value is int or current_value is float)): return false
	if battle.player_skill not in game.PROFILES.DATA or battle.phase not in ["play", "discard", "reward", "win", "dead"]: return false
	for key in ["collection", "deck", "discard", "hand", "rewards"]:
		for card in battle[key]:
			if card not in game.CARDS or (key != "hand" and card in game.TREASURES.TEMPORARY): return false
	if not battle.airdrop_recovery_turn is int or battle.airdrop_recovery_turn < 0 or battle.airdrop_recovery_turn > battle.turn + 1: return false
	if battle.active_displacements < 0 or battle.shield_charges not in [0, 1] or battle.next_enemy_uid < 1: return false
	if not battle.encounter_state.is_empty():
		if not game.ENCOUNTERS.valid_state(battle.encounter_state): return false
	if saved_screen == "game":
		if battle.encounter_state.is_empty() or battle.encounter_state.config != saved.nodes[saved.pending].encounter: return false
	elif not battle.encounter_state.is_empty(): return false
	var ids = {}
	for enemy in battle.enemies:
		if not enemy is Dictionary or not enemy.has("kind") or not enemy.has("pos") or not enemy.pos is Vector2i: return false
		if not enemy.get("uid") is int or enemy.uid < 1 or ids.has(enemy.uid) or enemy.uid >= battle.next_enemy_uid: return false
		for counter in ["action_credits", "action_credit_delay"]:
			if enemy.has(counter) and (not enemy[counter] is int or enemy[counter] < 0): return false
		if enemy.has("ai_recent"):
			if not enemy.ai_recent is Array or enemy.ai_recent.size()>2: return false
			for position_value in enemy.ai_recent:
				if not position_value is Vector2i or not game.R.inside(position_value): return false
		ids[enemy.uid] = true
	if not battle.encounter_state.is_empty() and battle.encounter_state.config.get("chapter", 1) == 2:
		# Encounter-local validation cannot see the live army or UID allocator.
		# Dead unyielding defenders retain identity; waves may already be dead.
		var reserved = {}
		for ghost in battle.encounter_state.ghosts:
			var uid = ghost.enemy.uid
			if uid >= battle.next_enemy_uid or ids.has(uid) or reserved.has(uid): return false
			reserved[uid] = true
		var wave_uids = {}
		var templates = game.ENCOUNTERS.CHAPTER_TWO.TEMPLATES
		for wave in battle.encounter_state.waves:
			if wave.status != "arrived": continue
			if wave.uid >= battle.next_enemy_uid or reserved.has(wave.uid) or wave_uids.has(wave.uid): return false
			wave_uids[wave.uid] = true
			var spec = templates[battle.encounter_state.config.id].waves[wave.index][1]
			for enemy in battle.enemies:
				if enemy.uid != wave.uid: continue
				if not enemy.get("reinforcement", false) or enemy.kind != spec[0] or enemy.get("max_hp") != spec[3]: return false
				if enemy.get("original_spawn") != Vector2i(spec[1] - 1, spec[2] - 1) or enemy.get("heavy") != spec[4] or enemy.get("unyielding") != spec[5]: return false
		for enemy in battle.enemies:
			if enemy.get("reinforcement", false) and not wave_uids.has(enemy.uid): return false
	for bleed in battle.pending_bleeds:
		if not bleed is Dictionary or not bleed.get("enemy_uid") is int or not bleed.get("amount") is int: return false
		if bleed.enemy_uid < 1 or bleed.amount < 1: return false
	return true
func position(node: Dictionary) -> Vector2:
	return content_point(node) - Vector2(0, scroll_y)
func home_rect() -> Rect2: return Rect2(24, 12, 100, 44)
func deck_rect() -> Rect2: return Rect2(game.ui_size.x - 144, 12, 120, 44)
func button(rect: Rect2, label: String, primary: bool = false):
	game.panel(rect, Palette.ACCENT if primary else PAPER_LIGHT, Palette.ACCENT if primary else Palette.BORDER)
	var text_size = 18 if rect.size.y >= 58 else 16
	var width = game.FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	if width > rect.size.x - 16:
		game.wrapped_text(label, Rect2(rect.position + Vector2(8, 2), rect.size - Vector2(16, 4)), 14, Palette.WHITE if primary else INK)
		return
	game.text_at(rect.get_center() + Vector2(-width * 0.5, text_size * 0.36), label, text_size, Palette.WHITE if primary else INK)
var page = 0
func row_rect(index: int) -> Rect2: return Rect2(24, 176 + index * 54, game.ui_size.x - 48, 46)
func capacity() -> int: return maxi(1, int((game.ui_size.y - 260) / 54))
func footer_rect(i: int) -> Rect2:
	return Rect2(24 + i * 145, game.ui_size.y - 65, 136, 48)
func click(pos: Vector2):
	if merchant_ui.active(): merchant_ui.click(pos);return
	if travel_target >= 0: return
	if home_rect().has_point(pos): game.show_home();return
	if game.screen == "map":
		if deck_rect().has_point(pos):
			game.card_picker.open("view", "全部永久牌组", range(game.collection.size()), Callable(), Callable());return
		var id = node_at(pos)
		game.information.clear()
		selected_node = id
		if id in legal(): confirm()

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
	var stamp_x = clampf(rect.end.x - side * 0.25, map_rect().position.x + 4, map_rect().end.x - side - 4)
	return Rect2(Vector2(stamp_x, rect.position.y + 3), Vector2(side, side))
func centered_text(point: Vector2, value: String, font_size: int, color: Color):
	var width = game.FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	game.text_at(point - Vector2(width * 0.5, 0), value, font_size, color)
func decoration_clear(rect: Rect2) -> bool:
	# Decoration uses unscrolled content coordinates, never the current viewport.
	var bounds = Rect2(map_rect().position + Vector2(14, 14), Vector2(map_rect().size.x - 28, content_height() - 28))
	if not bounds.encloses(rect): return false
	ensure_road_cache()
	for reserved in scenery_obstacles:
		if reserved.intersects(rect): return false
	var corridor = rect.grow(18)
	for point in scenery_roads:
		if corridor.has_point(point): return false
	return true
func decoration_layout() -> Array:
	var key = str([state.get("decor_seed", 0), game.ui_size, game.mobile_layout, game.compact_landscape, state.get("nodes", []).hash()].hash())
	if key == decoration_key: return decoration_cache
	decoration_key = key;decoration_cache = []
	if not active(): return decoration_cache
	var random = RandomNumberGenerator.new();random.seed = int(state.decor_seed)
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
	if paper_size != area.size:
		paper_size = area.size;paper_lines.clear()
		var random = RandomNumberGenerator.new();random.seed = 9631
		for i in 420:
			var p = Vector2(random.randf() * area.size.x, random.randf() * area.size.y)
			var q = p + Vector2(random.randf_range(1, 5), random.randf_range(-2, 2))
			paper_lines.append(p);paper_lines.append(q)
	game.draw_set_transform(area.position)
	game.draw_multiline(paper_lines, Color(0.35, 0.34, 0.29, 0.045), 0.7, true)
	game.draw_set_transform(Vector2.ZERO)
	for item in decoration_layout():
		var r: Rect2 = item.rect
		r.position.y -= scroll_y
		if not r.grow(10).intersects(area): continue
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
func draw_route_edge(node: Dictionary, target: Dictionary, cache_ready: bool = false):
	if not cache_ready: ensure_road_cache()
	var edge = road_cache[Vector2i(node.id, target.id)]
	var bounds: Rect2 = edge.bounds;bounds.position.y -= scroll_y
	if not bounds.intersects(map_rect()): return
	var traversed = node.id in state.visited and target.id in state.visited
	var available = node.id == state.current and target.id in legal()
	var selected = available and target.id == selected_node
	var color = INK if available or traversed else Palette.BORDER_STRONG
	var points: PackedVector2Array = edge.solid if traversed else edge.dashed
	game.draw_set_transform(Vector2(0, -scroll_y))
	if not points.is_empty(): game.draw_multiline(points, color, 2.4 if selected else (1.9 if available or traversed else 1.3), true)
	if available:
		var p = edge_point(edge.from, edge.to, 0.52)
		var q = edge_point(edge.from, edge.to, 0.54)
		var direction = (q - p).normalized()
		game.draw_line(p - direction.rotated(0.65) * 7, p, INK, 1.8, true)
		game.draw_line(p - direction.rotated(-0.65) * 7, p, INK, 1.8, true)
	game.draw_set_transform(Vector2.ZERO)
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
	var label = {"battle":"战斗", "elite":"关隘", "camp":"休整", "workshop":"工坊", "event":"奇遇", "boss":"决战"}[node.kind]
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
	ensure_road_cache()
	for node in state.nodes:
		for next in node.next: draw_route_edge(node, state.nodes[next], true)
	for id in range(state.nodes.size() - 1, -1, -1):
		var node = state.nodes[id]
		if hit_rect(node).merge(stamp_rect(node)).grow(24).intersects(area): draw_landmark(node)
	draw_piece()
	# Fixed opaque masks provide a strict visual viewport for the immediate-mode canvas.
	game.draw_rect(Rect2(0, 0, game.ui_size.x, area.position.y), PAPER)
	game.draw_rect(Rect2(0, area.end.y, game.ui_size.x, game.ui_size.y - area.end.y), PAPER)
	game.draw_rect(Rect2(0, area.position.y, area.position.x, area.size.y), PAPER)
	game.draw_rect(Rect2(area.end.x, area.position.y, game.ui_size.x - area.end.x, area.size.y), PAPER)
	game.draw_rect(area, Palette.BORDER, false, 1)
	if scroll_limit() > 0:
		var track = Rect2(area.end.x - 6, area.position.y + 8, 3, area.size.y - 16)
		game.draw_rect(track, Color(0.27, 0.25, 0.20, 0.12))
		var thumb_h = maxf(24, track.size.y * area.size.y / content_height())
		game.draw_rect(Rect2(track.position + Vector2(0, (track.size.y - thumb_h) * scroll_y / scroll_limit()), Vector2(3, thumb_h)), MUTED)
func reward_debt_text() -> String:
	return "无收益·剩%d场" % state.get("reward_debt", 0) if state.get("reward_debt", 0) > 0 else ""
func draw_header():
	button(home_rect(), "‹ 首页")
	if game.screen == "map":
		button(deck_rect(), "查看牌组")
		if travel_target >= 0: game.draw_rect(deck_rect(), Color(PAPER, 0.55))
	var title_x = 146.0 if game.compact_landscape else 150.0
	var subtitle = chapter_title()
	game.text_at(Vector2(title_x, 47), subtitle if game.mobile_layout and not game.compact_landscape else "弈 行", 20 if game.mobile_layout and not game.compact_landscape else 33, INK)
	if game.compact_landscape:
		game.text_at(Vector2(265, 45), subtitle, 21, INK)
		game.text_at(Vector2(16, 78), "已行 %d / %d  ·  生命%d  ·  永久牌%d张" % [state.visited.size(), state.path_length, game.lives, game.collection.size()], 16, MUTED)
	else:
		if game.mobile_layout:
			game.text_at(Vector2(26, 76), "已行%d/%d · 生命%d · 永久牌%d张" % [state.visited.size(), state.path_length, game.lives, game.collection.size()], 16, INK)
			game.text_at(Vector2(26, 99), "备战%s" % ("+2" if state.prepared else "无"), 14, MUTED)
		else:
			game.text_at(Vector2(26, 92), subtitle, 23, INK)
			game.text_at(Vector2(game.ui_size.x - 370, 91), "已行 %d / %d · 生命%d · 永久牌%d张" % [state.visited.size(), state.path_length, game.lives, game.collection.size()], 16, MUTED)
	if game.screen == "map" and not reward_debt_text().is_empty():
		var debt_pos = Vector2(590, 78) if game.compact_landscape else (Vector2(170, 99) if game.mobile_layout else Vector2(450, 92))
		game.text_at(debt_pos, reward_debt_text(), 16, RED)
	if not game.mobile_layout:
		game.text_at(Vector2(290, 45), "一子入山河，百战成归途", 18, MUTED)
		game.text_at(Vector2(850, 45), game.BUILD_VERSION + " · 朱印军符", 16, MUTED)
func inspect_at(pos: Vector2) -> Dictionary:
	var id = node_at(pos)
	if id < 0: return {}
	var node = state.nodes[id]
	var names = {"battle": "战斗", "elite": "关隘", "camp": "休整", "workshop": "工坊", "event": "奇遇", "boss": "决战"}
	var nature = {"battle": "普通战斗，检验当前构筑。", "elite": "精英战斗，奖励选择更多。", "camp": "休整节点，可删牌、回1命或随机获得一张牌。", "workshop": "工坊节点，可强化或删除一张永久牌。", "event": "未知遭遇，抵达后揭晓选项与代价。", "boss": "本章最终战斗，击败守将前进。"}
	return {"key": "node-%d" % node.id, "node_id": node.id, "title": names[node.kind], "lines": [nature[node.kind]], "anchor": hit_rect(node)}
func draw_deck():
	var area = map_rect().grow(-12)
	game.panel(area, PAPER_LIGHT, Palette.BORDER_STRONG)
	var counts = {}
	for id in game.collection: counts[id] = counts.get(id, 0) + 1
	game.text_at(area.position + Vector2(16, 32), "永久牌组", 24, INK)
	game.text_at(area.position + Vector2(16, 60), "消耗牌每战恢复", 16, MUTED)
	var text = ""
	for id in counts: text += "%s × %d   " % [game.CARDS[id][0], counts[id]]
	game.wrapped_text(text, Rect2(area.position + Vector2(16, 88), area.size - Vector2(32, 108)), 18, INK)
func draw():
	if merchant_ui.active(): merchant_ui.draw();return
	game.draw_rect(Rect2(Vector2.ZERO, game.ui_size), PAPER)
	if game.screen == "route_choice":
		draw_header()
		var node = state.nodes[state.pending]
		var heading = event_title(node) + (" · 确认后生效，可取消" if choice_mode == "confirm" else "")
		game.text_at(Vector2(24, 136), heading, 17, INK)
		game.text_at(Vector2(24, 158), "生命%d · 永久牌%d张%s" % [game.lives, game.collection.size(), " · 已备战+2" if state.prepared else ""], 14, MUTED)
		for i in capacity():
			var index = page * capacity() + i
			if index < choices.size(): button(row_rect(i), choices[index].label, choices[index].action == "confirm")
		if choice_mode == "confirm" and pending_choice.action == "exchange":
			var offer = game.CARDS[node.offers[pending_choice.offer]]
			game.wrapped_text("换入牌：%s · %d费 · %s · 交出与换入同时生效，永久牌张数不变。" % [offer[0], offer[1], offer[2]], Rect2(32, row_rect(2).position.y + 8, game.ui_size.x - 64, 140), 17, INK)
		if choice_mode == "confirm" and pending_choice.action == "focus" and game.CARDS.has("fatigue"):
			var fatigue = game.CARDS.fatigue
			game.wrapped_text("疲惫 · %d费\n%s\n复制牌与疲惫均加入永久牌组。" % [fatigue[1], fatigue[2]], Rect2(32, row_rect(2).position.y + 8, game.ui_size.x - 64, 140), 17, INK)
		elif choice_mode == "confirm" and pending_choice.action == "homework":
			game.wrapped_text("下一场胜利不提供常规加牌奖励。胜利后交付选定的复制牌，保留其强化效果。", Rect2(32, row_rect(2).position.y + 8, game.ui_size.x - 64, 140), 17, INK)
		button(footer_rect(0), "上一页")
		button(footer_rect(1), "下一页 %d" % (page + 1))
		return
	draw_map();draw_header()
	if str(state.last_result).begins_with("养精蓄锐："):
		game.wrapped_text(state.last_result, Rect2(map_rect().position + Vector2(14, 12), Vector2(map_rect().size.x - 28, 60)), 18, INK)
	if deck_view: draw_deck()
	if save_error != OK: game.text_at(Vector2(24, game.ui_size.y - 2), "本地存档失败，请勿关闭页面", 14, RED)
