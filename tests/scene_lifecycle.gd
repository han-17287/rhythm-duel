extends SceneTree
func _initialize() -> void:
	ProjectSettings.set_setting("application/config/server_url","ws://127.0.0.1:1")
	call_deferred("run")
func run() -> void:
	var baseline:=0
	var baseline_nodes:=0
	for i in range(32):
		var game=load("res://main.tscn").instantiate()
		root.add_child(game)
		game.socket.close()
		await process_frame
		game.queue_free()
		await process_frame
		await process_frame
		if i==4:
			baseline=int(Performance.get_monitor(Performance.OBJECT_COUNT))
			baseline_nodes=int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects:=int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes:=int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("SCENE_LIFECYCLE: objects %d -> %d, nodes %d -> %d"%[baseline,objects,baseline_nodes,nodes])
	assert(nodes<=baseline_nodes+2,"Scene reload retained nodes")
	assert(objects<=baseline+15,"Scene reload retained objects/resources")
	print("SCENE_LIFECYCLE_OK: 32 complete menu/audio/gameplay constructions and cleanups")
	call_deferred("quit")
