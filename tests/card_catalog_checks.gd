extends SceneTree
# Read-only catalog contracts and UI-only browser replay descriptors.
const PROFILES = preload("res://start_profiles.gd")
const UPGRADES = preload("res://card_upgrades.gd")
const FREE = preload("res://free_move_card.gd")
const TREASURES = preload("res://treasure_system.gd")
const OUT = "res://../verification/v0.14.13/catalog/"
const SIZES = [Vector2(1280,940),Vector2(390,844),Vector2(360,640),Vector2(844,390)]
const GROUPS = ["common","king","horse","artillery","special"]
var game
var picker
var checks = 0
var failures = 0

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("CARD CATALOG: " + label)
func point(p: Vector2) -> Array: return [p.x,p.y]
func rectangle(r: Rect2) -> Array: return [r.position.x,r.position.y,r.size.x,r.size.y]
func file_contents(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "<absent>"
func readonly_snapshot() -> Dictionary:
	var battle = game.history.capture()
	# Layout relocates decorative enemy sprites; all gameplay fields stay exact.
	for enemy in battle.enemies: enemy.erase("visual")
	return {"battle":battle,"route":game.route.state.duplicate(true),"screen":game.screen,
		"rng":game.rng.state,"role":game.player_skill,"unlock":game.skill_system.horse_unlocked,
		"save":file_contents(game.route.SAVE),"unlock_save":file_contents(game.skill_system.SAVE_PATH),
		"undo":game.normal_undos_remaining,"settings":file_contents("user://settings.cfg")}
func key(code: int):
	var event = InputEventKey.new();event.keycode = code;event.pressed = true;game._input(event)
func touch(position: Vector2, pressed: bool, canceled: bool = false, index: int = 1):
	var event = InputEventScreenTouch.new();event.position = position;event.pressed = pressed;event.canceled = canceled;event.index = index;game._input(event)
func tap(position: Vector2): touch(position,true);touch(position,false)
func drag(start: Vector2, finish: Vector2, canceled: bool = false):
	touch(start,true)
	var event = InputEventScreenDrag.new();event.position = finish;event.index = 1;game._input(event)
	touch(finish,false,canceled)
func expected_ids(group: String) -> Array:
	var ids = []
	if group == "special": return ["fatigue","grappling_hook","decoy_card","__free_king","__free_horse","__free_artillery_march","__free_artillery_attack"] + TREASURES.TEMPORARY
	var source: Array = PROFILES.COMMON if group == "common" else PROFILES.DATA[group].deck + PROFILES.DATA[group].rewards
	for id in source:
		if game.CARDS.has(id) and id not in ids and (group == "common" or id not in PROFILES.COMMON): ids.append(id)
	return ids
func same_ids(actual: Array, expected: Array) -> bool:
	var a = actual.duplicate();var b = expected.duplicate();a.sort();b.sort();return a == b
func select_slot(slot: int):
	picker.scroll_y = clampf(picker.card_rect(slot).get_center().y + picker.scroll_y - picker.grid_rect().get_center().y,0,picker.scroll_limit());picker.refresh()
	var visible: Rect2 = picker.card_rect(slot).intersection(picker.grid_rect())
	check(visible.size.x > 0 and visible.size.y > 0,"card %d reachable" % slot)
	tap(visible.get_center())

func run():
	DirAccess.make_dir_recursive_absolute(OUT + "fixtures")
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);picker = game.card_picker
	game.player_skill = "king";game.seed_value = 141303;game.new_expedition();game.route.enter(0);game.route.save();game.show_home()
	game.skill_system.horse_unlocked = false
	# Opening the role chooser is the normal frontend, not a new expedition.
	game.frontend.activate(0)
	check(game.screen == "skill_selection","normal home start reaches role chooser")
	check(not game.skill_system.is_unlocked("horse") and not game.skill_system.is_unlocked("artillery"),"other roles initially locked")
	var baseline = readonly_snapshot()
	var total = 0
	for group in GROUPS: total += expected_ids(group).size()
	var replays = []
	for size in SIZES:
		game.configure_layout(size)
		check(game.frontend.entries()[3] == "返回首页","legacy back entry retains index")
		check(game.frontend.entries()[4] == "查看全部卡牌","catalog appended to role chooser")
		tap(game.frontend.button_rect(4).get_center())
		check(picker.active and picker.action == "catalog" and game.screen == "skill_selection","frontend opens catalog in place")
		check(not picker.selected_valid(),"catalog has no mutation confirmation")
		for tab in GROUPS.size():
			tap(picker.catalog_tab_rect(tab).get_center())
			check(picker.catalog_tab == tab and not picker.catalog_detail,"tab switches to its grid")
			var expected = expected_ids(GROUPS[tab]);var actual = []
			for entry in picker.catalog_entries: actual.append(entry.id)
			check(same_ids(actual,expected),"%s pool exact and deduplicated" % GROUPS[tab])
			check(picker.indices.size() == expected.size(),"grid count equals source count")
			for slot in picker.catalog_entries.size():
				var entry: Dictionary = picker.catalog_entries[slot]
				check(entry.data.size() >= 4 and not str(entry.data[0]).is_empty(),"entry has named effect")
				check(entry.upgrade_id == UPGRADES.upgraded_id(entry.id) if UPGRADES.can_upgrade(entry.id) else entry.upgrade_id.is_empty(),"variant derives from registry")
				select_slot(slot)
				check(picker.catalog_detail and picker.selected == slot,"tap focuses exact catalog card")
				check(picker.catalog_id() == entry.id and picker.catalog_data() == entry.data,"focused base identity/data")
				for code in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6,KEY_7,KEY_SPACE,KEY_ENTER,KEY_KP_ENTER]: key(code)
				check(picker.active and picker.catalog_detail and readonly_snapshot() == baseline,"all shortcuts consumed without gameplay/save mutation")
				if not entry.upgrade_id.is_empty():
					tap(picker.catalog_variant_rect().get_center())
					check(picker.catalog_upgraded and picker.catalog_id() == entry.upgrade_id and picker.catalog_data() == game.descriptions.data(entry.upgrade_id),"same-card upgraded face")
					tap(picker.catalog_variant_rect().get_center())
					check(not picker.catalog_upgraded and picker.selected == slot,"toggle restores same base card")
				else:
					picker.toggle_catalog_variant();check(not picker.catalog_upgraded,"non-upgrade stays base")
				picker.confirm();check(picker.active and readonly_snapshot() == baseline,"confirm cannot acquire/change any card")
				tap(picker.catalog_back_rect().get_center());check(picker.active and not picker.catalog_detail,"detail back returns grid")
			# Cancelled/repeated touch and long swipe must never select a card.
			var start = picker.grid_rect().get_center();var finish = start - Vector2(0,110)
			drag(start,finish,true);check(not picker.catalog_detail and picker.pointer == -2,"touch cancel stops without opening detail")
			drag(start,finish);check(not picker.catalog_detail,"scroll release never becomes card tap")
			picker.scroll_y = picker.scroll_limit();picker.refresh();select_slot(picker.indices.size()-1)
			var selected_id = picker.catalog_id()
			game.configure_layout(Vector2(390,844) if size.x > 800 else Vector2(844,390));picker.refresh()
			check(picker.catalog_detail and picker.catalog_id() == selected_id and picker.scroll_y <= picker.scroll_limit(),"rotation preserves focused identity and clamps scroll")
			game.configure_layout(size);picker.refresh();tap(picker.catalog_back_rect().get_center())
			check(picker.active and not picker.catalog_detail,"detail back returns grid")
		check(readonly_snapshot() == baseline,"all groups/locked roles preserve expedition and unlocks")
		tap(picker.cancel_rect().get_center());check(not picker.active and readonly_snapshot() == baseline,"grid back returns unchanged role page")
		for repeat in 3:
			picker.open_catalog();select_slot(0);key(KEY_ESCAPE);check(not picker.active and readonly_snapshot() == baseline,"detail Escape and repeated reopen preserve role page")
		replays.append(make_replay(size))
	# Pure free movement descriptions are canonical battle data, independent of active identity.
	for spec in [["king","march"],["horse","march"],["artillery","march"],["artillery","attack"]]:
		var before = readonly_snapshot();var data: Array = FREE.data_for(spec[0],spec[1])
		check(data.size() >= 4 and data[1] == 0,"zero-cost free movement has full data")
		check(readonly_snapshot() == before,"free movement helper has no state/RNG side effects")
	# Every displayed permanent consumable uses the user's exact per-copy wording once.
	for id in game.CONSUMABLES:
		var data: Array = game.descriptions.data(id)
		var original: String = str(data[4])
		var layout = picker.face.text_layout(data,Vector2(432,10000),true,true)
		var rendered = "".join(layout.lines)
		check(rendered == original.replace("\n",""),"consumable complete rule appears exactly once: " + id)
		check(rendered.count("消耗：一局战斗只能用一次。") == 1 and not rendered.contains("下关恢复") and not rendered.contains("下场恢复"),"exactly one normalized consumable explanation: " + id)
	for effect in ["消耗：一局战斗只能用一次。","命+1。消耗：一局战斗只能用一次。"]:
		var data = ["测试",1,effect,"术"]
		check("".join(picker.face.text_layout(data,Vector2(432,10000),true,true).lines) == effect,"existing complete synthetic rule unchanged")
	var incomplete = ["测试",1,"命+1。","术"]
	check("".join(picker.face.text_layout(incomplete,Vector2(432,10000),true,true).lines) == "命+1。消耗：一局战斗只能用一次。","missing consumable detail receives exact rule")
	for id in game.TREASURES.TEMPORARY:
		var temporary = "".join(picker.face.text_layout(game.descriptions.data(id),Vector2(432,10000),true,true).lines)
		check(temporary.contains("回合结束消失") and not temporary.contains("一局战斗只能用一次"),"temporary lifetime is not permanent exhaustion: " + id)
	check("".join(picker.face.text_layout(game.CARDS.sword,Vector2(432,10000),true,false).lines) == str(game.CARDS.sword[2]),"nonconsumable renderer does not invent rules")
	# Existing permanent deck viewer remains physical-instance based, not catalog.
	game.screen = "map";game.collection = ["sword","sword","sword_plus"]
	picker.open("view","全部永久牌组",range(game.collection.size()),Callable(),Callable())
	check(picker.action == "view" and picker.indices.size() == 3,"map permanent deck retains duplicate physical copies")
	picker.cancel();game.screen = "home";picker.open_catalog();check(not picker.active,"catalog cannot open outside role selection")
	FileAccess.open(OUT + "replays.json",FileAccess.WRITE).store_string(JSON.stringify({"schema":1,"groups":GROUPS,"catalog_count":total,"replays":replays},"  "))
	game.queue_free();print("CARD CATALOG RESULT %d checks, %d failures; %d catalog identities" % [checks,failures,total]);quit(1 if failures else 0)

func make_replay(size: Vector2) -> Dictionary:
	game.configure_layout(size);game.screen = "home"
	var report = {"name":"catalog-" + str(int(size.x)),"viewport":point(size),"logical_size":point(game.ui_size),
		"fixture":"existing-expedition.cfg","start":point(game.frontend.button_rect(0).get_center()),"resume":point(game.frontend.button_rect(3).get_center()),"groups":[]}
	FileAccess.open(OUT + "fixtures/existing-expedition.cfg",FileAccess.WRITE).store_string(file_contents(game.route.SAVE))
	game.screen = "skill_selection";report.open = point(game.frontend.button_rect(4).get_center());report.role_back = point(game.frontend.button_rect(3).get_center())
	picker.open_catalog();report.cancel = point(picker.cancel_rect().get_center())
	for tab in GROUPS.size():
		picker.set_catalog_tab(tab)
		var group = {"id":GROUPS[tab],"tab":point(picker.catalog_tab_rect(tab).get_center()),"count":picker.catalog_entries.size(),"grid":rectangle(picker.grid_rect()),"cards":[],"scroll_limit":picker.scroll_limit()}
		for slot in picker.catalog_entries.size():
			var entry: Dictionary = picker.catalog_entries[slot]
			picker.scroll_y = clampf(picker.card_rect(slot).get_center().y + picker.scroll_y - picker.grid_rect().get_center().y,0,picker.scroll_limit());picker.refresh()
			var card = {"id":entry.id,"name":entry.data[0],"slot":slot,"scroll":picker.scroll_y,"tap":point(picker.card_rect(slot).intersection(picker.grid_rect()).get_center()),"upgrade_id":entry.upgrade_id}
			picker.tap(Vector2(card.tap[0],card.tap[1]))
			card.back = point(picker.catalog_back_rect().get_center());card.variant = point(picker.catalog_variant_rect().get_center());card.detail = rectangle(picker.grid_rect());card.detail_scroll_limit = picker.scroll_limit()
			picker.tap(picker.catalog_back_rect().get_center());group.cards.append(card)
		report.groups.append(group)
	picker.cancel();return report
