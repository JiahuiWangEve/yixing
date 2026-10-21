extends Control
const BUILD_VERSION = "v0.14.5"
const PASS_CARD_COST = 3
const ROUTE = preload("res://route_map.gd")
var route = ROUTE.new(self)
var autosave_elapsed = 0.0
const PROFILES = preload("res://start_profiles.gd")
const THEME = preload("res://theme.gd")
const FAN = preload("res://fan_hand.gd")
const GESTURE = preload("res://card_input.gd")
const SKILLS = preload("res://player_skills.gd")
const FREE_MOVE = preload("res://free_move_card.gd")
const HISTORY = preload("res://undo_history.gd")
const UNTARGETED = ["sweep", "life", "breath", "deploy", "pack", "tuna", "suppress", "guard", "reload", "fatigue"]
# One use per physical copy per stage; discarded unused copies still recycle.
const CONSUMABLES = ["life", "breath", "deploy", "tuna", "guard", "permanent_stake", "airdrop"]
const TACTICS = preload("res://tactics.gd")
const CAMPAIGN = preload("res://campaign.gd")
const ENCOUNTERS = preload("res://encounters.gd")
var encounter_state: Dictionary = {}
var encounter_info_open = false
const ENEMY_AI = preload("res://enemy_ai.gd")
const TUTORIAL = preload("res://tutorial.gd")
const REWARD_UI = preload("res://reward_choice.gd")
const FRONTEND = preload("res://frontend.gd")
const AUDIO = preload("res://pixel_audio.gd")
const R = preload("res://rules.gd")
const FONT = preload("res://assets/font-subset.otf")
var O = Vector2(412, 105)
var BOARD_RECT = Rect2(377, 70, 526, 583)
var RESTART_RECT = Rect2(773, 20, 130, 40)
var END_TURN_RECT = Rect2(680, 663, 223, 45)
var HAND_Y = 744.0
var CELL: float = 57.0
const ENEMY_HEALTH = {"g": 3, "e": 3, "h": 2}
var screen = "game"
var tutorial = TUTORIAL.new()
var frontend = FRONTEND.new(self)
var settings = preload("res://game_settings.gd").new()
const NORMAL_UNDO_LIMIT = 3
var normal_undos_remaining = NORMAL_UNDO_LIMIT
var rewardui = REWARD_UI.new(self)
var card_picker = preload("res://card_picker.gd").new(self)
var presentation = preload("res://presentation.gd").new(self)
var player_skill = "king"
var artillery_mode = "march"
var deploy_draw_used = false
# Pending future starts, separate from the bonus on the current turn.
var tuna_turns = 0
var tuna_active = false
# Battle/turn effect state belongs to undo snapshots and route saves.
var active_displacements = 0
var shield_charges = 0
var pending_bleeds: Array = []
var next_enemy_uid = 1
var reload_ready = false
var airdrop_recovery_turn = 0
var free_card_uid = 0
var free_selected = false
var skill_system = SKILLS.new(self)
var freecard = FREE_MOVE.new(self)
var tutorial_resume_lesson = 0
var debug_target = 0
var debug_remaining = 0
var debug_reward_total = 0
var ui_size = Vector2(1280, 940)
var mobile_layout = false
var compact_landscape = false
var short_mobile = false
var hand_page = 0
var hand_drawer = false
var PREV_RECT = Rect2()
var NEXT_RECT = Rect2()
var CANCEL_RECT = Rect2()
var DRAWER_RECT = Rect2()
var touch_start = Vector2.ZERO
var active_touch = -1
var touch_dragged = false
var touch_seen = false
var delivering_touch = false
var last_window_size = Vector2i.ZERO
# Godot Web may translate DOM touchcancel into a normal release. Capture the
# browser cancellation before that translation, so no cancel can commit a card.
var web_cancel_callback = null
var web_window = null
const WEB_CANCEL_EVENTS = ["touchcancel", "pointercancel", "blur", "pagehide", "visibilitychange", "resize"]
func install_web_input_cancel():
	if not OS.has_feature("web"): return
	web_window = JavaScriptBridge.get_interface("window")
	web_cancel_callback = JavaScriptBridge.create_callback(on_web_input_cancel)
	for event_name in WEB_CANCEL_EVENTS:
		web_window.addEventListener(event_name, web_cancel_callback, true)
func on_web_input_cancel(_arguments: Array):
	cancel_gesture()
	if card_picker.active: card_picker.pointer = -2;card_picker.dragged = true
func _exit_tree():
	if web_window == null or web_cancel_callback == null: return
	for event_name in WEB_CANCEL_EVENTS:
		web_window.removeEventListener(event_name, web_cancel_callback, true)
	web_cancel_callback = null;web_window = null
func configure_layout(size: Vector2):
	cancel_gesture()
	mobile_layout = size.x < 800 or size.x < size.y * 0.95 or (size.x < 1100 and size.y < 500) or OS.has_feature("web_android") or OS.has_feature("web_ios")
	compact_landscape = mobile_layout and size.x > size.y * 1.2
	short_mobile = false;hand_page = 0;hand_drawer = false
	PREV_RECT = Rect2();NEXT_RECT = Rect2();DRAWER_RECT = Rect2();CANCEL_RECT = Rect2()
	if not mobile_layout:
		ui_size = Vector2(1280, 940);O = Vector2(448, 105);CELL = 48.0;BOARD_RECT = Rect2(417, 74, 446, 494)
		RESTART_RECT = Rect2(773, 20, 130, 40);UNDO_RECT = Rect2(1015, 20, 230, 40)
		END_TURN_RECT = Rect2(680, 578, 223, 45);HAND_Y = 624
	elif compact_landscape:
		ui_size = Vector2(960, 540);CELL = 36.0;O = Vector2(56, 101);BOARD_RECT = Rect2(24, 69, 352, 388)
		RESTART_RECT = Rect2(690, 12, 130, 64);UNDO_RECT = Rect2(240, 12, 130, 52)
		END_TURN_RECT = Rect2(688, 430, 220, 64);HAND_Y = 155
	else:
		ui_size = Vector2(480, maxf(660, 480 * size.y / maxf(1, size.x)))
		CELL = clampf((ui_size.y - 450) / 9, 24, 44);O = Vector2(240 - CELL * 4, 135)
		BOARD_RECT = Rect2(O - Vector2(24, 24), Vector2(CELL * 8 + 48, CELL * 9 + 48))
		RESTART_RECT = Rect2(104, 12, 110, 46);UNDO_RECT = Rect2(320, 12, 148, 46)
		END_TURN_RECT = Rect2(305, BOARD_RECT.end.y + 8, 163, 48);HAND_Y = full_hand_area().position.y
	USE_RECT = END_TURN_RECT
	hand_views.clear()
	if handui != null: handui.reset()
	player_visual = cell_pos(player)
	for e in enemies: e.visual = cell_pos(e.pos)
	if card_picker.active: card_picker.pointer = -2;card_picker.refresh()
func full_hand_area() -> Rect2:
	if not mobile_layout: return Rect2(24, 624, 1232, 308)
	if compact_landscape: return Rect2(410, 155, 526, 242)
	var height = clampf(ui_size.y - (BOARD_RECT.end.y + 70) - 8, 220, 300)
	return Rect2(4, ui_size.y - height - 8, 472, height)
func free_card_rect() -> Rect2: return handui.free_bounds()
func hand_area() -> Rect2: return full_hand_area()
func free_card_available() -> bool:
	return screen == "game" and phase == "play" and not basic_used and free_card_uid > 0 and not recovery_active()
func refresh_free_card():
	free_selected = false
	free_card_uid = next_card_uid;next_card_uid += 1
func select_free_card():
	if not free_card_available() or input_lock > 0 or navigation_lock > 0: return
	selected = -1;free_selected = not free_selected
	if free_selected: audio_system.play_cue("select", tick)
func visible_hand_indices() -> Array:
	var result: Array = []
	for i in hand.size(): result.append(i)
	return result
func sync_hand_ids():
	while hand_ids.size() > hand.size(): hand_ids.pop_back()
	while hand_ids.size() < hand.size(): hand_ids.append(next_card_uid);next_card_uid += 1
func drag_card_uid() -> int: return gesture.uid if gesture.dragging else -1
func cancel_gesture():
	if gesture != null: gesture.cancel()
	if route != null: route.cancel_pointer()
	active_touch = -1;touch_dragged = true
func can_undo_action() -> bool:
	return screen == "game" and not tutorial.active and input_lock <= 0 and navigation_lock <= 0 and not presentation.active() and not card_picker.active and not encounter_info_open and (settings.debug_mode or normal_undos_remaining > 0)
func undo_action() -> bool:
	if tutorial.active: notice = "教学中不可悔棋";return false
	return history.undo()
func undo_label() -> String:
	if tutorial.active: return "教学禁用悔棋"
	if settings.debug_mode: return "悔棋 · 不限次" if mobile_layout else "悔棋 Ctrl+Z · 不限次"
	return "悔棋 · 剩%d次" % normal_undos_remaining if mobile_layout else "悔棋 Ctrl+Z · 剩%d次" % normal_undos_remaining
# Passing is not playing: central guards deliberately ignore target/stance legality.
func can_pass_card(index: int, free: bool = false) -> bool:
	if screen != "game" or phase != "play" or recovery_active() or tutorial.active or encounter_info_open: return false
	if presentation.active() or card_picker.active: return false
	if input_lock > 0 or navigation_lock > 0: return false
	if energy < PASS_CARD_COST: return false
	if free: return free_card_available()
	return index >= 0 and index < hand.size()
func pass_card(index: int, free: bool = false) -> bool:
	if not can_pass_card(index, free): return false
	history.record("pass");cancel_gesture()
	energy -= PASS_CARD_COST
	if free:
		free_card_uid = 0
	else:
		sync_hand_ids()
		var id: String = hand[index]
		discard.append(hand.pop_at(index));hand_ids.remove_at(index)
		log_line("过牌「%s」" % CARDS[id][0])
	selected = -1;free_selected = false;handui.sync()
	notice = "已过牌，不触发效果，抽1张牌。"
	# Remove first, then use the normal draw hook (shuffle, fatigue, hand limit).
	# A just-discarded card can be drawn again when the draw pile is empty.
	draw_card()
	queue_redraw()
	return true
func pass_button_rect() -> Rect2:
	return pass_drop_rect() # Selection and dragging share one visible target on every layout.
func pass_drop_rect() -> Rect2:
	# Transient selection/hold overlay; inset from OS gesture edges and outside board targets.
	if compact_landscape: return Rect2(840, 176, 84, 198)
	if mobile_layout: return Rect2(380, full_hand_area().position.y + 28, 84, 166)
	return Rect2(1100, 350, 140, 200)
func pass_zone_visible() -> bool:
	if screen != "game" or phase != "play" or recovery_active() or tutorial.active: return false
	if card_picker.active or encounter_info_open or presentation.active(): return false
	if gesture.active:
		return (gesture.uid == free_card_uid and free_card_available()) if gesture.free_move else hand_ids.has(gesture.uid)
	return (free_selected and free_card_available()) or (selected >= 0 and selected < hand.size())
func confirm_card():
	if screen != "game" or input_lock > 0 or navigation_lock > 0 or selected < 0 or selected >= hand.size(): return
	if phase == "discard": discard_hand(selected)
	elif phase == "play" and hand[selected] in UNTARGETED: play_card(selected, player)
func _notification(what):
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_WM_MOUSE_EXIT]: cancel_gesture()

func reward_rect(i: int) -> Rect2:
	if not mobile_layout: return Rect2(220 + i * 285, 310, 260, 190)
	if compact_landscape: return Rect2(24 + i * 312, 150, 288, 180)
	return Rect2(24, (95 + i * 130) if ui_size.y < 700 else (105 + i * 150), 432, 122 if ui_size.y < 700 else 138)
func skip_reward_rect() -> Rect2:
	if not mobile_layout: return Rect2(530, 530, 220, 50)
	if compact_landscape: return Rect2(370, 370, 220, 58)
	return Rect2(120, ui_size.y - 80, 240, 58)
func mobile_title_pos() -> Vector2:
	return Vector2(24, 46) if mobile_layout else Vector2(377, 48)
func update_window_layout():
	if DisplayServer.get_name() == "headless": return
	var size = get_window().size
	if size == last_window_size: return
	last_window_size = size
	var logical_size = Vector2(size)
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var bridge = Engine.get_singleton("JavaScriptBridge")
		logical_size = Vector2(float(bridge.eval("window.innerWidth", true)), float(bridge.eval("window.innerHeight", true)))
	var old_origin = O
	var old_cell = CELL
	configure_layout(logical_size)
	get_window().content_scale_size = Vector2i(ui_size)
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP

	for fx in effects:
		if fx.kind == "card_use":
			fx.from = hand_rect(0).position;fx.to = fx.from - Vector2(0, 60);fx.size = hand_rect(0).size
		elif fx.kind not in ["draw", "victory"]:
			fx.from = O + (fx.from - old_origin) / old_cell * CELL
			fx.to = O + (fx.to - old_origin) / old_cell * CELL
const INK = THEME.INK
const GOLD = THEME.GOLD
const RED = THEME.DANGER
const CARDS = {
	"airdrop": ["空投", 3, "飞至任意空格，周围3×3各3伤；命-1，下一回合停行动；消耗", "攻", "将专属。落点必须是其他空格，不能是敌子或木桩。落地周围3×3的每个敌子受3伤，自身扣1命（不被固守抵挡、不撤退）。命归零立即失败，即使同时击杀敌将。当前回合可继续；下一玩家回合不能移动或出牌，仍正常结算敌方与被动效果。消耗：本场移除，下场恢复。"],
	"fatigue": ["疲惫", 2, "抽到时能量-1；留手每轮-1，最低0。打出弃置", "负", "负面牌。抽到时立即扣1能量，能量为0则不扣、不欠费。每个后续玩家回合开始，仍在手中时再扣1；多张分别结算。花2费打出后正常弃置，已扣能量不返还；不是消耗牌。"],
	"sword_plus": ["短剑·淬锋", 1, "对正交相邻敌子造成2点伤害（强化）", "攻"],
	"spear_plus": ["长枪·淬锋", 2, "直线两格内造成2点伤害，不穿透（强化）", "攻"],
	"sword": ["短剑", 1, "对正交相邻敌子造成1点伤害", "攻"],
	"diagonal": ["斜斩", 1, "对斜角相邻敌子造成1点伤害", "攻"],
	"spear": ["长枪", 2, "直线两格内造成1点伤害，不穿透", "攻"],
	"horse": ["踏马", 1, "按马步移动，遵守蹩马腿；抽1张", "移"],
	"cannon": ["投石", 2, "直线隔恰好一子，造成1点伤害", "攻"],
	"sweep": ["横扫", 2, "对自身周围3×3内所有敌子各造成1点伤害", "攻"],
	"straight": ["疾行", 1, "直线移动至多两格，不穿透；抽1张", "移"],
	"life": ["续命", 2, "生命+1（上限5，本关消耗）；受击存活时转移安全格", "术", "生命+1（上限5，本关消耗）。受击后若仍有生命，转移到最近的安全空位；同距随机，没有安全空位则失败。转移不抽牌。"],
	"stake": ["架炮", 1, "两格内空位放木桩，挡路作炮架；持续3回合", "术"],
	"pierce": ["流血", 1, "正交相邻敌子，本回合末和下回合末各受到1点伤害", "攻", "对一个正交相邻敌子施加流血。本回合末和下回合末、敌方攻击前各受到1伤。跟随同一敌子，可叠加；目标死亡则剩余流血失效。"],
	"suppress": ["镇四方", 3, "抽1张；正交相邻所有敌子移动倒计时+2", "术", "先抽1张，再使正交相邻所有敌子的移动倒计时+2。不造成伤害，不影响敌方攻击；不消耗。手牌超限时效果仍完整结算后再弃牌。"],
	"guard": ["固守", 2, "抵挡下次受击，至下个玩家回合开始；消耗", "术", "下个玩家回合开始前抵挡1次实际受击，不掉命、不转移。未触发也到期失效；重复使用只刷新1次。"],
	"chain_assault": ["连袭", 2, "周围3×3内选一个敌子，造成1+本回合主动位移次数伤害", "攻", "在自身周围3×3内选择一个敌子，造成1+本回合此前成功主动位移次数的伤害。免费移动、移动牌与攻击附带位移均计入，每次行动计1次，不按格数；受击转移、失败移动与姿态切换不计。"],
	"permanent_stake": ["机关炮架", 1, "两格内空位放永久木桩，持续本场战斗；消耗", "术", "与架炮相同，曼哈顿距离两格内的空位放木桩，挡路并作炮架。不会按回合消失，战斗结束清除；本关消耗。"],
	"reload": ["装填", 1, "本回合下次炮击伤害+1；若击杀，抽1张", "术", "只强化本回合下一张成功打出的炮击，不强化其他攻击。无效目标不消耗装填；击杀时抽1张。未使用则回合结束失效，重复使用刷新1次，不叠加。"],
	"pursuit": ["追斩", 1, "相邻敌子1点伤害；仅击杀时抽1张", "攻"],
	"shock": ["震退", 1, "周围3×3或正交2格选一敌子，1伤并推1格", "攻"],
	"breath": ["调息", 0, "当前能量+1；本关消耗", "术"],
	"cannon_shot": ["炮击", 2, "直线隔恰好一子；行军2费1伤，攻击1费2伤", "攻"],
	"advance": ["进击", 1, "正交相邻敌子1伤；击杀后进入其位置，不抽牌", "攻"],
	"retreat_strike": ["回马枪", 1, "向目标反方向退1格再造成1伤，退路需空；不抽牌", "攻"],
	"knight_assault": ["马踏连营", 2, "马步攻击1伤，遵守蹩腿；击杀后进入目标格，不抽牌", "攻"],
	"deploy": ["展开", 1, "行军→攻击；本回合首次展开抽3张；消耗", "术", "仅炮车行军姿态可用。进入攻击姿态；每回合首次进入时抽3张，超出6张需弃牌。使用后本关移除，下关恢复。"],
	"pack": ["转进", 0, "攻击→行军；不抽牌，保留免费移动额度", "术"],
	"tuna": ["吐纳", 3, "下回合起连续3回合能量+1；消耗", "术", "使用当回合不返还能量。接下来3个玩家回合各以4能量开始；再次使用延长3回合，不叠加增量。过关清除。消耗：使用后本关移除，下关恢复。"],
}
var rng = RandomNumberGenerator.new()
var seed_value = 20261019
var player = Vector2i(4, 9)
var enemies: Array = []
var deck: Array = []
var discard: Array = []
var hand: Array = []
var hand_ids: Array = []
var next_card_uid = 1
var handui = FAN.new(self)
var gesture = GESTURE.new(self)
var history = HISTORY.new(self)
var UNDO_RECT = Rect2()
var USE_RECT = Rect2()
var collection: Array = []
var rewards: Array = []
var stage = 1
var turn = 1
var reinforcement_turns = 0
var reinforcement_pending = 0
var lives = 1
var energy = 3
var basic_used = false
var card_move_used = false
var selected = -1
var hover = Vector2i(-1, -1)
var phase = "play"
var show_threat = false
var initial_threat = 2.0
var tick = 0.0
var logs: Array = []
var notice = ""
var player_visual = Vector2.ZERO
var input_lock = 0.0
var navigation_lock = 0.0
var effects: Array = []
var hand_views: Array = []
var audio_system = AUDIO.new()
var mouse_pos = Vector2(-100, -100)
func enemy_health(kind: String) -> int:
	if kind == "g" and not tutorial.active:
		var tier = encounter_state.get("config", {}).get("tier", "")
		if tier == "boss" or (tier.is_empty() and stage == 6): return 9
		if tier == "elite": return 5
	return ENEMY_HEALTH.get(kind, 1)
func clear_effects():
	encounter_info_open = false
	effects.clear();hand_views.clear();input_lock = 0.0
	audio_system.clear_playback()
	player_visual = cell_pos(player)
	for e in enemies: e.visual = cell_pos(e.pos)
func effect(kind: String, from: Vector2, to: Vector2, duration: float = 0.3, delay: float = 0.0, extra: Dictionary = {}):
	var fx = {"kind": kind, "from": from, "to": to, "duration": duration, "delay": delay, "age": 0.0}
	var cues = {"move": "land", "recoil": "land", "draw": "draw", "card_use": "use", "hit": "hit", "death": "death", "player_hit": "hurt", "stun": "stun", "push": "push", "life": "heal", "spawn": "spawn", "victory": "victory", "stake_place": "land", "breath": "heal", "stance": "land", "tuna": "heal"}
	if cues.has(kind):
		fx.sound = cues[kind];fx.sound_played = false
		fx.sound_at = delay + (duration if kind in ["move", "recoil"] else (0.3 if kind == "spawn" else (0.15 if kind == "draw" else 0.0)))
	fx.merge(extra);effects.append(fx)
	input_lock = maxf(input_lock, delay + duration)
func move_piece(e: Dictionary, from: Vector2, to: Vector2, delay: float = 0.0, arc: bool = false):
	effect("move", from, to, 0.28, delay, {"piece": e, "arc": arc})
func sync_hand_views():
	sync_hand_ids();handui.sync();hand_views.clear()
	for i in hand.size(): hand_views.append({"id": hand[i], "pos": handui.bounds(i).position, "lift": 0.0, "flip": 1.0})
func hand_visual_rect(i: int) -> Rect2:
	sync_hand_ids();handui.sync();return handui.bounds(i)
func hand_draw_order() -> Array: return handui.draw_order()
func hand_hit_index(pos: Vector2) -> int: return handui.hit_index(pos)

func in_neighbor_square(p: Vector2i) -> bool:
	var d = p - player
	return d != Vector2i.ZERO and absi(d.x) <= 1 and absi(d.y) <= 1
func record_active_displacement(origin: Vector2i):
	if player != origin: active_displacements += 1
func recovery_active() -> bool: return airdrop_recovery_turn > 0 and turn == airdrop_recovery_turn
func clear_battle_card_effects():
	airdrop_recovery_turn = 0
	active_displacements = 0;shield_charges = 0;pending_bleeds = [];reload_ready = false
func queue_bleed(index: int, amount: int):
	if index < 0 or index >= enemies.size() or enemies[index].kind == "stake": return
	pending_bleeds.append({"enemy_uid": enemies[index].uid, "amount": amount})
func general_alive() -> bool:
	for enemy in enemies:
		if enemy.kind == "g": return true
	return false
func resolve_bleeds():
	# Detach queue first: killed targets never retarget a new occupant or reinforcement.
	var queued = pending_bleeds.duplicate(true)
	pending_bleeds.clear()
	for bleed in queued:
		for i in enemies.size():
			if enemies[i].get("uid", -1) == bleed.enemy_uid:
				var killed = damage_enemy(i, 0.0, 1, false)
				if not killed and bleed.amount > 1:
					pending_bleeds.append({"enemy_uid": bleed.enemy_uid, "amount": bleed.amount - 1})
				break
		if not general_alive():
			settle_victory()
			return

func damage_enemy(idx: int, impact_delay: float = 0.12, amount: int = 1, before_player_input: bool = false) -> bool:
	if idx < 0 or idx >= enemies.size() or enemies[idx].kind == "stake": return false
	var e = enemies[idx]
	e.hp = e.get("hp", enemy_health(e.kind)) - amount
	if amount > 0: ENCOUNTERS.on_general_damage(self, e)
	effect("hit", cell_pos(e.pos), cell_pos(e.pos), 0.24, impact_delay, {"piece": e})
	if e.hp <= 0:
		effect("death", cell_pos(e.pos), cell_pos(e.pos), 0.42, impact_delay + 0.08, {"symbol": piece_name(e.kind), "impact": impact_delay})
		enemies.remove_at(idx)
		pending_bleeds = pending_bleeds.filter(func(bleed): return bleed.enemy_uid != e.uid)
		ENCOUNTERS.on_enemy_defeated(self, e, before_player_input)
		return true
	return false

func _ready():
	install_web_input_cancel()
	add_child(audio_system)
	mouse_filter = Control.MOUSE_FILTER_STOP
	configure_layout(Vector2(1280, 940))
	update_window_layout()
	settings.load_settings()
	audio_system.set_muted(settings.audio_muted)
	audio_system.mute_changed.connect(settings.set_audio_muted)
	skill_system.load_progress()
	new_run()
	show_home()
	if "--screenshot" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://preview.png")
		get_tree().quit()
func new_expedition():
	new_run()
	route.generate(seed_value)
	screen = "map"
	route.save()

func new_run(preserve_tutorial: bool = false):
	normal_undos_remaining = NORMAL_UNDO_LIMIT
	presentation.clear();card_picker.close()
	route.state = {}
	history.clear();cancel_gesture();hand_ids = [];next_card_uid = 1;free_selected = false
	if preserve_tutorial: player_skill = "king"
	if not preserve_tutorial: tutorial.stop()
	navigation_lock = 0.0
	screen = "game";debug_target = 0;debug_remaining = 0;debug_reward_total = 0
	active_touch = -1;touch_dragged = true
	rng.seed = seed_value
	if not PROFILES.DATA.has(player_skill): player_skill = "king"
	stage = 1;lives = int(PROFILES.DATA[player_skill].lives)
	collection = PROFILES.DATA[player_skill].deck.duplicate()
	# Scripted lessons keep their original fixtures, independent of run balance.
	if preserve_tutorial:
		lives = 1
		collection = ["sword", "sword", "sword", "sword", "spear", "spear", "horse", "horse"]
	logs = []
	start_stage()
func home_rect() -> Rect2:
	if compact_landscape: return Rect2(110, 12, 120, 64)
	if mobile_layout: return Rect2(12, 12, 84, 46)
	return Rect2(25, 20, 110, 40)
func show_home():
	if route.active() and screen in ["game", "map", "route_choice"]: route.save()
	rewardui.reset()
	history.clear();cancel_gesture()
	if tutorial.active: tutorial_resume_lesson = tutorial.lesson_index
	navigation_lock = 0.0
	tutorial.stop();clear_effects();selected = -1;free_selected = false;active_touch = -1;touch_dragged = true;debug_remaining = 0;debug_target = 0;screen = "home"
func open_settings():
	if screen != "home": return
	cancel_gesture();screen = "settings";queue_redraw()
func open_tutorial_menu():
	show_home();screen = "tutorial_menu"
func start_tutorial(index: int):
	player_skill = "king";free_selected = false
	tutorial_resume_lesson = clampi(index, 0, 4)
	tutorial.start(self, tutorial_resume_lesson);screen = "game"
func start_debug_stage(index: int):
	new_run();debug_target = clampi(index, 1, CAMPAIGN.LAST_STAGE);debug_reward_total = debug_target - 1;debug_remaining = debug_reward_total
	if debug_remaining > 0: roll_rewards();phase = "reward"
	else: stage = debug_target;start_stage()
func reward_pool() -> Array:
	return PROFILES.COMMON.duplicate() + PROFILES.DATA[player_skill].rewards.duplicate()
func roll_rewards():
	rewardui.reset()
	if tutorial.active:
		rewards = ["cannon", "sweep", "shock", "straight", "guard", "life"]
		shuffle(rewards);rewards = rewards.slice(0, 3)
		return
	rewards = PROFILES.draw_rewards(player_skill, rng)
	shuffle(rewards)
func is_consumable(id: String) -> bool: return id in CONSUMABLES
func tutorial_allows(action: String, data: Dictionary = {}) -> bool:
	return not tutorial.active or tutorial.allows(action, data)
func tutorial_after(action: String, data: Dictionary = {}):
	if tutorial.active: tutorial.after_action(action, data)
func cancel_selection():
	if screen != "game" or not tutorial_allows("cancel"): return
	selected = -1;free_selected = false;tutorial_after("cancel")
func choose_reward(index: int = -1):
	if screen != "game" or phase != "reward" or input_lock > 0 or navigation_lock > 0 or index < -1 or index >= rewards.size(): return
	var data = {"index": index, "mode": "skip" if index < 0 else "add"}
	if not tutorial_allows("reward", data): return
	if route.rewards_blocked() and index >= 0: return
	if index >= 0: collection.append(rewards[index])
	finish_reward(data)
func delete_reward(index: int):
	if route.rewards_blocked(): return
	if screen != "game" or phase != "reward" or input_lock > 0 or navigation_lock > 0 or index < 0 or index >= collection.size(): return
	var data = {"index": index, "mode": "remove"}
	if not tutorial_allows("reward", data): return
	collection.remove_at(index)
	finish_reward(data)
func finish_reward(data: Dictionary):

	history.clear();cancel_gesture();rewardui.reset()
	if route.active():
		route.complete()
	elif debug_remaining > 0:
		debug_remaining -= 1
		if debug_remaining > 0: roll_rewards()
		else: stage = debug_target;start_stage()
	else: stage += 1;start_stage()
	navigation_lock = 0.25
	tutorial_after("reward", data)
func discard_hand(index: int):
	if screen != "game" or phase != "discard" or index < 0 or index >= hand.size(): return
	if not tutorial_allows("discard", {"index": index}): return
	history.record("discard");sync_hand_ids()
	discard.append(hand.pop_at(index));hand_ids.remove_at(index);handui.sync();phase = "discard" if hand.size() > 6 else "play";selected = -1
	input_lock = maxf(input_lock, 0.18)
	hand_page = mini(hand_page, maxi(0, (hand.size() - 1) / 2));hand_drawer = false;notice = "仍超出手牌上限，请继续弃置。" if phase == "discard" else "已弃置，继续行动。"
	tutorial_after("discard", {"index": index})
func select_card(index: int):
	if phase == "play" and recovery_active(): return
	if screen != "game" or phase not in ["play", "discard"] or index < 0 or index >= hand.size(): return
	if selected == index: cancel_selection();return
	if not tutorial_allows("select", {"index": index}): return
	free_selected = false
	selected = index;audio_system.play_cue("select", tick);hand_drawer = false
	notice = "点击高亮目标；右键或 Esc 取消。";tutorial_after("select", {"index": index})
func basic_move(target: Vector2i):
	if screen != "game" or phase != "play" or not basic_legal(target): return
	if not tutorial_allows("move", {"target": target}): return
	history.record("move")
	var origin = player
	move_piece({}, cell_pos(player), cell_pos(target), 0, player_skill == "horse");player = target;record_active_displacement(origin);basic_used = true;free_selected = false;selected = -1;notice = "基础移动完成，抽1张牌。";draw_card()
	tutorial_after("move", {"target": target})
func shuffle(a: Array):
	for i in range(a.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var tmp = a[i];a[i] = a[j];a[j] = tmp
func add_enemy(kind: String, p: Vector2i, cd: int):
	enemies.append({"uid": next_enemy_uid, "kind": kind, "pos": p, "cd": cd, "period": cd, "stun": 0, "hp": enemy_health(kind), "max_hp": enemy_health(kind), "visual": cell_pos(p)})
	next_enemy_uid += 1
func start_stage():
	rewardui.reset()
	history.clear();cancel_gesture();hand_ids = []
	navigation_lock = 0.0
	reinforcement_turns = 0;reinforcement_pending = 0;hand_page = 0;hand_drawer = false
	artillery_mode = "march";deploy_draw_used = false;tuna_turns = 0;tuna_active = false
	clear_battle_card_effects();next_enemy_uid = 1;encounter_state = {}
	clear_effects()
	player = Vector2i(4, 9);player_visual = cell_pos(player);enemies = [];turn = 1;energy = 3;basic_used = false;card_move_used = false;selected = -1
	refresh_free_card()
	hand = [];handui.reset();discard = [];deck = collection.duplicate();shuffle(deck)
	CAMPAIGN.setup(self)
	plan_intents()
	phase = "play";initial_threat = 2.0;notice = "向前一步，抽取你的第一张牌。"
	log_line("第%d关 · %s" % [stage, ENCOUNTERS.title(encounter_state.config) if ENCOUNTERS.active(self) else CAMPAIGN.stage_name(stage)])
func log_line(s: String):
	logs.push_front(s)
	if logs.size() > 7: logs.pop_back()
func _process(delta):
	presentation.tick(delta)
	if card_picker.active and not card_picker.valid_context(): card_picker.close()
	update_window_layout()
	route.tick(delta)
	tick += delta
	if input_lock <= 0: initial_threat = maxf(0, initial_threat - delta)
	input_lock = maxf(0, input_lock - delta)
	navigation_lock = maxf(0, navigation_lock - delta)

	player_visual = cell_pos(player)
	for e in enemies: e.visual = cell_pos(e.pos)
	var animated_pieces: Array = []
	for fx in effects:
		fx.age += delta
		if fx.has("sound") and not fx.sound_played and fx.age >= fx.sound_at:
			fx.sound_played = true;audio_system.play_cue(fx.sound, tick)
		var t = clampf((fx.age - fx.delay) / fx.duration, 0, 1)
		if fx.kind == "spawn":
			var landing = clampf((t - 0.46) / 0.54, 0, 1)
			fx.piece.visual = fx.to - Vector2(0, (1 - landing) * 24)
		if fx.kind == "move" or fx.kind == "recoil":
			var animated_piece = fx.get("piece", {})
			# A queued bonus move must not overwrite its still-playing first step.
			if fx.age < fx.delay and animated_piece in animated_pieces: continue
			animated_pieces.append(animated_piece)
			var eased = t * t * (3 - 2 * t)
			var v: Vector2 = fx.from.lerp(fx.to, eased)
			v.y -= sin(t * PI) * (24 if fx.get("arc", false) else 9)
			if fx.get("piece", {}).is_empty(): player_visual = v
			else: fx.piece.visual = v
	effects = effects.filter( func(fx): return fx.age < fx.delay + fx.duration)
	autosave_elapsed += delta
	if autosave_elapsed >= 1.0 and route.active() and screen == "game" and input_lock <= 0:
		autosave_elapsed = 0;route.save()
	sync_hand_ids();handui.tick(delta)
	if tutorial.active and screen == "game":
		tutorial.tick(delta)
		if tutorial.lesson_complete and input_lock <= 0: screen = "tutorial_complete"
	# Retain the static map canvas between input/animation changes. Battle still animates.
	if screen not in ["map", "route_choice"]:
		route.redraw_key = 0
		queue_redraw()
	elif route.needs_redraw():
		queue_redraw()
func cell_pos(p: Vector2i) -> Vector2: return O + Vector2(p) * CELL
func board_cell(pos: Vector2) -> Vector2i:
	var p = Vector2i(roundi((pos.x - O.x) / CELL), roundi((pos.y - O.y) / CELL))
	if R.inside(p) and pos.distance_to(cell_pos(p)) < 28: return p
	return Vector2i(-1, -1)
func movement_danger(id: String, p: Vector2i) -> bool:
	return R.threatened(p, enemies)
func placement_danger(p: Vector2i) -> bool:
	var board = enemies.duplicate(true)
	board.append({"kind": "stake", "pos": p, "stun": 0})
	return R.threatened(player, board)
func basic_legal(p: Vector2i) -> bool:
	if recovery_active(): return false
	if not R.inside(p) or basic_used or R.occupied(p, enemies) >= 0: return false
	var d = p - player
	if player_skill == "artillery":
		var distance = absi(d.x) + absi(d.y)
		return distance > 0 and distance <= (1 if artillery_mode == "attack" else 2) and R.blockers(player, p, enemies) == 0
	if player_skill != "horse": return absi(d.x) + absi(d.y) == 1
	if not ((absi(d.x) == 2 and absi(d.y) == 1) or (absi(d.x) == 1 and absi(d.y) == 2)): return false
	var leg = player + Vector2i(signi(d.x) if absi(d.x) == 2 else 0, signi(d.y) if absi(d.y) == 2 else 0)
	return R.occupied(leg, enemies) < 0
func card_cost(id: String) -> int:
	return 1 if id == "cannon_shot" and artillery_mode == "attack" else int(CARDS[id][1])
func card_data(id: String) -> Array:
	var data: Array = CARDS[id].duplicate()
	data[1] = card_cost(id)
	if id == "airdrop" and lives <= 1:
		data[2] = "仅剩1命：使用后直接失败；空格落地，周围3×3各3伤；消耗"
	if id == "cannon_shot":
		var amount = (2 if artillery_mode == "attack" else 1) + (1 if reload_ready else 0)
		data[2] = "%s：%d费%d伤；直线隔恰好一子%s" % ["攻击姿态" if artillery_mode == "attack" else "行军姿态", data[1], amount, "；装填击杀抽1张" if reload_ready else ""]
	if id == "chain_assault":
		data[2] = "周围3×3选一个敌子；当前%d伤（1+已主动位移%d次）" % [1 + active_displacements, active_displacements]
		data[4] = "当前%d伤（1+主动位移%d次）。周围3×3选一个敌子。免费、移动牌与攻击附带的成功位移，每次行动计1次；受击转移、失败与切姿态不计。" % [1 + active_displacements, active_displacements]
	return data
func target_danger(id: String, p: Vector2i) -> bool:
	if id == "airdrop":
		var survivors = enemies.filter(func(enemy): return enemy.kind == "stake" or int(enemy.hp) > 3 or absi(enemy.pos.x - p.x) > 1 or absi(enemy.pos.y - p.y) > 1)
		return lives <= 1 or R.threatened(p, survivors)
	if id in ["stake", "permanent_stake"]: return placement_danger(p)
	if id in ["advance", "retreat_strike", "knight_assault"]: return TACTICS.attack_danger(self, id, p)
	return CARDS[id][3] == "移" and movement_danger(id, p)
func can_commit_card(index: int, p: Vector2i) -> bool:
	if recovery_active(): return false
	if phase != "play" or index < 0 or index >= hand.size(): return false
	var id: String = hand[index]
	if energy < card_cost(id) or (CARDS[id][3] == "移" and card_move_used): return false
	if id == "life": return lives < 5
	if id == "breath": return true
	if id == "sweep":
		for e in enemies:
			if e.kind != "stake" and in_neighbor_square(e.pos): return true
		return false
	return card_legal(id, p)
func card_legal(id: String, p: Vector2i) -> bool:
	if recovery_active(): return false
	id = id.trim_suffix("_plus")
	if not R.inside(p): return false
	if id in TACTICS.IDS: return TACTICS.legal(self, id, p)
	var d = p - player
	var dist = abs(d.x) + abs(d.y)
	var idx = R.occupied(p, enemies)
	if idx >= 0 and enemies[idx].kind == "stake": return false
	match id:
		"airdrop": return player_skill == "king" and idx < 0 and p != player
		"fatigue": return true
		"deploy": return player_skill == "artillery" and artillery_mode == "march"
		"pack": return player_skill == "artillery" and artillery_mode == "attack"
		"tuna", "suppress", "guard": return player_skill == "king"
		"reload": return player_skill == "artillery"
		"cannon_shot": return player_skill == "artillery" and idx >= 0 and R.blockers(player, p, enemies) == 1
		"sword": return idx >= 0 and dist == 1
		"diagonal": return idx >= 0 and absi(d.x) == 1 and absi(d.y) == 1
		"spear": return idx >= 0 and dist <= 2 and R.blockers(player, p, enemies) == 0
		"cannon": return idx >= 0 and R.blockers(player, p, enemies) == 1
		"horse":
			if idx >= 0 or card_move_used: return false
			if not ((abs(d.x) == 2 and abs(d.y) == 1) or (abs(d.x) == 1 and abs(d.y) == 2)): return false
			return R.occupied(player + Vector2i(signi(d.x) if abs(d.x) == 2 else 0, signi(d.y) if abs(d.y) == 2 else 0), enemies) < 0
		"straight": return idx < 0 and not card_move_used and dist > 0 and dist <= 2 and R.blockers(player, p, enemies) == 0
	return false
func draw_card():
	if deck.is_empty(): deck = discard.duplicate();discard = [];shuffle(deck)
	if deck.is_empty(): notice = "牌库与弃牌堆已空。";return
	sync_hand_ids()
	var id = deck.pop_back();hand.append(id);hand_ids.append(next_card_uid);next_card_uid += 1
	if id == "fatigue": energy = maxi(0, energy - 1)
	handui.sync();effect("draw", Vector2.ZERO, Vector2.ZERO, 0.32)
	log_line("抽到「%s」" % CARDS[id][0])
	if id == "fatigue": notice = "疲惫：抽到立即扣1能量，最低0；不记欠费。"
	if hand.size() > 6: phase = "discard";selected = -1;free_selected = false;notice = "选一张牌，再确认弃置。"
func hand_rect(i: int) -> Rect2: return hand_visual_rect(i)
func _gui_input(event):
	if presentation.input_event(event): return
	if card_picker.input_event(event): return
	if screen in ["map", "route_choice"] and route.input_event(event): return
	if event is InputEventMouse and event.device == -1 and touch_seen and not delivering_touch: return
	if encounter_info_open:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: handle_click(event.position)
		return
	if event is InputEventMouseMotion and not (gesture.active and gesture.source == "touch"):
		hover = board_cell(event.position);mouse_pos = event.position;gesture.motion(event.position)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed: cancel_gesture();cancel_selection();return
		if gesture.active and gesture.source == "touch": return
		if event.button_index != MOUSE_BUTTON_LEFT: return
		mouse_pos = event.position
		if event.pressed:
			audio_system.unlock()
			if not encounter_info_open and gesture.press(event.position, "mouse"): return
			handle_click(event.position)
		else: gesture.release(event.position)
func handle_click(pos: Vector2):
	if presentation.active(): return
	if card_picker.active: card_picker.tap(pos);return
	if encounter_info_open:
		if encounter_close_rect().has_point(pos) or not encounter_panel_rect().has_point(pos): encounter_info_open = false
		return
	if screen == "game" and mobile_layout and ENCOUNTERS.active(self) and phase in ["play", "discard"] and encounter_rules_rect().has_point(pos):
		cancel_gesture();encounter_info_open = true;return
	if screen in ["map", "route_choice"]: route.click(pos);return
	if screen != "game": cancel_gesture();frontend.click(pos);return
	if home_rect().has_point(pos): show_home();return
	if UNDO_RECT.has_point(pos): undo_action();return
	if RESTART_RECT.has_point(pos):
		cancel_gesture()
		if tutorial.active: screen = "tutorial_pause"
		elif route.active(): new_expedition()
		else: new_run()
		return
	if settings.debug_mode and debug_skip_rect().has_point(pos) and not tutorial.active: debug_skip();return
	if input_lock > 0 or navigation_lock > 0: return
	if phase == "reward":
		var previous_mode: String = rewardui.mode
		rewardui.click(pos)
		if rewardui.mode != previous_mode: navigation_lock = maxf(navigation_lock, 0.15)
		return
	if phase in ["dead", "win"]: return
	if pass_zone_visible() and pass_drop_rect().has_point(pos): pass_card(selected, free_selected);return
	if USE_RECT.has_point(pos) and selected >= 0 and (phase == "discard" or hand[selected] in UNTARGETED): confirm_card();return
	if phase == "discard": return
	if END_TURN_RECT.has_point(pos): request_end_turn();return
	var target = board_cell(pos)
	if selected >= 0:
		if hand[selected] not in UNTARGETED and card_legal(hand[selected], target): play_card(selected, target)
		elif not BOARD_RECT.has_point(pos) and not hand_area().has_point(pos): cancel_selection()
	elif basic_legal(target): basic_move(target)
	elif free_selected and not full_hand_area().has_point(pos): cancel_selection()

func _input(event):
	if screen == "settings" and event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_ESCAPE: show_home()
		get_viewport().set_input_as_handled();return
	if presentation.input_event(event): get_viewport().set_input_as_handled();return
	if card_picker.input_event(event): get_viewport().set_input_as_handled();return
	if encounter_info_open and event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE: encounter_info_open = false
		get_viewport().set_input_as_handled();return
	if screen in ["map", "route_choice"] and (event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventKey):
		if route.input_event(event): get_viewport().set_input_as_handled();return
	if event is InputEventScreenTouch:
		touch_seen = true
		if event.canceled:
			if event.index == active_touch: cancel_gesture()
			return
		if event.pressed:
			audio_system.unlock()
			if active_touch < 0:
				active_touch = event.index;touch_start = event.position;touch_dragged = false;mouse_pos = event.position
				if not encounter_info_open: gesture.press(event.position, "touch")
		elif event.index == active_touch:
			active_touch = -1;mouse_pos = event.position
			if gesture.active: gesture.release(event.position)
			elif not touch_dragged and event.position.distance_to(touch_start) < 12:
				hover = board_cell(event.position);handle_click(event.position)
		return
	if event is InputEventScreenDrag:
		if event.index == active_touch:
			if event.position.distance_to(touch_start) >= 12: touch_dragged = true
			mouse_pos = event.position;gesture.motion(event.position)
		return
	if not (event is InputEventKey) or not event.pressed or event.echo: return
	audio_system.unlock()
	if event.keycode == KEY_Z and (event.ctrl_pressed or event.meta_pressed): undo_action();get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE: cancel_gesture();cancel_selection()
	elif event.keycode == KEY_SPACE: request_end_turn()

func request_end_turn():
	if encounter_info_open: return
	if screen != "game" or phase != "play" or input_lock > 0 or navigation_lock > 0: return
	cancel_gesture();end_turn()
func play_card(i: int, p: Vector2i):
	if recovery_active(): return
	if screen != "game": return
	if phase != "play" or i < 0 or i >= hand.size(): return
	var id = hand[i]
	if not tutorial_allows("play", {"index": i, "target": p, "card": id}): return
	if energy < card_cost(id): notice = "能量不足。";return
	if CARDS[id][3] == "移" and card_move_used: notice = "本回合已使用移动牌。";return
	if id not in ["sweep", "life", "breath"] and not card_legal(id, p): notice = "当前姿态或目标无法使用此牌。";return
	if id == "life" and lives >= 5: notice = "生命已满，保留此牌。";return
	if id == "sweep":
		var found = false
		for e in enemies:
			if e.kind != "stake" and in_neighbor_square(e.pos): found = true
		if not found: notice = "周围没有可横扫的敌子。";return
	history.record("play");free_selected = false;sync_hand_views()
	effect("card_use", hand_visual_rect(i).position, hand_visual_rect(i).position - Vector2(0, 60), 0.34, 0, {"card": id, "size": hand_rect(i).size})
	hand_views.remove_at(i);hand_ids.remove_at(i)
	energy -= card_cost(id);hand.remove_at(i);selected = -1;handui.sync()
	if not is_consumable(id): discard.append(id)
	log_line("使用「%s」" % CARDS[id][0])
	var idx = R.occupied(p, enemies)
	if id in TACTICS.IDS: TACTICS.apply(self, id, p, idx)
	match id:
		"airdrop":
			var origin = player
			move_piece({}, cell_pos(origin), cell_pos(p), 0.0, true)
			player = p;record_active_displacement(origin)
			lives -= 1;airdrop_recovery_turn = turn + 1
			for j in range(enemies.size() - 1, -1, -1):
				if enemies[j].kind != "stake" and absi(enemies[j].pos.x - p.x) <= 1 and absi(enemies[j].pos.y - p.y) <= 1:
					effect("sword", cell_pos(p), cell_pos(enemies[j].pos), 0.3, 0.28)
					damage_enemy(j, 0.28, 3)
			if lives <= 0:
				phase = "dead";clear_battle_card_effects();ENCOUNTERS.cancel_pending(self)
				notice = "空投自损，命数耗尽。";log_line(notice)
				return # Self-cost defeat takes precedence over any simultaneous general kill.
			notice = "空投完成：扣1命，下一回合不能移动或出牌。"
		"fatigue": notice = "疲惫已弃置；已扣能量不返还。"
		"sword", "spear", "sword_plus", "spear_plus", "cannon", "diagonal", "cannon_shot":
			var animation = "cannon" if id == "cannon_shot" else ("sword" if id == "diagonal" else id.trim_suffix("_plus"))
			effect(animation, cell_pos(player), cell_pos(p), 0.3)
			var loaded = id == "cannon_shot" and reload_ready
			var amount = (2 if id.ends_with("_plus") or (id == "cannon_shot" and artillery_mode == "attack") else 1) + (1 if loaded else 0)
			if loaded: reload_ready = false
			var killed = damage_enemy(idx, 0.3 if animation == "cannon" else 0.12, amount)
			if loaded and killed: draw_card()
		"deploy":
			artillery_mode = "attack"
			if free_card_uid > 0: refresh_free_card()
			if not deploy_draw_used:
				deploy_draw_used = true
				for draw in 3: draw_card()
			log_line("展开为攻击姿态。")
		"pack":
			artillery_mode = "march"
			if free_card_uid > 0: refresh_free_card()
			log_line("转进行军，免费移动额度不变。")
		"tuna":
			tuna_turns += 3
			effect("tuna", cell_pos(player), cell_pos(player), 0.35)
			log_line("吐纳：未来%d回合能量+1。" % tuna_turns)
		"horse", "straight":
			var origin = player
			move_piece({}, cell_pos(player), cell_pos(p), 0, id == "horse")
			player = p;record_active_displacement(origin);card_move_used = true;draw_card()
		"suppress":
			draw_card()
			for enemy in enemies:
				if enemy.kind != "stake" and absi(enemy.pos.x - player.x) + absi(enemy.pos.y - player.y) == 1:
					enemy.cd += 2;enemy.intent = Vector2i(-1, -1)
					if ENCOUNTERS.uses_action_credits(self): enemy.action_credit_delay = int(enemy.get("action_credit_delay", 0)) + 2
		"guard":
			shield_charges = 1
			effect("guard", cell_pos(player), cell_pos(player), 0.35)
		"reload": reload_ready = true
		"life": lives += 1;effect("life", cell_pos(player), cell_pos(player), 0.4)
		"sweep":
			for j in range(enemies.size() - 1, -1, -1):
				if enemies[j].kind != "stake" and in_neighbor_square(enemies[j].pos):
					effect("sword", cell_pos(player), cell_pos(enemies[j].pos), 0.3)
					damage_enemy(j)
	if not general_alive(): settle_victory()
	tutorial_after("play", {"index": i, "target": p, "card": id})
func settle_victory():
	if lives <= 0: return
	if screen != "game" or phase not in ["play", "discard"]: return
	cancel_gesture();clear_effects();rewardui.reset();clear_battle_card_effects()
	ENCOUNTERS.cancel_pending(self)
	if route.active():
		history.clear()
		route.battle_victory()
	selected = -1;free_selected = false;reinforcement_pending = 0;input_lock = 0;navigation_lock = 0
	var chapter_boss = route.active() and route.state.pending >= 0 and route.state.nodes[route.state.pending].kind == "boss"
	if (chapter_boss or stage == CAMPAIGN.LAST_STAGE) and not tutorial.active: skill_system.unlock_horse()
	if (chapter_boss and route.chapter() == 2) or (not route.active() and stage == CAMPAIGN.LAST_STAGE):
		phase = "win";log_line("章节突破！" if route.active() else "六关突破！")
		if route.active(): route.state.done = true;route.save()
	else:
		phase = "reward";roll_rewards()
		if route.active():
			rewards = [] if route.rewards_blocked() else route.state.nodes[route.state.pending].loot.duplicate()
			route.save()
	presentation.victory()
func debug_skip_rect() -> Rect2:
	if compact_landscape: return Rect2(410, 440, 116, 44)
	if mobile_layout: return Rect2(352, 64, 116, 40)
	return Rect2(1040, 80, 116, 44)
func debug_skip():
	if not settings.debug_mode: return
	if tutorial.active or screen != "game" or phase not in ["play", "discard"]: return
	settle_victory()

func plan_intents():
	# Warning is countdown-only. Never choose or reveal a future square during player play.
	for e in enemies: e.intent = Vector2i(-1, -1)
func end_turn():
	if screen != "game" or phase != "play" or not tutorial_allows("end_turn"): return
	history.record("end_turn");cancel_gesture()
	if recovery_active(): log_line("空投休整：跳过本回合行动，敌方正常行动。")
	selected = -1;free_selected = false;reload_ready = false
	input_lock = 0.3
	resolve_bleeds()
	if phase != "play": return

	var timeline = 0.0
	var hit = false
	var attacker: Dictionary = {}
	var blocked_attackers: Array = []
	for e in enemies:
		if R.attacks(e, player, enemies):
			if shield_charges > 0:
				shield_charges = 0;blocked_attackers.append(e)
				effect("guard", cell_pos(e.pos), cell_pos(player), 0.26)
				log_line("固守抵挡一次受击。")
				continue
			effect("player_hit", cell_pos(e.pos), cell_pos(player), 0.26)
			timeline = 0.26
			lives -= 1;hit = true;attacker = e;log_line("被%s击中，失去一命。" % piece_name(e.kind))
			if lives <= 0: phase = "dead";clear_battle_card_effects();ENCOUNTERS.cancel_pending(self);notice = "命数耗尽。";return
			var safe = R.safe_recoil(player, enemies)
			if safe.is_empty(): phase = "dead";clear_battle_card_effects();ENCOUNTERS.cancel_pending(self);notice = "无安全位置可撤退。";return
			var destination = safe[rng.randi_range(0, safe.size() - 1)]
			effect("recoil", cell_pos(player), cell_pos(destination), 0.34, timeline)
			timeline += 0.34
			player = destination;break

	# Lock rotation and grant final-battle credits once, before any movement.
	var credit_mode = ENCOUNTERS.uses_action_credits(self)
	ENCOUNTERS.prepare_phase(self)
	# Decide readiness once for the whole army, after attacks/recoil. Joint plans
	# can then choose a legal support-first or cannon-first execution order.
	var ready = {};var credit_ready_by_uid = {}
	for e in enemies:
		if e.kind == "stake" or e.stun > 0: continue
		e.cd -= 1
		var credit_delayed = credit_mode and int(e.get("action_credit_delay", 0)) > 0
		if credit_delayed: e.action_credit_delay -= 1
		var credit_ready = credit_mode and int(e.get("action_credits", 0)) > 0 and not credit_delayed
		if e.cd <= 0 or credit_ready:
			if e == attacker or e in blocked_attackers: e.cd = e.period;continue
			ready[e.uid] = true;credit_ready_by_uid[e.uid] = credit_ready
	var next_rotation = -1
	if credit_mode and ENCOUNTERS.has_rule(self,"palace_rotation"):
		var guards = []
		for ally in enemies:
			if ally.uid in encounter_state.guard_uids: guards.append(ally.uid)
		if not guards.is_empty(): next_rotation = guards[(int(encounter_state.phases)+1)%guards.size()]
	var ai_context = {"encounter_state":encounter_state,"next_rotation_uid":next_rotation,"player_skill":player_skill,"artillery_mode":artillery_mode,"credit_mode":credit_mode,"credit_ready":credit_ready_by_uid}
	var coordination = ENEMY_AI.CP.plan(enemies,player,ready,ai_context) if not tutorial.active else {"order":ready.keys(),"targets":{}}
	var acted_uids = {}
	for uid in coordination.order:
		if acted_uids.has(uid) or not ready.has(uid): continue
		acted_uids[uid] = true
		var index = ENEMY_AI.CP.by_uid(enemies,uid)
		if index < 0: continue
		var e = enemies[index]
		var options = R.moves(e,enemies,player)
		var target: Vector2i = coordination.targets.get(uid,Vector2i(-1,-1))
		var deliberate_hold = target == e.pos and not options.is_empty()
		if not deliberate_hold and target not in options:
			target = ENEMY_AI.choose(e,options,enemies,player,rng,ai_context,not tutorial.active)
			deliberate_hold = target == e.pos and not options.is_empty()
		if deliberate_hold:
			# A voluntary tactical hold completes one action; inability to move does not.
			if credit_ready_by_uid.get(uid,false): e.action_credits -= 1
		elif target in options:
			var origin: Vector2i = e.pos
			move_piece(e,cell_pos(origin),cell_pos(target),timeline,e.kind == "h")
			timeline += 0.28;e.pos = target;ENEMY_AI.CP.remember(e,origin)
			ENCOUNTERS.after_normal_move(self,e,origin,credit_ready_by_uid.get(uid,false))
			if credit_ready_by_uid.get(uid,false): e.action_credits -= 1
		e.cd = e.period
	for e in enemies:
		if e.stun > 0: e.stun -= 1
	# Chapter-two arrivals inspect the final board, after expiring temporary stakes.
	# Keep the original chapter-one reinforcement ordering unchanged.
	var chapter_two = ENCOUNTERS.is_chapter_two(self)
	if chapter_two: TACTICS.expire_stakes(self, maxf(timeline, input_lock))
	if ENCOUNTERS.active(self): ENCOUNTERS.finish_phase(self, timeline)
	else: resolve_reinforcements(timeline)
	if not chapter_two: TACTICS.expire_stakes(self, maxf(timeline, input_lock))
	turn += 1;history.trim()
	if airdrop_recovery_turn > 0 and turn > airdrop_recovery_turn: airdrop_recovery_turn = 0
	shield_charges = 0;active_displacements = 0
	plan_intents()
	tuna_active = tuna_turns > 0
	if tuna_active: tuna_turns -= 1
	energy = maxi(0, (4 if tuna_active else 3) - hand.count("fatigue"))
	basic_used = false;card_move_used = false;deploy_draw_used = false;initial_threat = 2.0
	refresh_free_card()
	notice = "空投休整：本回合不能移动或出牌，请结束回合。" if recovery_active() else ("受击后已撤退；重新规划路线。" if hit else "新回合：移动抽牌，组合出招。")
	tutorial_after("end_turn")
func resolve_reinforcements(timeline: float):
	if stage != 3 or phase != "play": return
	var general_alive = false
	for e in enemies:
		if e.kind == "g": general_alive = true
	if not general_alive: return
	reinforcement_turns += 1
	if reinforcement_turns % 3 == 0: reinforcement_pending += 1
	if reinforcement_pending <= 0: return
	var empty: Array = []
	for x in 9:
		var p = Vector2i(x, 0)
		if p != player and R.occupied(p, enemies) < 0: empty.append(p)
	if empty.is_empty(): return
	var spawn: Vector2i = empty[rng.randi_range(0, empty.size() - 1)]
	add_enemy("h", spawn, 3)
	var e = enemies.back()
	effect("spawn", cell_pos(spawn), cell_pos(spawn), 0.65, timeline, {"piece": e})
	reinforcement_pending -= 1
func piece_name(k: String) -> String:
	return {"p": "卒", "q": "卒", "a": "士", "e": "象", "g": "将", "c": "炮", "r": "车", "h": "马", "stake": "桩"}.get(k, k)
func text_at(p: Vector2, s: String, size: int = 20, color: Color = INK): draw_string(FONT, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
func wrapped_text(value: String, rect: Rect2, font_size: int = 16, color: Color = INK):
	var line = ""; var y = rect.position.y + font_size
	for letter in value:
		if letter == "\n":
			if y > rect.end.y: return
			text_at(Vector2(rect.position.x, y), line, font_size, color);line = "";y += font_size + 3
			continue
		if not line.is_empty() and FONT.get_string_size(line + letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > rect.size.x:
			if y > rect.end.y: return
			text_at(Vector2(rect.position.x, y), line, font_size, color);line = "";y += font_size + 3
		line += letter
	if not line.is_empty() and y <= rect.end.y: text_at(Vector2(rect.position.x, y), line, font_size, color)
func panel(rect: Rect2, color: Color, border: Color = Color.TRANSPARENT):
	draw_style_box(box(color, border), rect)
func box(color: Color, border: Color) -> StyleBoxFlat:
	var b = StyleBoxFlat.new();b.bg_color = color;b.border_color = border;b.set_border_width_all(1);b.set_corner_radius_all(10);return b
func context_hint() -> String:
	if tutorial.active: return tutorial.hint()
	if phase == "discard": return "手牌超限：请选择1张普通牌弃置"
	if phase != "play": return ""
	if recovery_active(): return "空投休整：不能移动或出牌，请结束回合。"
	if R.threatened(player, enemies): return "将军！结束回合前解除威胁。"
	if free_selected: return "选择免费移动落点，或再次点牌取消。"
	if player_skill == "artillery" and selected < 0:
		return "攻击姿态：正交走1格；炮击1费2伤；转进牌切回行军。" if artillery_mode == "attack" else "行军姿态：正交走1～2格；展开抽3张（每回合首次）。"
	if selected >= 0: return "点击高亮目标；再点选中牌取消。" if mobile_layout else "选择高亮目标；右键 / Esc 取消。"
	if notice in ["能量不足。", "本回合已使用移动牌。", "牌库与弃牌堆已空。"]: return notice
	var idx = R.occupied(hover, enemies)
	if idx >= 0:
		var e = enemies[idx]
		if e.kind == "stake": return "机关炮架 · 持续本场战斗" if e.get("permanent", false) else "木桩 · 挡路与炮架 · 剩余%d回合" % int(e.get("ttl", 3))
		var credit_label = ""
		var credits = ENCOUNTERS.available_action_credits(self, e, true)
		if credits > 0: credit_label = " · 加速%d次" % credits
		return "%s · %d/%d血 · 倒计时%d%s%s" % [(ENCOUNTERS.enemy_tags(e) + piece_name(e.kind) if ENCOUNTERS.enemy_tags(e) != "" else ("急行卒" if e.kind == "q" else piece_name(e.kind))), e.hp, e.max_hp, ENCOUNTERS.effective_countdown(self, e), credit_label, " · 定身中" if e.stun > 0 else ""]
	return ENCOUNTERS.status(self)
func _draw():
	if card_picker.active: card_picker.draw();return
	if screen in ["map", "route_choice"]:
		route.draw();presentation.draw();return
	if screen != "game":
		frontend.draw()
		return
	draw_rect(Rect2(Vector2.ZERO, ui_size), THEME.BACKGROUND)
	if settings.debug_mode and not tutorial.active and phase in ["play", "discard"]:
		panel(debug_skip_rect(), THEME.BUTTON);text_at(debug_skip_rect().position + Vector2(8, 24), "调试跳过", 18)
	if not mobile_layout or compact_landscape: text_at(mobile_title_pos(), "弈 行", 28, THEME.HEADING)
	panel(RESTART_RECT, THEME.BUTTON);text_at(RESTART_RECT.position + Vector2(16, 32 if mobile_layout else 27), "教学菜单" if tutorial.active else "重新开局", 18)
	var heading_pos = (Vector2(390, 46) if compact_landscape else Vector2(24, 88)) if mobile_layout else Vector2(500, 47)
	var heading = tutorial.title() if tutorial.active else (("调试 · " if debug_target > 0 else "") + "第 %d / 6 关   回合 %d" % [stage, turn] + " · " + PROFILES.DATA[player_skill].name)
	if route.active() and route.state.pending >= 0:
		var node = route.state.nodes[route.state.pending]
		heading = "%s · %s · 回合%d" % [ENCOUNTERS.title(node.encounter), {"battle": "普通", "elite": "精锐", "boss": "决战"}.get(node.kind, ""), turn]
	var heading_size = 16 if tutorial.active else 20
	var heading_width = ui_size.x - 48 if mobile_layout and not compact_landscape else RESTART_RECT.position.x - heading_pos.x - 12
	while heading_size > 12 and FONT.get_string_size(heading, HORIZONTAL_ALIGNMENT_LEFT, -1, heading_size).x > heading_width: heading_size -= 1
	text_at(heading_pos, heading, heading_size, THEME.HEADING)
	panel(BOARD_RECT, THEME.BOARD, THEME.BORDER)
	for x in 9: draw_line(cell_pos(Vector2i(x, 0)), cell_pos(Vector2i(x, 9)), THEME.GRID, 1.5 if mobile_layout else 1.0, true)
	for y in 10: draw_line(cell_pos(Vector2i(0, y)), cell_pos(Vector2i(8, y)), THEME.GRID, 1.5 if mobile_layout else 1.0, true)
	draw_rect(Rect2(O + Vector2(-3, 4.15 * CELL), Vector2(8 * CELL + 6, 0.7 * CELL)), THEME.BOARD)
	text_at(O + Vector2(CELL * 1.1, 4.63 * CELL), "楚 河", 22, GOLD);text_at(O + Vector2(CELL * 5.3, 4.63 * CELL), "汉 界", 22, GOLD)
	for top in [0, 7]:
		draw_line(cell_pos(Vector2i(3, top)), cell_pos(Vector2i(5, top + 2)), THEME.GRID)
		draw_line(cell_pos(Vector2i(5, top)), cell_pos(Vector2i(3, top + 2)), THEME.GRID)
	for y in 10:
		for x in 9:
			var p = Vector2i(x, y); var v = cell_pos(p)
			var inspected = R.occupied(hover, enemies)
			var visible_threat = (show_threat or initial_threat > 0) and R.threatened(p, enemies)
			if inspected >= 0 and R.attacks(enemies[inspected], p, enemies): visible_threat = true
			if visible_threat and input_lock <= 0: draw_circle(v, 13, Color(THEME.DANGER, 0.24))
			if input_lock <= 0 and free_selected and basic_legal(p) and ( not tutorial.active or tutorial.is_free_practice() or p in tutorial.target_cells()):
				draw_circle(v, 19, Color(THEME.DANGER, 0.27) if R.threatened(p, enemies) else Color(THEME.SAFE, 0.25))
			if input_lock <= 0 and selected >= 0 and hand[selected] not in UNTARGETED and card_legal(hand[selected], p) and ( not tutorial.active or tutorial.is_free_practice() or p in tutorial.target_cells()):
				var danger = target_danger(hand[selected], p)
				draw_circle(v, 19, Color(THEME.DANGER, 0.27) if danger else Color(THEME.SAFE, 0.25));draw_arc(v, 20, 0, TAU, 24, RED if danger else GOLD, 2)
	if tutorial.active and input_lock <= 0:
		for cell in tutorial.target_cells():
			draw_arc(cell_pos(cell), 25, 0, TAU, 32, GOLD, 3)
	if input_lock <= 0 and selected < 0 and basic_legal(hover) and phase == "play" and ( not tutorial.active or tutorial.is_free_practice()):
		var target = cell_pos(hover); var start = cell_pos(player); var dir = (target - start).normalized()
		var danger_color = RED if R.threatened(hover, enemies) else THEME.SAFE
		draw_circle(target, 20, Color(THEME.DANGER, 0.27) if R.threatened(hover, enemies) else Color(THEME.SAFE, 0.25));draw_line(start, target, danger_color, 3)
		draw_line(target, target - dir.rotated(0.5) * 13, danger_color, 3);draw_line(target, target - dir.rotated( - 0.5) * 13, danger_color, 3)
	if ENCOUNTERS.active(self): draw_encounter_signals()
	for e in enemies:
		if e.kind == "stake":
			draw_stake(cell_pos(e.pos));text_at(cell_pos(e.pos) + Vector2(-4, 26), ("∞" if e.get("permanent", false) else str(e.get("ttl", 3))), 13, THEME.INK);continue
		var hidden_spawn = false
		for fx in effects:
			if fx.kind == "spawn" and fx.piece == e and fx.age < fx.delay + 0.3: hidden_spawn = true
		if hidden_spawn: continue
		var v: Vector2 = e.get("visual", cell_pos(e.pos))
		if input_lock <= 0 and ENCOUNTERS.effective_countdown(self, e) <= 1 and e.stun == 0: v.x += sin(tick * 23) * 1.8
		var flash = 0.0
		for fx in effects:
			if fx.kind == "hit" and fx.get("piece", {}) == e and fx.age >= fx.delay:
				flash = 1 - clampf((fx.age - fx.delay) / fx.duration, 0, 1);v.x += sin(fx.age * 90) * 5 * flash
		var token_origin = v
		if mobile_layout: draw_set_transform(v, 0, Vector2.ONE * minf(1.0, CELL / 54.0));v = Vector2.ZERO
		draw_circle(v + Vector2(1, 3), 24, THEME.SHADOW);draw_circle(v, 23, THEME.PAPER.lerp(Color.WHITE, flash));draw_arc(v, 20, 0, TAU, 32, THEME.GRID, 2)
		text_at(v + Vector2(-14, 9), piece_name(e.kind), 28, THEME.INK)
		if mobile_layout: draw_set_transform(Vector2.ZERO, 0, Vector2.ONE);v = token_origin
		var badge = Vector2(CELL * 0.36, - CELL * 0.36) if mobile_layout else Vector2(20, -20)
		draw_circle(v + badge, 12 if mobile_layout else 10, THEME.SAFE);text_at(v + badge + Vector2(-5, 6), str(ENCOUNTERS.effective_countdown(self, e)), 18 if mobile_layout else 13, THEME.LIGHT)
		var max_hp = e.get("max_hp", enemy_health(e.kind))
		if max_hp > 3:
			var hp_label = "%d/%d" % [e.hp, max_hp]
			var hp_size = 12 if mobile_layout else 14
			var hp_width = FONT.get_string_size(hp_label, HORIZONTAL_ALIGNMENT_LEFT, -1, hp_size).x
			panel(Rect2(v + Vector2(-hp_width * 0.5 - 3, CELL * 0.34), Vector2(hp_width + 6, 17)), THEME.PAPER)
			text_at(v + Vector2(-hp_width * 0.5, CELL * 0.34 + 13), hp_label, hp_size, RED)
		elif max_hp > 1:
			for h in max_hp: draw_circle(v + Vector2((h - (max_hp - 1) * 0.5) * 9, CELL * 0.46 if mobile_layout else 29), 3, RED if h < e.get("hp", max_hp) else THEME.BORDER)
		if e.get("unyielding", false):
			text_at(v + Vector2(-CELL * 0.48, CELL * 0.18), "复", 12, GOLD)
		elif e.get("heavy", false):
			text_at(v + Vector2(-CELL * 0.48, CELL * 0.18), "重", 12, GOLD)
		if e.kind == "q" or e.get("signal", false):
			var rule_badge = v + Vector2(-CELL * 0.36, -CELL * 0.36)
			draw_circle(rule_badge, 10, RED)
			text_at(rule_badge + Vector2(-6, 5), "疾" if e.kind == "q" else "旗", 12, THEME.LIGHT)
		if ENCOUNTERS.available_action_credits(self, e, true) > 0:
			text_at(v + Vector2(-CELL * 0.48, CELL * 0.24), "速%d" % ENCOUNTERS.available_action_credits(self, e, true), 13, RED)
		elif e.get("march_mark", false) or e.get("bonus_pending", false): text_at(v + Vector2(-CELL * 0.48, CELL * 0.24), "+", 15, RED)
		if e.stun > 0: text_at(v + Vector2(-21, 40), "定身", 14, THEME.SAFE)
		var bleed_damage = 0
		for bleed in pending_bleeds:
			if bleed.enemy_uid == e.get("uid", -1): bleed_damage += bleed.amount
		if bleed_damage > 0: text_at(v + Vector2(-18, -CELL * 0.48), "血%d" % bleed_damage, 13, RED)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var pv = player_visual
	if shield_charges > 0: draw_arc(pv, CELL * 0.47, 0, TAU, 32, THEME.SAFE, 3)
	if input_lock <= 0 and R.threatened(player, enemies): pv.x += sin(tick * 29) * 2;draw_arc(pv, 29, 0, TAU, 32, RED, 3)
	var player_flash = 0.0
	for fx in effects:
		if fx.kind == "player_hit": player_flash = maxf(player_flash, 1 - clampf(fx.age / fx.duration, 0, 1))
	pv.x += sin(tick * 90) * 4 * player_flash
	if mobile_layout: draw_set_transform(pv, 0, Vector2.ONE * minf(1.0, CELL / 54.0));pv = Vector2.ZERO
	draw_circle(pv, 24, THEME.DANGER.lerp(Color.WHITE, player_flash));draw_arc(pv, 20, 0, TAU, 32, GOLD, 2);text_at(pv + Vector2(-14, 9), ("炮" if artillery_mode == "attack" else "行") if player_skill == "artillery" else ("马" if player_skill == "horse" else "帅"), 28, THEME.LIGHT)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	text_at((Vector2(24, 500) if compact_landscape else Vector2(24, BOARD_RECT.end.y + 36)) if mobile_layout else Vector2(397, 609), "命 %s" % "●".repeat(lives), 20, THEME.LIGHT)
	text_at((Vector2(200, 500) if compact_landscape else Vector2(150, BOARD_RECT.end.y + 36)) if mobile_layout else Vector2(550, 609), "能量 %d" % energy, 20, THEME.LIGHT)
	var confirm = selected >= 0 and (phase == "discard" or (phase == "play" and hand[selected] in UNTARGETED))
	panel(END_TURN_RECT, THEME.PAPER_SELECTED, RED if phase == "discard" else Color.TRANSPARENT);text_at(END_TURN_RECT.position + Vector2(12, 32), ("确认弃牌" if selected >= 0 else "请选择弃牌") if phase == "discard" else ("使用选中牌" if confirm else (("跳过回合" if mobile_layout else "跳过回合 [空格]") if recovery_active() else ("结束回合" if mobile_layout else "结束回合 [空格]"))), 18, THEME.INK)
	var statuses: Array[String] = []
	if tuna_active or tuna_turns > 0: statuses.append(("吐纳 本回合+1" if tuna_active else "吐纳") + " 后续%d回合" % tuna_turns)
	if shield_charges > 0: statuses.append("固守 1次")
	if reload_ready: statuses.append("装填 下次炮击+1")
	if player_skill == "horse": statuses.append("主动位移 %d次" % active_displacements)
	if not statuses.is_empty():
		var status = " · ".join(statuses)
		text_at(Vector2(410, 410) if compact_landscape else (Vector2(24, minf(BOARD_RECT.end.y + 62, full_hand_area().position.y - 8)) if mobile_layout else Vector2(24, 602)), status, 14, THEME.HEADING)
	var hint = context_hint()
	if not hint.is_empty() and input_lock <= 0: text_at((Vector2(410, 130) if compact_landscape else Vector2(24, 105)) if mobile_layout else Vector2(24, 618), hint, 14 if mobile_layout else 16, RED if phase == "discard" or R.threatened(player, enemies) else THEME.HEADING)
	draw_effects()
	if phase == "discard": draw_rect(full_hand_area().grow(2), RED, false, 3)
	handui.draw()
	gesture.draw()
	if presentation.active(): presentation.draw();return
	if phase == "reward" and input_lock <= 0: rewardui.draw()
	if phase in ["dead", "win"] and input_lock <= 0:
		draw_rect(Rect2(Vector2.ZERO, ui_size), THEME.OVERLAY);text_at(Vector2(24, ui_size.y * 0.4) if mobile_layout else Vector2(410, 380), ("山河已定 · 两章通关" if route.active() else "六关突破 · 原型通关") if phase == "win" else "此局已尽 · 再弈一局", 28 if mobile_layout else 36, THEME.HEADING)
		text_at(Vector2(24, ui_size.y * 0.4 + 50) if mobile_layout else Vector2(430, 435), "重新开局，再行山河" if phase == "win" else "可悔棋，或重新开局", 20, THEME.LIGHT)
		if phase == "win" and route.rewards_blocked():
			text_at(Vector2(24, ui_size.y * 0.4 + 90) if mobile_layout else Vector2(410, 480), route.homework_summary(), 18, THEME.LIGHT)
		if phase == "dead": text_at(Vector2(24, ui_size.y * 0.4 + 90) if mobile_layout else Vector2(480, 480), notice, 20, RED)
		panel(RESTART_RECT, THEME.PAPER_SELECTED);text_at(RESTART_RECT.position + Vector2(16, 32 if mobile_layout else 27), "重新开局", 18, THEME.INK)

	panel(UNDO_RECT, THEME.BUTTON, GOLD if history.can_undo() else THEME.BORDER);text_at(UNDO_RECT.position + Vector2(8, 29), undo_label(), 14 if mobile_layout else 16)
	panel(home_rect(), THEME.BUTTON);text_at(home_rect().position + Vector2(10, 29 if mobile_layout else 27), "首页" if mobile_layout else "返回首页", 18)

	if mobile_layout and ENCOUNTERS.active(self) and phase in ["play", "discard"]:
		panel(encounter_rules_rect(), THEME.BUTTON);text_at(encounter_rules_rect().position + Vector2(8, 29), "军阵", 16, THEME.INK)
	if encounter_info_open: draw_encounter_panel()

func draw_stake(position: Vector2, alpha: float = 1.0):
	var radius = minf(20, CELL * 0.32)
	draw_rect(Rect2(position - Vector2(radius, radius), Vector2(radius * 2, radius * 2)), Color(0.48, 0.34, 0.21, alpha))
	draw_line(position + Vector2( - radius, - radius), position + Vector2(radius, radius), Color(0.8, 0.65, 0.4, alpha), 3)
	draw_line(position + Vector2( - radius, radius), position + Vector2(radius, - radius), Color(0.8, 0.65, 0.4, alpha), 3)
func draw_effects():
	for fx in effects:
		if fx.age < fx.delay:
			if fx.kind == "stake_expire": draw_stake(fx.to)
			if fx.kind == "death":

				var v: Vector2 = fx.to
				var flash = fx.age >= fx.impact
				if flash: v.x += sin(fx.age * 90) * 4
				draw_circle(v, 23, Color.WHITE if flash else THEME.PAPER)
				draw_arc(v, 20, 0, TAU, 32, THEME.GRID, 2)
				text_at(v + Vector2(-14, 9), fx.symbol, 28, THEME.INK)
			continue
		var t = clampf((fx.age - fx.delay) / fx.duration, 0, 1)
		var fade = 1 - t
		var a: Vector2 = fx.from
		var b: Vector2 = fx.to
		match fx.kind:
			"stake_place": draw_arc(b, 18 + t * 15, 0, TAU, 24, Color(0.85, 0.68, 0.4, fade), 3)
			"stake_expire": draw_stake(b, fade)
			"stance", "tuna":
				draw_arc(b, 25 + t * 12, 0, TAU, 24, Color(THEME.SAFE, fade), 3)
				text_at(b + Vector2(-24, -32 - t * 15), "转进" if fx.kind == "stance" else "蓄气", 18, Color(THEME.SAFE, fade))
			"guard":
				draw_arc(b, 25 + t * 12, 0, TAU, 24, Color(THEME.SAFE, fade), 4)
				text_at(b + Vector2(-24, -32 - t * 15), "固守", 18, Color(THEME.SAFE, fade))
			"breath":
				draw_arc(b, 25 + t * 12, 0, TAU, 24, Color(THEME.SAFE, fade), 3)
				text_at(b + Vector2(-24, -32 - t * 20), "+1气", 20, Color(THEME.SAFE, fade))
			"spawn":
				draw_arc(b, 28 + sin(t * PI) * 10, 0, TAU, 32, Color(0.95, 0.75, 0.35, fade), 3)
				if t < 0.46:
					draw_line(b + Vector2(-16, 0), b + Vector2(16, 0), GOLD, 2)
					draw_line(b + Vector2(0, -16), b + Vector2(0, 16), GOLD, 2)
					text_at(b + Vector2(-8, -34), "援", 16, GOLD)
			"sword":
				draw_arc(b, 22, -1.2 + t * 1.2, 1.0 + t * 1.2, 18, Color(1, 0.9, 0.65, fade), 5)
			"spear":
				var tip = a.lerp(b, minf(1, t * 2)); var direction = (b - a).normalized()
				draw_line(tip - direction * 36, tip, Color(1, 0.88, 0.58, fade), 4)
				draw_line(tip, tip - direction.rotated(0.5) * 12, Color(1, 0.95, 0.8, fade), 3)
				draw_line(tip, tip - direction.rotated( - 0.5) * 12, Color(1, 0.95, 0.8, fade), 3)
			"cannon":
				var v = a.lerp(b, t) - Vector2(0, sin(t * PI) * 50)
				draw_circle(v, 7, Color(0.8, 0.85, 0.8, 1));draw_line(v, v - (b - a).normalized() * 15, Color(0.8, 0.85, 0.8, 0.4), 4)
			"death":
				for j in 8:
					var direction = Vector2.from_angle(j * TAU / 8)
					var v = b + direction * (12 + t * 35) + Vector2(0, t * t * 22)
					draw_colored_polygon(PackedVector2Array([v + direction * 7, v + direction.rotated(2) * 6, v + direction.rotated(-2) * 6]), Color(0.85, 0.77, 0.6, fade))
			"player_hit":
				draw_line(a, b, Color(1, 0.35, 0.25, fade), 4)
				draw_arc(b, 27 + t * 14, 0, TAU, 32, Color(1, 0.3, 0.2, fade), 3)
				text_at(b + Vector2(-15, -34 - t * 15), "−1", 24, Color(1, 0.55, 0.4, fade))
			"recoil":
				for j in 4:
					var u = maxf(0, t - j * 0.12); var v = a.lerp(b, u * u * (3 - 2 * u))
					draw_circle(v, 23, Color(0.8, 0.3, 0.2, (1 - float(j) / 4) * 0.22 * fade))
				draw_arc(b, 27, 0, TAU, 32, Color(0.5, 0.9, 0.8, sin(t * PI)), 2)
			"stun":
				draw_arc(b, 29 + t * 8, 0, TAU, 32, Color(0.5, 1, 0.9, fade), 3)
				draw_line(b + Vector2(-13, -18), b + Vector2(13, 18), Color(0.6, 1, 0.9, fade), 3)
				draw_line(b + Vector2(13, -18), b + Vector2(-13, 18), Color(0.6, 1, 0.9, fade), 3)
			"push":
				var v = a.lerp(b, t)
				draw_arc(v, 20, - 0.7 + (b - a).angle(), 0.7 + (b - a).angle(), 12, Color(0.8, 0.95, 0.7, fade), 4)
			"life":
				draw_arc(b, 27 + t * 16, 0, TAU, 32, Color(THEME.SAFE, fade), 3)
				text_at(b + Vector2(-16, -30 - t * 24), "+1", 24, Color(THEME.SAFE, fade))
			"card_use":
				var rect = Rect2(a.lerp(b, t), fx.size)
				panel(rect, Color(THEME.PAPER, fade), Color(THEME.BORDER, fade))
				text_at(rect.position + Vector2(15, 35), CARDS[fx.card][0], 24, Color(THEME.INK, fade))

func draw_mobile_hand_controls(): pass

func draw_encounter_signals():
	for marker in ENCOUNTERS.markers(self):
		var point = cell_pos(marker.pos)
		var color = GOLD if marker.kind == "revival" else RED
		draw_arc(point, CELL * 0.34, 0, TAU, 20, Color(color, 0.55), 1.5)
		text_at(point + Vector2(-CELL * 0.38, CELL * 0.40), marker.label, 11, color)
	var spawn: Vector2i = encounter_state.get("spawn_cell", Vector2i(-1, -1))
	if R.inside(spawn):
		draw_rect(Rect2(cell_pos(spawn) - Vector2.ONE * CELL * 0.42, Vector2.ONE * CELL * 0.84), Color(RED, 0.2))
		text_at(cell_pos(spawn) + Vector2(-17, 5), "援马", 13, RED)
	if ENCOUNTERS.has_rule(self, "palace_rotation"):
		var guard_uid = ENCOUNTERS.selected_guard(self)
		for enemy in enemies:
			if enemy.uid == guard_uid: draw_arc(cell_pos(enemy.pos), CELL * 0.46, 0, TAU, 28, GOLD, 2)
	if not mobile_layout:
		var area = Rect2(24, 144, 350, 244)
		panel(area, THEME.PAPER)
		text_at(area.position + Vector2(16, 30), ENCOUNTERS.title(encounter_state.config), 24, THEME.INK)
		var desc = ENCOUNTERS.details(encounter_state.config)
		if desc.is_empty(): desc = "普通军阵：棋子按象棋规则行动。先攻击，再按倒计时移动。"
		wrapped_text(desc, Rect2(area.position + Vector2(16, 43), Vector2(318, 150)), 15, THEME.INK)
		wrapped_text(ENCOUNTERS.status(self), Rect2(area.position + Vector2(16, 195), Vector2(318, 40)), 15, RED)

func encounter_rules_rect() -> Rect2:
	return Rect2(540, 440, 124, 44) if compact_landscape else Rect2(240, BOARD_RECT.end.y + 8, 56, 48)
func encounter_panel_rect() -> Rect2:
	return Rect2(Vector2(24, 110) if not compact_landscape else Vector2(200, 90), Vector2(ui_size.x - 48, minf(400, ui_size.y - 160)) if not compact_landscape else Vector2(560, 360))
func encounter_close_rect() -> Rect2:
	var area = encounter_panel_rect()
	return Rect2(area.position.x + 16, area.end.y - 66, area.size.x - 32, 50)
func draw_encounter_panel():
	draw_rect(Rect2(Vector2.ZERO, ui_size), THEME.OVERLAY)
	var area = encounter_panel_rect()
	panel(area, THEME.PAPER)
	text_at(area.position + Vector2(16, 34), ENCOUNTERS.title(encounter_state.config), 24, THEME.INK)
	var desc = ENCOUNTERS.details(encounter_state.config)
	if desc.is_empty(): desc = "普通军阵：先攻击，再按倒计时移动。士限九宫，象不过河，急行卒仍按卒的方向走。"
	if not ENCOUNTERS.is_chapter_two(self): desc += "\n每个敌方回合最多移动一次；多余加速顺延，不额外攻击。"
	wrapped_text(desc, Rect2(area.position + Vector2(16, 53), Vector2(area.size.x - 32, area.size.y - 148)), 18, THEME.INK)
	panel(encounter_close_rect(), THEME.PAPER_SELECTED)
	text_at(encounter_close_rect().position + Vector2(16, 32), "关闭 · 返回棋盘", 18, THEME.INK)
