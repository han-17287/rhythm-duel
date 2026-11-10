extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	assert(game.interface.home.visible and not game.interface.rooms.visible)
	assert(game.endpoint.text=="wss://rhythm-duel.onrender.com")
	game.interface.page = "rooms"
	game.interface.sync()
	assert(game.interface.rooms.visible and not game.interface.home.visible)
	game.receive({"type":"joined","slot":0,"code":"ABC123"})
	game.interface.sync()
	assert(game.interface.waiting.visible and game.interface.waiting_code.text=="ABC123" and game.phase=="room")
	game.receive({"type":"turn","turn":0,"attacker":0,"speed":1.0,"scores":[0,0]})
	game.interface.sync()
	assert(game.interface.budget.visible and not game.interface.waiting.visible)
	game.receive({"type":"turn","turn":1,"attacker":1,"speed":1.0,"scores":[0,1000]})
	game.interface.sync()
	assert(game.phase=="waiting" and game.interface.role.visible and not game.interface.waiting.visible)
	game.receive({"type":"pattern","notes":[{"t":0.0,"d":8.0}],"speed":1.0})
	game.interface.sync()
	assert(game.phase=="play" and game.interface.role.text.contains("수비"))
	game.receive({"type":"result","points":8000,"scores":[8000,1000],"finished":true})
	game.interface.sync()
	assert(game.result.visible and game.result.text=="P1 승리!")
	game.queue_free()
	await process_frame
	print("INTERFACE_SMOKE_OK: home, rooms, room code, attack, defense, result, production URL")
	quit()
