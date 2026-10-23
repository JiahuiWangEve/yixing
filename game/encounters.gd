extends RefCounted
# A generated node fixes its army and rule once. Combat state is snapshotted by undo.
const R = preload("res://rules.gd")
const CHAPTER_TWO = preload("res://chapter_two.gd")
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
	"double_step": "标记卒每第二次非加速成功移动积攒1次加速，后续回合使用；加速移动不继续积攒。",
	"horse_relay": "第5、10、15轮结束后援马；提前预告，场上增援马最多2匹，堵住出生格可取消。",
	"river_signal": "旗卒过河后，配对炮获得1次加速，从下一敌方回合起使用，仅一次。",
	"palace_rotation": "每轮轮到一名守军，获得1次加速行动；多余加速顺延。",
	"last_stand": "敌将首次受伤存活后，现存士象卒各获得1次加速行动，仅一次。"
}
const ELITES = ["river_cannon", "rook_pressure", "horse_cannon", "palace_guard", "two_wings"]
const RULE_FOR = {"river_cannon": "river_signal", "rook_pressure": "double_step", "horse_cannon": "horse_relay", "palace_guard": "palace_rotation", "two_wings": "last_stand"}

static func node_config(kind: String, row: int, random: RandomNumberGenerator, chapter: int = 1) -> Dictionary:
	if chapter == 2: return CHAPTER_TWO.node_config(kind, row, random)
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
	if config is Dictionary and config.get("id", "") in CHAPTER_TWO.TEMPLATES: return CHAPTER_TWO.valid_config(config)
	if config is Dictionary and config.get("chapter", 1) != 1: return false
	if not config is Dictionary or config.get("id", "") not in TEMPLATES: return false
	if config.get("tier", "") not in ["battle", "elite", "boss"] or not config.get("rules") is Array: return false
	for rule in config.rules:
		if rule not in RULE_NAMES: return false
	if config.tier == "boss": return config.id == "palace_final" and config.rules == ["palace_rotation", "last_stand"]
	if config.tier == "elite": return config.id in ELITES and config.rules == [RULE_FOR[config.id]]
	return config.id not in ["horse_cannon", "palace_guard", "two_wings", "palace_final"] and config.rules.is_empty()

static func setup(game, config: Dictionary):
	if config.get("id", "") in CHAPTER_TWO.TEMPLATES:
		CHAPTER_TWO.setup(game, config);return
	game.encounter_state = {"config": config.duplicate(true), "phases": 0, "retaliated": false, "river_triggered": false, "signal_uid": -1, "cannon_uid": -1, "guard_uids": [], "spawn_cell": Vector2i(-1, -1)}
	game.add_enemy("g", Vector2i(4, 0), 3)
	for spec in TEMPLATES[config.id].pieces:
		game.add_enemy(spec[0], Vector2i(spec[1], spec[2]), 1 if spec[0] == "q" else (2 if spec[0] == "p" else 3))
		var enemy = game.enemies.back()
		enemy.normal_moves = 0;enemy.march_normal_moves = 0;enemy.bonus_pending = false
		enemy.action_credits = 0;enemy.action_credit_delay = 0
		if enemy.kind in ["a", "e"]: game.encounter_state.guard_uids.append(enemy.uid)
		if "double_step" in config.rules and enemy.kind in ["p", "q"]: enemy.march_mark = true
		if "river_signal" in config.rules:
			if enemy.kind == "p" and game.encounter_state.signal_uid < 0: game.encounter_state.signal_uid = enemy.uid;enemy.signal = true
			if enemy.kind == "c" and game.encounter_state.cannon_uid < 0: game.encounter_state.cannon_uid = enemy.uid

static func active(game) -> bool: return not game.tutorial.active and not game.encounter_state.is_empty()
static func has_rule(game, rule: String) -> bool: return active(game) and rule in game.encounter_state.config.rules
static func is_chapter_two(game) -> bool: return active(game) and game.encounter_state.config.get("chapter", 1) == 2
static func on_enemy_defeated(game, enemy: Dictionary, before_player_input: bool = false):
	if is_chapter_two(game): CHAPTER_TWO.on_enemy_defeated(game, enemy, before_player_input)
static func cancel_pending(game):
	if is_chapter_two(game): CHAPTER_TWO.cancel_pending(game)
static func markers(game) -> Array: return CHAPTER_TWO.markers(game) if is_chapter_two(game) else []
static func enemy_tags(enemy: Dictionary) -> String: return CHAPTER_TWO.enemy_tags(enemy)
static func title(config: Dictionary) -> String:
	if config.get("id", "") in CHAPTER_TWO.TEMPLATES: return CHAPTER_TWO.title(config)
	return TEMPLATES.get(config.get("id", ""), {}).get("name", "")
static func summary(config: Dictionary) -> String:
	if config.get("id", "") in CHAPTER_TWO.TEMPLATES: return CHAPTER_TWO.summary(config)
	var labels: Array[String] = []
	for rule in config.get("rules", []): labels.append(RULE_NAMES[rule])
	return " · ".join(labels)
static func details(config: Dictionary) -> String:
	if config.get("id", "") in CHAPTER_TWO.TEMPLATES: return CHAPTER_TWO.details(config)
	var text = ""
	for rule in config.get("rules", []):
		if config.get("tier", "") == "boss" and rule == "palace_rotation":
			text += "轮防：每轮指定一名守军，获得1次加速行动。\n"
		elif config.get("tier", "") == "boss" and rule == "last_stand":
			text += "反扑：敌将首次受伤存活，现存士象卒各获得1次加速行动，仅一次。\n"
		else: text += RULE_TEXT[rule] + "\n"
	if config.get("tier", "") in ["elite", "boss"]:
		text += "每轮最多移动一次，加速叠加顺延。移动或战术留守耗1次；定身、堵路、攻击留位保留。镇四方延迟加速2轮；移动不额外攻击。"
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
		if ally.kind in ["a", "e", "p", "q"]:
			ally.action_credits = int(ally.get("action_credits", 0)) + 1
	game.log_line("残阵反扑：守军各获1次加速行动，叠加顺延。")

# Elite and final battles accelerate future turns, never add a second move in one phase.
# Credits are per-enemy snapshot data. Successful movement spends exactly one;
# reset of the normal cooldown never discards the remaining credits.
static func uses_action_credits(game) -> bool:
	if game.training.is_playing(): return true
	return active(game) and not is_chapter_two(game) and game.encounter_state.config.get("tier", "") in ["elite", "boss"]

static func available_action_credits(game, enemy: Dictionary, include_rotation: bool = false) -> int:
	if not uses_action_credits(game): return 0
	var count = int(enemy.get("action_credits", 0))
	# Read legacy v0.10.0 pending retaliation without mutating a preview/save.
	if enemy.get("bonus_pending", false) and int(enemy.get("bonus_after_phase", 0)) <= int(game.encounter_state.phases): count += 1
	if include_rotation and has_rule(game, "palace_rotation") and enemy.uid == selected_guard(game): count += 1
	return count

static func prepare_phase(game):
	if not uses_action_credits(game): return
	var selected = selected_guard(game) if has_rule(game, "palace_rotation") else -1
	for enemy in game.enemies:
		enemy.action_credits = int(enemy.get("action_credits", 0))
		enemy.action_credit_delay = int(enemy.get("action_credit_delay", 0))
		if not enemy.has("march_normal_moves"): enemy.march_normal_moves = int(enemy.get("normal_moves", 0))
		if enemy.get("bonus_pending", false) and int(enemy.get("bonus_after_phase", 0)) <= int(game.encounter_state.phases):
			enemy.action_credits += 1
			enemy.bonus_pending = false # Idempotent old-save pending conversion.
		if enemy.uid == selected: enemy.action_credits += 1

static func effective_countdown(game, enemy: Dictionary) -> int:
	var countdown = maxi(1, int(enemy.cd))
	if available_action_credits(game, enemy, true) > 0:
		countdown = mini(countdown, int(enemy.get("action_credit_delay", 0)) + 1)
	if uses_action_credits(game) and enemy.get("bonus_pending", false):
		var due = maxi(1, int(enemy.get("bonus_after_phase", 0)) - int(game.encounter_state.phases) + 1)
		countdown = mini(countdown, maxi(due, int(enemy.get("action_credit_delay", 0)) + 1))
	return countdown

static func wants_bonus(_game, _enemy: Dictionary) -> bool:
	# Kept as a compatibility query: no rule authorizes a second same-phase move.
	return false

static func after_normal_move(game, enemy: Dictionary, from: Vector2i, spent_credit: bool = false):
	var prior_moves = int(enemy.get("normal_moves", 0))
	enemy.normal_moves = prior_moves + 1
	if has_rule(game, "double_step") and enemy.get("march_mark", false) and not spent_credit:
		# Keep total movement statistics separate from natural march progress.
		enemy.march_normal_moves = int(enemy.get("march_normal_moves", prior_moves)) + 1
		if int(enemy.march_normal_moves) % 2 == 0:
			enemy.action_credits = int(enemy.get("action_credits", 0)) + 1
	if has_rule(game, "river_signal") and not game.encounter_state.river_triggered and enemy.uid == game.encounter_state.signal_uid and from.y < 5 and enemy.pos.y >= 5:
		game.encounter_state.river_triggered = true
		for ally in game.enemies:
			if ally.uid == game.encounter_state.cannon_uid:
				# Army readiness was snapshotted before movement. A new credit cannot
				# affect or be spent by this phase, regardless of pawn/cannon order.
				ally.action_credits = int(ally.get("action_credits", 0)) + 1
		game.log_line("旗卒渡河：配对炮获得1次加速，下轮起使用。")

static func finish_phase(game, timeline: float):
	if not active(game): return
	if game.training.is_playing():
		game.encounter_state.phases += 1
		CHAPTER_TWO.finish_revivals(game, timeline);return
	if is_chapter_two(game):
		CHAPTER_TWO.finish_phase(game, timeline);return
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
	if is_chapter_two(game): return CHAPTER_TWO.status(game)
	var label = summary(game.encounter_state.config)
	if has_rule(game, "horse_relay"):
		var completed = int(game.encounter_state.phases)
		if R.inside(game.encounter_state.spawn_cell): label += " · 下轮援马"
		elif completed < 15: label += " · 援马还需%d轮" % (5 - completed % 5)
	return label

static func valid_state(value) -> bool:
	if value is Dictionary and value.get("config") is Dictionary and value.config.get("id", "") in CHAPTER_TWO.TEMPLATES: return CHAPTER_TWO.valid_state(value)
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
