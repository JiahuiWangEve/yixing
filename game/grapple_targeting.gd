extends RefCounted
# A hook selects a stable occupied anchor before a distinct empty landing.
# Only _commit calls the ordinary card transaction; previews never spend/draw.
const R = preload("res://rules.gd")
const CARD = "grappling_hook"
const INVALID = Vector2i(-1, -1)
var game
var active = false
var committing = false
var card_uid = -1
var anchor_uid = -1
var anchor_cell = INVALID
var origin_cell = INVALID
var source_turn = -1

func _init(owner): game = owner

static func landing_candidates(origin: Vector2i, anchor: Vector2i, pieces: Array) -> Array:
	var result: Array = []
	var delta = origin - anchor
	if not R.inside(origin) or not R.inside(anchor) or origin == anchor: return result
	if maxi(absi(delta.x), absi(delta.y)) > 2 or R.occupied(anchor, pieces) < 0: return result
	var direction = Vector2i(signi(delta.x), signi(delta.y))
	var candidates: Array = [anchor + direction]
	if direction.x != 0 and direction.y != 0:
		candidates = [anchor + Vector2i(direction.x, 0), anchor + Vector2i(0, direction.y), anchor + direction]
	for cell in candidates:
		if R.inside(cell) and cell != origin and R.occupied(cell, pieces) < 0: result.append(cell)
	return result

func cancel():
	active = false;committing = false;card_uid = -1;anchor_uid = -1
	anchor_cell = INVALID;origin_cell = INVALID;source_turn = -1

func instruction() -> String:
	return "钩爪：点高亮空格落下；点选中的牌可取消。" if active else "钩爪：点2格内棋子，再选朝向自己的空格。"

func _ready(index: int) -> bool:
	return game.screen == "game" and game.phase == "play" and not game.recovery_active() and game.input_lock <= 0 and game.navigation_lock <= 0 and not game.card_picker.active and not game.presentation.active() and not game.encounter_info_open and index >= 0 and index < game.hand.size() and game.hand[index] == CARD and game.energy >= game.card_cost(CARD)

func _anchor_index(cell: Vector2i) -> int:
	if not R.inside(cell) or cell == game.player: return -1
	var index = R.occupied(cell, game.enemies)
	if index < 0 or int(game.enemies[index].get("uid", -1)) < 0: return -1
	return index if not landing_candidates(game.player, cell, game.enemies).is_empty() else -1

func legal_anchor(cell: Vector2i) -> bool:
	return _anchor_index(cell) >= 0

func _pending_valid() -> bool:
	if not active or game.turn != source_turn or game.player != origin_cell: return false
	var index: int = game.hand_ids.find(card_uid)
	if not _ready(index) or game.selected != index or game.free_selected: return false
	var anchor_index = _anchor_index(anchor_cell)
	return anchor_index >= 0 and int(game.enemies[anchor_index].get("uid", -1)) == anchor_uid

func tick():
	if active and not _pending_valid(): cancel()

func legal_target(cell: Vector2i) -> bool:
	# Do not silently turn a stale second-stage choice into a new anchor.
	if active:
		return _pending_valid() and cell in landing_candidates(origin_cell, anchor_cell, game.enemies)
	return legal_anchor(cell)

func can_commit(index: int, landing: Vector2i) -> bool:
	return committing and _ready(index) and index < game.hand_ids.size() and game.hand_ids[index] == card_uid and _pending_valid() and landing in landing_candidates(origin_cell, anchor_cell, game.enemies) and game.board_info._tutorial_allows_preview(index, landing)

func choose(index: int, cell: Vector2i) -> bool:
	if active:
		if not _pending_valid() or index >= game.hand_ids.size() or index < 0 or game.hand_ids[index] != card_uid:
			cancel();return false
		if cell not in landing_candidates(origin_cell, anchor_cell, game.enemies): return false
		return _commit(index, cell)
	if not _ready(index) or not game.board_info._tutorial_allows_preview(index, cell): return false
	var anchor_index = _anchor_index(cell)
	if anchor_index < 0: return false
	game.sync_hand_ids()
	active = true;card_uid = game.hand_ids[index];anchor_uid = int(game.enemies[anchor_index].uid)
	anchor_cell = cell;origin_cell = game.player;source_turn = game.turn
	game.selected = index;game.free_selected = false
	var choices = landing_candidates(origin_cell, anchor_cell, game.enemies)
	# Orthogonal anchors have only one geometric landing. Diagonal anchors
	# always require a second explicit click, even if blockers leave one choice.
	if anchor_cell.x == origin_cell.x or anchor_cell.y == origin_cell.y:
		return _commit(index, choices[0])
	game.notice = instruction();game.queue_redraw()
	return true

func _commit(index: int, landing: Vector2i) -> bool:
	committing = true
	if not can_commit(index, landing): cancel();return false
	game.play_card(index, landing)
	# Card use can open a modal or change the hand. Never retain a late landing.
	cancel();game.queue_redraw()
	return true

func state(index: int) -> Dictionary:
	var result = {"anchor_cells": [], "landing_cells": [], "anchor": INVALID, "instruction": instruction()}
	if not _ready(index): return result
	if active:
		if not _pending_valid() or game.hand_ids[index] != card_uid: return result
		result.anchor = anchor_cell
		for cell in landing_candidates(origin_cell, anchor_cell, game.enemies):
			if game.board_info._tutorial_allows_preview(index, cell): result.landing_cells.append(cell)
		return result
	for piece in game.enemies:
		if legal_anchor(piece.pos) and game.board_info._tutorial_allows_preview(index, piece.pos): result.anchor_cells.append(piece.pos)
	return result

func draw():
	var index: int = game.selected
	if game.gesture.dragging: index = -1 if game.gesture.free_move else game.hand_ids.find(game.gesture.uid)
	var view = state(index)
	for cell in view.anchor_cells:
		game.draw_arc(game.cell_pos(cell), game.CELL * 0.48, 0, TAU, 32, game.THEME.SAFE, 3)
	if view.anchor != INVALID:
		game.draw_arc(game.cell_pos(view.anchor), game.CELL * 0.48, 0, TAU, 32, Color(game.THEME.SAFE, 0.7), 2)
	for cell in view.landing_cells:
		var center: Vector2 = game.cell_pos(cell)
		var color: Color = game.THEME.DANGER if game.R.threatened(cell, game.enemies) else game.THEME.SAFE
		var side: float = game.CELL * 0.74
		game.draw_rect(Rect2(center - Vector2.ONE * side * 0.5, Vector2.ONE * side), Color(color, 0.12))
		game.draw_arc(center, game.CELL * 0.36, 0, TAU, 28, color, 3)
