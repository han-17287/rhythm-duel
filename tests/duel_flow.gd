extends SceneTree
var a: Control
var b: Control
func _initialize() -> void:
	Engine.max_fps=240
	call_deferred("run")
func until(check: Callable, timeout := 12.0) -> void:
	var end:=Time.get_ticks_msec()+int(timeout*1000)
	while not check.call() and Time.get_ticks_msec()<end: await process_frame
	assert(check.call(),"Timed out waiting for duel state")
func key(game: Control, pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=KEY_SPACE
	event.pressed=pressed
	game._input(event)
func record(game: Control) -> void:
	for i in range(8):
		key(game,true)
		await create_timer(.04).timeout
		key(game,false)
		await create_timer(.1).timeout
	assert(game.phase=="review" and game.notes.size()==8)
func defend(game: Control) -> void:
	for note in game.notes.duplicate(true):
		await until(func(): return game.now()>=game.origin+float(note.t)/game.speed)
		key(game,true)
		await create_timer(.035).timeout
		key(game,false)
func run() -> void:
	a=load("res://main.tscn").instantiate()
	b=load("res://main.tscn").instantiate()
	root.add_child(a);root.add_child(b)
	await process_frame
	for game in [a,b]:
		game.socket.close()
		game.socket=WebSocketPeer.new()
		game.connected=false
		game.connection_started=-1
		game.endpoint.text="ws://127.0.0.1:8850"
		game.preferences.values.key="SPACE"
		game.preferences.values.offset_ms=0
		game.preferences.values.volume=0.0
		game.apply_preferences()
	a.room_settings={"mode":"casual","rounds":1,"speed":1.0}
	a.connect_room("create")
	await until(func(): return a.phase=="room")
	b.code.text=a.interface.room_code
	b.connect_room("join")
	await until(func(): return a.room_players.size()==2 and b.room_players.size()==2)
	a.send_packet({"type":"start"})
	await until(func(): return a.phase=="record" and b.phase=="waiting")
	await record(a)
	await until(func(): return b.activity_units==8)
	a.preview_pattern()
	assert(a.phase=="preview" and b.phase=="waiting")
	await until(func(): return a.phase=="review")
	a.confirm_pattern()
	await until(func(): return a.phase=="play" and b.phase=="play")
	await defend(b)
	await until(func(): return a.phase=="result" and not a.last_report.is_empty() and b.phase=="result")
	assert(a.last_report.points==8000 and b.last_report.max_combo==8)
	a.send_packet({"type":"next"})
	await until(func(): return b.phase=="record" and a.phase=="waiting")
	await record(b)
	b.confirm_pattern()
	await until(func(): return a.phase=="play" and b.phase=="play")
	await defend(a)
	await until(func(): return a.match_finished and b.match_finished)
	assert(a.last_report.points==8000 and a.result.text=="무승부!")
	a.send_packet({"type":"rematch"})
	await until(func(): return a.rematch_votes.size()==1)
	b.send_packet({"type":"rematch"})
	await until(func(): return b.phase=="record" and a.phase=="waiting")
	assert(a.attacker==1 and b.attacker==1)
	a.socket.close();b.socket.close()
	a.queue_free();b.queue_free()
	await process_frame
	print("DUEL_FLOW_OK: two Godot clients, real key timing, draft/listen/send, perfect defense, score parity, rematch")
	call_deferred("quit")
