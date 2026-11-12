extends SceneTree
# Run headless with a shell timeout. Every failed check explicitly exits; no
# assert can suspend this SceneTree indefinitely in a debug build.
const Ranker = preload("res://gameplay/ranker.gd")
const Score = preload("res://gameplay/scoring.gd")
var game
var checks := 0
var played_notes := 0
var original_records := ""
var original_preferences_file := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		push_error("RHYTHM_GAMEPLAY_FAILED: " + message)
	return condition

func finish(code: int) -> void:
	if is_instance_valid(game):
		game.story_music.stop()
		game.queue_free()
	call_deferred("quit", code)

func saved_preferences() -> String:
	return FileAccess.get_file_as_string("user://preferences.cfg") if FileAccess.file_exists("user://preferences.cfg") else ""

func run() -> void:
	create_timer(150).timeout.connect(func(): push_error("RHYTHM_GAMEPLAY_TIMEOUT"); quit(124))
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.socket.close()
	game.connected = false
	game.connection_started = -1
	game.outgoing.clear()
	game.preferences.values.key = "SPACE"
	game.preferences.values.offset_ms = 0
	game.preferences.values.reduced_motion = true
	game.preferences.values.volume = 0.0
	game.preferences.values.music_volume = 0.0
	game.apply_preferences()
	original_records = JSON.stringify(game.preferences.records)
	original_preferences_file = saved_preferences()
	if not index_boundaries(): finish(1); return
	if not one_lane_penalties(): finish(1); return
	if not double_hold_and_miss_cursor(): finish(1); return
	if not training_loops(): finish(1); return
	if not all_charts_exact_input(): finish(1); return
	if not no_formal_writes("all practice cases"): finish(1); return
	print("RHYTHM_GAMEPLAY_OK: %d checks, 24 charts / %d real-key notes; bounded lookup, live penalties, hold/miss cursor, practice loops, no record writes" % [checks, played_notes])
	finish(0)

func set_clock(at: float) -> void:
	game.origin = game.now() - at / float(game.speed)

func key_at(at: float, code: int, pressed: bool) -> void:
	set_clock(at)
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	game._input(event)

func tap(at: float, code := KEY_SPACE) -> void:
	key_at(at, code, true)
	key_at(at + .012, code, false)

func advance(at: float) -> void:
	set_clock(at)
	game._process(0.0)

func fixture(kind: String, notes: Array) -> void:
	game.launch_ranker("r01", kind, true, 1.0, 0.0, 0.0, "hard")
	game.notes = notes.duplicate(true)
	game.begin_play()

func live_matches_report(label: String) -> bool:
	var report: Dictionary = Score.analyze(game.notes, game.hits, game.judge_windows(), true, Ranker.EXTRA_PENALTY)
	if not check(is_equal_approx(maxf(0.0, float(game.live_points)), float(report.points)), label + ": live/final points differ"): return false
	if not check(is_equal_approx(float(game.live_possible), float(report.maximum)), label + ": live/final possible points differ"): return false
	if not check(int(game.live_extra) == int(report.extra), label + ": extra count differs"): return false
	if not check(game.live_judgments.size() == game.notes.size(), label + ": unresolved final notes"): return false
	for i in range(game.notes.size()):
		if not check(int(game.live_judgments[i]) == int(report.judgments[i]), label + ": judgment differs at %d" % i): return false
	return true

func index_boundaries() -> bool:
	game.notes = []
	if not check(game.note_index_at(0.0) == 0, "Empty lower bound"): return false
	game.notes = [{"t": .5, "d": 0.0}, {"t": .5, "d": 0.0}, {"t": 1.0, "d": 0.0}, {"t": 8.0, "d": 0.0}]
	for pair in [[-INF, 0], [.499999, 0], [.5, 0], [.500001, 2], [1.0, 2], [1.000001, 3], [8.0, 3], [8.000001, 4], [INF, 4]]:
		if not check(game.note_index_at(float(pair[0])) == int(pair[1]), "Lower bound at %s" % str(pair[0])): return false
	return true

func one_lane_penalties() -> bool:
	fixture("one", [{"t": 1.0, "d": 0.0}, {"t": 1.5, "d": 0.0}, {"t": 2.0, "d": .5}, {"t": 3.0, "d": 0.0}])
	tap(.2)
	if not check(game.live_points == -600 and game.live_possible == 0 and game.live_extra == 1, "First-note stray must retain negative debt"): return false
	tap(1.0)
	if not check(game.live_points == 400 and game.combo == 1, "First perfect must repay earlier stray penalty"): return false
	advance(1.62)
	if not check(game.resolved.has(1) and int(game.live_judgments[1]) == 3 and game.combo == 0, "Expired one-lane tap becomes a miss"): return false
	key_at(2.0, KEY_SPACE, true)
	if not check(game.active_hold == 2 and not game.resolved.has(2), "Hold waits for release"): return false
	key_at(2.5, KEY_SPACE, false)
	tap(2.75)
	tap(3.0)
	advance(3.2)
	if not live_matches_report("ONE perfect/miss/hold/stray"): return false
	var report: Dictionary = Score.analyze(game.notes, game.hits, game.judge_windows(), true, Ranker.EXTRA_PENALTY)
	if not check(report.points == 1800 and report.accuracy == 45 and report.counts == [3, 0, 0, 1], "Known one-lane result"): return false
	# Lower-bound optimization must retain the earliest candidate, rather than
	# stealing a later perfect from dense chronological rhythm scoring.
	fixture("one", [{"t": 1.0, "d": 0.0}, {"t": 1.076, "d": 0.0}])
	tap(.94)
	tap(1.01)
	if not live_matches_report("Dense chronological matching"): return false
	if not check(game.live_points == 800, "Dense presses must produce two NICE judgments"): return false
	# A long run of extras must clamp only for display/final score, never erase
	# debt before later successful notes recover it.
	fixture("one", [{"t": 2.0, "d": 0.0}])
	tap(.2); tap(.5); tap(.8); tap(2.0)
	if not check(game.live_points == -800 and game.live_extra == 3, "Stray debt remains after later note"): return false
	return live_matches_report("Negative live total clamps at final score")

func double_hold_and_miss_cursor() -> bool:
	fixture("double", [{"t": .5, "d": 1.0, "lane": 0}, {"t": .75, "d": 0.0, "lane": 1}, {"t": 1.0, "d": 0.0, "lane": 1}, {"t": 1.25, "d": 0.0, "lane": 1}, {"t": 1.8, "d": 0.0, "lane": 0}])
	tap(.2, KEY_J)
	key_at(.5, KEY_F, true)
	tap(.75, KEY_J)
	advance(1.12)
	if not check(game.double_beat.held[0] and not game.resolved.has(0), "Upper hold survives lower-lane activity"): return false
	if not check(game.resolved.has(2) and int(game.live_judgments[2]) == 3, "Unresolved hold must not block later missed note"): return false
	tap(1.25, KEY_J)
	key_at(1.5, KEY_F, false)
	tap(1.8, KEY_F)
	advance(2.0)
	if not live_matches_report("DOUBLE held lane/missed countervoice"): return false
	if not check(game.judgment_cursor == game.notes.size() and game.live_points == 3400, "Miss cursor drains after hold release"): return false
	fixture("double", [{"t": 1.0, "d": 0.0, "lane": 0}, {"t": 1.0, "d": 0.0, "lane": 1}, {"t": 2.0, "d": 0.0, "lane": 0}])
	key_at(1.0, KEY_J, true); key_at(1.0, KEY_F, true)
	key_at(1.012, KEY_F, false); key_at(1.012, KEY_J, false)
	tap(2.0, KEY_J)
	if not check(not game.resolved.has(2), "Wrong lane cannot consume upper note"): return false
	tap(2.0, KEY_F)
	if not check(game.live_extra == 1 and game.live_points == 2400, "Chord and wrong-lane penalty"): return false
	return live_matches_report("DOUBLE chords and lane isolation")

func play_exact_chart() -> void:
	var events: Array = []
	for note in game.notes:
		var code: int = (KEY_F if int(note.get("lane", 0)) == 0 else KEY_J) if game.ranker_kind == "double" else KEY_SPACE
		events.append({"t": float(note.t), "code": code, "pressed": true})
		events.append({"t": float(note.t) + maxf(.012, float(note.d)), "code": code, "pressed": false})
	events.sort_custom(func(a, b): return a.t < b.t or (a.t == b.t and not a.pressed and b.pressed))
	for event in events:
		key_at(float(event.t), int(event.code), bool(event.pressed))

func no_formal_writes(label: String) -> bool:
	if not check(JSON.stringify(game.preferences.records) == original_records, label + ": local records changed"): return false
	if not check(saved_preferences() == original_preferences_file, label + ": preferences file changed"): return false
	for packet in game.outgoing:
		if not check(packet.get("type", "") not in ["ranker_begin", "ranker_result"], label + ": queued a formal ranker request"): return false
	return check(not game.ranker_upload_pending and game.ranker_waiting.is_empty(), label + ": formal upload/session is pending")

func training_loops() -> bool:
	# Logged-in practice still must never request a ranked nonce or publish.
	game.profile = {"id": "rhythm-test", "name": "RhythmTest", "skin": "mint", "coins": 12, "rating": 1000, "wins": 0, "losses": 0, "draws": 0}
	game.accounts_enabled = true
	game.ranker_session = "stale-formal-session"
	var song: Dictionary = Ranker.find("r01")
	var seek: float = song.bars[8].t
	var end: float = song.bars[12].t
	game.start_ranker("r01", "double", true, .75, seek, end, "expert", true)
	if not check(game.ranker_loop and game.ranker_loop_count == 1 and game.ranker_session.is_empty(), "Loop begins locally and clears old nonce"): return false
	play_exact_chart()
	game.finish_ranker()
	if not check(game.phase == "play" and game.ranker_loop_count == 2 and game.ranker_loop_best == 100 and game.ranker_loop_last.all_perfect, "First loop restarts with retained best/report"): return false
	if not check(game.hits.is_empty() and game.live_extra == 0 and game.live_points == 0 and game.judgment_cursor == 0, "Restart clears attempt state"): return false
	# Complete an empty second attempt; best must survive a worse result.
	game.finish_ranker()
	if not check(game.ranker_loop_count == 3 and game.ranker_loop_best == 100 and game.ranker_loop_last.accuracy == 0, "Second loop retains better previous score"): return false
	key_at(.1, KEY_R, true)
	if not check(game.ranker_loop and game.ranker_loop_count == 3 and game.ranker_loop_best == 100, "R preserves loop statistics"): return false
	if not check(game.ranker_seek == seek and game.ranker_end == end and game.speed == .75 and game.ranker_difficulty == "expert", "R preserves selected rhythm drill"): return false
	key_at(.1, KEY_L, true)
	if not check(not game.ranker_loop and game.phase == "play", "L finishes current attempt instead of aborting it"): return false
	play_exact_chart()
	game.finish_ranker()
	if not check(game.phase == "result" and game.last_report.all_perfect and game.ranker_training, "Stopped loop presents practice result"): return false
	if not no_formal_writes("two loops and final stopped attempt"): return false
	game.start_ranker("r01", "one", true, .5, seek, end, "hard", true)
	game.open_menu("home")
	if not check(game.phase == "lobby" and not game.ranker_loop and game.ranker_loop_last.is_empty() and not game.story_music.started, "Menu exit cancels loop and audio"): return false
	game.launch_ranker("r01", "one", false, 1.0, 0.0, 0.0, "hard", true)
	if not check(not game.ranker_loop, "Formal run cannot enable a practice loop"): return false
	game.open_menu("ranker")
	return no_formal_writes("practice navigation")

func all_charts_exact_input() -> bool:
	var chart_count := 0
	for song in Ranker.catalog():
		for difficulty in Ranker.DIFFICULTIES:
			for kind in ["one", "double"]:
				game.launch_ranker(str(song.id), kind, true, 1.0, 0.0, 0.0, difficulty)
				var count: int = game.notes.size()
				var label: String = "%s/%s/%s" % [song.id, difficulty, kind]
				if not check(count > 0, label + ": empty chart"): return false
				play_exact_chart()
				if not check(game.live_extra == 0 and game.live_judgments.size() == count and game.combo == count, label + ": real-key input dropped a note"): return false
				game.finish_ranker()
				if not check(game.last_report.all_perfect and game.last_report.accuracy == 100 and game.last_report.max_combo == count, label + ": final exact-input score differs"): return false
				if not check(game.live_points == game.last_report.points, label + ": live/final exact score differs"): return false
				played_notes += count
				chart_count += 1
	return check(chart_count == 24, "Expected four songs, three tiers and two disciplines")
