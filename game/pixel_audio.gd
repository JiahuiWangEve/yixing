extends Node
signal mute_changed(muted: bool)

const RATE = 44100
const CUES = {
	"land": preload("res://assets/audio/wood_paper/01_land.wav"), 
	"draw": preload("res://assets/audio/wood_paper/02_draw.wav"), 
	"select": preload("res://assets/audio/wood_paper/03_select.wav"), 
	"use": preload("res://assets/audio/wood_paper/04_use.wav"), 
	"hit": preload("res://assets/audio/wood_paper/05_hit.wav"), 
	"death": preload("res://assets/audio/wood_paper/06_death.wav"), 
	"hurt": preload("res://assets/audio/wood_paper/07_hurt.wav"), 
	"stun": preload("res://assets/audio/wood_paper/08_stun.wav"), 
	"push": preload("res://assets/audio/wood_paper/09_push.wav"), 
	"heal": preload("res://assets/audio/wood_paper/10_heal.wav"), 
	"spawn": preload("res://assets/audio/wood_paper/11_spawn.wav"), 
	"victory": preload("res://assets/audio/wood_paper/12_victory.wav")}
var muted = false
var unlocked = false
var played_events: Array = []
var streams: Dictionary = {}
var voices: Array = []
var last_played: Dictionary = {}
var voice_index = 0
func _ready():
	for cue in CUES: streams[cue] = CUES[cue]
	for i in 4:
		var voice = AudioStreamPlayer.new();voice.volume_db = -18.0;add_child(voice);voices.append(voice)
func unlock():
	unlocked = true
func toggle_mute():
	set_muted(not muted)
func set_muted(value: bool):
	if muted == value: return
	muted = value
	if muted:
		for voice in voices: voice.stop()
	mute_changed.emit(muted)
func clear_playback():
	for voice in voices: voice.stop()
	played_events.clear();last_played.clear()
func play_cue(cue: String, now: float):
	if muted or not unlocked or not streams.has(cue): return

	if now - float(last_played.get(cue, -100.0)) < 0.055: return
	last_played[cue] = now
	played_events.append({"cue": cue, "time": now})
	if played_events.size() > 128: played_events.pop_front()

	if DisplayServer.get_name() == "headless": return
	var voice = voices[voice_index % voices.size()];voice_index += 1
	voice.stream = streams[cue];voice.play()

func _exit_tree():
	clear_playback()
