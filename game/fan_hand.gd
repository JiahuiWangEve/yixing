extends RefCounted




const LOCAL_SIZE = Vector2(156, 156)
const ARRIVAL_SECONDS = 0.36
const MAX_ANGLE = 0.17453292519943
const MOBILE_MAX_ANGLE = 0.1221730476396
var game
var views: Dictionary = {}
var _hovered_visual = -1
var _hover_uid = -1
var _hover_anchor = Vector2(-100000, -100000)
var _initialized = false
var _last_area = Rect2()
var _focus_index = -1
var _order: Array = []
var _discard_time = 0.0
var _last_phase = ""
const DISCARD_PULSE_SECONDS = 0.46



const FREE_INDEX = -2
var hovered_index: int:
	get: return _ordinary_index(_hovered_visual)
	set(value):
		_set_hover(_visual_index(value) if value >= 0 else (0 if value == FREE_INDEX and _has_free() else -1))
func _has_free() -> bool:
	return game.screen == "game" and game.phase in ["play", "discard"] and not game.basic_used
func _cards() -> Array:
	var result: Array = []
	if _has_free(): result.append("__free_" + game.player_skill)
	result.append_array(game.hand)
	return result
func _uids() -> Array:
	var result: Array = []
	if _has_free(): result.append(game.free_card_uid)
	result.append_array(game.hand_ids)
	return result
func _is_free(i: int) -> bool: return i == 0 and _has_free()
func _visual_index(i: int) -> int: return i + (1 if _has_free() else 0)
func _ordinary_index(i: int) -> int:
	if i < 0: return -1
	if _is_free(i): return FREE_INDEX
	return i - (1 if _has_free() else 0)
func _selection() -> int:
	if _has_free() and game.free_selected and game.phase == "play": return 0
	return _visual_index(game.selected) if game.selected >= 0 and game.selected < game.hand.size() else -1
func _data(i: int) -> Array:
	if _is_free(i):
		if game.player_skill == "artillery":
			if game.artillery_mode == "attack": return ["炮步", 0, "攻击姿态：免费正交走1格，移动抽1张；与收炮共用免费行动", "移"]
			return ["行军", 0, "免费正交走1–2格，不穿透；每回合1次，移动抽1张", "移"]
		return ["马步" if game.player_skill == "horse" else "帅步", 0, 
			"免费马步，遵守蹩腿；每回合1次，移动抽1张，与点格共用" if game.player_skill == "horse" else "免费正交走1格；每回合1次，移动抽1张，与点格共用", "移"]
	return game.card_data(game.hand[_ordinary_index(i)])
func _consumable(i: int) -> bool:
	return not _is_free(i) and game.is_consumable(game.hand[_ordinary_index(i)])
func display_entries() -> Array:
	game.sync_hand_ids()
	var result: Array = []
	for i in _cards().size(): result.append({"free": _is_free(i), "index": _ordinary_index(i), "uid": _uids()[i], "card": _cards()[i]})
	return result
func card_transform(i: int) -> Transform2D: return _visual_transform(_visual_index(i))
func bounds(i: int) -> Rect2: return _visual_bounds(_visual_index(i))
func draw_card(i: int, transform: Transform2D, alpha: float = 1.0): _draw_visual_card(_visual_index(i), transform, alpha)
func text_layout(i: int, dimensions: Vector2, focused: bool) -> Dictionary: return _visual_text_layout(_visual_index(i), dimensions, focused)
func hit_index(position: Vector2) -> int: return _ordinary_index(_visual_hit_index(position))
func exposed_point(i: int) -> Vector2: return _visual_exposed_point(_visual_index(i))
func draw_order() -> Array:
	var result: Array = []
	for i in _visual_draw_order():
		if not _is_free(i): result.append(_ordinary_index(i))
	return result
func display_draw_order() -> Array:
	var result: Array = []
	for i in _visual_draw_order(): result.append(_ordinary_index(i))
	return result
func free_transform() -> Transform2D: return _visual_transform(0) if _has_free() else Transform2D.IDENTITY
func free_bounds() -> Rect2: return _visual_bounds(0) if _has_free() else Rect2()
func free_hit(position: Vector2) -> bool: return _has_free() and _visual_hit_index(position) == 0
func free_exposed_point() -> Vector2: return _visual_exposed_point(0) if _has_free() else Vector2.INF
func free_draw(transform: Transform2D, alpha: float = 1.0):
	if _has_free(): _draw_visual_card(0, transform, alpha)

func _init(owner):
	game = owner

func reset():
	views.clear()
	_hovered_visual = -1
	_hover_uid = -1
	_hover_anchor = Vector2(-100000, -100000)
	_focus_index = -1
	_order.clear()
	_initialized = false
	_last_area = Rect2()
	_discard_time = 0.0
	_last_phase = ""

func notify_discard():

	_discard_time = DISCARD_PULSE_SECONDS

func card_size() -> Vector2:
	return LOCAL_SIZE

func _valid(i: int) -> bool:
	return i >= 0 and i < _cards().size() and i < _uids().size()

func _dragged_uid() -> int:
	return int(game.drag_card_uid()) if game.has_method("drag_card_uid") else -1

func _selected_index() -> int:
	return _selection()

func _active_focus() -> int:
	var selected_index = _selected_index()
	return selected_index if selected_index >= 0 else (_hovered_visual if _valid(_hovered_visual) else -1)

func _set_hover(visual: int):
	_hovered_visual = visual
	_hover_uid = int(_uids()[visual]) if _valid(visual) else -1
	_hover_anchor = game.mouse_pos

func sync():
	var phase = str(game.get("phase"))
	if phase == "discard" and _last_phase != "discard": notify_discard()
	_last_phase = phase
	var area: Rect2 = game.hand_area()


	if _hover_uid >= 0: _hovered_visual = _uids().find(_hover_uid)
	if not _valid(_hovered_visual): _hovered_visual = -1;_hover_uid = -1
	_focus_index = _active_focus()
	var targets = _layout_targets(_focus_index)
	var present: Dictionary = {}
	var previous_free: Dictionary = {}
	for old_uid in views:
		if bool(views[old_uid].get("free", false)): previous_free = views[old_uid];break
	for i in mini(_cards().size(), _uids().size()):
		var uid = int(_uids()[i])
		present[uid] = true
		if not views.has(uid):
			var target: Dictionary = targets[i]
			var arrival = 0.0 if _initialized else 1.0
			var free = _is_free(i)
			var origin: Vector2 = target.center
			if arrival < 1.0:
				if free:
					origin = Vector2(previous_free.get("center", target.center)) - Vector2(30, 0)
				else:
					origin = Vector2(area.end.x - target.size.x * 0.5 - 7.0, target.center.y)
			var start_angle = float(target.angle) if free or arrival >= 1.0 else 0.1
			views[uid] = {"center": origin, "angle": start_angle, "size": target.size, 
				"birth": arrival, "from": origin, "from_angle": start_angle, "free": free, 
				"focus": 1.0 if i == _focus_index else 0.0}
			_contain(views[uid], area)
			views[uid].from = views[uid].center
	for uid in views.keys():
		if not present.has(uid): views.erase(uid)


	if area != _last_area:
		for i in targets.size(): views[int(_uids()[i])].size = targets[i].size
		for uid in views.keys(): _contain(views[uid], area)
		_last_area = area
	_initialized = true
	_refresh_order()

func tick(delta: float):
	_discard_time = maxf(0.0, _discard_time - maxf(0.0, delta))
	sync()
	if game.input_lock <= 0 and _dragged_uid() < 0:
		if _hover_uid < 0 or game.mouse_pos.distance_to(_hover_anchor) > 2.0:
			var candidate = _hit_current(game.mouse_pos)
			if _valid(candidate) and float(views[int(_uids()[candidate])].birth) < 1.0: candidate = -1
			if _is_free(candidate) and game.phase == "discard": candidate = -1
			_set_hover(candidate)
	else:
		_set_hover(-1)
	_focus_index = _active_focus()
	var targets = _layout_targets(_focus_index)
	var blend = 1.0 - exp(-14.0 * maxf(delta, 0.0))
	for i in targets.size():
		if not _valid(i): continue
		var view: Dictionary = views[int(_uids()[i])]
		var target: Dictionary = targets[i]
		view.focus = lerpf(float(view.focus), 1.0 if i == _focus_index else 0.0, blend)
		if float(view.birth) < 1.0:
			view.birth = minf(1.0, float(view.birth) + maxf(delta, 0.0) / ARRIVAL_SECONDS)
			var progress = 1.0 - pow(1.0 - float(view.birth), 3.0)
			view.center = Vector2(view.from).lerp(target.center, progress)


			if not bool(view.get("free", false)): view.center.y -= sin(float(view.birth) * PI) * 4.0
			view.angle = lerpf(float(view.get("from_angle", 0.1)), float(target.angle), progress)
		else:
			view.center = Vector2(view.center).lerp(target.center, blend)
			view.angle = lerpf(float(view.angle), float(target.angle), blend)
		view.size = target.size
		_contain(view, game.hand_area())
	_refresh_order()

func _rail_spacing() -> float:
	return 36.0 if game.hand_area().size.x > 800.0 else 29.0

func _desktop_fan() -> bool: return game.hand_area().size.x > 800.0
func _max_angle() -> float: return MAX_ANGLE if _desktop_fan() else MOBILE_MAX_ANGLE
func _fan_arc() -> float: return 25.0 if _desktop_fan() else 14.0
func _focus_lift() -> float: return 12.0 if _desktop_fan() else 10.0

func _fixed_card_size() -> Vector2:
	var area: Rect2 = game.hand_area()
	if _desktop_fan(): return Vector2(198.36, 228.0)
	var angle = _max_angle()
	var overhead = _fan_arc() + _focus_lift() + 12.0
	var usable_height = maxf(50.0, area.size.y - overhead)


	var height = minf(280.0, usable_height / (cos(angle) + 0.87 * sin(angle)))
	var width = height * 0.87
	for iteration in 3:
		var max_width = (area.size.x - 16.0 - 6.0 * _rail_spacing() - 10.0 - height * sin(angle)) / (1.0 + cos(angle))
		width = maxf(28.0, minf(height * 0.87, max_width))
		height = maxf(40.0, minf(280.0, (usable_height - width * sin(angle)) / cos(angle)))
	return Vector2(width, height)

func _layout_targets(focus: int) -> Array:
	var result: Array = []
	var count = mini(_cards().size(), _uids().size())
	if count <= 0: return result
	var area: Rect2 = game.hand_area()
	var dimensions = _fixed_card_size()
	var width = dimensions.x
	var gap = _rail_spacing()
	var extra = maxf(0.0, width + 8.0 - gap) if focus >= 0 and focus < count - 1 else 0.0


	var lead = (10.0 if focus == count - 1 else 2.0) if focus > 0 else 0.0
	var span = width + gap * float(count - 1) + extra + lead
	var left = area.get_center().x - span * 0.5
	var top = area.position.y + 4.0 + _focus_lift()
	for i in count:
		var normalized = 0.0 if count == 1 else float(i) * 2.0 / float(count - 1) - 1.0
		var is_focus = i == focus
		var angle = 0.0 if is_focus else normalized * _max_angle()
		var half_height = (absf(sin(angle)) * dimensions.x + absf(cos(angle)) * dimensions.y) * 0.5
		var x = left + float(i) * gap + (extra if focus >= 0 and i > focus else 0.0) + (lead if focus > 0 and i >= focus else 0.0)
		var center = Vector2(x + width * 0.5, top + _fan_arc() * normalized * normalized + half_height - (_focus_lift() if is_focus else 0.0))
		result.append({"center": center, "angle": angle, "size": dimensions})
	return result

func _project_visible_rails(_focus: int):


	pass

func _contain(view: Dictionary, area: Rect2):


	var dimensions: Vector2 = view.size
	var angle = float(view.angle)
	var half = Vector2(absf(cos(angle)) * dimensions.x + absf(sin(angle)) * dimensions.y, 
		absf(sin(angle)) * dimensions.x + absf(cos(angle)) * dimensions.y) * 0.5
	var inner = area.grow(-4.0)
	view.center = Vector2(clampf(view.center.x, inner.position.x + half.x, inner.end.x - half.x), 
		clampf(view.center.y, inner.position.y + half.y, inner.end.y - half.y))

func _raw_card_transform(i: int) -> Transform2D:
	if not _valid(i): return Transform2D.IDENTITY
	var uid = int(_uids()[i])
	if not views.has(uid): sync()
	if not views.has(uid): return Transform2D.IDENTITY
	var view: Dictionary = views[uid]
	var flip = maxf(0.045, absf(cos(float(view.birth) * PI))) if float(view.birth) < 1.0 and not bool(view.get("free", false)) else 1.0
	var scale: Vector2 = Vector2(view.size) / LOCAL_SIZE
	scale.x *= flip
	var axis_x = Vector2.from_angle(float(view.angle)) * scale.x
	var axis_y = Vector2.from_angle(float(view.angle) + PI * 0.5) * scale.y
	return Transform2D(axis_x, axis_y, Vector2(view.center) - axis_x * LOCAL_SIZE.x * 0.5 - axis_y * LOCAL_SIZE.y * 0.5)

func _visual_transform(i: int) -> Transform2D:
	var transform = _raw_card_transform(i)
	if _discard_time > 0.0 and not _is_free(i):
		var elapsed = DISCARD_PULSE_SECONDS - _discard_time
		transform.origin.x += sin(elapsed * 66.0) * 2.5 * (_discard_time / DISCARD_PULSE_SECONDS)
	return transform

func _visual_bounds(i: int) -> Rect2:
	if not _valid(i): return Rect2()
	var transform = _visual_transform(i)
	var rect = Rect2(transform * Vector2.ZERO, Vector2.ZERO)
	for point in [Vector2(LOCAL_SIZE.x, 0), LOCAL_SIZE, Vector2(0, LOCAL_SIZE.y)]:
		rect = rect.expand(transform * point)
	return rect

func _refresh_order():
	_order.clear()
	var dragged = _dragged_uid()
	for i in mini(_cards().size(), _uids().size()):
		if int(_uids()[i]) != dragged: _order.append(i)

	var focus = _active_focus()
	if focus in _order and _can_promote(focus):
		_order.erase(focus)
		_order.append(focus)

func _can_promote(focus: int) -> bool:
	if not _valid(focus): return false
	var inverse = _raw_card_transform(focus).affine_inverse()
	var local_rect = Rect2(Vector2.ZERO, LOCAL_SIZE)
	for i in _cards().size():
		if i == focus: continue
		var transform = _raw_card_transform(i)
		var physical_size = Vector2(transform.x.length(), transform.y.length()) * LOCAL_SIZE
		if physical_size.x < 28.0: continue
		var large = physical_size.x >= 165.0 and physical_size.y >= 210.0
		var name_y = 50.0 if large else 44.0
		var step = 26.0 if large else 20.0
		var ys = [19.0 if large else 17.0]
		for glyph in str(_data(i)[0]).length(): ys.append(name_y + glyph * step - 7.0)
		for y in ys:
			for x in ([8.0, 19.0, 29.0] if large else [7.0, 15.0, 24.0]):
				var point = transform * (Vector2(x, y) / physical_size * LOCAL_SIZE)
				if local_rect.has_point(inverse * point): return false
	return true

func geometry_snapshot() -> Dictionary:
	sync()
	var area: Rect2 = game.hand_area()
	var entries: Array = []
	for i in _cards().size():
		var transform = _visual_transform(i)
		var corners: Array = []
		for point in [Vector2.ZERO, Vector2(LOCAL_SIZE.x, 0), LOCAL_SIZE, Vector2(0, LOCAL_SIZE.y)]:
			var world = transform * point;corners.append([world.x, world.y])
		var view: Dictionary = views[int(_uids()[i])]
		entries.append({"free": _is_free(i), "index": _ordinary_index(i), "uid": int(_uids()[i]), 
			"name": str(_data(i)[0]), "cost": int(_data(i)[1]), "birth": float(view.birth), 
			"center": [view.center.x, view.center.y], "size": [view.size.x, view.size.y], 
			"angle": transform.x.angle(), "corners": corners})
	return {"area": [area.position.x, area.position.y, area.size.x, area.size.y], 
		"max_angle": _max_angle(), "arc": _fan_arc(), "draw_order": display_draw_order(), "cards": entries}

func _visual_draw_order() -> Array:
	sync()
	return _order.duplicate()

func _hit_current(position: Vector2) -> int:
	if not game.hand_area().has_point(position): return -1
	for slot in range(_order.size() - 1, -1, -1):
		var i = int(_order[slot])
		if not _valid(i): continue
		var local = _visual_transform(i).affine_inverse() * position
		if Rect2(Vector2.ZERO, LOCAL_SIZE).has_point(local): return i
	return -1

func _visual_hit_index(position: Vector2) -> int:
	sync()
	return _hit_current(position)

func _visual_exposed_point(i: int) -> Vector2:
	sync()
	if not _valid(i): return Vector2.INF
	var transform = _visual_transform(i)
	var dimensions = Vector2(transform.x.length() * LOCAL_SIZE.x, transform.y.length() * LOCAL_SIZE.y)


	for y in [17.0, 44.0, 64.0, 84.0, dimensions.y - 17.0]:
		for x in [15.0, 8.0, 22.0]:
			if x >= dimensions.x or y >= dimensions.y: continue
			var point = transform * (Vector2(x, y) / dimensions * LOCAL_SIZE)
			if _hit_current(point) == i: return point
	for row in range(1, 12):
		for column in range(1, 12):
			var point = transform * (LOCAL_SIZE * Vector2(float(column), float(row)) / 12.0)
			if _hit_current(point) == i: return point
	return Vector2.INF

func draw():
	sync()
	var area: Rect2 = game.hand_area()
	var border = game.THEME.BORDER.darkened(0.35)
	if _discard_time > 0.0: border = border.lerp(game.THEME.DANGER, sin((_discard_time / DISCARD_PULSE_SECONDS) * PI) * 0.85)
	game.panel(area, game.THEME.BACKGROUND, border)
	for i in _order: _draw_visual_card(i, _visual_transform(i), 0.62 if _is_free(i) and game.phase == "discard" else 1.0)
	game.draw_set_transform_matrix(Transform2D.IDENTITY)

func _tint(color: Color, alpha: float) -> Color:
	color.a *= alpha
	return color

func _wrapped(text: String, width: float, font_size: int) -> Array:
	var lines: Array = []
	var line = ""
	for character in text:
		if character == "\n":
			lines.append(line)
			line = ""
		elif not line.is_empty() and game.FONT.get_string_size(line + character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			lines.append(line)
			line = character
		else: line += character
	if not line.is_empty(): lines.append(line)
	return lines

func _flow_lines(text: String, narrow_width: float, wide_width: float, font_size: int, full_from: int) -> Array:
	var lines: Array = []
	var line = ""
	for character in text:
		var allowed = narrow_width if lines.size() < full_from else wide_width
		if character == "\n":
			lines.append(line);line = ""
		elif not line.is_empty() and game.FONT.get_string_size(line + character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > allowed:
			lines.append(line);line = character
		else: line += character
	if not line.is_empty(): lines.append(line)
	return lines

func _visual_text_layout(i: int, dimensions: Vector2, focused: bool) -> Dictionary:
	var data: Array = _data(i)
	var large = dimensions.x >= 165.0 and dimensions.y >= 210.0
	var body_left = 40.0 if large else 30.0
	var start_y = 52.0 if large else 43.0
	var name_bottom = (50.0 if large else 44.0) + float(str(data[0]).length() - 1) * (26.0 if large else 20.0) + 4.0
	var text: String = str(data[4]) if focused and data.size() > 4 else str(data[2])
	if focused and _consumable(i) and not text.contains("下关恢复"): text += "\n消耗：使用后本关移除，下关恢复。"
	var font_size = 18 if large else 14
	var lines: Array = []
	var full_from = 0
	var available_lines = 1
	while true:
		var line_height = float(font_size + 2)
		full_from = maxi(0, ceili((name_bottom + float(font_size) + 3.0 - start_y) / line_height)) if focused else 999
		lines = _flow_lines(text, dimensions.x - body_left - 8.0, dimensions.x - 12.0, font_size, full_from)
		available_lines = maxi(1, int((dimensions.y - 10.0 - start_y) / line_height) + 1)
		if lines.size() <= available_lines or font_size <= 12: break
		font_size -= 1
	return {"lines": lines, "font_size": font_size, "line_height": font_size + 2, 
		"start_y": start_y, "full_from": full_from, "body_left": body_left, 
		"available_lines": available_lines, "complete": lines.size() <= available_lines, "large": large}

func _draw_visual_card(i: int, transform: Transform2D, alpha: float = 1.0):
	if not _valid(i): return
	var data: Array = _data(i)
	var uid = int(_uids()[i])
	var view: Dictionary = views.get(uid, {"birth": 1.0, "focus": 0.0})
	var width = transform.x.length() * LOCAL_SIZE.x
	var height = transform.y.length() * LOCAL_SIZE.y


	var physical = Transform2D(transform.x.normalized(), transform.y.normalized(), transform.origin)
	game.draw_set_transform_matrix(physical)
	var rect = Rect2(Vector2.ZERO, Vector2(width, height))
	var focused = i == _active_focus()
	var chosen = i == _selected_index()
	game.panel(Rect2(Vector2(2, 3), rect.size), _tint(game.THEME.SHADOW, alpha * 0.65))
	if float(view.birth) < 0.5 and not bool(view.get("free", false)):
		game.panel(rect, _tint(game.THEME.CARD_BACK, alpha), _tint(game.GOLD, alpha))
		if width > 36:
			game.panel(rect.grow(-6), Color.TRANSPARENT, _tint(game.THEME.BORDER, alpha))
			game.text_at(Vector2(width * 0.5 - 14, height * 0.5 + 10), "弈", 28, _tint(game.THEME.LIGHT, alpha))
		game.draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	game.panel(rect, _tint(game.THEME.PAPER_SELECTED if chosen else game.THEME.PAPER, alpha), 
		_tint(game.GOLD if focused else game.THEME.BORDER, alpha))
	if width < 28:
		game.draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	var large = width >= 165.0 and height >= 210.0
	var name: String = str(data[0])
	var name_size = 22 if large else 17
	var name_y = 50.0 if large else 44.0
	var name_step = 26.0 if large else 20.0
	var name_bottom = name_y + float(name.length() - 1) * name_step + 4.0
	var rail_width = 33.0 if large else 25.0
	game.panel(Rect2(3, 4, rail_width, minf(height - 8.0, name_bottom + 7.0)), _tint(game.THEME.PAPER.lerp(game.THEME.BORDER, 0.16), alpha))
	var badge_x = 19.0 if large else 15.5
	game.draw_circle(Vector2(badge_x, 19.0 if large else 17.0), 13.0 if large else 10.5, _tint(game.GOLD, alpha))
	game.text_at(Vector2(badge_x - (6.0 if large else 4.5), 25.0 if large else 22.0), str(data[1]), 18 if large else 15, _tint(game.THEME.LIGHT, alpha))
	for j in name.length():
		game.text_at(Vector2(7, name_y + j * name_step), name.substr(j, 1), name_size, _tint(game.THEME.INK, alpha))
	if width >= 76:
		var layout = _visual_text_layout(i, Vector2(width, height), focused)
		game.text_at(Vector2(layout.body_left, 28.0 if large else 23.0), {"攻": "攻击", "移": "移动", "术": "术法"}.get(str(data[3]), str(data[3])), 18 if large else 14, _tint(game.THEME.SAFE, alpha))
		if _consumable(i) and width >= 110:
			var tag_size = 14 if large else 12
			var tag_width = float(tag_size * 2 + 8)
			var tag_y = 10.0 if large else 8.0
			game.panel(Rect2(width - tag_width - 5, tag_y, tag_width, tag_size + 6), _tint(game.THEME.DANGER, alpha))
			game.text_at(Vector2(width - tag_width - 1, tag_y + tag_size + 1), "消耗", tag_size, _tint(game.THEME.LIGHT, alpha))
		var show_lines = mini(layout.lines.size(), int(layout.available_lines))
		for line_index in show_lines:
			var line: String = str(layout.lines[line_index])
			var left = layout.body_left if line_index < int(layout.full_from) else 6.0
			var body_width = width - float(left) - (8.0 if line_index < int(layout.full_from) else 6.0)
			if line_index == show_lines - 1 and layout.lines.size() > show_lines:
				while not line.is_empty() and game.FONT.get_string_size(line + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, int(layout.font_size)).x > body_width: line = line.substr(0, line.length() - 1)
				line += "…"
			game.text_at(Vector2(left, float(layout.start_y) + line_index * float(layout.line_height)), line, int(layout.font_size), _tint(game.INK, alpha))
	game.draw_set_transform_matrix(Transform2D.IDENTITY)
