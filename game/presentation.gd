extends RefCounted
const Palette = preload("res://palette.gd")
# Presentation only: callers commit and save first. Never grants rewards or rerolls.
const SEAL = preload("res://assets/map/seals/victory_seal.svg")
var game
var face
var kind = ""
var elapsed = 0.0
var old_id = ""
var new_id = ""
var card_index = -1
var context_screen = ""
var context_phase = ""
func _init(owner):
	game = owner;face = preload("res://card_face.gd").new(owner)
func active() -> bool: return not kind.is_empty()
func clear():
	kind = "";elapsed = 0;game.queue_redraw()
func start(effect: String):
	game.cancel_gesture();game.route.cancel_pointer()
	kind = effect;elapsed = 0;context_screen = game.screen;context_phase = game.phase;game.queue_redraw()
func victory():
	if game.lives <= 0: return
	start("victory")
func upgrade(before: String, after: String, index: int):
	old_id = before;new_id = after;card_index = index;start("upgrade")
func tick(delta: float):
	if not active(): return
	if game.screen != context_screen or game.phase != context_phase: clear();return
	elapsed += maxf(0, delta)
	if kind == "victory" and elapsed >= 1.05: clear()
	elif kind == "upgrade" and elapsed >= 2.0: clear()
	game.queue_redraw()
func input_event(event) -> bool:
	if not active(): return false
	if game.screen != context_screen or game.phase != context_phase: clear();return false
	# Keep both reading windows intact; only the two-second timer dismisses.
	return true
func draw():
	if not active(): return
	game.draw_rect(Rect2(Vector2.ZERO, game.ui_size), Color(Palette.PAPER, 0.98))
	var center = game.ui_size * 0.5
	if kind == "victory":
		# A short hold precedes the descending red general's seal.
		if elapsed < 0.16: return
		var progress = clampf((elapsed - 0.16) / 0.28, 0, 1)
		var side = minf(260, minf(game.ui_size.x, game.ui_size.y) * 0.5)
		var scale = 1.0 + 0.65 * pow(1.0 - progress, 3)
		var tint = Color.WHITE;tint.a = minf(1, progress * 3)
		game.draw_set_transform(center, -0.13, Vector2.ONE * scale)
		game.draw_texture_rect(SEAL, Rect2(Vector2.ONE * -side * 0.5, Vector2.ONE * side), false, tint)
		game.draw_set_transform(Vector2.ZERO)
		return
	var dimensions = Vector2(260,310)
	if game.compact_landscape: dimensions = Vector2(220,270)
	var progress = clampf((elapsed - 0.6) / 0.45, 0, 1)
	var id = old_id if progress < 0.5 else new_id
	var scale_x = maxf(0.035, absf(cos(progress * PI)))
	var position = center - dimensions * 0.5
	var transform = Transform2D(Vector2(dimensions.x * scale_x / 156,0),Vector2(0,dimensions.y / 156),center - Vector2(dimensions.x * scale_x * 0.5,dimensions.y * 0.5))
	face.draw_data(game, game.descriptions.data(id), game.is_consumable(id), transform, 1, false, progress >= 0.5)
	if progress > 0.5 and progress < 1:
		game.draw_rect(Rect2(position, dimensions).grow(5), Color(Palette.ACCENT, sin((progress-0.5)*PI*2)), false, 4)
	var title = "兵书 · 口诀领悟" if progress < 0.5 else "强化完成 · " + game.CARDS[new_id][0]
	var width = game.FONT.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,24).x
	game.text_at(Vector2(center.x-width*0.5, position.y-24), title,24,game.THEME.HEADING)
	var label = "第%d张 · %s" % [card_index+1, "伤害与效果已更新" if progress >= 0.5 else "被选中的永久牌"]
	game.text_at(Vector2(center.x-120,position.y+dimensions.y+30),label,18,game.THEME.LIGHT)
	if elapsed >= 1.05: game.text_at(Vector2(center.x-115,position.y+dimensions.y+58),"强化完成 · 稍后自动返回",17,game.THEME.LIGHT)
