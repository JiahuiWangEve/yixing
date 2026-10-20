extends RefCounted

var game
func _init(owner): game = owner
func visible() -> bool: return game.handui._has_free()
func title() -> String:
	if game.player_skill == "artillery": return "炮步" if game.artillery_mode == "attack" else "行军"
	return "马步" if game.player_skill == "horse" else "帅步"
func description() -> String: return str(game.handui._data(0)[2]) if visible() else ""
func bounds() -> Rect2: return game.handui.free_bounds()
func hit_test(position: Vector2) -> bool: return game.handui.free_hit(position)
func draw(): pass
func draw_card(rect: Rect2, alpha: float = 1.0):
	var size = game.handui.card_size()
	var transform = Transform2D(Vector2(rect.size.x / size.x, 0), Vector2(0, rect.size.y / size.y), rect.position)
	game.handui.free_draw(transform, alpha)
