class_name ChessRules
extends RefCounted
static func inside(p: Vector2i) -> bool:
 return p.x>=0 and p.x<9 and p.y>=0 and p.y<10
static func occupied(p: Vector2i, enemies: Array) -> int:
 for i in enemies.size():
  if enemies[i].pos==p: return i
 return -1
static func blockers(a: Vector2i,b: Vector2i,enemies: Array) -> int:
 if a.x!=b.x and a.y!=b.y: return 99
 var step=Vector2i(signi(b.x-a.x),signi(b.y-a.y))
 var p=a+step
 var n=0
 while p!=b:
  if occupied(p,enemies)>=0: n+=1
  p+=step
 return n
static func attacks(e: Dictionary,p: Vector2i,enemies: Array) -> bool:
 if not inside(p) or e.get("stun",0)>0 or p==e.pos: return false
 var d: Vector2i=p-e.pos
 match e.kind:
  "p": return d==Vector2i(0,1) or (e.pos.y>=5 and abs(d.x)==1 and d.y==0)
  "e": return abs(d.x)==2 and abs(d.y)==2 and p.y<=4 and occupied(e.pos+d/2,enemies)<0
  "g": return absi(d.x)+absi(d.y)==1 and p.x>=3 and p.x<=5 and p.y<=2
  "r": return blockers(e.pos,p,enemies)==0
  "c": return blockers(e.pos,p,enemies)==1
  "h":
   if not ((abs(d.x)==2 and abs(d.y)==1) or (abs(d.x)==1 and abs(d.y)==2)): return false
   var leg=e.pos+Vector2i(signi(d.x) if abs(d.x)==2 else 0,signi(d.y) if abs(d.y)==2 else 0)
   return occupied(leg,enemies)<0
 return false
static func threatened(p: Vector2i,enemies: Array) -> bool:
 for e in enemies:
  if attacks(e,p,enemies): return true
 return false
static func moves(e: Dictionary,enemies: Array,player: Vector2i) -> Array:
 if e.get("stun",0)>0:return []
 var out=[]
 var occupied_board=enemies.duplicate()
 occupied_board.append({"pos":player})
 for y in 10:
  for x in 9:
   var p=Vector2i(x,y)
   if p==e.pos or p==player or occupied(p,enemies)>=0: continue
   if e.kind=="c":
    if blockers(e.pos,p,occupied_board)==0: out.append(p)
   elif attacks(e,p,occupied_board): out.append(p)
 return out
static func safe_recoil(origin: Vector2i,enemies: Array) -> Array:
 var best=999
 var out=[]
 for y in 10:
  for x in 9:
   var p=Vector2i(x,y)
   if p==origin or occupied(p,enemies)>=0 or threatened(p,enemies): continue
   var dist=abs(p.x-origin.x)+abs(p.y-origin.y)
   if dist<best: best=dist;out=[]
   if dist==best: out.append(p)
 return out
