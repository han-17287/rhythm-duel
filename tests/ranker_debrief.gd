extends SceneTree
const Ranker=preload("res://gameplay/ranker.gd")
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:push_error(message);quit(1)
func _initialize()->void:call_deferred("run")
func run()->void:
	var game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.socket.close();game.set_process(false);game.profile={};game.accounts_enabled=false
	# This fixture repeatedly finishes without real elapsed audio time. Keep
	# fanfare voices silent so shutdown does not retain active mixer playbacks.
	game.preferences.values.volume=0.0;game.apply_preferences()
	var before:Dictionary=game.preferences.records.duplicate(true)
	var phrase:Dictionary=Ranker.find("r04").phrases[19]
	game.launch_ranker("r04","double",true,1,float(phrase.t),float(phrase.end),"inferno")
	game.hits=game.notes.duplicate(true);game.finish_ranker();game.interface.sync()
	var screen=game.interface.gameplay_ui.ranker_debrief
	check(screen.page.visible,"Ranker result must show its own debrief")
	check(screen.rows.size()==1 and int(screen.rows[0].index)==19,"Only the played phrase is displayed")
	check(screen.selected==0 and not screen.train.disabled,"Played phrase is selectable")
	check(screen.phrase_caption.text.contains("ALL PERFECT"),"Complete exact phrase earns its accurate badge")
	check(screen.timing_plot.valid_count==game.notes.size(),"Timing distribution includes actual timing samples")
	check(is_equal_approx(screen.timing_plot.limit,80),"Plot follows Inferno80ms window")
	check(screen.personal_best.text.contains("연습"),"Practice never claims a personal-best update")
	screen.train.pressed.emit()
	check(game.phase=="play" and game.ranker_training and game.ranker_loop,"Selected phrase goes straight into repeat practice")
	check(is_equal_approx(game.speed,.75) and is_equal_approx(game.ranker_seek,float(phrase.t)),"Retry uses correct phrase and0.75speed")
	check(game.preferences.records==before and game.ranker_session.is_empty(),"Practice does not alter records or create a formal session")
	game.ranker_loop=false;game.hits=game.notes.duplicate(true);game.finish_ranker();game.interface.sync()
	var row:Dictionary=game.ranker_phrase_report[0].duplicate(true)
	var worse:Dictionary=row.duplicate(true);worse.index=20;worse.accuracy=50;worse.extra=3;worse.full_combo=false;worse.all_perfect=false
	game.ranker_phrase_report=[row,worse];game.interface.sync()
	check(screen.selected==1,"Weakest played phrase is selected first")
	var event:=InputEventKey.new();event.pressed=true;event.keycode=KEY_LEFT
	check(screen.handle_input(event) and screen.selected==0,"Arrow input selects another phrase")
	for button in screen.phrase_buttons:
		if button.visible:check(button.size.x<=40,"Heatmap buttons must not overflow due to default content margins")
	row.complete=false;row.full_combo=false;row.all_perfect=false
	game.ranker_phrase_report=[row];game.interface.sync()
	check(screen.phrase_caption.text.contains("부분 연습"),"Partial coverage cannot claim full-phrase mastery")
	game.ranker_phrase_report=[];game.interface.sync()
	check(screen.train.disabled and screen.weakest.disabled,"Empty report offers no invented practice target")
	game.open_menu("ranker");game.interface.sync();check(not screen.page.visible,"Leaving results hides the debrief")
	screen=null;game.queue_free();await process_frame
	print("RANKER_DEBRIEF_OK: %d checks, real phrase/timing, weak selection, practice isolation, keyboard and bounded layout"%checks)
	quit()
