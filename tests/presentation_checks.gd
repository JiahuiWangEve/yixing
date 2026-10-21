extends SceneTree
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("PRESENTATION: " + label)
func fresh():
	game.new_expedition();game.route.enter(0);game.input_lock = 0;game.navigation_lock = 0
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.settings.set_debug_mode(true);game.set_process(false)
	for chapter in [1,2]:
		for kind in ["battle","boss"]:
			game.new_expedition();game.route.generate(4242,chapter)
			if kind == "boss": game.route.state.current = 14;game.route.state.visited = [0,3,5,6,9,11,14]
			var target = 15 if kind == "boss" else 0
			game.route.enter(target);game.debug_skip()
			var expected = game.collection.duplicate();var reward = game.rewards.duplicate()
			check(game.presentation.kind == "victory", "all battle tiers show victory seal")
			check(game.phase == ("win" if chapter == 2 and kind == "boss" else "reward"), "underlying outcome settled immediately %s %s actual %s" % [chapter,kind,game.phase])
			game.handle_click(game.rewardui.choice_rect(0).get_center())
			check(game.collection == expected and game.rewards == reward, "reward input locked during seal")
			game.presentation.tick(0.5);check(game.presentation.active(), "seal visible after brief pause")
			game.presentation.tick(0.6);check(not game.presentation.active(), "seal completes within 1.1 seconds")
			game.debug_skip();check(not game.presentation.active(), "repeat victory call cannot replay stamp")
	fresh();game.lives = 0;game.debug_skip();check(not game.presentation.active(), "zero life never stamps victory")
	fresh();game.route.state.reward_debt = 1;game.route.state.pending_homework = ["sword_plus"];game.debug_skip()
	check(game.presentation.active() and game.route.rewards_blocked(), "homework no-reward victory still stamps")
	var before = game.collection.duplicate();check(game.route.resume(), "settled victory saved before animation")
	check(not game.presentation.active() and game.collection == before and game.route.rewards_blocked(), "reload skips animation without duplicating homework")
	fresh();game.debug_skip();game.choose_reward(-1);game.presentation.clear()
	game.route.state.nodes[1].event_id = "manual";game.route.enter(1);game.collection = ["sword", "sword", "spear"]
	game.route.refresh_choices();var index = game.route.random_upgrade_index();var old = game.collection[index]
	for i in game.route.choices.size():
		if game.route.choices[i].action == "random_upgrade": game.route.resolve(i);break
	game.route.resolve(0)
	check(game.presentation.kind == "upgrade" and game.presentation.old_id == old and game.presentation.new_id == game.route.UPGRADES.upgraded_id(old), "animation captures actual physical card old/new")
	check(game.presentation.card_index == index and game.screen == "map", "random transaction committed once before presentation")
	before = game.collection.duplicate();game.handle_click(game.route.footer_rect(0).get_center())
	check(game.collection == before and not game.card_picker.active, "upgrade modal blocks underlying map")
	game.presentation.tick(0.5);check(game.presentation.active(), "old to new transition has readable duration")
	game.presentation.tick(1.31);check(not game.presentation.active(), "upgrade returns automatically")
	check(game.route.resume() and game.collection == before and not game.presentation.active(), "reload never rerolls or repeats upgrade")
	# Read-only deck browsing preserves physical copies and map camera exactly.
	game.route.selected_node = -1;game.route.scroll_y = 123
	var camera = game.route.scroll_y;before = game.collection.duplicate()
	game.route.click(game.route.footer_rect(0).get_center())
	check(game.card_picker.active and game.card_picker.action == "view", "existing map entry opens reused grid")
	game.card_picker.selected = 0;game.card_picker.confirm()
	check(game.card_picker.active and game.collection == before, "read-only grid cannot transact")
	game.card_picker.cancel();check(game.route.scroll_y == camera and game.route.selected_node == -1 and game.collection == before, "close restores map camera and selection")
	game.queue_free();print("PRESENTATION RESULT %d checks, %d failures" % [checks, failures]);quit(1 if failures else 0)
