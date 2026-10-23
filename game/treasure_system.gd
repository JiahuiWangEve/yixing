extends RefCounted
# Run ownership lives in route.state; only reversible battle effects live here.
const DATA = {
	"longevity_seal": {"name": "长生玉玺", "role": "king", "summary": "取消生命上限，不立即回血。", "description": "取消生命上限，不增加初始生命，不立即回血。"},
	"life_talisman": {"name": "替命金符", "role": "king", "summary": "每场首次命数耗尽时保留1命，主动自损也可触发。", "description": "每场战斗首次命数耗尽时保留1命；主动自损也可触发，不提供护盾或后续无敌。"},
	"tiger_tally": {"name": "行军虎符", "role": "king", "summary": "每主动位移3次，获得临时0费将步：正交移动1格。", "description": "每成功主动位移3次，获得临时0费将步：正交移动1格。余数跨回合保留；受击撤退不计。将步不占免费或移动牌额度，使用不抽牌；使用、过牌或回合末移除。过牌仍支付3能量并抽1张。"},
	"wind_horseshoe": {"name": "追风蹄铁", "role": "horse", "summary": "每回合第2次主动位移后立即获得1能量。", "description": "每回合第2次成功主动位移后立即获得1能量，每回合一次。"},
	"battle_tassel": {"name": "踏阵长缨", "role": "horse", "summary": "每回合第2次主动位移后，本回合下一张攻击伤害+2。", "description": "每回合第2次成功主动位移后，本回合下一张攻击牌伤害+2；整张牌生效，回合末失效。"},
	"spring_bit": {"name": "饮泉玉勒", "role": "horse", "summary": "每场前2次真正击败敌子各回复1命。不屈暂时击倒不计。", "description": "每场前2次真正击败敌子各回复1命；满血也计次数，不屈暂时击倒不计。"},
	"gate_cannon_seal": {"name": "镇关炮印", "role": "artillery", "summary": "以攻击姿态开始回合且未移动、未切姿态，首张炮击费用−1。", "description": "以攻击姿态开始回合，且尚未主动移动或切换姿态时，首张炮击费用−1，最低0。"},
	"roving_axle": {"name": "游击轮轴", "role": "artillery", "summary": "每回合首次攻击转行军，获得临时0费转移：正交移动1格。", "description": "每回合首次从攻击切换为行军姿态，获得临时0费转移：正交移动1格，不占免费或移动牌额度，使用不抽牌；使用、过牌或回合末移除。过牌仍支付3能量并抽1张。"},
	"chain_fire_fuse": {"name": "连珠火签", "role": "artillery", "summary": "炮击真正击败敌子时抽1张，可与装填叠加。", "description": "每次炮击真正击败敌子抽1张，可与装填叠加；不屈暂时击倒不计，终结战斗后不抽牌。"},
	"decoy_tally": {"name": "疑兵虎符", "role": "common", "summary": "第1、4、7…回合生成0费草木皆兵；手牌至多1张，跨回合保留。", "description": "第1回合及之后每3回合（第4、7…回合）生成一张0费草木皆兵；手牌中至多保留1张，跨回合不消失。可在以自身为中心5×5范围内的空格放置2血草人，场上至多1个，持续至被击碎。"},
}
const TEMP_CARDS = {
	"treasure_king_step": ["将步", 0, "临时：正交移动1格，不占移动额度；使用不抽牌，使用或回合末移除；过牌仍3费抽1张且移除", "移"],
	"treasure_transfer": ["转移", 0, "临时：正交移动1格，不占移动额度；使用不抽牌，使用或回合末移除；过牌仍3费抽1张且移除", "移"],
}
const TEMPORARY = ["treasure_king_step", "treasure_transfer"]
var game
func _init(owner): game = owner
static func ids_for(role: String) -> Array:
	# Formal chapter rewards stay exactly three profession-specific choices.
	var result: Array = []
	if role not in ["king", "horse", "artillery"]: return result
	for id in DATA:
		if DATA[id].role == role: result.append(id)
	return result
static func training_ids_for(role: String) -> Array:
	var result = ids_for(role)
	if role in ["king", "horse", "artillery"]:
		for id in DATA:
			if DATA[id].role == "common": result.append(id)
	return result
static func valid_battle_state(value) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true # Pre-treasure saves and untouched map state.
	for key in ["talisman_used", "victory_settled", "wind_used", "tassel_triggered", "tassel_ready", "gate_ready", "gate_spent", "axle_used"]:
		if not value.has(key) or not value[key] is bool: return false
	for key in ["tiger_moves", "spring_kills", "trigger_serial", "attack_bonus"]:
		if not value.has(key) or not value[key] is int or value[key] < 0: return false
	if value.tiger_moves > 2 or value.spring_kills > 2 or value.attack_bonus not in [0, 2]: return false
	if not value.has("active_card") or not value.active_card is String: return false
	if value.active_card.is_empty() and value.attack_bonus != 0: return false
	if value.tassel_ready and not value.tassel_triggered: return false
	if value.has("decoy_last_turn") and (not value.decoy_last_turn is int or value.decoy_last_turn < -1): return false
	if value.has("trigger_serials"):
		if not value.trigger_serials is Dictionary: return false
		for id in value.trigger_serials:
			if not DATA.has(id) or not value.trigger_serials[id] is int or value.trigger_serials[id] < 0: return false
	return true
func active_id() -> String:
	# This API remains the formal saved single treasure, never a training alias.
	if game.tutorial.active or training_active() or not game.route.active(): return ""
	var id = str(game.route.state.get("treasure_id", ""))
	return id if id in ids_for(game.player_skill) else ""
func training_active() -> bool:
	var training = game.get("training")
	return training != null and training.is_playing()
func active_ids() -> Array:
	if game.tutorial.active: return []
	if training_active():
		var result: Array = []
		var selected = game.training.state.get("treasure_ids", [])
		if not selected is Array: return result
		var allowed = training_ids_for(game.player_skill)
		for id in selected:
			if id is String and id in allowed and id not in result: result.append(id)
		return result
	var id = active_id()
	return [] if id.is_empty() else [id]
func has(id: String) -> bool: return id in active_ids()
func reset_battle():
	game.treasure_battle = {"talisman_used": false, "tiger_moves": 0, "spring_kills": 0, "trigger_serial": 0, "trigger_serials": {}, "decoy_last_turn": -1, "victory_settled": false, "active_card": "", "attack_bonus": 0}
	start_turn()
func start_turn():
	game.treasure_battle.merge({"wind_used": false, "tassel_triggered": false, "tassel_ready": false,
		"gate_ready": has("gate_cannon_seal") and game.artillery_mode == "attack", "gate_spent": false, "axle_used": false}, true)
func trigger(message: String, feedback: String = "draw", label: String = "", id: String = ""):
	# Explicit source IDs keep simultaneous training effects on their own icons.
	if id.is_empty():
		var ids = active_ids()
		if ids.size() == 1: id = ids[0]
	game.treasureui.trigger(feedback, label, id)
	game.treasure_battle.trigger_serial = int(game.treasure_battle.get("trigger_serial", 0)) + 1
	if has(id):
		var serials: Dictionary = game.treasure_battle.get("trigger_serials", {}).duplicate()
		serials[id] = int(serials.get(id, 0)) + 1
		game.treasure_battle.trigger_serials = serials
	game.log_line(message)
func on_displacement():
	if has("gate_cannon_seal"): game.treasure_battle.gate_ready = false
	if has("tiger_tally"):
		game.treasure_battle.tiger_moves = int(game.treasure_battle.get("tiger_moves", 0)) + 1
		if game.treasure_battle.tiger_moves >= 3:
			game.treasure_battle.tiger_moves -= 3
			generate_move("treasure_king_step");trigger("行军虎符：获得临时将步。", "draw", "", "tiger_tally")
	if game.active_displacements != 2: return
	if has("wind_horseshoe") and not game.treasure_battle.get("wind_used", false):
		game.treasure_battle.wind_used = true;game.energy += 1;trigger("追风蹄铁：能量+1。", "energy", "+1", "wind_horseshoe")
	if has("battle_tassel") and not game.treasure_battle.get("tassel_triggered", false):
		game.treasure_battle.tassel_triggered = true;game.treasure_battle.tassel_ready = true
		trigger("踏阵长缨：本回合下一张攻击伤害+2。", "draw", "", "battle_tassel")
func on_stance_change(previous: String, current: String):
	if previous == current: return
	game.treasure_battle.gate_ready = false
	if has("roving_axle") and previous == "attack" and current == "march" and not game.treasure_battle.get("axle_used", false):
		game.treasure_battle.axle_used = true;generate_move("treasure_transfer");trigger("游击轮轴：获得临时转移。", "draw", "", "roving_axle")
func generate_move(id: String):
	game.sync_hand_ids();game.hand.append(id);game.hand_ids.append(game.next_card_uid);game.next_card_uid += 1
	game.handui.sync();game.effect("draw", Vector2.ZERO, Vector2.ZERO, 0.32)
	if game.hand.size() > 6: game.phase = "discard";game.selected = -1;game.free_selected = false
func expire_temporary():
	game.sync_hand_ids()
	for index in range(game.hand.size() - 1, -1, -1):
		if game.hand[index] in TEMPORARY: game.hand.remove_at(index);game.hand_ids.remove_at(index)
	game.deck = game.deck.filter(func(id): return id not in TEMPORARY)
	game.discard = game.discard.filter(func(id): return id not in TEMPORARY)
	game.handui.sync()
func end_turn():
	expire_temporary();game.treasure_battle.tassel_ready = false;end_card()
func is_attack(id: String) -> bool: return game.CARDS.has(id) and game.CARDS[id][3] == "攻"
func preview_bonus(id: String) -> int:
	if not has("battle_tassel") or not is_attack(id): return 0
	if game.treasure_battle.get("tassel_ready", false): return 2
	# Retreat happens before its damage; advance/assault move only after damage.
	if id == "retreat_strike" and game.active_displacements == 1 and not game.treasure_battle.get("tassel_triggered", false): return 2
	return 0
func claim_attack_bonus():
	if has("battle_tassel") and game.treasure_battle.get("tassel_ready", false):
		game.treasure_battle.tassel_ready = false;game.treasure_battle.attack_bonus = 2
func begin_card(id: String):
	game.treasure_battle.active_card = id;game.treasure_battle.attack_bonus = 0
	if is_attack(id) and id != "retreat_strike": claim_attack_bonus()
	if id == "cannon_shot":
		if cannon_discount() > 0: trigger("镇关炮印：本次炮击费用−1。", "draw", "", "gate_cannon_seal")
		game.treasure_battle.gate_ready = false;game.treasure_battle.gate_spent = true
func end_card():
	game.treasure_battle.active_card = "";game.treasure_battle.attack_bonus = 0
func damage_bonus() -> int: return int(game.treasure_battle.get("attack_bonus", 0))
func cannon_discount() -> int:
	return 1 if has("gate_cannon_seal") and game.treasure_battle.get("gate_ready", false) and not game.treasure_battle.get("gate_spent", false) else 0
func rescue_ready() -> bool: return has("life_talisman") and not game.treasure_battle.get("talisman_used", false)
func rescue() -> bool:
	if game.lives > 0 or not rescue_ready(): return false
	game.treasure_battle.talisman_used = true;game.lives = 1;trigger("替命金符：保留1命，本场已使用。", "revive", "保留1命", "life_talisman")
	return true
func true_defeat(enemy: Dictionary) -> bool:
	return enemy.kind not in ["stake", "decoy"] and not enemy.get("unyielding", false)
func on_enemy_defeated(enemy: Dictionary):
	if not true_defeat(enemy): return
	if has("spring_bit") and int(game.treasure_battle.get("spring_kills", 0)) < 2:
		game.treasure_battle.spring_kills = int(game.treasure_battle.get("spring_kills", 0)) + 1
		var restored: int = game.heal_lives(1) if game.lives > 0 else 0
		trigger("饮泉玉勒：击败回复%d命（本场%d/2次）。" % [restored, game.treasure_battle.spring_kills], "draw", "", "spring_bit")
	if has("chain_fire_fuse") and game.treasure_battle.get("active_card", "") == "cannon_shot" and game.general_alive() and game.lives > 0:
		game.draw_card();trigger("连珠火签：炮击击败，抽1张。", "draw", "", "chain_fire_fuse")
func status(id: String = "") -> Dictionary:
	var ids = active_ids()
	if id.is_empty() and not ids.is_empty(): id = ids[0]
	if id not in ids: return {}
	var result = {"id": id, "name": DATA[id].name, "role": DATA[id].role, "description": DATA[id].description,
		"badge": "", "lines": [DATA[id].description], "ready": false, "used": false, "trigger_serial": int(game.treasure_battle.get("trigger_serials", {}).get(id, 0))}
	match id:
		"longevity_seal": result.ready = true
		"life_talisman": result.used = game.treasure_battle.get("talisman_used", false);result.ready = not result.used;result.badge = "用" if result.used else "备"
		"tiger_tally": result.badge = "%d/3" % int(game.treasure_battle.get("tiger_moves", 0))
		"wind_horseshoe": result.used = game.treasure_battle.get("wind_used", false);result.badge = "用" if result.used else "%d/2" % mini(2, game.active_displacements)
		"battle_tassel": result.ready = game.treasure_battle.get("tassel_ready", false);result.used = game.treasure_battle.get("tassel_triggered", false) and not result.ready;result.badge = "+2" if result.ready else ("用" if result.used else "%d/2" % mini(2, game.active_displacements))
		"spring_bit": result.badge = "余%d" % maxi(0, 2 - int(game.treasure_battle.get("spring_kills", 0)))
		"gate_cannon_seal": result.ready = cannon_discount() > 0;result.badge = "−1" if result.ready else ""
		"roving_axle": result.used = game.treasure_battle.get("axle_used", false);result.badge = "用" if result.used else ""
		"decoy_tally":
			var held = "decoy_card" in game.hand
			var decoy_hp = 0;var decoy_max_hp = 2
			for piece in game.enemies:
				if piece.get("kind", "") == "decoy" and int(piece.get("hp", 2)) > decoy_hp:
					decoy_hp = int(piece.get("hp", 2));decoy_max_hp = int(piece.get("max_hp", 2))
			result.ready = held and decoy_hp == 0
			result.badge = "%d血" % decoy_hp if decoy_hp > 0 else ("备" if held else "%d回" % (3 - posmod(game.turn - 1, 3)))
			result.lines.append("手牌：%d/1张；场上草人：%s。" % [1 if held else 0, "%d/%d血" % [decoy_hp,decoy_max_hp] if decoy_hp > 0 else "无"])
			result.lines.append("下次生成：第%d回合；届时已有草木皆兵则不重复生成。" % (game.turn + 3 - posmod(game.turn - 1, 3)))
	if id == "gate_cannon_seal": result.lines.append("当前首炮费用−1。" if result.ready else "本回合未就绪：未以攻击姿态开始，或已经移动、切换姿态、使用炮击。")
	elif id == "chain_fire_fuse": result.lines.append("按每次真正击败结算，无次数上限。")
	elif id == "longevity_seal": result.lines.append("当前生命%d，无上限。" % game.lives)
	elif not result.badge.is_empty(): result.lines.append("当前：" + result.badge + "。")
	return result
