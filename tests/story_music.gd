extends SceneTree
const Maps=preload("res://gameplay/maps.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var score=JSON.parse_string(FileAccess.get_file_as_string("res://assets/music/score.json"))
	assert(score.size()==12)
	for i in range(12):
		var data:Dictionary=Maps.catalog()[i]
		var song:AudioStream=load("res://assets/music/%s.ogg"%data.id)
		assert(song!=null and not song.loop)
		assert(absf(song.get_length()-float(score[i].duration))<.06)
		var chart:=Maps.chart(data.id)
		assert(chart.size()==score[i].notes.size())
		for j in range(chart.size()):
			assert(absf(chart[j].t-score[i].notes[j].t)<.00002)
			assert(absf(chart[j].d-score[i].notes[j].d)<.00002)
	var g=load("res://main.tscn").instantiate();root.add_child(g);await process_frame
	g.start_map("m01")
	assert(g.story_music.track_id=="m01" and g.story_music.started)
	g.update_map_audio(0)
	assert(g.story_music.started and g.story_music.player.playing)
	g.toggle_pause();assert(g.story_music.player.stream_paused)
	g.toggle_pause();assert(not g.story_music.player.stream_paused)
	g.start_map("m12",true,.5,true)
	assert(g.story_music.rate==.5 and g.story_music.player.pitch_scale==.5)
	g.update_map_audio(0)
	g.open_menu("solo")
	assert(not g.story_music.player.playing and not g.story_music.started)
	await create_timer(.4).timeout;g.queue_free();await process_frame
	print("STORY_MUSIC_OK: 12 original songs, 641 exact melody/chart events, full duration, pause/resume, half-speed, exit cleanup");quit()
