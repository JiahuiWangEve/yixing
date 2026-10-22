extends SceneTree
const T = preload("res://../tests/route_test_helpers.gd")
const OUT = "res://../verification/v0.14.3/picker/"
var game
var reports = []
func _initialize(): call_deferred("run")
func point(p: Vector2) -> Array: return [p.x,p.y]
func run():
	DirAccess.make_dir_recursive_absolute(OUT + "fixtures")
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	for size in [Vector2(1280,940),Vector2(390,844),Vector2(360,640),Vector2(844,390)]:
		for action in ["remove", "upgrade", "focus", "homework"]:
			if game.card_picker.active: game.card_picker.close()
			game.configure_layout(size);game.player_skill = "king";game.seed_value = 14343;game.new_expedition()
			game.route.enter(0);game.route.complete()
			T.enter_next(game, "camp" if action == "remove" else ("workshop" if action == "upgrade" else "event"), "manual");game.collection = []
			for i in 24: game.collection.append("sword" if action == "upgrade" else (["sword", "sword_plus", "fatigue", "airdrop"][i % 4]))
			game.route.refresh_choices();game.route.save()
			assert(game.route.valid_snapshot(game.route.state, game.history.capture(), "route_choice"))
			var name = action + "-" + str(int(size.x))
			FileAccess.open(OUT + "fixtures/" + name + ".cfg", FileAccess.WRITE).store_string(FileAccess.get_file_as_string(game.route.SAVE))
			var report = {"name": name, "action": action, "viewport": point(size), "logical_size": point(game.ui_size), "fixture": name + ".cfg", "before": game.collection.duplicate()}
			game.screen = "home";report.resume = point(game.frontend.button_rect(3).get_center());game.screen = "route_choice"
			for i in game.route.choices.size():
				if game.route.choices[i].action == "select_" + action:
					report.open = point(game.route.row_rect(i).get_center());game.route.resolve(i);break
			var picker = game.card_picker
			report.first = point(picker.card_rect(0).get_center());report.cancel = point(picker.cancel_rect().get_center());report.confirm = point(picker.confirm_rect().get_center())
			report.drag_from = point(Vector2(picker.grid_rect().get_center().x, picker.grid_rect().end.y - 15))
			report.drag_to = point(Vector2(picker.grid_rect().get_center().x, picker.grid_rect().position.y + 15))
			report.swipes = ceili(picker.scroll_limit() / (report.drag_from[1] - report.drag_to[1])) + 1
			picker.scroll_y = picker.scroll_limit();report.last = point(picker.card_rect(23).get_center())
			assert(picker.grid_rect().has_point(picker.card_rect(23).get_center()))
			picker.selected = 23;picker.confirm();game.route.save()
			report.after = game.collection.duplicate();report.homework = game.route.state.pending_homework.duplicate();report.debt = game.route.state.reward_debt
			reports.append(report)
	FileAccess.open(OUT + "replays.json", FileAccess.WRITE).store_string(JSON.stringify(reports, "  "))
	game.queue_free();print("PICKER WEB FIXTURES ", reports.size(), " valid production saves");quit()
