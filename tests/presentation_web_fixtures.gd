extends SceneTree
const OUT = "res://../verification/v0.14.3/presentation/"
var game
func _initialize(): call_deferred("run")
func point(p): return [p.x,p.y]
func save_fixture(name: String):
	game.route.save();assert(game.route.valid_snapshot(game.route.state,game.history.capture(),game.screen))
	FileAccess.open(OUT+"fixtures/"+name+".cfg",FileAccess.WRITE).store_string(FileAccess.get_file_as_string(game.route.SAVE))
func run():
	DirAccess.make_dir_recursive_absolute(OUT+"fixtures")
	game=load("res://main.tscn").instantiate();root.add_child(game);game.settings.set_debug_mode(true);FileAccess.open(OUT+"fixtures/settings.cfg",FileAccess.WRITE).store_string(FileAccess.get_file_as_string(game.settings.SAVE));game.set_process(false)
	var reports=[]
	for size in [Vector2(1280,940),Vector2(390,844)]:
		game.configure_layout(size);game.seed_value=14343;game.player_skill="king";game.new_expedition();game.route.enter(0)
		var name="presentation-"+str(int(size.x))
		save_fixture(name+"-victory")
		var report={"name":name,"viewport":point(size),"logical_size":point(game.ui_size),"skip":point(game.debug_skip_rect().get_center())}
		game.screen="home";report.resume=point(game.frontend.button_rect(3).get_center());game.screen="game"
		game.debug_skip();game.choose_reward(-1);game.presentation.clear()
		game.route.state.nodes[1].event_id="manual";game.route.enter(1);game.collection=["sword","spear","sword_plus"];game.route.refresh_choices()
		save_fixture(name+"-upgrade");report.before=game.collection.duplicate()
		report.choose=point(game.route.row_rect(2).get_center());report.confirm=point(game.route.row_rect(0).get_center())
		game.route.resolve(2);game.route.resolve(0);report.after=game.collection.duplicate();report.view=point(game.route.deck_rect().get_center())
		game.presentation.clear();game.route.click(game.route.deck_rect().get_center());report.back=point(game.card_picker.cancel_rect().get_center());reports.append(report)
		game.card_picker.close()
	FileAccess.open(OUT+"replays.json",FileAccess.WRITE).store_string(JSON.stringify(reports,"  "));game.queue_free();print("PRESENTATION WEB FIXTURES 4 saves");quit()
