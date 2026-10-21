extends SceneTree
# Offline QA driver: emits validated ordinary save files and real UI replay steps.
const OUT = "res://../verification/v0.13.0/events/"
var game
var steps = []
var failures = 0
func _initialize(): call_deferred("run")
func check(ok, label):
	if not ok: failures += 1;push_error(label)
func summary() -> Dictionary:
	return {"screen": game.screen, "current": game.route.state.current, "pending": game.route.state.pending, "visited": game.route.state.visited.duplicate(), "prepared": game.route.state.prepared, "reward_debt": game.route.state.reward_debt, "reward_blocked": game.route.state.reward_blocked, "pending_homework": game.route.state.pending_homework.duplicate(), "homework_awarded": game.route.state.homework_awarded.duplicate(), "energy": game.energy, "turn": game.turn, "deck": game.deck.duplicate(), "discard": game.discard.duplicate(), "collection": game.collection.duplicate(), "hand": game.hand.duplicate(), "rewards": game.rewards.duplicate(), "lives": game.lives, "phase": game.phase}
func point(v): return [v.x,v.y]
func step(kind: String, label: String, taps: Array = []):
	steps.append({"kind":kind,"label":label,"taps":taps,"expected":summary()})
func choose(action: String, card_index: int = -1):
	if action == "upgrade" and not game.card_picker.active: choose("select_upgrade")
	if game.card_picker.active:
		var picker = game.card_picker
		var pos: Vector2
		if action == "back": pos = picker.cancel_rect().get_center()
		elif action == "confirm": pos = picker.confirm_rect().get_center()
		else:
			var slot = picker.indices.find(card_index)
			check(slot >= 0, "picker instance exists " + action)
			if slot < 0: return
			pos = picker.card_rect(slot).get_center()
			check(picker.grid_rect().has_point(pos), "fixture selection is visible")
		picker.tap(pos);step("tap", action, [point(pos)]);return
	var index = -1
	for i in game.route.choices.size():
		var choice = game.route.choices[i]
		if choice.action == action and (card_index < 0 or choice.get("index", -1) == card_index): index = i;break
	check(index >= 0, "choice exists "+action)
	if index < 0: return
	var taps = []
	var target_page = int(index / game.route.capacity())
	while game.route.page < target_page:
		taps.append(point(game.route.footer_rect(1).get_center()));game.route.page += 1
	taps.append(point(game.route.row_rect(index % game.route.capacity()).get_center()))
	game.route.resolve(index)
	step("tap", action, taps)
func reload_step():
	game.route.save();check(game.route.resume(),"fixture resume")
	step("reload","resume without reroll")
func enter(id: int):
	game.route.focus_current()
	var taps = [point(game.route.position(game.route.state.nodes[id])), point(game.route.confirm_rect().get_center())]
	check(game.route.map_rect().has_point(Vector2(taps[0][0],taps[0][1])), "next node visible")
	game.route.enter(id);step("enter","enter node "+str(id),taps)
func victory():
	game.debug_skip();step("tap","debug victory",[point(game.debug_skip_rect().get_center())])
func reward_return():
	var pos = game.rewardui.confirm_rect().get_center() if game.route.rewards_blocked() else game.rewardui.choice_rect(2).get_center()
	game.navigation_lock = 0;game.choose_reward(-1);step("tap","return from victory",[point(pos)])
func setup(name: String, size: Vector2):
	game.player_skill="king";game.seed_value=1313;game.new_expedition();game.configure_layout(size)
	game.route.enter(0);game.route.complete()
	game.collection=["sword_plus","sword","spear","life","sword_plus"];game.lives=4
	if name=="workshop":
		game.route.state.visited=[0,1,4];game.route.state.current=4;game.route.enter(6)
	elif name.begins_with("camp"): game.route.enter(3)
	else:
		var event_id="herbalist" if name.begins_with("herb") else ("merchant" if name=="merchant" else "manual")
		game.route.state.nodes[1].event_id=event_id
		if name=="herb_full": game.lives=5

		if name=="manual_ineligible": game.collection=["sword_plus","life"]
		game.route.enter(1)
	if name.begins_with("fatigue"):
		game.new_expedition();game.route.enter(0)
		game.collection=["sword","fatigue","fatigue"];game.deck=["sword","fatigue","fatigue"];game.hand=[];game.hand_ids=[];game.discard=[]
		game.energy=0 if name=="fatigue_zero" else 1
	game.route.save();steps=[]
func run():
	DirAccess.make_dir_recursive_absolute(OUT+"fixtures")
	game=load("res://main.tscn").instantiate();root.add_child(game);game.settings.set_debug_mode(true);FileAccess.open(OUT+"fixtures/settings.cfg",FileAccess.WRITE).store_string(FileAccess.get_file_as_string(game.settings.SAVE))
	var reports=[]
	for size in [Vector2(1280,940),Vector2(390,844),Vector2(844,390),Vector2(360,640)]:
		for name in ["herb_heal","herb_breath","herb_full","merchant","manual_focus","manual_homework","manual_mnemonic","manual_ineligible","camp_prepare","camp_remove","workshop","fatigue_zero","fatigue_one"]:
			setup(name,size)
			var filename=name+"-"+str(int(size.x))+".cfg"
			check(game.route.valid_snapshot(game.route.state,game.history.capture(),game.screen),filename+" valid")
			var file=FileAccess.open(OUT+"fixtures/"+filename,FileAccess.WRITE);file.store_string(FileAccess.get_file_as_string(game.route.SAVE));file.close()
			var initial=summary()
			match name:
				"herb_heal": choose("heal");choose("back");reload_step();choose("heal");choose("confirm")
				"herb_breath": choose("breath");choose("confirm")
				"herb_full": choose("disabled");choose("breath");choose("confirm")
				"merchant": choose("select_exchange");choose("exchange",0);choose("back");reload_step();choose("select_exchange");choose("exchange",0);choose("confirm")
				"manual_focus","manual_homework":
					var mode="focus" if name=="manual_focus" else "homework"
					choose("select_"+mode);choose(mode,0);choose("back");reload_step();choose("select_"+mode);choose(mode,0);choose("confirm");reload_step()
					enter(4);victory();reload_step();reward_return();enter(6);choose("leave");enter(7);victory();reward_return()
				"manual_mnemonic": choose("random_upgrade");choose("back");reload_step();choose("random_upgrade");choose("confirm")
				"manual_ineligible": choose("disabled");choose("leave")
				"camp_prepare": choose("prepare");choose("back");choose("prepare");choose("confirm");reload_step();enter(5)
				"camp_remove": choose("select_remove");choose("remove",0);choose("back");choose("select_remove");choose("remove",0);choose("confirm")
				"fatigue_zero","fatigue_one":
					for target in [Vector2i(4,8),Vector2i(4,7)]:
						game.input_lock=0;game.navigation_lock=0;game.basic_move(target)
						step("combat","draw fatigue",[point(game.cell_pos(target))])
						game.input_lock=0;game.end_turn()
						step("combat","retained fatigue next turn",[point(game.END_TURN_RECT.get_center())])
				"workshop": choose("upgrade",1);choose("back");choose("upgrade",1);choose("confirm")
			reports.append({"fixture":filename,"name":name,"viewport":point(size),"logical_size":point(game.ui_size),"initial":initial,"steps":steps.duplicate(true)})
	var file=FileAccess.open(OUT+"replays.json",FileAccess.WRITE);file.store_string(JSON.stringify(reports,"  "));file.close()
	print("EVENT WEB FIXTURES ",reports.size()," replays, ",failures," failures")
	game.free();quit(1 if failures else 0)
