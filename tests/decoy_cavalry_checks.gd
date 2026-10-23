extends SceneTree
const R = preload("res://rules.gd")
const AI = preload("res://enemy_ai.gd")
const CP = preload("res://cannon_planner.gd")
const GE = preload("res://general_evasion.gd")
const CAV = preload("res://cavalry_roles.gd")
const D = preload("res://decoy_system.gd")
var checks = 0
var failures = 0

class MockTreasures:
	var source
	var enabled = true
	func _init(value): source = weakref(value)
	func has(id): return enabled and id == "decoy_tally"
	func generate_move(id):
		var owner = source.get_ref()
		owner.hand.append(id);owner.hand_ids.append(owner.next_card_uid);owner.next_card_uid += 1
	func trigger(value, _feedback = "draw", _label = "", _id = ""): source.get_ref().logs.append(value)
class MockGame:
	var enemies = []
	var player = Vector2i(4, 5)
	var effects = []
	var logs = []
	var hand = []
	var hand_ids = []
	var next_card_uid = 1
	var next_enemy_uid = 1
	var treasure_battle = {}
	var turn = 1
	var lives = 3
	var treasures
	func _init(): treasures = MockTreasures.new(self)
	func cell_pos(pos): return Vector2(pos) * 48.0
	func add_enemy(kind, pos, cd):
		enemies.append({"uid":next_enemy_uid,"kind":kind,"pos":pos,"cd":cd,"period":cd,"stun":0,"hp":1,"max_hp":1,"visual":cell_pos(pos)})
		next_enemy_uid += 1
	func effect(kind, from, to, duration = 0.3, delay = 0.0, extra = {}):
		var value = {"kind":kind,"from":from,"to":to,"duration":duration,"delay":delay}
		value.merge(extra);effects.append(value)
	func move_piece(piece, from, to, delay = 0.0, arc = false): effect("move",from,to,0.28,delay,{"piece":piece,"arc":arc})
	func piece_name(kind): return kind
	func log_line(value): logs.append(value)

func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error("DECOY/CAVALRY: " + label)
func piece(uid: int, kind: String, x: int, y: int, role: String = "") -> Dictionary:
	var value = {"uid":uid,"kind":kind,"pos":Vector2i(x,y),"stun":0,"hp":2,"max_hp":2,"cd":1,"period":3}
	if not role.is_empty(): CAV.configure(value, role)
	return value
func run():
	geometry_checks()
	placement_generation_checks()
	attack_checks()
	cavalry_checks()
	planning_checks()
	print("DECOY CAVALRY RESULT %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func geometry_checks():
	var decoy = piece(2,"decoy",2,4)
	var rook = piece(1,"r",0,4)
	var cannon = piece(1,"c",0,4)
	check(not R.attacks(rook,Vector2i(4,4),[rook,decoy]), "decoy blocks an enemy rook ray")
	check(R.attacks(cannon,Vector2i(4,4),[cannon,decoy]), "decoy supplies exactly one enemy cannon screen")
	check(R.blockers(Vector2i(4,4),Vector2i(0,4),[cannon,decoy]) == 1, "the same body supplies a player cannon screen")
	var horse = piece(1,"h",1,1);var leg = piece(2,"decoy",2,1)
	check(not R.attacks(horse,Vector2i(3,2),[horse,leg]), "decoy blocks horse leg")
	var elephant = piece(1,"e",0,0);var eye = piece(2,"decoy",1,1)
	check(not R.attacks(elephant,Vector2i(2,2),[elephant,eye]), "decoy blocks elephant eye")
	check(R.moves(decoy,[decoy],Vector2i(4,5)).is_empty(), "neutral decoy has no legal movements")
	for y in 10:
		for x in 9: check(not R.attacks(decoy,Vector2i(x,y),[decoy]), "neutral decoy cannot attack")
	check(decoy.pos not in R.moves(rook,[rook,decoy],Vector2i(8,9)), "ordinary rook moves cannot land on occupied decoy")
	check(R.captures_object(rook,decoy.pos,[rook,decoy],Vector2i(8,9)), "clear rook capture remains legal")
	check(not R.captures_object(rook,decoy.pos,[rook,decoy],Vector2i(1,4)), "player body blocks rook capture toward decoy")
	check(not R.captures_object(cannon,decoy.pos,[cannon,decoy],Vector2i(8,9)), "zero-screen cannon cannot capture decoy")
	check(R.captures_object(cannon,decoy.pos,[cannon,decoy],Vector2i(1,4)), "player is a legal single cannon screen")
	var screen = piece(3,"stake",1,4)
	check(R.captures_object(cannon,decoy.pos,[cannon,screen,decoy],Vector2i(8,9)), "one-screen cannon captures decoy")
	decoy.pos = Vector2i(4,4)
	check(not R.captures_object(cannon,decoy.pos,[cannon,screen,decoy],Vector2i(3,4)), "two-screen cannon cannot capture decoy")

func placement_generation_checks():
	var game = MockGame.new();var system = D.new(game)
	check(not system.can_place(game.player), "cannot place beneath player")
	check(system.can_place(Vector2i(2,3)) and system.can_place(Vector2i(6,7)), "5x5 includes both diagonal radius-two corners")
	check(not system.can_place(Vector2i(1,5)), "placement cannot exceed radius two")
	game.add_enemy("p",Vector2i(3,4),99)
	check(not system.can_place(Vector2i(3,4)), "occupied placement is rejected")
	check(system.place(Vector2i(6,7)), "empty radius-two placement succeeds")
	var decoy = D.find(game.enemies)
	check(decoy.kind == "decoy" and decoy.hp == 2 and decoy.max_hp == 2 and not decoy.has("ttl"), "decoy starts at two HP and has no expiry")
	check(not system.place(Vector2i(2,3)), "one board decoy maximum")
	check(system.start_turn() and game.hand == ["decoy_card"], "turn one generates even while board decoy exists")
	check(not system.start_turn() and game.hand.size() == 1, "turn-start hook is idempotent")
	game.hand.clear();game.hand_ids.clear()
	for turn in [2,3]:
		game.turn = turn;check(not system.start_turn(), "intervening turn does not generate")
	game.turn = 4;check(system.on_turn_start() and game.hand_ids == [2], "turn four generates a fresh stable hand UID")
	game.turn = 7;check(not system.start_turn() and game.hand.size() == 1, "holding card suppresses turn-seven duplicate")
	game.hand.clear();game.hand_ids.clear()
	check(not system.start_turn(), "discarding later in generation turn does not regenerate")
	game.turn = 10;check(system.start_turn(), "turn ten resumes schedule")
	game.player = Vector2i(0,0);game.enemies.clear()
	check(system.can_place(Vector2i(2,2)) and not system.can_place(Vector2i(-1,0)), "edge placement clips to real board")
	game.treasures.enabled = false;game.turn = 13;game.hand.clear()
	check(not system.start_turn(), "no treasure means no generated card")

func attack_checks():
	var game = MockGame.new();game.player = Vector2i(8,9)
	var system = D.new(game)
	game.add_enemy("p",Vector2i(4,4),1);var first = game.enemies.back()
	game.add_enemy("h",Vector2i(2,4),1);var second = game.enemies.back()
	game.add_enemy("r",Vector2i(8,5),1);var third = game.enemies.back()
	game.add_enemy("decoy",Vector2i(4,5),0);var decoy = game.enemies.back();decoy.hp=2
	var result = system.attack(first,0.0)
	check(result.consumed and not result.moved and decoy.hp == 1 and first.pos == Vector2i(4,4), "surviving first hit consumes attack without movement")
	check(game.lives == 3 and game.effects.filter(func(fx): return fx.kind == "enemy_impact").size() == 1, "decoy damage is separate and shows one bump-return")
	var impact = game.effects.back()
	check(impact.target_cell == Vector2i(4,5) and impact.decoy_target, "bump effect targets decoy, not player")
	var unchanged = system.attack(first,result.timeline)
	check(unchanged.consumed and decoy.hp == 1 and unchanged.timeline == result.timeline, "same actor cannot attack a second time in phase")
	result = system.attack(second,result.timeline)
	check(result.consumed and result.moved and result.destroyed and second.pos == Vector2i(4,5), "destroying horse legally captures into former decoy square")
	check(D.find(game.enemies).is_empty() and game.enemies.size() == 3, "destroyed neutral object removed without affecting other pieces")
	check(game.effects.filter(func(fx): return fx.kind == "move").size() == 1, "capture creates exactly one movement")
	check(not system.attack(third,result.timeline).consumed, "later attacker reselects after decoy disappears")
	for kind in ["a","e","g"]:
		check(not D.is_offensive(piece(1,kind,4,0)), "defensive role does not chase bait")
	check(not D.is_offensive(piece(1,"h",4,0,"guard_horse")), "guard horse does not chase bait")
	for kind in ["p","q","h","r","c"]:
		check(D.is_offensive(piece(1,kind,4,0)), "offensive identity accepts bait priority")
	game = MockGame.new();system = D.new(game);game.player=Vector2i(8,9)
	game.add_enemy("h",Vector2i(2,4),1);var horse = game.enemies.back()
	game.add_enemy("stake",Vector2i(3,4),0)
	game.add_enemy("decoy",Vector2i(4,5),0);game.enemies.back().hp=1
	check(not system.attack(horse,0.0).consumed and horse.pos == Vector2i(2,4), "blocked horse never performs an illegal decoy capture")
	game.enemies.remove_at(1);horse.stun=1
	check(not system.attack(horse,0.0).consumed, "stunned attacker cannot damage decoy")
	game = MockGame.new();system = D.new(game);game.player=Vector2i(8,9)
	game.add_enemy("c",Vector2i(0,4),1);var cannon = game.enemies.back()
	game.add_enemy("decoy",Vector2i(4,4),0);game.enemies.back().hp=1
	check(not system.attack(cannon,0.0).consumed, "zero-screen cannon does not receive an illegal capture")
	game.add_enemy("stake",Vector2i(2,4),0)
	check(system.attack(cannon,0.0).moved and cannon.pos == Vector2i(4,4), "single-screen cannon capture lands legally")

func cavalry_checks():
	var player = Vector2i(4,7)
	for identity in CAV.ROLES:
		var horse = piece(1,"h",4,4,identity)
		check(horse.kind == "h" and horse.hp == 2 and horse.max_hp == 2, identity + " uses standard horse identity and two HP")
		for blocker in [Vector2i(4,3),Vector2i(5,4),Vector2i(4,5),Vector2i(3,4)]:
			var board = [horse,piece(2,"decoy",blocker.x,blocker.y)]
			var normal = horse.duplicate();normal.erase("ai_role")
			check(R.moves(horse,board,player) == R.moves(normal,board,player), identity + " retains exact horse movement under leg blocking")
			for y in 10:
				for x in 9: check(R.attacks(horse,Vector2i(x,y),board) == R.attacks(normal,Vector2i(x,y),board), identity + " retains exact horse attack geometry")
	var guard = piece(1,"h",3,2,"guard_horse")
	var board = [guard,piece(2,"g",4,0),piece(3,"a",3,0),piece(4,"decoy",3,5)]
	var original = board.duplicate(true)
	var options = R.moves(guard,board,Vector2i(4,8))
	var chosen = CAV.choose(guard,options,board,Vector2i(4,8))
	check(chosen == guard.pos or chosen in options, "guard chooses only legal move or qualified hold")
	check((chosen - Vector2i(4,0)).length_squared() <= 13, "guard remains anchored near general despite distant bait/player")
	var without_decoy = board.duplicate();without_decoy.pop_back()
	check(chosen == CAV.choose(guard,R.moves(guard,without_decoy,Vector2i(4,8)),without_decoy,Vector2i(4,8)), "irrelevant bait cannot lure guard away from post")
	check(board == original, "cavalry evaluation does not mutate board")
	var threatened = [piece(1,"g",4,0),piece(2,"h",3,2,"guard_horse")]
	check(GE.profile(threatened[0],threatened,Vector2i(4,1),{}).unsafe, "guard presence does not grant general invulnerability")
	var scout = piece(1,"h",4,4,"outrider")
	board = [scout,piece(2,"g",4,0)]
	options = R.moves(scout,board,Vector2i(4,7))
	var a = CAV.choose(scout,options,board,Vector2i(4,7),{"hand":["spear"],"future_player":Vector2i(0,0)})
	var b = CAV.choose(scout,options,board,Vector2i(4,7),{"hand":["life"],"future_player":Vector2i(8,9)})
	check(a == b, "outrider ignores hidden cards and future input hints")
	var trial = CAV.placed(scout,a,board);var moved=scout.duplicate();moved.pos=a
	var fresh_score = CAV.outrider_score(moved,trial,Vector2i(4,7))
	var duplicate = moved.duplicate();duplicate.uid=99
	check(fresh_score > CAV.outrider_score(moved,trial + [duplicate],Vector2i(4,7)), "fresh escape coverage outranks duplicate friendly control")
	guard.stun=1
	check(CAV.choose(guard,options,board,player) == CAV.NONE, "stunned cavalry never receives free role action")

func planning_checks():
	var random = RandomNumberGenerator.new();random.seed=7021
	var player=Vector2i(8,9)
	for kind in ["p","q","h","r","c"]:
		var actor=piece(1,kind,2,5);var decoy=piece(2,"decoy",5,5)
		var board=[actor,decoy,piece(3,"stake",4,4)]
		var before=board.duplicate(true);var state=random.state
		var options=R.moves(actor,board,player)
		var target=AI.choose(actor,options,board,player,random)
		check(target == actor.pos or target in options, kind + " bait planner never invents a move")
		check(target != decoy.pos, kind + " movement planner never lands on uncaptured decoy")
		check(board == before and random.state == state, kind + " bait planning is read-only and uses no RNG")
		var plan=AI.plan(board,player,{actor.uid:true})
		check(actor.uid in plan.order and not plan.targets.has(actor.uid), kind + " bait choice cannot be overwritten by joint cannon plans")
	var standard=[piece(1,"p",0,0),piece(2,"g",4,0)]
	check(AI.plan(standard,player,{1:true,2:true}) == CP.plan(standard,player,{1:true,2:true}), "standard army without bait keeps original planner result")
	for identity in CAV.ROLES:
		var actor=piece(1,"h",3,2,identity)
		var board=[actor,piece(2,"g",4,0),piece(3,"c",0,3)]
		var plan=AI.plan(board,player,{1:true,2:true,3:true})
		check(1 in plan.order and not plan.targets.has(1), identity + " role remains reserved under cannon coordination")
		var state=random.state
		AI.choose(actor,R.moves(actor,board,player),board,player,random)
		check(random.state==state, identity + " role does not sample RNG")
