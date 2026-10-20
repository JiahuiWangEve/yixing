extends SceneTree
const R = preload("res://rules.gd")
var passed := 0
var failed := 0
var game: Control

func check(ok: bool, label: String):
 if ok:
  passed += 1
  print("PASS ", label)
 else:
  failed += 1
  push_error("FAIL " + label)

func enemy(kind: String, p: Vector2i, cd: int = 5, stun: int = 0) -> Dictionary:
 return {"kind": kind, "pos": p, "cd": cd, "period": cd, "stun": stun}

func reset_game():
 game.new_run()
 game.enemies = [enemy("g", Vector2i(4,0), 5)]
 game.deck = ["sword", "horse", "spear"]
 game.discard = []
 game.hand = []

func click_at(p: Vector2, button: int = MOUSE_BUTTON_LEFT):
 # Synthetic clicks model deliberate input after the brief animation lock.
 game._process(0.5)
 var event = InputEventMouseButton.new()
 event.position = p
 event.button_index = button
 event.pressed = true
 game._gui_input(event)

func board_click(p: Vector2i):
 click_at(game.cell_pos(p))

func _initialize():
 call_deferred("run_checks")

func run_checks():
 game = load("res://main.tscn").instantiate()
 root.add_child(game)
 game.set_process(false)
 # Geometry checks supplement the builder's original suite.
 var horse = enemy("h", Vector2i(4,4))
 check(R.attacks(horse, Vector2i(5,6), [horse]), "horse vertical major axis clear")
 check(not R.attacks(horse, Vector2i(5,6), [horse, enemy("p", Vector2i(4,5))]), "horse vertical leg blocks")
 var elephant = enemy("e", Vector2i(4,4))
 check(not R.attacks(elephant, Vector2i(6,6), [elephant]), "elephant cannot cross river")
 var general = enemy("g", Vector2i(3,2))
 check(not R.attacks(general, Vector2i(2,2), [general]), "general cannot exit palace sideways")
 check(not R.attacks(general, Vector2i(3,3), [general]), "general cannot exit palace forwards")
 var rook = enemy("r", Vector2i(4,0))
 check(not R.moves(rook, [rook], Vector2i(4,3)).has(Vector2i(4,4)), "rook movement cannot pass through player")
 var cannon = enemy("c", Vector2i(4,0))
 check(not R.moves(cannon, [cannon], Vector2i(4,3)).has(Vector2i(4,4)), "cannon movement cannot pass through player")
 # Attacks happen despite high movement cooldown; attacker stays; damage has no draw.
 reset_game()
 game.player = Vector2i(4,6)
 game.enemies = [enemy("p", Vector2i(4,5),1), enemy("g",Vector2i(4,0),5)]
 var attacking_piece: Dictionary = game.enemies[0]
 game.end_turn()
 check(game.lives == 2, "ready attacker causes one life loss")
 check(attacking_piece.pos == Vector2i(4,5), "attacker remains on original square after hit")
 check(game.hand.is_empty() and game.deck.size() == 3, "hit and recoil do not draw")
 check(R.occupied(game.player,game.enemies) < 0 and not R.threatened(game.player,game.enemies), "recoil is empty and globally safe")
 check(absi(game.player.x-4)+absi(game.player.y-6) == 1, "recoil uses nearest safe distance")
 reset_game()
 game.player = Vector2i(2,4)
 game.enemies = [enemy("p",Vector2i(2,3),9), enemy("g",Vector2i(4,0),9)]
 game.end_turn()
 check(game.lives == 2, "cooldown nine still permits attack")
 check(game.enemies[0].pos == Vector2i(2,3), "high cooldown attacker also stays")
 # An early mover unblocks a later rook; no same-phase attack may follow.
 reset_game()
 game.player = Vector2i(4,8)
 game.enemies = [enemy("h",Vector2i(4,4),1),enemy("r",Vector2i(4,0),5)]
 game.enemies[0].intent = Vector2i(2,5)
 game.end_turn()
 check(game.lives == 3, "global attack pass precedes all movement")
 check(game.enemies[0].pos.x != 4, "blocking horse actually moved off rook file")
 check(R.threatened(game.player,game.enemies), "newly exposed rook threatens only next phase")
 reset_game()
 game.player = Vector2i(4,8)
 game.enemies = [enemy("p",Vector2i(4,6),1),enemy("g",Vector2i(4,0),5)]
 game.enemies[0].intent = Vector2i(4,7)
 game.end_turn()
 check(game.enemies[0].pos == Vector2i(4,7) and game.lives == 3, "newly adjacent moved pawn never attacks same phase")
 # Stun must prevent both movement and attacking once, then naturally expire.
 reset_game()
 game.player = Vector2i(2,4)
 game.enemies = [enemy("p",Vector2i(2,3),1,1),enemy("g",Vector2i(4,0),5)]
 game.end_turn()
 check(game.lives == 3 and game.enemies[0].pos == Vector2i(2,3), "stun one skips attack and movement")
 check(game.enemies[0].stun == 0, "stun one expires exactly after skipped phase")
 game.end_turn()
 check(game.lives == 2, "expired stun permits next phase attack")
 # Starting state, active moves, per-turn budgets, and no end-turn draw.
 game.new_run()
 check(game.stage == 1 and game.hand.is_empty() and game.deck.size() == 8 and game.energy == 3, "new run starts stage one empty hand three energy")
 board_click(Vector2i(4,8))
 check(game.player == Vector2i(4,8) and game.hand.size() == 1 and game.energy == 3, "basic move draws immediately and costs zero energy")
 board_click(Vector2i(4,7))
 check(game.player == Vector2i(4,8) and game.hand.size() == 1, "second basic move is blocked")
 game.end_turn()
 check(game.hand.size() == 1 and game.energy == 3 and not game.basic_used and not game.card_move_used, "new turn resets budgets but does not draw")
 reset_game()
 game.hand = ["horse", "horse"]
 game.energy = 3
 game.play_card(0,Vector2i(5,7))
 check(game.player == Vector2i(5,7) and game.card_move_used and game.energy == 2 and game.hand.size() == 2, "movement card consumes energy and draws immediately")
 check(not game.card_legal("horse",Vector2i(4,5)), "second movement card disallowed in turn")
 # Real GUI cancel / invalid-target behavior.
 reset_game()
 game.hand = ["sword"]
 click_at(Vector2(80,750))
 check(game.selected == 0, "card click selects card")
 board_click(Vector2i(0,0))
 check(game.hand.size() == 1 and game.energy == 3 and game.selected == 0, "invalid target costs no card or energy")
 click_at(Vector2(80,750),MOUSE_BUTTON_RIGHT)
 check(game.selected == -1 and game.hand.size() == 1 and game.energy == 3, "right-click cancellation costs nothing")
 click_at(Vector2(80,750))
 var escape = InputEventKey.new()
 escape.pressed = true
 escape.keycode = KEY_ESCAPE
 game._input(escape)
 check(game.selected == -1 and game.energy == 3, "escape cancellation costs nothing")
 # Overflow blocks gameplay until selected discard.
 reset_game()
 game.hand = ["sword","sword","sword","sword","sword","sword"]
 board_click(Vector2i(4,8))
 check(game.hand.size() == 7 and game.phase == "discard", "seventh card enters forced selected discard")
 check(game.hand_rect(6).end.x <= 1280, "all seven overflow cards fit viewport")
 var prior_turn: int = game.turn
 click_at(game.END_TURN_RECT.get_center())
 check(game.turn == prior_turn and game.phase == "discard", "overflow cannot be bypassed by ending turn")
 game.energy = 0
 click_at(Vector2(80,750))
 check(game.hand.size() == 6 and game.discard.size() == 1 and game.phase == "play" and game.energy == 0, "discard choice costs no energy and returns to play")
 # Kill general transitions immediately, while other enemies survive.
 reset_game()
 game.player = Vector2i(4,1)
 game.enemies.append(enemy("p",Vector2i(7,6)))
 game.hand = ["sword"]
 game.play_card(0,Vector2i(4,0))
 check(game.phase == "reward" and game.enemies.size() == 1 and game.lives == 3, "general death grants immediate reward without cleanup combat")
 check(game.rewards.size() == 3, "reward offers three choices")
 var before_collection: int = game.collection.size()
 var chosen: String = game.rewards[0]
 click_at(Vector2(250,350))
 check(game.stage == 2 and game.phase == "play" and game.collection.size() == before_collection+1 and game.collection.has(chosen), "reward selection adds card and starts next stage")
 check(game.hand.is_empty() and game.deck.size() == game.collection.size() and game.energy == 3, "next stage reshuffles collection and starts with zero hand")
 game.player = Vector2i(4,1)
 game.hand = ["sword"]
 game.play_card(0,Vector2i(4,0))
 click_at(Vector2(600,550))
 check(game.stage == 3 and game.collection.size() == before_collection+1, "reward skip starts third stage without adding card")
 game.player = Vector2i(4,1)
 game.hand = ["sword"]
 game.play_card(0,Vector2i(4,0))
 check(game.phase == "win" and game.stage == 3, "third general death immediately wins run")
 var old_player: Vector2i = game.player
 board_click(Vector2i(4,2))
 check(game.player == old_player, "win overlay blocks gameplay")
 click_at(game.RESTART_RECT.get_center())
 check(game.phase == "play" and game.stage == 1 and game.lives == 3 and game.collection.size() == 8, "restart resets completed run")
 # Exhaust and cap behavior.
 reset_game()
 game.hand = ["life"]
 game.lives = 5
 game.play_card(0,game.player)
 check(game.hand.size() == 1 and game.energy == 3, "life at cap preserves card and energy")
 game.lives = 4
 game.play_card(0,game.player)
 check(game.lives == 5 and game.hand.is_empty() and game.discard.is_empty() and game.energy == 1, "life heals one and exhausts from current-stage piles")
 # Recoil tie-breaking, complete-board safety, and death edges.
 var seen_recoil: Dictionary = {}
 var recoil_fixture = [enemy("p",Vector2i(4,5),5),enemy("g",Vector2i(4,0),5)]
 var expected_recoil: Array = R.safe_recoil(Vector2i(4,6),recoil_fixture)
 check(expected_recoil.size() >= 2, "nearest-safe recoil fixture contains tied destinations")
 for random_seed in range(1,25):
  reset_game()
  game.rng.seed = random_seed
  game.player = Vector2i(4,6)
  game.enemies = recoil_fixture.duplicate(true)
  game.end_turn()
  seen_recoil[game.player] = true
  check(expected_recoil.has(game.player), "random recoil stays within nearest-safe tie set " + str(random_seed))
 check(seen_recoil.size() >= 2, "recoil random tie-break reaches multiple tied destinations")
 reset_game()
 game.player = Vector2i(4,6)
 game.enemies = []
 for y in range(10):
  game.enemies.append(enemy("r",Vector2i(0,y),5))
 check(R.safe_recoil(game.player,game.enemies).is_empty(), "fully threatened board has no safe recoil destination")
 game.end_turn()
 check(game.phase == "dead" and game.lives == 2, "no safe recoil ends run after life loss")
 reset_game()
 game.player = Vector2i(4,6)
 game.lives = 1
 game.enemies = [enemy("p",Vector2i(4,5),1),enemy("g",Vector2i(4,0),5)]
 game.end_turn()
 check(game.phase == "dead" and game.lives == 0 and game.player == Vector2i(4,6), "last life ends run immediately without recoil")
 # Committed destinations must remain legal after player actions.
 reset_game()
 game.player = Vector2i(2,4)
 game.enemies = [enemy("p",Vector2i(2,3),1),enemy("g",Vector2i(4,0),5)]
 game.enemies[0].intent = Vector2i(2,4)
 game.hand = ["push"]
 game.play_card(0,Vector2i(2,3))
 check(game.enemies[0].pos == Vector2i(2,2), "push moves adjacent target one square away")
 game.end_turn()
 check(game.lives == 3 and game.enemies[0].pos == Vector2i(2,2), "push invalidates stale two-step pawn intent")
 reset_game()
 game.player = Vector2i(4,8)
 game.enemies = [enemy("p",Vector2i(3,7),1),enemy("g",Vector2i(4,0),5)]
 game.enemies[0].intent = Vector2i(4,7)
 board_click(Vector2i(4,7))
 game.end_turn()
 check(game.enemies[0].pos != game.player, "committed movement never overlaps player destination")
 # All overflow choices, including newly drawn seventh, remain selectable.
 reset_game()
 game.hand = ["sword","sword","sword","sword","sword","sword"]
 game.deck = ["horse"]
 board_click(Vector2i(4,8))
 click_at(game.hand_rect(6).get_center())
 check(game.hand.size() == 6 and not game.hand.has("horse") and game.discard.has("horse"), "player can explicitly discard newly drawn seventh card")
 # Empty-deck refill and full deck exhaustion should not block legal movement.
 reset_game()
 game.deck = []
 game.discard = ["sword"]
 board_click(Vector2i(4,8))
 check(game.hand == ["sword"] and game.discard.is_empty(), "active move reshuffles discard when draw pile empty")
 reset_game()
 game.deck = []
 game.discard = []
 board_click(Vector2i(4,8))
 check(game.player == Vector2i(4,8) and game.basic_used and game.hand.is_empty(), "empty card supply still permits legal active move")
 print("INDEPENDENT QA: ",passed," passed, ",failed," failed")
 game.queue_free()
 quit(1 if failed else 0)
