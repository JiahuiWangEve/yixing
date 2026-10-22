extends SceneTree
const RULES = preload("res://rules.gd")
var game
var passed = 0
var failed = 0
const RETIRED = ["push", "stun", "swap"]
func check(ok: bool, label: String):
	if ok:
		passed += 1
		print("PASS ", label)
	else:
		failed += 1
		push_error("TUTORIAL: " + label)
func settle():
	game.clear_effects()
	game.navigation_lock = 0.0
	game.tutorial.tick(2.0)
func _initialize(): call_deferred("run_checks")
func run_checks():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	for lesson in 5:
		for reward_mode in (["add", "skip"] if lesson == 4 else ["skip"]):
			game.start_tutorial(lesson)
			check(game.tutorial.step_count() > 0, "lesson %d has fixed steps" % lesson)
			var count = game.tutorial.step_count()
			for step in count:
				check(game.tutorial.step_index == step and not game.tutorial.lesson_complete, "lesson %d step %d ready" % [lesson, step])
				if game.tutorial.step_index != step or game.tutorial.lesson_complete: break
				var spec: Dictionary = game.tutorial._steps[step]
				var valid = true
				for pile in [game.collection, game.deck, game.hand, game.discard, game.rewards]:
					for card in pile:
						valid = valid and card not in RETIRED and game.CARDS.has(card)
				check(valid, "lesson %d step %d uses current cards only" % [lesson, step])
				if lesson == 1 and step == 4:
					var elephant = RULES.occupied(Vector2i(5, 3), game.enemies)
					check(elephant >= 0 and game.enemies[elephant].hp == 3 and game.enemies[elephant].max_hp == 3, "elephant lesson starts with current three-HP elephant")
					check(game.hand == ["sword", "sword", "sword", "horse"] and game.energy == 3, "elephant lesson supplies exactly three swords and three energy")
				if spec.get("free", false):
					var escaped = false
					for y in 10:
						for x in 9:
							var cell = Vector2i(x, y)
							if not escaped and game.basic_legal(cell) and not RULES.threatened(cell, game.enemies):
								game.basic_move(cell)
								escaped = true
					check(escaped, "free threat practice has safe legal move")
					settle()
				match str(spec.action):
					"select": game.select_card(game.hand.find(spec.card))
					"cancel": game.cancel_selection()
					"move": game.basic_move(spec.target)
					"play": game.play_card(game.hand.find(spec.card), spec.target)
					"discard": game.discard_hand(0)
					"pass": game.pass_card(game.hand.find(spec.card))
					"reward":
						var before_cards = game.collection.duplicate()
						game.delete_reward(0)
						check(game.phase == "reward" and game.collection == before_cards, "tutorial rejects retired permanent reward deletion")
						game.choose_reward(0 if reward_mode == "add" else -1)
					"end_turn": game.end_turn()
				if lesson == 1 and step in [4, 5]:
					var elephant = RULES.occupied(Vector2i(5, 3), game.enemies)
					check(elephant >= 0 and game.enemies[elephant].hp == 6 - step, "elephant survives sword %d with correct remaining HP" % (step - 3))
				if lesson == 1 and step == 6:
					check(RULES.occupied(Vector2i(5, 3), game.enemies) < 0, "third tutorial sword actually kills elephant")
					check(game.energy == 0 and game.hand == ["horse"], "three sword hits spend all three energy and retain horse")
				if lesson == 1 and step == 7:
					check(game.energy == 3 and game.hand == ["horse"], "elephant lesson end turn restores energy and retains horse")
				check(not game.tutorial._retry_pending and game.tutorial._pending_step == step + 1, "lesson %d step %d %s achieves observed success (%s)" % [lesson, step, spec.action, reward_mode])
				if game.tutorial._retry_pending or game.tutorial._pending_step != step + 1: break
				settle()
			check(game.tutorial.lesson_complete, "lesson %d completes (%s)" % [lesson, reward_mode])
			check(game.tutorial.finished == (lesson == 4), "lesson %d final completion flag" % lesson)
		game.tutorial.restart()
		var skipped = 0
		while not game.tutorial.lesson_complete and skipped < 10:
			game.tutorial.skip_step()
			skipped += 1
		check(game.tutorial.lesson_complete, "lesson %d sections can be skipped safely" % lesson)
	print("TUTORIAL RESULT ", passed, " passed, ", failed, " failed")
	game.queue_free()
	quit(1 if failed else 0)
