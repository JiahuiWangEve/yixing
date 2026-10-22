extends RefCounted
# Read-only presentation data. The caller opts into battle state explicitly;
# catalog/deck/reward/merchant callers must retain the default false argument.
const FREE_MOVE = preload("res://free_move_card.gd")
const TEMPORARY = ["treasure_king_step", "treasure_transfer"]
const CONSUMABLE_RULE = "消耗：一局战斗只能用一次。"
const FREE_IDENTITIES = {
	"__free_king": ["king", "march"],
	"__free_horse": ["horse", "march"],
	"__free_artillery_march": ["artillery", "march"],
	"__free_artillery_attack": ["artillery", "attack"],
}
var game

func _init(owner): game = owner

func data(id: String, battle: bool = false) -> Array:
	if FREE_IDENTITIES.has(id): return _free_data(id)
	if not game.CARDS.has(id): return []
	var result: Array = game.CARDS[id].duplicate(true)
	while result.size() < 5: result.append("")
	if battle: result[1] = game.card_cost(id)
	var descriptions: Array = _attack(id, battle) if str(result[3]) == "攻" else _utility(id, battle)
	result[2] = descriptions[0]
	result[4] = descriptions[1]
	if id in game.CONSUMABLES:
		result[4] += "\n" + CONSUMABLE_RULE
	return result

func _free_data(id: String) -> Array:
	var identity: Array = FREE_IDENTITIES[id]
	var result: Array = FREE_MOVE.data_for(identity[0], identity[1]).duplicate(true)
	var movement = "正交移动1格至空格"
	var rule = ""
	if identity[0] == "horse":
		movement = "马步移动至空格"
		rule = "遵守蹩马腿；"
	elif id == "__free_artillery_march":
		movement = "正交移动1–2格至空格"
		rule = "不穿透；"
	result[2] = movement + "\n" + rule + "抽1张；每回合1次"
	result.append(movement + "；" + rule + "抽1张。每回合1次，与点格移动共用免费额度，不占移动牌额度。")
	return result

func _bonus(id: String, battle: bool) -> int:
	return int(game.treasures.preview_bonus(id)) if battle else 0

func _amount(base: int, bonus: int) -> String:
	return "伤害%d" % (base + bonus) + ("（宝物+%d）" % bonus if bonus > 0 else "")

func _self_cost_rule(battle: bool) -> String:
	var rule = "护盾不抵消命耗，不撤退。"
	if battle and game.lives <= 1:
		return rule + ("替命金符可用，保留1命。" if game.treasures.rescue_ready() else "当前仅1命，使用即败，优先于击杀敌将。")
	return rule + "命归零即败，优先于击杀敌将；可用的替命金符能保留1命。"

func _battle_self_cost_rule() -> String:
	if game.lives <= 1:
		return "金符保留1命。" if game.treasures.rescue_ready() else "当前使用即败。"
	return "命归零先判败。"

func _attack(id: String, battle: bool) -> Array:
	var kind = "单体"
	var area = "正交1格"
	var amount = _amount(1, _bonus(id, battle))
	var brief = ""
	var detail = ""
	var self_cost = id in ["blood_edge", "blood_break", "airdrop"]
	match id:
		"sword", "sword_plus":
			amount = _amount(2 if id == "sword_plus" else 1, _bonus(id, battle))
		"diagonal": area = "斜角1格"
		"spear", "spear_plus":
			area = "正交1–2格"
			amount = _amount(2 if id == "spear_plus" else 1, _bonus(id, battle))
			brief = "不穿透"
			detail = "路径不得有其他棋子，不穿透。"
		"cannon":
			area = "正交直线"
			brief = "隔恰好1子"
			detail = "与目标之间须恰好隔1枚棋子，敌子或木桩均可作炮架。"
		"cannon_shot":
			area = "正交直线"
			amount = "伤害行军1/攻击2"
			brief = "隔恰好1子"
			detail = "与目标之间须恰好隔1枚棋子，敌子或木桩均可作炮架。行军姿态2费、伤害1；攻击姿态1费、伤害2。"
			if battle:
				var loaded = 1 if game.reload_ready else 0
				amount = _amount((2 if game.artillery_mode == "attack" else 1) + loaded, _bonus(id, true))
				brief += "；" + ("攻击姿态" if game.artillery_mode == "attack" else "行军姿态")
				detail = "当前%s姿态，费用%d；与目标间恰好隔1子，敌子或木桩均可。" % ["攻击" if game.artillery_mode == "attack" else "行军", game.card_cost(id)]
				if loaded > 0:
					brief += "；装填+1"
					detail += "含装填+1，击杀抽1张，使用后装填失效；战斗结束不抽。"
				if game.treasures.cannon_discount() > 0: detail += "费用已计入镇关炮印−1。"
				if game.treasures.has("chain_fire_fuse"): detail += "连珠火签：真正击败再抽1张，可叠加装填；不屈暂倒、战斗结束不抽。"
		"sweep":
			kind = "群体";area = "自身3×3范围"
			detail = "范围内敌子各受伤害；须有敌子，不伤木桩。"
		"blood_edge":
			kind = "群体";area = "单一正交方向1–3格"
			amount = _amount(2, _bonus(id, battle));brief = "贯穿"
			detail = "点范围内格选方向；贯穿，须有敌子，不伤木桩。不移动、不跳过回合。"
		"blood_break":
			kind = "群体";area = "四正交各1–2格"
			amount = _amount(3, _bonus(id, battle));brief = "不含斜角"
			detail = "不含斜角；贯穿，须有敌子，不伤木桩。不移动、不跳过回合。"
		"last_stand":
			amount = _amount(3 if game.lives == 1 else 1, _bonus(id, true)) if battle else "伤害1，仅1命时3"
			brief = "出牌时仅1命则3伤" if battle else ""
			detail = "出牌时恰好1命则基础伤害3，否则1；不扣命、不移动。"
		"airdrop":
			kind = "群体";area = "落点3×3范围"
			amount = _amount(3, _bonus(id, battle))
			brief = "飞至其他空格；下回合停行动"
			detail = "飞至任意其他空格（不能落在棋子上），不伤木桩。当前回合可继续；下一玩家回合禁移动、出牌，敌方与被动照常。"
		"pierce":
			amount = "伤害1×2"
			brief = "本回合末、下回合末各1"
			detail = "本回合与下一玩家回合结束时、敌方攻击前各1伤，不立即造成伤害。跟随目标，可叠加；目标死亡后失效。"
			if battle and _bonus(id, true) > 0: detail += "踏阵长缨会被本张消耗，但不增加延迟流血伤害。"
		"chain_assault":
			area = "自身3×3范围"
			amount = "伤害本回合主动位移次数+1"
			var bonus = _bonus(id, battle)
			if battle:
				if bonus > 0: amount += "+%d" % bonus
				amount += "（当前%d）" % (int(game.active_displacements) + 1 + bonus)
			detail = "成功的免费移动、移动牌与攻击位移，每次计1次，非格数；受击转移、失败与切姿态不计。"
		"pursuit":
			brief = "击杀抽1张"
			detail = "仅击杀且战斗未结束时抽1张，不移动。"
		"shock":
			area = "3×3范围或正交2格"
			brief = "存活目标推1格"
			detail = "目标存活时向远离自己的方向推1格；推入格须在棋盘内且为空。推不动仍造成伤害。"
		"advance":
			brief = "击杀进目标格；不抽牌"
			detail = "先攻击；击杀后进入目标格，不抽牌。未击杀则不移动。"
		"retreat_strike":
			brief = "先退1格再攻击；退路须空"
			detail = "先向目标反方向退1格，再攻击原目标；退路须在棋盘内且为空，不抽牌。"
			if battle and game.treasures.has("battle_tassel") and not game.treasure_battle.get("tassel_ready", false) and int(game.active_displacements) == 1 and not game.treasure_battle.get("tassel_triggered", false):
				amount = "伤害1（退步触发宝物则+2）"
				detail += "若合法撤退成为本回合第2次主动位移，则先触发踏阵长缨，再使本张伤害+2。"
		"knight_assault":
			area = "马步攻击";amount = _amount(2, _bonus(id, battle))
			brief = "遵守蹩腿；击杀进入目标格"
			detail = "遵守蹩马腿。先攻击，击杀后进入目标格，不抽牌；未击杀则不移动。"
		_:
			# Preserve unknown future rules instead of silently inventing an effect.
			var original: Array = game.CARDS[id]
			return [str(original[2]), str(original[4]) if original.size() > 4 else str(original[2])]
	var lead = ("命−1；" if self_cost else "") + kind + "；" + area + "\n" + amount
	var short_text = lead + ("；" + brief if not brief.is_empty() else "")
	var full_text = lead + "。" + detail
	# The unchanged small battle card shows actionable essentials. The permanent
	# viewer/catalog retains the exhaustive rule text, not a copy of live state.
	if battle:
		match id:
			"blood_edge": detail = "贯穿，不伤木桩；不移动、不跳回合。"
			"blood_break": detail = "不含斜角；贯穿，不伤木桩；不移动。"
			"airdrop": detail = "飞至任意其他空格。下回合不能移动/出牌。"
			"chain_assault": detail = "免费/移动牌/攻击位移每次计1；受击/失败/切姿态不计。"
			"pierce":
				detail = "本回合末与下回合末各1，敌方攻击前结算；随目标、可叠加，目标死即失效。"
				if _bonus(id, true) > 0: detail += "宝物已耗，延迟伤害不加成。"
			"retreat_strike":
				detail = "向目标反方向先退1格再打；退路须为空且在棋盘内；不抽牌。"
				if amount.contains("退步触发"): detail += "宝物为踏阵长缨。"
			"cannon_shot":
				detail = "隔恰好1子；" + ("攻击姿态。" if game.artillery_mode == "attack" else "行军姿态。")
				if game.reload_ready: detail += "含装填+1，击杀抽1张；终战不抽。"
				if game.treasures.cannon_discount() > 0: detail += "费用已计入镇关炮印−1。"
				if game.treasures.has("chain_fire_fuse"): detail += "火签真正击败再抽1；不屈暂倒/终战不抽。"
		full_text = lead + "。" + detail
	if battle and _bonus(id, true) > 0 and id != "pierce":
		# The retreat-trigger case describes its condition instead of claiming a
		# target-independent damage constant before a legal retreat is chosen.
		if not amount.contains("退步触发"): full_text += "伤害已计入踏阵长缨+2。"
	if self_cost:
		full_text += _battle_self_cost_rule() if battle else _self_cost_rule(false)
		if battle and game.lives <= 1:
			short_text += "；" + ("金符保留1命" if game.treasures.rescue_ready() else "当前使用即失败")
	return [short_text, full_text]

func _utility(id: String, battle: bool) -> Array:
	match id:
		"horse":
			return ["马步移动至空格\n遵守蹩马腿；抽1张", "马步移动至空格；遵守蹩马腿，抽1张。每回合最多1张普通移动牌，与免费移动额度独立。"]
		"straight":
			return ["正交移动1–2格至空格；不穿透；抽1张", "正交移动1–2格至空格；不穿透，抽1张。每回合最多1张普通移动牌，与免费移动额度独立。"]
		"treasure_king_step", "treasure_transfer":
			return ["正交移动1格至空格\n不占移动额度；不抽牌\n回合结束消失", "正交移动1格至空格，不占免费或移动牌额度，不抽牌。成功使用或过牌后消失；回合结束消失。过牌仍3费抽1张。"]
		"stake":
			return ["木桩；曼哈顿2格内空位\n挡路作炮架；持续3回合", "曼哈顿1–2格空位放木桩（含斜角相邻），挡路作炮架。本次起，第3次敌方行动结束后消失。"]
		"permanent_stake":
			return ["木桩；曼哈顿2格内空位\n挡路作炮架；持续本场", "曼哈顿1–2格空位放木桩（含斜角相邻），挡路作炮架；不按回合消失，战斗结束清除。"]
		"life":
			var cap = "无上限" if battle and game.unlimited_lives() else "上限5"
			return ["命+1（%s）" % cap, "命+1（%s）。%s" % [cap, "" if cap == "无上限" else "满命时不可使用。"]]
		"breath": return ["本回合能量+1", "立即获得1能量；不增加后续回合的起始能量。"]
		"tuna":
			return ["下回合起连续3回合\n起始能量+1", "下回合起，连续3回合起始能量+1（3变4，仍被疲惫扣减）。当回合不返费；再用延长3回合，不叠加增量；过关清除。"]
		"suppress":
			return ["抽1张；正交1格内所有敌子\n移动倒计时+2", "先抽1张，再令正交1格所有敌子移动倒计时+2；行动凭据移动也延后2轮。不伤害、不影响攻击；手牌超限先结算再弃牌。"]
		"guard":
			return ["抵挡下次受击1次\n至下个玩家回合开始", "抵挡下次受击，不掉命、不转移，不抵消主动命耗。下个玩家回合开始失效；重复使用只刷新1次。"]
		"reload":
			return ["本回合下张炮击伤害+1\n击杀抽1张", "本回合下张成功炮击伤害+1；击杀且战斗未结束时抽1张。无效目标不耗装填；仅强化炮击，回合末失效，重复只刷新、不叠加。"]
		"deploy":
			var short_text = "行军→攻击姿态\n本回合首次展开抽3张"
			var full_text = "行军→攻击姿态；每回合首次展开抽3张，超6张须弃牌。不移动，不改变免费移动额度。"
			if battle and game.deploy_draw_used:
				short_text = "行军→攻击姿态\n本回合已展开，不再抽牌"
				full_text += "本回合已展开过，本次不再抽牌。"
			return [short_text, full_text]
		"pack":
			return ["攻击→行军姿态\n不抽牌；保留免费移动额度", "攻击→行军姿态；不移动、不抽牌。保留免费移动额度，不刷新已用额度。"]
		"fatigue":
			return ["抽到、后续回合开始仍留手\n能量−1（最低0）\n2费打出弃置", "抽到时立即能量−1；后续每个玩家回合开始仍留手再扣1，最低0；多张分别触发。2费打出弃置，不返还已扣能量，可再抽到。"]
	var original: Array = game.CARDS[id]
	return [str(original[2]), str(original[4]) if original.size() > 4 else str(original[2])]
