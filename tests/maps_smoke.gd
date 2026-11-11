extends SceneTree
const Maps=preload("res://gameplay/maps.gd")
const Scoring=preload("res://gameplay/scoring.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var total:=0
	var records: Dictionary={}
	assert(Maps.catalog().size()==12 and Maps.unlocked("m01",records) and not Maps.unlocked("m02",records))
	for item in Maps.catalog():
		var notes:=Maps.chart(item.id)
		assert(notes.size()>=24)
		var end:=-1.0
		for note in notes:
			assert(float(note.t)-end>=.079,"Overlapping or too-close map notes: "+str(item.id))
			end=float(note.t)+float(note.d)
		assert(end>=18 and end<=60)
		var report:=Scoring.analyze(notes,notes.duplicate(true))
		assert(report.all_perfect and report.full_combo and report.accuracy==100)
		total+=notes.size()
		records[Maps.record_id(item.id)]={"stars":3}
		assert(Maps.unlocked(item.id,records))
	assert(Maps.total_stars(records)==36 and Maps.next_id("m12")=="")
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.preferences.values.key="SPACE"
	game.preferences.values.offset_ms=0
	game.preferences.records.clear()
	game.start_map("m02")
	assert(game.map_id=="")
	game.start_map("m12",true,.5,true)
	assert(game.map_id=="m12" and game.map_training and game.map_guide and game.speed==.5)
	game.hits=game.notes.duplicate(true)
	game.finish_local_round()
	assert(game.preferences.records.is_empty() and game.last_report.all_perfect)
	game.start_map("m01")
	game.hits=game.notes.duplicate(true)
	game.finish_local_round()
	assert(Maps.unlocked("m02",game.preferences.records))
	game.next_solo_wave()
	assert(game.map_id=="m02" and game.phase=="play")
	game.open_menu("solo")
	game.interface.sync()
	assert(game.map_id=="" and game.interface.gameplay_ui.map_ui.page.visible)
	game.interface.page="arcade"
	game.interface.sync()
	assert(game.interface.gameplay_ui.course_page.visible)
	await create_timer(.5).timeout
	game.queue_free()
	await process_frame
	print("MAPS_SMOKE_OK: 12 authored maps, %d notes, no overlaps, perfect scoring, locked-map practice, no practice unlock, clear/next/map menu"%total)
	call_deferred("quit")
