extends SceneTree
const Preferences=preload("res://gameplay/preferences.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var prefs:=Preferences.new()
	prefs.values.volume=0.25
	prefs.values.bpm=140
	prefs.values.offset_ms=-35
	prefs.values.key="F"
	var notes: Array=[]
	for i in range(8):notes.append({"t":i*0.5,"d":0.0})
	assert(prefs.save_pattern(notes))
	assert(prefs.save_pattern(notes) and prefs.patterns.size()==1)
	var restored:=Preferences.new()
	restored.load_data()
	assert(restored.values.bpm==140 and restored.values.offset_ms==-35 and restored.values.key=="F")
	assert(restored.patterns.size()==1 and Preferences.valid_pattern(restored.patterns[0].notes))
	assert(not Preferences.valid_pattern([{"t":0,"d":9}]))
	assert(not Preferences.valid_pattern([{"t":"bad","d":8}]))
	assert(not Preferences.valid_pattern([{"t":0,"d":INF}]))
	assert(not Preferences.valid_pattern([{"t":0,"d":4},{"t":1,"d":4}]))
	restored.delete_pattern(0)
	assert(restored.patterns.is_empty())
	var bank=preload("res://gameplay/sound_bank.gd").new()
	root.add_child(bank)
	await process_frame
	assert(bank.streams.size()>=12)
	for stream in bank.streams.values():
		assert(stream.mix_rate==22050 and stream.get_length()>0)
		assert(stream.data.size()>100)
	bank.queue_free()
	await process_frame
	print("PREFERENCES_OK: durable settings, saved pattern deduplication and validation, synthesized sound bank")
	call_deferred("quit")
