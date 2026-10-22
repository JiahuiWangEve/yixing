extends RefCounted
# Current, playable pools are the authority, not every historical entry in CARDS.
const PROFILES = preload("res://start_profiles.gd")
const UPGRADES = preload("res://card_upgrades.gd")
const FREE_MOVE = preload("res://free_move_card.gd")
const GROUPS = [
	{"id": "common", "label": "公共"}, {"id": "king", "label": "将"},
	{"id": "horse", "label": "马"}, {"id": "artillery", "label": "炮车"},
	{"id": "special", "label": "特殊"}
]
static func _append_card(result: Array, id: String, cards: Dictionary, source: String):
	if not cards.has(id): return
	for entry in result:
		if entry.id == id: return
	var upgrade_id = UPGRADES.upgraded_id(id) if UPGRADES.can_upgrade(id) else ""
	if not cards.has(upgrade_id): upgrade_id = ""
	result.append({"id": id, "data": cards[id].duplicate(), "source": source, "upgrade_id": upgrade_id})
static func entries_for(group_id: String, cards: Dictionary) -> Array:
	var result: Array = []
	if group_id == "common":
		for id in PROFILES.COMMON: _append_card(result, id, cards, "公共卡牌")
	elif PROFILES.DATA.has(group_id):
		var pool: Array = PROFILES.DATA[group_id].deck.duplicate()
		pool.append_array(PROFILES.DATA[group_id].rewards)
		for id in pool:
			if id not in PROFILES.COMMON: _append_card(result, id, cards, "角色专属")
	elif group_id == "special":
		_append_card(result, "fatigue", cards, "负面牌 · 非普通奖励")
		for identity in ["king", "horse", "artillery"]:
			for stance in (["march", "attack"] if identity == "artillery" else ["march"]):
				var id = "__free_" + identity + ("_" + stance if identity == "artillery" else "")
				result.append({"id": id, "data": FREE_MOVE.data_for(identity, stance),
					"source": "免费生成 · 非普通奖励", "upgrade_id": ""})
	return result
