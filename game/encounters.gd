extends RefCounted
# A generated node fixes its army and rule once. Combat state is snapshotted by undo.
const R = preload("res://rules.gd")
const TEMPLATES = {
	"three_pawns": {"name": "三卒拦路", "pieces": [["p", 2, 3], ["p", 4, 3], ["p", 6, 3]]},
	"quick_pawns": {"name": "急卒突进", "pieces": [["q", 2, 3], ["p", 4, 3], ["q", 6, 3]]},
	"single_advisor": {"name": "单士守门", "pieces": [["a", 3, 0], ["p", 2, 3], ["p", 6, 3]]},
	"double_advisors": {"name": "双士护将", "pieces": [["a", 3, 0], ["a", 5, 0], ["p", 4, 3]]},
	"elephant_gap": {"name": "象眼有隙", "pieces": [["e", 2, 0], ["p", 3, 1], ["p", 6, 3]]},
	"pawn_cannon": {"name": "卒架孤炮", "pieces": [["c", 2, 1], ["p", 2, 3], ["p", 6, 3]]},
	"river_cannon": {"name": "过河架炮", "pieces": [["c", 2, 3], ["p", 2, 4], ["p", 6, 3], ["a", 5, 0]]},
	"rook_pressure": {"name": "车卒压线", "pieces": [["r", 7, 1], ["p", 2, 3], ["p", 4, 3], ["p", 6, 3]]},
	"horse_cannon": {"name": "马后藏炮", "pieces": [["h", 2, 2], ["c", 2, 0], ["p", 6, 3], ["a", 5, 0]]},
	"palace_guard": {"name": "士象固宫", "pieces": [["a", 3, 0], ["a", 5, 0], ["e", 2, 0], ["e", 6, 0], ["p", 4, 3]]},
	"two_wings": {"name": "两翼合围", "pieces": [["h", 1, 2], ["c", 7, 1], ["p", 1, 4], ["p", 7, 4], ["a", 3, 0]]},
	"palace_final": {"name": "九宫决阵", "pieces": [["a", 3, 0], ["a", 5, 0], ["e", 2, 0], ["e", 6, 0], ["h", 1, 2], ["c", 7, 1], ["p", 4, 3]]}
}
const RULE_NAMES = {"double_step": "连步压线", "horse_relay": "援马驿站", "river_signal": "渡河急炮", "palace_rotation": "九宫轮防", "last_stand": "残阵反扑"}
const RULE_TEXT = {
	"double_step": "标记卒每第二次正常行动多走一步，不额外攻击。",
	"horse_relay": "第5、10、15轮结束后援马；提前预告，场上增援马最多2匹，堵住出生格可取消。",
	"river_signal": "旗卒过河后，从下轮起配对炮的下一次正常行动多走一步，仅一次。",
	"palace_rotation": "每轮轮到一名守军；倒计时归零行动时可多走一步。",
	"last_stand": "敌将首次受伤存活后，现存士象卒下一次行动多走一步，仅一次。"
}
const ELITES = ["river_cannon", "rook_pressure", "horse_cannon", "palace_guard", "two_wings"]
const RULE_FOR = {"river_cannon": "river_signal", "rook_pressure": "double_step", "horse_cannon": "horse_relay", "palace_guard": "palace_rotation", "two_wings": "last_stand"}

static func node_config(kind: String, row: int, random: RandomNumberGenerator) -> Dictionary:
	var id = ""
	var modifiers: Array = []
	if kind == "boss":
		id = "palace_final";modifiers = ["palace_rotation", "last_stand"]
	elif kind == "elite":
		var pool = ["river_cannon", "rook_pressure", "horse_cannon"] if row <= 2 else ELITES
		id = pool[random.randi_range(0, pool.size() - 1)];modifiers = [RULE_FOR[id]]
	elif kind == "battle":
		var pool = ["three_pawns"] if row == 0 else (["quick_pawns", "single_advisor", "double_advisors", "elephant_gap", "pawn_cannon"] if row <= 2 else ["double_advisors", "elephant_gap", "pawn_cannon", "river_cannon", "rook_pressure"])
		id = pool[random.randi_range(0, pool.size() - 1)]
	return {} if id.is_empty() else {"id": id, "tier": kind, "rules": modifiers}

static func valid_config(config) -> bool:
	if not config is Dictionary or config.get("id", "") not in TEMPLATES: return false
	if config.get("tier", "") not in ["battle", "elite", "boss"] or not config.get("rules") is Array: return false
	for rule in config.rules:
		if rule not in RULE_NAMES: return false
	if config.tier == "boss": return config.id == "palace_final" and config.rules == ["palace_rotation", "last_stand"]
	if config.tier == "elite": return config.id in ELITES and config.rules == [RULE_FOR[config.id]]
	return config.id not in ["horse_cannon", "palace_guard", "two_wings", "palace_final"] and config.rules.is_empty()

static func setup(game, config: Dictionary):
	game.encounter_state = {"config": config.duplicate(true), "phases": 0, "retaliated": false, "river_triggered": false, "signal_uid": -1, "cannon_uid": -1, "guard_uids": [], "spawn_cell": Vector2i(-1, -1)}
	game.add_enemy("g", Vector2i(4, 0), 3)
	for spec in TEMPLATES[config.id].pieces:
		game.add_enemy(spec[0], Vector2i(spec[1], spec[2]), 1 if spec[0] == "q" else (2 if spec[0] == "p" else 3))
		var enemy = game.enemies.back()
		enemy.normal_moves = 0;enemy.bonus_pending = false
		if enemy.kind in ["a", "e"]: game.encounter_state.guard_uids.append(enemy.uid)
		if "double_step" in config.rules and enemy.kind in ["p", "q"]: enemy.march_mark = true
		if "river_signal" in config.rules:
			if enemy.kind == "p" and game.encounter_state.signal_uid < 0: game.encounter_state.signal_uid = enemy.uid;enemy.signal = true
			if enemy.kind == "c" and game.encounter_state.cannon_uid < 0: game.encounter_state.cannon_uid = enemy.uid

static func active(game) -> bool: return not game.tutorial.active and not game.encounter_state.is_empty()
static func has_rule(game, rule: String) -> bool: return active(game) and rule in game.encounter_state.config.rules
static func title(config: Dictionary) -> String: return TEMPLATES.get(config.get("id", ""), {}).get("name", "")
static func summary(config: Dictionary) -> String:
	var labels: Array[String] = []
	for rule in config.get("rules", []): labels.append(RULE_NAMES[rule])
	return " · ".join(labels)
static func details(config: Dictionary) -> String:
	var text = ""
	for rule in config.get("rules", []): text += RULE_TEXT[rule] + "\n"
	return text.strip_edges()

static func selected_guard(game) -> int:
	var guards = []
	for enemy in game.enemies:
		if enemy.uid in game.encounter_state.guard_uids: guards.append(enemy.uid)
	if guards.is_empty(): return -1
	return guards[int(game.encounter_state.phases) % guards.size()]

static func on_general_damage(game, enemy: Dictionary):
	if not has_rule(game, "last_stand") or enemy.kind != "g" or enemy.hp <= 0 or game.encounter_state.retaliated: return
	game.encounter_state.retaliated = true
	for ally in game.enemies:
		if ally.kind in ["a", "e", "p", "q"]: ally.bonus_pending = true
	game.log_line("残阵反扑：守军下次正常行动额外走一步。")

static func wants_bonus(game, enemy: Dictionary) -> bool:
	if not active(game): return false
	if enemy.get("bonus_pending", false) and int(enemy.get("bonus_after_phase", 0)) <= int(game.encounter_state.phases): return true
	if has_rule(game, "double_step") and enemy.get("march_mark", false) and int(enemy.get("normal_moves", 0)) % 2 == 0: return true
	return has_rule(game, "palace_rotation") and enemy.uid == selected_guard(game)

static func after_normal_move(game, enemy: Dictionary, from: Vector2i):
	enemy.normal_moves = int(enemy.get("normal_moves", 0)) + 1
	if has_rule(game, "river_signal") and not game.encounter_state.river_triggered and enemy.uid == game.encounter_state.signal_uid and from.y < 5 and enemy.pos.y >= 5:
		game.encounter_state.river_triggered = true
		for ally in game.enemies:
			if ally.uid == game.encounter_state.cannon_uid:
				ally.bonus_pending = true
				ally.bonus_after_phase = int(game.encounter_state.phases) + 1
		game.log_line("旗卒渡河：配对炮下次行动额外走一步。")

static func finish_phase(game, timeline: float):
	if not active(game): return
	game.encounter_state.phases += 1
	var completed = int(game.encounter_state.phases)
	if not has_rule(game, "horse_relay") or not game.general_alive(): return
	# Birth is after all attacks/movement. Waves are never banked.
	if completed in [5, 10, 15]:
		var spawn: Vector2i = game.encounter_state.spawn_cell
		var horses = 0
		for enemy in game.enemies:
			if enemy.get("reinforcement", false) and enemy.kind == "h": horses += 1
		if R.inside(spawn) and R.occupied(spawn, game.enemies) < 0 and spawn != game.player and horses < 2:
			game.add_enemy("h", spawn, 3)
			game.enemies.back().reinforcement = true
			game.effect("spawn", game.cell_pos(spawn), game.cell_pos(spawn), 0.65, timeline, {"piece": game.enemies.back()})
			game.log_line("援马抵达，本轮不行动。")
		else: game.log_line("本波援马取消：出生点被占或援马已满。")
		game.encounter_state.spawn_cell = Vector2i(-1, -1)
	if completed in [4, 9, 14]:
		# Fixed wave entry; player can intentionally occupy/block the announced square.
		game.encounter_state.spawn_cell = Vector2i([0, 8, 0][completed / 5], 0)
		game.log_line("下轮后方援马抵达，棋盘已标出出生格。")

static func status(game) -> String:
	if not active(game): return ""
	var label = summary(game.encounter_state.config)
	if has_rule(game, "horse_relay"):
		var completed = int(game.encounter_state.phases)
		if R.inside(game.encounter_state.spawn_cell): label += " · 下轮援马"
		elif completed < 15: label += " · 援马还需%d轮" % (5 - completed % 5)
	return label

static func valid_state(value) -> bool:
	if not value is Dictionary or not valid_config(value.get("config")): return false
	for key in ["phases", "signal_uid", "cannon_uid"]:
		if not value.get(key) is int: return false
	if value.phases < 0 or value.signal_uid < -1 or value.cannon_uid < -1 or value.signal_uid == 0 or value.cannon_uid == 0: return false
	for key in ["retaliated", "river_triggered"]:
		if not value.get(key) is bool: return false
	if not value.get("guard_uids") is Array or not value.get("spawn_cell") is Vector2i: return false
	var seen = []
	for uid in value.guard_uids:
		if not uid is int or uid < 1 or uid in seen: return false
		seen.append(uid)
	return value.spawn_cell == Vector2i(-1, -1) or (R.inside(value.spawn_cell) and value.spawn_cell.y == 0 and value.phases in [4, 9, 14])
