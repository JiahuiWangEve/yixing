extends RefCounted



static func card_point(game, index: int) -> Vector2:
	game.sync_hand_views()
	var bounds: Rect2 = game.hand_visual_rect(index)
	var center: Vector2 = bounds.get_center()
	if game.hand_hit_index(center) == index:
		return center
	for y in range(int(bounds.position.y) + 2, int(bounds.end.y) - 1, 3):
		for x in range(int(bounds.position.x) + 2, int(bounds.end.x) - 1, 3):
			var point = Vector2(x, y)
			if game.hand_hit_index(point) == index:
				return point
	push_error("No exposed hit point for hand card " + str(index))
	return center

static func free_point(game) -> Vector2:
	game.sync_hand_views()
	var bounds: Rect2 = game.handui.free_bounds()
	var center: Vector2 = bounds.get_center()
	if game.hand_hit_index(center) == -2: return center
	for y in range(int(bounds.position.y) + 2, int(bounds.end.y) - 1, 3):
		for x in range(int(bounds.position.x) + 2, int(bounds.end.x) - 1, 3):
			var point = Vector2(x, y)
			if game.hand_hit_index(point) == -2: return point
	push_error("No exposed hit point for the visible free fan card")
	return center
