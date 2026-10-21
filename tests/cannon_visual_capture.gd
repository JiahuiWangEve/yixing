extends SceneTree
# Test-only scene driver. Produces valid ordinary save files, not runtime hooks.
# Headless: generate fixtures and native behavior traces. GUI: additionally render.
const OUT = "res://../verification/v0.11.0/cannon/"
var checks = 0
var failures = 0
var reports = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
func json_write(path: String, value):
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "  ") + "\n")
func point(p: Vector2i): return [p.x,p.y]
func summary(game):
	var pieces = []
	for e in game.enemies:
		pieces.append({"uid":e.uid,"kind":e.kind,"pos":point(e.pos),"cd":e.cd,"period":e.period,"credits":e.get("action_credits",0),"moves":e.get("normal_moves",0),"intent":point(e.get("intent",Vector2i(-1,-1)))})
	return {"player":point(game.player),"turn":game.turn,"lives":game.lives,"pieces":pieces}
func setup(game, name: String):
	game.new_expedition();game.tutorial.stop();game.enemies=[];game.next_enemy_uid=1
	game.route.state.pending=0;game.route.state.nodes[0].encounter={"id":"pawn_cannon","tier":"battle","rules":[]}
	if name in ["held_support","boss_credit_cap","stress_four_cannons"]:
		game.route.state.visited=[0,1,4,6,7,10,13];game.route.state.current=13;game.route.state.pending=15
	var config=game.route.state.nodes[game.route.state.pending].encounter
	game.encounter_state={"config":config.duplicate(true),"phases":0,"retaliated":false,"river_triggered":false,"signal_uid":-1,"cannon_uid":-1,"guard_uids":[],"spawn_cell":Vector2i(-1,-1)}
	var specs=[]
	match name:
		"support_first":
			game.player=Vector2i(4,5);specs=[["c",0,0,1],["p",2,4,1]]
		"cannon_first":
			game.player=Vector2i(0,8);specs=[["c",0,4,1],["h",2,3,1]]
		"held_support":
			game.player=Vector2i(0,8);specs=[["c",0,0,3],["h",0,3,3]];game.shield_charges=1
		"obsolete_line":
			game.player=Vector2i(5,1);specs=[["c",0,8,1],["stake",2,8,3],["stake",2,1,3],["g",4,0,3]]
		"boss_credit_cap":
			game.player=Vector2i(4,5);specs=[["c",0,0,1],["p",2,4,1]]
		"stress_four_cannons":
			game.player=Vector2i(4,5);specs=[["c",0,0,1],["c",8,0,1],["c",0,9,1],["c",8,9,1],["h",2,2,1],["h",6,2,1],["h",2,7,1],["h",6,7,1],["p",2,4,1],["p",6,4,1],["p",3,6,1],["p",5,6,1],["g",4,0,1]]
	for spec in specs:
		game.add_enemy(spec[0],Vector2i(spec[1],spec[2]),3)
		var e=game.enemies.back();e.cd=spec[3];e.normal_moves=0;e.action_credits=0;e.action_credit_delay=0
		if name in ["boss_credit_cap","stress_four_cannons"]: e.action_credits=3
		if name=="stress_four_cannons": e.period=1
		if e.kind=="stake": e.permanent=true
	if name=="held_support": game.enemies[1].action_credits=2
	if name=="obsolete_line": game.enemies[0].ai_recent=[Vector2i(0,1)]
	game.lives=3;game.hand=[];game.hand_ids=[];game.deck=[];game.discard=[];game.logs=[]
	game.screen="game";game.phase="play";game.turn=1;game.notice="";game.initial_threat=0
	game.navigation_lock=0;game.input_lock=0;game.hover=Vector2i(-1,-1);game.mouse_pos=Vector2(-100,-100)
	game.clear_effects();game.plan_intents();game.refresh_free_card();game.queue_redraw()
func save_fixture(game, name: String):
	var battle=game.history.capture()
	check(game.route.valid_snapshot(game.route.state,battle,"game"),name+" valid ordinary snapshot")
	var config=ConfigFile.new();config.set_value("run","version",5);config.set_value("run","route",game.route.state);config.set_value("run","battle",battle);config.set_value("run","screen","game")
	check(config.save(OUT+"fixtures/"+name+".cfg")==OK,name+" fixture saved")
func screenshot(viewport, name: String):
	for frame in 3: await RenderingServer.frame_post_draw
	var image=viewport.get_texture().get_image()
	check(not image.is_empty(),name+" nonempty native render")
	check(image.save_png(OUT+"native/"+name+".png")==OK,name+" native saved")
func run():
	DirAccess.make_dir_recursive_absolute(OUT+"fixtures")
	DirAccess.make_dir_recursive_absolute(OUT+"native")
	var rendering=DisplayServer.get_name()!="headless"
	for size in [Vector2i(1280,940),Vector2i(390,844)]:
		var viewport=SubViewport.new();viewport.size=size;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
		var game=load("res://main.tscn").instantiate();viewport.add_child(game);game.set_process(false)
		game.configure_layout(Vector2(size));viewport.size_2d_override=Vector2i(game.ui_size);viewport.size_2d_override_stretch=true;game.size=game.ui_size
		for name in ["support_first","cannon_first","held_support","obsolete_line","boss_credit_cap","stress_four_cannons"]:
			setup(game,name)
			if size.x==1280: save_fixture(game,name)
			var before=summary(game)
			if rendering: await screenshot(viewport,name+"-before-"+str(size.x))
			var start=Time.get_ticks_usec();game.end_turn();var elapsed=Time.get_ticks_usec()-start
			var movement=[];var counts={}
			for fx in game.effects:
				if fx.kind!="move": continue
				var uid=fx.get("piece",{}).get("uid",-1)
				movement.append({"uid":uid,"delay":fx.get("delay",0),"from":[fx.from.x,fx.from.y],"to":[fx.to.x,fx.to.y]})
				counts[uid]=counts.get(uid,0)+1
			if name in ["boss_credit_cap","stress_four_cannons"]:
				for count in counts.values(): check(count<=1,name+" at most one movement per enemy")
			for e in game.enemies: check(e.intent==Vector2i(-1,-1),name+" no hidden destination")
			if name=="support_first": check(movement.size()==2 and movement[0].uid==2 and movement[1].uid==1,"support moves first")
			if name=="cannon_first": check(movement.size()==2 and movement[0].uid==1 and movement[1].uid==2,"cannon moves first")
			if name=="held_support": check(game.enemies[1].pos==Vector2i(0,3) and game.enemies[1].action_credits==1,"held support spends one credit")
			if name=="obsolete_line": check(game.enemies[0].pos==Vector2i(0,1),"outdated cannon line relocates")
			var after=summary(game)
			game.clear_effects();game.initial_threat=0;game.queue_redraw()
			if rendering: await screenshot(viewport,name+"-after-"+str(size.x))
			reports.append({"name":name,"viewport":[size.x,size.y],"before":before,"after":after,"movement":movement,"native_end_turn_us":elapsed,"native_rendered":rendering})
		game.free();viewport.free()
	json_write(OUT+"native-behavior.json",{"checks":checks,"failures":failures,"rendered":rendering,"scenarios":reports})
	print("CANNON FIXTURES ",checks," checks, ",failures," failures; rendered=",rendering)
	quit(1 if failures else 0)
