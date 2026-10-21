extends RefCounted
# Chapter two keeps ordinary chess movement; health, revival and finite waves
# are encounter data. Every mutable counter belongs to encounter_state so undo,
# replay and route saves share exactly the same deterministic lifecycle.
const R = preload("res://rules.gd")
# Each piece is [kind, one-based file, one-based rank, HP, heavy, unyielding].
# Each wave is [enemy-phase arrival, piece]. The authored coordinates are kept
# one-based here to make the battle sheets directly auditable.
const TEMPLATES = {
	"c2_heavy_pawns": {"name": "坚卒拦路", "tier": "battle", "pieces": [
		["g", 5, 1, 4, false, false], ["e", 3, 1, 4, true, false], ["p", 4, 4, 2, true, false], ["p", 6, 4, 1, false, false], ["p", 8, 4, 1, false, false]],
		"waves": [[9, ["h", 8, 1, 2, false, false]]]},
	"c2_lone_guard": {"name": "孤士守宫", "tier": "battle", "pieces": [
		["g", 5, 1, 4, false, false], ["a", 4, 1, 2, false, true], ["e", 7, 1, 3, false, false], ["h", 2, 3, 2, false, false], ["p", 5, 4, 1, false, false], ["p", 7, 4, 1, false, false]],
		"waves": [[5, ["h", 8, 1, 2, false, false]], [9, ["p", 2, 3, 2, true, false]]]},
	"c2_cannon_fort": {"name": "炮垒待援", "tier": "battle", "pieces": [
		["g", 5, 1, 4, false, false], ["e", 7, 1, 3, false, true], ["c", 2, 2, 2, false, false], ["p", 2, 4, 2, true, false], ["h", 8, 3, 2, false, false], ["p", 5, 4, 1, false, false]],
		"waves": [[5, ["h", 8, 1, 2, false, false]], [9, ["h", 2, 1, 2, false, false]]]},
	"c2_palace_guard": {"name": "不屈宫卫", "tier": "elite", "pieces": [
		["g", 5, 1, 6, false, false], ["a", 4, 1, 2, false, true], ["e", 7, 1, 4, true, true], ["r", 1, 2, 2, false, false], ["p", 4, 4, 2, true, false], ["p", 6, 4, 1, false, false]],
		"waves": [[5, ["h", 8, 1, 2, false, false]], [8, ["h", 2, 1, 2, false, false]], [11, ["p", 8, 3, 2, true, false]]]},
	"c2_double_cannon": {"name": "双炮重垒", "tier": "elite", "pieces": [
		["g", 5, 1, 6, false, false], ["a", 6, 1, 2, false, true], ["e", 3, 1, 4, true, false], ["c", 2, 2, 2, false, false], ["c", 8, 2, 1, false, false], ["p", 2, 4, 2, true, false], ["p", 8, 4, 1, false, false]],
		"waves": [[5, ["h", 8, 1, 2, false, false]], [8, ["h", 2, 1, 2, false, false]], [11, ["h", 8, 3, 2, false, false]]]},
	"c2_inner_city": {"name": "内城决阵", "tier": "boss", "pieces": [
		["g", 5, 1, 9, false, false], ["a", 4, 1, 2, false, true], ["e", 7, 1, 4, true, true], ["e", 3, 1, 3, false, false], ["c", 8, 2, 2, false, false], ["r", 1, 2, 2, false, false], ["p", 8, 4, 2, true, false], ["p", 5, 4, 1, false, false]],
		"waves": [[5, ["h", 8, 1, 2, false, false]], [9, ["h", 2, 1, 2, false, false]], [13, ["h", 8, 3, 2, false, false]]]}
}
const NORMALS = ["c2_heavy_pawns", "c2_lone_guard", "c2_cannon_fort"]
const NORMAL_POOL = ["c2_heavy_pawns", "c2_lone_guard", "c2_lone_guard", "c2_cannon_fort", "c2_cannon_fort"]
const ELITES = ["c2_palace_guard", "c2_double_cannon"]
const MAX_REINFORCEMENTS = 2
const MAX_WAVE_DELAY = 2

static func node_config(kind: String, row: int, random: RandomNumberGenerator) -> Dictionary:
	var id = ""
	if kind == "boss": id = "c2_inner_city"
	elif kind == "elite": id = ELITES[random.randi_range(0, ELITES.size() - 1)]
	elif kind == "battle": id = "c2_heavy_pawns" if row == 0 else NORMAL_POOL[random.randi_range(0, NORMAL_POOL.size() - 1)]
	return {} if id.is_empty() else {"id": id, "tier": kind, "rules": [], "chapter": 2}

static func valid_config(config) -> bool:
	if not config is Dictionary or config.get("id", "") not in TEMPLATES: return false
	return config.get("chapter") is int and config.chapter == 2 and config.get("tier") == TEMPLATES[config.id].tier and config.get("rules") is Array and config.rules.is_empty()

static func position(spec: Array) -> Vector2i: return Vector2i(spec[1] - 1, spec[2] - 1)

static func spawn(game, spec: Array, reinforcement: bool = false) -> Dictionary:
	game.add_enemy(spec[0], position(spec), 2 if spec[0] == "p" else 3)
	var enemy: Dictionary = game.enemies.back()
	enemy.hp = spec[3];enemy.max_hp = spec[3]
	enemy.heavy = spec[4];enemy.unyielding = spec[5]
	enemy.original_spawn = position(spec)
	enemy.normal_moves = 0;enemy.bonus_pending = false
	if reinforcement: enemy.reinforcement = true
	return enemy

static func setup(game, config: Dictionary):
	game.encounter_state = {"config": config.duplicate(true), "phases": 0, "ghosts": [], "waves": [], "cancelled": false}
	for spec in TEMPLATES[config.id].pieces: spawn(game, spec)
	for index in TEMPLATES[config.id].waves.size():
		game.encounter_state.waves.append({"index": index, "status": "scheduled", "blocked_phases": 0, "reason": "", "uid": -1})

static func title(config: Dictionary) -> String: return TEMPLATES.get(config.get("id", ""), {}).get("name", "")

static func summary(config: Dictionary) -> String:
	var template: Dictionary = TEMPLATES.get(config.get("id", ""), {})
	if template.is_empty(): return ""
	var heavy = false;var unyielding = 0
	for spec in template.pieces:
		heavy = heavy or spec[4]
		if spec[5]: unyielding += 1
	for wave in template.waves: heavy = heavy or wave[1][4]
	var labels: Array[String] = []
	if heavy: labels.append("厚血")
	if unyielding > 0: labels.append("不屈×%d" % unyielding)
	labels.append("增援%d波" % template.waves.size())
	return " · ".join(labels)

static func details(config: Dictionary) -> String:
	if config.get("id", "") not in TEMPLATES: return ""
	var arrivals: Array[String] = []
	for wave in TEMPLATES[config.id].waves: arrivals.append(str(wave[0]))
	var text = "厚血只增加血量，走法不变。"
	for spec in TEMPLATES[config.id].pieces:
		if spec[5]:
			text += "\n不屈：原位留残影，不挡路、不作炮架。经过2个完整玩家回合，原位空闲时满血复归；数字为轮末倒计时。"
			break
	text += "\n增援于第%s轮末抵达，提前1轮预告；场上增援最多2枚，受阻最多延后2轮，仍受阻则取消。复归优先，复归与增援当轮不行动。敌将阵亡全部取消。" % "、".join(arrivals)
	return text

static func enemy_tags(enemy: Dictionary) -> String:
	var tags: Array[String] = []
	if enemy.get("heavy", false): tags.append("厚血")
	if enemy.get("unyielding", false): tags.append("不屈")
	if enemy.get("reinforcement", false): tags.append("增援")
	return " · ".join(tags)

static func cancel_pending(game):
	game.encounter_state.cancelled = true
	game.encounter_state.ghosts.clear()
	for wave in game.encounter_state.waves:
		if wave.status not in ["arrived", "cancelled"]:
			wave.status = "cancelled";wave.reason = "战斗结束"

static func on_enemy_defeated(game, enemy: Dictionary, before_player_input: bool = false):
	# A removed unit must never carry delayed damage into its next incarnation.
	for index in range(game.pending_bleeds.size() - 1, -1, -1):
		if game.pending_bleeds[index].enemy_uid == enemy.uid: game.pending_bleeds.remove_at(index)
	if enemy.kind == "g" or not game.general_alive():
		cancel_pending(game);return
	if game.encounter_state.cancelled or not enemy.get("unyielding", false): return
	for ghost in game.encounter_state.ghosts:
		if ghost.enemy.uid == enemy.uid: return
	# Most of the current turn was already available when a card kills a unit,
	# so that partial turn cannot count. Start-of-turn bleed occurs before any
	# input and therefore the just-starting player turn DOES count in full.
	var completed = int(game.encounter_state.phases)
	var revival = {"uid": enemy.uid, "kind": enemy.kind, "pos": enemy.original_spawn, "original_spawn": enemy.original_spawn,
		"hp": 0, "max_hp": enemy.max_hp, "heavy": enemy.get("heavy", false), "unyielding": true,
		"cd": 3, "period": 3, "stun": 0, "normal_moves": 0, "bonus_pending": false}
	game.encounter_state.ghosts.append({"enemy": revival, "defeat_phase": completed, "before_player_input": before_player_input,
		"ready_phase": completed + (2 if before_player_input else 3), "status": "waiting"})
	game.log_line("不屈残影留在原位，经过2个完整玩家回合后复归。")

static func occupied(game, cell: Vector2i) -> bool: return game.player == cell or R.occupied(cell, game.enemies) >= 0

static func living_reinforcements(game) -> int:
	var count = 0
	for enemy in game.enemies:
		if enemy.get("reinforcement", false): count += 1
	return count

static func finish_revivals(game, timeline: float):
	var remaining: Array = []
	for ghost in game.encounter_state.ghosts:
		if game.encounter_state.phases < ghost.ready_phase:
			remaining.append(ghost);continue
		if occupied(game, ghost.enemy.original_spawn):
			if ghost.status != "blocked": game.log_line("不屈复归受阻：原位被占，等待空位。")
			ghost.status = "blocked";remaining.append(ghost);continue
		var enemy: Dictionary = ghost.enemy.duplicate(true)
		enemy.hp = enemy.max_hp;enemy.visual = game.cell_pos(enemy.pos)
		enemy.intent = Vector2i(-1, -1)
		game.enemies.append(enemy) # Stable UID; revival never consumes a new UID.
		game.effect("spawn", game.cell_pos(enemy.pos), game.cell_pos(enemy.pos), 0.65, timeline, {"piece": enemy})
		game.log_line("不屈守军满血复归，本轮不行动。")
	game.encounter_state.ghosts = remaining

static func finish_waves(game, timeline: float):
	var completed = int(game.encounter_state.phases)
	var definitions: Array = TEMPLATES[game.encounter_state.config.id].waves
	var spawned = false
	for wave in game.encounter_state.waves:
		if wave.status in ["arrived", "cancelled"]: continue
		var definition: Array = definitions[wave.index]
		var arrival = int(definition[0])
		if completed < arrival:
			if completed == arrival - 1 and wave.status == "scheduled":
				wave.status = "announced"
				game.log_line("第%d波增援下轮末抵达，出生格已标出。" % (wave.index + 1))
			continue
		var reason = ""
		if occupied(game, position(definition[1])): reason = "出生格被占"
		elif living_reinforcements(game) >= MAX_REINFORCEMENTS: reason = "增援已满"
		elif spawned: reason = "本轮已增援"
		# Two postponements permit the two following enemy-phase endings to
		# retry. A third blocked check cancels permanently instead of banking.
		if completed > arrival + MAX_WAVE_DELAY or (not reason.is_empty() and completed == arrival + MAX_WAVE_DELAY):
			wave.status = "cancelled";wave.reason = reason if not reason.is_empty() else "等待超时"
			game.log_line("第%d波增援取消：%s。" % [wave.index + 1, wave.reason])
		elif not reason.is_empty():
			wave.status = "blocked";wave.reason = reason;wave.blocked_phases = completed - arrival + 1
			game.log_line("第%d波增援受阻：%s，已延后%d轮。" % [wave.index + 1, reason, wave.blocked_phases])
		else:
			var enemy = spawn(game, definition[1], true)
			wave.status = "arrived";wave.reason = "";wave.uid = enemy.uid;spawned = true
			game.effect("spawn", game.cell_pos(enemy.pos), game.cell_pos(enemy.pos), 0.65, timeline, {"piece": enemy})
			game.log_line("第%d波增援抵达，本轮不行动。" % (wave.index + 1))

static func finish_phase(game, timeline: float):
	game.encounter_state.phases += 1
	if game.encounter_state.cancelled: return
	if not game.general_alive(): cancel_pending(game);return
	# Revival has priority over reinforcement when their entry cells coincide.
	finish_revivals(game, timeline)
	finish_waves(game, timeline)

static func markers(game) -> Array:
	var result: Array = []
	if game.encounter_state.cancelled: return result
	for ghost in game.encounter_state.ghosts:
		result.append({"pos": ghost.enemy.original_spawn, "label": "归阻" if ghost.status == "blocked" else "归%d" % maxi(0, ghost.ready_phase - int(game.encounter_state.phases)),
			"kind": "revival", "status": ghost.status, "uid": ghost.enemy.uid,
			"remaining_phases": maxi(0, ghost.ready_phase - int(game.encounter_state.phases))})
	var definitions: Array = TEMPLATES[game.encounter_state.config.id].waves
	for wave in game.encounter_state.waves:
		if wave.status in ["announced", "blocked"]:
			result.append({"pos": position(definitions[wave.index][1]), "label": "援阻" if wave.status == "blocked" else "增援",
				"kind": "reinforcement", "status": wave.status, "wave": wave.index + 1})
	return result

static func status(game) -> String:
	var labels: Array[String] = [summary(game.encounter_state.config)]
	if game.encounter_state.cancelled:
		labels.append("复归与增援已停止")
		return " · ".join(labels)
	var pending = 0;var blocked = 0;var cancelled = 0
	for ghost in game.encounter_state.ghosts:
		if ghost.status == "blocked": blocked += 1
		else: pending += 1
	if pending > 0: labels.append("待复归%d" % pending)
	if blocked > 0: labels.append("复归受阻%d" % blocked)
	for wave in game.encounter_state.waves:
		if wave.status == "announced": labels.append("下轮增援%d" % (wave.index + 1))
		elif wave.status == "blocked": labels.append("增援%d受阻%d/2" % [wave.index + 1, wave.blocked_phases])
		elif wave.status == "cancelled": cancelled += 1
	if cancelled > 0: labels.append("已取消%d波" % cancelled)
	return " · ".join(labels)

static func original_spec(config: Dictionary, cell: Vector2i) -> Array:
	for spec in TEMPLATES[config.id].pieces:
		if position(spec) == cell: return spec
	return []

static func valid_state(value) -> bool:
	if not value is Dictionary or not valid_config(value.get("config")): return false
	if not value.get("phases") is int or value.phases < 0 or not value.get("cancelled") is bool: return false
	if not value.get("ghosts") is Array or not value.get("waves") is Array: return false
	if value.cancelled and not value.ghosts.is_empty(): return false
	var seen = {};var cells = {}
	for ghost in value.ghosts:
		if not ghost is Dictionary or not ghost.get("enemy") is Dictionary: return false
		var enemy: Dictionary = ghost.enemy
		if not enemy.get("uid") is int or enemy.uid < 1 or seen.has(enemy.uid): return false
		if not enemy.get("original_spawn") is Vector2i or cells.has(enemy.original_spawn): return false
		var spec = original_spec(value.config, enemy.original_spawn)
		if spec.is_empty() or not spec[5] or enemy.get("kind") != spec[0] or enemy.get("max_hp") != spec[3]: return false
		if enemy.get("pos") != enemy.original_spawn or enemy.get("hp") != 0 or enemy.get("heavy") != spec[4] or enemy.get("unyielding") != true: return false
		if enemy.get("cd") != 3 or enemy.get("period") != 3 or enemy.get("stun") != 0: return false
		if not ghost.get("defeat_phase") is int or ghost.defeat_phase < 0 or ghost.defeat_phase > value.phases: return false
		if not ghost.get("before_player_input") is bool or not ghost.get("ready_phase") is int: return false
		if ghost.ready_phase != ghost.defeat_phase + (2 if ghost.before_player_input else 3): return false
		if ghost.get("status") not in ["waiting", "blocked"]: return false
		if ghost.status == "blocked" and ghost.ready_phase > value.phases: return false
		if ghost.status == "waiting" and ghost.ready_phase <= value.phases: return false
		seen[enemy.uid] = true;cells[enemy.original_spawn] = true
	var definitions: Array = TEMPLATES[value.config.id].waves
	if value.waves.size() != definitions.size(): return false
	for index in value.waves.size():
		var wave = value.waves[index]
		if not wave is Dictionary or wave.get("index") != index or not wave.get("uid") is int: return false
		if wave.get("status") not in ["scheduled", "announced", "blocked", "arrived", "cancelled"]: return false
		if not wave.get("blocked_phases") is int or wave.blocked_phases < 0 or wave.blocked_phases > MAX_WAVE_DELAY: return false
		if wave.get("reason") not in ["", "出生格被占", "增援已满", "本轮已增援", "等待超时", "战斗结束"]: return false
		if value.cancelled and wave.status not in ["arrived", "cancelled"]: return false
		if wave.status == "arrived":
			if wave.uid < 1 or seen.has(wave.uid) or value.phases < definitions[index][0] or not wave.reason.is_empty(): return false
			seen[wave.uid] = true
		elif wave.uid != -1: return false
		if wave.status == "scheduled" and (value.phases >= definitions[index][0] - 1 or wave.blocked_phases != 0): return false
		if wave.status == "announced" and (value.phases != definitions[index][0] - 1 or wave.blocked_phases != 0): return false
		if wave.status == "blocked" and (wave.blocked_phases < 1 or value.phases != definitions[index][0] + wave.blocked_phases - 1 or wave.reason.is_empty()): return false
		if wave.status == "cancelled" and wave.reason.is_empty(): return false
	return true
