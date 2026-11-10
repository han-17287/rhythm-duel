extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func receive(ws: WebSocketPeer) -> Dictionary:
	var end := Time.get_ticks_msec()+4000
	while Time.get_ticks_msec()<end:
		ws.poll()
		if ws.get_available_packet_count()>0:
			return JSON.parse_string(ws.get_packet().get_string_from_utf8())
		await process_frame
	return {}
func open_peer() -> WebSocketPeer:
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:8765")
	var end := Time.get_ticks_msec()+4000
	while ws.get_ready_state()!=WebSocketPeer.STATE_OPEN and Time.get_ticks_msec()<end:
		ws.poll()
		await process_frame
	assert(ws.get_ready_state()==WebSocketPeer.STATE_OPEN)
	return ws
func run() -> void:
	var a: WebSocketPeer = await open_peer()
	a.send_text(JSON.stringify({"type":"create"}))
	var joined: Dictionary = await receive(a)
	assert(joined.get("type")=="joined")
	await receive(a) # waiting room state
	var b: WebSocketPeer = await open_peer()
	b.send_text(JSON.stringify({"type":"join","code":joined.code}))
	var other: Dictionary = await receive(b)
	assert(other.get("slot")==1)
	await receive(a)
	await receive(b)
	a.send_text(JSON.stringify({"type":"start"}))
	var ta: Dictionary = await receive(a)
	var tb: Dictionary = await receive(b)
	assert(ta.get("type")=="turn" and tb.get("type")=="turn")
	a.close()
	b.close()
	print("GODOT_NETWORK_OK: two Godot WebSocketPeer connections joined the same room")
	quit()
