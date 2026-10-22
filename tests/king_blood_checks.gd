extends SceneTree
# Run with disposable user:// storage; exercises normal play/preview/pass/undo.
const KB = preload("res://king_blood.gd")
const R = preload("res://rules.gd")
var game
var checks = 0
var failures = 0

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("KING BLOOD: " + label)

func fresh(cards: Array = ["blood_edge"], life: int = 4, energy: int = 9, expedition: bool = false):
	game.player_skill = "king"
	if expedition: game.new_expedition();game.route.enter(0)
	else: game.new_run()
	game.enemies = [];add("g", Vector2i(4, 0), 99)
	game.player = Vector2i(4, 5);game.lives = life;game.energy = energy
	game.collection = cards.duplicate();game.hand = cards.duplicate();game.hand_ids = []
	game.deck = [];game.discard = [];game.rewards = []
	game.phase = "play";game.screen = "game";game.clear_effects();game.presentation.clear()
	game.input_lock = 0;game.navigation_lock = 0;game.sync_hand_views();game.history.clear()

func add(kind: String, pos: Vector2i, hp: int = 8) -> Dictionary:
	game.add_enemy(kind, pos, 999)
	var enemy: Dictionary = game.enemies.back();enemy.hp = hp;enemy.max_hp = hp
	return enemy

func settle():
	game.clear_effects();game.presentation.clear();game.input_lock = 0;game.navigation_lock = 0

func undo() -> bool:
	settle();return game.undo_action()

func hp_of(uid: int) -> int:
	for enemy in game.enemies:
		if enemy.uid == uid: return int(enemy.hp)
	return 0

func reject(index: int, target: Vector2i, label: String):
	var before = game.history.capture()
	check(not game.can_commit_card(index, target), label + " cannot commit")
	game.play_card(index, target)
	var same = true
	for key in ["energy", "lives", "hand", "hand_ids", "enemies", "player", "deck", "discard", "collection"]:
		if game.get(key) != before[key]: same = false
	check(same, label + " spends/mutates nothing")

func run():
	game = load("res://main.tscn").instantiate();root.add_child(game)
	game.settings.set_debug_mode(true);game.set_process(false)
	var wired = KB.IDS.all(func(id): return game.CARDS.has(id))
	check(wired, "three cards registered in main")
	if wired:
		check_metadata()
		check_geometry()
		check_legality()
		check_edge_damage()
		check_break_damage()
		check_last_stand()
		check_preview()
		check_death_priority()
		check_copy_undo()
		check_pass()
		check_pointer_input()
		check_triumph()
	print("KING BLOOD RESULT ", checks - failures, " passed, ", failures, " failed")
	game.free();quit(1 if failures else 0)

func check_metadata():
	fresh()
	check(game.card_cost("blood_edge") == 1 and game.card_cost("blood_break") == 3 and game.card_cost("last_stand") == 1, "printed energy costs 1/3/1")
	check(not game.is_consumable("blood_edge") and game.is_consumable("blood_break") and not game.is_consumable("last_stand"), "only blood break exhausts")
	check("blood_break" in game.UNTARGETED and "blood_edge" not in game.UNTARGETED and "last_stand" not in game.UNTARGETED, "cross attack is untargeted; line and adjacent attacks target")
	for identity in game.PROFILES.DATA:
		for id in KB.IDS:
			check(id not in game.PROFILES.DATA[identity].deck, id + " is not a starter for " + identity)
			check((id in game.PROFILES.DATA[identity].rewards) == (identity == "king"), id + " rewards belong only to king")
			check(id not in game.PROFILES.COMMON, id + " absent from common rewards")

func check_geometry():
	fresh()
	for step in KB.DIRECTIONS:
		var expected = [game.player + step, game.player + step * 2, game.player + step * 3]
		for distance in range(1, 4):
			var target: Vector2i = game.player + step * distance
			check(KB.direction(game.player, target) == step and KB.cells(game, "blood_edge", target) == expected, "any of three direction cells yields entire line " + str(target))
	for invalid in [game.player, Vector2i(5,4), Vector2i(6,3), Vector2i(8,5), Vector2i(-1,5), Vector2i(4,10)]:
		check(KB.direction(game.player, invalid) == Vector2i.ZERO and KB.cells(game,"blood_edge",invalid).is_empty(), "invalid line selector " + str(invalid))
	var cross = KB.cells(game, "blood_break", game.player)
	check(cross.size() == 8, "cross reaches exactly eight board cells")
	for cell in cross:
		var delta: Vector2i = cell - game.player
		check((delta.x == 0 or delta.y == 0) and absi(delta.x) + absi(delta.y) in [1,2], "cross has no diagonal/self cell " + str(cell))
	for origin in [Vector2i(0,0), Vector2i(8,9)]:
		game.player = origin
		check(KB.cells(game,"blood_break",origin).size() == 4, "corner cross clips to four " + str(origin))
		for target in KB.cells(game,"blood_break",origin): check(R.inside(target), "edge clipping stays on board")

func check_legality():
	for id in KB.IDS:
		fresh([id]);var target = game.player if id == "blood_break" else game.player + Vector2i.UP
		reject(0, target, id + " cannot swing empty")
		add("stake", game.player + Vector2i.UP)
		reject(0, target, id + " cannot swing at stake only")
		fresh([id]);add("p",game.player + Vector2i.UP)
		for identity in ["horse", "artillery"]:
			game.player_skill = identity;reject(0,target,id + " forbidden to " + identity)
		game.player_skill = "king";game.energy = game.card_cost(id) - 1
		reject(0,target,id + " insufficient energy")
	fresh();add("p",Vector2i(4,4));add("p",Vector2i(5,4))
	for invalid in [game.player, Vector2i(5,4), Vector2i(8,5), Vector2i(4,-1)]: reject(0,invalid,"line bad selector " + str(invalid))
	fresh(["last_stand"]);add("p",Vector2i(5,4));add("p",Vector2i(4,3))
	reject(0,Vector2i(5,4),"last stand diagonal")
	reject(0,Vector2i(4,3),"last stand distance two")
	fresh();add("stake",Vector2i(4,4));add("p",Vector2i(4,3))
	check(game.card_legal("blood_edge",Vector2i(4,4)), "stake selector still selects a direction with a real enemy behind it")

func check_edge_damage():
	for step in KB.DIRECTIONS:
		fresh()
		var victims: Array = []
		for distance in range(1,4): victims.append(add("p",game.player + step * distance,5))
		var far = add("p",game.player + step * 4,5)
		var diagonal = add("p",game.player + Vector2i(step.y,step.x) + step,5)
		var origin: Vector2i = game.player
		game.shield_charges = 1;game.basic_used = true;game.card_move_used = true;game.active_displacements = 2
		game.play_card(0,origin + step)
		check(victims.all(func(enemy): return enemy.hp == 3) and far.hp == 5 and diagonal.hp == 5, "blood edge hits entire line, no side/out-of-range " + str(step))
		check(game.lives == 3 and game.energy == 8 and game.player == origin and game.shield_charges == 1, "edge direct life cost ignores guard, no recoil " + str(step))
		check(game.basic_used and game.card_move_used and game.active_displacements == 2 and game.airdrop_recovery_turn == 0, "edge does not consume/reset movement or schedule recovery")
		check(game.hand.is_empty() and game.discard == ["blood_edge"] and game.phase == "play", "edge recycles without auto-ending turn")
	fresh();var stake = add("stake",Vector2i(4,4));var behind = add("p",Vector2i(4,3),6);var end = add("p",Vector2i(4,2),6)
	game.play_card(0,Vector2i(4,4))
	check(stake.hp == 8 and behind.hp == 4 and end.hp == 4, "edge passes through undamaged wooden stake")

func check_break_damage():
	fresh(["blood_break"])
	var victims: Array = []
	for cell in KB.cells(game,"blood_break",game.player): victims.append(add("p",cell,5))
	var diagonal = add("p",Vector2i(5,4),5);var far = add("p",Vector2i(4,2),5)
	game.shield_charges = 1;var origin: Vector2i = game.player
	game.play_card(0,game.player)
	check(victims.all(func(enemy): return enemy.hp == 2) and diagonal.hp == 5 and far.hp == 5, "cross damages all eight cells, no diagonal or third cell")
	check(game.lives == 3 and game.energy == 6 and game.shield_charges == 1 and game.player == origin, "cross pays three energy and direct one life only")
	check(game.phase == "play" and game.turn == 1 and game.airdrop_recovery_turn == 0 and not game.recovery_active(), "cross never skips/ends the current or next player turn")
	check(game.hand.is_empty() and game.discard.is_empty() and game.collection == ["blood_break"], "cross exhausts battle copy but preserves permanent collection")
	fresh(["blood_break"]);var stake = add("stake",Vector2i(4,4));var behind = add("p",Vector2i(4,3),6)
	game.play_card(0,game.player)
	check(stake.hp == 8 and behind.hp == 3, "cross passes through undamaged stake")

func check_last_stand():
	for life in [1,2,3,5]:
		fresh(["last_stand"],life);var target = add("p",Vector2i(4,4),7)
		game.play_card(0,target.pos)
		check(target.hp == (4 if life == 1 else 6) and game.lives == life and game.energy == 8, "last stand uses exactly-one-life branch " + str(life))
		check(game.discard == ["last_stand"] and game.player == Vector2i(4,5), "last stand recycles and never displaces")
	fresh(["blood_edge","last_stand"],2);var target = add("p",Vector2i(4,4),9)
	game.play_card(0,target.pos);game.play_card(0,target.pos)
	check(game.lives == 1 and target.hp == 4, "last stand reads life at play time after previous sacrifice")

func check_preview():
	for id in KB.IDS:
		for life in [1,4]:
			fresh([id],life)
			var one = add("p",Vector2i(4,4),2);add("p",Vector2i(4,3),5);add("p",Vector2i(5,5),5)
			var target: Vector2i = game.player if id == "blood_break" else one.pos
			var before = game.history.capture();var preview: Dictionary = game.board_info.preview(0,target)
			check(not preview.is_empty(), id + " board preview exists at life " + str(life))
			if preview.is_empty(): continue
			var expected = KB.preview(game,id,target)
			check(preview.affected == expected.affected and preview.self_damage == expected.self_damage and preview.self_defeat == expected.self_defeat, id + " preview uses shared rule plan")
			check(game.history.capture() == before, id + " preview is read-only including RNG")
			game.play_card(0,target)
			for hit in preview.affected: check(hp_of(hit.uid) == hit.hp_after, id + " preview matches real hp for UID " + str(hit.uid))
			check(game.lives == life - int(preview.self_damage) and (game.phase == "dead") == bool(preview.self_defeat), id + " self damage/defeat preview matches resolution")

func check_death_priority():
	for id in ["blood_edge","blood_break"]:
		fresh([id],1,9,true)
		game.enemies[0].pos = Vector2i(4,4);game.enemies[0].hp = KB.amount(game,id)
		game.route.state.pending_homework = ["spear_plus"];game.route.state.reward_debt = 1
		var before = game.collection.duplicate();var target: Vector2i = game.player if id == "blood_break" else Vector2i(4,4)
		check(game.can_commit_card(0,target), id + " lethal self-cost remains playable")
		game.play_card(0,target)
		check(game.lives == 0 and game.phase == "dead" and not game.general_alive(), id + " simultaneous enemy king kill loses before triumph heal")
		check(game.collection == before and game.rewards.is_empty() and not game.route.state.victory_recorded and game.route.state.reward_debt == 1 and game.route.state.pending_homework == ["spear_plus"], id + " defeat cannot grant rewards/homework")
		game.settle_victory();game.debug_skip()
		check(game.lives == 0 and game.phase == "dead", id + " later victory/debug calls cannot revive zero life")
		check(undo() and game.phase == "play" and game.lives == 1 and game.general_alive() and game.hand == [id], id + " undo restores lethal action and exhausted copy")
		game.lives = 2;game.play_card(0,target)
		check(game.phase == "reward" and game.lives == 2, id + " survivor pays one then receives exactly one triumph life")
		game.settle_victory();check(game.lives == 2, id + " triumph is not awarded twice")

func check_copy_undo():
	fresh(["blood_break","blood_break","blood_edge","last_stand"])
	var victim = add("p",Vector2i(4,4),9)
	var before = game.history.capture();var ids = game.hand_ids.duplicate()
	game.play_card(1,game.player)
	check(game.hand == ["blood_break","blood_edge","last_stand"] and game.hand_ids == [ids[0],ids[2],ids[3]], "exhaust removes only selected physical copy")
	check(game.collection == before.collection and game.discard.is_empty() and victim.hp == 6, "exhaust preserves collection and other copy")
	check(undo() and game.history.capture() == before, "undo restores exact copies, IDs, life, HP, energy and RNG")
	game.play_card(0,Vector2i(4,5));settle();game.play_card(0,Vector2i(4,5))
	check(game.hand == ["blood_edge","last_stand"] and game.discard.is_empty() and game.lives == 2, "two copies independently exhaust within one battle")
	fresh(["blood_edge","blood_edge"]);add("p",Vector2i(4,4),9);before = game.history.capture()
	game.play_card(1,Vector2i(4,4))
	check(game.hand == ["blood_edge"] and game.discard == ["blood_edge"], "nonconsumable removes one copy and recycles exactly one")
	check(undo() and game.history.capture() == before, "nonconsumable undo restores independent copies")

func check_pass():
	for id in KB.IDS:
		fresh([id],1,3);var victim = add("p",Vector2i(4,4),6)
		game.deck = ["sword"];game.shield_charges = 1
		var before = game.history.capture()
		check(game.pass_card(0), id + " three-energy pass succeeds")
		check(game.energy == 0 and game.lives == 1 and victim.hp == 6 and game.player == Vector2i(4,5) and game.shield_charges == 1 and game.airdrop_recovery_turn == 0, id + " pass never executes attack/self-cost/recovery")
		check(game.hand == ["sword"] and game.discard == [id] and game.collection == [id] and game.phase == "play", id + " pass draws once and recycles even consumable")
		check(undo() and game.history.capture() == before, id + " pass undo restores exact prior state")

func check_pointer_input():
	for size in [Vector2(1280,940),Vector2(390,844),Vector2(360,640)]:
		for drag in [false,true]:
			for distance in range(1,4):
				fresh();game.configure_layout(size);game.sync_hand_views()
				var victim = add("p",Vector2i(4,2),6)
				var target = Vector2i(4,5-distance)
				if drag:
					var start: Vector2 = game.handui.exposed_point(0)
					check(game.gesture.press(start), "blood edge starts drag " + str(size))
					game.gesture.motion(game.cell_pos(target))
					check(game.gesture.valid_target(), "drag accepts any 1-3 range direction selector")
					game.gesture.release(game.cell_pos(target))
				else:
					game.select_card(0);game.handle_click(game.cell_pos(target))
				check(game.hand.is_empty() and victim.hp == 4 and game.player == Vector2i(4,5) and game.lives == 3, "pointer direction applies full line " + str([size,drag,distance]))
		fresh();game.configure_layout(size);game.sync_hand_views();add("p",Vector2i(4,3))
		game.gesture.press(game.handui.exposed_point(0));game.gesture.motion(game.cell_pos(Vector2i(5,4)))
		check(not game.gesture.valid_target(), "diagonal drag is invalid " + str(size))
		game.gesture.release(game.cell_pos(Vector2i(5,4)))
		check(game.hand == ["blood_edge"] and game.lives == 4 and game.energy == 9, "invalid drag spends nothing")
	game.configure_layout(Vector2(1280,940))

func check_triumph():
	for life in [1,4,5]:
		fresh([],life);game.enemies = [];game.settle_victory()
		check(game.lives == mini(5,life+1) and game.phase == "reward", "triumph central life boundary " + str(life))
		var saved_life = game.lives;game.settle_victory();game.debug_skip()
		check(game.lives == saved_life, "repeated victory cannot heal twice " + str(life))
	for identity in ["horse","artillery"]:
		fresh([],1);game.player_skill = identity;game.enemies = [];game.settle_victory()
		check(game.lives == 1 and game.phase == "reward", identity + " never receives king passive")
	fresh([],1);game.tutorial.active = true;game.enemies = [];game.settle_victory()
	check(game.lives == 1 and game.phase == "reward", "scripted tutorials never receive triumph healing")
	game.tutorial.active = false
	fresh([],0);game.enemies = [];game.settle_victory()
	check(game.lives == 0 and game.phase == "play" and game.rewards.is_empty(), "zero-life victory call cannot heal or reward")
	# Reward-suppressed homework is still a real victory, not a healing exception.
	game.player_skill = "king";game.new_expedition();game.route.enter(0);settle();game.lives = 1
	game.route.state.pending_homework = ["spear_plus"];game.route.state.reward_debt = 1
	var collection = game.collection.duplicate();collection.append("spear_plus")
	game.debug_skip()
	check(game.lives == 2 and game.rewards.is_empty() and game.route.rewards_blocked() and game.collection == collection, "no-reward homework victory heals once and settles homework")
	check(game.route.resume() and game.lives == 2, "victory receipt reload preserves healed life")
	game.settle_victory();game.debug_skip();game.route.battle_victory()
	check(game.lives == 2 and game.collection == collection, "reloaded/repeated receipt cannot duplicate healing or homework")
	# Both chapter bosses use the same victory entry point.
	for chapter in [1,2]:
		game.player_skill = "king";game.new_expedition();game.route.generate(game.seed_value,chapter)
		game.route.state.visited = [0,3,5,6,8,11,14];game.route.state.current = 14
		game.route.enter(15);settle();game.lives = 1;game.debug_skip()
		check(game.lives == 2 and game.phase == ("reward" if chapter == 1 else "win"), "chapter boss heals one life " + str(chapter))
		game.settle_victory();game.debug_skip()
		check(game.lives == 2, "chapter boss repeated settlement does not heal " + str(chapter))
