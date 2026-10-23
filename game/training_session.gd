extends RefCounted
# Detached runtime. Never writes the expedition, unlocks, or settings.
var game
var backup: Dictionary = {}
var entry: Dictionary = {}
func _init(owner): game = owner
func restore(snapshot: Dictionary):
	for key in game.HISTORY.FIELDS:
		if snapshot.has(key):
			var value = snapshot[key]
			game.set(key, value.duplicate(true) if value is Array or value is Dictionary else value)
	game.rng.state = snapshot.rng_state
	game.cancel_gesture();game.clear_effects();game.history.clear();game.handui.reset()
	game.selected = -1;game.free_selected = false;game.navigation_lock = 0
	game.screen = "game";game.sync_hand_ids();game.queue_redraw()
func start(preset: Dictionary):
	if backup.is_empty():
		backup = {"battle": game.history.capture(), "route": game.route.state.duplicate(true),
			"checkpoint": game.battle_restart.snapshot.duplicate(true), "budget": game.normal_undos_remaining}
	game.route.state = {};game.battle_restart.clear();game.tutorial.stop()
	game.presentation.clear();game.card_picker.close();game.rewardui.reset();game.treasureui.feedback = ""
	if preset.get("snapshot") is Dictionary and not preset.snapshot.is_empty():
		restore(preset.snapshot)
	else:
		game.clear_effects();game.clear_battle_card_effects();game.history.clear();game.cancel_gesture()
		game.player_skill = preset.player_skill;game.player = preset.player
		game.lives = preset.lives;game.energy = preset.energy;game.artillery_mode = preset.artillery_mode
		game.stage = 1;game.turn = 1;game.phase = "play";game.screen = "game"
		game.seed_value = preset.seed;game.rng.seed = preset.seed
		game.basic_used = false;game.card_move_used = false;game.deploy_draw_used = false
		game.tuna_turns = 0;game.tuna_active = false;game.reinforcement_turns = 0;game.reinforcement_pending = 0
		game.hand = preset.hand.duplicate();game.deck = preset.deck.duplicate();game.deck.reverse()
		if preset.shuffle: game.shuffle(game.deck)
		game.discard = [];game.rewards = [];game.collection = preset.hand.duplicate() + preset.deck.duplicate()
		game.hand_ids = [];game.next_card_uid = 1;game.next_enemy_uid = 1;game.enemies = []
		game.encounter_state = {"config": {"id": "training", "chapter": 2, "tier": "training", "rules": []},
			"phases": 0, "ghosts": [], "waves": [], "cancelled": false, "guard_uids": []}
		for spec in preset.enemies:
			game.add_enemy(spec.kind, spec.pos, spec.get("period", 3))
			var enemy: Dictionary = game.enemies.back()
			for key in ["hp", "max_hp", "cd", "period", "stun", "ai_role", "heavy", "unyielding", "action_credits"]:
				if spec.has(key): enemy[key] = spec[key]
			enemy.max_hp = maxi(enemy.hp, enemy.get("max_hp", enemy.hp))
			enemy.original_spawn = spec.pos;enemy.action_credit_delay = 0
			if enemy.kind == "stake": enemy.permanent = spec.get("permanent", true);enemy.ttl = spec.get("ttl", 3)
		game.logs = [];game.notice = "演武试玩：不影响远征进度。";game.initial_threat = 0
		game.sync_hand_ids();game.free_card_uid = 0
		if preset.free_step: game.refresh_free_card()
		game.treasures.reset_battle();game.decoys.start_turn()
		game.clear_effects();game.handui.reset();game.input_lock = 0;game.navigation_lock = 0
		game.board_info.begin_battle();game.plan_intents()
	entry = game.history.capture()
	game.queue_redraw()
func reset() -> bool:
	if entry.is_empty() or game.input_lock > 0 or game.navigation_lock > 0 or game.presentation.active() or game.card_picker.active: return false
	restore(entry);game.treasureui.feedback = "";game.input_lock = 0.25;return true
func stop():
	game.presentation.clear();game.card_picker.close();game.treasureui.feedback = ""
	if not backup.is_empty():
		restore(backup.battle);game.route.state = backup.route.duplicate(true)
		game.battle_restart.snapshot = backup.checkpoint.duplicate(true)
		game.normal_undos_remaining = backup.budget
	backup = {};entry = {};game.screen = "training_editor"
