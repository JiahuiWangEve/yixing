extends RefCounted
const FIELDS = ["artillery_mode", "deploy_draw_used", "tuna_turns", "tuna_active", "player_skill", "free_card_uid", "free_selected", "player", "enemies", "deck", "discard", "hand", "hand_ids", "next_card_uid", "collection", "rewards", "stage", "turn", "lives", "energy", "basic_used", "card_move_used", "reinforcement_turns", "reinforcement_pending", "phase", "debug_target", "debug_remaining", "debug_reward_total", "logs", "notice", "initial_threat", "seed_value"]
var game
var entries: Array = []
var oldest_turn = 1
func _init(owner): game = owner
func clear():
	entries.clear();oldest_turn = 1
func capture() -> Dictionary:
	game.sync_hand_ids()
	var snapshot = {"rng_state": game.rng.state}
	for key in FIELDS:
		var value = game.get(key)
		snapshot[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return snapshot
func record(action: String):
	if game.tutorial.active or game.screen != "game": return
	entries.append({"action": action, "turn": game.turn, "state": capture()})
	trim()
func trim():
	oldest_turn = maxi(oldest_turn, maxi(1, game.turn - 3))
	while not entries.is_empty() and int(entries[0].turn) < oldest_turn: entries.pop_front()
func can_undo() -> bool:
	return game.screen == "game" and not game.tutorial.active and not entries.is_empty()
func undo() -> bool:
	if not can_undo(): return false
	var snapshot: Dictionary = entries.pop_back().state
	game.rewardui.reset()
	game.cancel_gesture()
	game.clear_effects()
	for key in FIELDS:
		var value = snapshot[key]
		game.set(key, value.duplicate(true) if value is Array or value is Dictionary else value)
	game.rng.state = snapshot.rng_state
	game.selected = -1;game.free_selected = false;game.navigation_lock = 0.0;game.input_lock = 0.0
	game.active_touch = -1;game.touch_dragged = true
	game.clear_effects()
	game.handui.reset()
	game.queue_redraw()
	return true
