extends SceneTree
# Ordinary production saves plus projected hit geometry. The Web runner drives
# only canvas mouse/touch events; no runtime hooks or debug route mutation.
const OUT = "res://../verification/v0.14.12/map-single-tap/"
var game
var checks = 0
var failures = 0
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1;push_error(message)
func _initialize(): call_deferred("run")
func point(value: Vector2) -> Array: return [value.x, value.y]
func rectangle(value: Rect2) -> Array: return [value.position.x, value.position.y, value.size.x, value.size.y]
func touch(pos: Vector2, pressed: bool):
	var event = InputEventScreenTouch.new();event.index = 0;event.position = pos;event.pressed = pressed;game._input(event)
func popup(pos: Vector2, source: String) -> Rect2:
	var info = load("res://information_popup.gd").new(game)
	info.data = game.route.inspect_at(pos);info.source = source;info.position = pos;info.layout();return info.area
func run():
	DirAccess.make_dir_recursive_absolute(OUT + "fixtures")
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.settings.set_debug_mode(true)
	var reports = []
	for size in [Vector2(1280, 940), Vector2(390, 844), Vector2(360, 640), Vector2(844, 390)]:
		game.configure_layout(size);game.seed_value = 14120;game.new_expedition();game.presentation.clear();game.route.tick(0)
		var route = game.route
		var pos = route.hit_rect(route.state.nodes[0]).get_center()
		var blank = route.map_rect().position + Vector2(4, 4)
		var unavailable = -1
		for node in route.state.nodes:
			if node.id not in route.legal() and route.map_rect().encloses(route.hit_rect(node)):
				unavailable = node.id;break
		check(unavailable >= 0, "fixture exposes a nonlegal landmark")
		check(route.node_at(pos) == 0 and route.node_at(blank) == -1, "fixture uses actual legal hitbox and blank area")
		var initial = route.state.duplicate(true)
		route.save();check(route.save_error == OK and route.valid_snapshot(route.state, game.history.capture(), game.screen), "ordinary map snapshot validates")
		var name = "map-%d.cfg" % size.x
		FileAccess.open(OUT + "fixtures/" + name, FileAccess.WRITE).store_string(FileAccess.get_file_as_string(route.SAVE))
		var report = {"viewport": point(size), "logical_size": point(game.ui_size), "fixture": name, "point": point(pos), "hit": rectangle(route.hit_rect(route.state.nodes[0])), "blank": point(blank), "unavailable": point(route.hit_rect(route.state.nodes[unavailable]).get_center()), "unavailable_id": unavailable, "mouse_popup": rectangle(popup(pos, "mouse")), "touch_popup": rectangle(popup(pos, "touch")), "home": point(route.home_rect().get_center()), "deck": point(route.deck_rect().get_center())}
		game.screen = "home";report.resume = point(game.frontend.button_rect(3).get_center());game.screen = "map"
		route.click(route.deck_rect().get_center());report.close_deck = point(game.card_picker.cancel_rect().get_center());game.card_picker.cancel()
		route.ensure_road_cache();var builds = route.road_cache_builds;var work = route.road_segment_tests
		for iteration in 20:
			touch(pos, true);game.information.tick(0.41);touch(pos, false);route.ensure_road_cache()
			check(game.information.visible and game.information.sticky and route.selected_node == 0, "hold release stays visually inspectable")
			touch(blank, true);touch(blank, false);route.ensure_road_cache()
		check(route.state == initial and route.road_cache_builds == builds and route.road_segment_tests == work, "repeated real inspection and clearing do not rebuild roads or mutate run")
		touch(pos, true);touch(pos, false);check(route.travel_target == 0, "ordinary short release starts first march")
		route.tick(0.2);var elapsed = route.travel_elapsed;touch(pos, true);touch(pos, false)
		check(route.travel_elapsed == elapsed and route.travel_target == 0, "duplicate input does not restart march")
		route.tick(route.TRAVEL_SECONDS);check(game.screen == "game" and route.state.pending == 0, "single tap reaches battle")
		reports.append(report)
	FileAccess.open(OUT + "replays.json", FileAccess.WRITE).store_string(JSON.stringify(reports, "  "))
	game.free();print("MAP SINGLE TAP FIXTURES: %d checks; %d failures; %d replays" % [checks, failures, reports.size()]);quit(1 if failures else 0)
