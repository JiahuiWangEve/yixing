extends SceneTree
const T = preload("res://../tests/route_test_helpers.gd")
# Native preferences and input-routing checks. No physical-audio claim.
const SETTINGS = preload("res://game_settings.gd")
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("SOUND SETTINGS: " + label)
	else: print("PASS ", label)
func start_game():
	if is_instance_valid(game): game.free()
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
func key(code: int, ctrl: bool = false, echo: bool = false):
	var event = InputEventKey.new();event.keycode = code;event.pressed = true;event.ctrl_pressed = ctrl;event.echo = echo
	game._input(event)
func tap(pos: Vector2):
	var event = InputEventScreenTouch.new();event.index = 0;event.position = pos;event.pressed = true
	game._input(event);event.pressed = false;game._input(event)
func old_sound_rect() -> Rect2:
	if game.compact_landscape: return Rect2(830, 12, 106, 64)
	if game.mobile_layout: return Rect2(220, 12, 88, 46)
	return Rect2(913, 20, 88, 40)
func no_old_toggle(label: String):
	var muted: bool = game.audio_system.muted
	game.handle_click(old_sound_rect().get_center())
	check(game.audio_system.muted == muted, "former top sound hitbox cannot toggle on " + label)
	# That location can now open the map deck viewer. Dismiss normally before
	# this fixture directly switches screens for its next independent case.
	if game.card_picker.active: key(KEY_ESCAPE)
func run():
	DirAccess.remove_absolute(SETTINGS.SAVE)
	start_game()
	check(not game.audio_system.muted and not game.settings.audio_muted, "fresh preferences start with sound enabled")
	check(game.frontend.entries() == ["开始游戏", "教程", "设置", "继续山河棋路存档", "调试模式：关"], "home replaces only index two and retains Continue/debug indices")
	var config = ConfigFile.new();config.set_value("settings", "debug_mode", true);config.save(SETTINGS.SAVE)
	start_game()
	check(game.settings.debug_mode and not game.audio_system.muted, "legacy debug-only preference remains enabled; sound defaults on")
	game.handle_click(game.frontend.button_rect(2).get_center())
	check(game.screen == "settings" and not game.audio_system.muted, "former menu sound button now navigates without toggling")
	check(game.frontend.entries() == ["声音：开启", "返回首页"], "settings contains only sound and return")
	game.audio_system.unlock();game.audio_system.play_cue("land", 1.0)
	check(game.audio_system.played_events.size() > 0, "enabled audio reaches cue scheduling without testing physical output")
	game.handle_click(game.frontend.button_rect(0).get_center())
	check(game.audio_system.muted and game.settings.audio_muted and game.frontend.entries()[0] == "声音：关闭", "sound row disables audio and updates status")
	var played: int = game.audio_system.played_events.size()
	game.audio_system.play_cue("land", 2.0)
	check(game.audio_system.played_events.size() == played, "muted audio does not schedule additional cues")
	for voice in game.audio_system.voices: check(not voice.playing, "mute stops every playback voice")
	config.load(SETTINGS.SAVE)
	check(config.get_value("settings", "audio_muted", false) and config.get_value("settings", "debug_mode", false), "native write stores mute while preserving debug preference")
	start_game();game.open_settings()
	check(game.audio_system.muted and game.settings.debug_mode and game.frontend.entries()[0] == "声音：关闭", "fresh scene restores audio and debug preferences")
	game.handle_click(game.frontend.button_rect(1).get_center())
	check(game.screen == "home" and game.audio_system.muted, "return button preserves sound")
	game.frontend.activate(4);start_game()
	check(not game.settings.debug_mode and game.audio_system.muted, "changing debug does not overwrite audio preference")
	for size in [Vector2(1280,940), Vector2(390,844), Vector2(360,640), Vector2(844,390)]:
		game.configure_layout(size);game.show_home();no_old_toggle("home " + str(size))
		tap(game.frontend.button_rect(2).get_center())
		check(game.screen == "settings", "touch opens settings " + str(size))
		for i in game.frontend.entries().size():
			check(Rect2(Vector2.ZERO, game.ui_size).encloses(game.frontend.button_rect(i)) and game.frontend.button_rect(i).size.y >= 48, "setting touch target fits " + str(size))
		var muted: bool = game.audio_system.muted
		tap(game.frontend.button_rect(0).get_center())
		check(game.audio_system.muted != muted, "touch toggles once " + str(size))
		var snapshot = game.history.capture();var quota: int = game.normal_undos_remaining
		for code in [KEY_SPACE, KEY_ENTER, KEY_Z]: key(code, code == KEY_Z)
		key(KEY_ESCAPE, false, true)
		check(game.screen == "settings" and game.history.capture() == snapshot and game.normal_undos_remaining == quota, "settings blocks gameplay shortcuts and Escape repeat " + str(size))
		key(KEY_ESCAPE)
		check(game.screen == "home", "Escape returns home " + str(size))
		for menu in ["skill_selection", "tutorial_menu", "tutorial_pause", "tutorial_complete", "debug_profile", "debug_menu"]:
			game.screen = menu;no_old_toggle(menu + " " + str(size))
			check(not game.frontend.entries().any(func(entry): return entry.begins_with("声音")), "no sound row on " + menu)
		game.new_run();game.clear_effects();game.navigation_lock = 0
		for phase in ["play", "discard", "reward", "dead", "win"]:
			game.phase = phase;no_old_toggle("battle " + phase + " " + str(size))
		game.start_tutorial(0);game.clear_effects();no_old_toggle("tutorial " + str(size))
		game.new_expedition();no_old_toggle("map " + str(size))
		game.route.state.current = 0;game.route.state.visited = [0];T.enter_next(game, "event");no_old_toggle("route choice " + str(size))
		game.show_home();game.open_settings();tap(game.frontend.button_rect(1).get_center())
		check(game.screen == "home", "touch return button " + str(size))
	# Preferences do not live in expedition snapshots; new runs and Continue keep them.
	game.new_expedition();game.route.save();game.show_home();game.open_settings()
	var saved = FileAccess.get_file_as_string(game.route.SAVE)
	game.audio_system.set_muted(true);game.frontend.activate(1);game.frontend.activate(3)
	check(game.screen == "map" and game.audio_system.muted and FileAccess.get_file_as_string(game.route.SAVE) == saved, "Continue keeps mute and does not rewrite expedition from settings")
	game.new_expedition();check(game.audio_system.muted, "new expedition preserves mute")
	game.show_home();game.open_settings();game.frontend.activate(0)
	start_game();check(not game.audio_system.muted, "re-enabled sound survives restart")
	config = ConfigFile.new();config.set_value("settings", "audio_muted", "wrong type");config.set_value("settings", "debug_mode", true);config.save(SETTINGS.SAVE)
	start_game();check(not game.audio_system.muted and game.settings.debug_mode, "malformed sound field safely defaults without losing valid debug")
	check(not FileAccess.get_file_as_string("res://main.gd").contains("SOUND_RECT"), "legacy sound rectangle no longer exists in production input or drawing")
	game.free();print("SOUND SETTINGS RESULT %d checks, %d failures" % [checks, failures]);quit(1 if failures else 0)
