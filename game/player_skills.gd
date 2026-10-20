extends RefCounted



const SAVE_PATH = "user://skill_unlock.cfg"
const SAVE_SECTION = "skills"
const HORSE_KEY = "horse_unlocked"
var game
var horse_unlocked = false
var load_error = OK
var save_error = OK

func _init(owner): game = owner

func load_progress() -> bool:
	horse_unlocked = false
	var config = ConfigFile.new()
	load_error = config.load(SAVE_PATH)
	if load_error != OK: return false
	var saved = config.get_value(SAVE_SECTION, HORSE_KEY, false)

	horse_unlocked = saved is bool and saved
	return true

func unlock_horse() -> bool:

	horse_unlocked = true
	var config = ConfigFile.new()
	config.set_value(SAVE_SECTION, HORSE_KEY, true)
	save_error = config.save(SAVE_PATH)
	return save_error == OK

func is_unlocked(id: String) -> bool:
	return id == "king" or (id in ["horse", "artillery"] and horse_unlocked)

func choose(id: String) -> bool:
	if not is_unlocked(id): return false
	game.player_skill = id
	game.new_run()
	return true

func show_selection():

	game.show_home()
	game.handui.reset()
	game.screen = "skill_selection"
	game.queue_redraw()
