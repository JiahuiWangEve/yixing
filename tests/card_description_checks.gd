extends SceneTree
# Run with disposable user:// storage. This module is tested directly so the
# presentation integration cannot hide a static-versus-battle context mistake.
const DESCRIPTIONS = preload("res://card_description.gd")
const CATALOG = preload("res://card_catalog.gd")
var game
var descriptions
var checks = 0
var failures = 0

func _initialize(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if not value: failures += 1;push_error("CARD DESCRIPTION: " + label)
func text(id: String, battle: bool = false, full: bool = false) -> String:
	return str(descriptions.data(id, battle)[4 if full else 2])
func snapshot() -> Dictionary:
	return {"battle": game.history.capture(), "route": game.route.state.duplicate(true),
		"rng": game.rng.state, "screen": game.screen, "undo": game.normal_undos_remaining,
		"logs": game.logs.duplicate(true), "effects": game.effects.duplicate(true),
		"cards": game.CARDS.duplicate(true), "history": game.history.entries.duplicate(true)}
func settle():
	game.clear_effects();game.presentation.clear();game.input_lock = 0;game.navigation_lock = 0
func add(kind: String, pos: Vector2i, hp: int = 20) -> Dictionary:
	game.add_enemy(kind, pos, 999)
	var enemy: Dictionary = game.enemies.back();enemy.hp = hp;enemy.max_hp = hp
	return enemy
func fresh(treasure: String = "", cards: Array = [], lives: int = 4):
	game.player_skill = game.TREASURES.DATA[treasure].role if not treasure.is_empty() else "king"
	if treasure.is_empty(): game.new_run()
	else:
		game.new_expedition();game.route.enter(0);game.route.state.treasure_id = treasure
		game.treasures.reset_battle()
	game.enemies = [];add("g", Vector2i(8, 0), 99)
	game.player = Vector2i(4, 5);game.lives = lives;game.energy = 20
	game.hand = cards.duplicate();game.hand_ids = [];game.deck = [];game.discard = []
	game.phase = "play";game.screen = "game";game.active_displacements = 0
	game.basic_used = false;game.card_move_used = false;game.history.clear();game.sync_hand_views();settle()
func play(id: String, target: Vector2i):
	settle();game.play_card(game.hand.find(id), target)
func arm_tassel():
	game.active_displacements = 2
	game.treasure_battle.tassel_triggered = true;game.treasure_battle.tassel_ready = true

func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	descriptions = DESCRIPTIONS.new(game)
	check_all_identities()
	check_static_context()
	check_attack_shapes()
	check_move_and_utility_rules()
	check_dynamic_damage()
	check_cannon()
	check_lives()
	check_consumable_copies()
	check_text_layout()
	print("CARD DESCRIPTION RESULT ", checks - failures, " passed, ", failures, " failed")
	game.free();quit(1 if failures else 0)

func check_all_identities():
	fresh()
	var before = snapshot()
	for id in game.CARDS:
		for battle in [false, true]:
			var actual: Array = descriptions.data(id, battle)
			check(actual.size() >= 5 and not str(actual[2]).is_empty() and not str(actual[4]).is_empty(), id + " has both normalized descriptions")
			check(actual[0] == game.CARDS[id][0] and actual[3] == game.CARDS[id][3], id + " retains canonical identity/type")
			check(actual[1] == (game.card_cost(id) if battle else game.CARDS[id][1]), id + " uses correct fee context")
			check(not str(actual[2]).contains("消耗"), id + " leaves consumable label to badge")
			for obsolete in ["本关移除", "本场移除", "下关恢复", "下场恢复", "本关消耗"]:
				check(not str(actual[4]).contains(obsolete), id + " removes obsolete redundant wording " + obsolete)
			var expected_rule_count = 1 if id in game.CONSUMABLES else 0
			check(str(actual[4]).count(DESCRIPTIONS.CONSUMABLE_RULE) == expected_rule_count, id + " has consumable rule exactly when needed")
			actual[0] = "修改返回副本";actual[2] = "修改返回副本"
			check(game.CARDS[id][0] != actual[0] and descriptions.data(id, battle)[2] != actual[2], id + " returns independent copy")
	for id in DESCRIPTIONS.FREE_IDENTITIES:
		var spec: Array = DESCRIPTIONS.FREE_IDENTITIES[id]
		var canonical: Array = game.FREE_MOVE.data_for(spec[0], spec[1])
		var actual: Array = descriptions.data(id)
		check(actual.size() == 5 and actual[0] == canonical[0] and actual[1] == 0 and actual[3] == "移", id + " derives correct canonical free identity")
		check(str(actual[2]).contains("空格") and str(actual[2]).contains("抽1张") and str(actual[2]).contains("每回合1次"), id + " has normalized movement/empty/draw/limit")
		check(descriptions.data(id, true) == actual, id + " does not inherit unrelated current role")
	check(descriptions.data("not_a_card").is_empty(), "unknown ID has no fabricated card")
	check(snapshot() == before, "all description calls leave gameplay/treasure/deck/route/RNG/history/constants untouched")
	for group in CATALOG.GROUPS:
		for entry in CATALOG.entries_for(group.id, game.CARDS):
			check(entry.id != "cannon", "historic cannon remains absent from catalog")
			check(not descriptions.data(entry.id).is_empty(), "all available catalog identities supported " + entry.id)

func check_static_context():
	fresh()
	var generic: Dictionary = {}
	for id in game.CARDS: generic[id] = descriptions.data(id)
	for treasure in ["battle_tassel", "gate_cannon_seal", "longevity_seal", "life_talisman"]:
		fresh(treasure, [], 1)
		game.active_displacements = 7;game.artillery_mode = "attack";game.reload_ready = true;game.deploy_draw_used = true
		game.treasure_battle.tassel_ready = true;game.treasure_battle.tassel_triggered = true
		game.treasure_battle.gate_ready = true;game.treasure_battle.gate_spent = false
		var before = snapshot()
		for id in game.CARDS:
			check(descriptions.data(id) == generic[id], "%s cannot leak into static %s" % [treasure, id])
			check(not text(id).contains("当前"), id + " static short has no arbitrary current amount")
		check(snapshot() == before, "static reads do not mutate " + treasure)
	check(text("cannon_shot").contains("行军1/攻击2") and text("cannon_shot", false, true).contains("行军姿态2费、伤害1") and text("cannon_shot", false, true).contains("攻击姿态1费、伤害2"), "generic cannon describes both complete alternatives")
	check(descriptions.data("cannon_shot")[1] == 2, "generic cannon retains base-cost badge")
	check(text("life").contains("上限5") and not text("life").contains("无上限"), "generic healing has baseline cap")
	check(text("chain_assault").contains("本回合主动位移次数+1") and not text("chain_assault").contains("当前"), "generic chain keeps formula without current0")
	check(text("last_stand").contains("伤害1，仅1命时3"), "generic last stand shows both life conditions")

func check_attack_shapes():
	fresh()
	for id in game.CARDS:
		if game.CARDS[id][3] != "攻": continue
		var short_text = text(id);var full_text = text(id, false, true)
		var expected = "命−1；群体；" if id in ["blood_edge", "blood_break", "airdrop"] else ("群体；" if id == "sweep" else "单体；")
		check(short_text.begins_with(expected) and full_text.begins_with(expected), id + " has selfcost/type/range/damage ordering")
		check(short_text.find("伤害") > short_text.find("；"), id + " names damage after attack type/range")
	check(text("blood_edge").contains("单一正交方向1–3格") and text("blood_edge").contains("贯穿"), "blood edge is one direction, three cells, piercing")
	check(text("blood_break").contains("四正交各1–2格") and text("blood_break").contains("不含斜角"), "blood break is four orthogonal rays, not diagonal radius")
	check(text("chain_assault").begins_with("单体；自身3×3范围"), "chain is single target in 3x3")
	check(text("airdrop").contains("落点3×3范围") and text("airdrop").contains("其他空格") and text("airdrop").contains("下回合停行动"), "airdrop location, other-empty landing and recovery explicit")
	check(text("airdrop", false, true).contains("当前回合可继续") and text("airdrop", false, true).contains("敌方与被动照常"), "airdrop recovery timing complete")
	check(text("pierce").contains("伤害1×2") and text("pierce", false, true).contains("下一玩家回合结束时") and text("pierce", false, true).contains("不立即造成伤害"), "bleed timing is delayed twice, not immediate two damage")
	check(text("shock").contains("3×3范围或正交2格") and text("shock", false, true).contains("推不动仍造成伤害"), "shock range and blocked push accurate")
	check(text("retreat_strike", false, true).contains("先向目标反方向退1格，再攻击原目标"), "retreat occurs before attack")
	check(text("knight_assault").contains("马步攻击") and text("knight_assault").contains("遵守蹩腿"), "knight attack has leg condition")

func check_move_and_utility_rules():
	fresh()
	check(text("horse").contains("马步移动至空格") and text("horse").contains("蹩马腿") and text("horse").contains("抽1张"), "horse movement states landing/leg/draw")
	check(text("straight").contains("正交移动1–2格至空格") and text("straight").contains("不穿透"), "straight movement is bounded orthogonal and unblocked")
	for id in ["stake", "permanent_stake"]:
		check(text(id).contains("木桩") and text(id).contains("曼哈顿2格内空位") and text(id, false, true).contains("含斜角相邻"), id + " deployment object/location accurate")
	check(text("stake").contains("持续3回合") and text("permanent_stake").contains("持续本场"), "deployment durations distinct")
	for id in DESCRIPTIONS.TEMPORARY:
		check(text(id, false, true).contains("回合结束消失") and text(id, false, true).contains("成功使用或过牌后消失"), id + " exact temporary lifetime")
		check(not text(id, false, true).contains(DESCRIPTIONS.CONSUMABLE_RULE) and not text(id, false, true).contains("恢复"), id + " never promises next-battle restoration")
	check(text("life").begins_with("命+1"), "healing uses life notation")
	check(text("tuna", false, true).contains("下回合起") and text("tuna", false, true).contains("不叠加增量") and text("tuna", false, true).contains("疲惫扣减"), "tuna timing/stacking/fatigue precise")
	check(text("fatigue", false, true).contains("抽到时立即能量−1") and text("fatigue", false, true).contains("每个玩家回合开始") and text("fatigue", false, true).contains("多张分别触发"), "fatigue distinguishes draw and retained-turn triggers")
	check(text("guard", false, true).contains("不抵消主动命耗") and text("guard", false, true).contains("重复使用只刷新1次"), "guard states expiry and no stack/selfcost protection")
	check(text("pack", false, true).contains("不刷新已用额度"), "pack does not restore free movement")
	game.deploy_draw_used = true
	check(text("deploy", true).contains("不再抽牌") and text("deploy").contains("首次展开抽3张"), "deploy actual draw state is battle-only")

func check_dynamic_damage():
	fresh("battle_tassel", ["chain_assault"]);arm_tassel()
	var victim = add("p", Vector2i(5, 4), 20)
	var before = snapshot()
	check(text("chain_assault", true).contains("本回合主动位移次数+1+2（当前5）"), "chain includes formula plus actual treasure total")
	check(text("chain_assault", true, true).contains("踏阵长缨+2"), "chain names the bonus source")
	check(snapshot() == before, "dynamic damage inspection does not consume treasure")
	play("chain_assault", victim.pos)
	check(victim.hp == 15, "chain displayed total matches actual five damage")
	check(text("chain_assault", true).contains("当前3") and not text("chain_assault", true).contains("+1+2"), "consumed treasure immediately disappears from description")
	fresh("battle_tassel", ["sweep"]);arm_tassel()
	check(text("sweep", true).contains("伤害3（宝物+2）"), "static-base group damage includes ready treasure")
	fresh("battle_tassel", ["retreat_strike"])
	game.active_displacements = 1;victim = add("p", Vector2i(4, 4), 20)
	before = snapshot()
	check(text("retreat_strike", true).contains("退步触发宝物则+2") and not text("retreat_strike", true).contains("伤害3"), "self-triggering retreat bonus remains conditional until valid retreat")
	check(snapshot() == before, "conditional retreat inspection is read-only")
	play("retreat_strike", victim.pos)
	check(victim.hp == 17 and game.active_displacements == 2, "legal retreat triggers own actual three damage")
	fresh("battle_tassel", ["pierce"]);arm_tassel();victim = add("p", Vector2i(4, 4), 20)
	check(text("pierce", true).contains("伤害1×2") and not text("pierce", true).contains("宝物+2"), "bleed does not advertise unimplemented delayed bonus")
	check(text("pierce", true, true).contains("延迟伤害不加成"), "bleed explains consumed-but-ineffective ready bonus")
	play("pierce", victim.pos)
	check(victim.hp == 20 and not game.treasure_battle.tassel_ready, "bleed begins without immediate damage and consumes bonus")
	settle();game.end_turn();check(victim.hp == 19, "first actual delayed tick remains one damage")
	settle();game.end_turn();check(victim.hp == 18, "second actual delayed tick remains one damage")

func check_cannon():
	fresh("gate_cannon_seal", ["cannon_shot"])
	game.artillery_mode = "march";game.treasures.start_turn()
	check(descriptions.data("cannon_shot", true)[1] == 2 and text("cannon_shot", true).contains("伤害1"), "march cannon is two energy and one damage")
	game.artillery_mode = "attack";game.treasures.start_turn();game.reload_ready = true
	var before = snapshot()
	check(descriptions.data("cannon_shot", true)[1] == 0 and text("cannon_shot", true).contains("伤害3") and text("cannon_shot", true).contains("装填+1"), "battle cannon reflects stance/reload/discount")
	check(text("cannon_shot", true, true).contains("费用已计入镇关炮印−1"), "cannon discounted cost explanation accurate")
	check(snapshot() == before, "cannon inspection cannot spend discount or reload")
	add("stake", Vector2i(4, 4), 1);var victim = add("p", Vector2i(4, 3), 20)
	play("cannon_shot", victim.pos)
	check(victim.hp == 17 and game.energy == 20 and not game.reload_ready, "cannon shown fee/damage match actual outcome")
	check(descriptions.data("cannon_shot", true)[1] == 1 and text("cannon_shot", true).contains("伤害2"), "spent cannon effects vanish from next description")

func check_lives():
	fresh("longevity_seal", ["life"], 5)
	check(text("life", true).contains("命+1（无上限）") and text("life").contains("上限5"), "healing cap depends only on explicit battle context")
	play("life", game.player);check(game.lives == 6, "uncapped healing text matches actual heal")
	fresh()
	for life in [1, 2, 5]:
		game.lives = life
		check(text("last_stand", true).contains("伤害%d" % (3 if life == 1 else 1)), "last stand reads actual life %d" % life)
	for treasure in ["", "life_talisman"]:
		fresh(treasure, [], 1)
		for id in ["blood_edge", "blood_break", "airdrop"]:
			check(text(id, true).begins_with("命−1；"), id + " warning does not displace selfcost-first ordering")
			check(text(id, true).contains("当前使用即失败" if treasure.is_empty() else "金符保留1命"), id + " one-life warning reflects actual rescue")
		if not treasure.is_empty():
			game.treasure_battle.talisman_used = true
			for id in ["blood_edge", "blood_break", "airdrop"]: check(text(id, true).contains("当前使用即失败"), id + " spent talisman is not falsely protective")
	fresh("life_talisman", ["airdrop"], 1)
	play("airdrop", Vector2i(2, 5));check(game.lives == 1 and game.airdrop_recovery_turn > 0, "airdrop rescue warning matches retained life and next-turn recovery")
	fresh("", ["airdrop"], 1)
	play("airdrop", Vector2i(2, 5));check(game.phase == "dead" and game.lives == 0, "airdrop no-rescue warning matches actual defeat")

func check_consumable_copies():
	fresh("", ["life", "life"], 1)
	var ids: Array = game.hand_ids.duplicate()
	var before = snapshot();descriptions.data("life", true);descriptions.data("life")
	check(snapshot() == before, "viewing duplicate consumables preserves both physical IDs")
	play("life", game.player)
	check(game.hand == ["life"] and game.hand_ids == [ids[1]], "one consumable use leaves second physical copy intact")
	play("life", game.player)
	check(game.hand.is_empty() and game.lives == 3 and not game.discard.has("life"), "both physical consumable copies remain separately usable once")

func check_text_layout():
	for size in [Vector2(1280, 940), Vector2(390, 844), Vector2(844, 390), Vector2(360, 640)]:
		fresh();game.configure_layout(size)
		var ids: Array = game.CARDS.keys() + DESCRIPTIONS.FREE_IDENTITIES.keys()
		for id in ids:
			for count in [1, 6]: check_card_layout(id, size, count)
		fresh("battle_tassel");game.configure_layout(size);arm_tassel()
		for id in ["chain_assault", "sweep", "retreat_strike", "pierce", "sword_plus", "spear_plus", "shock", "advance", "knight_assault", "pursuit"]:
			check_card_layout(id, size, 6)
		game.active_displacements = 1;game.treasure_battle.tassel_triggered = false;game.treasure_battle.tassel_ready = false
		check_card_layout("retreat_strike", size, 6)
		for treasure in ["gate_cannon_seal", "chain_fire_fuse"]:
			fresh(treasure);game.configure_layout(size);game.artillery_mode = "attack";game.treasures.start_turn();game.reload_ready = true
			check_card_layout("cannon_shot", size, 6)
		fresh("life_talisman", [], 1);game.configure_layout(size)
		for spent in [false, true]:
			game.treasure_battle.talisman_used = spent
			for id in ["blood_edge", "blood_break", "airdrop", "last_stand"]: check_card_layout(id, size, 6)
		fresh("longevity_seal", [], 5);game.configure_layout(size);check_card_layout("life", size, 6)
		fresh("gate_cannon_seal");game.configure_layout(size);game.deploy_draw_used = true;check_card_layout("deploy", size, 6)

func check_card_layout(id: String, size: Vector2, count: int):
	game.hand = [id if game.CARDS.has(id) else "sword"]
	if count > 1: game.hand.append_array(["sword", "horse", "diagonal", "life", "stake"])
	game.hand_ids = [];game.sync_hand_ids()
	game.selected = 0;game.handui.reset();game.handui.sync()
	for tick in 20: game.handui.tick(0.05)
	var transform = game.handui.card_transform(0)
	var dimensions = Vector2(transform.x.length(), transform.y.length()) * game.handui.card_size()
	for focused in [false, true]:
		var layout = game.handui.face.text_layout(descriptions.data(id, true), dimensions, focused, game.is_consumable(id))
		var last_baseline = float(layout.start_y) + maxf(0, layout.lines.size() - 1) * float(layout.line_height)
		if not bool(layout.complete): print("DESCRIPTION TEXT OVERFLOW ", id, " viewport=", size, " hand=", count, " focused=", focused, " card=", dimensions, " font=", layout.font_size, " lines=", layout.lines.size(), "/", layout.available_lines)
		check(bool(layout.complete) and last_baseline <= dimensions.y - 4, id + " short/full description fits card at " + str(size) + " hand=" + str(count))
