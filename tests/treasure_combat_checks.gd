extends SceneTree
const TS = preload("res://treasure_system.gd")
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if not value: failures += 1;push_error("TREASURE: " + label)
func settle():
	game.clear_effects();game.presentation.clear();game.input_lock = 0;game.navigation_lock = 0
func add(kind: String, pos: Vector2i, hp: int = 20) -> Dictionary:
	game.add_enemy(kind, pos, 999)
	var enemy: Dictionary = game.enemies.back();enemy.hp = hp;enemy.max_hp = hp
	return enemy
func fresh(id: String, cards: Array = [], lives: int = 3):
	game.player_skill = TS.DATA[id].role;game.new_expedition();game.route.enter(0)
	game.route.state.treasure_id = id;game.treasures.reset_battle()
	game.enemies = [];add("g", Vector2i(8,0),99)
	game.player = Vector2i(4,5);game.lives = lives;game.energy = 20
	game.hand = cards.duplicate();game.hand_ids = [];game.deck = [];game.discard = []
	game.phase = "play";game.screen = "game";game.active_displacements = 0
	game.basic_used = false;game.card_move_used = false;game.history.clear();game.sync_hand_views();settle()
func play(id: String, target: Vector2i):
	settle();var index = game.hand.find(id);check(index >= 0, "fixture has " + id)
	if index >= 0: game.play_card(index,target)
func move_event(target: Vector2i):
	var origin: Vector2i = game.player;game.player = target;game.record_active_displacement(origin)
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.settings.set_debug_mode(true)
	check(TS.DATA.size() == 10,"nine formal treasures plus one training-only shared treasure")
	for role in ["king","horse","artillery"]: check(TS.ids_for(role).size() == 3,"three choices for " + role)
	check_longevity();check_talisman();check_tiger();check_horse();check_spring();check_cannon();check_axle();check_fuse();check_scope();check_actual_movement();check_state_and_reset();check_fatal_victory()
	print("TREASURE COMBAT RESULT ",checks-failures," passed, ",failures," failed")
	game.free();quit(1 if failures else 0)
func check_longevity():
	fresh("longevity_seal",["life"],5)
	check(game.lives == 5 and game.life_limit() == -1 and game.can_heal(),"seal only removes cap, no heal")
	check("无上限" in game.card_data("life")[2],"healing card reflects cap")
	play("life",game.player);check(game.lives == 6,"life card heals beyond five")
	game.settle_victory();check(game.lives == 7,"triumph exceeds five")
	game.settle_victory();check(game.lives == 7,"victory healing atomic")
func check_talisman():
	fresh("life_talisman",["blood_edge","blood_edge"],1)
	var enemy = add("p",Vector2i(4,4),9)
	var preview: Dictionary = game.board_info.preview(0,Vector2i(4,4))
	var before = game.history.capture()
	check(not preview.self_defeat and "保留1命" in str(preview.lines),"self-cost preview shows rescue")
	check(before == game.history.capture(),"preview has no side effects")
	game.shield_charges = 1;play("blood_edge",Vector2i(4,4))
	check(game.lives == 1 and game.treasure_battle.talisman_used and game.phase == "play", "first self-death rescued")
	check(game.shield_charges == 1 and game.player == Vector2i(4,5) and enemy.hp == 7,"self-cost bypasses shield and recoil")
	settle();check(game.undo_action(),"rescue undo works")
	check(not game.treasure_battle.talisman_used and game.lives == 1,"undo restores unused talisman")
	play("blood_edge",Vector2i(4,4));play("blood_edge",Vector2i(4,4));check(game.phase == "dead" and game.lives == 0,"second self-death is lethal")
	fresh("life_talisman",["airdrop"],1);add("p",Vector2i(2,3),7)
	play("airdrop",Vector2i(3,4));check(game.lives == 1 and game.airdrop_recovery_turn == 2,"airdrop rescue retains recovery")
	settle();game.end_turn();check(game.recovery_active(),"airdrop still skips next turn")
	fresh("life_talisman",[],1);add("r",Vector2i(4,4),9)
	game.end_turn();check(game.lives == 1 and game.treasure_battle.talisman_used and game.player != Vector2i(4,5),"enemy lethal hit rescued then normal recoil")
	check(game.active_displacements == 0,"forced recoil is not active displacement")
func check_tiger():
	fresh("tiger_tally",[])
	move_event(Vector2i(3,5));move_event(Vector2i(2,5));check(game.treasure_battle.tiger_moves == 2 and game.hand.is_empty(),"tiger waits three successful events")
	game.end_turn();check(game.treasure_battle.tiger_moves == 2,"tiger remainder crosses turn")
	move_event(Vector2i(3,5));check(game.hand == ["treasure_king_step"] and game.treasure_battle.tiger_moves == 0,"third event generates exactly one step")
	var uid = game.hand_ids[0];game.basic_used = true;game.card_move_used = true
	check(game.can_commit_card(0,Vector2i(3,4)),"temporary move independent of both quotas")
	play("treasure_king_step",Vector2i(3,4))
	check(game.player == Vector2i(3,4) and game.hand.is_empty() and game.discard.is_empty() and game.treasure_battle.tiger_moves == 1,"step exhausts and counts toward next three, no draw")
	settle();check(game.undo_action() and game.hand_ids[0] == uid and game.treasure_battle.tiger_moves == 0,"undo restores exact physical temporary card")
	game.deck = ["sword"];game.energy = 3;settle();check(game.pass_card(0),"temporary pass permitted")
	check(game.energy == 0 and game.hand == ["sword"] and "treasure_king_step" not in game.discard and game.treasure_battle.tiger_moves == 0,"pass costs three, draws one, no treasure effect")
	game.treasures.generate_move("treasure_king_step");game.phase = "play";settle();game.end_turn()
	check("treasure_king_step" not in game.hand and "treasure_king_step" not in game.discard,"unplayed temporary vanishes at turn end")
func check_horse():
	fresh("wind_horseshoe",[]);game.energy = 0
	move_event(Vector2i(3,5));move_event(Vector2i(2,5));move_event(Vector2i(1,5))
	check(game.energy == 1 and game.hand.is_empty(),"second horse displacement grants energy once, no horse card")
	fresh("battle_tassel",["sweep"])
	move_event(Vector2i(3,5));move_event(Vector2i(4,5));var left = add("p",Vector2i(3,5),9);var right = add("p",Vector2i(5,5),9)
	var preview: Dictionary = game.board_info.preview(0,game.player)
	check(preview.affected.size() == 2 and preview.affected[0].damage == 3 and preview.affected[1].damage == 3,"entire sweep previews +2 per target")
	play("sweep",game.player);check(left.hp == 6 and right.hp == 6 and not game.treasure_battle.tassel_ready,"whole sweep gets buff once")
	fresh("battle_tassel",["retreat_strike"]);move_event(Vector2i(4,4));var victim = add("p",Vector2i(4,3),8)
	preview = game.board_info.preview(0,Vector2i(4,3));check(preview.affected[0].damage == 3,"return strike second move is previewed before damage")
	play("retreat_strike",Vector2i(4,3));check(victim.hp == 5 and game.active_displacements == 2 and not game.treasure_battle.tassel_ready,"return strike second move buffs same card")
	fresh("battle_tassel",["advance","sword"]);move_event(Vector2i(4,4));add("p",Vector2i(4,3),1);victim = add("p",Vector2i(4,2),8)
	play("advance",Vector2i(4,3));check(game.treasure_battle.tassel_ready and game.treasures.damage_bonus() == 0,"advance kill move arms only next attack")
	play("sword",Vector2i(4,2));check(victim.hp == 5,"next attack receives +2")
	fresh("battle_tassel",["sword"]);move_event(Vector2i(3,5));move_event(Vector2i(4,5))
	game.play_card(0,Vector2i(0,0));check(game.treasure_battle.tassel_ready,"invalid attack does not consume")
	game.energy = 3;game.deck = ["spear"];settle();game.pass_card(0);check(game.treasure_battle.tassel_ready,"passing attack does not consume")
	settle();game.end_turn();check(not game.treasure_battle.tassel_ready,"unused buff expires on turn end")
func check_spring():
	fresh("spring_bit",[],3);var enemy = add("p",Vector2i(1,1),1)
	game.damage_enemy(game.enemies.find(enemy));check(game.lives == 3 and game.treasure_battle.spring_kills == 1,"full health consumes true defeat")
	enemy = add("p",Vector2i(1,2),1);enemy.unyielding = true;game.damage_enemy(game.enemies.find(enemy))
	check(game.treasure_battle.spring_kills == 1,"unyielding fall not true defeat")
	game.lives = 2;enemy = add("p",Vector2i(1,3),1);game.damage_enemy(game.enemies.find(enemy));check(game.lives == 3 and game.treasure_battle.spring_kills == 2,"second true defeat heals")
	enemy = add("p",Vector2i(1,4),1);game.damage_enemy(game.enemies.find(enemy));check(game.lives == 3,"third defeat no heal")
	fresh("spring_bit",["sword"],2);game.enemies=[];add("g",Vector2i(4,4),1);play("sword",Vector2i(4,4))
	check(game.lives == 3 and game.phase == "reward","terminal general heals before victory carry")
func check_cannon():
	fresh("gate_cannon_seal",["cannon_shot"]);game.artillery_mode = "attack";game.treasures.start_turn();game.energy = 0
	add("stake",Vector2i(4,4),1);var victim = add("p",Vector2i(4,3),9)
	check(game.card_cost("cannon_shot") == 0 and game.can_commit_card(0,Vector2i(4,3)),"gate cost/legality zero on attack turn start")
	play("cannon_shot",Vector2i(4,3));check(victim.hp == 7 and game.energy == 0 and game.card_cost("cannon_shot") == 1,"discount used exactly once")
	game.treasures.start_turn();move_event(Vector2i(3,5));check(game.card_cost("cannon_shot") == 1,"active move invalidates discount")
	game.treasures.start_turn();game.treasures.on_stance_change("attack","march");game.treasures.on_stance_change("march","attack")
	check(game.card_cost("cannon_shot") == 1,"stance cycling cannot farm discount")
	game.artillery_mode = "march";game.treasures.start_turn();game.artillery_mode = "attack";game.treasures.on_stance_change("march","attack")
	check(game.card_cost("cannon_shot") == 1,"deploy midturn does not qualify")
func check_axle():
	fresh("roving_axle",["pack"]);game.artillery_mode = "attack";game.basic_used = true;game.card_move_used = true
	play("pack",game.player);check(game.hand == ["treasure_transfer"] and game.treasure_battle.axle_used,"first pack generates transfer")
	check(game.can_commit_card(0,Vector2i(4,4)),"axle move ignores both quotas")
	game.treasures.on_stance_change("march","attack");game.treasures.on_stance_change("attack","march");check(game.hand.size() == 1,"repeated stance cycle no duplicate")
	play("treasure_transfer",Vector2i(4,4));check(game.discard == ["pack"] and game.hand.is_empty(),"transfer exhausts without draw")
func check_fuse():
	fresh("chain_fire_fuse",["cannon_shot"]);game.artillery_mode = "attack";game.reload_ready = true
	add("stake",Vector2i(4,4),1);add("p",Vector2i(4,3),3);game.deck = ["sword","fatigue"];game.energy = 3
	play("cannon_shot",Vector2i(4,3));check(game.hand.size() == 2 and game.hand.has("fatigue") and game.energy == 1,"fuse stacks reload, uses normal fatigue draw")
	fresh("chain_fire_fuse",["cannon_shot"]);game.artillery_mode = "attack";add("stake",Vector2i(4,4),1);var victim=add("p",Vector2i(4,3),2);victim.unyielding=true;game.deck=["sword"]
	play("cannon_shot",Vector2i(4,3));check(game.hand.is_empty() and game.deck == ["sword"],"unyielding cannon fall no fuse draw")
	fresh("chain_fire_fuse",["cannon_shot"]);game.enemies=[];game.artillery_mode="attack";game.reload_ready=true
	add("stake",Vector2i(4,4),1);add("g",Vector2i(4,3),3);game.deck=["fatigue","sword"]
	play("cannon_shot",Vector2i(4,3));check(game.hand.is_empty() and game.deck.size()==2 and game.phase=="reward","terminal shot suppresses both draws")
func check_scope():
	fresh("longevity_seal",[],5);game.player_skill="horse";check(not game.unlimited_lives(),"wrong role does not activate treasure")
	game.player_skill="king";game.tutorial.active=true;check(not game.unlimited_lives() and game.treasures.status().is_empty(),"tutorial disables treasure")
	game.tutorial.active=false;game.route.state={};check(not game.unlimited_lives(),"no route ownership means no account effect")

func check_actual_movement():
	fresh("tiger_tally",["straight"])
	game.deck = ["sword","sword"]
	game.basic_move(Vector2i(4,4));check(game.active_displacements == 1 and game.treasure_battle.tiger_moves == 1,"real free move counted once")
	play("straight",Vector2i(4,2));check(game.active_displacements == 2 and game.treasure_battle.tiger_moves == 2,"real paid two-cell move counts one event")
	var before = game.treasure_battle.duplicate(true);game.basic_move(Vector2i(4,1))
	check(game.treasure_battle == before,"failed exhausted free move does not count")
	fresh("battle_tassel",["knight_assault"]);move_event(Vector2i(4,4));var enemy = add("p",Vector2i(5,2),3)
	play("knight_assault",Vector2i(5,2));check(enemy.hp == 1 and game.active_displacements == 1 and not game.treasure_battle.tassel_ready,"nonlethal assault cannot retroactively trigger damage buff")
	fresh("battle_tassel",["knight_assault"]);move_event(Vector2i(4,4));add("p",Vector2i(5,2),2)
	play("knight_assault",Vector2i(5,2));check(game.player == Vector2i(5,2) and game.active_displacements == 2 and game.treasure_battle.tassel_ready,"lethal assault move arms next card only")
func check_state_and_reset():
	check(TS.valid_battle_state({}),"legacy empty battle state accepted")
	for id in TS.DATA:
		if TS.DATA[id].role == "common": continue # Training-only treasure is not a formal reward.
		fresh(id)
		check(TS.valid_battle_state(game.treasure_battle),id + " canonical battle state valid")
		var before = game.history.capture();var serial = game.treasure_battle.trigger_serial
		game.treasures.status();game.treasures.status()
		check(game.history.capture() == before and game.treasure_battle.trigger_serial == serial,id + " status is read-only")
	game.treasure_battle.tiger_moves = 3;check(not TS.valid_battle_state(game.treasure_battle),"corrupt counter rejected")
	fresh("life_talisman",[],1);game.lose_lives(1);game.start_stage();check(not game.treasure_battle.talisman_used,"talisman resets next battle")
	fresh("spring_bit");game.treasure_battle.spring_kills = 2;game.start_stage();check(game.treasure_battle.spring_kills == 0,"spring resets next battle")
	fresh("tiger_tally");game.treasure_battle.tiger_moves=2;game.treasures.generate_move("treasure_king_step");game.start_stage()
	check(game.treasure_battle.tiger_moves == 0 and game.hand.is_empty() and "treasure_king_step" not in game.deck,"new battle has no counter/card carry")
	fresh("roving_axle");game.treasure_battle.axle_used = true;game.treasures.start_turn();check(not game.treasure_battle.axle_used,"axle resets per turn")
	fresh("wind_horseshoe");game.treasure_battle.wind_used=true;game.treasures.start_turn();check(not game.treasure_battle.wind_used,"wind resets per turn")
func check_fatal_victory():
	fresh("life_talisman",["blood_edge"],1);game.enemies=[];add("g",Vector2i(4,4),2)
	play("blood_edge",Vector2i(4,4));check(game.phase == "reward" and game.lives == 2 and game.treasure_battle.talisman_used,"self-cost rescue precedes simultaneous victory and triumph")
	fresh("life_talisman",["blood_edge"],1);game.treasure_battle.talisman_used=true;game.enemies=[];add("g",Vector2i(4,4),2)
	play("blood_edge",Vector2i(4,4));check(game.phase == "dead" and game.lives == 0,"used rescue cannot let victory or triumph outrun self-death")
