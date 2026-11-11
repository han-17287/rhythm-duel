extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var g=load("res://main.tscn").instantiate();root.add_child(g);await process_frame
	g.preferences.values.offset_ms=0
	g.start_practice(true)
	# Both keys can be down together; release order does not change chart order.
	g.double_beat.press(0,true);g.double_beat.press(1,true)
	assert(g.double_beat.held==[true,true])
	g.double_beat.press(1,false);g.double_beat.press(0,false)
	assert(g.notes.size()==2 and g.used==2)
	assert(g.notes[0].lane==0 and g.notes[1].lane==1)
	# Simultaneous notes must match their own lane, and both taps score.
	g.notes=[{"t":0.0,"d":0.0,"lane":0},{"t":0.0,"d":0.0,"lane":1}]
	g.begin_play();g.origin=g.now()
	g.double_beat.press(1,true);g.double_beat.press(1,false)
	assert(g.resolved.has(1) and not g.resolved.has(0))
	g.double_beat.press(0,true);g.double_beat.press(0,false)
	assert(g.Scoring.analyze(g.notes,g.hits).points==2000)
	# An upper hold can continue while lower taps are played.
	g.notes=[{"t":0.0,"d":1.0,"lane":0},{"t":0.5,"d":0.0,"lane":1}]
	g.begin_play();g.origin=g.now();g.double_beat.press(0,true)
	g.origin=g.now()-.5;g.double_beat.press(1,true);g.double_beat.press(1,false)
	assert(g.double_beat.held[0] and g.resolved.has(1))
	g.origin=g.now()-1;g.double_beat.press(0,false)
	assert(g.Scoring.analyze(g.notes,g.hits).points==2000)
	# Budget reservations prevent two simultaneous holds spending >8 units.
	g.start_practice(true);g.double_beat.press(0,true);g.double_beat.press(1,true)
	g.origin=g.now()-10;g.double_beat.update()
	assert(g.phase=="review" and g.used==8 and g.preferences.valid_pattern(g.notes))
	g.start_double_training();await process_frame
	assert(g.is_double() and g.phase=="play")
	g.open_menu("solo");g.queue_free();await process_frame
	print("DOUBLE BEAT INPUT / CHORD / HOLD / BUDGET PASSED");quit()
