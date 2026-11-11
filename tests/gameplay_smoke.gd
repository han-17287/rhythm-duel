extends SceneTree
const Score = preload("res://gameplay/scoring.gd")
const Challenges = preload("res://gameplay/challenges.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.preferences.values.key="SPACE"
	game.preferences.values.offset_ms=0
	# Pressing slightly before the first note must still produce a releasable input.
	game.practice=true
	game.notes=[{"t":0.0,"d":0.0}]
	game.begin_play()
	game.origin=game.now()+0.03
	var press:=InputEventKey.new()
	press.keycode=KEY_SPACE
	press.pressed=true
	game._input(press)
	assert(game.key_held and game.down<0 and game.combo==1)
	var release:=InputEventKey.new()
	release.keycode=KEY_SPACE
	release.pressed=false
	game._input(release)
	assert(not game.key_held and game.hits.size()==1)
	assert(Score.analyze(game.notes,game.hits).points==1000)
	# A tap release must not consume a nearby hold with an overlapping timing window.
	game.notes=[{"t":0.0,"d":0.0},{"t":0.1,"d":1.0}]
	game.begin_play()
	game.origin=game.now()-0.02
	game._input(press)
	game._input(release)
	assert(game.resolved.has(0) and not game.resolved.has(1))
	for course in Challenges.courses():
		for wave in range(12):
			var notes: Array=Challenges.pattern(str(course.id),wave)
			var budget:=0
			var end:=-1.0
			for n in notes:
				budget+=maxi(1,ceili(float(n.d)))
				assert(float(n.t)>end+0.075)
				end=float(n.t)+float(n.d)
			assert(budget==8 and notes==Challenges.pattern(str(course.id),wave))
	game.start_challenge("first")
	assert(game.phase=="play" and game.solo_id=="first")
	game.hits=game.notes.duplicate(true)
	game.finish_local_round()
	assert(game.last_report.all_perfect and not game.match_finished)
	game.next_solo_wave()
	assert(game.solo_wave==1 and game.phase=="play")
	game.hits=game.notes.duplicate(true)
	game.finish_local_round()
	game.next_solo_wave()
	game.hits=game.notes.duplicate(true)
	game.finish_local_round()
	assert(game.match_finished and game.last_report.points==24000)
	assert(game.preferences.records.has("first"))
	game.open_menu("solo")
	assert(game.phase=="lobby")
	await create_timer(0.45).timeout
	game.queue_free()
	await process_frame
	print("GAMEPLAY_SMOKE_OK: early input, 72 valid deterministic patterns, three-wave progression, local records")
	call_deferred("quit")
