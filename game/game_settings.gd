extends RefCounted
# Preferences are independent of expedition saves and undo snapshots.
const SAVE = "user://game_settings.cfg"
const WEB_SAVE_KEY = "yixing.settings.v1"
var debug_mode = false
var save_error = OK
func load_settings():
	debug_mode = false
	var config = ConfigFile.new()
	var loaded = false
	if OS.has_feature("web"):
		var snapshot = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('" + WEB_SAVE_KEY + "')||'';}catch(e){return '';}})()")
		if snapshot is String and not snapshot.is_empty(): loaded = config.parse(snapshot) == OK
	if not loaded: loaded = config.load(SAVE) == OK
	if loaded:
		var value = config.get_value("settings", "debug_mode", false)
		debug_mode = value is bool and value
func set_debug_mode(enabled: bool):
	debug_mode = enabled
	var config = ConfigFile.new()
	config.set_value("settings", "debug_mode", debug_mode)
	save_error = config.save(SAVE)
	if OS.has_feature("web"):
		var encoded = JSON.stringify(config.encode_to_text())
		var stored = JavaScriptBridge.eval("(function(){try{localStorage.setItem('" + WEB_SAVE_KEY + "'," + encoded + ");return true;}catch(e){return false;}})()")
		if stored == true: save_error = OK
