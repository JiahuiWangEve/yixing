extends RefCounted
# One modal for physical permanent-card instances. Nothing commits before confirm.
const UPGRADES = preload("res://card_upgrades.gd")
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

func _init(owner):
	game = owner;face = preload("res://card_face.gd").new(owner)
func open(kind: String, heading: String, eligible: Array, confirm_callback: Callable, cancel_callback: Callable, incoming_card: String = ""):
	game.cancel_gesture();game.route.cancel_pointer()
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
func close():
	active = false;pointer = -2;dragged = false;incoming_card = ""
	if is_instance_valid(clip): clip.hide()
	game.cancel_gesture();game.route.cancel_pointer();game.queue_redraw()
func cancel():
	var callback = on_cancel;close()
	if callback.is_valid(): callback.call()
func valid_context() -> bool:
	return active and game.screen == source_screen and game.phase == source_phase and game.route.state.get("pending", -1) == source_pending and game.collection == snapshot
func selected_valid() -> bool:
	return action != "view" and valid_context() and selected in indices and (action != "upgrade" or UPGRADES.can_upgrade(snapshot[selected]))
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
func draw():
	if not active: return
	refresh_layout_only()
	game.draw_rect(Rect2(Vector2.ZERO, game.ui_size), game.THEME.BACKGROUND)
	game.text_at(Vector2(24, 42), "准备换入：" + str(game.CARDS[incoming_card][0]) if has_incoming_preview() else title, 26, game.THEME.HEADING)
	if has_incoming_preview(): _draw_incoming_preview()
	else: game.text_at(Vector2(24, 76), ("共 %d 张 · 永久牌逐张展示" if action == "view" else "可选 %d 张 · 每张卡牌单独选择") % indices.size(), 17, game.THEME.LIGHT)
	game.wrapped_text(description(), Rect2(24, game.ui_size.y - (132 if game.compact_landscape else 152), game.ui_size.x - 48, 58 if game.compact_landscape else 78), 17, game.THEME.HEADING)
	game.rewardui._button(cancel_rect(), "返回")
	if action != "view": game.rewardui._button(confirm_rect(), "确认" + {"upgrade": "强化", "remove": "删除", "focus": "抄写", "homework": "记录", "exchange": "交换"}.get(action, "选择") if selected_valid() else "先选择一张牌", selected_valid(), action == "remove")
	if scroll_limit() > 0:
		var area = grid_rect();var height = maxf(24, area.size.y * area.size.y / (area.size.y + scroll_limit()))
		game.draw_rect(Rect2(area.end.x + 7, area.position.y + (area.size.y - height) * scroll_y / scroll_limit(), 3, height), game.GOLD)
func refresh_layout_only():
	scroll_y = clampf(scroll_y, 0, scroll_limit())
	if is_instance_valid(clip):
		clip.position = grid_rect().position;clip.size = grid_rect().size;canvas.size = clip.size;canvas.queue_redraw()
func _draw_cards():
	if not active: return
	for slot in indices.size():
		var rect = card_rect(slot)
		if not rect.grow(24).intersects(grid_rect()): continue
		var index: int = indices[slot];var id: String = snapshot[index]
		var origin = rect.position - grid_rect().position
		var transform = Transform2D(Vector2(rect.size.x / 156, 0), Vector2(0, rect.size.y / 156), origin)
		face.draw_data(canvas, game.CARDS[id], game.is_consumable(id), transform, 1.0, false, selected == index)
		if selected == index: canvas.draw_rect(Rect2(origin, rect.size).grow(2), game.GOLD, false, 3)
		canvas.draw_string(game.FONT, origin + Vector2(4, rect.size.y + 23), "第%d张%s" % [index + 1, " · 已选" if selected == index else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, game.THEME.LIGHT)
