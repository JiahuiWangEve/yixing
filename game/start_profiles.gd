extends RefCounted
# Opening identity owns the permanent starter deck and rewards, not initial draws.
# Retired cards are removed. This demo version starts a new run-save namespace.
const COMMON = ["sword", "spear", "diagonal", "breath"]
const DATA = {
	"king": {"name": "帅", "lives": 2,
		"deck": ["sword", "sword", "spear", "life"],
		"rewards": ["life", "sweep", "pierce", "shock", "tuna", "suppress", "guard", "horse", "airdrop", "blood_edge", "blood_break", "last_stand"]},
	"horse": {"name": "马", "lives": 1,
		"deck": ["sword", "sword", "spear", "advance"],
		"rewards": ["straight", "pursuit", "advance", "retreat_strike", "knight_assault", "chain_assault"]},
	"artillery": {"name": "炮车", "lives": 1,
		"deck": ["sword", "stake", "cannon_shot", "deploy"],
		"rewards": ["stake", "cannon_shot", "deploy", "pack", "permanent_stake", "reload"]}
}
static func reward_weight(identity: String, id: String) -> int:
	# Pure horse movement appears half as often per draw as its attack cards.
	return 1 if identity == "horse" and id == "straight" else 2
static func draw_rewards(identity: String, random: RandomNumberGenerator, exclusive_count: int = 2) -> Array:
	var exclusive: Array = DATA.get(identity, {}).get("rewards", [])
	return _draw_rewards_from_pools(identity, random, exclusive_count, exclusive, COMMON)

static func _legal_unique(candidates: Array, allowed: Array, excluded: Array = []) -> Array:
	var result: Array = []
	for id in candidates:
		if id is String and id in allowed and id not in excluded and id not in result: result.append(id)
	return result

static func _take_weighted(identity: String, random: RandomNumberGenerator, pool: Array) -> String:
	if pool.is_empty(): return ""
	var total = 0
	for id in pool: total += reward_weight(identity, id)
	var ticket = random.randi_range(0, total - 1)
	for i in pool.size():
		ticket -= reward_weight(identity, pool[i])
		if ticket < 0: return pool.pop_at(i)
	return ""

static func _draw_rewards_from_pools(identity: String, random: RandomNumberGenerator, exclusive_count: int, exclusive_candidates: Array, common_candidates: Array) -> Array:
	# Prefer the requested own-card quota plus one common. A smaller pool fills
	# from the remaining legal cards, never repeats a card or invents an ID.
	var own: Array = DATA.get(identity, {}).get("rewards", [])
	var pool = _legal_unique(exclusive_candidates, own, COMMON)
	var common = _legal_unique(common_candidates, COMMON)
	var result: Array = []
	var quota = maxi(0, exclusive_count)
	for pick in mini(quota, pool.size()): result.append(_take_weighted(identity, random, pool))
	if not common.is_empty(): result.append(common.pop_at(random.randi_range(0, common.size() - 1)))
	pool.append_array(common)
	while result.size() < quota + 1 and not pool.is_empty(): result.append(_take_weighted(identity, random, pool))
	return result
