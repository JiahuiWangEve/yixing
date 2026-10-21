extends SceneTree
# One right-side target serves click-selected and held/dragged physical cards.
var game
var checks = 0
var failures = 0

func _initialize(): call_deferred("run")

func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("DISCARD ZONE: " + label)

func fresh(size: Vector2, energy: int = 5, cards: Array = ["sword", "sword"]):
	if game.card_picker.active: game.card_picker.close()
	game.tutorial.stop();game.presentation.clear();game.player_skill = "king";game.new_run()
	game.set_process(false);game.configure_layout(size)
	game.enemies = [];game.add_enemy("g", Vector2i(4, 0), 999)
	game.player = Vector2i(4, 8);game.lives = 4
	game.collection = cards.duplicate();game.hand = cards.duplicate();game.hand_ids = []
	game.deck = ["spear", "diagonal"];game.discard = [];game.energy = energy
	game.screen = "game";game.phase = "play";game.selected = -1;game.free_selected = false
	game.encounter_info_open = false;game.clear_effects();game.presentation.clear()
	game.input_lock = 0;game.navigation_lock = 0;game.cancel_gesture();game.touch_seen = false
	game.sync_hand_ids();game.handui.reset();game.handui.sync();game.history.clear()

func button(position: Vector2, pressed: bool, kind: String, canceled: bool = false):
	if kind == "touch":
		var event = InputEventScreenTouch.new()
		event.index = 0;event.position = position;event.pressed = pressed;event.canceled = canceled
		game._input(event)
	else:
		var event = InputEventMouseButton.new()
		event.device = 0;event.button_index = MOUSE_BUTTON_LEFT;event.position = position;event.pressed = pressed
		game._gui_input(event)

func motion(position: Vector2, kind: String):
	if kind == "touch":
		var event = InputEventScreenDrag.new();event.index = 0;event.position = position;game._input(event)
	else:
		var event = InputEventMouseMotion.new();event.device = 0;event.position = position;game._gui_input(event)

func tap(position: Vector2, kind: String):
	button(position, true, kind);button(position, false, kind)

func snapshot() -> Dictionary:
	return {"rules": game.history.capture(), "selected": game.selected, "entries": game.history.entries.duplicate(true)}

func check_selection(size: Vector2, kind: String):
	for free in [false, true]:
		fresh(size)
		var source: Vector2 = game.handui.free_exposed_point() if free else game.handui.exposed_point(0)
		var drop: Vector2 = game.pass_drop_rect().get_center()
		var old_uid: int = game.free_card_uid if free else game.hand_ids[0]
		check(not game.pass_zone_visible(), "unselected hand hides zone " + str(size) + kind)
		button(source, true, kind)
		check(game.pass_zone_visible() and game.gesture.active and not game.gesture.dragging, "holding immediately shows zone before drag " + str(size) + kind)
		check(game.hand.size() == 2 and game.energy == 5, "holding alone has no card effects")
		button(source, false, kind)
		check(game.pass_zone_visible() and not game.gesture.active and (game.free_selected if free else game.selected == 0), "tap selects and keeps shared zone visible " + str(size) + kind)
		var state: Dictionary = game.gesture.pass_zone_state()
		check(state.enabled and not state.highlighted and state.title == "弃置" and state.cost == "3费" and state.replacement == "补抽1张" and state.hint == "单击弃置", "selection uses shared enabled labels")
		button(drop, true, kind)
		check(game.gesture.active and game.gesture.pass_pressed and game.gesture.uid == old_uid and not game.gesture.dragging, "zone pointer-down captures selection instead of card beneath it")
		check(game.energy == 5 and game.history.entries.is_empty(), "zone pointer-down waits for completed click")
		button(drop, false, kind)
		check(game.energy == 2 and game.history.entries.size() == 1 and not game.pass_zone_visible(), "zone click commits once and hides after deselection")
		check(game.deck == ["spear"] and game.hand.back() == "diagonal" and game.player == Vector2i(4, 8) and not game.basic_used, "zone click draws one without movement or card effects")
		check((game.free_card_uid == 0 and game.discard.is_empty() and game.hand.size() == 3) if free else (not game.hand_ids.has(old_uid) and game.discard == ["sword"] and game.hand.size() == 2), "zone click discards only the selected physical source")
		var after = snapshot();button(drop, false, kind)
		check(snapshot() == after, "duplicate zone release has no fallback")

func check_drag(size: Vector2, kind: String):
	for free in [false, true]:
		fresh(size)
		var source: Vector2 = game.handui.free_exposed_point() if free else game.handui.exposed_point(0)
		var drop: Vector2 = game.pass_drop_rect().get_center()
		button(source, true, kind)
		motion(source + Vector2(-1, 1), kind)
		check(game.pass_zone_visible() and not game.gesture.dragging, "stationary long-hold jitter keeps zone visible without dragging")
		motion(drop, kind)
		var state: Dictionary = game.gesture.pass_zone_state()
		check(game.gesture.dragging and state.visible and state.highlighted and state.hint == "松手弃置" and not game.gesture.valid_target(), "drag-in highlights the same zone, not a board target")
		motion(source, kind)
		check(game.pass_zone_visible() and not game.gesture.pass_zone_state().highlighted, "retreating clears zone highlight")
		var before = snapshot();button(source, false, kind)
		check(snapshot() == before and not game.pass_zone_visible(), "dragging back cancels without selecting or paying")
		button(source, true, kind);motion(drop, kind);button(drop, false, kind)
		check(game.energy == 2 and game.history.entries.size() == 1 and game.hand.back() == "diagonal", "held-card drag-in release pays three and draws one")
		check((game.free_card_uid == 0 and game.discard.is_empty()) if free else game.discard == ["sword"], "held-card release discards correct source")
		before = snapshot();button(drop, false, kind)
		check(snapshot() == before, "repeated drag release is ignored")

func check_disabled_and_cancel(size: Vector2, kind: String):
	fresh(size, 2, ["breath"])
	var source: Vector2 = game.handui.exposed_point(0)
	var drop: Vector2 = game.pass_drop_rect().get_center()
	tap(source, kind)
	var before = snapshot()
	var state: Dictionary = game.gesture.pass_zone_state()
	check(state.visible and not state.enabled and state.hint == "能量不足", "unaffordable selected zone is visible and disabled")
	tap(drop, kind)
	check(snapshot() == before and game.selected == 0, "disabled zone swallows click without underlying selection, play or movement")
	game.cancel_selection();source = game.handui.exposed_point(0);before = snapshot()
	button(source, true, kind);motion(drop, kind)
	check(game.pass_zone_visible() and not game.gesture.pass_zone_state().highlighted, "unaffordable drag cannot show successful-drop highlight")
	button(drop, false, kind)
	check(snapshot() == before, "unaffordable drop never falls back to zero-cost card play")
	fresh(size);source = game.handui.exposed_point(0);drop = game.pass_drop_rect().get_center();tap(source, kind)
	before = snapshot();button(drop, true, kind);motion(game.cell_pos(Vector2i(4, 7)), kind);button(game.cell_pos(Vector2i(4, 7)), false, kind)
	check(snapshot() == before and not game.gesture.active, "dragging a pressed zone onto board cannot play or move")
	button(drop, true, kind);motion(source, kind);motion(drop, kind);button(drop, false, kind)
	check(snapshot() == before and not game.gesture.active, "zone drag-out and return is not a click and never commits")
	button(drop, true, kind)
	if kind == "touch": button(drop, false, kind, true)
	else: game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	button(drop, false, kind)
	check(snapshot() == before and not game.gesture.active, "canceled zone click and late release preserve selection and rules")
	game.cancel_selection();source = game.handui.exposed_point(0);before = snapshot()
	button(source, true, kind);motion(drop, kind)
	if kind == "touch": button(drop, false, kind, true)
	else: game._notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	button(drop, false, kind)
	check(snapshot() == before and not game.gesture.active and not game.pass_zone_visible(), "interrupted held-card drag cannot commit on late release")

func check_contexts(size: Vector2):
	fresh(size);game.select_card(0)
	var drop: Vector2 = game.pass_drop_rect().get_center()
	game.airdrop_recovery_turn = game.turn
	var before = snapshot()
	check(not game.pass_zone_visible(), "recovery hides selected discard zone")
	tap(drop, "touch")
	check(game.history.capture() == before.rules and game.history.entries == before.entries, "recovery cannot discard, draw or spend")
	fresh(size);game.select_card(0)
	game.card_picker.open("view", "牌组", range(game.collection.size()), Callable(), Callable())
	before = snapshot()
	check(not game.pass_zone_visible(), "grid picker hides selected discard zone")
	tap(drop, "touch")
	check(snapshot() == before and game.card_picker.active, "grid picker input cannot discard battle cards")
	game.card_picker.close();game.encounter_info_open = true
	check(not game.pass_zone_visible(), "encounter modal hides zone")
	game.encounter_info_open = false;game.presentation.start("victory")
	check(not game.pass_zone_visible(), "presentation modal hides zone")
	game.presentation.clear()
	for screen in ["map", "route_choice", "home", "settings", "tutorial_pause"]:
		game.screen = screen;check(not game.pass_zone_visible(), "nonbattle screen hides stale selected zone " + screen)
	game.screen = "game"
	for phase in ["discard", "reward", "dead", "win"]:
		game.phase = phase;check(not game.pass_zone_visible(), "nonplay phase hides selected paid zone " + phase)
	game.phase = "play";game.tutorial.active = true
	check(not game.pass_zone_visible(), "guided tutorial hides paid discard zone")
	game.tutorial.active = false

func check_uid_and_overlap():
	var size = Vector2(390, 844)
	fresh(size, 9, ["sword", "sword", "sword", "sword", "sword", "sword"])
	game.select_card(0)
	var drop: Vector2 = game.pass_drop_rect().get_center()
	var ids: Array = game.hand_ids.duplicate()
	button(drop, true, "touch")
	game.hand.remove_at(0);game.hand_ids.remove_at(0);game.handui.sync()
	var before = snapshot();button(drop, false, "touch")
	check(snapshot() == before and game.hand_ids.has(ids[1]), "stale selected-zone UID cannot discard the replacement index")
	fresh(size, 9, ["sword", "sword", "sword", "sword", "sword", "sword"])
	game.select_card(1);ids = game.hand_ids.duplicate();button(drop, true, "touch")
	game.hand.remove_at(0);game.hand_ids.remove_at(0);game.handui.sync();button(drop, false, "touch")
	check(not game.hand_ids.has(ids[1]) and game.hand_ids.has(ids[2]) and game.energy == 6, "selected-zone UID survives hand reindexing")
	fresh(size, 9, ["sword", "sword", "sword", "sword", "sword", "sword"])
	var area: Rect2 = game.pass_drop_rect()
	var underlying = Vector2.INF
	for x in range(int(area.position.x + 4), int(area.end.x - 32), 3):
		for y in range(int(area.position.y + 20), int(area.end.y - 20), 3):
			var point = Vector2(x, y)
			if game.handui.hit_index(point) >= 0: underlying = point;break
		if underlying.is_finite(): break
	check(underlying.is_finite(), "small-screen fixture has a real card beneath transient zone")
	if underlying.is_finite():
		before = snapshot();button(underlying, true, "touch");motion(underlying + Vector2(13, 0), "touch");button(underlying + Vector2(13, 0), false, "touch")
		check(snapshot() == before, "minor in-zone movement keeps deliberate-direction threshold")
		game.select_card(0);ids = game.hand_ids.duplicate();button(underlying, true, "touch")
		check(game.gesture.pass_pressed and game.gesture.uid == ids[0], "visible zone intercepts even a different underlying card")
		button(underlying, false, "touch")
		check(not game.hand_ids.has(ids[0]) and game.energy == 6 and game.history.entries.size() == 1, "overlap click commits selected card, never the card underneath")

func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	for size in [Vector2(1280, 940), Vector2(390, 844), Vector2(844, 390), Vector2(360, 640), Vector2(320, 480)]:
		fresh(size)
		var area: Rect2 = game.pass_drop_rect()
		check(game.pass_button_rect() == area and Rect2(Vector2.ZERO, game.ui_size).encloses(area) and not area.intersects(game.BOARD_RECT) and not area.intersects(game.END_TURN_RECT), "one shared side zone stays clear of board/end-turn " + str(size))
		for kind in ["mouse", "touch"]:
			check_selection(size, kind);check_drag(size, kind);check_disabled_and_cancel(size, kind)
		check_contexts(size)
	check_uid_and_overlap()
	print("DISCARD ZONE RESULT %d checks, %d failures" % [checks, failures])
	game.free();quit(1 if failures else 0)
