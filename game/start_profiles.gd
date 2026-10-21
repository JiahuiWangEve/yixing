extends RefCounted
# Opening identity owns the permanent starter deck and rewards, not initial draws.
# Retired cards are removed. This demo version starts a new run-save namespace.
const COMMON = ["sword", "spear", "diagonal", "breath"]
const DATA = {
	"king": {"name": "帅", "lives": 2,
		"deck": ["sword", "sword", "spear", "life"],
		"rewards": ["life", "sweep", "pierce", "shock", "tuna", "suppress", "guard", "horse", "airdrop"]},
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
static func draw_rewards(identity: String, random: RandomNumberGenerator) -> Array:
	var pool: Array = DATA[identity].rewards.duplicate()
	var result: Array = []
	for pick in 2:
		var total = 0
		for id in pool: total += reward_weight(identity, id)
		var ticket = random.randi_range(0, total - 1)
		for i in pool.size():
			ticket -= reward_weight(identity, pool[i])
			if ticket < 0:
				result.append(pool.pop_at(i))
				break
	result.append(COMMON[random.randi_range(0, COMMON.size() - 1)])
	return result
