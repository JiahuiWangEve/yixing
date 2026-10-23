extends RefCounted
# Legality, preview and committed damage share this immutable action plan.
# Payment, hand-copy identity and undo snapshots are owned by main.
const R = preload("res://rules.gd")
const E = preload("res://encounters.gd")
const IDS = ["blood_edge", "blood_break", "last_stand"]
const DIRECTIONS = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

static func direction(origin: Vector2i, target: Vector2i) -> Vector2i:
	if not R.inside(target): return Vector2i.ZERO
	var delta = target - origin
	var distance = absi(delta.x) + absi(delta.y)
	if distance < 1 or distance > 3 or (delta.x != 0 and delta.y != 0): return Vector2i.ZERO
	return Vector2i(signi(delta.x), signi(delta.y))

static func cells(game, id: String, target: Vector2i) -> Array:
	var result: Array = []
	if id not in IDS or not R.inside(target): return result
	match id:
		"blood_edge":
			var step = direction(game.player, target)
			if step == Vector2i.ZERO: return result
			for distance in range(1, 4):
				var cell: Vector2i = game.player + step * distance
				if R.inside(cell): result.append(cell)
		"blood_break":
			for step in DIRECTIONS:
				for distance in range(1, 3):
					var cell: Vector2i = game.player + step * distance
					if R.inside(cell): result.append(cell)
		"last_stand":
			var delta: Vector2i = target - game.player
			if absi(delta.x) + absi(delta.y) == 1: result.append(target)
	return result

static func _targets_in_cells(game, area: Array) -> Array:
	var result: Array = []
	for enemy in game.enemies:
		# Like sweep, stakes neither enable the attack nor take damage. They
		# also do not block these attacks: every occupied range cell is pierced.
		if enemy.kind not in ["stake", "decoy"] and enemy.pos in area: result.append(enemy)
	return result

static func targets(game, id: String, target: Vector2i) -> Array:
	return _targets_in_cells(game, cells(game, id, target))

static func amount(game, id: String) -> int:
	match id:
		"blood_edge": return 2
		"blood_break": return 3
		"last_stand": return 3 if game.lives == 1 else 1
	return 0

static func self_cost(id: String) -> int:
	return 1 if id in ["blood_edge", "blood_break"] else 0

static func plan(game, id: String, target: Vector2i) -> Dictionary:
	var area = cells(game, id, target)
	var victims = _targets_in_cells(game, area)
	var cost = self_cost(id)
	return {"card": id, "target": target, "cells": area, "targets": victims,
		"amount": amount(game, id), "self_cost": cost,
		"self_defeat": game.self_cost_is_lethal(cost),
		"legal": id in IDS and game.player_skill == "king" and game.lives > 0 and not victims.is_empty()}

static func legal(game, id: String, target: Vector2i) -> bool:
	return bool(plan(game, id, target).legal)

static func preview(game, id: String, target: Vector2i) -> Dictionary:
	var state = plan(game, id, target)
	if not state.legal: return {}
	var affected: Array = [];var lines: Array = [];var general_down = false
	for enemy in state.targets:
		if enemy.kind == "g" and state.amount >= int(enemy.get("hp", game.enemy_health(enemy.kind))): general_down = true
	for enemy in state.targets:
		var hp = int(enemy.get("hp", game.enemy_health(enemy.kind)))
		var down: bool = state.amount >= hp
		affected.append({"uid": enemy.uid, "pos": enemy.pos, "damage": state.amount, "hp_before": hp,
			"hp_after": maxi(0, hp - state.amount), "down": down, "delayed": false, "unyielding": enemy.get("unyielding", false)})
		var revival = "（不屈，之后可复归）" if down and enemy.get("unyielding", false) and not general_down and not state.self_defeat else ""
		lines.append("%s：%d伤 → %s%s。" % [game.piece_name(enemy.kind), state.amount, "击倒" if down else "剩余%d血" % (hp - state.amount), revival])
	if state.self_cost > 0:
		lines.append("自身扣1命：%s；护盾不抵消自损、不撤退、不跳过回合。" % ("生命归零，直接失败，优先于敌将击倒与凯旋" if state.self_defeat else ("替命金符触发，保留1命" if game.lives <= state.self_cost and game.treasures.rescue_ready() else "剩余%d命" % (game.lives - state.self_cost))))
	elif id == "last_stand":
		lines.append("出牌时恰好1命，造成3伤。" if game.lives == 1 else "出牌时不是1命，造成1伤。")
	return {"card": id, "target": target, "affected": affected, "lines": lines,
		"self_damage": state.self_cost, "self_defeat": state.self_defeat}

static func apply(game, id: String, target: Vector2i) -> bool:
	var state = plan(game, id, target)
	if not state.legal: return false
	# Direct life debit follows airdrop: guard and recoil hooks never run.
	# Still damage all victims, then signal main to stop before victory/healing.
	game.lose_lives(state.self_cost)
	for index in range(game.enemies.size() - 1, -1, -1):
		if game.enemies[index] not in state.targets: continue
		game.effect("spear" if id == "blood_edge" else "sword", game.cell_pos(game.player), game.cell_pos(game.enemies[index].pos), 0.3)
		game.damage_enemy(index, 0.12, state.amount)
	if state.self_defeat:
		game.phase = "dead";game.clear_battle_card_effects();E.cancel_pending(game)
		game.notice = "%s自损，命数耗尽。" % ("血锋" if id == "blood_edge" else "浴血破阵")
		game.log_line(game.notice)
		return true
	if state.self_cost > 0:
		game.notice = "%s完成：扣1命，不移动，不跳过回合。" % ("血锋" if id == "blood_edge" else "浴血破阵")
	return false
