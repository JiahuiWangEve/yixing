extends SceneTree
var game:Control
var passed=0
var failed=0
func check(ok:bool,label:String):
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error("FAIL "+label)
func key(code:int,pressed:bool=true,echo:bool=false):
 var event=InputEventKey.new()
 event.keycode=code;event.pressed=pressed;event.echo=echo
 game._input(event)
func reset():
 game.new_run()
 game.enemies=[{"kind":"p","pos":Vector2i(2,3),"cd":1,"period":2,"stun":0,"intent":Vector2i(2,4)}]
func _initialize():
 game=load("res://main.tscn").instantiate();root.add_child(game)
 for code in [KEY_ENTER,KEY_KP_ENTER]:
  reset();game.energy=0;game.selected=0
  key(code)
  check(game.turn==2,"Enter variant ends exactly one turn: "+str(code))
  check(game.enemies[0].pos==Vector2i(2,4),"Enter variant resolves enemy movement: "+str(code))
  check(game.energy==3 and game.selected==-1,"Enter variant restores energy and cancels selection: "+str(code))
  key(code)
  check(game.turn==2,"Repeated press during animation ignored: "+str(code))
  game._process(0.5);key(code,true,true)
  check(game.turn==2,"Held-key echo after animation ignored: "+str(code))
  key(code,false)
  check(game.turn==2,"Key release ignored: "+str(code))
  key(code)
  check(game.turn==3,"Fresh press after animation works: "+str(code))
  for phase in ["reward","discard","dead","win","enemy"]:
   reset();game.phase=phase
   key(code)
   check(game.turn==1 and game.enemies[0].pos==Vector2i(2,3),"Enter ignored in "+phase+": "+str(code))
 reset();game.input_lock=0.18;key(KEY_ENTER)
 check(game.turn==1,"Movement animation lock blocks Enter")
 reset();key(KEY_SPACE)
 check(game.turn==1,"Unrelated key does not end turn")
 reset();game.selected=0;key(KEY_ESCAPE)
 check(game.selected==-1 and game.turn==1,"Escape still cancels card selection only")
 reset()
 var click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=game.END_TURN_RECT.get_center()
 game._gui_input(click)
 check(game.turn==2 and game.enemies[0].pos==Vector2i(2,4),"Mouse button shares end-turn path")
 print("KEYBOARD QA: ",passed," passed, ",failed," failed")
 game.queue_free();quit(1 if failed>0 else 0)
