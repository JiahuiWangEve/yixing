extends RefCounted
const R = preload("res://rules.gd")
const IDS = ["stake", "pierce", "pursuit", "shock", "breath", "swap"]
static func enemy_target(game, p: Vector2i) -> bool:
	var i = R.occupied(p, game.enemies)
	return i >= 0 and game.enemies[i].kind != "stake"
static func legal(game, id: String, p: Vector2i) -> bool:
	if not R.inside(p): return false
	var distance = absi(p.x - game.player.x) + absi(p.y - game.player.y)
	match id:
		"stake": return distance > 0 and distance <= 2 and R.occupied(p, game.enemies) < 0
		"pierce", "pursuit", "shock": return distance == 1 and enemy_target(game, p)
		"breath": return true
		"swap":
			var i = R.occupied(p, game.enemies)
			return distance == 1 and enemy_target(game, p) and game.enemies[i].kind != "g" and not game.card_move_used
	return false
static func swap_danger(game, target: Vector2i) -> bool:
	var board = game.enemies.duplicate(true)
	var i = R.occupied(target, board)
	if i < 0: return false
	board[i].pos = game.player
	return R.threatened(target, board)
static func apply(game, id: String, p: Vector2i, index: int):
	match id:
		"stake":
			game.enemies.append({"kind": "stake", "pos": p, "visual": game.cell_pos(p), "cd": 0, "period": 0, "stun": 0, "ttl": 3})
			game.effect("stake_place", game.cell_pos(p), game.cell_pos(p), 0.3)
		"pierce":
			game.effect("spear", game.cell_pos(game.player), game.cell_pos(p), 0.3)
			game.damage_enemy(index, 0.12, 2)
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
		"swap":
			var victim: Dictionary = game.enemies[index]
			var origin: Vector2i = game.player
			victim.pos = origin;game.player = p;game.card_move_used = true
			game.move_piece({}, game.cell_pos(origin), game.cell_pos(p), 0, true)
			game.move_piece(victim, game.cell_pos(p), game.cell_pos(origin), 0.1, true)
			game.draw_card()
static func expire_stakes(game, timeline: float):
	for i in range(game.enemies.size() - 1, -1, -1):
		var piece: Dictionary = game.enemies[i]
		if piece.kind != "stake": continue
		piece.ttl = int(piece.get("ttl", 3)) - 1
		if piece.ttl <= 0:
			game.effect("stake_expire", game.cell_pos(piece.pos), game.cell_pos(piece.pos), 0.18, timeline)
			game.enemies.remove_at(i)
