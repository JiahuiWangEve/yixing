extends SceneTree
var passed=0
var failed=0
var game
func check(ok:bool,label:String):
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;push_error(label)
func click_at(p:Vector2):
 var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=p
 game._gui_input(event)
func _initialize():
 game=load("res://main.tscn").instantiate();root.add_child(game)
 check(game.BOARD_RECT.get_center().x==640,"Board centered in viewport")
 check(game.RESTART_RECT.end.y<game.BOARD_RECT.position.y,"Restart above board")
 check(game.END_TURN_RECT.position.y>game.BOARD_RECT.end.y,"End turn below board")
 check(game.END_TURN_RECT.end.y<game.HAND_Y,"End turn above cards")
 check(game.BOARD_RECT.has_point(game.cell_pos(Vector2i(0,0))) and game.BOARD_RECT.has_point(game.cell_pos(Vector2i(8,9))),"Board contains extreme intersections")
 check(game.context_hint().is_empty(),"No permanent starting hint or log")
 for point in [Vector2(1100,630),Vector2(1150,45),Vector2(700,630)]:
  game.new_run();game.turn=4;click_at(point)
  check(game.turn==4 and not game.show_threat,"Removed button location has no old action: "+str(point))
 game.new_run();click_at(game.END_TURN_RECT.get_center())
 check(game.turn==2,"Relocated end button works")
 game._process(0.5);click_at(game.RESTART_RECT.get_center())
 check(game.turn==1,"Relocated restart works")
 click_at(game.cell_pos(Vector2i(4,8)))
 check(game.player==Vector2i(4,8) and game.hand.size()==1,"Relocated board movement and draw work")
 game._process(0.5);game.hand=["sword"];click_at(game.hand_rect(0).get_center())
 check(game.selected==0 and game.context_hint().contains("高亮"),"Relocated card selects and target hint appears")
 game.phase="discard";game.hand=["sword","sword","sword","sword","sword","sword","sword"]
 check(game.context_hint().contains("弃置"),"Forced discard prompt retained")
 for i in 7:
  check(game.hand_rect(i).position.y>game.END_TURN_RECT.end.y and Rect2(0,0,1280,900).encloses(game.hand_rect(i)),"Card fully visible below controls: "+str(i))
 click_at(game.hand_rect(6).get_center())
 check(game.hand.size()==6 and game.phase=="play","Seventh card discard hit area works")
 game.new_run();game.hover=game.enemies[0].pos
 check(game.context_hint().contains("倒计时"),"Enemy hover detail uses contextual hint")
 game.hover=Vector2i(-1,-1);game.player=Vector2i(2,4)
 check(game.context_hint().contains("将军"),"Check warning retained near board")
 print("LAYOUT QA: ",passed," passed, ",failed," failed")
 game.queue_free();quit(1 if failed>0 else 0)
