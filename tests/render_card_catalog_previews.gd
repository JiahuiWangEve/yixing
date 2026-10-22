extends Node
# Run through a real Godot GUI in an isolated QA copy, never --headless.
const OUT = "res://../verification/v0.14.13/catalog/native/"
const SIZES = [Vector2i(1280,940),Vector2i(390,844),Vector2i(360,640),Vector2i(844,390)]
var reports = []
var assertions = 0
func _ready(): call_deferred("run")
func check(ok: bool, label: String):
	assertions += 1
	assert(ok,label)
func snapshot(game) -> Dictionary:
	var battle = game.history.capture()
	for enemy in battle.enemies: enemy.erase("visual")
	return {"battle":battle,"route":game.route.state.duplicate(true),"role":game.player_skill,"unlock":game.skill_system.horse_unlocked,"save":FileAccess.get_file_as_string(game.route.SAVE)}
func capture(viewport: SubViewport, game, name: String):
	game.card_picker.refresh();game.queue_redraw()
	for frame in 5: await RenderingServer.frame_post_draw
	var picture = viewport.get_texture().get_image()
	check(not picture.is_empty(),"real rendered image")
	check(picture.save_png(OUT + name + ".png") == OK,"write screenshot")
	reports.append({"file":name + ".png","width":picture.get_width(),"height":picture.get_height()})
func run():
	DirAccess.make_dir_recursive_absolute(OUT)
	for dimensions in SIZES:
		var viewport = SubViewport.new();viewport.size = dimensions;viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS;add_child(viewport)
		var game = load("res://main.tscn").instantiate();viewport.add_child(game);game.set_process(false);game.configure_layout(Vector2(dimensions))
		viewport.size_2d_override = Vector2i(game.ui_size);viewport.size_2d_override_stretch = true;game.size = game.ui_size
		game.player_skill = "king";game.seed_value = 141303;game.new_expedition();game.route.enter(0);game.show_home();game.skill_system.horse_unlocked = false;game.frontend.activate(0)
		var baseline = snapshot(game);var picker = game.card_picker;var suffix = "-" + str(dimensions.x)
		await capture(viewport,game,"role-chooser" + suffix)
		game.frontend.click(game.frontend.button_rect(4).get_center());check(picker.active and picker.action == "catalog","frontend opens catalog")
		for tab in 5:
			picker.tap(picker.catalog_tab_rect(tab).get_center())
			var group: String = picker.CATALOG.GROUPS[tab].id
			await capture(viewport,game,group + "-grid" + suffix)
			if picker.scroll_limit() > 0:
				picker.scroll_y = picker.scroll_limit();picker.refresh();await capture(viewport,game,group + "-grid-bottom" + suffix)
			for slot in picker.catalog_entries.size():
				picker.scroll_y = clampf(picker.card_rect(slot).get_center().y + picker.scroll_y - picker.grid_rect().get_center().y,0,picker.scroll_limit());picker.refresh()
				var entry: Dictionary = picker.catalog_entries[slot]
				picker.tap(picker.card_rect(slot).intersection(picker.grid_rect()).get_center())
				check(picker.catalog_detail and picker.catalog_id() == entry.id,"focused intended identity")
				await capture(viewport,game,group + "-" + entry.id + suffix)
				if picker.scroll_limit() > 0:
					picker.scroll_y = picker.scroll_limit();picker.refresh();await capture(viewport,game,group + "-" + entry.id + "-effect-bottom" + suffix)
				if picker.catalog_has_upgrade():
					picker.tap(picker.catalog_variant_rect().get_center());check(picker.catalog_id() == entry.upgrade_id,"upgraded same card")
					await capture(viewport,game,group + "-" + entry.upgrade_id + suffix)
				picker.tap(picker.catalog_back_rect().get_center());check(not picker.catalog_detail,"detail returns grid")
				check(snapshot(game) == baseline,"catalog preserves saved game and locked identities")
		picker.tap(picker.cancel_rect().get_center());check(not picker.active and game.screen == "skill_selection","catalog returns role chooser")
		await capture(viewport,game,"role-returned" + suffix)
		viewport.queue_free();await get_tree().process_frame
	var report = {"renderer":RenderingServer.get_video_adapter_name(),"screenshots":reports,"assertions":assertions,"failures":0}
	FileAccess.open(OUT + "report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	FileAccess.open(OUT + "complete.txt",FileAccess.WRITE).store_string("%d real native screenshots; %d passing assertions" % [reports.size(),assertions])
	print("CATALOG NATIVE: %d screenshots, %d assertions" % [reports.size(),assertions]);get_tree().quit()
