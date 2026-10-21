extends RefCounted
# Read-only battle information. Drawing/inspection never prepares an enemy phase,
# calls tutorial.allows(), samples RNG, or applies hypothetical attacks to game state.
const E = preload("res://encounters.gd")
const C2 = preload("res://chapter_two.gd")
const R = preload("res://rules.gd")
const T = preload("res://theme.gd")
const ATTACKS = ["sword", "sword_plus", "spear", "spear_plus", "diagonal", "cannon", "cannon_shot", "pierce", "pursuit", "shock", "advance", "retreat_strike", "knight_assault", "chain_assault", "airdrop", "sweep"]
const CREDIT_RULE = "每个敌方回合最多移动一次；移动或战术留守消耗1次加速，多余加速顺延。定身、堵路、攻击留位保留加速；镇四方延迟加速2轮。移动不额外攻击。"
const REVIVAL_RULE = "击倒后在原位留下残影，不挡路、不作炮架。经过2个完整玩家回合，原位空闲时满血复归；复归当轮不行动。敌将阵亡后取消。"
var game
var cue = ""
var cue_left = 0.0
var cue_is_log = false
var tag_cache_key: Array = []
var tag_cache: Array = []
var tag_cache_builds = 0

func _init(owner): game = owner
func tick(delta: float):
	cue_left = maxf(0.0, cue_left - delta)
	if cue_is_log and cue not in game.logs: cue_left = 0.0
func begin_battle():
	cue = "";cue_left = 0.0;cue_is_log = false
	var tags = mechanism_tags()
	if tags.is_empty(): return
	if E.is_chapter_two(game): cue = "增援按轮抵达；不屈击倒后会复归。" if tags.any(func(tag): return tag.key == "unyielding") else "厚血不改变走法，增援按轮抵达。"
	else: cue = "本阵：" + E.summary(game.encounter_state.config) + "。"
	cue += "悬停或长按标签查看。";cue_left = 6.0
func note_log(value: String):
	for prefix in ["残阵反扑", "旗卒渡河", "援马抵达", "本波援马取消", "下轮后方援马", "不屈", "第1波增援", "第2波增援", "第3波增援"]:
		if value.begins_with(prefix): cue = value;cue_left = 4.5;cue_is_log = true;return

func hp_segments(enemy: Dictionary) -> Array:
	var count = int(enemy.get("max_hp", game.enemy_health(enemy.kind)))
	var result: Array = []
	if count <= 1 or enemy.kind == "stake": return result
	for index in count: result.append(index < int(enemy.get("hp", count)))
	return result
func bleed_status(enemy: Dictionary) -> Dictionary:
	var this_end = 0;var next_end = 0
	for bleed in game.pending_bleeds:
		if int(bleed.enemy_uid) != int(enemy.get("uid", -1)): continue
		this_end += 1
		if int(bleed.amount) > 1: next_end += 1
	return {"this_end": this_end, "next_end": next_end}
func enemy_statuses(enemy: Dictionary) -> Array:
	var statuses: Array = []
	if enemy.kind == "stake": return statuses
	if enemy.get("heavy", false): statuses.append({"key": "heavy", "glyph": "重", "line": "厚血：只增加血量，不改变走法。", "color": T.GOLD})
	if enemy.get("unyielding", false): statuses.append({"key": "unyielding", "glyph": "复", "line": "不屈：击倒后经过2个完整玩家回合满血复归；原位被占则等待。", "color": T.GOLD})
	if enemy.get("reinforcement", false): statuses.append({"key": "reinforcement", "glyph": "援", "line": "增援棋子：计入场上增援数量上限。", "color": T.GOLD})
	if enemy.kind == "q": statuses.append({"key": "quick", "glyph": "疾", "line": "急行：每轮移动。", "color": T.DANGER})
	if enemy.get("signal", false): statuses.append({"key": "signal", "glyph": "旗", "line": "旗卒：" + E.RULE_TEXT.river_signal + (" 已触发。" if game.encounter_state.get("river_triggered", false) else " 尚未触发。"), "color": T.DANGER})
	if enemy.get("march_mark", false): statuses.append({"key": "march", "glyph": "步", "line": "连步标记：" + E.RULE_TEXT.double_step + " 当前正常移动进度%d/2。" % (int(enemy.get("march_normal_moves", enemy.get("normal_moves", 0))) % 2), "color": T.DANGER})
	var credits = E.available_action_credits(game, enemy, false)
	var rotation = E.has_rule(game, "palace_rotation") and int(enemy.uid) == E.selected_guard(game)
	if credits > 0 or rotation:
		var line = "加速×%d" % credits if credits > 0 else "轮防"
		if rotation: line += "；下轮加速+1"
		var delay = int(enemy.get("action_credit_delay", 0))
		if delay > 0: line += "；延迟%d轮" % delay
		line += "：后续移动提前，每轮最多移动一次，溢出保留。"
		statuses.append({"key": "credits", "glyph": "速", "line": line, "color": T.DANGER})
	elif enemy.get("bonus_pending", false): statuses.append({"key": "pending_credit", "glyph": "速", "line": "待加速：触发后提前移动，溢出保留。", "color": T.DANGER})
	if int(enemy.get("stun", 0)) > 0: statuses.append({"key": "stun", "glyph": "定", "line": "定身：还剩%d个敌方回合，不能攻击或移动。" % int(enemy.stun), "color": T.SAFE})
	var bleed = bleed_status(enemy)
	if bleed.this_end > 0:
		var line = "流血：本回合结束−%d" % bleed.this_end
		if bleed.next_end > 0: line += "，下回合结束−%d" % bleed.next_end
		statuses.append({"key": "bleed", "glyph": "血", "line": line + "。", "color": T.DANGER})
	return statuses
func player_statuses() -> Array:
	var result: Array = []
	if game.shield_charges > 0: result.append({"key": "guard", "glyph": "盾", "color": T.SAFE, "line": "固守：剩余%d次抵挡实际受击，不掉命、不撤退；下个玩家回合开始失效，不能抵挡空投自损。" % game.shield_charges})
	if game.reload_ready: result.append({"key": "reload", "glyph": "填", "color": T.GOLD, "line": "装填：本回合下次成功炮击伤害+1，若击杀则抽1张；无效目标不消耗，重复使用不叠加。"})
	if game.tuna_active or game.tuna_turns > 0: result.append({"key": "tuna", "glyph": "纳", "color": T.SAFE, "line": "吐纳：%s后续%d个玩家回合基础能量+1；再次使用延长3回合，不叠加增量。" % ["本回合已生效；" if game.tuna_active else "", game.tuna_turns]})
	if game.airdrop_recovery_turn > 0: result.append({"key": "recovery", "glyph": "休", "color": T.DANGER, "line": "空投休整：%s不能移动或出牌，敌方与被动效果照常结算。" % ("本回合" if game.recovery_active() else "下一玩家回合")})
	return result
func piece_rect(cell: Vector2i) -> Rect2:
	return Rect2(game.cell_pos(cell) - Vector2.ONE * game.CELL * 0.46, Vector2.ONE * game.CELL * 0.92)
func enemy_info(enemy: Dictionary) -> Dictionary:
	var lines: Array = []
	var title: String = "急行卒" if enemy.kind == "q" else game.piece_name(enemy.kind)
	if enemy.kind == "stake":
		title = "机关炮架" if enemy.get("permanent", false) else "木桩"
		lines.append("挡路并作炮架，不攻击。")
		lines.append("持续本场战斗。" if enemy.get("permanent", false) else "剩余%d回合；回合末减少1，归零消失。" % int(enemy.get("ttl", 3)))
	else:
		title += " · %d/%d血" % [int(enemy.get("hp", game.enemy_health(enemy.kind))), int(enemy.get("max_hp", game.enemy_health(enemy.kind)))]
		lines.append("移动倒计时：%d回合。" % E.effective_countdown(game, enemy))
		for status in enemy_statuses(enemy): lines.append(status.line)
	return {"key": "enemy:%s" % enemy.get("uid", enemy.pos), "title": title, "lines": lines, "anchor": piece_rect(enemy.pos)}
func player_info() -> Dictionary:
	var lines: Array = ["生命 %d；能量 %d。" % [game.lives, game.energy], "本回合主动位移 %d次。" % game.active_displacements]
	if game.player_skill == "artillery": lines.append("攻击姿态：正交走1格，炮击1费2伤。" if game.artillery_mode == "attack" else "行军姿态：正交走1～2格，炮击2费1伤。")
	for status in player_statuses(): lines.append(status.line)
	return {"key": "player", "title": "我方", "lines": lines, "anchor": piece_rect(game.player)}
func mechanism_tags() -> Array:
	var result: Array = []
	if not E.active(game): return result
	if E.is_chapter_two(game):
		var config: Dictionary = game.encounter_state.config
		var template: Dictionary = C2.TEMPLATES[config.id]
		var heavy = false;var unyielding = false
		for spec in template.pieces:
			heavy = heavy or bool(spec[4]);unyielding = unyielding or bool(spec[5])
		for wave in template.waves: heavy = heavy or bool(wave[1][4])
		if heavy: result.append({"key": "heavy", "label": "厚血", "title": "厚血", "lines": ["只增加血量，不改变走法；多血棋子的细条每格为1血，查看棋子可见当前/最大生命。"]})
		if unyielding:
			var lines: Array = [REVIVAL_RULE]
			for ghost in game.encounter_state.ghosts: lines.append(ghost_line(ghost))
			if game.encounter_state.cancelled: lines.append("战斗已结束，复归已取消。")
			result.append({"key": "unyielding", "label": "不屈", "title": "不屈复归", "lines": lines})
		var lines: Array = ["提前1轮预告；场上增援最多2枚，受阻最多延后2轮，仍受阻则取消。复归优先，增援当轮不行动；敌将阵亡后取消。"]
		for wave in game.encounter_state.waves:
			var definition: Array = template.waves[wave.index]
			var status: String = {"scheduled": "待抵达", "announced": "下轮末抵达", "blocked": "受阻", "arrived": "已抵达", "cancelled": "已取消"}.get(wave.status, wave.status)
			lines.append("第%d波：第%d轮末，%s%s。" % [int(wave.index) + 1, int(definition[0]), status, "（%s，已延后%d轮）" % [wave.reason, wave.blocked_phases] if wave.status == "blocked" else ("（%s）" % wave.reason if wave.status == "cancelled" else "")])
		result.append({"key": "waves", "label": "增援%d波" % template.waves.size(), "title": "有限增援", "lines": lines})
	else:
		for rule in game.encounter_state.config.rules:
			var lines: Array = [E.RULE_TEXT[rule], CREDIT_RULE]
			if rule == "last_stand": lines.append("当前：已触发。" if game.encounter_state.retaliated else "当前：尚未触发。")
			elif rule == "river_signal": lines.append("当前：已触发。" if game.encounter_state.river_triggered else "当前：尚未触发。")
			elif rule == "horse_relay": lines.append(E.status(game))
			elif rule == "palace_rotation":
				for enemy in game.enemies:
					if enemy.uid == E.selected_guard(game): lines.append("下一轮守军：%s（%d，%d）。" % [game.piece_name(enemy.kind), enemy.pos.x + 1, enemy.pos.y + 1])
			result.append({"key": rule, "label": E.RULE_NAMES[rule], "title": E.RULE_NAMES[rule], "lines": lines})
	return result
func tag_items() -> Array:
	var army: Array = []
	for enemy in game.enemies: army.append([enemy.get("uid", -1), enemy.kind, enemy.pos])
	var key = [game.encounter_state.hash(), army.hash(), game.tutorial.active, game.ui_size, game.mobile_layout, game.compact_landscape]
	if key == tag_cache_key: return tag_cache
	tag_cache_key = key;tag_cache_builds += 1
	var result = mechanism_tags()
	var origin = Vector2(24, 144)
	if game.compact_landscape: origin = Vector2(410, 82)
	elif game.mobile_layout: origin = Vector2(24, 95)
	var x = origin.x
	for item in result:
		var width = game.FONT.get_string_size(item.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 18
		item.anchor = Rect2(x, origin.y, width, 18);item.key = "mechanism:" + item.key
		x += width + 7
	tag_cache = result
	return tag_cache
func ghost_line(ghost: Dictionary) -> String:
	return "%s：原位（%d，%d），%s。" % [game.piece_name(ghost.enemy.kind), ghost.enemy.original_spawn.x + 1, ghost.enemy.original_spawn.y + 1, "原位被占，空闲后复归" if ghost.status == "blocked" else "还需%d次轮末结算" % maxi(0, int(ghost.ready_phase) - int(game.encounter_state.phases))]
func marker_info(marker: Dictionary) -> Dictionary:
	var lines: Array = [];var title = "增援预告"
	if marker.kind == "revival":
		title = "不屈残影"
		for ghost in game.encounter_state.ghosts:
			if ghost.enemy.uid == marker.uid:
				lines.append(ghost_line(ghost));lines.append("复归生命 %d / %d。" % [ghost.enemy.max_hp, ghost.enemy.max_hp]);break
		lines.append(REVIVAL_RULE)
	else:
		lines.append("出生格（%d，%d）；%s。" % [marker.pos.x + 1, marker.pos.y + 1, "受阻，等待空位或增援名额" if marker.status == "blocked" else "下轮末抵达"])
		for tag in mechanism_tags():
			if tag.key in ["waves", "horse_relay"]: lines.append_array(tag.lines)
	return {"key": "marker:%s:%s" % [marker.kind, marker.get("uid", marker.get("wave", 0))], "title": title, "lines": lines, "anchor": piece_rect(marker.pos)}
func markers() -> Array:
	if not E.active(game): return []
	var result = E.markers(game)
	var spawn: Vector2i = game.encounter_state.get("spawn_cell", Vector2i(-1, -1))
	if R.inside(spawn): result.append({"pos": spawn, "label": "援", "kind": "reinforcement", "status": "announced", "wave": 0})
	return result
func inspect_at(pos: Vector2) -> Dictionary:
	if game.screen != "game" or game.phase not in ["play", "discard"] or game.presentation.active() or game.card_picker.active: return {}
	for item in tag_items():
		if item.anchor.has_point(pos): return item
	if not game.BOARD_RECT.has_point(pos): return {}
	var cell: Vector2i = game.board_cell(pos)
	var info: Dictionary = {}
	var index = R.occupied(cell, game.enemies)
	if index >= 0: info = enemy_info(game.enemies[index])
	elif cell == game.player: info = player_info()
	for marker in markers():
		if marker.pos == cell:
			var marker_data = marker_info(marker)
			if info.is_empty(): info = marker_data
			else:
				info.lines.append(marker_data.title + "：")
				info.lines.append_array(marker_data.lines)
	if not info.is_empty():
		var current = current_preview(cell)
		if not current.is_empty(): info.lines.append_array(current.lines)
	return info

func _tutorial_allows_preview(index: int, target: Vector2i) -> bool:
	var tutorial = game.tutorial
	if not tutorial.active: return true
	if tutorial.lesson_complete or tutorial._retry_pending or tutorial._pending_step >= 0 or not tutorial._presentation_finished(): return false
	var spec: Dictionary = tutorial._steps[tutorial.step_index]
	if spec.get("free", false): return true
	return str(spec.action) == "play" and game.hand[index] == str(spec.get("card", "")) and (not spec.has("target") or target == spec.target)
func preview(index: int, target: Vector2i) -> Dictionary:
	if game.screen != "game" or game.phase != "play" or game.input_lock > 0 or game.navigation_lock > 0 or game.card_picker.active or game.presentation.active() or game.encounter_info_open: return {}
	if index < 0 or index >= game.hand.size() or not game.can_commit_card(index, target) or not _tutorial_allows_preview(index, target): return {}
	var id: String = game.hand[index]
	if id not in ATTACKS: return {}
	var affected: Array = [];var lines: Array = [];var amount = 1
	if id.ends_with("_plus"): amount = 2
	elif id == "cannon_shot": amount = (2 if game.artillery_mode == "attack" else 1) + (1 if game.reload_ready else 0)
	elif id == "chain_assault": amount = 1 + int(game.active_displacements)
	elif id == "airdrop": amount = 3
	elif id == "pierce": amount = 0
	var general_down = false
	for enemy in game.enemies:
		if enemy.kind != "g": continue
		var hit: bool = enemy.pos == target
		if id == "sweep": hit = game.in_neighbor_square(enemy.pos)
		elif id == "airdrop": hit = absi(enemy.pos.x - target.x) <= 1 and absi(enemy.pos.y - target.y) <= 1
		general_down = hit and amount >= int(enemy.get("hp", game.enemy_health(enemy.kind)))
	for enemy in game.enemies:
		if enemy.kind == "stake": continue
		var hit: bool = enemy.pos == target
		if id == "sweep": hit = game.in_neighbor_square(enemy.pos)
		elif id == "airdrop": hit = absi(enemy.pos.x - target.x) <= 1 and absi(enemy.pos.y - target.y) <= 1
		if not hit: continue
		var hp = int(enemy.get("hp", game.enemy_health(enemy.kind)))
		var down = amount >= hp
		affected.append({"uid": enemy.uid, "pos": enemy.pos, "damage": amount, "hp_before": hp, "hp_after": maxi(0, hp - amount), "down": down, "delayed": id == "pierce", "unyielding": enemy.get("unyielding", false)})
		if id == "pierce": lines.append("流血预览：立即0伤；新增本回合末1伤、下回合末1伤。目标死亡则余下流血失效。")
		else: lines.append("%s：%d伤 → %s%s。" % [game.piece_name(enemy.kind), amount, "击倒" if down else "剩余%d血" % (hp - amount), "（不屈，之后可复归）" if down and enemy.get("unyielding", false) and not general_down and not (id == "airdrop" and game.lives <= 1) else ""])
	if id == "airdrop": lines.append("自身扣1命：%s；下一玩家回合停行动。" % ("生命归零，直接失败，优先于敌将击倒" if game.lives <= 1 else "剩余%d命" % (game.lives - 1)))
	if id == "shock" and not affected.is_empty() and not affected[0].down:
		var destination: Vector2i = target + Vector2i(signi(target.x - game.player.x), signi(target.y - game.player.y))
		lines.append("目标推退1格。" if R.inside(destination) and R.occupied(destination, game.enemies) < 0 and destination != game.player else "目标后方受阻，不发生推退。")
	if id in ["advance", "knight_assault"] and not affected.is_empty(): lines.append("击倒后进入目标格。" if affected[0].down else "未击倒，不发生位移。")
	if id == "retreat_strike": lines.append("先后退1格，再造成伤害。")
	if id == "pursuit" or (id == "cannon_shot" and game.reload_ready): lines.append("击杀则按实际牌堆抽1张；抽牌内容不预判。")
	return {"card": id, "target": target, "affected": affected, "lines": lines, "self_damage": 1 if id == "airdrop" else 0, "self_defeat": id == "airdrop" and game.lives <= 1}
func current_preview(target: Vector2i) -> Dictionary:
	var index = int(game.selected)
	if game.gesture.dragging:
		if game.gesture.free_move or not game.BOARD_RECT.has_point(game.gesture.pointer) or game.pass_drop_rect().has_point(game.gesture.pointer): return {}
		index = game.hand_ids.find(game.gesture.uid)
	return preview(index, target)

func draw_enemy_status(enemy: Dictionary, point: Vector2):
	var scale = minf(1.0, game.CELL / 48.0)
	var badge = point + Vector2(0.36, -0.36) * game.CELL
	game.draw_circle(badge, 9 * scale, T.SAFE)
	var font_size = maxi(10, int(13 * scale))
	var text = str(E.effective_countdown(game, enemy))
	var width = game.FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	game.text_at(badge + Vector2(-width * 0.5, font_size * 0.36), text, font_size, T.LIGHT)
	var segments = hp_segments(enemy)
	if not segments.is_empty():
		var total = game.CELL * 0.78;var gap = minf(1.5, total / float(segments.size() * 5));var width_per = (total - gap * (segments.size() - 1)) / segments.size()
		var origin = point + Vector2(-total * 0.5, game.CELL * 0.47)
		for index in segments.size():
			var rect = Rect2(origin + Vector2(index * (width_per + gap), 0), Vector2(width_per, maxf(2.5, 3.5 * scale)))
			game.draw_rect(rect, T.DANGER if segments[index] else T.PAPER)
			if not segments[index]: game.draw_rect(rect, T.GRID, false, 0.6)
	_draw_statuses(enemy_statuses(enemy), point)
func status_markers(statuses: Array) -> Array:
	# The full list remains in inspection; excess statuses use one explicit +N
	# marker rather than overlapping or implying that missing slots are absent.
	var visible = statuses.slice(0, 4) if statuses.size() > 5 else statuses.duplicate()
	if statuses.size() > 5: visible.append({"key": "more", "glyph": "+%d" % (statuses.size() - 4), "color": T.INK})
	var offsets = [Vector2(-0.46, -0.26), Vector2(-0.48, 0), Vector2(-0.43, 0.27), Vector2(0.43, 0.27), Vector2(0.48, 0)]
	var size = clampf(game.CELL * 0.24, 8.0, 11.0)
	var result: Array = []
	for index in visible.size():
		var status: Dictionary = visible[index].duplicate()
		var extent = Vector2(size * (1.6 if status.key == "more" else 1.0), size)
		status.rect = Rect2(offsets[index] * game.CELL - extent * 0.5, extent)
		result.append(status)
	return result
func _draw_statuses(statuses: Array, point: Vector2):
	for status in status_markers(statuses):
		var rect: Rect2 = status.rect;rect.position += point
		if status.key == "more": game.panel(rect, status.color)
		else: game.draw_circle(rect.get_center(), rect.size.y * 0.5, status.color)
		var font_size = maxi(7, int(rect.size.y - 1))
		var width = game.FONT.get_string_size(status.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		game.text_at(rect.get_center() + Vector2(-width * 0.5, font_size * 0.36), status.glyph, font_size, T.LIGHT)
func draw_player_status(): _draw_statuses(player_statuses(), game.player_visual)
func draw_signals():
	for marker in markers():
		var point: Vector2 = game.cell_pos(marker.pos)
		var color: Color = T.GOLD if marker.kind == "revival" else T.DANGER
		game.draw_circle(point, game.CELL * 0.31, Color(T.PAPER, 0.3))
		game.draw_arc(point, game.CELL * 0.33, 0, TAU, 24, Color(color, 0.45), 1.2)
		var label: String = marker.label
		if marker.kind == "revival":
			for ghost in game.encounter_state.ghosts:
				if ghost.enemy.uid == marker.uid:
					game.text_at(point + Vector2(-game.CELL * 0.19, game.CELL * 0.16), game.piece_name(ghost.enemy.kind), int(game.CELL * 0.4), Color(color, 0.4));break
			label = "阻" if marker.status == "blocked" else str(marker.remaining_phases)
		var anchor = point + Vector2(game.CELL * 0.26, game.CELL * 0.30)
		game.panel(Rect2(anchor - Vector2(4, 10), Vector2(maxf(14, label.length() * 11 + 4), 15)), Color(T.PAPER, 0.9))
		game.text_at(anchor, label, 11, color)
	if E.has_rule(game, "palace_rotation"):
		for enemy in game.enemies:
			if enemy.uid == E.selected_guard(game): game.draw_arc(game.cell_pos(enemy.pos), game.CELL * 0.46, 0, TAU, 28, T.GOLD, 1.2)
func cue_visible() -> bool:
	if game.screen != "game" or game.phase not in ["play", "discard"] or cue_left <= 0 or cue.is_empty(): return false
	if game.tutorial.active or game.phase == "discard" or game.recovery_active() or R.threatened(game.player, game.enemies): return false
	return game.notice not in ["能量不足。", "本回合已使用移动牌。", "牌库与弃牌堆已空。"]
func should_show_context() -> bool:
	return not (game.mobile_layout and not game.compact_landscape and cue_visible())
func draw_hud():
	if game.phase not in ["play", "discard"]: return
	for item in tag_items():
		game.panel(item.anchor, T.BUTTON, T.BORDER)
		game.text_at(item.anchor.position + Vector2(9, 14), item.label, 13, T.INK)
	if not cue_visible(): return
	var rect = Rect2(24, 177, 345, 64)
	if game.compact_landscape: rect = Rect2(410, 108, 500, 22)
	elif game.mobile_layout:
		rect = Rect2(24, game.BOARD_RECT.end.y + 54, game.ui_size.x - 48, 20)
	if game.mobile_layout:
		var text = cue
		while text.length() > 1 and game.FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x > rect.size.x: text = text.left(text.length() - 2) + "…"
		game.text_at(rect.position + Vector2(0, 13), text, 12, T.HEADING)
	else: game.wrapped_text(cue, rect, 14, T.HEADING)
func draw_preview(target: Vector2i):
	var data = current_preview(target)
	if data.is_empty(): return
	for impact in data.affected:
		var point: Vector2 = game.cell_pos(impact.pos)
		game.draw_arc(point, game.CELL * 0.45, 0, TAU, 28, T.DANGER, 2)
		var label = "末1" if impact.delayed else ("-%d 倒" % impact.damage if impact.down else "-%d" % impact.damage)
		var size = maxi(9, mini(12, int(game.CELL * 0.3)))
		var width = game.FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var rect = Rect2(point + Vector2(-width * 0.5 - 3, -(size + 4) * 0.5), Vector2(width + 6, size + 4))
		game.panel(rect, T.DANGER)
		game.text_at(rect.position + Vector2(3, size + 1), label, size, T.LIGHT)
	if data.self_defeat:
		var p: Vector2 = game.cell_pos(target)
		game.text_at(p + Vector2(-24, -game.CELL * 0.52), "自损败局", 12, T.DANGER)
