extends RefCounted

var game
func _init(owner): game = owner
func visible() -> bool: return game.handui._has_free()
# Pure shared data: the battle hand and read-only catalog must show the same cards.
static func data_for(identity: String, stance: String = "march") -> Array:
	if identity == "artillery":
		if stance == "attack": return ["炮步", 0, "攻击姿态：免费正交走1格，移动抽1张；每回合一次", "移"]
		return ["行军", 0, "免费正交走1–2格，不穿透；每回合1次，移动抽1张", "移"]
	return ["马步" if identity == "horse" else "帅步", 0,
		"免费马步，遵守蹩腿；每回合1次，移动抽1张，与点格共用" if identity == "horse" else "免费正交走1格；每回合1次，移动抽1张，与点格共用", "移"]
func title() -> String: return str(data_for(game.player_skill, game.artillery_mode)[0])
func description() -> String: return str(game.handui._data(0)[2]) if visible() else ""
func bounds() -> Rect2: return game.handui.free_bounds()
func hit_test(position: Vector2) -> bool: return game.handui.free_hit(position)
func draw(): pass
func draw_card(rect: Rect2, alpha: float = 1.0):
	var size = game.handui.card_size()
	var transform = Transform2D(Vector2(rect.size.x / size.x, 0), Vector2(0, rect.size.y / size.y), rect.position)
	game.handui.free_draw(transform, alpha)
