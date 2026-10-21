extends RefCounted
# Shared, stateless card face. Battle hand and permanent-deck picker use identical ink.
const LOCAL_SIZE = Vector2(156, 156)
var game
func _init(owner): game = owner
func panel(canvas: CanvasItem, rect: Rect2, color: Color, border: Color = Color.TRANSPARENT):
	canvas.draw_style_box(game.box(color, border), rect)
func text_at(canvas: CanvasItem, point: Vector2, value: String, font_size: int, color: Color):
	canvas.draw_string(game.FONT, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
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

func text_layout(data: Array, dimensions: Vector2, focused: bool, consumable: bool) -> Dictionary:
	var large = dimensions.x >= 165.0 and dimensions.y >= 210.0
	var body_left = 40.0 if large else 30.0
	var start_y = 52.0 if large else 43.0
	var name_bottom = (50.0 if large else 44.0) + float(str(data[0]).length() - 1) * (26.0 if large else 20.0) + 4.0
	var text: String = str(data[4]) if focused and data.size() > 4 else str(data[2])
	if focused and consumable and not text.contains("下关恢复"): text += "\n消耗：使用后本关移除，下关恢复。"
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

func draw_data(canvas: CanvasItem, data: Array, consumable: bool, transform: Transform2D, alpha: float = 1.0, focused: bool = false, chosen: bool = false, view: Dictionary = {"birth": 1.0}):
	var width = transform.x.length() * LOCAL_SIZE.x
	var height = transform.y.length() * LOCAL_SIZE.y


	var physical = Transform2D(transform.x.normalized(), transform.y.normalized(), transform.origin)
	canvas.draw_set_transform_matrix(physical)
	var rect = Rect2(Vector2.ZERO, Vector2(width, height))
	panel(canvas, Rect2(Vector2(2, 3), rect.size), _tint(game.THEME.SHADOW, alpha * 0.65))
	if float(view.birth) < 0.5 and not bool(view.get("free", false)):
		panel(canvas, rect, _tint(game.THEME.CARD_BACK, alpha), _tint(game.GOLD, alpha))
		if width > 36:
			panel(canvas, rect.grow(-6), Color.TRANSPARENT, _tint(game.THEME.BORDER, alpha))
			text_at(canvas, Vector2(width * 0.5 - 14, height * 0.5 + 10), "弈", 28, _tint(game.THEME.LIGHT, alpha))
		canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	panel(canvas, rect, _tint(game.THEME.PAPER_SELECTED if chosen else game.THEME.PAPER, alpha),
		_tint(game.GOLD if focused else game.THEME.BORDER, alpha))
	if width < 28:
		canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	var large = width >= 165.0 and height >= 210.0
	var name: String = str(data[0])
	var name_size = 22 if large else 17
	var name_y = 50.0 if large else 44.0
	var name_step = 26.0 if large else 20.0
	var name_bottom = name_y + float(name.length() - 1) * name_step + 4.0
	var rail_width = 33.0 if large else 25.0
	panel(canvas, Rect2(3, 4, rail_width, minf(height - 8.0, name_bottom + 7.0)), _tint(game.THEME.PAPER.lerp(game.THEME.BORDER, 0.16), alpha))
	var badge_x = 19.0 if large else 15.5
	canvas.draw_circle(Vector2(badge_x, 19.0 if large else 17.0), 13.0 if large else 10.5, _tint(game.GOLD, alpha))
	text_at(canvas, Vector2(badge_x - (6.0 if large else 4.5), 25.0 if large else 22.0), str(data[1]), 18 if large else 15, _tint(game.THEME.LIGHT, alpha))
	for j in name.length():
		text_at(canvas, Vector2(7, name_y + j * name_step), name.substr(j, 1), name_size, _tint(game.THEME.INK, alpha))
	if width >= 76:
		var layout = text_layout(data, Vector2(width, height), focused, consumable)
		text_at(canvas, Vector2(layout.body_left, 28.0 if large else 23.0), {"攻": "攻击", "移": "移动", "术": "术法", "负": "负面"}.get(str(data[3]), str(data[3])), 18 if large else 14, _tint(game.THEME.DANGER if str(data[3]) == "负" else game.THEME.SAFE, alpha))
		if consumable and width >= 110:
			var tag_size = 14 if large else 12
			var tag_width = float(tag_size * 2 + 8)
			var tag_y = 10.0 if large else 8.0
			panel(canvas, Rect2(width - tag_width - 5, tag_y, tag_width, tag_size + 6), _tint(game.THEME.DANGER, alpha))
			text_at(canvas, Vector2(width - tag_width - 1, tag_y + tag_size + 1), "消耗", tag_size, _tint(game.THEME.LIGHT, alpha))
		var show_lines = mini(layout.lines.size(), int(layout.available_lines))
		for line_index in show_lines:
			var line: String = str(layout.lines[line_index])
			var left = layout.body_left if line_index < int(layout.full_from) else 6.0
			var body_width = width - float(left) - (8.0 if line_index < int(layout.full_from) else 6.0)
			if line_index == show_lines - 1 and layout.lines.size() > show_lines:
				while not line.is_empty() and game.FONT.get_string_size(line + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, int(layout.font_size)).x > body_width: line = line.substr(0, line.length() - 1)
				line += "…"
			text_at(canvas, Vector2(left, float(layout.start_y) + line_index * float(layout.line_height)), line, int(layout.font_size), _tint(game.INK, alpha))
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
