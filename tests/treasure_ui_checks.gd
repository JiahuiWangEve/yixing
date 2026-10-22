extends SceneTree
# Focused read-only/UI-only assertions. Route transaction/save tests own the
# actual chapter transition; this suite never claims a synthetic fixture.
const T = preload("res://treasure_system.gd")
const ROUTE_TEST = preload("res://../tests/route_test_helpers.gd")
const OUT = "res://../verification/v0.15.0/treasure-ui/"
const SIZES = [Vector2(1280,940), Vector2(390,844), Vector2(360,640), Vector2(844,390)]
var game
var ui
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("TREASURE UI: " + label)
func snapshot() -> Dictionary:
	return {"route": game.route.state.duplicate(true), "battle": game.treasure_battle.duplicate(true), "energy": game.energy, "lives": game.lives,
		"collection": game.collection.duplicate(), "hand": game.hand.duplicate(), "rng": game.rng.state, "turn": game.turn, "phase": game.phase}
func touch(pos: Vector2, down: bool, canceled: bool = false, index: int = 1):
	var event = InputEventScreenTouch.new();event.position = pos;event.pressed = down;event.canceled = canceled;event.index = index
	game._input(event)
func drag(pos: Vector2, index: int = 1):
	var event = InputEventScreenDrag.new();event.position = pos;event.index = index;game._input(event)
func fixture(role: String, size: Vector2):
	game.information.clear();game.presentation.clear();game.tutorial.stop();game.player_skill = role;game.new_expedition();game.configure_layout(size)
	game.route.state.treasure_id = "";game.route.state.treasure_choices = T.ids_for(role);game.screen = "treasure_choice"
	game.input_lock = 0;game.navigation_lock = 0;game.encounter_info_open = false;ui.tick(0)
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);ui = game.treasureui
	for size in SIZES:
		for role in ["king", "horse", "artillery"]:
			fixture(role, size)
			var before = snapshot();var fixed = ui.choice_ids()
			check(fixed == T.ids_for(role) and fixed.size() == 3, "three saved profession choices")
			check(ui.columns() == (1 if game.mobile_layout and not game.compact_landscape else 3), "responsive columns")
			check(ui.area().end.y <= game.ui_size.y - 80, "footer stays outside scroll area")
			for index in fixed.size():
				ui.scroll_y = clampf(ui.card_rect(index).get_center().y + ui.scroll_y - ui.area().get_center().y, 0, ui.scroll_limit())
				var rect: Rect2 = ui.card_rect(index);var visible: Rect2 = rect.intersection(ui.area())
				check(visible.size.x > 44 and visible.size.y > 44, "each saved choice reachable")
				var description: String = T.DATA[fixed[index]].get("summary", T.DATA[fixed[index]].description)
				var rows = ui.wrapped(description, rect.size.x - (148 if ui.portrait() else 40), 18)
				var baseline = (38 if ui.portrait() else 160) + 34 + maxi(0, rows.size() - 1) * 24
				check(baseline < rect.size.y - 12, "complete choice body fits at18px")
				check(ui.choice_at(visible.get_center()) == fixed[index], "hit target maps exact saved ID")
			ui.scroll_y = 0;ui.sync()
			var start: Vector2 = ui.card_rect(0).intersection(ui.area()).get_center()
			for keycode in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6,KEY_7,KEY_SPACE,KEY_ENTER,KEY_KP_ENTER,KEY_ESCAPE]:
				var key = InputEventKey.new();key.keycode = keycode;key.pressed = true;game._input(key)
			check(snapshot() == before and game.screen == "treasure_choice", "all battle shortcuts captured")
			touch(start, true);touch(start, false, true)
			check(not ui.claimed and snapshot() == before, "canceled release never claims")
			touch(start, true);drag(start + Vector2(0, 30));drag(start);touch(start, false)
			check(not ui.claimed and snapshot() == before, "drag back to original cannot claim")
			ui.scroll_y = 0;start = ui.card_rect(0).intersection(ui.area()).get_center()
			touch(start, true);touch(start + Vector2(25,0), true, false, 2);touch(start, false);touch(start + Vector2(25,0), false, false, 2)
			check(not ui.claimed and ui.pointer == -2 and snapshot() == before, "multitouch sequence cannot claim")
			touch(Vector2(5,5), true);touch(start, false)
			check(not ui.claimed and snapshot() == before, "outside press cannot claim on inside release")
			touch(start, true);game.cancel_gesture();touch(start, false)
			check(not ui.claimed and snapshot() == before, "blur/web/resize cancellation hook drops capture")
			check(ui.choice_ids() == fixed, "inspection/scroll/input never rerolls choices")
		# No treasure creates neither an icon inspection nor an empty slot.
		game.screen = "map";game.route.state.treasure_id = "";game.route.state.treasure_choices = []
		check(ui.inspect_at(ui.icon_rect().get_center()).is_empty(), "unowned treasure has no inspector")
		for id in T.DATA:
			game.player_skill = T.DATA[id].role;game.route.state.treasure_id = id;game.treasures.reset_battle()
			game.treasure_battle.tiger_moves = 2;game.treasure_battle.spring_kills = 1;game.treasure_battle.talisman_used = true
			game.treasure_battle.wind_used = true;game.treasure_battle.tassel_ready = true;game.treasure_battle.gate_ready = true;game.treasure_battle.axle_used = true
			game.screen = "map";var before = snapshot();var info = ui.inspect_at(ui.icon_rect().get_center())
			check(info.get("lines", []) == [T.DATA[id].description], "map shows only complete rules, never stale battle state")
			check(snapshot() == before, "map inspection side-effect free")
			game.screen = "game";game.phase = "play";before = snapshot();info = ui.inspect_at(ui.icon_rect().get_center())
			check(info.title == T.DATA[id].name and info.lines == game.treasures.status().lines, "battle inspection canonical effect and current status")
			check(snapshot() == before, "battle inspection side-effect free")
			check(ui.icon_rect().size.x >= 44 and ui.icon_rect().size.y >= 44, "touch hit area at least44px")
			check(not ui.icon_rect().intersects(game.home_rect()) and not ui.icon_rect().intersects(game.RESTART_RECT) and not ui.icon_rect().intersects(game.UNDO_RECT), "icon does not overlap top controls")
			check(Rect2(Vector2.ZERO,game.ui_size).encloses(ui.icon_rect()), "icon inside safe viewport")
		game.player_skill = "king";game.route.state.treasure_id = "tiger_tally";game.treasures.reset_battle()
		game.screen = "map";game.route.deck_view = false;game.route.travel_target = -1
		var pos: Vector2 = ui.icon_rect().get_center();var before = snapshot()
		var hover = InputEventMouseMotion.new();hover.position = pos;game.information.input_event(hover);game.information.tick(0.29)
		check(not game.information.visible, "hover waits0.3s")
		game.information.tick(0.02);check(game.information.visible and game.information.data.has("treasure_id"), "hover shares information popup")
		game.information.clear();touch(pos,true);game.information.tick(0.39);check(not game.information.visible, "touch waits0.4s")
		game.information.tick(0.02);check(game.information.visible, "stationary hold opens treasure rules")
		drag(pos + Vector2(0,20));game.information.tick(1);check(not game.information.visible, "moved hold stays dismissed")
		touch(pos + Vector2(0,20),false);check(snapshot() == before, "hold and scroll preserve all gameplay")
		game.screen = "game";ui.trigger("revive");ui.tick(0.8);check(ui.feedback.is_empty(), "revival pulse expires without blocking input")
	make_replays()
	game.queue_free();print("TREASURE UI RESULT %d checks, %d failures" % [checks, failures]);quit(1 if failures else 0)

func point(pos: Vector2) -> Array: return [pos.x,pos.y]
func rectangle(rect: Rect2) -> Array: return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]
func popup_rectangle() -> Array:
	var before = snapshot()
	game.information.candidate(ui.icon_rect().get_center(), "mouse");game.information.tick(0.31)
	check(game.information.visible, "fixture popup opens through shared hover delay")
	var result = rectangle(game.information.area)
	game.information.clear()
	check(snapshot() == before, "fixture popup measurement changes no gameplay/save state")
	return result
func save_fixture(filename: String):
	game.route.save()
	check(game.route.save_error == OK, "fixture saved through production route.save")
	check(game.route.valid_snapshot(game.route.state, game.history.capture(), game.screen), "fixture validates: " + filename)
	FileAccess.open(OUT + "fixtures/" + filename, FileAccess.WRITE).store_string(FileAccess.get_file_as_string(game.route.SAVE))
func pending_fixture(role: String, size: Vector2):
	game.player_skill = role;game.seed_value = 150015;game.tutorial.stop();game.new_expedition();game.configure_layout(size)
	var boss = ROUTE_TEST.kind_id(game.route, "boss");ROUTE_TEST.before(game.route, boss);game.route.enter(boss)
	game.settle_victory();game.presentation.clear();game.input_lock = 0;game.navigation_lock = 0;game.choose_reward(-1)
	check(game.screen == "treasure_choice" and game.route.chapter() == 1, "ordinary boss reward reaches saved mandatory treasure choice")
	ui.tick(0)
func make_replays():
	DirAccess.make_dir_recursive_absolute(OUT + "fixtures")
	var replays: Array = []
	for size in SIZES:
		for role in ["king", "horse", "artillery"]:
			pending_fixture(role,size)
			var filename = "pending-%s-%d.cfg" % [role, int(size.x)]
			save_fixture(filename)
			var pending_save = FileAccess.get_file_as_string(game.route.SAVE)
			var ids = ui.choice_ids()
			var replay = {"viewport": point(size), "logical_size": point(game.ui_size), "role": role, "fixture": filename,
				"choice_taps": [], "choice_ids": ids, "choice_scrolls": [], "choices": [], "grid": rectangle(ui.area()), "scroll_limit": ui.scroll_limit(),
				"expected_chapter": 2, "claimed_fixtures": []}
			for index in ids.size():
				var rect: Rect2 = ui.card_rect(index);var visible: Rect2 = rect.intersection(ui.area())
				replay.choice_taps.append(point(visible.get_center()) if visible.size.y >= 44 else null)
				var scroll = clampf(rect.get_center().y - ui.area().get_center().y, 0, ui.scroll_limit())
				replay.choice_scrolls.append({"scroll": scroll, "tap": point(rect.get_center() - Vector2(0,scroll))})
				replay.choices.append({"id":ids[index],"scroll":scroll,"tap":point(rect.get_center() - Vector2(0,scroll))})
			game.screen = "home";replay.resume = point(game.frontend.button_rect(3).get_center())
			for index in ids.size():
				FileAccess.open(game.route.SAVE, FileAccess.WRITE).store_string(pending_save)
				check(game.route.resume(), "pending choice survives normal reload")
				ui.tick(0);ui.scroll_y = float(replay.choice_scrolls[index].scroll)
				var target = ui.card_rect(index).intersection(ui.area()).get_center()
				touch(target,true);touch(target,false)
				check(game.screen == "map" and game.route.chapter() == 2 and game.route.state.treasure_id == ids[index], "single valid release claims exact saved treasure")
				var claimed = snapshot();touch(target,false)
				check(snapshot() == claimed, "duplicate release cannot claim twice or advance map")
				ui.tick(0)
				var map_file = "map-%s-%d.cfg" % [ids[index], int(size.x)]
				var battle_file = "battle-%s-%d.cfg" % [ids[index], int(size.x)]
				save_fixture(map_file)
				var entry = {"id":ids[index], "map_fixture":map_file, "map_icon":point(ui.icon_rect().get_center()), "map_popup":popup_rectangle(), "expected_chapter":2}
				check(game.route.resume() and game.route.state.treasure_id == ids[index], "claimed map reload retains one treasure")
				game.route.enter(0);game.presentation.clear();game.input_lock = 0;game.navigation_lock = 0;game.clear_effects()
				save_fixture(battle_file);entry.battle_fixture = battle_file;entry.battle_icon = point(ui.icon_rect().get_center());entry.battle_popup = popup_rectangle()
				check(game.route.resume() and game.route.state.treasure_id == ids[index], "claimed battle reload retains treasure")
				replay.claimed_fixtures.append(entry)
				if index == 0:
					replay.map_fixture = map_file;replay.battle_fixture = battle_file;replay.icon = entry.map_icon;replay.map_icon = entry.map_icon;replay.battle_icon = entry.battle_icon;replay.expected_treasure_id = ids[index];replay.map_popup = entry.map_popup;replay.battle_popup = entry.battle_popup
			replays.append(replay)
	FileAccess.open(OUT + "replays.json",FileAccess.WRITE).store_string(JSON.stringify({"schema":1,"web_save_key":game.route.WEB_SAVE_KEY,"replays":replays},"  ") + "\n")
