extends SceneTree

func _initialize():
	var source = preload("res://pixel_audio.gd").new()
	var combined = PackedByteArray()
	for cue in source.CUES:
		var stream = source.CUES[cue]
		for offset in range(0, stream.data.size(), 2):
			var value = stream.data.decode_s16(offset)
			value = int(value * db_to_linear(-18.0))
			combined.append(value & 255);combined.append((value >> 8) & 255)
		for i in int(source.RATE * 0.22): combined.append(0);combined.append(0)
	var result = AudioStreamWAV.new();result.format = AudioStreamWAV.FORMAT_16_BITS;result.mix_rate = source.RATE;result.data = combined
	var args = OS.get_cmdline_user_args()
	var path = args[0] if not args.is_empty() else "user://xiangqi_sound_preview.wav"
	var error = result.save_to_wav(path)
	print("SOUND PREVIEW ", path, " result=", error)
	source.free();quit(error)
