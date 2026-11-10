extends SceneTree
var game: Control
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.start_practice()
	assert(game.phase == "record")
	for i in range(8):
		game.origin = game.now()-i*0.5-0.05
		game.down = i*0.5
		game.finish_record_note()
	assert(game.notes.size()==8)
	assert(game.phase=="play")
	game.judge_tap(0.0)
	assert(game.result.text=="perfecto!!!")
	game.notes=[{"t":0.0,"d":2.0}]
	game.resolved.clear()
	game.judge_hold(0.0,2.0)
	assert(game.result.text=="perfecto!!!")
	game.resolved.clear()
	game.judge_hold(0.0,0.5)
	assert(game.result.text=="water XXXX")
	print("GODOT_SMOKE_OK: UI, recording, replay, tap and hold judgments")
	quit()
