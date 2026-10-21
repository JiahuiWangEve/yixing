extends RefCounted

const STAGES = [
	{"name": "初入棋局", "pieces": [["p", 2, 3], ["p", 6, 3], ["p", 4, 3]]}, 
	{"name": "双卒象阵", "pieces": [["p", 2, 3], ["p", 6, 3], ["e", 2, 0]]}, 
	{"name": "象守援军", "pieces": [["p", 2, 3], ["p", 6, 3], ["p", 4, 3], ["e", 2, 0]]}, 
	{"name": "隔山炮阵", "pieces": [["p", 2, 3], ["p", 6, 3], ["c", 1, 1]]}, 
	{"name": "长车压境", "pieces": [["p", 2, 3], ["p", 6, 3], ["r", 7, 1]]}, 
	{"name": "车马炮合围", "pieces": [["p", 4, 3], ["h", 2, 2], ["c", 1, 1], ["r", 7, 1]]}
]
const LAST_STAGE = 6
static func setup(game):
	if game.route.active() and game.route.state.pending >= 0:
		var node = game.route.state.nodes[game.route.state.pending]
		if node.get("encounter", {}) != {}:
			game.ENCOUNTERS.setup(game, node.encounter)
			return
	var config = STAGES[clampi(game.stage, 1, LAST_STAGE) - 1]
	game.add_enemy("g", Vector2i(4, 0), 3)
	for spec in config.pieces:
		game.add_enemy(spec[0], Vector2i(spec[1], spec[2]), 2 if spec[0] == "p" else 3)
static func stage_name(stage: int) -> String:
	return STAGES[clampi(stage, 1, LAST_STAGE) - 1].name
