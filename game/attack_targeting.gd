extends RefCounted
# Read-only action choices, separate from damage previews and committed effects.
# A choice is a victim, a self-centred action, a direction, or an explicit landing.
const R = preload("res://rules.gd")
const INVALID = Vector2i(-1, -1)
var game

func _init(owner): game = owner

func is_attack(id: String) -> bool:
	return game.CARDS.has(id) and game.CARDS[id][3] == "攻"

func _ready(index: int) -> bool:
	return game.screen == "game" and game.phase == "play" and not game.recovery_active() and game.input_lock <= 0 and game.navigation_lock <= 0 and not game.card_picker.active and not game.presentation.active() and not game.encounter_info_open and index >= 0 and index < game.hand.size() and is_attack(game.hand[index])

func _legal(index: int, target: Vector2i) -> bool:
	# tutorial.allows() captures state. Only its existing read-only counterpart
	# belongs in range queries, drag previews, or action enumeration.
	return game.can_commit_card(index, target) and game.board_info._tutorial_allows_preview(index, target)

func _mode(id: String) -> String:
	if id == "airdrop": return "landing"
	if id == "blood_edge": return "direction"
	if id in ["sweep", "blood_break"]: return "self_aoe"
	return "single"

func _append_enemy(result: Dictionary, enemy: Dictionary):
	if enemy.kind in ["stake", "decoy"] or enemy.pos in result.enemy_cells: return
	result.enemy_cells.append(enemy.pos)
	result.enemy_uids.append(enemy.uid)

func _append_cells(result: Dictionary, cells: Array):
	for cell in cells:
		if cell not in result.range_cells: result.range_cells.append(cell)

func state(index: int) -> Dictionary:
	var result = {"index": index, "card": "", "mode": "", "range_cells": [], "target_cells": [], "enemy_cells": [], "enemy_uids": [], "actions": [], "auto_target": INVALID}
	if index < 0 or index >= game.hand.size() or not is_attack(game.hand[index]): return result
	var id: String = game.hand[index]
	result.card = id;result.mode = _mode(id)
	if not _ready(index): return result
	match result.mode:
		"single":
			for enemy in game.enemies:
				if enemy.kind in ["stake", "decoy"] or not _legal(index, enemy.pos): continue
				result.target_cells.append(enemy.pos)
				result.actions.append({"target": enemy.pos, "enemy_uid": enemy.uid})
				_append_enemy(result, enemy)
			# Empty geometry is not advertised as an available attack when there
			# is no eligible enemy, insufficient energy, or a tutorial restriction.
			if not result.actions.is_empty():
				for y in 10:
					for x in 9:
						var cell = Vector2i(x, y)
						if _in_range(id, cell) and game.board_info._tutorial_allows_preview(index, cell): result.range_cells.append(cell)
		"self_aoe":
			if _legal(index, game.player):
				result.target_cells.append(game.player)
				result.actions.append({"target": game.player})
				if id == "blood_break":
					_append_cells(result, game.KING_BLOOD.cells(game, id, game.player))
					for enemy in game.KING_BLOOD.targets(game, id, game.player): _append_enemy(result, enemy)
				else:
					for y in range(game.player.y - 1, game.player.y + 2):
						for x in range(game.player.x - 1, game.player.x + 2):
							var cell = Vector2i(x, y)
							if R.inside(cell) and game.in_neighbor_square(cell): result.range_cells.append(cell)
					for enemy in game.enemies:
						if game.in_neighbor_square(enemy.pos): _append_enemy(result, enemy)
		"direction":
			for direction in game.KING_BLOOD.DIRECTIONS:
				var anchor = INVALID
				for distance in range(1, 4):
					var cell: Vector2i = game.player + direction * distance
					if not R.inside(cell) or not _legal(index, cell): continue
					result.target_cells.append(cell)
					if anchor == INVALID: anchor = cell
				if anchor == INVALID: continue
				result.actions.append({"target": anchor, "direction": direction})
				_append_cells(result, game.KING_BLOOD.cells(game, id, anchor))
				for enemy in game.KING_BLOOD.targets(game, id, anchor): _append_enemy(result, enemy)
		"landing":
			# Landing choices are not an attack range and are never auto-picked,
			# even if the board happens to have only one legal empty cell.
			for y in 10:
				for x in 9:
					var cell = Vector2i(x, y)
					if _legal(index, cell):
						result.target_cells.append(cell)
						result.actions.append({"target": cell})
	if result.mode != "landing" and result.actions.size() == 1:
		result.auto_target = result.actions[0].target
	return result

func resolve_release(index: int, cell: Vector2i, explicit_aim: bool) -> Vector2i:
	if not _ready(index): return INVALID
	var id: String = game.hand[index]
	var mode = _mode(id)
	if mode == "self_aoe": return game.player if _legal(index, game.player) else INVALID
	if explicit_aim:
		# Never fall back from an invalid victim, direction, or landing to a
		# different action, even if exactly one other legal action exists.
		return cell if R.inside(cell) and _legal(index, cell) else INVALID
	if mode == "landing": return INVALID
	return state(index).auto_target

func _in_range(id: String, cell: Vector2i) -> bool:
	# Geometry mirrors the existing rules, without inventing hypothetical
	# victims or editing the board to make card_legal accept an empty square.
	if not R.inside(cell) or cell == game.player: return false
	var occupied = R.occupied(cell, game.enemies)
	if occupied >= 0 and game.enemies[occupied].kind in ["stake", "decoy"]: return false
	var delta: Vector2i = cell - game.player
	var distance = absi(delta.x) + absi(delta.y)
	match id.trim_suffix("_plus"):
		"sword", "pierce", "pursuit", "advance", "last_stand": return distance == 1
		"diagonal": return absi(delta.x) == 1 and absi(delta.y) == 1
		"spear": return distance <= 2 and R.blockers(game.player, cell, game.enemies) == 0
		"cannon", "cannon_shot": return R.blockers(game.player, cell, game.enemies) == 1
		"shock": return distance <= 2
		"chain_assault": return absi(delta.x) <= 1 and absi(delta.y) <= 1
		"retreat_strike":
			var retreat: Vector2i = game.player - delta
			return distance == 1 and R.inside(retreat) and R.occupied(retreat, game.enemies) < 0
		"knight_assault":
			if not ((absi(delta.x) == 2 and absi(delta.y) == 1) or (absi(delta.x) == 1 and absi(delta.y) == 2)): return false
			var leg: Vector2i = game.player + Vector2i(signi(delta.x) if absi(delta.x) == 2 else 0, signi(delta.y) if absi(delta.y) == 2 else 0)
			return R.occupied(leg, game.enemies) < 0
	return false
