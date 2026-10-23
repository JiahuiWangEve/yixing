extends SceneTree
var game
var checks=0
var failures=0
func _initialize(): call_deferred("run")
func check(value: bool,label:String):
	checks+=1
	if not value: failures+=1;push_error("TRAINING LAYOUT: "+label)
func inspect(label:String):
	game.queue_redraw();await process_frame;await process_frame
	var hits: Array=game.training.hit_regions
	check(not hits.is_empty(),label+" produces interactive regions")
	var viewport_rect=Rect2(Vector2.ZERO,game.ui_size)
	for i in hits.size():
		check(viewport_rect.encloses(hits[i].rect),label+" target in viewport "+hits[i].id)
		for j in range(i+1,hits.size()):
			var overlap:Rect2=hits[i].rect.intersection(hits[j].rect)
			check(overlap.size.x<=1 or overlap.size.y<=1,label+" targets disjoint "+hits[i].id+" / "+hits[j].id)
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	var training=game.training;training.open();training.create_new()
	for size in [Vector2(1280,940),Vector2(390,844),Vector2(480,660),Vector2(844,390)]:
		game.configure_layout(size)
		if game.compact_landscape:
			check(training.status_position().y-14 > training.board_bounds().end.y,"landscape status clears board")
			check(training.status_position().y < game.ui_size.y-66,"landscape status clears footer buttons")
		for tab in 4:
			training.tab=tab;training.tab_page=0;training.modal="";training.selected_piece=-2
			await inspect(str(size)+" tab"+str(tab))
		for modal in ["cards","options","presets","tab_drawer"]:
			training.modal=modal;training.tab=3;training.card_group=1;training.card_page=0
			await inspect(str(size)+" "+modal)
		for piece in [-1,0]:
			training.selected_piece=piece;training.modal="attributes"
			await inspect(str(size)+" attributes"+str(piece))
	training.hide_name_edit()
	print("TRAINING LAYOUT: %d checks, %d failures"%[checks,failures])
	game.free();quit(1 if failures else 0)
