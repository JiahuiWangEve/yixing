extends RefCounted
# Isolated local scenarios. This module never writes route, unlock or settings saves.
const Palette = preload("res://palette.gd")
const CATALOG = preload("res://card_catalog.gd")
const UPGRADES = preload("res://card_upgrades.gd")
const PROFILES = preload("res://start_profiles.gd")
const TREASURES = preload("res://treasure_system.gd")
const R = preload("res://rules.gd")
const SAVE_PATH = "user://training_presets_v1.dat"
const WEB_SAVE_KEY = "yixing.training.presets.v1"
const SCHEMA = 1
const MAX_PRESETS = 40
const TABS = ["角色", "宝物", "卡牌", "棋子"]
const PALETTE = [
	{"kind":"g", "label":"将"}, {"kind":"a", "label":"士"}, {"kind":"e", "label":"象"},
	{"kind":"h", "label":"马"}, {"kind":"h", "ai_role":"outrider", "label":"游骑"},
	{"kind":"h", "ai_role":"guard_horse", "label":"近卫骑"}, {"kind":"r", "label":"车"},
	{"kind":"c", "label":"炮"}, {"kind":"p", "label":"卒"}, {"kind":"q", "label":"急行卒"},
	{"kind":"stake", "label":"木桩"}, {"kind":"decoy", "label":"草人"}
]
var game
var face
var state: Dictionary = {}
var presets: Array = []
var finish_condition: String:
	get: return str(state.get("finish_condition", "general"))
	set(value): state["finish_condition"] = value
var playing = false
var loaded = false
var load_error = false
var saved_id = ""
var recent_id = ""
var message = ""
var dirty = false
var tab = 0
var tab_page = 0
var selected_piece = -2 # -2 none; -1 player; >=0 enemy
var place_index = 8
var tool = "place"
var modal = ""
var confirm_action = ""
var name_edit: LineEdit
var card_group = 0
var card_page = 0
var card_selected = ""
var card_pile = "hand"
var pile_selected = -1
var pile_page = 0
var preset_page = 0
var hit_regions: Array = []
var pointer = -2
var pointer_start = Vector2.ZERO
var pointer_dragged = false
var touch_seen = false
var scroll_origin = Vector2.ZERO
var name_pointer = -2
var touch_contacts: Dictionary = {}
var multitouch = false

func _init(owner):
	game = owner
	face = preload("res://card_face.gd").new(owner)
func is_playing() -> bool: return playing
func new_state() -> Dictionary:
	return {"name":"新演武", "player_skill":"king", "player":Vector2i(4,9), "lives":5, "energy":3,
		"artillery_mode":"march", "hand":PROFILES.DATA.king.deck.duplicate(), "deck":[], "enemies":[make_piece(0,Vector2i(4,0),1)],
		"treasure_ids":[], "free_step":true, "shuffle":false, "seed":20261023, "finish_condition":"general"}
func open():
	if playing: return_to_editor();return
	if not loaded: load_presets();loaded = true
	if state.is_empty(): state = new_state()
	game.cancel_gesture();game.screen = "training_editor"
	selected_piece = -2;modal = "";pointer = -2;hit_regions.clear()
	if not load_error: message = "独立演武，不影响征途、解锁或正式悔棋次数。"
	game.queue_redraw()
func create_new():
	state = new_state();saved_id = "";dirty = false;selected_piece = -2;tab_page = 0;modal = ""
	message = "新配置：选择棋子后，可连续点击空格摆放。";game.queue_redraw()
func changed():
	if state.has("snapshot"):
		state.erase("snapshot");message = "已改动配置，将以当前配置开始新演武。"
	dirty = true;game.queue_redraw()
func choose_role(role: String):
	if not PROFILES.DATA.has(role): return
	state.player_skill = role
	state.lives = int(PROFILES.DATA[role].lives)
	state.treasure_ids = state.treasure_ids.filter(func(id): return compatible_treasure(id))
	changed()
func compatible_treasure(id: String) -> bool:
	return id in TREASURES.training_ids_for(str(state.player_skill))
func make_piece(index: int, position: Vector2i, uid: int) -> Dictionary:
	var kind: String = PALETTE[index].kind
	var health = int({"g":3,"e":3,"h":2,"decoy":2}.get(kind,1))
	var period = 1 if kind == "q" else (2 if kind == "p" else 3)
	if kind in ["stake","decoy"]: period = 0
	var piece = {"uid":uid,"kind":kind,"pos":position,"hp":health,"max_hp":health,"cd":period,"period":period,"stun":0,
		"action_credits":0,"heavy":false,"unyielding":false,"original_spawn":position}
	if PALETTE[index].has("ai_role"): piece.ai_role = PALETTE[index].ai_role
	if kind == "stake": piece.permanent = true;piece.ttl = 3
	if kind == "decoy": piece.neutral = true
	return piece
func piece_label(piece: Dictionary) -> String:
	if piece.get("ai_role", "") == "outrider": return "游骑"
	if piece.get("ai_role", "") == "guard_horse": return "近卫骑"
	for entry in PALETTE:
		if entry.kind == piece.kind: return entry.label
	return str(piece.kind)
func place_at(cell: Vector2i):
	if not R.inside(cell): return
	var occupied = R.occupied(cell, state.enemies)
	if tool == "erase":
		if occupied >= 0: state.enemies.remove_at(occupied);selected_piece = -2;changed()
		return
	if cell == state.player: select_piece(-1);return
	if occupied >= 0: select_piece(occupied);return
	if tool == "player" or (tool == "select" and selected_piece == -1):
		state.player = cell;selected_piece = -1;tool = "select";changed();return
	if tool == "select" and selected_piece >= 0 and selected_piece < state.enemies.size():
		state.enemies[selected_piece].pos = cell;state.enemies[selected_piece].original_spawn = cell;changed();return
	if tool == "place" and state.enemies.size() < 89:
		if PALETTE[place_index].kind == "decoy" and state.enemies.any(func(e): return e.kind == "decoy"):
			message = "场上最多1个草人，请先移动或移除已有草人。";game.queue_redraw();return
		var uid = 1
		for piece in state.enemies: uid = maxi(uid,int(piece.uid)+1)
		state.enemies.append(make_piece(place_index,cell,uid));selected_piece = -2;changed()
func select_piece(index: int):
	selected_piece = index;tool = "select";tab_page = 0
	if game.mobile_layout: tab = 3
	game.queue_redraw()
func remove_selected():
	if selected_piece < 0 or selected_piece >= state.enemies.size(): return
	state.enemies.remove_at(selected_piece);selected_piece = -2;changed()
func play() -> bool:
	var error = validate_preset(state)
	if error.is_empty() and not state.has("snapshot") and finish_condition == "general" and not state.enemies.any(func(e): return e.kind == "g"):
		error = "击败将模式需要敌将；也可改为清敌或自由调试。"
	if not error.is_empty(): message = error;game.queue_redraw();return false
	modal = "";hide_name_edit();playing = true;game.start_training(state.duplicate(true));return true
func return_to_editor():
	if playing: game.stop_training()
	playing = false;game.screen = "training_editor";modal = "";hit_regions.clear()
	message = "已返回原配置，试演中的变化不会改动原预设。";game.queue_redraw()
func reset_play():
	if playing: game.reset_training()
func save_current_position():
	if not playing: return
	var captured = state.duplicate(true)
	captured.name = str(state.name).left(38) + " · 当前局面"
	captured.snapshot = game.history.capture().duplicate(true)
	captured.player = game.player;captured.player_skill = game.player_skill;captured.lives = maxi(1,game.lives);captured.energy = game.energy
	captured.artillery_mode = game.artillery_mode;captured.enemies = game.enemies.duplicate(true)
	captured.hand = game.hand.duplicate();captured.deck = game.deck.duplicate();captured.deck.reverse()
	for enemy in captured.enemies: enemy.erase("visual")
	var id = persist_preset(captured, "")
	if not id.is_empty(): game.notice = "当前完整局面已另存为演武预设（含牌堆、状态与随机数）。"
	else: game.notice = message
func validate_preset(value) -> String:
	if not value is Dictionary: return "预设格式无效。"
	for field in ["name","player_skill","artillery_mode","finish_condition"]:
		if not value.get(field) is String: return "预设缺少有效配置。"
	if value.name.is_empty() or value.name.length() > 48: return "名称需为1至48字。"
	if not PROFILES.DATA.has(value.player_skill) or value.artillery_mode not in ["march","attack"]: return "角色或姿态无效。"
	if value.finish_condition not in ["general","clear","free"]: return "结束条件无效。"
	if not value.get("player") is Vector2i or not R.inside(value.player): return "玩家位置不在棋盘上。"
	for field in ["lives","energy","seed"]:
		if not value.get(field) is int: return "数值配置无效。"
	if value.lives < 1 or value.lives > 999 or value.energy < 0 or value.energy > 999: return "命数或能量超出范围。"
	if not value.get("free_step") is bool or not value.get("shuffle") is bool: return "开局选项无效。"
	for field in ["hand","deck"]:
		if not value.get(field) is Array or value[field].size() > 200: return "牌堆超出上限。"
		for id in value[field]:
			if not id is String or not game.CARDS.has(id): return "预设包含当前版本不可用的卡牌。"
	if value.hand.count("decoy_card") > 1: return "手牌中最多保留1张草木皆兵。"
	for id in value.deck:
		if game.is_generated_card(id): return "宝物生成牌只能配置在手牌，不能加入牌库。"
	if not value.get("treasure_ids") is Array or value.treasure_ids.size() > TREASURES.DATA.size(): return "宝物配置无效。"
	var seen_treasures = []
	for id in value.treasure_ids:
		if not id is String or not TREASURES.DATA.has(id) or id in seen_treasures: return "宝物配置无效。"
		if id not in TREASURES.training_ids_for(value.player_skill): return "宝物与角色不兼容。"
		seen_treasures.append(id)
	if not value.get("enemies") is Array or value.enemies.size() > 89: return "棋子配置无效。"
	var positions = [value.player]
	var decoy_count = 0
	var uids = []
	for piece in value.enemies:
		if not piece is Dictionary or piece.get("kind", "") not in ["g","a","e","h","r","c","p","q","stake","decoy"]: return "棋子类型无效。"
		if not piece.get("pos") is Vector2i or not R.inside(piece.pos) or piece.pos in positions: return "棋子重叠或超出棋盘。"
		positions.append(piece.pos)
		if piece.kind == "decoy": decoy_count += 1
		if decoy_count > 1: return "场上最多配置1个草人。"
		for field in ["uid","hp","cd","period","stun"]:
			if not piece.get(field) is int or piece[field] < (1 if field in ["uid","hp"] else 0) or piece[field] > 999999: return "棋子数值无效。"
		if piece.uid in uids or piece.hp > 999 or piece.cd > 99 or piece.period > 99 or piece.stun > 99: return "棋子数值重复或超出范围。"
		uids.append(piece.uid)
		if piece.get("ai_role", "") not in ["", "outrider", "guard_horse"] or (piece.has("ai_role") and piece.kind != "h"): return "棋子职责无效。"
		for field in ["heavy","unyielding","permanent"]:
			if piece.has(field) and not piece[field] is bool: return "棋子特性无效。"
		if piece.has("max_hp") and (not piece.max_hp is int or piece.max_hp < piece.hp or piece.max_hp > 999): return "棋子最大生命须不小于当前生命，且不超过999。"
		for field in ["action_credits","action_credit_delay","ttl"]:
			if piece.has(field) and (not piece[field] is int or piece[field] < 0 or piece[field] > 999999): return "棋子状态数值无效。"
	if value.has("snapshot"):
		var snap = value.snapshot
		if not snap is Dictionary or not snap.get("rng_state") is int: return "完整局面快照无效。"
		for field in game.HISTORY.FIELDS:
			if not snap.has(field): return "完整局面缺少必要状态。"
			if typeof(snap[field]) != typeof(game.get(field)):
				if not ((snap[field] is int or snap[field] is float) and (game.get(field) is int or game.get(field) is float)): return "完整局面状态类型无效。"
		if snap.phase not in ["play","discard","dead","win","reward"] or snap.lives < 0 or snap.turn < 1: return "完整局面阶段无效。"
		if not TREASURES.valid_battle_state(snap.treasure_battle): return "完整局面宝物状态无效。"
		var snapshot_config = value.duplicate(true)
		snapshot_config.erase("snapshot")
		for field in ["player_skill","player","artillery_mode","hand","deck","enemies","energy"]: snapshot_config[field] = snap[field]
		snapshot_config.lives = maxi(1,snap.lives)
		var snapshot_error = validate_preset(snapshot_config)
		if not snapshot_error.is_empty(): return snapshot_error
		if not snap.hand_ids is Array or snap.hand_ids.size() != snap.hand.size() or snap.next_card_uid < 1 or snap.next_enemy_uid < 1: return "完整局面实体编号无效。"
		var card_uids = []
		for uid in snap.hand_ids:
			if not uid is int or uid < 1 or uid >= snap.next_card_uid or uid in card_uids: return "完整局面卡牌实体编号无效。"
			card_uids.append(uid)
		for piece in snap.enemies:
			if piece.uid >= snap.next_enemy_uid: return "完整局面棋子实体编号无效。"
		for field in ["enemies","deck","discard","hand","hand_ids","collection","pending_bleeds","logs","rewards"]:
			if not snap[field] is Array or snap[field].size() > 2000: return "完整局面状态无效。"
		for field in ["treasure_battle","encounter_state"]:
			if not snap[field] is Dictionary: return "完整局面状态无效。"
		for field in ["deck","discard","hand","collection"]:
			for id in snap[field]:
				if not id is String or not game.CARDS.has(id): return "完整局面含不可用卡牌。"
	return ""
func load_presets():
	presets = [];recent_id = "";load_error = false
	var data = null
	if OS.has_feature("web"):
		var encoded = _read_web_value()
		if encoded is String and not encoded.is_empty():
			if encoded.length() > 5592410: load_error = true
			else: data = bytes_to_var(Marshalls.base64_to_raw(encoded))
	if data == null and not load_error:
		if not FileAccess.file_exists(SAVE_PATH): return
		var file = FileAccess.open(SAVE_PATH,FileAccess.READ)
		if file == null or file.get_length() > 4194304: load_error = true
		else: data = file.get_var(false);file.close()
	if load_error or not data is Dictionary or data.get("version") != SCHEMA or not data.get("presets") is Array or data.get("presets",[]).size() > MAX_PRESETS:
		load_error = true;message = "已有演武预设无法读取，暂不覆盖；正式存档未受影响。";return
	for entry in data.presets.slice(0,MAX_PRESETS):
		if entry is Dictionary and entry.get("id") is String and validate_preset(entry.get("data")).is_empty(): presets.append(entry)
		else: load_error = true
	if load_error: message = "部分旧演武预设无效，保留原文件，暂不覆盖。"
	recent_id = str(data.get("recent_id",""))
func write_presets() -> bool:
	if load_error: message = "已有演武预设无法读取，为避免覆盖暂不保存。";return false
	var data = {"version":SCHEMA,"presets":presets,"recent_id":recent_id}
	var temporary = SAVE_PATH + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	var local_saved = false
	if file != null:
		file.store_var(data,false);file.flush();var error = file.get_error();file.close()
		if error == OK: local_saved = DirAccess.rename_absolute(temporary,SAVE_PATH) == OK
	var web_saved = false
	if OS.has_feature("web"):
		web_saved = _write_web_presets(data)
	if not local_saved and not web_saved: message = "本地保存不可用，配置仍保留在当前页面。";return false
	return true
func _read_web_value():
	return JavaScriptBridge.eval("(function(){try{return localStorage.getItem('"+WEB_SAVE_KEY+"')||'';}catch(e){return '';}})()")
func _write_web_value(encoded: String):
	return JavaScriptBridge.eval("(function(){try{localStorage.setItem('"+WEB_SAVE_KEY+"',"+JSON.stringify(encoded)+");return true;}catch(e){return false;}})()")
func _write_web_presets(data: Dictionary) -> bool:
	var encoded = Marshalls.raw_to_base64(var_to_bytes(data))
	# Confirm the committed payload, not the bridge's write return value. Rolling
	# back memory after a committed write would let the next save lose that preset.
	_write_web_value(encoded)
	var committed = _read_web_value()
	return committed is String and committed == encoded
func persist_preset(value: Dictionary, replace_id: String) -> String:
	var error = validate_preset(value)
	if not error.is_empty(): message = error;return ""
	var old = presets.duplicate(true);var old_recent = recent_id
	var index = -1
	for i in presets.size():
		if presets[i].id == replace_id: index = i;break
	if index < 0 and presets.size() >= MAX_PRESETS: message = "最多保存40份预设，请先删除不用的预设。";return ""
	var id = replace_id if index >= 0 else str(Time.get_unix_time_from_system()) + "_" + str(Time.get_ticks_usec())
	var entry = {"id":id,"data":value.duplicate(true)}
	if index >= 0: presets[index] = entry
	else: presets.append(entry)
	recent_id = id
	if not write_presets(): presets = old;recent_id = old_recent;return ""
	message = "已保存「%s」，只保存在当前浏览器或设备。" % value.name
	return id
func save_named(name: String, copy: bool = false) -> bool:
	var named = state.duplicate(true);named.name = name.strip_edges().left(48)
	var id = persist_preset(named,"" if copy else saved_id)
	if id.is_empty(): return false
	state = named;saved_id = id;dirty = false;return true
func load_preset(id: String) -> bool:
	for entry in presets:
		if entry.id == id:
			state = entry.data.duplicate(true);saved_id = id;recent_id = id;dirty = false;selected_piece = -2;modal = "";write_presets()
			message = "已打开「%s」。" % state.name;game.queue_redraw();return true
	message = "暂无最近预设。";return false
func delete_preset(id: String) -> bool:
	var old = presets.duplicate(true);var old_recent = recent_id
	for i in presets.size():
		if presets[i].id == id:
			presets.remove_at(i)
			if recent_id == id: recent_id = str(presets.back().id) if not presets.is_empty() else ""
			if not write_presets(): presets = old;recent_id = old_recent;return false
			if saved_id == id: saved_id = "";dirty = true
			message = "预设已删除，当前编辑配置仍保留。";return true
	return false
func hide_name_edit():
	name_pointer = -2
	if is_instance_valid(name_edit): name_edit.hide();name_edit.release_focus()
func open_name(mode: String):
	modal = mode;message = ""
	if not is_instance_valid(name_edit):
		name_edit = LineEdit.new();name_edit.max_length = 48;name_edit.add_theme_font_override("font",game.FONT)
		name_edit.add_theme_font_size_override("font_size",20);game.add_child(name_edit)
		name_edit.text_submitted.connect(func(_value): _activate("name_confirm"))
	name_edit.text = str(state.name) + (" 副本" if mode == "copy" else "")
	name_edit.position = Vector2(36,game.ui_size.y * 0.4);name_edit.size = Vector2(game.ui_size.x - 72,52)
	name_edit.show();name_edit.grab_focus();name_edit.select_all();game.queue_redraw()
func open_confirm(action: String): modal = "confirm";confirm_action = action;game.queue_redraw()
func button_rect(id: String) -> Rect2:
	for hit in hit_regions:
		if hit.id == id: return hit.rect
	return Rect2()
func board_geometry() -> Dictionary:
	if not game.mobile_layout: return {"origin":Vector2(424,142),"cell":50.0}
	if game.compact_landscape: return {"origin":Vector2(50,108),"cell":35.0}
	return {"origin":Vector2(240 - 4 * minf(38,(game.ui_size.y-414)/9),100),"cell":minf(38,(game.ui_size.y-414)/9)}
func board_bounds() -> Rect2:
	var geometry = board_geometry();return Rect2(geometry.origin-Vector2.ONE*20,Vector2(8,9)*geometry.cell+Vector2.ONE*40)
func panel_rect() -> Rect2:
	if not game.mobile_layout: return Rect2(20,138,338,game.ui_size.y-252)
	if game.compact_landscape: return Rect2(390,142,550,game.ui_size.y-230)
	var y = board_bounds().end.y+62
	return Rect2(16,y,game.ui_size.x-32,maxf(70,game.ui_size.y-y-110))
func tabs_y() -> float:
	if not game.mobile_layout: return 86
	if game.compact_landscape: return 88
	return board_bounds().end.y+12
func _button(id: String, rect: Rect2, label: String, selected: bool = false, enabled: bool = true, size: int = 17):
	game.panel(rect,Palette.SURFACE if enabled else Palette.HAND,Palette.ACCENT if selected else Palette.BORDER)
	var color = Palette.INK if enabled else Palette.INK_SECONDARY
	while label.length() > 1 and game.FONT.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x > rect.size.x-12:
		label = label.left(label.length()-2)+"…"
	var width = game.FONT.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	game.text_at(rect.position+Vector2(maxf(6,(rect.size.x-width)/2),rect.size.y/2+size*0.35),label,size,color)
	if enabled: hit_regions.append({"id":id,"rect":rect})
func _label(pos: Vector2, text: String, size: int = 16, color: Color = Palette.INK_SECONDARY): game.text_at(pos,text,size,color)
func _wrap(pos: Vector2, text: String, width: float, size: int = 16, max_lines: int = 4):
	var lines: Array = face._wrapped(text,width,size)
	for i in mini(lines.size(),max_lines): _label(pos+Vector2(0,i*(size+6)),str(lines[i]),size)
func _stepper(key: String, rect: Rect2, title: String, value: int):
	var suffix = " · 调试" if key == "lives" and value > PROFILES.life_limit(state.player_skill) else ""
	_label(rect.position+Vector2(0,27),title+"  "+str(value)+suffix,17,Palette.INK)
	_button("adjust:"+key+":-1",Rect2(rect.end.x-104,rect.position.y,48,42),"−",false,true,22)
	_button("adjust:"+key+":1",Rect2(rect.end.x-48,rect.position.y,48,42),"+",false,true,22)
func draw():
	hit_regions.clear()
	game.draw_rect(Rect2(Vector2.ZERO,game.ui_size),Palette.PAPER)
	_label(Vector2(20,42),"演武场",28,Palette.INK)
	_label(Vector2(124,40),str(state.get("name","新演武")).left(7 if game.mobile_layout and not game.compact_landscape else 34) + (" · 未保存" if dirty else ""),17)
	_button("home",Rect2(game.ui_size.x-92,14,76,42),"首页")
	if not game.mobile_layout:
		_button("new",Rect2(20,62,102,34),"新建",false,true,16)
		_button("presets",Rect2(132,62,102,34),"预设库",false,true,16)
		_button("recent",Rect2(244,62,114,34),"打开最近",false,true,16)
	else:
		_button("new",Rect2(20,54,64,32),"新建",false,true,14)
		_button("presets",Rect2(92,54,84,32),"预设库",false,true,14)
		_button("recent",Rect2(184,54,96,32),"打开最近",false,true,14)
	_draw_board()
	var panel = panel_rect()
	var tx = panel.position.x
	for i in 4:
		var width = (panel.size.x-18)/4
		_button("tab:"+str(i),Rect2(tx+i*(width+6),tabs_y()+(16 if not game.mobile_layout else 0),width,38),TABS[i],tab == i)
	game.panel(panel,Palette.SURFACE,Palette.BORDER)
	if game.mobile_layout and not game.compact_landscape and panel.size.y < 190:
		_draw_mobile_summary(panel.grow(-12))
	elif game.mobile_layout and selected_piece >= -1 and tab == 3: _draw_attributes(panel.grow(-12))
	else:
		match tab:
			0: _draw_role(panel.grow(-12))
			1: _draw_treasures(panel.grow(-12))
			2: _draw_piles(panel.grow(-12))
			3: _draw_palette(panel.grow(-12))
	if not game.mobile_layout:
		var attributes = Rect2(914,102,346,game.ui_size.y-216)
		game.panel(attributes,Palette.SURFACE,Palette.BORDER);_draw_attributes(attributes.grow(-16))
		_label(Vector2(404,650),"先选棋子，再点空格：连续摆放。",16)
		_label(Vector2(404,676),"点已有棋子可改属性，再点空格移动。",16)
		_label(Vector2(404,702),"玩家独立摆放；每个位置只能有一枚棋子。",16)
	var foot = game.ui_size.y-66
	_button("save",Rect2(16,foot,126,50),"保存预设")
	_button("options",Rect2(150,foot,126,50),"试演选项")
	_button("play",Rect2(284,foot,game.ui_size.x-300,50),"开始试演",true)
	_wrap(Vector2(20,foot-30),message,game.ui_size.x-40,14,1)
	if not modal.is_empty(): _draw_modal()
func _draw_board():
	var geometry = board_geometry();var origin: Vector2 = geometry.origin;var cell: float = geometry.cell
	game.panel(board_bounds(),Palette.BOARD,Palette.BORDER_STRONG)
	for y in 10: game.draw_line(origin+Vector2(0,y*cell),origin+Vector2(8*cell,y*cell),Palette.GRID,1)
	for x in 9:
		game.draw_line(origin+Vector2(x*cell,0),origin+Vector2(x*cell,4*cell),Palette.GRID,1)
		game.draw_line(origin+Vector2(x*cell,5*cell),origin+Vector2(x*cell,9*cell),Palette.GRID,1)
	for y in [0,7]:
		game.draw_line(origin+Vector2(3*cell,y*cell),origin+Vector2(5*cell,(y+2)*cell),Palette.GRID,1)
		game.draw_line(origin+Vector2(5*cell,y*cell),origin+Vector2(3*cell,(y+2)*cell),Palette.GRID,1)
	_label(origin+Vector2(cell*2.7,cell*4.65),"楚 河    汉 界",16,Palette.GRID)
	for i in state.enemies.size():
		var piece: Dictionary = state.enemies[i]
		_draw_piece(origin+Vector2(piece.pos)*cell,cell,piece_label(piece),selected_piece == i,false)
	_draw_piece(origin+Vector2(state.player)*cell,cell,{"king":"帅","horse":"马","artillery":"炮"}.get(state.player_skill,"帅"),selected_piece == -1,true)
func _draw_piece(at: Vector2, cell: float, label: String, selected: bool, player: bool):
	game.draw_circle(at,cell*0.43,Palette.SURFACE)
	game.draw_arc(at,cell*0.43,0,TAU,40,Palette.ACCENT if selected or player else Palette.GRID,3 if selected else 1.5)
	var size = 20 if label.length() == 1 else 11
	var width = game.FONT.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	_label(at+Vector2(-width/2,size*0.36),label,size,Palette.ACCENT if player else Palette.INK)
func _draw_mobile_summary(rect: Rect2):
	var summary = ""
	match tab:
		0: summary = "%s · %d命 · %d能量" % [{"king":"将","horse":"马","artillery":"炮车"}.get(state.player_skill,"将"),state.lives,state.energy]
		1: summary = "已装备 %d 件兼容宝物" % state.treasure_ids.size()
		2: summary = "手牌 %d 张 · 牌库 %d 张" % [state.hand.size(),state.deck.size()]
		3:
			if selected_piece == -1: summary = "已选玩家 · 再点空格移动"
			elif selected_piece >= 0: summary = "已选%s · 再点空格移动" % piece_label(state.enemies[selected_piece])
			else: summary = "摆放：" + ("橡皮擦" if tool == "erase" else str(PALETTE[place_index].label))
	_label(rect.position+Vector2(0,22),summary,17,Palette.INK)
	_button("expand_tab",Rect2(rect.position.x,rect.position.y+34,rect.size.x,38),"展开"+TABS[tab]+"设置",false,true,16)
func _draw_role(rect: Rect2):
	var roles = ["king","horse","artillery"]
	for i in 3:
		var width = (rect.size.x-12)/3
		_button("role:"+roles[i],Rect2(rect.position+Vector2(i*(width+6),0),Vector2(width,40)),["将","马","炮车"][i],state.player_skill == roles[i])
	var y = rect.position.y+50
	_stepper("lives",Rect2(rect.position.x,y,rect.size.x,42),"命数",state.lives)
	if rect.size.y >= 150:
		_stepper("energy",Rect2(rect.position.x,y+48,rect.size.x,42),"能量",state.energy)
	if rect.size.y >= 210:
		_button("player",Rect2(rect.position.x,y+100,rect.size.x,42),"摆放玩家 · 点一个空格",tool == "player")
		_button("stance",Rect2(rect.position.x,y+150,rect.size.x,42),"炮车姿态："+("行军" if state.artillery_mode == "march" else "攻击"),false,state.player_skill == "artillery")
		_wrap(Vector2(rect.position.x,y+218),"三种角色均可演武，不改变正式解锁。切换角色保留已摆好的棋盘。",rect.size.x,16,2 if game.compact_landscape else 3)
	else:
		_button("role_details",Rect2(rect.end.x-96,rect.end.y-36,96,36),"更多属性",false,true,14)
func _draw_treasures(rect: Rect2):
	var ids = TREASURES.DATA.keys()
	var rows = maxi(1,int((rect.size.y-44)/58))
	var pages = maxi(1,ceili(float(ids.size())/rows));tab_page = clampi(tab_page,0,pages-1)
	for row in rows:
		var index = tab_page*rows+row
		if index >= ids.size(): break
		var id: String = ids[index];var allowed = compatible_treasure(id)
		var chosen = id in state.treasure_ids
		_button("treasure:"+id,Rect2(rect.position+Vector2(0,row*58),Vector2(rect.size.x,50)),("✓ " if chosen else "")+str(TREASURES.DATA[id].name)+( " · 不兼容" if not allowed else ""),chosen,allowed,16)
	_page_controls(rect,"tab_page",tab_page,pages)
func _draw_palette(rect: Rect2):
	var columns = 3
	var rows = maxi(1,int((rect.size.y-94)/48));var per_page = rows*columns
	var pages = ceili(float(PALETTE.size())/per_page);tab_page = clampi(tab_page,0,pages-1)
	for slot in per_page:
		var index = tab_page*per_page+slot
		if index >= PALETTE.size(): break
		var width = (rect.size.x-12)/3
		_button("piece:"+str(index),Rect2(rect.position+Vector2((slot%3)*(width+6),(slot/3)*48),Vector2(width,42)),PALETTE[index].label,tool == "place" and place_index == index,true,16)
	var bottom = rect.end.y-88
	_button("player",Rect2(rect.position.x,bottom,rect.size.x/2-4,38),"摆玩家",tool == "player",true,15)
	_button("erase",Rect2(rect.position.x+rect.size.x/2+4,bottom,rect.size.x/2-4,38),"橡皮擦",tool == "erase",true,15)
	_page_controls(rect,"tab_page",tab_page,pages)
func _draw_attributes(rect: Rect2):
	if selected_piece == -2:
		_label(rect.position+Vector2(0,24),"所选棋子",22,Palette.INK)
		_wrap(rect.position+Vector2(0,64),"点击棋盘上的棋子查看属性。选中后点击空格可搬移；使用橡皮擦可连续删除。",rect.size.x,17,6)
		return
	var player = selected_piece == -1
	var piece = {} if player else state.enemies[selected_piece]
	_label(rect.position+Vector2(0,24),"玩家" if player else piece_label(piece),22,Palette.INK)
	_button("unselect",Rect2(rect.end.x-80,rect.position.y,80,34),"取消选择",false,true,14)
	var rows: Array = ["lives","energy"] if player else ["hp","cd","period","stun","action_credits"]
	var labels = {"lives":"命数","energy":"能量","hp":"生命","cd":"移动倒计时","period":"移动间隔","stun":"定身回合","action_credits":"加速次数"}
	var max_rows = maxi(1,int((rect.size.y-92)/46))
	var pages = ceili(float(rows.size())/max_rows);var page = clampi(tab_page,0,maxi(0,pages-1))
	for i in mini(rows.size()-page*max_rows,max_rows):
		var field: String = rows[page*max_rows+i]
		_stepper(field,Rect2(rect.position+Vector2(0,44+i*46),Vector2(rect.size.x,42)),labels[field],int(state.get(field,0) if player else piece.get(field,0)))
	if not game.mobile_layout:
		var y = rect.position.y+44+rows.size()*46
		if player:
			_button("stance",Rect2(rect.position.x,y,rect.size.x,42),"姿态："+("行军" if state.artillery_mode == "march" else "攻击"),false,state.player_skill == "artillery")
		else:
			for trait_name in ["heavy","unyielding"]:
				_button("trait:"+trait_name,Rect2(rect.position.x,y,rect.size.x,42),{"heavy":"厚血","unyielding":"不屈"}[trait_name]+"："+("开" if piece.get(trait_name,false) else "关"),piece.get(trait_name,false),piece.kind not in ["stake","decoy"]);y += 50
			if piece.kind == "stake": _button("trait:permanent",Rect2(rect.position.x,y,rect.size.x,42),"永久木桩："+("开" if piece.get("permanent",false) else "关"),piece.get("permanent",false));y += 50
			_button("remove",Rect2(rect.position.x,y,rect.size.x,42),"删除所选棋子")
		_wrap(Vector2(rect.position.x,rect.end.y-70),"生命、倒计时与既有特性仅作用于本次演武。",rect.size.x,16,3)
	else:
		_button("attributes",Rect2(rect.position.x,rect.end.y-40,rect.size.x/2-4,38),"完整属性",false,true,15)
		_button("remove" if not player else "player",Rect2(rect.position.x+rect.size.x/2+4,rect.end.y-40,rect.size.x/2-4,38),"删除棋子" if not player else "移动玩家",false,true,15)
func _draw_piles(rect: Rect2):
	_label(rect.position+Vector2(0,24),"起始手牌 %d · 牌库 %d" % [state.hand.size(),state.deck.size()],19,Palette.INK)
	_button("cards:hand",Rect2(rect.position+Vector2(0,40),Vector2(rect.size.x,44)),"编辑起始手牌")
	_button("cards:deck",Rect2(rect.position+Vector2(0,94),Vector2(rect.size.x,44)),"编辑牌库 · 顶端先抽")
	if rect.size.y >= 210: _wrap(rect.position+Vector2(0,176),"每张都是独立实体，可重复加入、强化、删除和调整顺序。默认手牌与抽牌顺序固定。",rect.size.x,16,4)
func _page_controls(rect: Rect2, prefix: String, page: int, pages: int):
	if pages <= 1: return
	_button(prefix+":-1",Rect2(rect.position.x,rect.end.y-38,62,36),"上页",false,page>0,14)
	_label(Vector2(rect.position.x+76,rect.end.y-13),"%d / %d" % [page+1,pages],15)
	_button(prefix+":1",Rect2(rect.end.x-62,rect.end.y-38,62,36),"下页",false,page<pages-1,14)
func _draw_modal():
	game.draw_rect(Rect2(Vector2.ZERO,game.ui_size),Color(Palette.PAPER,0.98))
	hit_regions.clear()
	_button("close",Rect2(game.ui_size.x-100,14,84,42),"返回")
	if modal == "cards": _draw_cards_modal();return
	if modal == "presets": _draw_presets_modal();return
	if modal in ["save","rename","copy"]:
		_label(Vector2(28,64),{"save":"保存演武预设","rename":"重命名预设","copy":"另存副本"}[modal],26,Palette.INK)
		_wrap(Vector2(36,game.ui_size.y*0.4-32),"名称只用于本机预设，最多48字。",game.ui_size.x-72,17,2)
		_button("name_confirm",Rect2(36,game.ui_size.y*0.4+70,game.ui_size.x-72,48),"确认保存",true)
		_wrap(Vector2(36,game.ui_size.y*0.4+148),message,game.ui_size.x-72,17,3)
		return
	if modal == "confirm":
		_label(Vector2(28,64),"请确认",26,Palette.INK)
		var label = "删除当前预设？此操作不能撤销。" if confirm_action == "delete" else "当前未保存的更改将丢失，是否继续？"
		_wrap(Vector2(28,140),label,game.ui_size.x-56,20,4)
		_button("confirm",Rect2(28,260,game.ui_size.x-56,50),"确认继续",true)
		return
	if modal == "tab_drawer":
		_label(Vector2(28,64),TABS[tab]+"配置",26,Palette.INK)
		var drawer = Rect2(28,104,game.ui_size.x-56,game.ui_size.y-138)
		match tab:
			0: _draw_role(drawer)
			1: _draw_treasures(drawer)
			2: _draw_piles(drawer)
			3: _draw_palette(drawer)
		return
	if modal == "attributes":
		_label(Vector2(28,64),"棋子属性",26,Palette.INK)
		_draw_full_attributes();return
	_label(Vector2(28,64),"试演选项",26,Palette.INK)
	var width = minf(600,game.ui_size.x-48);var x = (game.ui_size.x-width)/2
	_button("free_step",Rect2(x,108,width,48),"自动提供免费移动："+("开" if state.free_step else "关"),state.free_step)
	_button("shuffle",Rect2(x,168,width,48),"开局洗牌："+("开" if state.shuffle else "关 · 固定牌序"),state.shuffle)
	var labels = {"general":"击败将","clear":"清除全部敌子","free":"自由调试"}
	for i in 3:
		var option = ["general","clear","free"][i]
		_button("finish:"+option,Rect2(x,238+i*58,width,48),"结束条件 · "+labels[option],finish_condition == option)
	_stepper("seed",Rect2(x,426,width,42),"随机种子",state.seed)
	_wrap(Vector2(x,500),"重置试演会恢复同一初始局面与随机数。自由调试不因清敌而结束；清敌与自由模式无需放置敌将。",width,17,5)
func _draw_full_attributes():
	var rect = Rect2(28,96,game.ui_size.x-56,game.ui_size.y-122)
	var player = selected_piece == -1
	var piece = {} if player else state.enemies[selected_piece]
	_button("choose_piece",Rect2(160,22,136,40),"继续摆放",false,true,16)
	var rows = ["lives","energy"] if player else ["hp","cd","period","stun","action_credits"]
	var labels = {"lives":"命数","energy":"能量","hp":"生命","cd":"移动倒计时","period":"移动间隔","stun":"定身回合","action_credits":"加速次数"}
	var y = rect.position.y
	for field in rows:
		_stepper(field,Rect2(rect.position.x,y,rect.size.x,44),labels[field],int(state.get(field,0) if player else piece.get(field,0)));y += 52
	if player:
		_button("stance",Rect2(rect.position.x,y,rect.size.x,44),"姿态："+("行军" if state.artillery_mode == "march" else "攻击"),false,state.player_skill == "artillery")
		_button("player",Rect2(rect.position.x,y+56,rect.size.x,44),"移动玩家 · 选择空格")
	else:
		for trait_name in ([] if piece.kind in ["stake","decoy"] else ["heavy","unyielding"]):
			_button("trait:"+trait_name,Rect2(rect.position.x,y,rect.size.x,44),{"heavy":"厚血","unyielding":"不屈"}[trait_name]+"："+("开" if piece.get(trait_name,false) else "关"),piece.get(trait_name,false),piece.kind not in ["stake","decoy"]);y += 52
		if piece.kind == "stake": _button("trait:permanent",Rect2(rect.position.x,y,rect.size.x,44),"永久木桩："+("开" if piece.get("permanent",false) else "关"),piece.get("permanent",false));y += 52
		_button("remove",Rect2(rect.position.x,y,rect.size.x,44),"删除棋子")
func can_add_card() -> bool:
	return game.CARDS.has(card_selected) and state[card_pile].size() < 200 and not (card_selected == "decoy_card" and card_selected in state.hand)
func available_cards() -> Array:
	var result = []
	for entry in CATALOG.entries_for(CATALOG.GROUPS[card_group].id,game.CARDS):
		if game.CARDS.has(entry.id) and (card_pile == "hand" or not game.is_generated_card(entry.id)): result.append(entry)
	return result
func card_grid_rect() -> Rect2:
	if game.compact_landscape: return Rect2(24,166,game.ui_size.x-352,game.ui_size.y-238)
	return Rect2(24,166,game.ui_size.x-48,maxf(168,game.ui_size.y-454))
func card_grid_columns() -> int: return maxi(2,mini(6,int((card_grid_rect().size.x+16)/190)))
func card_grid_page_size() -> int:
	var rows = 1 if game.compact_landscape else maxi(1,int(card_grid_rect().size.y/232))
	return card_grid_columns()*rows
func card_grid_card_rect(slot: int) -> Rect2:
	var grid = card_grid_rect();var columns = card_grid_columns();var width = (grid.size.x-(columns-1)*12)/columns
	var height = minf(288 if game.compact_landscape else 218,grid.size.y)
	return Rect2(grid.position+Vector2((slot%columns)*(width+12),(slot/columns)*232),Vector2(width,height))
func _draw_card(rect: Rect2, id: String, selected: bool):
	var transform = Transform2D(Vector2(rect.size.x/156,0),Vector2(0,rect.size.y/156),rect.position)
	face.draw_data(game,game.descriptions.data(id),game.is_consumable(id),transform,1,true,selected)
func _draw_cards_modal():
	if game.compact_landscape: _draw_landscape_cards_modal();return
	_label(Vector2(24,44),"配置"+("起始手牌" if card_pile == "hand" else "牌库"),26,Palette.INK)
	_label(Vector2(24,78),"选卡后添加。下方每一项都是独立实体。",16)
	for i in CATALOG.GROUPS.size():
		var width = (game.ui_size.x-80)/5
		_button("group:"+str(i),Rect2(24+i*(width+8),98,width,42),CATALOG.GROUPS[i].label,card_group == i,true,16)
	var cards = available_cards();var page_size = card_grid_page_size();var pages = maxi(1,ceili(float(cards.size())/page_size))
	card_page = clampi(card_page,0,pages-1)
	for slot in page_size:
		var index = card_page*page_size+slot
		if index >= cards.size(): break
		var id: String = cards[index].id;var rect = card_grid_card_rect(slot)
		_draw_card(rect,id,card_selected == id)
		hit_regions.append({"id":"card:"+id,"rect":rect})
	var controls_y = card_grid_rect().end.y+8
	_button("card_page:-1",Rect2(24,controls_y,62,38),"上页",false,card_page>0,14)
	_label(Vector2(96,controls_y+25),"%d/%d" % [card_page+1,pages],15)
	_button("card_page:1",Rect2(145,controls_y,62,38),"下页",false,card_page<pages-1,14)
	_button("add_card",Rect2(219,controls_y,game.ui_size.x-243,38),"添加所选" if can_add_card() else ("选择一张卡" if card_selected.is_empty() else "已达上限"),true,can_add_card(),16)
	var py = controls_y+54
	var pile: Array = state[card_pile]
	_label(Vector2(24,py+18),("手牌" if card_pile == "hand" else "牌库顶 → 底")+" · %d张" % pile.size(),17,Palette.INK)
	var visible = 4 if game.mobile_layout and not game.compact_landscape else 8
	var pages_pile = maxi(1,ceili(float(pile.size())/visible));pile_page = clampi(pile_page,0,pages_pile-1)
	for slot in visible:
		var index = pile_page*visible+slot
		if index >= pile.size(): break
		var width = (game.ui_size.x-48-(visible-1)*6)/visible
		var name: String = game.CARDS[pile[index]][0]
		_button("pile:"+str(index),Rect2(24+slot*(width+6),py+28,width,44),"%d %s" % [index+1,name],pile_selected == index,true,13)
	_button("pile_page:-1",Rect2(24,py+80,62,34),"上页",false,pile_page>0,14)
	_button("pile_page:1",Rect2(94,py+80,62,34),"下页",false,pile_page<pages_pile-1,14)
	_label(Vector2(168,py+104),"实体 %d/%d" % [pile_page+1,pages_pile],14)
	var y = game.ui_size.y-64
	var labels = ["前移","后移","强化","移除"]
	var actions = ["pile_move:-1","pile_move:1","upgrade","pile_remove"]
	for i in 4:
		var width = (game.ui_size.x-66)/4
		var valid = pile_selected >= 0 and pile_selected < pile.size()
		if i == 2 and valid: valid = UPGRADES.can_upgrade(pile[pile_selected])
		_button(actions[i],Rect2(24+i*(width+6),y,width,46),labels[i],false,valid,16)
func _draw_landscape_cards_modal():
	_label(Vector2(24,44),"配置"+("起始手牌" if card_pile == "hand" else "牌库"),26,Palette.INK)
	_label(Vector2(24,78),"卡面选择 → 添加实体；右侧调整独立牌序。",16)
	for i in CATALOG.GROUPS.size():
		var width = (game.ui_size.x-80)/5
		_button("group:"+str(i),Rect2(24+i*(width+8),98,width,42),CATALOG.GROUPS[i].label,card_group == i,true,16)
	var cards = available_cards();var page_size = card_grid_page_size();var pages = maxi(1,ceili(float(cards.size())/page_size))
	card_page = clampi(card_page,0,pages-1)
	for slot in page_size:
		var index = card_page*page_size+slot
		if index >= cards.size(): break
		var id: String = cards[index].id;var rect = card_grid_card_rect(slot)
		_draw_card(rect,id,card_selected==id);hit_regions.append({"id":"card:"+id,"rect":rect})
	var grid = card_grid_rect();var controls_y = game.ui_size.y-64
	_button("card_page:-1",Rect2(24,controls_y,72,44),"上页",false,card_page>0,16)
	_label(Vector2(108,controls_y+28),"%d/%d" % [card_page+1,pages],16)
	_button("card_page:1",Rect2(168,controls_y,72,44),"下页",false,card_page<pages-1,16)
	_button("add_card",Rect2(252,controls_y,grid.end.x-252,44),"添加所选" if can_add_card() else ("选择一张卡" if card_selected.is_empty() else "已达上限"),true,can_add_card(),17)
	var x = grid.end.x+24;var width = game.ui_size.x-x-24;var pile: Array = state[card_pile]
	_label(Vector2(x,180),("手牌" if card_pile=="hand" else "牌库顶 → 底")+" · %d张" % pile.size(),17,Palette.INK)
	var pages_pile = maxi(1,ceili(float(pile.size())/4));pile_page = clampi(pile_page,0,pages_pile-1)
	for slot in 4:
		var index = pile_page*4+slot
		if index >= pile.size(): break
		_button("pile:"+str(index),Rect2(x,192+slot*44,width,38),"%d · %s" % [index+1,game.CARDS[pile[index]][0]],pile_selected==index,true,16)
	_button("pile_page:-1",Rect2(x,376,72,36),"上页",false,pile_page>0,14)
	_button("pile_page:1",Rect2(x+width-72,376,72,36),"下页",false,pile_page<pages_pile-1,14)
	_label(Vector2(x+84,400),"%d/%d" % [pile_page+1,pages_pile],14)
	for i in 4:
		var valid = pile_selected>=0 and pile_selected<pile.size()
		if i==2 and valid: valid=UPGRADES.can_upgrade(pile[pile_selected])
		_button(["pile_move:-1","pile_move:1","upgrade","pile_remove"][i],Rect2(x+(i%2)*(width/2+4),426+(i/2)*50,width/2-4,44),["前移","后移","强化","移除"][i],false,valid,16)
func _draw_presets_modal():
	_label(Vector2(24,54),"演武预设",26,Palette.INK)
	_label(Vector2(24,84),"独立本地保存，不读取或覆盖征途存档。",16)
	var rows = maxi(1,int((game.ui_size.y-260)/56));var pages = maxi(1,ceili(float(presets.size())/rows))
	preset_page = clampi(preset_page,0,pages-1)
	for row in rows:
		var index = preset_page*rows+row
		if index >= presets.size(): break
		var entry: Dictionary = presets[index]
		_button("load:"+str(entry.id),Rect2(24,112+row*56,game.ui_size.x-48,48),str(entry.data.name)+( " · 完整局面" if entry.data.has("snapshot") else ""),saved_id == entry.id,true,18)
	if presets.is_empty(): _label(Vector2(24,150),"还没有预设，返回编辑后点击保存。",18)
	_page_controls(Rect2(24,110,game.ui_size.x-48,game.ui_size.y-220),"preset_page",preset_page,pages)
	var width = (game.ui_size.x-64)/3
	for i in 3:
		_button(["rename","copy","delete"][i],Rect2(24+i*(width+8),game.ui_size.y-70,width,48),["重命名当前","另存副本","删除当前"][i],false,not saved_id.is_empty() if i != 1 else true,16)
func cancel_pointer():
	pointer = -2;pointer_dragged = true;name_pointer = -2
	touch_contacts.clear();multitouch = false
func handle_input(event: InputEvent) -> bool:
	if game.screen != "training_editor": return false
	# Native LineEdit owns text selection, virtual-keyboard taps and drags.
	if is_instance_valid(name_edit) and name_edit.visible:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and name_edit.get_global_rect().has_point(event.position): name_pointer = -1;return false
			if not event.pressed and name_pointer == -1: name_pointer = -2;return false
		elif event is InputEventMouseMotion and (name_pointer == -1 or name_edit.get_global_rect().has_point(event.position)): return false
		elif event is InputEventScreenTouch:
			if event.pressed and name_edit.get_global_rect().has_point(event.position): name_pointer = event.index;return false
			if not event.pressed and name_pointer == event.index: name_pointer = -2;return false
		elif event is InputEventScreenDrag and name_pointer == event.index: return false
	if event is InputEventKey:
		if is_instance_valid(name_edit) and name_edit.visible:
			if event.pressed and event.keycode == KEY_ESCAPE: hide_name_edit();modal = "";game.queue_redraw();return true
			return false
		if event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE: _activate("close" if not modal.is_empty() else "home")
			elif event.keycode == KEY_DELETE and modal.is_empty(): remove_selected()
			elif event.keycode == KEY_S and (event.ctrl_pressed or event.meta_pressed): _activate("save")
		return true
	if event is InputEventScreenTouch:
		touch_seen = true
		if event.pressed:
			touch_contacts[event.index] = true
			if touch_contacts.size() > 1 or multitouch:
				multitouch = true;pointer = -2;pointer_dragged = true;return true
			pointer = event.index;pointer_start = event.position;pointer_dragged = false
		else:
			touch_contacts.erase(event.index)
			if event.canceled:
				pointer = -2;pointer_dragged = true;multitouch = not touch_contacts.is_empty();return true
			if multitouch:
				if touch_contacts.is_empty(): multitouch = false
				pointer = -2;return true
			if pointer == event.index:
				pointer = -2
				if not pointer_dragged and pointer_start.distance_to(event.position)<14: click(event.position)
		return true
	if event is InputEventScreenDrag:
		if event.index == pointer and pointer_start.distance_to(event.position)>=14: pointer_dragged = true
		return true
	if event is InputEventMouseButton:
		if event.device == -1 and touch_seen: return true
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: pointer = -1;pointer_start = event.position;pointer_dragged = false
			elif pointer == -1:
				pointer = -2
				if not pointer_dragged and pointer_start.distance_to(event.position)<14: click(event.position)
		return true
	if event is InputEventMouseMotion:
		if pointer == -1 and pointer_start.distance_to(event.position)>=14: pointer_dragged = true
		return true
	return false
func click(position: Vector2):
	for hit in hit_regions:
		if hit.rect.has_point(position): _activate(hit.id);return
	if not modal.is_empty() or not board_bounds().has_point(position): return
	var geometry = board_geometry();var local = (position-geometry.origin)/geometry.cell
	place_at(Vector2i(roundi(local.x),roundi(local.y)))
func _activate(action: String):
	var parts = action.split(":");var command = parts[0];var argument = parts[1] if parts.size()>1 else ""
	match command:
		"home":
			if dirty: open_confirm("home")
			else: hide_name_edit();game.show_home()
		"new":
			if dirty: open_confirm("new")
			else: create_new()
		"presets": modal = "presets"
		"recent":
			if dirty: open_confirm("load:"+recent_id)
			else: load_preset(recent_id)
		"load":
			if dirty: open_confirm(action)
			else: load_preset(argument)
		"close": modal = "";hide_name_edit()
		"tab":
			tab = int(argument);tab_page = 0
			if game.mobile_layout and not game.compact_landscape: modal = "tab_drawer"
		"expand_tab": modal = "attributes" if selected_piece >= -1 and tab == 3 else "tab_drawer"
		"role": choose_role(argument)
		"role_details": selected_piece = -1;modal = "attributes"
		"treasure":
			if compatible_treasure(argument):
				if argument in state.treasure_ids: state.treasure_ids.erase(argument)
				else: state.treasure_ids.append(argument)
				changed()
		"piece": place_index = int(argument);tool = "place";selected_piece = -2;modal = ""
		"player": tool = "player";selected_piece = -1;modal = ""
		"erase": tool = "erase";selected_piece = -2;modal = ""
		"unselect": selected_piece = -2;tool = "place";tab_page = 0
		"choose_piece": selected_piece = -2;tool = "place";tab = 3;tab_page = 0;modal = "tab_drawer"
		"remove": remove_selected();modal = ""
		"attributes": modal = "attributes"
		"adjust":
			var step = int(parts[2]);var minimum = 1 if argument in ["lives","hp"] else 0
			var maximum = 2147483647 if argument == "seed" else (999 if argument in ["lives","energy","hp"] else 99)
			if argument in ["lives","energy","seed"]: state[argument] = clampi(int(state[argument])+step,minimum,maximum)
			elif selected_piece >= 0 and selected_piece < state.enemies.size():
				var piece: Dictionary = state.enemies[selected_piece];piece[argument] = clampi(int(piece.get(argument,0))+step,minimum,maximum)
				if argument == "hp": piece.max_hp = piece.hp
			changed()
		"trait":
			if selected_piece >= 0 and selected_piece < state.enemies.size():
				var piece: Dictionary = state.enemies[selected_piece];piece[argument] = not piece.get(argument,false);changed()
		"stance":
			if state.player_skill == "artillery": state.artillery_mode = "attack" if state.artillery_mode == "march" else "march";changed()
		"free_step", "shuffle": state[command] = not state[command];changed()
		"finish": finish_condition = argument;changed()
		"options": modal = "options"
		"save":
			if saved_id.is_empty(): open_name("save")
			else: save_named(state.name)
		"rename", "copy": open_name(command)
		"name_confirm":
			if is_instance_valid(name_edit) and save_named(name_edit.text,modal == "copy"): hide_name_edit();modal = ""
		"delete": open_confirm("delete")
		"confirm":
			modal = ""
			if confirm_action == "delete": delete_preset(saved_id);modal = "presets"
			elif confirm_action == "new": create_new()
			elif confirm_action == "home": dirty = false;game.show_home()
			elif confirm_action.begins_with("load:"): load_preset(confirm_action.trim_prefix("load:"))
		"play": play()
		"cards": card_pile = argument;modal = "cards";card_selected = "";pile_selected = -1;pile_page = 0
		"group": card_group = int(argument);card_page = 0;card_selected = ""
		"card": card_selected = argument
		"add_card":
			if card_selected == "decoy_card" and card_selected in state.hand:
				message = "手牌中最多1张草木皆兵。";game.queue_redraw();return
			if game.CARDS.has(card_selected) and state[card_pile].size()<200: state[card_pile].append(card_selected);pile_selected = state[card_pile].size()-1;changed()
		"pile": pile_selected = int(argument)
		"pile_move":
			var pile: Array = state[card_pile];var destination = pile_selected+int(argument)
			if pile_selected >= 0 and pile_selected < pile.size() and destination >= 0 and destination < pile.size():
				var id = pile.pop_at(pile_selected);pile.insert(destination,id);pile_selected = destination;changed()
		"upgrade":
			if pile_selected >= 0 and pile_selected < state[card_pile].size() and UPGRADES.can_upgrade(state[card_pile][pile_selected]): state[card_pile][pile_selected] = UPGRADES.upgraded_id(state[card_pile][pile_selected]);changed()
		"pile_remove":
			if pile_selected >= 0 and pile_selected < state[card_pile].size(): state[card_pile].remove_at(pile_selected);pile_selected = mini(pile_selected,state[card_pile].size()-1);changed()
		"tab_page": tab_page = maxi(0,tab_page+int(argument))
		"card_page": card_page = maxi(0,card_page+int(argument))
		"pile_page": pile_page = maxi(0,pile_page+int(argument))
		"preset_page": preset_page = maxi(0,preset_page+int(argument))
	game.queue_redraw()
