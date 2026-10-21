extends SceneTree
class Painter:
	extends RefCounted
	const PROFILES = preload("res://start_profiles.gd")
	var player_skill = "king"
	var ui_size = Vector2(480,1039)
	var mobile_layout = true
	var compact_landscape = false
	var calls = 0
	func draw_line(_a, _b, _c, _w = -1, _aa = false): calls += 1
	func draw_multiline(_a, _b, _w = -1, _aa = false): calls += 1
	func draw_set_transform(_a): pass
func _initialize():
	var painter = Painter.new()
	var script_path = "res://route_map.gd"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline="): script_path = arg.trim_prefix("--baseline=")
	var route = load(script_path).new(painter)
	route.generate(12345)
	route.state.current = 0;route.state.visited = [0]
	var timings = []
	for frame in 35:
		route.scroll_y = frame * 8
		var start = Time.get_ticks_usec()
		for node in route.state.nodes:
			for next in node.next: route.draw_route_edge(node, route.state.nodes[next])
		if frame >= 5: timings.append(Time.get_ticks_usec() - start)
	timings.sort()
	print(JSON.stringify({"script":script_path,"samples":timings.size(),"median_us":timings[15],"p95_us":timings[28],"draw_calls_per_frame":painter.calls / 35.0,"scope":"Native GDScript road CPU with no-op painter; not device frame rate or GPU timing"}))
	quit()
