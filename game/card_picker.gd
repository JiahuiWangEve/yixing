extends RefCounted
# One shared modal: permanent-card transactions and the read-only current catalog.
# Transaction modes never commit before confirm; catalog mode never commits at all.
const UPGRADES = preload("res://card_upgrades.gd")
const CATALOG = preload("res://card_catalog.gd")
var game
var face
var active = false
var action = ""
var title = ""
var incoming_card = ""
var snapshot: Array = []
var indices: Array = []
var selected = -1
var scroll_y = 0.0
var on_confirm: Callable
var on_cancel: Callable
var source_screen = ""
var source_phase = ""
var source_pending = -1
var clip: Control
var canvas: Control
var pointer = -2
var pointer_start = Vector2.ZERO
var pointer_last = Vector2.ZERO
var dragged = false
var pointer_scroll = false
var touch_seen = false
var catalog_tab = 0
var catalog_entries: Array = []
var catalog_detail = false
var catalog_upgraded = false
var catalog_grid_scroll = 0.0
var catalog_size_cache: Dictionary = {}

func _init(owner):
	game = owner;face = preload("res://card_face.gd").new(owner)
func open(kind: String, heading: String, eligible: Array, confirm_callback: Callable, cancel_callback: Callable, incoming_card: String = ""):
	game.cancel_gesture();game.route.cancel_pointer()
	catalog_detail = false;catalog_upgraded = false;catalog_entries = [];catalog_size_cache.clear()
	action = kind;title = heading;snapshot = game.collection.duplicate();indices = []
	self.incoming_card = incoming_card if kind == "exchange" and game.CARDS.has(incoming_card) else ""
	for index in eligible:
		if index >= 0 and index < snapshot.size() and game.CARDS.has(snapshot[index]): indices.append(index)
	selected = -1;scroll_y = 0;pointer = -2;dragged = false
	on_confirm = confirm_callback;on_cancel = cancel_callback
	source_screen = game.screen;source_phase = game.phase;source_pending = game.route.state.get("pending", -1)
	active = true
	if not is_instance_valid(clip):
		clip = Control.new();clip.mouse_filter = Control.MOUSE_FILTER_IGNORE;clip.clip_contents = true
		canvas = Control.new();canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		game.add_child(clip);clip.add_child(canvas);canvas.draw.connect(_draw_cards)
	refresh()
func open_catalog():
	# Repeated entry taps reuse this modal rather than stacking children or resetting it.
	if game.screen != "skill_selection" or (active and action == "catalog"): return
	open("catalog", "全部卡牌", [], Callable(), Callable())
	set_catalog_tab(0)
func set_catalog_tab(index: int):
	if not active or action != "catalog" or index < 0 or index >= CATALOG.GROUPS.size(): return
	catalog_tab = index
	catalog_entries = CATALOG.entries_for(CATALOG.GROUPS[index].id, game.CARDS)
	indices = range(catalog_entries.size())
	selected = -1;catalog_detail = false;catalog_upgraded = false;catalog_grid_scroll = 0
	scroll_y = 0;pointer = -2;dragged = false
	refresh()
func catalog_tab_rect(index: int) -> Rect2:
	var width = (game.ui_size.x - 48 - 32) / 5.0
	return Rect2(24 + index * (width + 8), 92, width, 44)
func catalog_back_rect() -> Rect2:
	return Rect2(164, game.ui_size.y - 64, 128, 48)
func catalog_variant_rect() -> Rect2:
	return Rect2(304, game.ui_size.y - 64, game.ui_size.x - 328, 48)
func catalog_id() -> String:
	if action != "catalog" or selected not in indices: return ""
	var entry: Dictionary = catalog_entries[selected]
	return str(entry.upgrade_id) if catalog_upgraded and not str(entry.upgrade_id).is_empty() else str(entry.id)
func catalog_data() -> Array:
	if action != "catalog" or selected not in indices: return []
	var entry: Dictionary = catalog_entries[selected]
	return game.CARDS[catalog_id()] if catalog_upgraded and not str(entry.upgrade_id).is_empty() else entry.data
func catalog_has_upgrade() -> bool:
	return action == "catalog" and selected in indices and not str(catalog_entries[selected].upgrade_id).is_empty()
func toggle_catalog_variant():
	if action != "catalog" or not catalog_detail or not catalog_has_upgrade(): return
	catalog_upgraded = not catalog_upgraded;scroll_y = 0;refresh()
func back_from_catalog_detail():
	if action != "catalog" or not catalog_detail: return
	catalog_detail = false;catalog_upgraded = false;scroll_y = catalog_grid_scroll;refresh()
func _catalog_detail_size() -> Vector2:
	if action != "catalog" or selected not in indices: return Vector2.ZERO
	var width = minf(432, grid_rect().size.x - 8)
	var key = "%s:%s" % [catalog_id(), width]
	if catalog_size_cache.has(key): return catalog_size_cache[key]
	# Measure at ample height first: preserve the shared face's normal 18px text,
	# grow the card instead of silently shrinking or truncating a long effect.
	var layout = face.text_layout(catalog_data(), Vector2(width, 10000), true, game.is_consumable(catalog_id()))
	var height = maxf(maxf(330, width * 1.17), float(layout.start_y) + maxf(0, layout.lines.size() - 1) * float(layout.line_height) + 18)
	var dimensions = Vector2(width, height)
	catalog_size_cache[key] = dimensions
	return dimensions
func catalog_detail_rect() -> Rect2:
	var dimensions = _catalog_detail_size()
	return Rect2(grid_rect().position + Vector2((grid_rect().size.x - dimensions.x) * 0.5, 4 - scroll_y), dimensions)
func close():
	active = false;pointer = -2;dragged = false;incoming_card = "";catalog_detail = false
	if is_instance_valid(clip): clip.hide()
	game.cancel_gesture();game.route.cancel_pointer();game.queue_redraw()
func cancel():
	var callback = on_cancel;close()
	if callback.is_valid(): callback.call()
func valid_context() -> bool:
	return active and game.screen == source_screen and game.phase == source_phase and game.route.state.get("pending", -1) == source_pending and (action == "catalog" or game.collection == snapshot)
func selected_valid() -> bool:
	return action not in ["view", "catalog"] and valid_context() and selected in indices and (action != "upgrade" or UPGRADES.can_upgrade(snapshot[selected]))
func confirm():
	if not selected_valid(): return
	var index = selected;var callback = on_confirm
	close() # Close first: duplicate taps cannot commit twice.
	if callback.is_valid(): callback.call(index)
func has_incoming_preview() -> bool:
	return action == "exchange" and game.CARDS.has(incoming_card)
func incoming_preview_rect() -> Rect2:
	return Rect2(24, 96, 188 if game.compact_landscape else 180, 250 if game.compact_landscape else 230)
func grid_rect() -> Rect2:
	if action == "catalog": return Rect2(24, 156, game.ui_size.x - 48, maxf(110, game.ui_size.y - 238))
	if has_incoming_preview():
		if game.compact_landscape: return Rect2(236, 96, game.ui_size.x - 260, maxf(110, game.ui_size.y - 238))
		return Rect2(24, 362, game.ui_size.x - 48, maxf(110, game.ui_size.y - 536))
	if game.compact_landscape: return Rect2(24, 96, game.ui_size.x - 48, maxf(110, game.ui_size.y - 238))
	return Rect2(24, 108, game.ui_size.x - 48, maxf(110, game.ui_size.y - 282))
func columns() -> int:
	return clampi(int((grid_rect().size.x + 16) / 210), 1, 6)
func card_size() -> Vector2:
	var width = (grid_rect().size.x - (columns() - 1) * 16) / columns()
	return Vector2(width, maxf(250, width * 1.17))
func card_rect(slot: int) -> Rect2:
	var dimensions = card_size()
	return Rect2(grid_rect().position + Vector2((slot % columns()) * (dimensions.x + 16), (slot / columns()) * (dimensions.y + 34) - scroll_y), dimensions)
func scroll_limit() -> float:
	if action == "catalog" and catalog_detail: return maxf(0, _catalog_detail_size().y + 8 - grid_rect().size.y)
	var rows = ceili(float(indices.size()) / columns())
	return maxf(0, rows * (card_size().y + 34) - grid_rect().size.y)
func cancel_rect() -> Rect2: return Rect2(24, game.ui_size.y - 64, 128, 48)
func confirm_rect() -> Rect2: return Rect2(168, game.ui_size.y - 64, game.ui_size.x - 192, 48)
func refresh():
	if not active: return
	scroll_y = clampf(scroll_y, 0, scroll_limit())
	if is_instance_valid(clip):
		clip.position = grid_rect().position;clip.size = grid_rect().size;clip.show();canvas.size = clip.size;canvas.queue_redraw()
	game.queue_redraw()
func tap(pos: Vector2):
	if cancel_rect().has_point(pos): cancel();return
	if action == "catalog":
		for tab in CATALOG.GROUPS.size():
			if catalog_tab_rect(tab).has_point(pos): set_catalog_tab(tab);return
		if catalog_detail:
			if catalog_back_rect().has_point(pos): back_from_catalog_detail()
			elif catalog_variant_rect().has_point(pos): toggle_catalog_variant()
			return
		if not grid_rect().has_point(pos): return
		for slot in indices.size():
			if card_rect(slot).has_point(pos):
				selected = indices[slot];catalog_detail = true;catalog_upgraded = false
				catalog_grid_scroll = scroll_y;scroll_y = 0;refresh();return
		return
	if confirm_rect().has_point(pos): confirm();return
	if not grid_rect().has_point(pos): return
	for slot in indices.size():
		if card_rect(slot).has_point(pos): selected = indices[slot];refresh();return
func press(pos: Vector2, id: int):
	if pointer != -2: return
	pointer = id;pointer_start = pos;pointer_last = pos;dragged = false;pointer_scroll = grid_rect().has_point(pos)
func motion(pos: Vector2, id: int):
	if pointer != id: return
	if pos.distance_to(pointer_start) >= 12: dragged = true
	if dragged and pointer_scroll: scroll_y = clampf(scroll_y - (pos.y - pointer_last.y), 0, scroll_limit());refresh()
	pointer_last = pos
func release(pos: Vector2, id: int, canceled: bool = false):
	if pointer != id: return
	var is_tap = not canceled and not dragged and pos.distance_to(pointer_start) < 12
	pointer = -2
	if is_tap: tap(pos)
func input_event(event) -> bool:
	if not active: return false
	if not valid_context(): close();return true
	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE: cancel()
			elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]: confirm()
		return true # Space must never end a turn behind the picker.
	if event is InputEventScreenTouch:
		touch_seen = true;game.touch_seen = true
		if event.pressed: press(event.position, event.index)
		else: release(event.position, event.index, event.canceled)
	elif event is InputEventScreenDrag: motion(event.position, event.index)
	elif event is InputEventMouse:
		if event.device == -1 and touch_seen: return true
		if event is InputEventMouseMotion: motion(event.position, -1)
		elif event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed: press(event.position, -1)
				else: release(event.position, -1)
			elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and grid_rect().has_point(event.position):
				scroll_y = clampf(scroll_y + (100 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -100), 0, scroll_limit());refresh()
	return true
func description() -> String:
	if action == "catalog":
		if catalog_detail and selected in indices:
			return str(catalog_entries[selected].source) + (" · 强化版" if catalog_upgraded else " · 原版")
		return "特殊卡牌不属于普通奖励；点选查看完整效果" if catalog_tab == 4 else "点选查看完整效果；上下滑动浏览"
	if not valid_context(): return "牌组已改变，请返回后重新选择。"
	if indices.is_empty(): return "永久牌组为空。" if action == "view" else "没有符合条件的永久牌。可返回选择其他选项。"
	if has_incoming_preview() and selected not in indices: return "点选一张要交出的永久牌，再确认交换。返回可重新选择行商报价。"
	if selected not in indices: return "全部永久牌逐张展示，点选查看，上下滑动浏览。" if action == "view" else "点选一张牌，再确认；同名牌逐张展示，上下滑动查看更多。"
	var id: String = snapshot[selected]
	var name: String = game.CARDS[id][0]
	match action:
		"view": return "%s · %d费 · %s" % [name, game.CARDS[id][1], game.CARDS[id][2]]
		"upgrade": return "强化「%s」第%d张 → %s：%s" % [name, selected + 1, game.CARDS[UPGRADES.upgraded_id(id)][0], UPGRADES.description(id)]
		"remove": return "永久删除「%s」第%d张，仅移除这一张。" % [name, selected + 1]
		"focus": return "立即复制「%s」，并加入疲惫：抽到扣1能量，最低0；留在手中每轮扣1；2费打出。" % name
		"homework": return "记录「%s」副本（保留强化）：下一战无常规奖励，胜利后交付。" % name
		"exchange":
			if has_incoming_preview(): return "交出「%s」第%d张 → 换入「%s」。" % [name, selected + 1, game.CARDS[incoming_card][0]]
			return "交出「%s」第%d张，换入已选定的行商报价牌。" % [name, selected + 1]
	return ""
func _draw_incoming_preview():
	var area = incoming_preview_rect()
	var transform = Transform2D(Vector2(area.size.x / 156, 0), Vector2(0, area.size.y / 156), area.position)
	face.draw_data(game, game.CARDS[incoming_card], game.is_consumable(incoming_card), transform)
	game.draw_rect(area.grow(2), game.GOLD, false, 2)
	if game.compact_landscape:
		game.text_at(Vector2(24, area.end.y + 28), "换入后永久牌张数不变", 16, game.THEME.LIGHT)
	else:
		game.text_at(Vector2(224, 130), "选择交出的永久牌", 20, game.THEME.HEADING)
		game.wrapped_text("选中下方旧牌后，确认交换。\n返回可重新选择行商报价。", Rect2(224, 150, game.ui_size.x - 248, 140), 17, game.THEME.LIGHT)
	game.text_at(Vector2(grid_rect().position.x, grid_rect().position.y - 14), "可选 %d 张 · 每张卡牌单独选择" % indices.size(), 17, game.THEME.LIGHT)
func _draw_catalog():
	game.draw_rect(Rect2(Vector2.ZERO, game.ui_size), game.THEME.BACKGROUND)
	game.text_at(Vector2(24, 42), title, 26, game.THEME.HEADING)
	var subtitle = description() if catalog_detail else "%s · %d 张 · %s" % [CATALOG.GROUPS[catalog_tab].label, indices.size(), "非普通奖励，点选查看" if catalog_tab == 4 else "点选查看完整效果"]
	game.text_at(Vector2(24, 76), subtitle, 17, game.THEME.LIGHT)
	for tab in CATALOG.GROUPS.size():
		var rect = catalog_tab_rect(tab)
		game.rewardui._button(rect, CATALOG.GROUPS[tab].label)
		if catalog_tab == tab: game.draw_rect(rect.grow(-2), game.GOLD, false, 2)
	game.rewardui._button(cancel_rect(), "返回")
	if catalog_detail:
		game.rewardui._button(catalog_back_rect(), "返回列表")
		if catalog_has_upgrade(): game.rewardui._button(catalog_variant_rect(), "查看原版" if catalog_upgraded else "查看强化版")
	else:
		game.text_at(Vector2(172, game.ui_size.y - 35), "仅供浏览，不改变牌组", 17, game.THEME.LIGHT)
	_draw_scrollbar()
func _draw_scrollbar():
	if scroll_limit() <= 0: return
	var area = grid_rect();var height = maxf(24, area.size.y * area.size.y / (area.size.y + scroll_limit()))
	game.draw_rect(Rect2(area.end.x + 7, area.position.y + (area.size.y - height) * scroll_y / scroll_limit(), 3, height), game.GOLD)
func draw():
	if not active: return
	refresh_layout_only()
	if action == "catalog": _draw_catalog();return
	game.draw_rect(Rect2(Vector2.ZERO, game.ui_size), game.THEME.BACKGROUND)
	game.text_at(Vector2(24, 42), "准备换入：" + str(game.CARDS[incoming_card][0]) if has_incoming_preview() else title, 26, game.THEME.HEADING)
	if has_incoming_preview(): _draw_incoming_preview()
	else: game.text_at(Vector2(24, 76), ("共 %d 张 · 永久牌逐张展示" if action == "view" else "可选 %d 张 · 每张卡牌单独选择") % indices.size(), 17, game.THEME.LIGHT)
	game.wrapped_text(description(), Rect2(24, game.ui_size.y - (132 if game.compact_landscape else 152), game.ui_size.x - 48, 58 if game.compact_landscape else 78), 17, game.THEME.HEADING)
	game.rewardui._button(cancel_rect(), "返回")
	if action != "view": game.rewardui._button(confirm_rect(), "确认" + {"upgrade": "强化", "remove": "删除", "focus": "抄写", "homework": "记录", "exchange": "交换"}.get(action, "选择") if selected_valid() else "先选择一张牌", selected_valid(), action == "remove")
	_draw_scrollbar()
func refresh_layout_only():
	scroll_y = clampf(scroll_y, 0, scroll_limit())
	if is_instance_valid(clip):
		clip.position = grid_rect().position;clip.size = grid_rect().size;canvas.size = clip.size;canvas.queue_redraw()
func _draw_cards():
	if not active: return
	if action == "catalog" and catalog_detail:
		var rect = catalog_detail_rect()
		var transform = Transform2D(Vector2(rect.size.x / 156, 0), Vector2(0, rect.size.y / 156), rect.position - grid_rect().position)
		face.draw_data(canvas, catalog_data(), game.is_consumable(catalog_id()), transform, 1.0, true)
		return
	for slot in indices.size():
		var rect = card_rect(slot)
		if not rect.grow(24).intersects(grid_rect()): continue
		var index: int = indices[slot];var id: String = str(catalog_entries[index].id) if action == "catalog" else str(snapshot[index])
		var origin = rect.position - grid_rect().position
		var transform = Transform2D(Vector2(rect.size.x / 156, 0), Vector2(0, rect.size.y / 156), origin)
		face.draw_data(canvas, catalog_entries[index].data if action == "catalog" else game.CARDS[id], game.is_consumable(id), transform, 1.0, false, selected == index)
		if selected == index: canvas.draw_rect(Rect2(origin, rect.size).grow(2), game.GOLD, false, 3)
		var caption = "第%d张%s" % [index + 1, " · 已选" if selected == index else ""]
		if action == "catalog": caption = str(catalog_entries[index].source) + (" · 可强化" if not str(catalog_entries[index].upgrade_id).is_empty() else "")
		canvas.draw_string(game.FONT, origin + Vector2(4, rect.size.y + 23), caption, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8 if action == "catalog" else -1, 16, game.THEME.LIGHT)
