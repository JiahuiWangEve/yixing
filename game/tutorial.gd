extends RefCounted



const RULES = preload("res://rules.gd")
const LESSON_NAMES = ["移动与抽牌", "出牌与能量", "移动牌与手牌上限", "威胁与敌方阶段", "胜负、奖励与换牌"]
var active = false
var lesson_index = 0
var step_index = 0
var lesson_complete = false
var finished = false
var game
var _steps: Array = []
var _pending_step = -1
var _transition_wait = 0.0
var _retry_pending = false
var _last_action = ""
var _before: Dictionary = {}
var _feedback = ""
var _feedback_time = 0.0

func start(owner, index: int = 0):
	game = owner
	active = true
	lesson_index = clampi(index, 0, LESSON_NAMES.size() - 1)
	lesson_complete = false
	finished = false
	_steps = _build_steps()
	_load_section(0)

func stop():
	active = false
	lesson_complete = false
	finished = false
	_pending_step = -1
	_retry_pending = false
	_last_action = ""
	_before.clear()
	if is_instance_valid(game):
		game.selected = -1
		game.clear_effects()

func restart():
	if is_instance_valid(game): start(game, lesson_index)

func skip_step():


	if not active or lesson_complete: return
	game.selected = -1
	game.clear_effects()
	var section = int(_steps[step_index].section)
	for i in range(step_index + 1, _steps.size()):
		if int(_steps[i].section) != section:
			_load_section(int(_steps[i].section))
			_feedback = "已跳过上一练习。"
			_feedback_time = 2.0
			return
	_complete()

func tick(delta: float):
	if not active or lesson_complete or not is_instance_valid(game): return
	_feedback_time = maxf(0.0, _feedback_time - delta)
	if game.phase == "dead" and not _retry_pending:
		_retry_pending = true
		_pending_step = -1
		_transition_wait = 0.55
	if not _presentation_finished(): return


	_transition_wait = maxf(0.0, _transition_wait - delta)
	if _retry_pending and _transition_wait <= 0.0:
		_load_section(int(_steps[step_index].section))
		_feedback = "已重试当前练习。"
		_feedback_time = 2.0
		return
	if _pending_step < 0 or _transition_wait > 0.0: return
	var next = _pending_step
	_pending_step = -1
	if next >= _steps.size():
		_complete()
	elif int(_steps[next].section) != int(_steps[step_index].section):
		_load_section(int(_steps[next].section))
	else:
		step_index = next
		_feedback = ""
		_feedback_time = 0.0

func pass_step() -> bool:
	return active and not lesson_complete and not _retry_pending and _pending_step < 0 and step_index >= 0 and step_index < _steps.size() and str(_steps[step_index].action) == "pass"
func can_pass(index: int, free: bool = false) -> bool:
	return pass_step() and _presentation_finished() and not free and _card_at({"index": index}) == str(_steps[step_index].card)

func allows(action: String, data: Dictionary = {}) -> bool:
	if not active: return true
	if lesson_complete or _retry_pending or _pending_step >= 0 or not _presentation_finished(): return false
	var spec: Dictionary = _steps[step_index]
	var allowed = false
	if spec.get("free", false):
		allowed = action in ["move", "end_turn", "select", "cancel", "play", "discard"]
	elif action == "cancel":
		allowed = str(spec.action) in ["cancel", "play", "select", "discard", "pass"]
	elif action == "select":
		if str(spec.action) == "discard":
			allowed = not _card_at(data).is_empty()
		else:
			allowed = str(spec.action) in ["select", "play", "pass"] and _card_at(data) == str(spec.get("card", ""))
	elif action == str(spec.action):
		allowed = true
		if action == "move" and spec.has("target"):
			allowed = data.get("target", Vector2i(-1, -1)) == spec.target
		elif action == "play":
			allowed = _card_at(data) == str(spec.get("card", ""))
			if spec.has("target"): allowed = allowed and data.get("target", Vector2i(-1, -1)) == spec.target
		elif action == "pass":
			allowed = can_pass(int(data.get("index", -1)))
		elif action == "discard":
			allowed = not _card_at(data).is_empty()
		elif action == "reward":
			var index = int(data.get("index", -2))
			allowed = str(data.get("mode", "add")) != "remove" and (index == -1 or (index >= 0 and index < game.rewards.size()))
	if not allowed:
		game.notice = "教学目标：" + str(spec.hint)
		return false
	_capture(action, data)
	return true

func after_action(action: String, data: Dictionary = {}):
	if not active or lesson_complete or _pending_step >= 0: return
	if action != _last_action: return
	_last_action = ""
	if game.phase == "dead":
		_retry_pending = true
		_transition_wait = 0.55
		return
	var spec: Dictionary = _steps[step_index]
	if action != str(spec.action): return
	if not _observed_success(action, data):
		_retry_pending = true
		_transition_wait = 0.55
		game.notice = "当前练习未达成，重新练习。"
		return
	_feedback = ""
	_feedback_time = 0.0
	_pending_step = step_index + 1
	var changes_exercise = _pending_step >= _steps.size() or int(_steps[_pending_step].section) != int(spec.section)
	_transition_wait = 0.8 if changes_exercise else (0.18 if action in ["select", "cancel"] else 0.3)

func title() -> String:
	return "教学预设 %d/%d · %s" % [lesson_index + 1, LESSON_NAMES.size(), LESSON_NAMES[lesson_index]]

func hint() -> String:
	if lesson_complete: return _completion_hint()
	if not active or _steps.is_empty(): return ""
	if _retry_pending: return "失误不扣进度，正在重置当前练习。"
	if _pending_step >= 0: return _result_hint()
	return str(_steps[step_index].hint)

func target_cells() -> Array:
	if not active or lesson_complete or _retry_pending or _pending_step >= 0 or _steps.is_empty(): return []
	var spec: Dictionary = _steps[step_index]
	if spec.has("target"): return [spec.target]
	return []

func step_count() -> int:
	return _steps.size()

func is_free_practice() -> bool:
	return active and not lesson_complete and not _steps.is_empty() and bool(_steps[step_index].get("free", false))

func section_label() -> String:
	if _steps.is_empty(): return ""
	var section = int(_steps[mini(step_index, _steps.size() - 1)].section)
	for spec in _steps:
		if int(spec.section) == section and spec.has("label"): return str(spec.label)
	return "固定练习"

func _step(action: String, text: String, section: int, extra: Dictionary = {}) -> Dictionary:
	var result = {"action": action, "hint": text, "section": section}
	result.merge(extra)
	return result

func _build_steps() -> Array:
	match lesson_index:
		0:
			return [
				_step("move", "0张普通牌；点亮格或用帅步移动，固定抽短剑。", 0, {"target": Vector2i(4, 7), "label": "固定抽牌练习"}),
				_step("end_turn", "基础移动已用；点结束回合（电脑空格），观察手牌。", 0),
				_step("move", "回合不自动抽牌；移动恢复，再走亮格。", 0, {"target": Vector2i(5, 7)})]
		1:
			return [
				_step("select", "预置手牌：先点选短剑，尚不花能量。", 0, {"card": "sword", "label": "选牌与一命卒"}),
				_step("cancel", "再次点短剑取消；也可按 Esc。", 0),
				_step("play", "选短剑，再点亮格的卒；一击扣一血。", 0, {"card": "sword", "target": Vector2i(4, 5)}),
				_step("end_turn", "短剑花一气；结束回合，余牌会保留。", 0),
				_step("play", "新预设：象有三血；用短剑击中亮格。", 1, {"card": "sword", "target": Vector2i(5, 3), "label": "三血象练习"}),
				_step("play", "象还剩两血；再用短剑击中亮格。", 1, {"card": "sword", "target": Vector2i(5, 3)}),
				_step("play", "象还剩一血；第三剑击败它，观察碎裂。", 1, {"card": "sword", "target": Vector2i(5, 3)}),
				_step("end_turn", "三气已用完；结束回合回三气，踏马保留。", 1)]
		2:
			return [
				_step("move", "固定抽牌：基础移动到亮格，抽到踏马。", 0, {"target": Vector2i(4, 7), "label": "移动接攻击"}),
				_step("play", "付费移动牌需先点击选中，再点亮格。用踏马移动并抽短剑。", 0, {"card": "horse", "target": Vector2i(6, 6)}),
				_step("play", "两种移动各限一次；用新抽的短剑杀卒。", 0, {"card": "sword", "target": Vector2i(6, 5)}),
				_step("end_turn", "基础与牌移动都已用；结束回合恢复。", 0),
				_step("move", "新预设六张手牌；走亮格抽第七张。", 1, {"target": Vector2i(4, 7), "label": "七张强制弃牌"}),
				_step("discard", "手牌上限六：选一张，再点确认弃牌。", 1)]
		3:
			return [
				_step("move", "卒的倒计时三只管移动；先走亮格解围。", 0, {"target": Vector2i(3, 6), "label": "攻击不等倒计时"}),
				_step("end_turn", "已离开攻击格；安全后再结束回合。", 0),
				_step("end_turn", "新预设当前安全；结束回合观察卒前进。", 1, {"label": "移动后不连击"}),
				_step("move", "卒刚移动不会连击；现在走亮格避险。", 1, {"target": Vector2i(3, 7)}),
				_step("end_turn", "你有一回合反应；解围后结束回合。", 1),
				_step("end_turn", "自由测验：选安全路线，活过敌方阶段。", 2, {"free": true, "label": "自由避险测验"})]
		4:
			return [
				_step("play", "预置三张短剑；将有三血，先出一剑。", 0, {"card": "sword", "target": Vector2i(4, 0), "label": "三血将与破阵奖励"}),
				_step("play", "将剩两血；再用短剑击中亮格。", 0, {"card": "sword", "target": Vector2i(4, 0)}),
				_step("play", "将剩一血；最后一剑真正破阵。", 0, {"card": "sword", "target": Vector2i(4, 0)}),
				_step("reward", "破阵奖励：选择一张新牌加入牌组，也可跳过。", 0),
				_step("pass", "选短剑点右侧弃置，或长按拖入松手：3费抽1张。", 1, {"card": "sword", "label": "付费弃牌重抽"})]
	return []

func _load_section(section: int):
	_pending_step = -1
	_retry_pending = false
	_transition_wait = 0.0
	_last_action = ""
	_before.clear()
	_feedback = ""
	_feedback_time = 0.0
	for i in _steps.size():
		if int(_steps[i].section) == section:
			step_index = i
			break
	_reset_board()
	match lesson_index:
		0:
			game.player = Vector2i(4, 8)
			game.deck = ["sword", "sword"]
			_general()
		1:
			if section == 0:
				game.player = Vector2i(4, 6)
				game.hand = ["sword", "horse"]
				_general()
				game.add_enemy("p", Vector2i(4, 5), 3)
			else:
				game.player = Vector2i(4, 3)
				game.hand = ["sword", "sword", "sword", "horse"]
				_general()
				game.add_enemy("e", Vector2i(5, 3), 3)
		2:
			game.player = Vector2i(4, 8)
			_general()
			if section == 0:
				game.deck = ["sword", "horse"]
				game.add_enemy("p", Vector2i(6, 5), 3)
			else:
				game.hand = ["sword", "sword", "spear", "horse", "horse", "straight"]
				game.deck = ["sword"]
		3:
			_general()
			game.deck = ["sword", "horse"] if section == 2 else ["sword"]
			if section == 0:
				game.player = Vector2i(4, 6)
				game.add_enemy("p", Vector2i(4, 5), 3)
			elif section == 1:
				game.player = Vector2i(4, 7)
				game.add_enemy("p", Vector2i(4, 5), 1)
				game.enemies.back().period = 3
			else:
				game.player = Vector2i(4, 7)
				game.add_enemy("p", Vector2i(4, 6), 3)
				game.add_enemy("p", Vector2i(3, 6), 3)
		4:
			if section == 0:
				game.player = Vector2i(4, 1)
				game.hand = ["sword", "sword", "sword"]
				_general()
			else:
				game.player = Vector2i(4, 9)
				game.hand = ["sword"]
				game.deck = ["spear"]
				game.energy = 3
				_general()
	game.player_visual = game.cell_pos(game.player)
	game.plan_intents()
	if lesson_index == 3 and section == 1:
		game.enemies.back().intent = Vector2i(4, 6)
	game.clear_effects()
	game.initial_threat = 9999.0
	game.notice = "教学固定布局与抽牌；" + str(_steps[step_index].hint)
	game.log_line("教学预设 · " + section_label())

func _reset_board():
	game.new_run(true)
	game.screen = "game"
	game.phase = "play"
	game.player = Vector2i(4, 9)
	game.enemies = []
	game.deck = []
	game.discard = []
	game.hand = []
	game.rewards = []
	game.stage = 1
	game.turn = 1
	game.reinforcement_turns = 0
	game.reinforcement_pending = 0
	game.lives = 1
	game.energy = 3
	game.basic_used = false
	game.card_move_used = false
	game.selected = -1
	game.hand_page = 0
	game.hand_drawer = false
	game.hover = Vector2i(-1, -1)
	game.logs = []
	game.clear_effects()

func _general():
	game.add_enemy("g", Vector2i(4, 0), 99)

func _card_at(data: Dictionary) -> String:
	var index = int(data.get("index", -1))
	if index < 0 or index >= game.hand.size(): return ""
	return str(game.hand[index])

func _capture(action: String, data: Dictionary):
	_last_action = action
	_before = {
		"player": game.player, "lives": game.lives, "energy": game.energy,
		"turn": game.turn, "stage": game.stage, "hand": game.hand.duplicate(), "collection": game.collection.duplicate(),
		"basic_used": game.basic_used, "card_move_used": game.card_move_used,
		"card": _card_at(data), "enemies": game.enemies.duplicate(true),
		"reinforcement_turns": game.reinforcement_turns,
		"reward_mode": str(data.get("mode", "add")), "collection_size": game.collection.size(), "reward_index": int(data.get("index", -2))}

func _observed_success(action: String, data: Dictionary) -> bool:
	if _before.is_empty(): return false
	var spec: Dictionary = _steps[step_index]
	match action:
		"select":
			return game.selected >= 0 and game.selected < game.hand.size() and game.hand[game.selected] == spec.card and game.energy == _before.energy
		"cancel":
			return game.selected == -1 and game.energy == _before.energy and game.hand == _before.hand
		"move":
			return game.player == spec.target and game.basic_used and game.energy == _before.energy and game.hand.size() == _before.hand.size() + 1
		"play":
			var card = str(_before.card)
			if card != str(spec.card) or game.energy != int(_before.energy) - int(game.CARDS[card][1]): return false
			if card == "horse": return game.player == spec.target and game.card_move_used and game.basic_used and game.hand == ["sword"]
			var target: Vector2i = spec.target
			var before_index = RULES.occupied(target, _before.enemies)
			var after_index = RULES.occupied(target, game.enemies)
			if before_index < 0: return false
			var previous: Dictionary = _before.enemies[before_index]
			if card == "sword":
				if int(previous.hp) == 1: return after_index < 0
				return after_index >= 0 and int(game.enemies[after_index].hp) == int(previous.hp) - 1
		"pass":
			return game.energy == int(_before.energy) - 3 and game.hand == ["spear"] and game.deck.is_empty() and game.discard == ["sword"] and game.player == _before.player and game.enemies == _before.enemies and game.collection == _before.collection
		"discard":
			return _before.hand.size() == 7 and game.hand.size() == 6 and game.phase == "play" and game.energy == _before.energy
		"reward":
			if str(_before.get("reward_mode", "add")) == "remove": return false
			var added = 0 if int(_before.reward_index) == -1 else 1
			return game.stage == int(_before.stage) + 1 and game.collection.size() == int(_before.collection_size) + added
		"end_turn":
			if game.phase != "play" or game.turn != int(_before.turn) + 1 or game.energy != 3 or game.basic_used or game.card_move_used: return false
			if game.hand != _before.hand: return false
			if lesson_index == 3 and step_index == 2:
				return game.player == _before.player and game.lives == 1 and RULES.occupied(Vector2i(4, 6), game.enemies) >= 0 and RULES.threatened(game.player, game.enemies)

			return game.lives == int(_before.lives)
	return false

func _presentation_finished() -> bool:
	if not is_instance_valid(game) or game.input_lock > 0.0: return false
	for fx in game.effects:
		if float(fx.get("age", 0.0)) < float(fx.get("delay", 0.0)) + float(fx.get("duration", 0.0)): return false
	return true

func _result_hint() -> String:
	if lesson_index == 0 and step_index == 1: return "移动已恢复，手牌仍一张；没有自动抽牌。"
	if lesson_index == 1 and step_index in [3, 7]: return "能量恢复三气；没有打出的踏马仍在手里。"
	if lesson_index == 2 and step_index == 3: return "基础移动与移动牌次数都恢复了。"
	if lesson_index == 2 and step_index == 4: return "已抽到第七张；必须弃一张才能继续。"
	if lesson_index == 4 and step_index == 4: return "完成：3费弃置抽1张；不触发效果，不永久删牌。"
	if lesson_index == 1 and step_index == 4: return "象受伤但未死；还剩两血。"
	if lesson_index == 1 and step_index == 5: return "象还剩一血；第三剑可击败它。"
	if lesson_index == 1 and step_index == 6: return "三剑击败三血象；三气用完，踏马仍在手里。"
	if lesson_index == 3 and step_index == 2: return "卒已前进形成威胁，但没有同阶段再攻击。"
	return str(_steps[step_index].hint)

func _complete():
	_pending_step = -1
	_retry_pending = false
	_last_action = ""
	_before.clear()
	lesson_complete = true
	finished = lesson_index == LESSON_NAMES.size() - 1
	game.selected = -1
	game.clear_effects()
	game.notice = _completion_hint()

func _completion_hint() -> String:
	match lesson_index:
		0: return "移动免费且抽牌；每回合一次，回合不自动抽牌。"
		1: return "卒一血、象三血；回合恢复三气，保留手牌。"
		2: return "两种移动各一次；超六张要选牌确认弃置。"
		3: return "先攻击后移动；一命受击失败，先解围。"
		4: return "完成：3费弃置抽1张；不触发效果，不永久删牌。"
	return "练习完成。"
