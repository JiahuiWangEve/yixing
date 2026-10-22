extends SceneTree
const E = preload("res://encounters.gd")
const C2 = preload("res://chapter_two.gd")
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1;push_error(label)
func fixture():
	game.tutorial.stop();game.player_skill = "king";game.new_run()
	game.enemies = [];game.encounter_state = {};game.player = Vector2i(4, 6)
	game.add_enemy("g", Vector2i(4, 0), 99)
	game.lives = 3;game.energy = 20;game.hand = [];game.hand_ids = [];game.deck = [];game.discard = []
	game.screen = "game";game.phase = "play";game.clear_effects();game.navigation_lock = 0
	game.player_visual = game.cell_pos(game.player);game.history.clear();game.presentation.clear();game.card_picker.close()
func add(kind: String, p: Vector2i, hp: int) -> Dictionary:
	game.add_enemy(kind, p, 3)
	game.enemies.back().hp = hp;game.enemies.back().max_hp = hp
	return game.enemies.back()
func actor(uid: int) -> Dictionary:
	for enemy in game.enemies:
		if enemy.uid == uid: return enemy
	return {}
func pack() -> Dictionary:
	return {"history": game.history.capture(), "effects": game.effects.duplicate(true), "selected": game.selected, "input_lock": game.input_lock, "history_entries": game.history.entries.duplicate(true), "route": game.route.state.duplicate(true)}
func check_statuses():
	fixture()
	var enemy = add("p", Vector2i(4, 5), 1)
	check(game.board_info.hp_segments(enemy).is_empty(), "one HP has no health bar")
	for max_hp in [2, 3, 4, 6, 9]:
		enemy.hp = max_hp;enemy.max_hp = max_hp
		check(game.board_info.hp_segments(enemy).size() == max_hp and game.board_info.hp_segments(enemy).all(func(value): return value), "full multihp keeps every segment: %d" % max_hp)
		enemy.hp = 1
		check(game.board_info.hp_segments(enemy).count(true) == 1, "damaged multihp exact filled segments")
	check(game.board_info.enemy_statuses(enemy).is_empty(), "ordinary enemy has no invented status")
	enemy.heavy = true;enemy.unyielding = true;enemy.stun = 2
	game.queue_bleed(1, 2);game.queue_bleed(1, 1)
	var statuses = game.board_info.enemy_statuses(enemy)
	check(statuses.map(func(s): return s.key) == ["heavy", "unyielding", "stun", "bleed"], "coexisting status markers are not overwritten")
	check(game.board_info.bleed_status(enemy) == {"this_end": 2, "next_end": 1}, "bleed displays true timing not total as immediate damage")
	var info = game.board_info.inspect_at(game.cell_pos(enemy.pos))
	check(info.title.ends_with("1/9血") and info.anchor.has_point(game.cell_pos(enemy.pos)), "enemy inspect exact HP and hitrect")
	check(not "\n".join(info.lines).contains("复活次数"), "no fabricated revival limit")
	check(game.board_info.player_statuses().is_empty(), "no absent player statuses")
	game.shield_charges = 1;game.reload_ready = true;game.tuna_turns = 2;game.airdrop_recovery_turn = game.turn + 1
	check(game.board_info.player_statuses().size() == 4, "actual player statuses inspectable")
func check_mechanisms_and_ghosts():
	fixture();game.enemies = []
	E.setup(game, {"id": "c2_palace_guard", "tier": "elite", "chapter": 2, "rules": []})
	var guard: Dictionary = game.enemies[1];var uid: int = guard.uid
	game.damage_enemy(1, 0, 99);game.clear_effects()
	var marker = game.board_info.markers()[0]
	check(marker.uid == uid and marker.remaining_phases == 3, "ghost countdown uses actual remaining phases")
	var info = game.board_info.inspect_at(game.cell_pos(marker.pos))
	check(info.title == "不屈残影" and "\n".join(info.lines).contains("还需3次轮末结算"), "ghost tooltip exact countdown and rules")
	game.player = marker.pos
	for i in 3: E.finish_phase(game, 0)
	info = game.board_info.inspect_at(game.cell_pos(marker.pos))
	check(info.title == "我方" and "\n".join(info.lines).contains("原位被占"), "occupied ghost remains inspectable under live piece")
	check(game.board_info.markers()[0].status == "blocked", "blocked ghost remains a faint board marker")
	check(game.board_info.mechanism_tags().size() == 3, "only authored chapter2 mechanisms")
	for size in [Vector2(1280, 940), Vector2(390, 844), Vector2(360, 640), Vector2(844, 390)]:
		game.configure_layout(size)
		for tag in game.board_info.tag_items():
			check(Rect2(Vector2.ZERO, game.ui_size).encloses(tag.anchor), "tag fits viewport")
			check(not tag.anchor.intersects(game.BOARD_RECT.grow(-5)), "tag does not cover pieces")
			check(game.board_info.inspect_at(tag.anchor.get_center()).key == tag.key, "each tag has its own inspection target")
	fixture();game.enemies = []
	E.setup(game, {"id": "palace_final", "tier": "boss", "rules": ["palace_rotation", "last_stand"]})
	check(game.board_info.mechanism_tags().size() == 2, "boss has two compact rule tags")
	var selected = E.selected_guard(game)
	for enemy in game.enemies:
		if enemy.uid == selected: check(game.board_info.enemy_statuses(enemy).any(func(s): return s.key == "credits"), "upcoming rotation credit has truthful current marker")
func check_dense_status_and_cues():
	fixture()
	var synthetic: Array = []
	for i in 9: synthetic.append({"key": "status%d" % i, "glyph": "重", "color": Color.RED})
	for size in [Vector2(1280, 940), Vector2(390, 844), Vector2(360, 640), Vector2(844, 390)]:
		game.configure_layout(size)
		var markers = game.board_info.status_markers(synthetic)
		check(markers.size() == 5 and markers.back().glyph == "+5", "excess actual statuses grouped explicitly")
		for i in markers.size():
			for j in range(i + 1, markers.size()): check(not markers[i].rect.intersects(markers[j].rect), "7+ status markers never overlap")
	fixture();game.enemies = []
	E.setup(game, {"id": "palace_final", "tier": "boss", "rules": ["palace_rotation", "last_stand"]})
	game.board_info.tag_items();var builds: int = game.board_info.tag_cache_builds
	for i in 100: game.board_info.tag_items()
	check(game.board_info.tag_cache_builds == builds, "steady frames do not rebuild full tag rules/layout")
	game.encounter_state.phases += 1;game.board_info.tag_items()
	check(game.board_info.tag_cache_builds == builds + 1, "changed encounter refreshes tag current state")
	game.configure_layout(Vector2(390, 844));game.player_skill = "artillery";game.notice = ""
	game.board_info.cue = "旗卒渡河：配对炮获得1次加速，下轮起使用。";game.board_info.cue_left = 4
	check(not game.context_hint().is_empty() and game.board_info.cue_visible() and not game.board_info.should_show_context(), "artillery routine stance hint yields to mechanism feedback")
	game.phase = "discard"
	check(not game.board_info.cue_visible() and game.board_info.should_show_context(), "mandatory discard keeps priority")
	game.phase = "play";game.airdrop_recovery_turn = game.turn
	check(not game.board_info.cue_visible() and game.board_info.should_show_context(), "airdrop recovery keeps priority")
	game.airdrop_recovery_turn = 0;game.player = Vector2i(4, 1)
	check(not game.board_info.cue_visible() and game.board_info.should_show_context(), "check warning keeps priority")
	fixture();add("p", Vector2i(4, 5), 2);game.hand = ["sword"];game.sync_hand_views()
	game.tutorial.game = game;game.tutorial.active = true;game.tutorial._steps = [{"action": "play", "card": "sword", "target": Vector2i(4, 5), "hint": "预览"}];game.tutorial.step_index = 0
	var before = pack();var action: String = game.tutorial._last_action;var captured: Dictionary = game.tutorial._before.duplicate(true)
	check(not game.board_info.preview(0, Vector2i(4, 5)).is_empty(), "guided tutorial allowed target has preview")
	game.board_info.preview(0, Vector2i(8, 8))
	check(pack() == before and game.tutorial._last_action == action and game.tutorial._before == captured, "tutorial preview does not call mutating allows/capture")
	game.tutorial.stop()
func check_previews():
	for id in game.board_info.ATTACKS:
		for hp in [1, 4]:
			fixture()
			var target = Vector2i(4, 5)
			if id in ["cannon", "cannon_shot"]:
				target = Vector2i(4, 3);add("stake", Vector2i(4, 4), 1)
			elif id == "diagonal": target = Vector2i(5, 5)
			elif id == "knight_assault": target = Vector2i(5, 4)
			var victim_pos = Vector2i(5, 5) if id == "airdrop" else target
			var victim = add("p", victim_pos, hp);var uid: int = victim.uid
			if id == "cannon_shot": game.player_skill = "artillery";game.artillery_mode = "attack";game.reload_ready = true
			if id == "chain_assault": game.active_displacements = 3
			if id == "sweep": target = game.player
			game.hand = [id];game.sync_hand_views();game.selected = 0
			var before = pack()
			var preview: Dictionary = game.board_info.preview(0, target)
			check(not preview.is_empty(), "attack covered: " + id)
			if preview.is_empty(): continue
			check(pack() == before, "preview pure: " + id)
			var expected: Dictionary = preview.affected[0]
			game.play_card(0, target)
			var after = actor(uid)
			check(after.is_empty() == bool(expected.down), "down preview matches actual: " + id)
			if not after.is_empty(): check(int(after.hp) == int(expected.hp_after), "damage preview matches actual: " + id)
			if id == "pierce": check(game.pending_bleeds.size() == 1 and game.pending_bleeds[0].amount == 2 and expected.damage == 0, "delayed bleed not misrepresented as instant")
			if id == "airdrop": check(game.lives == 2 and game.airdrop_recovery_turn == 2, "airdrop self-cost and recovery true")
	fixture();add("p", Vector2i(4, 5), 3);game.hand = ["sword"];game.sync_hand_views();game.selected = 0
	var before = pack()
	for i in 40:
		game.board_info.inspect_at(game.cell_pos(Vector2i(4, 5)))
		game.board_info.current_preview(Vector2i(4, 5))
	check(pack() == before, "repeated inspection preserves RNG, hand/deck, history, encounter and effects")
	game.energy = 0;check(game.board_info.preview(0, Vector2i(4, 5)).is_empty(), "energy gate")
	game.energy = 10;game.input_lock = 1;check(game.board_info.preview(0, Vector2i(4, 5)).is_empty(), "animation gate")
	game.input_lock = 0;game.airdrop_recovery_turn = game.turn;check(game.board_info.preview(0, Vector2i(4, 5)).is_empty(), "recovery gate")
	game.airdrop_recovery_turn = 0;game.phase = "discard";check(game.board_info.preview(0, Vector2i(4, 5)).is_empty(), "discard gate")
	game.phase = "play";check(game.board_info.preview(0, Vector2i(8, 8)).is_empty(), "illegal target gate")
	game.hand = ["airdrop"];game.sync_hand_views();game.lives = 1
	var airdrop = game.board_info.preview(0, Vector2i(3, 5))
	check(airdrop.self_defeat and airdrop.self_damage == 1, "airdrop one-life defeat explicitly previewed")
	game.play_card(0, Vector2i(3, 5));check(game.phase == "dead", "airdrop defeat priority actual unchanged")
func check_hold_release():
	# Map holds now stay open after release. Shared battle inspection must retain
	# its original dismiss-on-release behavior and never play a selected attack.
	for size in [Vector2(1280, 940), Vector2(390, 844), Vector2(360, 640), Vector2(844, 390)]:
		game.configure_layout(size);fixture()
		add("p", Vector2i(4, 5), 3);game.hand = ["sword"];game.sync_hand_views();game.selected = 0
		game.information.clear()
		var before = pack()
		var touch = InputEventScreenTouch.new();touch.index = 4;touch.position = game.cell_pos(Vector2i(4, 5));touch.pressed = true
		game._input(touch);game.information.tick(0.39)
		check(not game.information.visible, "battle inspection waits for its hold threshold")
		game.information.tick(0.02)
		check(game.information.visible and game.information.consumed_hold, "battle long hold opens read-only information")
		check(pack() == before, "battle hold preserves selected attack, board, RNG and undo")
		touch.pressed = false;game._input(touch)
		check(not game.information.visible and not game.information.sticky and game.information.pointer == -2 and not game.information.consumed_hold, "battle hold release dismisses instead of retaining map-style inspection")
		check(pack() == before, "battle hold release never performs a selected attack")
func run():
	game = load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false)
	check_statuses();check_mechanisms_and_ghosts();check_dense_status_and_cues();check_previews();check_hold_release()
	game.free()
	print("BOARD INFO: %d checks; %d failures" % [checks, failures]);quit(1 if failures else 0)
