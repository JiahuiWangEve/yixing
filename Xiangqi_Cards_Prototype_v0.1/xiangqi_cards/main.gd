extends Control
const R=preload("res://rules.gd")
const FONT=preload("res://assets/font.ttc")
const O=Vector2(70,137)
const CELL=57.0
const INK=Color("e9dcc2")
const GOLD=Color("d9af65")
const RED=Color("e87864")
const CARDS={
 "sword":["短剑",1,"击败正交相邻的一个敌子", "攻"],
 "spear":["长枪",2,"击败直线两格内敌子，不穿透", "攻"],
 "horse":["踏马",1,"按马步移动，遵守蹩马腿；抽1张", "移"],
 "cannon":["投石",2,"直线隔恰好一子，击败目标", "攻"],
 "sweep":["横扫",2,"击败周围正交相邻的所有敌子", "攻"],
 "push":["退敌",1,"将相邻敌子推远一格，需空位", "术"],
 "straight":["疾行",1,"直线移动至多两格，不穿透；抽1张", "移"],
 "stun":["定身符",1,"两格内敌子下次敌方阶段无法移动或攻击", "术"],
 "life":["续命",2,"生命+1，上限5；本关消耗", "术"]}
var rng=RandomNumberGenerator.new()
var seed_value=20261019
var player=Vector2i(4,9)
var enemies:Array=[]
var deck:Array=[]
var discard:Array=[]
var hand:Array=[]
var collection:Array=[]
var rewards:Array=[]
var stage=1
var turn=1
var lives=3
var energy=3
var basic_used=false
var card_move_used=false
var selected=-1
var hover=Vector2i(-1,-1)
var phase="play"
var show_threat=false
var initial_threat=2.0
var tick=0.0
var logs:Array=[]
var notice=""
var player_visual=Vector2.ZERO
var input_lock=0.0
func _ready():
 mouse_filter=Control.MOUSE_FILTER_STOP
 new_run()
 if "--screenshot" in OS.get_cmdline_user_args():
  await get_tree().create_timer(0.8).timeout
  await RenderingServer.frame_post_draw
  get_viewport().get_texture().get_image().save_png("res://preview.png")
  get_tree().quit()
func new_run():
 rng.seed=seed_value
 stage=1;lives=3
 collection=["sword","sword","sword","sword","spear","spear","horse","horse"]
 logs=[]
 start_stage()
func shuffle(a:Array):
 for i in range(a.size()-1,0,-1):
  var j=rng.randi_range(0,i)
  var tmp=a[i];a[i]=a[j];a[j]=tmp
func add_enemy(kind:String,p:Vector2i,cd:int):
 enemies.append({"kind":kind,"pos":p,"cd":cd,"period":cd,"stun":0,"visual":cell_pos(p)})
func start_stage():
 input_lock=0.0
 player=Vector2i(4,9);player_visual=cell_pos(player);enemies=[];turn=1;energy=3;basic_used=false;card_move_used=false;selected=-1
 hand=[];discard=[];deck=collection.duplicate();shuffle(deck)
 add_enemy("g",Vector2i(4,0),3)
 add_enemy("p",Vector2i(2,3),2);add_enemy("p",Vector2i(6,3),2)
 if stage>=2: add_enemy("p",Vector2i(4,3),2)
 if stage>=3: add_enemy("e",Vector2i(2,0),3)
 plan_intents()
 phase="play";initial_threat=2.0;notice="向前一步，抽取你的第一张牌。"
 log_line("第%d关 · %s"%[stage,["初入棋局","三兵压境","象守中军"][stage-1]])
func log_line(s:String):
 logs.push_front(s)
 if logs.size()>7: logs.pop_back()
func _process(delta):
 tick+=delta;initial_threat=maxf(0,initial_threat-delta)
 input_lock=maxf(0,input_lock-delta)
 player_visual=player_visual.lerp(cell_pos(player),minf(1,delta*18))
 for e in enemies:e.visual=e.get("visual",cell_pos(e.pos)).lerp(cell_pos(e.pos),minf(1,delta*18))
 queue_redraw()
func cell_pos(p:Vector2i)->Vector2: return O+Vector2(p)*CELL
func board_cell(pos:Vector2)->Vector2i:
 var p=Vector2i(roundi((pos.x-O.x)/CELL),roundi((pos.y-O.y)/CELL))
 if R.inside(p) and pos.distance_to(cell_pos(p))<28: return p
 return Vector2i(-1,-1)
func basic_legal(p:Vector2i)->bool:
 return R.inside(p) and not basic_used and abs(p.x-player.x)+abs(p.y-player.y)==1 and R.occupied(p,enemies)<0
func card_legal(id:String,p:Vector2i)->bool:
 if not R.inside(p): return false
 var d=p-player
 var dist=abs(d.x)+abs(d.y)
 var idx=R.occupied(p,enemies)
 match id:
  "sword": return idx>=0 and dist==1
  "spear": return idx>=0 and dist<=2 and R.blockers(player,p,enemies)==0
  "cannon": return idx>=0 and R.blockers(player,p,enemies)==1
  "stun": return idx>=0 and dist<=2
  "push":
   if idx<0 or dist!=1 or (d.x!=0 and d.y!=0): return false
   var dest=p+Vector2i(signi(d.x),signi(d.y))
   return R.inside(dest) and R.occupied(dest,enemies)<0 and dest!=player
  "horse":
   if idx>=0 or card_move_used: return false
   if not ((abs(d.x)==2 and abs(d.y)==1) or (abs(d.x)==1 and abs(d.y)==2)): return false
   return R.occupied(player+Vector2i(signi(d.x) if abs(d.x)==2 else 0,signi(d.y) if abs(d.y)==2 else 0),enemies)<0
  "straight": return idx<0 and not card_move_used and dist>0 and dist<=2 and R.blockers(player,p,enemies)==0
 return false
func draw_card():
 if deck.is_empty(): deck=discard.duplicate();discard=[];shuffle(deck)
 if deck.is_empty(): notice="牌库与弃牌堆已空。";return
 var id=deck.pop_back();hand.append(id);log_line("抽到「%s」"%CARDS[id][0])
 if hand.size()>6: phase="discard";notice="手牌上限6：点击一张手牌弃置。"
func hand_rect(i:int)->Rect2:
 var step=174 if hand.size()>6 else 202
 return Rect2(30+i*step,710,step-12,158)
func _gui_input(event):
 if event is InputEventMouseMotion: hover=board_cell(event.position)
 if event is InputEventMouseButton and event.pressed:
  if event.button_index==MOUSE_BUTTON_RIGHT: selected=-1;return
  if event.button_index!=MOUSE_BUTTON_LEFT:return
  if input_lock>0:return
  var pos=event.position
  if Rect2(1110,25,130,40).has_point(pos): new_run();return
  if Rect2(600,605,210,42).has_point(pos):show_threat=not show_threat;return
  if phase=="reward":
   for i in rewards.size():
    if Rect2(220+i*285,310,260,190).has_point(pos):collection.append(rewards[i]);stage+=1;start_stage();return
   if Rect2(530,530,220,50).has_point(pos):stage+=1;start_stage();return
   return
  if phase in ["dead","win"]:return
  for i in hand.size():
   if hand_rect(i).has_point(pos):
    if phase=="discard":discard.append(hand.pop_at(i));phase="play";selected=-1;notice="已弃置，继续行动。";return
    if energy<CARDS[hand[i]][1]:notice="能量不足。";return
    if CARDS[hand[i]][3]=="移" and card_move_used:notice="本回合已使用移动牌。";return
    if hand[i] in ["sweep","life"]:play_card(i,player);return
    selected=i if selected!=i else -1;notice="点击高亮目标；右键或 Esc 取消。";return
  if phase!="play":return
  if Rect2(970,605,270,60).has_point(pos):end_turn();return
  var p=board_cell(pos)
  if selected>=0:
   if card_legal(hand[selected],p):play_card(selected,p)
  elif basic_legal(p):
   player=p;input_lock=0.18;basic_used=true;notice="基础移动完成，抽1张牌。";draw_card()
func _input(event):
 if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:selected=-1
func play_card(i:int,p:Vector2i):
 if phase!="play" or i<0 or i>=hand.size():return
 var id=hand[i]
 if energy<CARDS[id][1]:notice="能量不足。";return
 if CARDS[id][3]=="移" and card_move_used:notice="本回合已使用移动牌。";return
 if id not in ["sweep","life"] and not card_legal(id,p):notice="这个目标无法使用此牌。";return
 if id=="life" and lives>=5:notice="生命已满，保留此牌。";return
 if id=="sweep":
  var found=false
  for e in enemies:
   if abs(e.pos.x-player.x)+abs(e.pos.y-player.y)==1:found=true
  if not found:notice="周围没有可横扫的敌子。";return
 energy-=CARDS[id][1];hand.remove_at(i);selected=-1
 if id!="life":discard.append(id)
 log_line("使用「%s」"%CARDS[id][0])
 var idx=R.occupied(p,enemies)
 match id:
  "sword","spear","cannon":enemies.remove_at(idx)
  "horse","straight":player=p;input_lock=0.18;card_move_used=true;draw_card()
  "stun":enemies[idx].stun=1
  "push":enemies[idx].pos+=Vector2i(signi(p.x-player.x),signi(p.y-player.y))
  "life":lives+=1
  "sweep":
   for j in range(enemies.size()-1,-1,-1):
    if abs(enemies[j].pos.x-player.x)+abs(enemies[j].pos.y-player.y)==1:enemies.remove_at(j)
 var general=false
 for e in enemies:
  if e.kind=="g":general=true
 if not general:
  if stage==3:phase="win";log_line("三关突破！")
  else:
   phase="reward";rewards=["cannon","sweep","push","straight","stun","life"];shuffle(rewards);rewards=rewards.slice(0,3)
func plan_intents():
 for e in enemies:
  e.intent=Vector2i(-1,-1)
  if e.cd<=1 and e.stun==0:
   var options=R.moves(e,enemies,player)
   if not options.is_empty():
    options.sort_custom(func(a,b):return (a-player).length_squared()<(b-player).length_squared())
    e.intent=options[rng.randi_range(0,mini(3,options.size())-1)]
func end_turn():
 if phase!="play":return
 selected=-1
 input_lock=0.3
 # Every enemy can attack, independent of its movement countdown.
 var hit=false
 var attacker:Dictionary={}
 for e in enemies:
  if R.attacks(e,player,enemies):
   lives-=1;hit=true;attacker=e;log_line("被%s击中，失去一命。"%piece_name(e.kind))
   if lives<=0:phase="dead";notice="命数耗尽。";return
   var safe=R.safe_recoil(player,enemies)
   if safe.is_empty():phase="dead";notice="无安全位置可撤退。";return
   player=safe[rng.randi_range(0,safe.size()-1)];break
 # Stable ordered movement; no new attacks after moving this phase.
 for i in enemies.size():
  var e=enemies[i]
  if e.stun>0:continue
  e.cd-=1
  if e.cd<=0:
   var target:Vector2i=e.get("intent",Vector2i(-1,-1))
   if e!=attacker and target in R.moves(e,enemies,player):
    e.pos=target
   e.cd=e.period
 for e in enemies:
  if e.stun>0:e.stun-=1
 plan_intents()
 turn+=1;energy=3;basic_used=false;card_move_used=false;initial_threat=2.0
 notice="受击后已撤退；重新规划路线。" if hit else "新回合：移动抽牌，组合出招。"
func piece_name(k:String)->String:
 return {"p":"卒","e":"象","g":"将","c":"炮","r":"车","h":"马"}.get(k,k)
func text_at(p:Vector2,s:String,size:int=20,color:Color=INK):draw_string(FONT,p,s,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)
func panel(rect:Rect2,color:Color,border:Color=Color.TRANSPARENT):
 draw_style_box(box(color,border),rect)
func box(color:Color,border:Color)->StyleBoxFlat:
 var b=StyleBoxFlat.new();b.bg_color=color;b.border_color=border;b.set_border_width_all(1);b.set_corner_radius_all(10);return b
func _draw():
 draw_rect(Rect2(0,0,1280,900),Color("121d20"))
 text_at(Vector2(30,46),"弈 行",32,GOLD);text_at(Vector2(137,44),"象棋 × 卡牌   /   可玩原型",18)
 panel(Rect2(1110,25,130,40),Color("26383b"));text_at(Vector2(1135,52),"重新开局",18)
 text_at(Vector2(600,100),"第 %d / 3 关     回合 %d"%[stage,turn],27,GOLD)
 text_at(Vector2(600,143),"命数  %s   / 5"%"●".repeat(lives),24,RED)
 text_at(Vector2(600,182),"能量  %d / 3"%energy,24)
 text_at(Vector2(600,219),"基础移动：%s    移动牌：%s"%["已用" if basic_used else "可用","已用" if card_move_used else "可用"],18)
 text_at(Vector2(600,251),"牌库 %d   弃牌 %d   手牌 %d / 6"%[deck.size(),discard.size(),hand.size()],18)
 panel(Rect2(35,102,527,583),Color("263735"),Color("66705c"))
 for x in 9:draw_line(cell_pos(Vector2i(x,0)),cell_pos(Vector2i(x,9)),Color("697967"),1)
 for y in 10:draw_line(cell_pos(Vector2i(0,y)),cell_pos(Vector2i(8,y)),Color("697967"),1)
 draw_rect(Rect2(O+Vector2(-3,4.15*CELL),Vector2(8*CELL+6,.7*CELL)),Color("263735"))
 text_at(O+Vector2(65,4.63*CELL),"楚 河",22,GOLD);text_at(O+Vector2(310,4.63*CELL),"汉 界",22,GOLD)
 for top in [0,7]:
  draw_line(cell_pos(Vector2i(3,top)),cell_pos(Vector2i(5,top+2)),Color("697967"))
  draw_line(cell_pos(Vector2i(5,top)),cell_pos(Vector2i(3,top+2)),Color("697967"))
 for y in 10:
  for x in 9:
   var p=Vector2i(x,y);var v=cell_pos(p)
   var inspected=R.occupied(hover,enemies)
   var visible_threat=(show_threat or initial_threat>0) and R.threatened(p,enemies)
   if inspected>=0 and R.attacks(enemies[inspected],p,enemies):visible_threat=true
   if visible_threat:draw_circle(v,13,Color(0.9,.3,.2,.24))
   if selected>=0 and card_legal(hand[selected],p):
    var danger=CARDS[hand[selected]][3]=="移" and R.threatened(p,enemies)
    draw_circle(v,19,Color(.9,.3,.2,.4) if danger else Color(.4,.8,.7,.4));draw_arc(v,20,0,TAU,24,RED if danger else GOLD,2)
 if selected<0 and basic_legal(hover) and phase=="play":
  var target=cell_pos(hover);var start=cell_pos(player);var dir=(target-start).normalized()
  var danger_color=RED if R.threatened(hover,enemies) else GOLD
  draw_circle(target,20,Color(.9,.3,.2,.4) if R.threatened(hover,enemies) else Color(.4,.8,.7,.4));draw_line(start,target,danger_color,3)
  draw_line(target,target-dir.rotated(.5)*13,danger_color,3);draw_line(target,target-dir.rotated(-.5)*13,danger_color,3)
 var inspected_index=R.occupied(hover,enemies)
 if inspected_index>=0:
  var inspected=enemies[inspected_index]
  var intent:Vector2i=inspected.get("intent",Vector2i(-1,-1))
  if R.inside(intent):
   draw_line(cell_pos(inspected.pos),cell_pos(intent),Color("a9bba1"),2)
   draw_arc(cell_pos(intent),16,0,TAU,20,Color("a9bba1"),2)
  text_at(Vector2(600,551),"%s · 移动倒计时%d · %s"%[piece_name(inspected.kind),inspected.cd,"定身中，无法攻击或移动" if inspected.stun>0 else "攻击不受倒计时限制"],17,GOLD)
 for e in enemies:
  var v:Vector2=e.get("visual",cell_pos(e.pos))
  if e.cd<=1 and e.stun==0:v.x+=sin(tick*23)*1.8
  draw_circle(v+Vector2(1,3),24,Color("152020"));draw_circle(v,23,Color("d8c8a5"));draw_arc(v,20,0,TAU,32,Color("5a4432"),2)
  text_at(v+Vector2(-14,9),piece_name(e.kind),28,Color("423b32"))
  draw_circle(v+Vector2(20,-20),10,Color("274e54"));text_at(v+Vector2(15,-15),str(e.cd),13)
  if e.stun>0:text_at(v+Vector2(-21,35),"定身",14,Color("82e7da"))
 var pv=player_visual
 if R.threatened(player,enemies):pv.x+=sin(tick*29)*2;draw_arc(pv,29,0,TAU,32,RED,3)
 draw_circle(pv,24,Color("a74332"));draw_arc(pv,20,0,TAU,32,GOLD,2);text_at(pv+Vector2(-14,9),"帅",28,INK)
 if R.threatened(player,enemies):text_at(Vector2(600,296),"将军！结束回合前解除威胁。",23,RED)
 else:text_at(Vector2(600,296),"观察走位 · 出牌破阵",23,Color("8bc4af"))
 for i in logs.size():text_at(Vector2(605,337+i*30),logs[i],18,INK if i==0 else Color("91a49d"))
 panel(Rect2(600,605,210,42),Color("26383b"));text_at(Vector2(615,633),"威胁范围："+("常显" if show_threat else "短暂"),18)
 panel(Rect2(970,605,270,60),Color("b38a4a"));text_at(Vector2(1030,644),"结束回合 →",23,Color("172226"))
 text_at(Vector2(600,581),notice.substr(0,36),17,GOLD)
 text_at(Vector2(30,700),"移动：悬停预览 / 单击落子     出牌：选牌 → 选目标     取消：右键 / Esc",17,Color("9eb4a9"))
 for i in hand.size():
  var id=hand[i];var rect=hand_rect(i)
  panel(rect,Color("2b4244") if selected!=i else Color("425b50"),GOLD if selected==i else Color("526663"))
  text_at(rect.position+Vector2(13,30),CARDS[id][0],24,GOLD)
  text_at(rect.position+Vector2(rect.size.x-45,29),str(CARDS[id][1])+"气",16)
  text_at(rect.position+Vector2(13,59),"「%s」"%CARDS[id][3],15,Color("8bc4af"))
  var desc:String=CARDS[id][2]
  var line=0
  while desc.length()>0:
   text_at(rect.position+Vector2(13,83+line*22),desc.substr(0,8 if hand.size()>6 else 10),16)
   desc=desc.substr(8 if hand.size()>6 else 10);line+=1
 if hand.is_empty():text_at(Vector2(45,773),"空手入局。先移动，便能抽牌；未使用的手牌会保留。",24,Color("8da69b"))
 if phase=="discard":text_at(Vector2(600,550),"手牌已满：选择一张弃置后继续",22,RED)
 if phase=="reward":
  draw_rect(Rect2(0,0,1280,900),Color(0.03,.08,.09,.91));text_at(Vector2(390,235),"破阵成功 · 选择一张新牌",32,GOLD)
  for i in rewards.size():
   var id=rewards[i];var pos=Vector2(220+i*285,310)
   panel(Rect2(pos,Vector2(260,190)),Color("2b4244"),GOLD);text_at(pos+Vector2(25,45),CARDS[id][0],30,GOLD);text_at(pos+Vector2(25,80),"费用 %d"%CARDS[id][1],19)
   var desc:String=CARDS[id][2]
   text_at(pos+Vector2(25,118),desc.substr(0,12),17);text_at(pos+Vector2(25,146),desc.substr(12),17)
  panel(Rect2(530,530,220,50),Color("26383b"));text_at(Vector2(563,563),"跳过，进入下一关",20)
 if phase in ["dead","win"]:
  draw_rect(Rect2(0,0,1280,900),Color(.03,.08,.09,.87));text_at(Vector2(410,380),"三关突破 · 原型通关" if phase=="win" else "此局已尽 · 再弈一局",36,GOLD)
  text_at(Vector2(430,435),"点击右上角「重新开局」再次挑战",22)
  if phase=="dead":text_at(Vector2(480,480),notice,22,RED)
  panel(Rect2(1110,25,130,40),Color("b38a4a"));text_at(Vector2(1135,52),"重新开局",18,Color("172226"))
