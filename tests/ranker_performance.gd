extends SceneTree
const Ranker=preload("res://gameplay/ranker.gd")
const Preferences=preload("res://gameplay/preferences.gd")
var checks:=0
var game:Control
var saved_preferences:=PackedByteArray()
var had_preferences:=false

func _initialize()->void:call_deferred("run")

func check(condition:bool,message:String)->bool:
	checks+=1
	if not condition:push_error("RANKER_PERFORMANCE_FAILED: "+message)
	return condition

func prepare_phrase(partial:=false,empty:=false)->Dictionary:
	var phrase:Dictionary=Ranker.find("r01").phrases[0]
	game.launch_ranker("r01","one",true,1,float(phrase.t)+(1.0 if partial else 0.0),float(phrase.end),"hard")
	game.notes=[] if empty else [{"t":.2,"d":0.0},{"t":.7,"d":0.0},{"t":1.2,"d":0.0},{"t":1.7,"d":0.0}]
	game.begin_play()
	return phrase

func settle_phrase(phrase:Dictionary)->float:
	var time:float=float(phrase.end)-game.ranker_seek+game.hit_window()+.01
	game.ranker_run.advance(time)
	return time

func incremental_phrases()->bool:
	var phrase:=prepare_phrase()
	if not check(game.ranker_phrase_live.size()==1,"Only the selected phrase has incremental state"):return false
	for i in range(3):game.register_judgment(i,0.0,0.0)
	game.register_judgment(0,INF)
	var row:Dictionary=game.ranker_phrase_live[0]
	if not check(row.judged==3 and row.counts==[3,0,0,0],"Repeated judgment cannot double-count a note"):return false
	settle_phrase(phrase)
	if not check(not row.closed and game.ranker_phrase_notice.is_empty(),"Unresolved final note prevents premature phrase completion"):return false
	game.register_judgment(3,0.0,0.0)
	var finished_at:=settle_phrase(phrase)
	if not check(row.closed and game.ranker_phrase_notice.ends_with("ALL PERFECT"),"Complete exact phrase earns ALL PERFECT"):return false
	if not check(row.points==4000 and row.maximum==4000,"Incremental phrase score matches four exact notes"):return false
	var expiry:float=game.ranker_phrase_notice_until
	game.ranker_run.advance(finished_at+1)
	if not check(is_equal_approx(expiry,game.ranker_phrase_notice_until),"A completed phrase emits feedback exactly once"):return false
	phrase=prepare_phrase()
	for i in range(4):game.register_judgment(i,.03 if i==0 else 0.0)
	settle_phrase(phrase)
	if not check(game.ranker_phrase_notice.ends_with("FULL COMBO") and game.ranker_phrase_live[0].counts==[3,1,0,0],"Great timing preserves FC but does not claim AP"):return false
	phrase=prepare_phrase()
	for i in range(4):game.register_judgment(i,0.0)
	game.judge_tap(3.5)
	settle_phrase(phrase)
	row=game.ranker_phrase_live[0]
	if not check(row.extra==1 and row.points==3400 and game.live_extra==1,"Off-beat input applies the actual 600-point penalty to the phrase"):return false
	if not check(game.ranker_phrase_notice.ends_with("CLEAR"),"Extra input breaks AP and FC even when every note is perfect"):return false
	phrase=prepare_phrase()
	for i in range(4):game.register_judgment(i,INF if i==0 else 0.0)
	settle_phrase(phrase)
	if not check(game.ranker_phrase_live[0].counts==[3,0,0,1] and game.ranker_phrase_notice.ends_with("CLEAR"),"One miss loses combo and still clears at 75 percent"):return false
	phrase=prepare_phrase()
	for i in range(4):game.register_judgment(i,INF if i<2 else 0.0)
	settle_phrase(phrase)
	if not check(game.ranker_phrase_notice.ends_with("다시 도전"),"Below-clear accuracy requests practice"):return false
	phrase=prepare_phrase(true)
	for i in range(4):game.register_judgment(i,0.0)
	settle_phrase(phrase)
	if not check(game.ranker_phrase_live[0].closed and not game.ranker_phrase_live[0].complete and game.ranker_phrase_notice.is_empty(),"Clipped practice cannot claim full-phrase AP or FC"):return false
	phrase=prepare_phrase(false,true)
	settle_phrase(phrase)
	if not check(game.ranker_phrase_live[0].closed and game.ranker_phrase_notice.is_empty(),"An empty phrase never earns an invented award"):return false
	prepare_phrase()
	if not check(game.ranker_phrase_live[0].judged==0 and game.ranker_phrase_live[0].extra==0 and not game.ranker_phrase_live[0].closed and game.ranker_phrase_notice.is_empty(),"Retry resets judgment, stray, closure and notice state"):return false
	game.open_menu("ranker")
	return check(game.ranker_phrase_live.is_empty() and game.ranker_run.note_rows.is_empty() and game.ranker_phrase_notice.is_empty() and game.ranker_phrase_notice_until<0,"Leaving Ranker clears the entire incremental lifecycle")

func report(points:int,combo:int,full:=false,perfect:=false)->Dictionary:
	return {"points":points,"accuracy":90.0,"grade":"A","max_combo":combo,"full_combo":full,"all_perfect":perfect}

func calibrated_phrase_boundaries()->bool:
	var phrase:=prepare_phrase()
	game.ranker_end=float(Ranker.find("r01").phrases[1].end)
	game.begin_play();game.preferences.values.offset_ms=-150
	for i in range(4):
		game.resolved[i]=true;game.register_judgment(i,0.0)
	# Exercise the real update caller: music has crossed the close threshold,
	# but calibrated input still belongs to the preceding phrase.
	game.origin=game.now()-(float(phrase.end)+.11)
	game._process(0)
	var row:Dictionary=game.ranker_phrase_live[0]
	if not check(not row.closed and game.ranker_phrase_notice.is_empty(),"Negative calibration cannot close an interior phrase on the music clock"):return false
	game.judge_tap(float(phrase.end)-.04)
	if not check(row.extra==1 and row.points==3400,"Calibrated boundary stray is attributed before phrase completion"):return false
	game.origin=game.now()-(float(phrase.end)+.27)
	game._process(0)
	if not check(row.closed and game.ranker_phrase_notice.ends_with("CLEAR"),"Interior phrase closes as CLEAR after its calibrated input window expires"):return false
	if not check(absf(game.ranker_phrase_notice_until-(float(phrase.end)+.27+1.5))<.08,"Phrase notice lifetime uses display time, independent of calibration"):return false
	game.preferences.values.offset_ms=0
	phrase=prepare_phrase();game.preferences.values.offset_ms=150
	for i in range(4):
		game.resolved[i]=true;game.register_judgment(i,0.0)
	game.hits=game.notes.duplicate(true)
	game.origin=game.now()-(float(phrase.end)+.11)
	game._process(0)
	row=game.ranker_phrase_live[0]
	if not check(game.phase=="play" and not row.closed and game.ranker_phrase_notice.is_empty(),"Positive calibration cannot award final-phrase AP while tail input remains possible"):return false
	var tail_time:float=float(phrase.end)+.26
	game.judge_tap(tail_time);game.hits.append({"t":tail_time,"d":0.0,"lane":0})
	if not check(row.extra==1 and row.points==3400,"Late final input remains attributed to the last phrase"):return false
	game.origin=game.now()-(float(phrase.end)+.23)
	game._process(0)
	if not check(game.phase=="result" and row.closed and game.ranker_phrase_notice.ends_with("CLEAR"),"Final phrase closes only when the run actually ends"):return false
	if not check(game.last_report.extra==1 and not game.last_report.full_combo and not game.last_report.all_perfect and game.ranker_phrase_report[0].extra==1,"Final report preserves tail penalty without a false mastery stamp"):return false
	game.preferences.values.offset_ms=0;game.open_menu("ranker")
	return true

func persistent_badges()->bool:
	var prefs=Preferences.new()
	var id:=Ranker.record_id("r01","double","expert")
	if not check(prefs.remember(id,report(10000,9)),"First formal score is a personal best"):return false
	var best:Dictionary=prefs.records[id].duplicate(true)
	if not check(not prefs.remember(id,report(9000,10,true)),"Lower-score FC does not replace personal best"):return false
	if not check(prefs.records[id].points==best.points and prefs.records[id].max_combo==best.max_combo and prefs.records[id].full_combo and not prefs.records[id].all_perfect,"FC stamp is independent of best numerical performance"):return false
	var loaded=Preferences.new();loaded.load_data()
	if not check(loaded.records[id]==prefs.records[id],"Lower-score FC stamp is saved and restored"):return false
	if not check(prefs.remember(id,report(11000,8)),"A higher non-FC score still becomes the personal best"):return false
	if not check(prefs.records[id].points==11000 and prefs.records[id].full_combo,"Higher-score non-FC preserves earned FC"):return false
	if not check(not prefs.remember(id,report(8000,12,false,true)),"Lower-score AP updates a badge without replacing the score"):return false
	if not check(prefs.records[id].all_perfect and prefs.records[id].full_combo and prefs.records[id].points==11000,"AP implies FC and preserves the best score"):return false
	prefs.remember(id,report(12000,7))
	loaded.load_data()
	if not check(loaded.records[id].points==12000 and loaded.records[id].all_perfect and loaded.records[id].full_combo,"A subsequent best preserves and reloads both mastery stamps"):return false
	var cfg:=ConfigFile.new()
	cfg.set_value("game","data",{"records":{
		"legacy":{"points":1234,"accuracy":88.0,"grade":"A","max_combo":4},
		"invalid_flags":{"points":100,"accuracy":50.0,"full_combo":"true","all_perfect":1},
		"ap_only":{"points":200,"accuracy":100.0,"all_perfect":true}}})
	if not check(cfg.save("user://preferences.cfg")==OK,"Legacy persistence fixture saves"):return false
	loaded.load_data()
	if not check(not loaded.records.legacy.full_combo and not loaded.records.legacy.all_perfect,"Legacy scores default to no invented mastery badges"):return false
	if not check(not loaded.records.invalid_flags.full_combo and not loaded.records.invalid_flags.all_perfect,"Malformed badge values do not grant achievements"):return false
	return check(loaded.records.ap_only.all_perfect and loaded.records.ap_only.full_combo,"Reloaded AP stamp implies FC even in old partial data")

func run()->void:
	had_preferences=FileAccess.file_exists("user://preferences.cfg")
	if had_preferences:saved_preferences=FileAccess.get_file_as_bytes("user://preferences.cfg")
	game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.socket.close();game.set_process(false);game.profile={};game.accounts_enabled=false
	game.preferences.values.volume=0.0;game.preferences.values.music_volume=0.0;game.preferences.values.reduced_motion=true;game.apply_preferences()
	var success:=incremental_phrases() and calibrated_phrase_boundaries() and persistent_badges()
	game.story_music.stop();game.queue_free();await process_frame;game=null
	if had_preferences:
		var file:=FileAccess.open("user://preferences.cfg",FileAccess.WRITE)
		file.store_buffer(saved_preferences);file.close()
	elif FileAccess.file_exists("user://preferences.cfg"):DirAccess.remove_absolute(ProjectSettings.globalize_path("user://preferences.cfg"))
	if success:print("RANKER_PERFORMANCE_OK: %d checks; exactly-once phrase feedback, AP/FC/stray/miss, partial/empty/reset, calibrated interior/tail boundaries, persistent mastery independent of personal best, legacy reload"%checks)
	quit(0 if success else 1)
