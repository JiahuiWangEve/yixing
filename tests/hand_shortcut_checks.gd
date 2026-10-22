extends SceneTree
# Real key events; ordinary production-save fixtures for the short Web gate.
const OUT = "res://../verification/v0.14.10/hand-shortcuts/"
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("HAND SHORTCUT: " + label)
	else: print("PASS ", label)
func key(code: int, modifier: String = "", echo: bool = false, pressed: bool = true):
	var e = InputEventKey.new();e.keycode = code;e.pressed = pressed;e.echo = echo
	if modifier != "": e.set(modifier + "_pressed", true)
	game._input(e)
func settle():
	game.clear_effects();game.input_lock = 0;game.navigation_lock = 0;game.initial_threat = 0
	game.sync_hand_ids();game.handui.reset();game.handui.sync()
func fresh(cards: Array = ["life", "sword", "breath", "cannon_shot", "spear", "sweep", "fatigue", "life"]):
	game.touch_seen = false;game.cancel_gesture();game.tutorial.active = false;game.presentation.clear();game.card_picker.close();game.encounter_info_open = false
	game.configure_layout(Vector2(1280,940));game.player_skill = "king";game.new_run()
	game.hand = cards.duplicate();game.hand_ids = [];game.deck = ["life"];game.discard = []
	game.phase = "play";game.lives = 3;game.energy = 3;game.selected = -1;game.free_selected = false
	game.history.clear();settle()
func state() -> Dictionary:
	return {"battle": game.history.capture(), "selected": game.selected, "history": game.history.entries.duplicate(true), "screen": game.screen}
func economy() -> Dictionary:
	var result: Dictionary = game.history.capture()
	result.erase("notice");result.erase("free_selected")
	return result
func check_mapping():
	for free in [true, false]:
		for slot in range(1, 8):
			for keypad in [false, true]:
				fresh();game.basic_used = not free;settle()
				var before = economy()
				var index = slot - (2 if free else 1)
				# Exact production selection path used by a single card click.
				if index == -1: game.select_free_card()
				else: game.select_card(index)
				var expected = state()
				game.selected = -1;game.free_selected = false
				key((KEY_KP_1 if keypad else KEY_1) + slot - 1)
				check(state() == expected, "slot %d keypad=%s free=%s equals single-click selection" % [slot,keypad,free])
				check(economy() == before, "selection spends nothing and never plays slot " + str(slot))
				if index == -1: game.select_free_card()
				else: game.select_card(index)
				expected = state()
				key((KEY_KP_1 if keypad else KEY_1) + slot - 1)
				key((KEY_KP_1 if keypad else KEY_1) + slot - 1)
				check(state() == expected, "reselect toggles exactly like click " + str(slot))
func check_guards():
	fresh();var before = state()
	for code in [KEY_0,KEY_8,KEY_9,KEY_KP_0,KEY_KP_8,KEY_KP_9]: key(code)
	for modifier in ["ctrl", "meta", "alt", "shift"]: key(KEY_2, modifier)
	key(KEY_2, "", true);key(KEY_2, "", false, false)
	check(state() == before, "out of range, modifiers, repeat and release are inert")
	fresh([]);game.basic_used = true;before = state();key(KEY_1);key(KEY_KP_7)
	check(state() == before, "nonexistent slots are inert")
	for screen in ["home","settings","map","route_choice","tutorial_pause","tutorial_complete"]:
		fresh();game.screen = screen;before = state();key(KEY_2)
		check(state() == before, "screen guard " + screen)
	for phase in ["reward","enemy","dead","win"]:
		fresh();game.phase = phase;game.selected = 1;before = state();key(KEY_2)
		check(state() == before, "phase guard and selected discard protection " + phase)
	for guard in ["input_lock","navigation_lock","encounter_info_open","recovery","presentation","picker","gesture","touch"]:
		fresh()
		match guard:
			"input_lock", "navigation_lock": game.set(guard, 1.0)
			"encounter_info_open": game.encounter_info_open = true
			"recovery": game.airdrop_recovery_turn = game.turn
			"presentation": game.presentation.victory()
			"picker": game.card_picker.active = true
			"gesture": game.gesture.active = true
			"touch": game.touch_seen = true
		before = state();key(KEY_2)
		check(state() == before, "guard " + guard)
	for size in [Vector2(390,844),Vector2(844,390)]:
		fresh();game.configure_layout(size);before = state();key(KEY_1);key(KEY_KP_2)
		check(state() == before, "mobile keys inert " + str(size))
	fresh();game.start_tutorial(0);settle();before = state();key(KEY_2)
	check(game.selected == before.selected and economy().hand == before.battle.hand, "tutorial objective rejects forbidden select")
	game.tutorial.lesson_complete = true;before = state();key(KEY_2)
	check(game.selected == before.selected, "tutorial completion gate")
func check_mouse_and_discard():
	for index in [0,1,3]:
		fresh();var before = economy()
		var pos: Vector2 = game.handui.exposed_point(index)
		for down in [true,false]:
			var event = InputEventMouseButton.new();event.position = pos;event.button_index = MOUSE_BUTTON_LEFT;event.pressed = down
			game._gui_input(event)
		check(game.selected == index, "actual mouse event selected card " + str(index))
		var expected = state();game.selected = -1;game.free_selected = false
		key(KEY_2 + index)
		check(state() == expected and economy() == before, "actual key equals actual mouse without play " + str(index))
	fresh();game.phase = "discard";game.selected = 1;var before = economy();key(KEY_2)
	check(game.selected == 0 and economy() == before, "discard number selects without spending or deleting")
	key(KEY_2)
	check(game.selected == -1 and economy() == before, "discard same number cancels exactly like click")
	key(KEY_1)
	check(game.selected == -1 and not game.free_selected and economy() == before, "disabled free card stays inert during discard")
func check_mutations():
	fresh(["sword", "spear", "life", "breath", "cannon_shot"]);game.hand.reverse();game.hand_ids.reverse();settle();key(KEY_2)
	check(game.selected == 0 and game.hand[game.selected] == "cannon_shot", "current reordered hand index")
	game.cancel_selection();game.draw_card();settle();key(KEY_7)
	check(game.selected == 5, "draw retains current slot mapping")
	game.pass_card(0, false);settle();key(KEY_2)
	check(game.selected == 0 and game.hand[0] == "breath", "pass removal renumbers current hand")
	fresh();game.pass_card(-1, true);settle();key(KEY_1)
	check(game.selected == 0 and not game.free_selected, "passing free movement shifts first hand card to 1")
	fresh();var turn = game.turn;key(KEY_2);key(KEY_SPACE)
	check(game.turn == turn + 1 and game.hand.has("life"), "Space remains end-turn, not selected-card play")
	settle();key(KEY_Z, "ctrl")
	check(game.turn == turn and game.selected == -1, "Ctrl Z still undoes after shortcut selection")
func check_badges():
	fresh();var badges = game.handui.shortcut_badges()
	check(badges.size() == 7 and badges[0].free and badges[1].index == 0 and badges[6].number == 7, "desktop badges follow visual slots and stop at seven")
	for badge in badges:
		check(Rect2(Vector2.ZERO,game.ui_size).encloses(badge.rect), "badge inside viewport " + str(badge.number))
	game.basic_used = true;settle();badges = game.handui.shortcut_badges()
	check(badges.size() == 7 and not badges[0].free and badges[0].index == 0, "badge renumber after free card disappears")
	for size in [Vector2(390,844),Vector2(844,390)]:
		game.configure_layout(size);settle()
		check(game.handui.shortcut_badges().is_empty(), "no mobile badges " + str(size))
	fresh();game.touch_seen = true
	check(game.handui.shortcut_badges().is_empty(), "touch desktop suppresses keyboard badges")
	fresh();game.phase = "reward"
	check(game.handui.shortcut_badges().is_empty(), "reward has no shortcut badges")
	game.screen = "route_choice";game.card_picker.active = true
	check(game.handui.shortcut_badges().is_empty(), "picker has no shortcut badges")
func point(p: Vector2) -> Array: return [p.x,p.y]
func fixtures():
	DirAccess.make_dir_recursive_absolute(OUT + "fixtures")
	var reports = []
	for size in [Vector2(1280,940),Vector2(390,844)]:
		fresh();game.configure_layout(size);game.seed_value = 1410;game.new_expedition();game.route.enter(0)
		game.hand = ["life","sword","breath","cannon_shot","spear","sweep"];game.hand_ids = [];game.lives = 3;settle();game.route.save()
		check(game.route.valid_snapshot(game.route.state,game.history.capture(),"game"), "valid ordinary Web fixture " + str(size))
		var name = "hand-" + str(int(size.x))
		FileAccess.open(OUT + "fixtures/" + name + ".cfg",FileAccess.WRITE).store_string(FileAccess.get_file_as_string(game.route.SAVE))
		var row = {"name":name,"viewport":point(size),"logical_size":point(game.ui_size),"fixture":name + ".cfg","life":point(game.handui.exposed_point(0)),"confirm":point(game.USE_RECT.get_center()),"hand_area": [game.hand_area().position.x,game.hand_area().position.y,game.hand_area().size.x,game.hand_area().size.y]}
		game.screen = "home";row.resume = point(game.frontend.button_rect(3).get_center());game.screen = "game"
		reports.append(row)
	FileAccess.open(OUT + "replays.json",FileAccess.WRITE).store_string(JSON.stringify(reports,"  "))
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	check_mapping();check_guards();check_mouse_and_discard();check_mutations();check_badges();fixtures()
	print("HAND SHORTCUT RESULT ",checks," checks, ",failures," failures")
	game.free();quit(1 if failures else 0)
