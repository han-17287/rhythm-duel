extends SceneTree
const Ranker=preload("res://gameplay/ranker.gd")

func _initialize()->void:call_deferred("run")

func run()->void:
	var game=load("res://main.tscn").instantiate()
	root.add_child(game);await process_frame
	game.socket.close();game.profile={};game.accounts_enabled=false
	game.preferences.values.volume=0;game.preferences.values.music_volume=0;game.apply_preferences()
	game.open_menu("ranker");game.interface.sync()
	var arena=game.interface.gameplay_ui.ranker_ui
	var song:Dictionary=Ranker.find("r01")
	var phrases:Array=song.get("phrases",[])
	assert(not phrases.is_empty(),"Re-authored songs expose musical practice phrases")
	assert(arena.section_select.item_count==5+phrases.size())
	assert(arena.practice_ranges[0]=={"t":0.0,"end":0.0})
	# Existing whole-song/section entries retain their stable indices.
	assert(is_equal_approx(float(arena.practice_ranges[2].t),float(song.bars[int(song.section_bars)].t)))
	var phrase_index:=mini(7,phrases.size()-1)
	var phrase:Dictionary=phrases[phrase_index]
	arena.section_select.select(5+phrase_index);arena.signature="";arena.sync()
	assert(is_equal_approx(float(arena.preview_bounds(song).t),float(phrase.t)))
	var expected:Array=Ranker.chart("r01","one",float(phrase.t),minf(float(phrase.end),float(phrase.t)+6),"hard")
	assert(arena.preview.notes==expected,"Preview follows the selected phrase instead of the first drop")
	arena.audition()
	assert(is_equal_approx(arena.audition_start,float(song.audio_offset)+float(phrase.t)))
	assert(arena.audition_end<=float(song.audio_offset)+float(phrase.end)+.00001)
	arena.stop_audition()
	arena.loop_toggle.button_pressed=true;arena.speed.select(0)
	arena.practice_selected()
	assert(game.ranker_training and game.ranker_loop and is_equal_approx(game.speed,.5))
	assert(is_equal_approx(game.ranker_seek,float(phrase.t)) and is_equal_approx(game.ranker_end,float(phrase.end)))
	assert(game.ranker_session.is_empty(),"Loop practice cannot claim a global challenge session")
	assert(not game.notes.is_empty())
	for note in game.notes:
		assert(float(note.t)>=-.00001 and float(note.t)<float(phrase.end)-float(phrase.t))
	game.open_menu("ranker");game.interface.sync()
	arena.play.pressed.emit()
	assert(not game.ranker_training and not game.ranker_loop,"Record challenge ignores the practice repeat checkbox")
	assert(is_zero_approx(game.ranker_seek) and is_zero_approx(game.ranker_end) and is_equal_approx(game.speed,1.0))
	game.open_menu("ranker");arena.selected="r04";arena.sync()
	assert(arena.section_select.selected==0 and arena.practice_song=="r04")
	assert(arena.section_select.item_count==5+Ranker.find("r04").phrases.size())
	arena.stop_audition();game.story_music.stop()
	await create_timer(.15).timeout
	arena=null;game.queue_free();await process_frame;await process_frame
	print("RHYTHM_PRACTICE_UI_OK: phrase bounds/preview/audition, section compatibility, loop practice arguments, formal isolation")
	quit()
