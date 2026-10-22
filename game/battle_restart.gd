extends RefCounted
# A separate immutable entry checkpoint, never part of rewindable undo history.
var game
var snapshot: Dictionary = {}
func _init(owner): game = owner
func clear(): snapshot = {}
func identity() -> Dictionary:
	if not game.route.active(): return {"stage": game.stage, "role": game.player_skill}
	var route = game.route.state
	return {"seed": route.seed, "chapter": route.get("chapter", 1), "pending": route.pending, "role": game.player_skill, "treasure": route.get("treasure_id", "")}
func capture():
	clear()
	if game.tutorial.active or game.screen != "game" or game.phase != "play": return
	snapshot = {"identity": identity(), "state": game.history.capture()}
func load_snapshot(value):
	clear()
	if not value is Dictionary or not value.get("state") is Dictionary or value.get("identity") != identity(): return
	var state: Dictionary = value.state
	if state.get("phase") != "play" or state.get("turn") != 1 or state.get("lives", 0) <= 0: return
	if not state.get("rng_state") is int: return
	for key in game.HISTORY.FIELDS:
		if not state.has(key): return
	if game.route.active() and not game.route.valid_snapshot(game.route.state, state, "game"): return
	snapshot = value.duplicate(true)
func available() -> bool:
	return not snapshot.is_empty() and snapshot.identity == identity()
func can_restart() -> bool:
	if game.screen != "game" or game.phase not in ["play", "discard", "dead"]: return false
	if game.input_lock > 0 or game.navigation_lock > 0 or not game.effects.is_empty(): return false
	if game.presentation.active() or game.card_picker.active or game.encounter_info_open or game.gesture.active: return false
	if game.tutorial.active: return true
	if game.route.active() and game.route.state.get("victory_recorded", false): return false
	return available()
func restart() -> bool:
	if not can_restart():
		if game.screen == "game" and game.phase in ["play", "discard", "dead"] and game.input_lock <= 0 and game.navigation_lock <= 0 and not game.presentation.active() and not game.card_picker.active and not game.tutorial.active and not available():
			game.notice = "旧战斗无开场记录，从下一场起可重开。"
			game.board_info.cue = game.notice;game.board_info.cue_left = 4.0
			game.queue_redraw()
		return false
	var budget: int = game.normal_undos_remaining
	if game.tutorial.active:
		game.tutorial._load_section(int(game.tutorial._steps[game.tutorial.step_index].section))
	else:
		game.cancel_gesture();game.clear_effects();game.rewardui.reset();game.presentation.clear()
		for key in game.HISTORY.FIELDS:
			var value = snapshot.state[key]
			game.set(key, value.duplicate(true) if value is Array or value is Dictionary else value)
		game.rng.state = snapshot.state.rng_state
	game.normal_undos_remaining = budget
	game.history.clear();game.cancel_gesture();game.clear_effects()
	game.selected = -1;game.free_selected = false;game.hand_page = 0;game.hand_drawer = false
	game.handui.reset();game.board_info.begin_battle();game.treasureui.feedback = ""
	game.input_lock = 0.25;game.navigation_lock = 0.25
	game.route.save();game.queue_redraw()
	return true
