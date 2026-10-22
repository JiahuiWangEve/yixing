extends RefCounted
const R = preload("res://rules.gd")
const IDS = ["stake", "permanent_stake", "pierce", "pursuit", "shock", "breath", "advance", "retreat_strike", "knight_assault", "chain_assault"]
static func enemy_target(game, p: Vector2i) -> bool:
	var i = R.occupied(p, game.enemies)
	return i >= 0 and game.enemies[i].kind != "stake"
static func legal(game, id: String, p: Vector2i) -> bool:
	if not R.inside(p): return false
	var distance = absi(p.x - game.player.x) + absi(p.y - game.player.y)
	match id:
		"stake", "permanent_stake": return distance > 0 and distance <= 2 and R.occupied(p, game.enemies) < 0
		"pierce", "pursuit": return distance == 1 and enemy_target(game, p)
		"shock": return distance > 0 and distance <= 2 and enemy_target(game, p)
		"chain_assault": return distance > 0 and absi(p.x - game.player.x) <= 1 and absi(p.y - game.player.y) <= 1 and enemy_target(game, p)
		"advance": return distance == 1 and enemy_target(game, p)
		"retreat_strike":
			var dest = game.player - (p - game.player)
			return distance == 1 and enemy_target(game, p) and R.inside(dest) and R.occupied(dest, game.enemies) < 0
		"knight_assault":
			var d: Vector2i = p - game.player
			if not enemy_target(game, p) or not ((absi(d.x) == 2 and absi(d.y) == 1) or (absi(d.x) == 1 and absi(d.y) == 2)): return false
			var leg = game.player + Vector2i(signi(d.x) if absi(d.x) == 2 else 0, signi(d.y) if absi(d.y) == 2 else 0)
			return R.occupied(leg, game.enemies) < 0
		"breath": return true
	return false
static func attack_danger(game, id: String, target: Vector2i) -> bool:
	var board = game.enemies.duplicate(true)
	var i = R.occupied(target, board)
	if i < 0: return false
	var damage = 2 if id == "knight_assault" else 1
	var killed = int(board[i].get("hp", game.enemy_health(board[i].kind))) <= damage
	if killed: board.remove_at(i)
	else: board[i].hp -= damage
	var destination: Vector2i = game.player
	if id == "retreat_strike": destination = game.player - (target - game.player)
	elif killed: destination = target
	return R.threatened(destination, board)
static func apply(game, id: String, p: Vector2i, index: int):
	match id:
		"advance", "knight_assault", "retreat_strike":
			var origin: Vector2i = game.player
			if id == "retreat_strike":
				game.player = origin - (p - origin)
				game.move_piece({}, game.cell_pos(origin), game.cell_pos(game.player))
			game.effect("sword", game.cell_pos(game.player), game.cell_pos(p), 0.3, 0.28 if id == "retreat_strike" else 0.0)
			var killed: bool = game.damage_enemy(index, 0.4 if id == "retreat_strike" else 0.12, 2 if id == "knight_assault" else 1)
			if killed and id != "retreat_strike":
				game.player = p
				game.move_piece({}, game.cell_pos(origin), game.cell_pos(p), 0.2, id == "knight_assault")
			if game.player != origin: game.record_active_displacement(origin)
		"stake", "permanent_stake":
			game.add_enemy("stake", p, 0)
			if id == "permanent_stake": game.enemies.back()["permanent"] = true
			else: game.enemies.back()["ttl"] = 3
			game.effect("stake_place", game.cell_pos(p), game.cell_pos(p), 0.3)
		"pierce":
			game.effect("spear", game.cell_pos(game.player), game.cell_pos(p), 0.3)
			game.queue_bleed(index, 2)
		"chain_assault":
			game.effect("sword", game.cell_pos(game.player), game.cell_pos(p), 0.3)
			game.damage_enemy(index, 0.12, 1 + int(game.active_displacements))
		"pursuit":
			game.effect("sword", game.cell_pos(game.player), game.cell_pos(p), 0.3)
			if game.damage_enemy(index): game.draw_card()
		"shock":
			var victim: Dictionary = game.enemies[index]
			game.effect("sword", game.cell_pos(game.player), game.cell_pos(p), 0.3)
			if not game.damage_enemy(index):
				var direction = Vector2i(signi(p.x - game.player.x), signi(p.y - game.player.y))
				var destination = p + direction
				if R.inside(destination) and R.occupied(destination, game.enemies) < 0 and destination != game.player:
					victim.pos = destination
					game.effect("push", game.cell_pos(game.player), game.cell_pos(p), 0.2, 0.2)
					game.move_piece(victim, game.cell_pos(p), game.cell_pos(destination), 0.2)
		"breath":
			game.energy += 1
			game.effect("breath", game.cell_pos(game.player), game.cell_pos(game.player), 0.35)
static func expire_stakes(game, timeline: float):
	for i in range(game.enemies.size() - 1, -1, -1):
		var piece: Dictionary = game.enemies[i]
		if piece.kind != "stake" or bool(piece.get("permanent", false)): continue
		piece.ttl = int(piece.get("ttl", 3)) - 1
		if piece.ttl <= 0:
			game.effect("stake_expire", game.cell_pos(piece.pos), game.cell_pos(piece.pos), 0.18, timeline)
			game.enemies.remove_at(i)
