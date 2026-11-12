extends SceneTree
const Ranker=preload("res://gameplay/ranker.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.socket.close();game.preferences.records.clear()
	game.preferences.records["ranker:r01:one"]={"points":1000,"accuracy":95.0,"grade":"S","max_combo":1}
	assert(Ranker.power(game.preferences.records,"one","hard")>0)
	assert(Ranker.power(game.preferences.records,"one","inferno")==0)
	game.open_menu("ranker");game.interface.sync()
	var arena=game.interface.gameplay_ui.ranker_ui
	assert(arena.difficulty_tabs.size()==3)
	arena.difficulty_tabs[2].pressed.emit();assert(arena.difficulty=="inferno")
	arena.section_select.select(4);arena.practice_selected()
	assert(game.ranker_difficulty=="inferno" and game.ranker_training)
	game.toggle_pause();assert(game.paused)
	game.restart_practice_current();assert(game.ranker_difficulty=="inferno" and not game.paused)
	game.hits=game.notes.duplicate(true);game.finish_ranker()
	assert(game.preferences.records.size()==1 and game.preferences.records["ranker:r01:one"].points==1000)
	game.open_menu("ranker");game.interface.sync();assert(game.ranker_difficulty=="hard")
	game.profile={"id":"fixture","name":"Tier Tester","skin":"mint","coins":0,"rating":1000,"wins":0,"losses":0,"draws":0}
	game.ranker_waiting={"id":"r01","kind":"one","difficulty":"inferno"}
	game.receive({"type":"ranker_ready","id":"r01","kind":"one","difficulty":"expert","session":"wrong"})
	assert(game.phase=="lobby" and not game.ranker_waiting.is_empty())
	game.receive({"type":"ranker_ready","id":"r01","kind":"one","difficulty":"inferno","session":"correct"})
	assert(game.phase=="play" and game.ranker_difficulty=="inferno" and game.ranker_session=="correct")
	game.preferences.values.ranker_scroll=.8;assert(game.note_radius()*2<game.scroll_pixels()*.05)
	game.preferences.values.ranker_scroll=1.0;assert(game.note_radius()*2<game.scroll_pixels()*.05)
	for difficulty in Ranker.DIFFICULTIES:
		game.receive({"type":"ranker_board","id":"r01","kind":"one","difficulty":difficulty,"enabled":false,"rows":[]})
	assert(game.ranker_boards.has("r01:one") and game.ranker_boards.has("r01:one:expert") and game.ranker_boards.has("r01:one:inferno"))
	game.ranker_upload_pending=true;game.ranker_upload_key="r01:one:inferno";game.reward_text="current inferno"
	game.receive({"type":"ranker_result","id":"r01","kind":"one","difficulty":"hard","coins":40,"profile":game.profile})
	assert(game.ranker_upload_pending and game.reward_text=="current inferno")
	game.receive({"type":"ranker_result","id":"r01","kind":"one","difficulty":"inferno","coins":40,"profile":game.profile})
	assert(not game.ranker_upload_pending and game.reward_text.contains("40"))
	game.open_menu("home");assert(game.ranker_difficulty=="hard")
	arena=null;game.queue_free();await process_frame
	print("RANKER_DIFFICULTY_OK: tier UI, legacy record isolation, strict windows, practice retry, stale ready/result isolation, separate board caches")
	quit()
