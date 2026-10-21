extends SceneTree
# Test-only driver: ordinary, validated production saves, never a runtime API.
# Headless runs assert behavior. A rendering display additionally produces PNGs.
const OUT = "res://../verification/v0.12.0/rook/"
const R = preload("res://rules.gd")
const CP = preload("res://cannon_planner.gd")
const RT = preload("res://rook_tactics.gd")
const NAMES = ["distance_control", "horse_complement", "stale_near_general", "general_barrier", "planned_formation", "boss_hold_credit", "mixed_stress", "general_evades_cannon"]
var checks = 0
var failures = 0
var reports = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
func json_write(path: String, value):
	var file = FileAccess.open(path, FileAccess.WRITE)
	check(file != null,"open report "+path)
	if file != null: file.store_string(JSON.stringify(value, "  ") + "\n")
func point(p: Vector2i): return [p.x,p.y]
func summary(game):
	var pieces = []
	for e in game.enemies:
		pieces.append({"uid":e.uid,"kind":e.kind,"pos":point(e.pos),"cd":e.cd,"period":e.period,"credits":e.get("action_credits",0),"moves":e.get("normal_moves",0),"intent":point(e.get("intent",Vector2i(-1,-1)))})
	return {"player":point(game.player),"turn":game.turn,"lives":game.lives,"pieces":pieces}
func setup(game, name: String):
	game.player_skill="artillery" if name=="general_evades_cannon" else "king";game.new_expedition();game.tutorial.stop();game.enemies=[];game.next_enemy_uid=1
	game.route.state.pending=0;game.route.state.nodes[0].encounter={"id":"pawn_cannon","tier":"battle","rules":[]}
	if name in ["boss_hold_credit","mixed_stress"]:
		game.route.state.visited=[0,1,4,6,7,10,13];game.route.state.current=13;game.route.state.pending=15
	var config=game.route.state.nodes[game.route.state.pending].encounter
	game.encounter_state={"config":config.duplicate(true),"phases":0,"retaliated":false,"river_triggered":false,"signal_uid":-1,"cannon_uid":-1,"guard_uids":[],"spawn_cell":Vector2i(-1,-1)}
	var specs=[]
	match name:
		"distance_control":
			game.player=Vector2i(4,5);specs=[["r",0,0,1]]
		"horse_complement":
			game.player=Vector2i(4,5);specs=[["r",8,0,1],["h",2,5,3]]
		"stale_near_general":
			game.player=Vector2i(5,1);specs=[["r",0,8,1],["g",4,0,3]]
		"general_barrier":
			game.player=Vector2i(4,2);specs=[["r",0,1,1],["g",4,0,3]]
		"planned_formation":
			game.player=Vector2i(4,5);specs=[["c",0,0,1],["p",2,4,1],["r",8,0,1]]
		"boss_hold_credit":
			# The horse already attacks, so a shield absorbs it before movement.
			# The first rook does NOT attack and has legal moves: its hold is an action.
			game.player=Vector2i(4,5);specs=[["r",3,4,3],["h",2,6,3],["r",8,9,3]];game.shield_charges=1
		"general_evades_cannon":
			game.player=Vector2i(4,9);game.artillery_mode="attack";specs=[["g",4,1,1],["stake",4,5,3],["c",0,1,1]]
		"mixed_stress":
			game.player=Vector2i(4,5);specs=[["c",0,0,1],["c",8,0,1],["c",0,9,1],["c",8,9,1],["h",2,2,1],["h",6,2,1],["h",2,7,1],["h",6,7,1],["p",2,4,1],["p",6,4,1],["p",3,6,1],["p",5,6,1],["g",4,0,1],["r",1,1,1],["r",7,8,1]]
	for spec in specs:
		game.add_enemy(spec[0],Vector2i(spec[1],spec[2]),3)
		var e=game.enemies.back();e.cd=spec[3];e.normal_moves=0;e.action_credits=0;e.action_credit_delay=0
		if name=="mixed_stress": e.action_credits=3;e.period=1
		if e.kind=="stake": e.permanent=true
	if name=="boss_hold_credit": game.enemies[0].action_credits=2;game.enemies[2].action_credits=3
	if name=="stale_near_general": game.enemies[0].ai_recent=[Vector2i(5,8)]
	if name=="general_barrier": game.enemies[0].ai_recent=[Vector2i(4,1)]
	game.lives=3;game.hand=[];game.hand_ids=[];game.deck=[];game.discard=[];game.logs=[]
	game.screen="game";game.phase="play";game.turn=1;game.notice="";game.initial_threat=0
	game.navigation_lock=0;game.input_lock=0;game.hover=Vector2i(-1,-1);game.mouse_pos=Vector2(-100,-100)
	game.clear_effects();game.plan_intents();game.refresh_free_card();game.queue_redraw()
func save_fixture(game, name: String):
	var battle=game.history.capture()
	check(game.route.valid_snapshot(game.route.state,battle,"game"),name+" valid ordinary snapshot")
	var config=ConfigFile.new();config.set_value("run","version",4);config.set_value("run","route",game.route.state);config.set_value("run","battle",battle);config.set_value("run","screen","game")
	check(config.save(OUT+"fixtures/"+name+".cfg")==OK,name+" fixture saved")
func screenshot(viewport, name: String):
	for frame in 3: await RenderingServer.frame_post_draw
	var image=viewport.get_texture().get_image()
	check(not image.is_empty(),name+" nonempty native render")
	check(image.save_png(OUT+"native/"+name+".png")==OK,name+" native saved")
func fixture_checks(game, name: String, before_board: Array, before_player: Vector2i, movement: Array, counts: Dictionary):
	check(game.turn==2 and game.lives==3 and game.player==before_player,name+" no move-and-shoot damage or unexpected recoil")
	for e in game.enemies:
		check(e.intent==Vector2i(-1,-1),name+" no hidden destination uid="+str(e.uid))
		check(counts.get(e.uid,0)<=1,name+" at most one movement uid="+str(e.uid))
		check(e.normal_moves==counts.get(e.uid,0),name+" movement counter matches animation uid="+str(e.uid))
	var rook=game.enemies[0]
	match name:
		"distance_control":
			check(rook.pos==Vector2i(4,0) and R.attacks(rook,game.player,game.enemies),"lone rook chooses real long-range pressure")
			check(absi(rook.pos.x-game.player.x)+absi(rook.pos.y-game.player.y)>=3,"lone rook stays outside adjacent and two-cell spear range")
		"horse_complement":
			var horse=game.enemies[1]
			check(horse.pos==Vector2i(2,5) and horse.normal_moves==0,"horse's actual current control remains stationary")
			for p in [Vector2i(4,4),Vector2i(4,6)]: check(R.attacks(horse,p,game.enemies),"horse really controls vertical exit "+str(p))
			for p in [Vector2i(3,5),Vector2i(5,5)]: check(R.attacks(rook,p,game.enemies) and not R.attacks(horse,p,game.enemies),"rook adds genuinely new lateral exit "+str(p))
			check(rook.pos==Vector2i(8,5) and R.attacks(rook,game.player,game.enemies),"rook complements horse rather than duplicating its file")
		"stale_near_general":
			check(RT.value(before_board[0],before_board,before_player)==0,"old rook line has no relevant control")
			check(rook.pos==Vector2i(5,8) and rook.pos in before_board[0].ai_recent,"obsolete line relocates despite return history")
			check(R.attacks(rook,game.player,game.enemies) and R.attacks(rook,Vector2i(5,0),game.enemies),"relocation pressures player and real palace approach")
		"general_barrier":
			check(CP.general_barrier(before_board,before_player)==0 and CP.general_barrier(game.enemies,game.player)>0,"rook creates an actual two-cell spear barrier")
			check(rook.pos==Vector2i(4,1) and rook.pos in before_board[0].ai_recent,"urgent general protection overrides anti-return inertia")
		"planned_formation":
			var cannon=game.enemies[0];var support=game.enemies[1];rook=game.enemies[2]
			check(not R.attacks(before_board[0],before_player,before_board),"cannon formation is newly planned, not preexisting")
			check(movement.size()==3 and movement[0].uid==2 and movement[1].uid==1 and movement[2].uid==3,"rook resolves after actual support-first cannon formation")
			check(R.attacks(cannon,game.player,game.enemies) and R.blockers(cannon.pos,game.player,game.enemies)==1 and support.pos==Vector2i(2,5),"rook preserves actual single-screen cannon threat")
			check(R.attacks(rook,game.player,game.enemies) and rook.pos.x==game.player.x and cannon.pos.y==game.player.y,"rook adds orthogonal pressure instead of spoiling formation")
		"boss_hold_credit":
			check(not R.attacks(before_board[0],before_player,before_board) and not R.moves(before_board[0],before_board,before_player).is_empty(),"holding rook is movement-eligible, not attack-skipped or trapped")
			check(rook.pos==before_board[0].pos and rook.normal_moves==0 and rook.action_credits==1 and rook.cd==rook.period,"voluntary rook hold spends exactly one Boss credit and resets cooldown")
			check(game.enemies[2].normal_moves==1 and game.enemies[2].action_credits==2,"second rook spends only one of three Boss credits")
			check(game.enemies[1].pos==before_board[1].pos and game.shield_charges==0,"existing horse attack is shielded before moves")
		"general_evades_cannon":
			var general=game.enemies[0]
			check(R.blockers(before_player,before_board[0].pos,before_board)==1,"general starts on real exactly-one-screen player cannon line")
			check(general.pos==Vector2i(3,1) and general.normal_moves==1 and general.cd==general.period,"ready general makes one legal side-step rather than serving as cannon screen")
			check(R.blockers(game.player,general.pos,game.enemies)!=1,"general leaves the player cannon firing line")
		"mixed_stress":
			var rooks_moved=0;var cannons=0;var rooks=0
			for e in game.enemies:
				check(e.action_credits==2 and e.period==1,"mixed army retains unused credits uid="+str(e.uid))
				if e.kind=="c": cannons+=1
				if e.kind=="r": rooks+=1;rooks_moved+=e.normal_moves
			check(cannons==4 and rooks==2 and rooks_moved>0,"stress exercises four cannons plus two real rook decisions")
func run():
	DirAccess.make_dir_recursive_absolute(OUT+"fixtures");DirAccess.make_dir_recursive_absolute(OUT+"native")
	var rendering=DisplayServer.get_name()!="headless"
	for size in [Vector2i(1280,940),Vector2i(390,844)]:
		var viewport=SubViewport.new();viewport.size=size;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
		var game=load("res://main.tscn").instantiate();viewport.add_child(game);game.set_process(false)
		game.configure_layout(Vector2(size));viewport.size_2d_override=Vector2i(game.ui_size);viewport.size_2d_override_stretch=true;game.size=game.ui_size
		for name in NAMES:
			setup(game,name)
			if size.x==1280: save_fixture(game,name)
			var before=summary(game);var before_board=game.enemies.duplicate(true);var before_player: Vector2i=game.player
			var occupied={before_player:true}
			for e in before_board:
				check(R.inside(e.pos) and not occupied.has(e.pos),name+" rule-valid unoccupied fixture cell uid="+str(e.uid));occupied[e.pos]=true
				if e.kind=="r": check(not R.attacks(e,before_player,before_board),name+" rook has no attack-before-move conflict uid="+str(e.uid))
			if rendering: await screenshot(viewport,name+"-before-"+str(size.x))
			var start=Time.get_ticks_usec();game.end_turn();var elapsed=Time.get_ticks_usec()-start
			var movement=[];var counts={};var projected=before_board.duplicate(true);var previous_delay=-0.28
			for fx in game.effects:
				if fx.kind!="move": continue
				var uid=fx.get("piece",{}).get("uid",-1);var i=CP.by_uid(projected,uid);var final_i=CP.by_uid(game.enemies,uid)
				check(i>=0 and final_i>=0,name+" movement belongs to real piece")
				if i<0 or final_i<0: continue
				var origin: Vector2i=projected[i].pos;var target: Vector2i=game.enemies[final_i].pos;var delay=float(fx.get("delay",0))
				check(target in R.moves(projected[i],projected,before_player),name+" sequentially legal movement uid="+str(uid))
				check(fx.from.is_equal_approx(game.cell_pos(origin)) and fx.to.is_equal_approx(game.cell_pos(target)),name+" animation matches real board movement uid="+str(uid))
				check(delay>=previous_delay+0.279,name+" serial nonoverlapping movement animation uid="+str(uid));previous_delay=delay
				movement.append({"uid":uid,"delay":delay,"from":[fx.from.x,fx.from.y],"to":[fx.to.x,fx.to.y],"from_cell":point(origin),"to_cell":point(target)})
				counts[uid]=counts.get(uid,0)+1;projected[i].pos=target
			fixture_checks(game,name,before_board,before_player,movement,counts)
			var after=summary(game)
			game.clear_effects();game.initial_threat=0;game.queue_redraw()
			if rendering: await screenshot(viewport,name+"-after-"+str(size.x))
			reports.append({"name":name,"viewport":[size.x,size.y],"before":before,"after":after,"movement":movement,"native_end_turn_us":elapsed,"native_rendered":rendering})
		game.free();viewport.free()
	json_write(OUT+"native-behavior.json",{"checks":checks,"failures":failures,"rendered":rendering,"scenarios":reports})
	print("ROOK FIXTURES ",checks," checks, ",failures," failures; rendered=",rendering)
	quit(1 if failures else 0)
