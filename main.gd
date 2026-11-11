extends Control

const CYAN = Color("54f4d4")
const GOLD = Color("ffcc66")
const NAMES = ["perfecto!!!", "greato!!", "nice", "water XXXX"]
static var shared_theme: Theme

const Scoring = preload("res://gameplay/scoring.gd")
const Challenges = preload("res://gameplay/challenges.gd")
const NoteSkin = preload("res://gameplay/note_skin.gd")
var lane_style: StyleBoxFlat
var pad_style: StyleBoxFlat
var stage: RefCounted
var preferences = preload("res://gameplay/preferences.gd").new()
var sounds: Node
var effects: Node2D
var key_held := false
var active_hold := -1
var live_judgments: Dictionary = {}
var combo := 0
var max_combo := 0
var hit_offsets: Array = []
var last_hit_offset = null
var last_report: Dictionary = {}
var last_report_mine := true
var last_judgment := ""
var judgment_age := 0.0
var countdown_tick := -1
var preview_index := 0
var metronome_tick := -1
var last_hold_sound := 0.0
var activity_units := 0
var spectator_combo := 0
var spectator_resolved := 0
var turn_started_client := 0.0
var stage_deadline := INF
var library_return_phase := "lobby"
var solo_id := ""
var solo_wave := 0
var solo_reports: Array = []
var energy := 100.0
var new_best := false
var paused := false
var paused_at := 0.0
var emote_text := ""
var emote_until := 0.0
var rematch_votes: Array = []
var opponent_left := false
var socket := WebSocketPeer.new()
var connected := false
var pending := ""
var slot := 0
var attacker := 0
var phase := "lobby"
var notes: Array = []
var hits: Array = []
var resolved: Dictionary = {}
var origin := 0.0
var down := -1.0
var speed := 1.0
var used := 0
var turn_index := 0
var practice := false
var last_state := WebSocketPeer.STATE_CLOSED
var title: Label
var status: Label
var result: Label
var tally: Label
var hint: Label
var endpoint: LineEdit
var code: LineEdit
var lobby: HBoxContainer
var next_button: Button
var practice_button: Button
var flash := 0.0
var feedback_color := CYAN
var audio: AudioStreamPlayer
var interface: RefCounted
var profile: Dictionary = {}
var accounts_enabled := false
var session_token := ""
var outgoing: Array = []
var connection_started := -1.0
var room_settings := {"mode":"casual","rounds":3,"speed":1.0}
var room_players: Array = []
var reward_text := ""
var match_finished := false
var judgment_tween: Tween
var skin_color := CYAN
var catalog: Array = [
	{"id":"mint","name":"민트 펄스","price":0,"color":"54f4d4"},
	{"id":"lavender","name":"라벤더 웨이브","price":100,"color":"b49bff"},
	{"id":"sunset","name":"선셋 글로우","price":250,"color":"ff997d"},
	{"id":"ice","name":"아이스 블루","price":400,"color":"8cdaff"}
]

func now() -> float:
	return Time.get_ticks_usec() / 1000000.0

func label_at(text_value: String, pos: Vector2, font_size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text_value
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	add_child(l)
	return l

func _ready() -> void:
	if shared_theme==null and ResourceLoader.exists("res://assets/NotoSansKR.ttf"):
		var korean_theme := Theme.new()
		var korean_font := FontVariation.new()
		korean_font.base_font = load("res://assets/NotoSansKR.ttf")
		korean_font.variation_opentype = {"wght":450.0}
		korean_font.variation_embolden = 0.7
		korean_theme.default_font = korean_font
		shared_theme = korean_theme
	if shared_theme: theme=shared_theme
	preferences.load_data()
	stage=preload("res://gameplay/stage.gd").new(self)
	sounds = get_node_or_null("/root/PerfectoAudio")
	if sounds==null:
		sounds = preload("res://gameplay/sound_bank.gd").new()
		add_child(sounds)
	effects = preload("res://gameplay/particles.gd").new()
	add_child(effects)
	apply_preferences()
	interface = preload("res://interface.gd").new(self)
	interface.build()
	apply_preferences()
	load_session()
	if not session_token.is_empty(): open_transport()

func open_transport() -> void:
	if socket.get_ready_state() in [WebSocketPeer.STATE_OPEN,WebSocketPeer.STATE_CONNECTING]: return
	connected = false
	socket = WebSocketPeer.new()
	var err := socket.connect_to_url(endpoint.text.strip_edges())
	if err != OK:
		status.text = "서버 주소를 확인하세요"
		return
	connection_started = now()

func queue_request(packet: Dictionary) -> void:
	if connected and socket.get_ready_state()==WebSocketPeer.STATE_OPEN:
		send_packet(packet)
	else:
		outgoing.append(packet)
		open_transport()

func connect_room(action: String) -> void:
	if phase != "lobby": return
	pending = action
	practice = false
	phase = "connecting"
	status.text = "친구와 연결하고 있어요…"
	queue_request({"type":action,"code":code.text.to_upper(),"settings":room_settings})

func send_packet(packet: Dictionary) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(packet,"",true,true))

func load_session() -> void:
	if OS.has_feature("web"):
		var saved = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('perfecto_session') || ''}catch(e){return ''}})()")
		session_token = str(saved) if saved else ""
	else:
		var cfg := ConfigFile.new()
		if cfg.load("user://session.cfg")==OK: session_token = str(cfg.get_value("auth","token",""))

func save_session(token: String) -> void:
	session_token = token
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function(){try{localStorage.setItem('perfecto_session', %s)}catch(e){}})()" % JSON.stringify(token))
	else:
		var cfg := ConfigFile.new()
		cfg.set_value("auth","token",token)
		cfg.save("user://session.cfg")

func apply_profile(data: Dictionary) -> void:
	profile = data
	skin_color = CYAN
	for item in catalog:
		if item.id == profile.get("skin","mint"): skin_color = Color(str(item.color))

func account_action(action: String, name_value := "", password_value := "") -> void:
	status.text = "계정 서버에서 확인하고 있어요…"
	queue_request({"type":action,"name":name_value,"password":password_value})

func open_menu(destination: String) -> void:
	if not practice and phase!="lobby": send_packet({"type":"leave"})
	phase = "lobby"
	down = -1
	key_held = false
	paused = false
	solo_id = ""
	interface.page = destination
	interface.room_code = ""
	room_players.clear()
	status.text = reward_text

func configure_room(config: Dictionary) -> void:
	room_settings = config
	if phase=="room" and slot==0: send_packet({"type":"configure","settings":room_settings})

func start_practice() -> void:
	practice = true
	solo_id = ""
	solo_reports.clear()
	lobby.hide()
	slot = 0
	attacker = 0
	speed = float(room_settings.speed)
	reward_text = ""
	begin_record()
	status.text = "프리스타일 연습   ·   %.2fx"%speed

func begin_record() -> void:
	phase = "record"
	stage_deadline=INF if practice else minf(now()+45,turn_started_client+150)
	key_held = false
	active_hold = -1
	metronome_tick = -1
	paused = false
	activity_units = 0
	new_best = false
	last_report.clear()
	match_finished = false
	notes.clear()
	hits.clear()
	resolved.clear()
	used = 0
	down = -1
	origin = -1
	next_button.hide()
	result.add_theme_color_override("font_color",Color("f1edff"))
	result.text = "%s로 리듬을 만드세요"%str(preferences.values.key)
	hint.text = "첫 입력부터 녹음 · 8개를 채우고 미리듣기 · 전송 · 최대 30초"

func receive(m: Dictionary) -> void:
	match m.get("type", ""):
		"draft_ready":
			stage_deadline=now()+float(m.get("remaining",90))
			if phase=="review": hint.text = "미리듣기로 확인하고 공격을 보내세요."
		"activity":
			activity_units = int(m.get("units",0))
			if phase=="waiting":
				result.text = "상대가 공격을 준비하는 중…" if m.get("review",false) else "상대가 리듬을 만드는 중…"
		"progress":
			spectator_combo = int(m.get("combo",0))
			spectator_resolved = int(m.get("resolved",0))
		"rematch_state":
			rematch_votes = m.votes
		"emote":
			emote_text = "P%d: %s"%[int(m.slot)+1,str(m.text)]
			emote_until = now()+3
		"hello":
			accounts_enabled = bool(m.get("accounts_enabled",false))
			catalog = m.get("catalog",catalog)
		"profile":
			apply_profile(m.get("profile",{}))
			if m.has("token"): save_session(str(m.token))
			status.text = str(m.get("message","로그인되었습니다." if not profile.is_empty() else "로그아웃했습니다."))
			if interface.page=="auth": interface.page = "home"
		"reward":
			apply_profile(m.profile)
			reward_text = "보상 +%d 코인   ·   레이팅 %+d" % [int(m.coins),int(m.rating)]
			hint.text = reward_text
		"room":
			room_settings = m.settings
			room_players = m.players
			interface.update_options()
			phase = "room"
		"joined":
			slot = int(m.slot)
			interface.room_code = str(m.code)
			phase = "room"
			room_settings = m.get("settings",room_settings)
			room_players.clear()
			last_report.clear()
			rematch_votes.clear()
			opponent_left=false
			reward_text = ""
			status.text = "방 코드: %s  /  나: P%d  /  상대 기다리는 중" % [m.code, slot+1]
		"turn":
			room_settings = m.get("settings",room_settings)
			last_report.clear()
			rematch_votes.clear()
			opponent_left=false
			turn_started_client=now()
			stage_deadline=now()+45
			turn_index = int(m.turn)
			attacker = int(m.attacker)
			speed = float(m.speed)
			update_scores(m.scores)
			begin_record()
			status.text = "라운드 %d / %d · %.2fx · 나: P%d · 공격: P%d" % [turn_index/2+1,int(room_settings.rounds),speed,slot+1,attacker+1]
			if slot != attacker:
				phase = "waiting"
				result.text = "상대가 리듬을 만드는 중…"
				hint.text = "잠시 후 노트가 오른쪽에서 나타납니다"
		"pattern":
			notes = m.notes
			speed = float(m.speed)
			begin_play()
		"result":
			if m.has("report"): last_report = m.report
			last_report_mine = int(m.get("defender",1-attacker))==slot
			match_finished = bool(m.finished)
			phase = "result"
			update_scores(m.scores)
			result.add_theme_color_override("font_color",Color("f1edff"))
			result.text = "수비 점수 +%d" % int(m.points)
			if m.finished:
				if m.scores[slot]>=m.scores[1-slot]:
					sounds.fanfare()
					effects.confetti()
				result.text = "무승부!" if m.scores[0] == m.scores[1] else "%s 승리!" % player_name(0 if m.scores[0]>m.scores[1] else 1)
				hint.text = "경기 종료 · 처음으로 버튼으로 새 경기를 시작하세요"
			else:
				next_button.visible = slot == 0
				hint.text = "방장이 다음 공수를 시작합니다"
		"error":
			status.text = str(m.message)
			if m.get("action","")=="resume":
				save_session("")
				apply_profile({})
			if phase == "connecting":
				socket.close()
				connected = false
				phase = "lobby"
				lobby.show()
		"left":
			opponent_left=true
			if phase=="result" and match_finished:
				emote_text="상대가 나갔어요. 결과는 그대로 확인할 수 있어요."
				emote_until=now()+4
			elif phase in ["record","waiting","review","preview","play","result"]:
				phase="result"
				match_finished=true
				last_report.clear()
				result.text="상대의 이탈로 승리!"
				hint.text=reward_text if not reward_text.is_empty() else "중도 이탈 경기는 코인 보상이 없어요."
			else:
				phase="disconnected"
				result.text="상대가 방을 나갔습니다"
				hint.text="메인으로 돌아가 새 방을 만들어봐요."

func player_name(index: int) -> String:
	if index<room_players.size() and str(room_players[index])!="게스트": return str(room_players[index])
	return "P%d"%(index+1)

func update_scores(scores: Array) -> void:
	var left:=player_name(0)
	var right:=player_name(1)
	left=left.left(4)+"…" if left.length()>4 else left
	right=right.left(4)+"…" if right.length()>4 else right
	tally.text = "%s  %05d   :   %05d  %s" % [left,int(scores[0]),int(scores[1]),right]

func _notification(what: int) -> void:
	if what!=NOTIFICATION_APPLICATION_FOCUS_OUT: return
	if key_held and phase=="record": finish_record_note()
	elif key_held and phase=="play" and (practice or slot!=attacker): release_hit(input_time())
	if practice and phase=="play" and not paused: toggle_pause()

func apply_preferences() -> void:
	sounds.volume = float(preferences.values.volume)
	effects.enabled = bool(preferences.values.effects) and not bool(preferences.values.reduced_motion)
	for art in get_tree().get_nodes_in_group("perfecto_art"):
		if is_ancestor_of(art): art.motion_enabled=not bool(preferences.values.reduced_motion)

func input_time() -> float:
	return (now()-origin+float(preferences.values.offset_ms)/1000.0)*speed

func begin_play() -> void:
	phase = "play"
	origin = now() + 4.0
	down = -1
	key_held = false
	active_hold = -1
	paused = false
	hits.clear()
	resolved.clear()
	live_judgments.clear()
	hit_offsets.clear()
	combo = 0
	max_combo = 0
	countdown_tick = -1
	metronome_tick = -1
	spectator_combo = 0
	spectator_resolved = 0
	last_report.clear()
	result.text = "READY"
	result.add_theme_color_override("font_color",Color("f1edff"))
	hint.text = "판정선에 맞춰 %s · 롱 노트는 끝까지 유지"%str(preferences.values.key)

func toggle_fullscreen() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function(){try{const c=document.getElementById('canvas');const p=document.fullscreenElement?document.exitFullscreen():c.requestFullscreen?.();if(p&&p.catch)p.catch(()=>{})}catch(e){}})()")
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func pointer_input(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode={"SPACE":KEY_SPACE,"D":KEY_D,"F":KEY_F,"J":KEY_J,"K":KEY_K}.get(preferences.values.key,KEY_SPACE)
	event.pressed=pressed
	_input(event)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo: return
	if event.pressed and event.keycode==KEY_ESCAPE and practice and phase=="play":
		toggle_pause()
		return
	if phase=="preview" and event.pressed and event.keycode==KEY_P:
		stop_preview()
		return
	if phase=="review" and event.pressed:
		if event.keycode==KEY_ENTER: confirm_pattern()
		elif event.keycode==KEY_R: retry_recording()
		elif event.keycode==KEY_P: preview_pattern()
		return
	if paused: return
	var selected_key: int = {"SPACE":KEY_SPACE,"D":KEY_D,"F":KEY_F,"J":KEY_J,"K":KEY_K}.get(preferences.values.key,KEY_SPACE)
	if event.keycode!=selected_key: return
	if phase=="record" and slot==attacker:
		if event.pressed and not key_held:
			if not notes.is_empty() and now()-origin<float(notes[-1].t)+float(notes[-1].d)+0.08: return
			if origin<0: origin=now()
			key_held = true
			down = now()-origin
			flash = 1.0
			feedback_color=skin_color
			sounds.note(notes.size())
		elif not event.pressed and key_held:
			finish_record_note()
	elif phase=="play" and (practice or slot!=attacker):
		var t := input_time()
		if event.pressed and not key_held:
			if t < -0.180001: return
			key_held = true
			down = t
			flash = 1.0
			feedback_color=CYAN
			sounds.note(resolved.size())
			judge_tap(t)
		elif not event.pressed and key_held:
			release_hit(t)

func release_hit(t: float) -> void:
	var duration := maxf(0,t-down)
	hits.append({"t":down,"d":duration})
	if active_hold>=0: judge_hold(down,duration)
	key_held = false
	down = -1
	active_hold = -1

func finish_record_note() -> void:
	var duration := now()-origin-down
	if duration<0.3: duration=0
	duration = minf(duration,8-used)
	notes.append({"t":down,"d":duration})
	used += maxi(1,ceili(duration))
	key_held = false
	down = -1
	result.text = "%d / 8"%used
	if used>=8:
		phase = "review"
		stage_deadline=INF if practice else minf(now()+90,turn_started_client+150)
		result.text = "너의 비트가 완성됐어!"
		hint.text = "P 미리듣기   ·   R 다시 만들기   ·   ENTER 공격 전송"
		if not practice: send_packet({"type":"draft","notes":notes})
	elif not practice:
		send_packet({"type":"activity","units":used})

func preview_pattern() -> void:
	if phase!="review": return
	phase = "preview"
	preview_index = 0
	last_hold_sound = 0
	origin = now()+0.75
	resolved.clear()
	result.text = "LISTEN TO YOUR BEAT"
	hint.text = "완성된 리듬을 듣는 중…"

func stop_preview() -> void:
	if phase!="preview": return
	phase="review"
	result.text="이 비트로 공격할까?"
	hint.text="ENTER 전송   ·   R 다시 만들기   ·   P 다시 듣기"

func confirm_pattern() -> void:
	if phase!="review": return
	if practice: begin_play()
	else:
		phase="waiting"
		activity_units=8
		result.text="공격을 보내는 중…"
		send_packet({"type":"confirm"})

func retry_recording() -> void:
	if not phase in ["record","review","preview","timeout"]: return
	if not practice: send_packet({"type":"edit"})
	begin_record()

func show_judgment(error: float) -> void:
	var j := Scoring.judgment(error)
	last_hit_offset=null
	last_judgment = NAMES[j]
	feedback_color=[Color("72ffe4"),Color("ffdc88"),Color("c4a6ff"),Color("ff719b")][j]
	judgment_age = 0
	result.text = last_judgment
	if judgment_tween and judgment_tween.is_valid(): judgment_tween.kill()
	result.pivot_offset = Vector2(0,22)
	if not preferences.values.reduced_motion:
		result.scale = Vector2(1.055,1.055)
		judgment_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		judgment_tween.tween_property(result,"scale",Vector2.ONE,0.18)
	result.add_theme_color_override("font_color",feedback_color)

func register_judgment(index: int, error: float, signed_offset = null) -> void:
	if live_judgments.has(index): return
	var j := Scoring.judgment(error)
	live_judgments[index]=j
	combo = 0 if j==3 else combo+1
	max_combo = maxi(max_combo,combo)
	if signed_offset!=null: hit_offsets.append(float(signed_offset)*1000)
	if solo_id=="survival": energy=clampf(energy+(-24 if j==3 else 3 if j==0 else -4 if j==2 else 0),0,100)
	show_judgment(error)
	last_hit_offset=null if signed_offset==null else float(signed_offset)*1000
	if j==3: sounds.play("miss",0.55)
	else:
		effects.burst(Vector2(180,460),skin_color,j==0)
		if combo>0 and combo%4==0:
			sounds.play("perfect",0.4)
			effects.combo_pop(combo)
	if not practice: send_packet({"type":"progress","combo":combo,"resolved":live_judgments.size()})

func judge_tap(t: float) -> void:
	var best := -1
	var error := 0.180001
	for i in range(notes.size()):
		if resolved.has(i): continue
		var difference := absf(t-float(notes[i].t))
		if difference<=error:
			error=difference
			best=i
	if best<0:
		combo=0
		show_judgment(INF)
		sounds.play("miss",.25)
		if solo_id=="survival": energy=maxf(0,energy-10)
	elif float(notes[best].d)<0.3:
		resolved[best]=true
		register_judgment(best,error,t-float(notes[best].t))
	else:
		active_hold=best
		result.text="HOLD IT…"

func judge_hold(t: float, d: float) -> void:
	var index := active_hold
	# Direct calls are also used by deterministic scoring tests.
	if index<0:
		var best_error := 0.180001
		for i in range(notes.size()):
			if resolved.has(i) or float(notes[i].d)<0.3: continue
			var error := absf(t-float(notes[i].t))
			if error<=best_error:
				best_error=error
				index=i
	if index<0 or resolved.has(index): return
	resolved[index]=true
	var note: Dictionary = notes[index]
	var start_error:=t-float(note.t)
	var release_error:=t+d-float(note.t)-float(note.d)
	register_judgment(index,maxf(absf(start_error),absf(release_error)),release_error if absf(release_error)>absf(start_error) else start_error)

func open_library() -> void:
	if phase=="record" and (used>0 or key_held): return
	library_return_phase=phase
	if phase=="record": phase="library"
	else: interface.page="library"

func close_library() -> void:
	if library_return_phase=="record": phase="record"
	else: interface.page="solo"

func use_saved_pattern(index: int) -> void:
	if index<0 or index>=preferences.patterns.size(): return
	if library_return_phase!="record":
		practice=true
		solo_id=""
		slot=0
		attacker=0
		speed=float(room_settings.speed)
	notes=preferences.patterns[index].notes.duplicate(true)
	used=8
	down=-1
	key_held=false
	origin=-1
	last_report.clear()
	new_best=false
	phase="review"
	result.text=str(preferences.patterns[index].name)
	status.text="보관함에서 가져온 리듬"
	if not practice: send_packet({"type":"draft","notes":notes})

func save_current_pattern() -> void:
	if phase!="review": return
	if preferences.save_pattern(notes):
		emote_text="리듬을 보관함에 저장했어요!"
	else: emote_text="보관함이 가득 찼어요. 기존 리듬을 정리해 주세요."
	emote_until=now()+4

func start_challenge(id: String) -> void:
	practice=true
	solo_id=id
	solo_wave=0
	solo_reports.clear()
	energy=100
	new_best=false
	slot=0
	attacker=0
	start_solo_wave()

func start_solo_wave() -> void:
	var course: Dictionary = Challenges.courses().filter(func(c): return c.id==solo_id)[0]
	speed=float(course.speed)+(.08*solo_wave if solo_id=="survival" else .08*mini(solo_wave,2))
	speed=minf(speed,2.5)
	notes=Challenges.pattern(solo_id,solo_wave)
	begin_play()
	match_finished=false
	status.text="%s   ·   WAVE %d%s   ·   %.2fx"%[str(course.name),solo_wave+1,"" if solo_id=="survival" else " / 3",speed]

func next_solo_wave() -> void:
	if phase!="result" or solo_id.is_empty() or match_finished: return
	solo_wave+=1
	start_solo_wave()

func finish_local_round() -> void:
	last_report=Scoring.analyze(notes,hits)
	last_report_mine=true
	phase="result"
	match_finished=true
	result.add_theme_color_override("font_color",Color("f1edff"))
	if solo_id.is_empty():
		result.text="연습 결과"
		hint.text="같은 리듬에 다시 도전하거나 새 리듬을 만들어봐."
	else:
		solo_reports.append(last_report.duplicate(true))
		var course_finished := (solo_id!="survival" and solo_wave>=2) or (solo_id=="survival" and energy<=0)
		match_finished=course_finished
		result.text="앙코르 종료!" if solo_id=="survival" and course_finished else "코스 결과" if course_finished else "WAVE %d %s"%[solo_wave+1,"CLEAR" if last_report.accuracy>=60 else "FINISH"]
		if course_finished:
			last_report=Challenges.combine(solo_reports)
			if solo_id!="survival": result.text="코스 클리어!" if last_report.accuracy>=60 else "다시 도전해볼까?"
			new_best=preferences.remember(Challenges.record_id(solo_id),last_report)
			hint.text=("NEW BEST!   ·   " if new_best else "")+"기록은 이 기기에 저장돼요."
		else:
			hint.text="다음 비트에 도전해봐!" if solo_id!="survival" else "남은 에너지 %d   ·   다음 웨이브는 더 빨라져요."%int(energy)
	if last_report.full_combo:
		sounds.fanfare()
		effects.confetti()
	next_button.hide()

func toggle_pause() -> void:
	if not practice or phase!="play": return
	if key_held:
		hint.text="키를 뗀 후 잠시 멈출 수 있어요."
		return
	if not paused:
		paused=true
		paused_at=now()
	else:
		origin+=now()-paused_at
		paused=false

func replay_last() -> void:
	if not practice or phase!="result": return
	if not solo_id.is_empty():
		start_challenge(solo_id)
	else: begin_play()

func _process(delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not connected:
			connected = true
			connection_started = -1
			send_packet({"type":"hello"})
			if not session_token.is_empty(): send_packet({"type":"resume","token":session_token})
			for packet in outgoing: send_packet(packet)
			outgoing.clear()
		while socket.get_available_packet_count()>0:
			var packet = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if packet is Dictionary: receive(packet)
	elif connection_started>=0 and (state==WebSocketPeer.STATE_CLOSED or now()-connection_started>90):
		socket.close()
		connection_started = -1
		outgoing.clear()
		if not practice or phase=="lobby": status.text = "연결이 지연되고 있어요. 잠시 후 다시 시도하세요."
		if phase=="connecting": phase = "lobby"
	elif connected and state == WebSocketPeer.STATE_CLOSED:
		connected = false
		if not practice and phase not in ["lobby","result"]:
			phase = "disconnected"
			result.text = "연결이 종료되었습니다"
			hint.text = "메인으로 돌아가 새 방을 만들어 주세요."
			key_held=false
			down=-1
			active_hold=-1
		if not practice or phase=="lobby": status.text = "연결이 종료되었습니다. 다시 접속해 주세요."
	judgment_age += delta
	if not paused:
		if phase=="record" and origin>=0 and slot==attacker:
			if key_held:
				var elapsed := minf(now()-origin-down,8-used)
				result.text="%d / 8   ·   HOLD %.1fs"%[used+maxi(1,ceili(elapsed)),elapsed]
			if key_held and now()-origin-down>=8-used: finish_record_note()
			elif now()-origin>30:
				phase="timeout"
				result.text="이번 비트는 시간이 다 됐어"
			if bool(preferences.values.metronome):
				var beat := floori((now()-origin)*float(preferences.values.bpm)/60)
				if beat!=metronome_tick:
					metronome_tick=beat
					sounds.play("tick",0.3)
		elif phase=="preview":
			var preview_t := (now()-origin)*speed
			while preview_index<notes.size() and preview_t>=float(notes[preview_index].t):
				sounds.note(preview_index)
				preview_index+=1
			if preview_index>0:
				var current: Dictionary=notes[preview_index-1]
				if float(current.d)>=0.3 and preview_t<float(current.t)+float(current.d) and now()-last_hold_sound>0.18:
					last_hold_sound=now()
					sounds.play("hold",0.12)
			if preview_t>float(notes[-1].t)+float(notes[-1].d)+0.5:
				phase="review"
				result.text="이 비트로 공격할까?"
				hint.text="ENTER 전송   ·   R 다시 만들기   ·   P 다시 듣기"
		elif phase=="play":
			var t := (now()-origin)*speed
			if t<0:
				var tick := ceili(-t/speed)
				if combo==0: result.text="READY  %d"%tick
				if tick!=countdown_tick:
					countdown_tick=tick
					sounds.play("count",0.5)
			elif countdown_tick!=0:
				countdown_tick=0
				sounds.play("go",0.5)
				if combo==0: result.text="GO!"
			if t>=0 and not practice and slot==attacker: result.text="상대가 수비하는 중…"
			if active_hold>=0 and key_held and not resolved.has(active_hold):
				var remaining := maxf(0,(float(notes[active_hold].t)+float(notes[active_hold].d)-input_time())/speed)
				result.text="HOLD  %.1fs"%remaining
				if now()-last_hold_sound>0.18:
					last_hold_sound=now()
					sounds.play("hold",0.12)
					flash=maxf(flash,0.3)
			for i in range(notes.size()):
				if not resolved.has(i) and input_time()>float(notes[i].t)+float(notes[i].d)+0.180001:
					resolved[i]=true
					if practice or slot!=attacker: register_judgment(i,INF)
			if solo_id=="survival" and energy<=0:
				if key_held: release_hit(input_time())
				finish_local_round()
			elif t>float(notes[-1].t)+float(notes[-1].d)+0.5+absf(float(preferences.values.offset_ms))/1000*speed:
				if key_held: release_hit(input_time())
				if practice: finish_local_round()
				else:
					phase="result"
					if slot!=attacker: send_packet({"type":"result","hits":hits})
					else: result.text="수비 결과를 기다리는 중…"
	interface.sync(delta)
	flash = maxf(0,flash-delta*4)
	queue_redraw()

func _draw() -> void:
	if stage and stage.active(): stage.draw()
	else: stage.draw_menu()
	if phase=="waiting":
		for i in range(8):
			var y: float = 426.0+(sin(now()*3+i)*3 if not preferences.values.reduced_motion else 0)
			draw_circle(Vector2(245+i*95,y),16,Color("ff715c") if i<activity_units else Color("e5ded8"))
		return
	if not phase in ["record","play","preview","review"]: return
	if pad_style==null: pad_style=StyleBoxFlat.new()
	var key_style: StyleBoxFlat=pad_style
	key_style.bg_color = Color("214a50") if key_held else Color("28233f")
	key_style.border_color = Color("75ffe4") if key_held else Color("786293")
	key_style.set_border_width_all(2)
	key_style.set_corner_radius_all(14)
	if phase=="record" or (phase=="play" and (practice or slot!=attacker)):
		draw_style_box(key_style,Rect2(870,541,232,82))
	var y := 460.0
	var left := 1050.0 if phase in ["record","review"] else 180.0
	draw_style_box(panel_style(), Rect2(48,355,1056,165))
	if flash>0: draw_rect(Rect2(50,357,1052,161),Color(feedback_color,flash*.055))
	for x in range(200,1080,80): draw_line(Vector2(x,370),Vector2(x,505),Color(0.15,0.2,0.3),1)
	draw_line(Vector2(65,y),Vector2(1085,y),Color("71648d"),2)
	draw_line(Vector2(left,368),Vector2(left,508),Color(CYAN,.14),18+flash*14,true)
	draw_line(Vector2(left,368),Vector2(left,508),CYAN,3+flash*3,true)
	draw_string(ThemeDB.fallback_font,Vector2(left-12,516),"REC" if phase in ["record","review"] else "HIT",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("c6fff0"))
	draw_circle(Vector2(left,y),19+flash*7,Color(CYAN,0.12+flash*0.3))
	if phase=="play" and key_held and active_hold>=0:
		var hold: Dictionary=notes[active_hold]
		var ratio:=clampf((input_time()-float(hold.t))/maxf(.001,float(hold.d)),0,1)
		draw_arc(Vector2(left,y),32,-PI/2,TAU-PI/2,48,Color(GOLD,.18),3,true)
		if ratio>0:draw_arc(Vector2(left,y),32,-PI/2,ratio*TAU-PI/2,48,GOLD,3,true)
	if flash>0:
		for i in range(8):
			var angle := i*TAU/8
			var start := Vector2(left,y)+Vector2(cos(angle),sin(angle))*(25+(1-flash)*20)
			draw_line(start,start+Vector2(cos(angle),sin(angle))*9,Color(CYAN,flash),2,true)
	if phase in ["play","preview"]:
		var t := ((paused_at if paused else now())-origin)*speed
		for i in range(notes.size()):
			var n: Dictionary = notes[i]
			var x := left+(float(n.t)-t)*260
			var tail := x+float(n.d)*260
			if tail<60 or x>1090 or resolved.has(i): continue
			if float(n.d)>0:
				draw_line(Vector2(maxf(x,65),y),Vector2(minf(tail,1090),y),Color(skin_color,.12),30,true)
				draw_line(Vector2(maxf(x,65),y),Vector2(minf(tail,1090),y),Color(skin_color,0.85 if active_hold==i and key_held else 0.5),18,true)
				draw_line(Vector2(maxf(x,65),y),Vector2(minf(tail,1090),y),Color(skin_color.lightened(.4),.75),5,true)
				draw_circle(Vector2(clampf(tail,65,1090),y),8,skin_color)
			if x>=65: draw_note(Vector2(x,y),GOLD if float(n.d)>0 else skin_color)
	elif phase in ["record","review"]:
		var current := maxf(0,now()-origin) if origin>=0 else 0.0
		if phase=="review":
			var end := float(notes[-1].t)+float(notes[-1].d)
			var scale_x := 900.0/maxf(end,1)
			for n in notes:
				var x := 100+float(n.t)*scale_x
				if float(n.d)>0: draw_line(Vector2(x,460),Vector2(x+float(n.d)*scale_x,460),Color(GOLD,0.5),16)
				draw_note(Vector2(x,460),GOLD if float(n.d)>0 else skin_color)
		else:
			for n in notes: draw_record_note(float(n.t),float(n.d),current,false)
		if key_held:
			draw_record_note(down,minf(current-down,8-used),current,true)
			draw_circle(Vector2(1050,y),19+flash*7,Color(GOLD,0.3))

	stage.draw_progress()

func draw_record_note(start: float, duration: float, current: float, active: bool) -> void:
	var x := 1050.0-(current-start)*260.0
	var tail := x+duration*260.0
	if tail<65 or x>1090: return
	var color := GOLD if active or duration>=0.3 else skin_color
	if duration>0:
		draw_line(Vector2(clampf(x,65,1090),460),Vector2(clampf(tail,65,1090),460),Color(color,0.6),16)
		draw_circle(Vector2(clampf(tail,65,1090),460),8,color)
	if x>=65: draw_note(Vector2(x,460),color)

func draw_note(pos: Vector2, color: Color) -> void:
	NoteSkin.draw(self,pos,color,str(profile.get("skin","mint")))

func panel_style() -> StyleBoxFlat:
	if lane_style: return lane_style
	var s := StyleBoxFlat.new()
	s.bg_color = Color("1c1c34")
	s.border_color=Color("56456f")
	s.set_border_width_all(1)
	s.corner_radius_top_left = 16
	s.corner_radius_top_right = 16
	s.corner_radius_bottom_left = 16
	s.corner_radius_bottom_right = 16
	lane_style=s
	return s
