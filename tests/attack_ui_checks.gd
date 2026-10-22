extends SceneTree
# Production save fixtures and exact post-input snapshots for exported Web QA.
# No runtime hooks or debug-only game routes are required by the browser runner.
const OUT = "res://../verification/v0.15.1/attack-ui/"
const ROUTE_TEST = preload("res://../tests/route_test_helpers.gd")
const SIZES = [Vector2(1280,940), Vector2(390,844), Vector2(360,640), Vector2(844,390)]
const CASES = ["sword_unique", "sword_multiple", "sweep", "blood_unique", "blood_multiple", "blood_break", "airdrop", "chain_bonus"]
const BASIC = ["sword_unique", "sword_multiple", "airdrop"]
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("ATTACK UI: " + label)
func point(p) -> Array: return [p.x, p.y]
func rectangle(r: Rect2) -> Array: return [r.position.x, r.position.y, r.size.x, r.size.y]
func rgb(color: Color) -> Array: return [roundi(color.r * 255), roundi(color.g * 255), roundi(color.b * 255)]
func json_value(value):
	if value is Vector2 or value is Vector2i: return point(value)
	if value is Array:
		var result = []
		for item in value: result.append(json_value(item))
		return result
	if value is Dictionary:
		var result = {}
		for key in value: result[key] = json_value(value[key])
		return result
	return value
func settle():
	game.clear_effects();game.presentation.clear();game.input_lock = 0;game.navigation_lock = 0;game.initial_threat = 0
	game.player_visual = game.cell_pos(game.player)
	for enemy in game.enemies: enemy.visual = game.cell_pos(enemy.pos)
	game.mouse_pos = Vector2(-1000,-1000);game.hover = Vector2i(-1,-1)
	game.sync_hand_ids();game.handui.tick(1)
func pointer(pos: Vector2, down: bool, canceled: bool = false, index: int = 1):
	if game.mobile_layout:
		var e = InputEventScreenTouch.new();e.position = pos;e.pressed = down;e.canceled = canceled;e.index = index;game._input(e)
	else:
		var e = InputEventMouseButton.new();e.position = pos;e.pressed = down;e.button_index = MOUSE_BUTTON_LEFT;game._gui_input(e)
func motion(pos: Vector2):
	if game.mobile_layout:
		var e = InputEventScreenDrag.new();e.position = pos;e.index = 1;game._input(e)
	else:
		var e = InputEventMouseMotion.new();e.position = pos;e.button_mask = MOUSE_BUTTON_MASK_LEFT;game._gui_input(e)
func tap(pos: Vector2): pointer(pos,true);pointer(pos,false)
func drag(from: Vector2, to: Vector2): pointer(from,true);motion(to);pointer(to,false)
func add(pos: Vector2i, kind: String = "p"):
	game.add_enemy(kind,pos,999);game.enemies.back().hp = 12;game.enemies.back().max_hp = 12
func fresh(name: String, size: Vector2):
	game.card_picker.close();game.presentation.clear();game.information.clear();game.tutorial.stop()
	game.battle_touch_contacts.clear();game.battle_multitouch = false;game.cancel_gesture();game.touch_seen = false
	game.player_skill = "horse" if name == "chain_bonus" else "king"
	game.seed_value = 151151;game.new_expedition();game.configure_layout(size)
	if name == "chain_bonus":
		# Obtain the role's treasure through the ordinary boss/reward/claim path.
		var boss = ROUTE_TEST.kind_id(game.route,"boss");ROUTE_TEST.before(game.route,boss);game.route.enter(boss)
		game.settle_victory();settle();game.choose_reward(-1)
		check(game.route.choose_treasure("battle_tassel"),"ordinary chapter-two treasure claim")
	game.route.enter(0)
	game.enemies = [];game.next_enemy_uid = 1;add(Vector2i(4,0),"g")
	game.player = Vector2i(4,5);game.energy = 6;game.lives = 4;game.basic_used = true
	game.phase = "play";game.screen = "game";game.free_selected = false;game.selected = -1
	var id = "sword" if name.begins_with("sword") else ("blood_edge" if name.begins_with("blood_") and name != "blood_break" else ("chain_assault" if name == "chain_bonus" else name))
	game.hand = [id];game.hand_ids = [];game.deck = ["life", "breath"];game.discard = [];game.rewards = [];game.collection = [id,"life","breath"]
	if name in ["blood_unique","blood_multiple"]:
		add(Vector2i(4,4));add(Vector2i(4,3))
		if name == "blood_multiple": add(Vector2i(6,5))
	elif name == "airdrop": add(Vector2i(3,3));add(Vector2i(5,3))
	else:
		add(Vector2i(4,4))
		if name in ["sword_multiple","sweep","blood_break"]: add(Vector2i(5,5))
	if name == "chain_bonus":
		game.active_displacements = 2;game.treasure_battle.tassel_triggered = true;game.treasure_battle.tassel_ready = true
	game.plan_intents();game.history.clear();game.handui.reset();settle()
func save_fixture(stem: String) -> String:
	settle();game.route.save()
	check(game.route.save_error == OK,"production save succeeds " + stem)
	check(game.route.valid_snapshot(game.route.state,game.history.capture(),game.screen),"valid complete snapshot " + stem)
	var filename = stem + ".cfg"
	FileAccess.open(OUT + "fixtures/" + filename,FileAccess.WRITE).store_string(FileAccess.get_file_as_string(game.route.SAVE))
	return filename
func reload_fixture(filename: String):
	FileAccess.open(game.route.SAVE,FileAccess.WRITE).store_string(FileAccess.get_file_as_string(OUT + "fixtures/" + filename))
	check(game.route.resume(),"normal resume " + filename);settle()
func range_evidence(view: Dictionary) -> Dictionary:
	var empty = [];var rings = [];var squares = []
	for cell in view.range_cells:
		var center: Vector2 = game.cell_pos(cell);var side = game.CELL * 0.78
		squares.append(rectangle(Rect2(center - Vector2.ONE * side * 0.5,Vector2.ONE * side)))
		if cell != game.player and game.R.occupied(cell,game.enemies) < 0:
			empty.append({"cell":point(cell),"center":point(center),"sample":point(center + Vector2(0.23,0.23) * game.CELL)})
	for cell in view.enemy_cells: rings.append({"cell":point(cell),"center":point(game.cell_pos(cell)),"radius":game.CELL * 0.49,"width":3})
	return {"squares":squares,"empty":empty,"rings":rings,"cell_size":game.CELL,"board":rectangle(game.BOARD_RECT),
		"ring_hud":{"badge_offset":point(Vector2(0.36,-0.36)*game.CELL),"badge_radius":9*minf(1.0,game.CELL/48.0),"hp_box":[-game.CELL*0.39,game.CELL*0.47,game.CELL*0.78,maxf(2.5,3.5*minf(1.0,game.CELL/48.0))]},
		"colors":{"board":rgb(game.Palette.BOARD),"legal":rgb(game.Palette.LEGAL),"fill":rgb(game.Palette.BOARD.lerp(game.Palette.LEGAL,0.07)),"border":rgb(game.Palette.BOARD.lerp(game.Palette.LEGAL,0.52)),"surface":rgb(game.Palette.SURFACE),"hand":rgb(game.Palette.HAND),"ink":rgb(game.Palette.INK)}}
func text_row(value: String, baseline: Vector2, font_size: int, physical: Transform2D) -> Dictionary:
	# card_face draws in physical logical pixels after normalizing the fan axes.
	# Use actual font ascent/descent and advance, not font_size as a glyph box.
	var ascent = game.FONT.get_ascent(font_size)
	var descent = game.FONT.get_descent(font_size)
	var advance = game.FONT.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var local = Rect2(baseline + Vector2(-1,-ascent),Vector2(advance + 2,ascent + descent))
	var rect = Rect2(physical * local.position,Vector2.ZERO)
	for corner in [Vector2(local.end.x,local.position.y),local.end,Vector2(local.position.x,local.end.y)]: rect = rect.expand(physical * corner)
	return {"text":value,"rect":rectangle(rect),"baseline":point(physical * baseline),"font_size":font_size,"font_ascent":ascent,"font_descent":descent,"text_advance":advance,
		"local_rect":rectangle(local),"physical_transform":{"x":point(physical.x),"y":point(physical.y),"origin":point(physical.origin)}}
func focused_face() -> Dictionary:
	game.handui.tick(1)
	var t: Transform2D = game.handui.card_transform(0)
	var dimensions = Vector2(t.x.length(),t.y.length()) * game.handui.card_size()
	var layout = game.handui.text_layout(0,dimensions,true)
	var data: Array = game.card_data(game.hand[0])
	check(layout.complete, "normalized battle detail fits existing hand geometry: " + game.hand[0])
	var rows = []
	for i in mini(layout.lines.size(),int(layout.available_lines)):
		var left = float(layout.body_left) if i < int(layout.full_from) else 6.0
		rows.append(text_row(layout.lines[i],Vector2(left,float(layout.start_y) + i * layout.line_height),int(layout.font_size),Transform2D(t.x.normalized(),t.y.normalized(),t.origin)))
	var blank = Rect2(game.full_hand_area().position + Vector2(8,40),Vector2(dimensions.x-12,game.FONT.get_ascent(layout.font_size)+game.FONT.get_descent(layout.font_size)))
	check(not blank.intersects(game.handui.bounds(0)) and game.full_hand_area().encloses(blank),"negative text control is blank hand paper")
	return {"card":game.hand[0],"rect":rectangle(game.handui.bounds(0)),"short":data[2],"detail":data[4],"font_size":layout.font_size,"complete":layout.complete,"rows":rows,"blank_control":rectangle(blank)}
func catalog_evidence() -> Dictionary:
	var previous = game.screen;game.screen = "home"
	var report = {"start":point(game.frontend.button_rect(0).get_center())}
	game.screen = "skill_selection";report.open = point(game.frontend.button_rect(4).get_center())
	var picker = game.card_picker;picker.open_catalog()
	for tab in game.card_picker.CATALOG.GROUPS.size():
		picker.set_catalog_tab(tab)
		for slot in picker.catalog_entries.size():
			if picker.catalog_entries[slot].id != "blood_break": continue
			report.tab = point(picker.catalog_tab_rect(tab).get_center());report.grid = rectangle(picker.grid_rect())
			report.scroll_limit = picker.scroll_limit()
			picker.scroll_y = clampf(picker.card_rect(slot).get_center().y-picker.grid_rect().get_center().y,0,picker.scroll_limit())
			report.scroll = picker.scroll_y;report.tap = point(picker.card_rect(slot).intersection(picker.grid_rect()).get_center())
			picker.tap(Vector2(report.tap[0],report.tap[1]));report.detail_scroll_limit = picker.scroll_limit()
			var dimensions: Vector2 = picker.catalog_detail_rect().size
			var layout = picker.face.text_layout(picker.catalog_data(),dimensions,true,true)
			check(layout.complete and layout.font_size >= 18,"full catalog detail readable without clipping")
			check(str(picker.catalog_data()[4]).contains("消耗：一局战斗只能用一次。"),"catalog consumption explanation")
			report.detail = str(picker.catalog_data()[4]);report.face = rectangle(picker.catalog_detail_rect());report.rows = []
			for i in layout.lines.size():
				var left = float(layout.body_left) if i < int(layout.full_from) else 6.0
				report.rows.append(text_row(layout.lines[i],Vector2(left,layout.start_y+i*layout.line_height),int(layout.font_size),Transform2D(0,picker.catalog_detail_rect().position)))
			picker.close();game.screen = previous;return report
	check(false,"blood_break catalog entry exists");picker.close();game.screen = previous;return {}
func make_case(name: String, size: Vector2) -> Dictionary:
	fresh(name,size)
	var stem = "%s-%d" % [name,int(size.x)]
	var initial = save_fixture(stem + "-initial")
	var from: Vector2 = game.handui.bounds(0).get_center()
	var upward = Vector2(from.x,game.full_hand_area().position.y - 30)
	# Landscape hand and board are side by side. Upward release is explicitly
	# outside both the board and hand, while generic board release is separate.
	if game.BOARD_RECT.has_point(upward): upward.x = game.BOARD_RECT.end.x + 15
	check(not game.full_hand_area().has_point(upward) and not game.BOARD_RECT.has_point(upward),"unambiguous nonboard upward release coordinate")
	var r = {"name":name,"stem":stem,"basic":name in BASIC,"viewport":point(size),"logical_size":point(game.ui_size),"initial":initial,
		"card":game.hand[0],"card_point":point(from),"upward":point(upward),"generic_board":point(game.cell_pos(Vector2i(0,8))),"invalid_target":point(game.cell_pos(Vector2i(4,0))),
		"target":point(game.cell_pos(Vector2i(4,3) if name == "airdrop" else Vector2i(4,4))),"pass":point(game.pass_drop_rect().get_center()),"hand":rectangle(game.full_hand_area())}
	game.screen = "home";r.resume = point(game.frontend.button_rect(3).get_center());game.screen = "game"
	var before = game.history.capture();tap(from);settle()
	check(game.selected == 0 and game.hand.size() == 1 and game.energy == before.energy,"selection is not play " + stem)
	r.enemy_centers = []
	for enemy in game.enemies: r.enemy_centers.append(point(game.cell_pos(enemy.pos)))
	r.selected = save_fixture(stem + "-selected");r.range = range_evidence(game.attack_targets.state(0));r.actions = game.attack_targets.state(0).actions.size();r.face = focused_face()
	r.selected_point = point(game.handui.bounds(0).get_center())
	var frozen = game.history.capture();var route_frozen = game.route.state.duplicate(true)
	for _iteration in 4: game.attack_targets.state(0);game.descriptions.data(r.card,true)
	check(game.history.capture() == frozen and game.route.state == route_frozen,"range and normalized detail are read-only")
	if name in ["sword_multiple","blood_multiple","airdrop"]:
		drag(Vector2(r.selected_point[0],r.selected_point[1]),upward);settle()
		check(game.history.capture() == frozen,"ambiguous/airdrop upward release does not play " + stem)
		r.after_upward = save_fixture(stem + "-upward-inert")
		drag(Vector2(r.selected_point[0],r.selected_point[1]),Vector2(r.target[0],r.target[1]))
	else: drag(Vector2(r.selected_point[0],r.selected_point[1]),upward)
	check(game.hand.is_empty(),"ordinary release plays one exact card " + stem)
	r.after = save_fixture(stem + "-played")
	var committed = game.history.capture();pointer(upward,false);settle()
	check(game.history.capture() == committed,"duplicate release does not play twice " + stem)
	if name == "sword_unique":
		reload_fixture(initial);drag(from,Vector2(r.generic_board[0],r.generic_board[1]));r.after_board = save_fixture(stem + "-board-played")
		reload_fixture(initial);drag(from,Vector2(r.pass[0],r.pass[1]));r.after_pass = save_fixture(stem + "-passed")
		check(game.energy == before.energy-3 and game.hand == ["breath"] and game.discard == ["sword"],"discard zone remains three fee and draw, not attack")
		check(game.enemies[1].hp == 12,"discard never damages legal enemy")
	if name == "blood_break":
		reload_fixture(initial);r.catalog = catalog_evidence()
	if name == "chain_bonus":
		check(str(r.face.short).contains("本回合主动位移次数+1+2（当前5）"),"chain formula includes exact current treasure bonus")
	return r
func run():
	DirAccess.make_dir_recursive_absolute(OUT + "fixtures")
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	var reports = []
	for size in SIZES:
		for name in CASES: reports.append(make_case(name,size))
	FileAccess.open(OUT + "replays.json",FileAccess.WRITE).store_string(JSON.stringify({"schema":1,"web_save_key":game.route.WEB_SAVE_KEY,"replays":reports},"  ")+"\n")
	print("ATTACK UI RESULT %d checks, %d failures; %d valid production replay descriptors" % [checks,failures,reports.size()])
	game.queue_free();quit(1 if failures else 0)
