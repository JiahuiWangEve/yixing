extends RefCounted
# Opening identity owns the initial deck and rewards; stance never changes the pool.
const COMMON = ["sword", "spear", "diagonal", "push", "stun", "breath"]
const DATA = {
	"king": {"name": "帅", "lives": 2,
		"deck": ["sword", "sword", "sword", "spear", "spear", "horse", "life", "stun"],
		"rewards": ["life", "sweep", "pierce", "shock", "tuna"]},
	"horse": {"name": "马", "lives": 1,
		"deck": ["sword", "sword", "spear", "horse", "horse", "straight", "straight", "pursuit"],
		"rewards": ["horse", "straight", "swap", "pursuit"]},
	"artillery": {"name": "炮车", "lives": 1,
		"deck": ["sword", "spear", "straight", "stake", "cannon_shot", "cannon_shot", "deploy", "pack"],
		"rewards": ["stake", "cannon_shot", "deploy", "pack"]}
}
