extends SceneTree
# Multi-selection is a rules-layer feature, not a HUD-only badge. Exercise all
# compatible effects, formal isolation, and read-only per-icon inspection.
const T = preload("res://treasure_system.gd")
const D = preload("res://decoy_system.gd")
const SIZES = [Vector2(1280,940), Vector2(390,844), Vector2(360,640), Vector2(844,390)]
const POOLS = {
	"king": ["longevity_seal", "life_talisman", "tiger_tally"],
	"horse": ["wind_horseshoe", "battle_tassel", "spring_bit"],
	"artillery": ["gate_cannon_seal", "roving_axle", "chain_fire_fuse"]
}
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("TRAINING TREASURES: " + label)
func settle():
	game.clear_effects();game.presentation.clear();game.input_lock = 0;game.navigation_lock = 0
func add(kind: String, cell: Vector2i, hp: int = 20) -> Dictionary:
	game.add_enemy(kind,cell,999)
	var piece: Dictionary = game.enemies.back();piece.hp = hp;piece.max_hp = hp
	return piece
func fresh(role: String, cards: Array = []):
	game.training.playing = false;game.tutorial.stop();game.player_skill = role;game.new_expedition();game.route.enter(0)
	game.training.state = game.training.new_state();game.training.state.player_skill = role
	game.training.state.treasure_ids = T.training_ids_for(role);game.training.playing = true
	game.player = Vector2i(4,5);game.energy = 20;game.lives = 3;game.turn = 1;game.artillery_mode = "attack"
	game.enemies = [];add("g",Vector2i(8,0),99)
	game.hand = cards.duplicate();game.hand_ids = [];game.deck = [];game.discard = []
	game.phase = "play";game.screen = "game";game.active_displacements = 0
	game.basic_used = false;game.card_move_used = false;game.history.clear();game.sync_hand_views()
	game.treasures.reset_battle();game.treasureui.clear_feedback();settle()
func move_to(cell: Vector2i):
	var before: Vector2i = game.player;game.player = cell;game.record_active_displacement(before)
func play(id: String, cell: Vector2i):
	settle();var index = game.hand.find(id);check(index >= 0,"fixture contains " + id)
	if index >= 0: game.play_card(index,cell)
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.settings.set_debug_mode(true)
	check_pools();check_filters();check_king();check_horse();check_artillery();check_decoy();check_icons()
	game.training.playing = false
	print("TRAINING TREASURES RESULT %d checks, %d failures" % [checks, failures]);game.free();quit(1 if failures else 0)
func check_pools():
	for role in POOLS:
		check(T.ids_for(role) == POOLS[role],"formal pool unchanged: " + role)
		check(T.training_ids_for(role) == POOLS[role] + ["decoy_tally"],"only common decoy expands training pool: " + role)
	check(T.ids_for("common").is_empty() and T.ids_for("invalid").is_empty(),"no shared or unknown formal reward pool")
	check("decoy_card" not in T.TEMPORARY,"decoy card never expires through temporary-card path")
	fresh("king")
	game.route.state.treasure_id = "life_talisman";var route = game.route.state.duplicate(true)
	check(game.treasures.active_id().is_empty(),"formal accessor does not alias the first training treasure")
	check(game.treasures.active_ids().size() == 4 and game.route.state == route,"training ownership never mutates route ownership")
	game.training.playing = false
	check(game.treasures.active_id() == "life_talisman" and game.treasures.active_ids() == ["life_talisman"],"formal runtime returns saved singleton")
	game.route.state.treasure_id = "decoy_tally"
	check(game.treasures.active_ids().is_empty(),"training-only common cannot leak into formal runtime")
func check_filters():
	for role in POOLS:
		fresh(role)
		var other = "horse" if role != "horse" else "king"
		game.training.state.treasure_ids = POOLS[role] + ["decoy_tally", POOLS[role][0], POOLS[other][0], "not_a_treasure", 12]
		check(game.treasures.active_ids() == POOLS[role] + ["decoy_tally"],"compatible multiset deduplicated and wrong class filtered: " + role)
		check(not game.treasures.has(POOLS[other][0]) and game.treasures.status(POOLS[other][0]).is_empty(),"forbidden class has neither effect nor status: " + role)
		game.tutorial.active = true
		check(game.treasures.active_ids().is_empty(),"tutorial blocks training treasure effects")
		game.tutorial.active = false;game.training.state.treasure_ids = "invalid"
		check(game.treasures.active_ids().is_empty(),"malformed selection safely disables treasures")
func check_king():
	fresh("king",["blood_edge"]);game.lives = 1;var victim = add("p",Vector2i(4,4),9)
	check(game.life_limit() == -1,"selected longevity seal removes cap alongside other treasures")
	play("blood_edge",victim.pos)
	check(game.lives == 1 and game.treasure_battle.talisman_used and victim.hp == 7,"selected talisman rescues actual card self-damage")
	move_to(Vector2i(3,5));move_to(Vector2i(2,5));move_to(Vector2i(1,5))
	check(game.hand == ["treasure_king_step"] and game.treasure_battle.tiger_moves == 0,"selected tiger grants step alongside both king treasures")
	check(game.treasures.status("life_talisman").used and game.treasures.status("longevity_seal").ready,"independent king icon states")
	check(game.treasures.status("life_talisman").trigger_serial == 1 and game.treasures.status("tiger_tally").trigger_serial == 1,"per-treasure trigger counters")
	var snap = game.history.capture();game.treasures.on_enemy_defeated({"kind":"decoy"})
	check(game.history.capture() == snap,"neutral decoys are never rewarded as defeated enemies")
func check_horse():
	fresh("horse",["sword"]);game.energy = 0;game.lives = 2
	move_to(Vector2i(3,5));move_to(Vector2i(4,5))
	check(game.energy == 1 and game.treasure_battle.wind_used and game.treasure_battle.tassel_ready,"same displacement procs both horseshoe and tassel")
	var ids: Array = game.treasureui.feedback_events.map(func(e): return e.id)
	check("wind_horseshoe" in ids and "battle_tassel" in ids,"concurrent feedback preserves both exact source IDs")
	check(game.treasures.status("wind_horseshoe").used and game.treasures.status("battle_tassel").ready,"horse icon status does not implicitly read first treasure")
	var victim = add("p",Vector2i(4,4),3)
	play("sword",victim.pos)
	check(victim not in game.enemies and not game.treasure_battle.tassel_ready,"buffed attack actually defeats a three-health enemy")
	check(game.lives == 3 and game.treasure_battle.spring_kills == 1,"third horse treasure heals on same actual defeat")
	check(game.treasure_battle.trigger_serial == 3,"all independent triggered effects counted exactly once")
func check_artillery():
	fresh("artillery",["cannon_shot", "pack"]);game.energy = 0;game.reload_ready = false
	add("stake",Vector2i(4,4),1);add("p",Vector2i(4,3),2);game.deck = ["sword"]
	check(game.card_cost("cannon_shot") == 0,"first artillery treasure discounts actual cannon card")
	play("cannon_shot",Vector2i(4,3))
	check("sword" in game.hand and game.deck.is_empty(),"third artillery treasure draws for the discounted kill")
	check(game.treasures.status("gate_cannon_seal").trigger_serial == 1 and game.treasures.status("chain_fire_fuse").trigger_serial == 1,"discount and draw have separate exact-source counters")
	game.energy = 20;play("pack",game.player)
	check("treasure_transfer" in game.hand and game.treasure_battle.axle_used,"second artillery treasure generates transfer after pack")
	check(game.treasures.status("roving_axle").used and not game.treasures.status("gate_cannon_seal").ready,"all artillery statuses reflect actual independent rules")
func check_decoy():
	fresh("king")
	check(game.decoys.start_turn() and game.hand == ["decoy_card"],"first turn creates one decoy card")
	var uid: int = game.hand_ids[0]
	check(not game.decoys.start_turn() and game.hand.size() == 1,"repeated same-turn callback never duplicates")
	game.treasures.end_turn();game.turn = 2;game.treasures.start_turn()
	check(game.hand == ["decoy_card"] and game.hand_ids[0] == uid and not game.decoys.start_turn(),"decoy persists as same physical card on second turn")
	game.turn = 4;game.treasures.start_turn()
	check(not game.decoys.start_turn() and game.hand.size() == 1,"fourth turn cannot exceed one in hand")
	check(game.treasures.status("decoy_tally").ready and game.treasures.status("decoy_tally").badge == "备","available persistent card is shown as ready")
	play("decoy_card",Vector2i(6,7))
	var decoy = D.find(game.enemies)
	check(not decoy.is_empty() and decoy.hp == 2,"card places actual two-health object in inclusive 5x5 area")
	check(game.treasures.status("decoy_tally").badge == "2血" and not game.decoys.can_place(Vector2i(3,5)),"live object status and single-board-object limit")
	decoy.hp = 1
	check(game.treasures.status("decoy_tally").badge == "1血","icon reflects actual remaining object health")
	game.turn = 7;game.treasures.start_turn();check(game.decoys.start_turn(),"seventh turn may generate while existing board decoy remains")
	check(not game.treasures.status("decoy_tally").ready and game.hand.count("decoy_card") == 1,"held card is blocked while an object is on board")
	check(game.treasures.status("decoy_tally").trigger_serial == 2,"decoy generation source attributed without counting suppressed procs")
	check(T.valid_battle_state(game.treasure_battle),"multi-treasure/decoy counters validate for snapshots")
	var invalid = game.treasure_battle.duplicate(true);invalid.decoy_last_turn = -2
	check(not T.valid_battle_state(invalid),"corrupt decoy generation counter rejected")
func check_icons():
	for size in SIZES:
		for role in POOLS:
			fresh(role);game.configure_layout(size)
			var before = game.history.capture();var route = game.route.state.duplicate(true)
			var ids = game.treasures.active_ids();var rectangles: Array = []
			for index in ids.size():
				var id: String = ids[index];var rect = game.treasureui.icon_rect(index)
				check(rect.size.x >= 44 and rect.size.y >= 44,"all icon touch targets at least44px")
				check(Rect2(Vector2.ZERO,game.ui_size).encloses(rect),"all icons inside viewport")
				for other in rectangles: check(not rect.intersects(other),"icon hit targets do not overlap")
				rectangles.append(rect)
				for control in [game.home_rect(),game.RESTART_RECT,game.UNDO_RECT,game.END_TURN_RECT,game.debug_skip_rect()]:
					check(not rect.intersects(control),"icon does not cover a control")
				var info: Dictionary = game.treasureui.inspect_at(rect.get_center())
				check(info.get("treasure_id") == id and info.get("title") == T.DATA[id].name and info.get("lines") == game.treasures.status(id).lines,"every icon shows its own canonical name and actual status")
				game.information.candidate(rect.get_center(),"mouse");game.information.tick(0.31)
				check(game.information.visible and game.information.data.treasure_id == id,"hover opens exact multitreasure inspector")
				game.information.clear();game.information.candidate(rect.get_center(),"touch",1);game.information.tick(0.41)
				check(game.information.visible and game.information.data.treasure_id == id,"hold opens exact multitreasure inspector")
				game.information.clear()
			check(game.history.capture() == before and game.route.state == route,"all multi-icon inspection stays read-only")
			game.treasureui.trigger("draw","",ids[0]);game.treasureui.trigger("draw","",ids[1]);game.treasureui.clear_feedback()
			check(game.treasureui.feedback_events.is_empty() and game.treasureui.feedback.is_empty(),"restart can clear every concurrent presentation pulse")
