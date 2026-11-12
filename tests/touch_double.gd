extends SceneTree
func _initialize()->void:call_deferred("run")
func touch(index:int,point:Vector2,pressed:bool)->void:
	var event:=InputEventScreenTouch.new();event.index=index;event.position=point;event.pressed=pressed;event.window_id=root.get_window_id();root.push_input(event,true)
func run()->void:
	var g=load("res://main.tscn").instantiate();root.add_child(g);await process_frame
	g.launch_ranker("r01","double",true,1)
	g.notes=[{"t":0.0,"d":0.0,"lane":0},{"t":0.0,"d":0.0,"lane":1}];g.begin_play();g.origin=g.now();g.interface.sync()
	for pad in g.interface.gameplay_ui.double_touch:
		if pad is TouchScreenButton:pad.visibility_mode=TouchScreenButton.VISIBILITY_ALWAYS
	touch(0,Vector2(925,582),true);touch(1,Vector2(1047,582),true)
	await process_frame
	assert(g.double_beat.held==[true,true],"Both independent touch lanes must be held")
	touch(0,Vector2(925,582),false);await process_frame
	assert(g.double_beat.held==[false,true],"Releasing one finger must not release the other")
	touch(1,Vector2(1047,582),false);await process_frame
	assert(g.double_beat.held==[false,false] and g.hits.size()==2 and g.live_judgments.size()==2)
	g.open_menu("ranker");await create_timer(.4).timeout;g.queue_free();await process_frame
	print("TOUCH_DOUBLE_OK: two independent fingers, one release keeps other held, no duplicate mouse/touch hits");quit()
