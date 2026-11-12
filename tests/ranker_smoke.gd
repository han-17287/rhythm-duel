extends SceneTree
const Ranker=preload("res://gameplay/ranker.gd")
const Score=preload("res://gameplay/scoring.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var g=load("res://main.tscn").instantiate();root.add_child(g);await process_frame
	g.preferences.values.key="SPACE";g.preferences.values.offset_ms=0;g.preferences.records.clear()
	# This accelerated input fixture verifies timing, not real-time sound output.
	# The dedicated feedback and browser suites validate audible playback.
	g.preferences.values.volume=0;g.preferences.values.music_volume=0;g.apply_preferences()
	var total:=0
	for song in Ranker.catalog():
		assert(float(song.duration)+float(song.audio_offset)>=180 and float(song.duration)+float(song.audio_offset)<=240)
		assert(song.bars.size()==int(song.section_bars)*4)
		var stream:AudioStream=load("res://assets/ranker/%s.ogg"%song.id)
		assert(absf(stream.get_length()-float(song.duration)-float(song.audio_offset))<.06)
		for difficulty in Ranker.DIFFICULTIES:
			for kind in ["one","double"]:
				var chart:=Ranker.chart(song.id,kind,0,0,difficulty);total+=chart.size()
				assert(float(chart[-1].t)>120)
				var ends:=[-10.0,-10.0]
				for n in chart:
					var lane:=int(n.get("lane",0));assert(float(n.t)-ends[lane]>=(.07499 if difficulty=="hard" else .05999 if difficulty=="expert" else .04999))
					ends[lane]=float(n.t)+float(n.d)
				assert(Score.analyze(chart,chart,Ranker.windows(difficulty),true).accuracy==100)
				g.launch_ranker(song.id,kind,false,1,0,0,difficulty)
				var events:Array=[]
				for n in chart:
					events.append({"t":float(n.t),"pressed":true,"lane":int(n.get("lane",0))})
					events.append({"t":float(n.t)+maxf(float(n.d),.012),"pressed":false,"lane":int(n.get("lane",0))})
				events.sort_custom(func(a,b):return a.t<b.t or (a.t==b.t and not a.pressed))
				for entry in events:
					g.origin=g.now()-float(entry.t)
					var event:=InputEventKey.new();event.pressed=entry.pressed;event.keycode=(KEY_F if entry.lane==0 else KEY_J) if kind=="double" else KEY_SPACE
					g._input(event)
				g.finish_ranker()
				assert(g.last_report.all_perfect and g.last_report.accuracy==100,"Input parity "+song.id+kind+difficulty)
				assert(g.preferences.records.has(Ranker.record_id(song.id,kind,difficulty)))
				g.interface.sync()
	assert(Ranker.record_id("r01","one")=="ranker:r01:one:v2")
	assert(Ranker.record_id("r01","one","expert")=="ranker:r01:one:expert:v2")
	assert(Ranker.record_id("r01","double","inferno")=="ranker:r01:double:inferno:v2")
	assert(g.preferences.records.size()==24)
	var hard_saved:Dictionary=g.preferences.records[Ranker.record_id("r01","one")]
	assert(hard_saved.points==Score.analyze(Ranker.chart("r01","one"),Ranker.chart("r01","one")).points)
	var final_song:=Ranker.find("r04")
	g.launch_ranker("r04","double",true,.5,float(final_song.bars[int(final_song.section_bars)*3].t))
	assert(g.ranker_seek>0 and g.notes[0].t==0 and g.story_music.rate==.5)
	g.launch_ranker("r04","double",true,.5,float(final_song.bars[int(final_song.section_bars)*3].t),0,"inferno")
	assert(g.ranker_difficulty=="inferno" and g.judge_windows()==Ranker.windows("inferno"))
	var size_before:int=g.preferences.records.size();g.hits=g.notes.duplicate(true);g.finish_ranker();assert(g.preferences.records.size()==size_before)
	# Alternating F/J drives one lane without a key-up from the old hand ending the new tap.
	g.launch_ranker("r01","one");g.notes=[{"t":0.0,"d":0.0},{"t":.085,"d":0.0}];g.begin_play();g.origin=g.now()
	var key:=InputEventKey.new();key.keycode=KEY_F;key.pressed=true;g._input(key)
	g.origin=g.now()-.085;key=InputEventKey.new();key.keycode=KEY_J;key.pressed=true;g._input(key)
	g.origin=g.now()-.1;key=InputEventKey.new();key.keycode=KEY_F;key.pressed=false;g._input(key);assert(g.key_held)
	g.origin=g.now()-.12;key=InputEventKey.new();key.keycode=KEY_J;key.pressed=false;g._input(key)
	assert(not g.key_held and Score.analyze(g.notes,g.hits,Ranker.WINDOWS,true).points==2000)
	var dense:=Score.analyze([{"t":0.0,"d":0.0},{"t":.076,"d":0.0}],[{"t":-.06,"d":.01},{"t":.01,"d":.01}],Ranker.WINDOWS,true)
	assert(dense.counts==[0,0,2,0] and dense.max_combo==2)
	var song:=Ranker.find("r04")
	var seek:float=song.bars[int(song.section_bars)].t;var end:float=song.bars[int(song.section_bars)*2].t
	g.launch_ranker("r04","double",true,.75,seek,end)
	assert(g.notes[-1].t<end-seek and absf(g.round_end()-(end-seek+.05))<.001)
	g.toggle_pause();assert(g.paused and g.story_music.player.stream_paused)
	g.restart_practice_current();assert(not g.paused and g.ranker_training and g.ranker_seek==seek and g.ranker_end==end)
	var ranker_ui=g.interface.gameplay_ui.ranker_ui
	ranker_ui.selected="r04";ranker_ui.kind="double";ranker_ui.difficulty="inferno";ranker_ui.rebuild_practice_options();ranker_ui.section_select.select(4);ranker_ui.speed.select(1);ranker_ui.practice_selected()
	assert(g.ranker_seek==float(song.bars[int(song.section_bars)*3].t) and g.ranker_end==float(song.duration))
	assert(Ranker.section("r04",g.ranker_seek).section==3 and g.ranker_difficulty=="inferno")
	g.restart_practice_current();assert(g.ranker_difficulty=="inferno")
	g.launch_ranker("r01","one");g.toggle_pause();assert(not g.paused)
	g._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(g.paused and g.ranker_training and g.ranker_session.is_empty())
	g.open_menu("ranker");g.interface.sync();assert(g.interface.gameplay_ui.ranker_ui.page.visible)
	var arena=g.interface.gameplay_ui.ranker_ui
	arena.difficulty_tabs[1].pressed.emit();assert(arena.difficulty=="expert")
	arena.audition();assert(arena.auditioning and arena.audition_music.started)
	assert(arena.audition_start>0)
	arena.selected="r02";arena.sync();assert(not arena.auditioning)
	arena.audition();g.launch_ranker("r01","one");arena.sync()
	assert(not arena.auditioning and g.story_music.started)
	g.open_menu("ranker");arena.stop_audition()
	arena=null;ranker_ui=null
	# Let the native mixer release the stopped stream before engine shutdown.
	await create_timer(.15).timeout;g.queue_free();await process_frame;await process_frame
	print("RANKER_SMOKE_OK: 24 tiered charts, %d notes, exact Ogg durations, real one/double inputs, holds, separate records, section/half-speed practice"%total);quit()
