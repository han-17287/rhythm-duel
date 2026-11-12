extends Control

const CYAN = Color("54f4d4")
const GOLD = Color("ffcc66")
const NAMES = ["perfecto!!!", "greato!!", "nice", "water XXXX"]
static var shared_theme: Theme

const Scoring = preload("res://gameplay/scoring.gd")
const Challenges = preload("res://gameplay/challenges.gd")
const Maps = preload("res://gameplay/maps.gd")
const Story = preload("res://gameplay/story.gd")
var story_music: Node
var double_practice:=false
var double_beat = preload("res://gameplay/double_beat.gd").new(self)
const Ranker=preload("res://gameplay/ranker.gd")
var ranker_id:=""
var ranker_kind:="one"
var ranker_difficulty:="hard"
var ranker_one_key:=-1
var ranker_training:=false
var ranker_seek:=0.0
var ranker_end:=0.0
var ranker_session:=""
var ranker_boards:Dictionary={}
var ranker_waiting:Dictionary={}
var ranker_request_at:=0.0
var ranker_upload_pending:=false
var ranker_upload_key:=""
var ranker_upload_at:=0.0
var map_id:=""
var map_training:=false
var map_guide:=false
var map_tick:=-1
var map_guide_index:=0
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
var live_points:=0.0
var live_possible:=0.0
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
var web_input: JavaScriptObject
var copy_success: JavaScriptObject
var copy_failure: JavaScriptObject
var pending := ""
var auth_pending:=false
var auth_started_at:=0.0
var room_public:=false
var room_auto:=false
var room_title:=""
var room_request_canceled:=false
var match_active:=false
var match_cancel_pending:=false
var match_mode:="casual"
var match_started_at:=0.0
var match_cancel_at:=0.0
var match_waiting:=0
var match_position:=0
var match_start_at:=-1.0
var public_rooms:Array=[]
var public_room_filter:="all"
var public_room_loading:=false
var public_room_requested_at:=-10.0
var public_room_error:=""
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
	Input.use_accumulated_input=false
	if OS.has_feature("web"):web_input=JavaScriptBridge.get_interface("PerfectoInput")
	if shared_theme==null and ResourceLoader.exists("res://assets/PerfectoUI.woff2"):
		var korean_theme := Theme.new()
		var korean_font := FontVariation.new()
		korean_font.base_font = load("res://assets/PerfectoUI.woff2")
		korean_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):500.0}
		korean_font.variation_embolden = 0.2
		korean_theme.default_font = korean_font
		shared_theme = korean_theme
	if shared_theme: theme=shared_theme
	preferences.load_data()
	stage=preload("res://gameplay/stage.gd").new(self)
	sounds = get_node_or_null("/root/PerfectoAudio")
	if sounds==null:
		sounds = preload("res://gameplay/sound_bank.gd").new()
		add_child(sounds)
	story_music=preload("res://gameplay/story_music.gd").new()
	add_child(story_music)
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
	socket.outbound_buffer_size=524288
	socket.inbound_buffer_size=524288
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

func connect_room(action: String, public_room := false, title_value := "") -> void:
	if phase != "lobby": return
	cancel_match()
	room_request_canceled=false
	pending=action;practice=false;phase="connecting"
	status.text="대전방에 연결하고 있어요…"
	var packet:Dictionary={"type":action,"code":code.text.to_upper(),"settings":room_settings}
	if action=="create":packet.merge({"public":public_room,"title":title_value})
	queue_request(packet)

func create_social_room(public_room:bool,title_value:String)->void:
	connect_room("create",public_room,title_value)
func join_public_room(code_value:String)->void:
	code.text=code_value;connect_room("join")
func browse_public_rooms(mode := "all")->void:
	public_room_filter=mode;public_room_loading=true;public_room_requested_at=now();public_room_error=""
	queue_request({"type":"browse_rooms","mode":mode})
func start_matchmaking(mode:String)->void:
	if phase!="lobby" or match_active or match_cancel_pending:return
	if mode not in ["casual","rush","double","ranked"]:return
	if mode=="ranked" and profile.is_empty():interface.page="auth";status.text="랭크전은 로그인이 필요해요.";return
	match_active=true;match_mode=mode;match_started_at=now();match_waiting=0;match_position=0
	practice=false;room_request_canceled=false;status.text="실제 상대를 찾고 있어요…"
	queue_request({"type":"match_join","mode":mode})
func cancel_match()->void:
	if not match_active:return
	match_active=false;match_waiting=0;match_position=0;match_start_at=-1
	status.text=""
	outgoing=outgoing.filter(func(packet):return packet.get("type","")!="match_join")
	if connected:
		match_cancel_pending=true;match_cancel_at=now();send_packet({"type":"match_cancel"})
	else:match_cancel_pending=false

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
	cancel_match()
	auth_pending=true;auth_started_at=now()
	status.text = "계정 서버에서 확인하고 있어요…"
	queue_request({"type":action,"name":name_value,"password":password_value})

func open_menu(destination: String) -> void:
	cancel_match()
	if phase=="connecting":
		room_request_canceled=true
		outgoing=outgoing.filter(func(packet):return packet.get("type","") not in ["create","join"])
	room_public=false;room_auto=false;room_title="";match_start_at=-1
	ranker_id="";ranker_difficulty="hard";ranker_session="";ranker_waiting.clear()
	story_music.stop()
	double_practice=false
	double_beat.reset()
	if not map_id.is_empty() and interface.gameplay_ui.map_ui: interface.gameplay_ui.map_ui.selected=map_id
	map_id=""
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

func start_practice(double_mode := false) -> void:
	ranker_id="";ranker_difficulty="hard";ranker_session=""
	double_practice=double_mode
	map_id=""
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
	if web_input!=null:web_input.clearPointers()
	story_music.stop()
	double_beat.reset()
	map_id=""
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
	result.text = "F 위 / J 아래 · 두 줄로 만들어봐" if is_double() else "%s로 리듬을 만드세요"%str(preferences.values.key)
	hint.text = "첫 입력부터 녹음 · 8개를 채우고 미리듣기 · 전송 · 최대 30초"

func receive(m: Dictionary) -> void:
	match m.get("type", ""):
		"room_list":
			if str(m.get("mode",public_room_filter))!=public_room_filter:return
			public_rooms=m.get("rooms",[]);public_room_loading=false;public_room_error=""
		"match_status":
			if bool(m.get("queued",false)):
				if not match_active:return
				if str(m.get("mode",match_mode))!=match_mode:return
				match_waiting=int(m.get("waiting",1));match_position=int(m.get("position",1))
				match_started_at=now()-float(m.get("elapsed",now()-match_started_at))
			else:
				match_active=false;match_cancel_pending=false;match_waiting=0;match_position=0
		"match_found":
			if not match_active:return
			room_auto=true;match_start_at=now()+maxf(0,float(m.get("starts_in",3)))
			status.text="상대를 찾았어요! %s"%str(m.get("opponent","상대"))
		"leave_ok":
			match_cancel_pending=false
		"ranker_ready":
			if ranker_waiting.get("id","")==m.id and ranker_waiting.get("kind","")==m.kind and ranker_waiting.get("difficulty","hard")==m.get("difficulty","hard") and (interface.page=="ranker" or phase=="result"):
				ranker_session=str(m.session);ranker_waiting.clear();launch_ranker(str(m.id),str(m.kind),false,1.0,0.0,0.0,str(m.get("difficulty","hard")))
		"ranker_board":
			ranker_boards[Ranker.board_id(str(m.id),str(m.kind),str(m.get("difficulty","hard")))]=m
		"ranker_result":
			var response_key:=Ranker.board_id(str(m.id),str(m.kind),str(m.get("difficulty","hard")))
			if response_key==ranker_upload_key:ranker_upload_pending=false
			apply_profile(m.profile)
			if response_key==Ranker.board_id(ranker_id,ranker_kind,ranker_difficulty):
				reward_text="글로벌 기록 등록 완료"+(" · 첫 클리어 +%d 코인"%int(m.coins) if int(m.coins)>0 else "")
				emote_text=reward_text;emote_until=now()+5
			ranker_boards.erase(response_key)
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
			auth_pending=false
			apply_profile(m.get("profile",{}))
			if m.has("token"): save_session(str(m.token))
			status.text = str(m.get("message","로그인되었습니다." if not profile.is_empty() else "로그아웃했습니다."))
			if interface.page=="auth": interface.page = "home"
		"reward":
			apply_profile(m.profile)
			reward_text = "보상 +%d 코인   ·   레이팅 %+d" % [int(m.coins),int(m.rating)]
			hint.text = reward_text
		"room":
			if not bool(m.get("auto",false)) and match_active:return
			if bool(m.get("auto",false)) and match_active and str(m.settings.mode)!=match_mode:return
			if bool(m.get("auto",false)) and not match_active and phase=="lobby":return
			if room_request_canceled and phase=="lobby":return
			room_public=bool(m.get("public",room_public));room_auto=bool(m.get("auto",room_auto));room_title=str(m.get("title",room_title))
			room_settings = m.settings
			room_players = m.players
			interface.update_options()
			phase = "room"
		"joined":
			if bool(m.get("auto",false)) and not match_active:
				send_packet({"type":"match_cancel"});return
			if not bool(m.get("auto",false)) and match_active:return
			if bool(m.get("auto",false)) and str(m.get("settings",{}).get("mode",match_mode))!=match_mode:return
			if room_request_canceled:
				send_packet({"type":"leave"});return
			room_public=bool(m.get("public",false));room_auto=bool(m.get("auto",false));room_title=str(m.get("title",""))
			match_cancel_pending=false
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
			match_active=false;match_cancel_pending=false;match_start_at=-1
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
			var action:String=str(m.get("action",""))
			if action in ["register","login","resume","logout"]:auth_pending=false
			if action=="browse_rooms":public_room_loading=false;public_room_error=status.text
			if action in ["match_join","match_cancel"]:match_active=false;match_cancel_pending=false;match_waiting=0;match_position=0
			if m.get("action","")=="ranker_begin":ranker_waiting.clear()
			if m.get("action","")=="ranker_result":
				ranker_upload_pending=false;reward_text="글로벌 등록 실패 · 로컬 기록은 저장됐어요."
			if m.get("action","")=="resume":
				save_session("")
				apply_profile({})
			if phase=="connecting" and action in ["create","join"]:
				phase="lobby";pending=""
				interface.page="rooms"
		"left":
			if m.has("code") and str(m.code)!=interface.room_code:return
			match_active=false;match_cancel_pending=false;match_start_at=-1
			opponent_left=true
			if phase=="room" and room_auto:
				phase="lobby";interface.page="rooms";room_auto=false;room_public=false
				room_players.clear();interface.room_code="";status.text="상대의 연결이 끊겼어요. 다시 검색해 주세요.";return
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
	if is_double(): double_beat.release_all()
	if key_held and phase=="record": finish_record_note()
	elif key_held and phase=="play" and (practice or slot!=attacker): release_hit(input_time())
	if practice and phase=="play" and not paused:
		if not ranker_id.is_empty() and not ranker_training:
			ranker_training=true;ranker_session="";status.text+=" · 연습 전환";emote_text="창을 벗어나 연습으로 전환했어요. 정식 기록에는 반영하지 않아요.";emote_until=now()+5
		toggle_pause()

func apply_preferences() -> void:
	sounds.volume = float(preferences.values.volume)
	if story_music:story_music.volume(float(preferences.values.volume),float(preferences.values.music_volume))
	effects.enabled = bool(preferences.values.effects) and not bool(preferences.values.reduced_motion)
	for art in get_tree().get_nodes_in_group("perfecto_art"):
		if is_ancestor_of(art): art.motion_enabled=not bool(preferences.values.reduced_motion)

func input_time() -> float:
	return play_time()+float(preferences.values.offset_ms)/1000.0*speed

func begin_play() -> void:
	if web_input!=null:web_input.clearPointers()
	ranker_one_key=-1
	story_music.stop()
	if not ranker_id.is_empty():
		var song:=Ranker.find(ranker_id)
		story_music.prepare(ranker_id,speed,float(song.audio_offset)+ranker_seek,"ranker")
		story_music.start(maxf(0,story_music.pre_roll-4*60.0/song_bpm()))
	elif not map_id.is_empty():
		story_music.prepare(map_id,speed,4*60.0/float(Maps.find(map_id).bpm))
		story_music.start(0)
	double_beat.reset()
	phase = "play"
	origin = now() + (4*60.0/song_bpm()/speed if is_song() else 4.0)
	down = -1
	key_held = false
	active_hold = -1
	paused = false
	hits.clear()
	resolved.clear()
	live_judgments.clear()
	live_points=0;live_possible=0
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
	hint.text = "F 위 / J 아래 · 동시 입력 가능 · 홀드는 끝까지 유지" if is_double() else "SPACE / F / J · 한 줄 교차 입력 · 홀드는 끝까지 유지" if not ranker_id.is_empty() else "판정선에 맞춰 %s · 롱 노트는 끝까지 유지"%str(preferences.values.key)

func toggle_fullscreen() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function(){try{const c=document.getElementById('canvas');const p=document.fullscreenElement?document.exitFullscreen():c.requestFullscreen?.();if(p&&p.catch)p.catch(()=>{})}catch(e){}})()")
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func pointer_input(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode={"SPACE":KEY_SPACE,"D":KEY_D,"F":KEY_F,"J":KEY_J,"K":KEY_K}.get(preferences.values.key,KEY_SPACE)
	event.pressed=pressed
	event.set_meta("pointer",true)
	event.set_meta("pointer_delay",web_pointer_delay(pressed))
	_input(event)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo: return
	if phase=="lobby" and interface.get("auth_view") and interface.auth_view.handle_input(event):
		get_viewport().set_input_as_handled();return
	if phase in ["record","play"] and event.physical_keycode in [KEY_SPACE,KEY_D,KEY_F,KEY_J,KEY_K]:event.keycode=event.physical_keycode
	var event_delay:=web_key_delay(event)
	var event_now:=now()-event_delay
	if phase in ["record","play"] and (event.ctrl_pressed or event.alt_pressed or event.meta_pressed):return
	if phase=="lobby" and interface and interface.gameplay_ui:
		if interface.gameplay_ui.calibration_ui.handle_input(event,event_delay):
			get_viewport().set_input_as_handled();return
		if interface.gameplay_ui.ranker_ui.handle_input(event):
			get_viewport().set_input_as_handled();return
		if interface.gameplay_ui.map_ui.handle_input(event):
			get_viewport().set_input_as_handled();return
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
	if event.pressed and event.keycode==KEY_R and practice and phase=="result":replay_last();return
	if paused:
		if event.pressed and event.keycode==KEY_R:restart_practice_current()
		return
	if is_double():
		double_beat.input(event,event_delay)
		return
	var selected_key: int = {"SPACE":KEY_SPACE,"D":KEY_D,"F":KEY_F,"J":KEY_J,"K":KEY_K}.get(preferences.values.key,KEY_SPACE)
	if event.keycode!=selected_key and not (not ranker_id.is_empty() and ranker_kind=="one" and event.keycode in [KEY_SPACE,KEY_F,KEY_J]): return
	if phase=="record" and slot==attacker:
		if event.pressed and not key_held:
			if not notes.is_empty() and event_now-origin<float(notes[-1].t)+float(notes[-1].d)+0.08: return
			if origin<0: origin=event_now
			key_held = true
			down = event_now-origin
			flash = 1.0
			feedback_color=skin_color
			sounds.note(notes.size())
		elif not event.pressed and key_held:
			finish_record_note(event_now)
	elif phase=="play" and (practice or slot!=attacker):
		var t := input_time()-event_delay*speed
		if not ranker_id.is_empty() and ranker_kind=="one":
			if event.pressed and key_held and active_hold<0 and event.keycode!=ranker_one_key:release_hit(t)
			if not event.pressed and event.keycode!=ranker_one_key:return
		if event.pressed and not key_held:
			if t < -0.180001: return
			ranker_one_key=event.keycode
			key_held = true
			down = t
			flash = 1.0
			feedback_color=CYAN
			sounds.note(resolved.size(),.23 if is_song() else 1.0)
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

func finish_record_note(at := -1.0) -> void:
	var duration := (now() if at<0 else at)-origin-down
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
	var j := Scoring.judgment(error,judge_windows())
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
	var j := Scoring.judgment(error,judge_windows())
	live_judgments[index]=j
	var weight:float=maxi(1,ceili(float(notes[index].d)))
	live_points+=float(Scoring.POINTS[j])*weight;live_possible+=1000*weight
	combo = 0 if j==3 else combo+1
	max_combo = maxi(max_combo,combo)
	if signed_offset!=null: hit_offsets.append(float(signed_offset)*1000)
	if solo_id=="survival": energy=clampf(energy+(-24 if j==3 else 3 if j==0 else -4 if j==2 else 0),0,100)
	show_judgment(error)
	last_hit_offset=null if signed_offset==null else float(signed_offset)*1000
	if j==3: sounds.play("miss",0.55)
	else:
		effects.burst(Vector2(180,406+int(notes[index].get("lane",0))*76 if is_double() else 460),skin_color,j==0)
		if combo>0 and combo%(25 if not ranker_id.is_empty() else 4)==0:
			sounds.play("perfect",0.18 if is_song() else 0.4)
			effects.combo_pop(combo,Vector2(180,406+int(notes[index].get("lane",0))*76 if is_double() else 460))
	if not practice: send_packet({"type":"progress","combo":combo,"resolved":live_judgments.size()})

func judge_tap(t: float, lane := 0) -> void:
	var best := -1
	var error := hit_window()+.000001
	for i in range(notes.size()):
		if resolved.has(i) or int(notes[i].get("lane",0))!=lane: continue
		var difference := absf(t-float(notes[i].t))
		if difference<=error:
			error=difference
			best=i
			if not ranker_id.is_empty():break
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
		var best_error := hit_window()+.000001
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
	if phase=="record" and (used>0 or key_held or double_beat.held[0] or double_beat.held[1]): return
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
	var saved: Array=preferences.patterns[index].notes
	var saved_double: bool=saved.any(func(n):return n.has("lane"))
	if not practice and saved_double!=is_double():
		emote_text="현재 모드와 같은 줄 수의 리듬을 선택해 주세요.";emote_until=now()+3;return
	if practice:double_practice=saved_double
	double_beat.reset()
	notes=saved.duplicate(true)
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
	ranker_id="";ranker_difficulty="hard";ranker_session=""
	story_music.stop()
	double_practice=false
	map_id=""
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
	if not map_id.is_empty():
		next_map()
		return
	if phase!="result" or solo_id.is_empty() or match_finished: return
	solo_wave+=1
	start_solo_wave()

func finish_local_round() -> void:
	if not ranker_id.is_empty():
		finish_ranker();return
	if not map_id.is_empty():
		finish_map()
		return
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
	if not ranker_id.is_empty() and not ranker_training:
		emote_text="정식 랭커 도전은 일시정지할 수 없어요. 구간 연습에서는 가능해요.";emote_until=now()+3;return
	if key_held or (is_double() and (double_beat.held[0] or double_beat.held[1])):
		hint.text="키를 뗀 후 잠시 멈출 수 있어요."
		return
	if not paused:
		paused=true
		paused_at=now()
		story_music.pause(true)
	else:
		origin+=now()-paused_at
		paused=false
		story_music.pause(false)

func replay_last() -> void:
	if not practice or phase!="result": return
	if not ranker_id.is_empty():
		start_ranker(ranker_id,ranker_kind,ranker_training,speed,ranker_seek,ranker_end,ranker_difficulty);return
	if not map_id.is_empty():
		start_map(map_id,map_training,speed,map_guide)
		return
	if not solo_id.is_empty():
		start_challenge(solo_id)
	else: begin_play()

func _process(delta: float) -> void:
	if phase=="lobby" and interface and interface.page!="ranker":ranker_waiting.clear()
	if ranker_upload_pending and now()-ranker_upload_at>10:
		ranker_upload_pending=false;reward_text="글로벌 등록을 확인하지 못했어요. 로컬 기록은 저장됐어요."
	if not ranker_waiting.is_empty() and now()-ranker_request_at>12:
		var pending_ranker:=ranker_waiting.duplicate();ranker_waiting.clear()
		emote_text="연결이 지연되어 로컬 기록으로 시작해요.";emote_until=now()+5
		if interface.page=="ranker" or phase=="result":launch_ranker(pending_ranker.id,pending_ranker.kind,false,1.0,0.0,0.0,str(pending_ranker.get("difficulty","hard")))
	if auth_pending and now()-auth_started_at>12:
		auth_pending=false
		outgoing=outgoing.filter(func(packet):return packet.get("type","") not in ["register","login","resume","logout"])
		if interface.page=="auth":status.text="계정 서버 응답이 늦어요. 잠시 후 다시 시도해 주세요."
	if match_cancel_pending and now()-match_cancel_at>12:
		match_cancel_pending=false
	if match_active and phase=="lobby" and interface.page!="rooms":cancel_match()
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not connected:
			connected = true
			connection_started = -1
			send_packet({"type":"hello"})
			if not session_token.is_empty():
				auth_pending=true;auth_started_at=now();send_packet({"type":"resume","token":session_token})
			for packet in outgoing: send_packet(packet)
			outgoing.clear()
		while socket.get_available_packet_count()>0:
			var packet = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if packet is Dictionary: receive(packet)
	elif connection_started>=0 and (state==WebSocketPeer.STATE_CLOSED or now()-connection_started>90):
		socket.close()
		auth_pending=false;match_active=false;match_cancel_pending=false;public_room_loading=false
		connection_started = -1
		outgoing.clear()
		if not practice or phase=="lobby": status.text = "연결이 지연되고 있어요. 잠시 후 다시 시도하세요."
		if phase=="connecting": phase = "lobby"
	elif connected and state == WebSocketPeer.STATE_CLOSED:
		connected = false
		auth_pending=false;match_active=false;match_cancel_pending=false;public_room_loading=false
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
		if is_double(): double_beat.update()
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
			if preview_t>pattern_end()+0.5:
				phase="review"
				result.text="이 비트로 공격할까?"
				hint.text="ENTER 전송   ·   R 다시 만들기   ·   P 다시 듣기"
		elif phase=="play":
			var t := play_time()
			if is_song():
				update_map_audio(t)
				t=play_time()
			if is_song() and not story_music.failure().is_empty():
				var destination:="ranker" if not ranker_id.is_empty() else "solo"
				open_menu(destination);emote_text="음악을 불러오지 못했어요. 연결을 확인하고 다시 시작해 주세요.";emote_until=now()+5;return
			if t<0:
				var tick := ceili(-t/(60.0/song_bpm())) if is_song() else ceili(-t/speed)
				if combo==0: result.text="READY  %d"%tick
				if tick!=countdown_tick:
					countdown_tick=tick
					if not is_song():sounds.play("count",0.5)
			elif countdown_tick!=0:
				countdown_tick=0
				if not is_song():sounds.play("go",0.5)
				if combo==0: result.text="GO!"
			if t>=0 and not practice and slot==attacker: result.text="상대가 수비하는 중…"
			if active_hold>=0 and key_held and not resolved.has(active_hold):
				var remaining := maxf(0,(float(notes[active_hold].t)+float(notes[active_hold].d)-input_time())/speed)
				result.text="HOLD  %.1fs"%remaining
				if now()-last_hold_sound>0.18:
					last_hold_sound=now()
					sounds.play("hold",0.12)
					flash=maxf(flash,0.3)
			var judgment_time:=input_time()
			for i in range(notes.size()):
				if not resolved.has(i) and judgment_time>float(notes[i].t)+float(notes[i].d)+hit_window()+.000001:
					resolved[i]=true
					if practice or slot!=attacker: register_judgment(i,INF)
			if solo_id=="survival" and energy<=0:
				if is_double(): double_beat.release_all()
				elif key_held: release_hit(input_time())
				finish_local_round()
			elif t>round_end()+absf(float(preferences.values.offset_ms))/1000*speed:
				if is_double(): double_beat.release_all()
				elif key_held: release_hit(input_time())
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
	if is_double():
		double_beat.draw()
		stage.draw_progress()
		return
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
		var t := play_time()
		for i in range(notes.size()):
			var n: Dictionary = notes[i]
			var x := left+(float(n.t)-t)*scroll_pixels()
			var tail := x+float(n.d)*scroll_pixels()
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

func note_radius() -> float:
	if ranker_id.is_empty():return 18.0
	var base:float={"hard":12.0,"expert":10.5,"inferno":9.0}.get(ranker_difficulty,12.0)
	return base*minf(1.0,float(preferences.values.ranker_scroll))
func draw_note(pos: Vector2, color: Color) -> void:
	NoteSkin.draw(self,pos,color,str(profile.get("skin","mint")),note_radius())

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


func start_map(id: String, training := false, rate := 1.0, guide := false) -> void:
	ranker_id="";ranker_difficulty="hard";ranker_session=""
	double_practice=false
	var data:=Maps.find(id)
	if data.is_empty() or (not training and not Maps.unlocked(id,preferences.records)):return
	practice=true
	map_id=id
	map_training=training
	map_guide=training and guide
	solo_id=""
	solo_reports.clear()
	new_best=false
	reward_text=""
	slot=0
	attacker=0
	speed=clampf(rate,.5,1.25) if training else 1.0
	notes=Maps.chart(id).duplicate(true)
	map_tick=-1
	map_guide_index=0
	begin_play()
	match_finished=false
	status.text="MAP %s  ·  %s  ·  %d BPM  ·  %.2fx%s"%[id.substr(1),str(data.name),int(data.bpm),speed,"  ·  연습" if training else ""]

func update_map_audio(t: float) -> void:
	if t<0:return
	story_music.start(t)
	if map_guide:
		while map_guide_index<notes.size() and t>=float(notes[map_guide_index].t):
			sounds.play("note%d"%posmod(map_guide_index,8),.25)
			map_guide_index+=1

func finish_map() -> void:
	story_music.stop()
	last_report=Scoring.analyze(notes,hits)
	last_report_mine=true
	phase="result"
	match_finished=true
	var cleared:=float(last_report.accuracy)>=60
	if not map_training:new_best=preferences.remember(Maps.record_id(map_id),last_report)
	result.text="연습 완료!" if map_training else ("보스 격파!" if int(map_id.substr(1))%4==0 else "신호 복구!") if cleared else "한 번 더 도전해볼까?"
	result.add_theme_color_override("font_color",Color("f1edff"))
	next_button.hide()
	if cleared:
		sounds.fanfare()
		effects.confetti()

func next_map() -> void:
	if phase!="result" or map_id.is_empty():return
	var id:=Maps.next_id(map_id)
	if not id.is_empty():start_map(id,map_training,speed,map_guide)


func copy_room_code() -> void:
	var code_value: String=interface.room_code
	if code_value.is_empty():return
	if OS.has_feature("web"):
		var nav=JavaScriptBridge.get_interface("navigator")
		if nav.clipboard==null:
			clipboard_result([],false)
			return
		if copy_success==null:
			copy_success=JavaScriptBridge.create_callback(clipboard_result.bind(true))
			copy_failure=JavaScriptBridge.create_callback(clipboard_result.bind(false))
		nav.clipboard.writeText(code_value).then(copy_success).catch(copy_failure)
	else:
		DisplayServer.clipboard_set(code_value)
		clipboard_result([],true)

func clipboard_result(_args: Array, succeeded: bool) -> void:
	if succeeded:
		interface.room_view.copied_until=now()+2.5
		emote_text="방 코드를 복사했어요. 친구에게 보내줘!"
	else:emote_text="자동 복사를 사용할 수 없어요. 화면의 방 코드를 직접 입력해 주세요."
	emote_until=now()+3

func is_double() -> bool:
	return ranker_kind=="double" if not ranker_id.is_empty() else double_practice if practice else room_settings.mode=="double"

func pattern_end() -> float:
	var end:=0.0
	for n in notes:end=maxf(end,float(n.t)+float(n.d))
	return end

func start_double_training() -> void:
	start_practice(true)
	notes=[{"t":0.0,"d":0.0,"lane":0},{"t":0.5,"d":0.0,"lane":1},{"t":1.0,"d":0.0,"lane":0},{"t":1.0,"d":0.0,"lane":1},{"t":1.75,"d":1.0,"lane":0},{"t":2.0,"d":0.0,"lane":1},{"t":2.5,"d":0.0,"lane":1},{"t":3.25,"d":0.0,"lane":0}]
	begin_play()
	status.text="DOUBLE BEAT · F 위 / J 아래 · 교차·동시·홀드 연습"

func play_time() -> float:
	if is_song() and phase=="play" and story_music.started and DisplayServer.get_name()!="headless":
		return (story_music.last_clock if paused else story_music.time())-story_music.pre_roll
	return ((paused_at if paused else now())-origin)*speed

func round_end() -> float:
	if not ranker_id.is_empty():return (ranker_end if ranker_end>0 else float(Ranker.find(ranker_id).duration))-ranker_seek+.05
	if not map_id.is_empty():
		var data:=Maps.find(map_id)
		return float(data.bars)*4*60.0/float(data.bpm)+.25
	return pattern_end()+.5

func is_song() -> bool:return not map_id.is_empty() or not ranker_id.is_empty()
func song_bpm() -> float:
	if not ranker_id.is_empty():return float(Ranker.section(ranker_id,ranker_seek).bpm)
	return float(Maps.find(map_id).bpm) if not map_id.is_empty() else 120.0
func judge_windows() -> Array:return Ranker.windows(ranker_difficulty) if not ranker_id.is_empty() else Scoring.WINDOWS
func hit_window() -> float:return float(judge_windows()[2])

func start_ranker(id: String,kind: String,training := false,rate := 1.0,seek := 0.0,end := 0.0,difficulty := "hard") -> void:
	var song:=Ranker.find(id)
	if song.is_empty() or not kind in ["one","double"] or not difficulty in Ranker.DIFFICULTIES or Ranker.source_chart(id,kind,difficulty).is_empty():return
	if not training and not profile.is_empty() and accounts_enabled:
		if not ranker_waiting.is_empty():return
		ranker_waiting={"id":id,"kind":kind,"difficulty":difficulty};ranker_request_at=now()
		queue_request({"type":"ranker_begin","id":id,"kind":kind,"difficulty":difficulty})
		status.text="기록 도전을 준비하고 있어요…";return
	launch_ranker(id,kind,training,rate,seek,end,difficulty)

func launch_ranker(id: String,kind: String,training := false,rate := 1.0,seek := 0.0,end := 0.0,difficulty := "hard") -> void:
	map_id="";map_guide=false;solo_id="";practice=true;slot=0;attacker=0
	if training or profile.is_empty():ranker_session=""
	ranker_id=id;ranker_kind=kind;ranker_difficulty=difficulty;ranker_training=training;ranker_seek=seek if training else 0.0;ranker_end=end if training else 0.0
	speed=clampf(rate,.5,1) if training else 1.0
	notes=Ranker.chart(id,kind,ranker_seek,ranker_end,difficulty);new_best=false;reward_text=""
	begin_play();match_finished=false
	status.text="RANKER / %s / %s / %s / %s"%[difficulty.to_upper(),"DOUBLE" if kind=="double" else "ONE BEAT",str(Ranker.find(id).title),"연습 %.2fx"%speed if training else "STRICT TIMING"]

func finish_ranker() -> void:
	story_music.stop()
	last_report=Scoring.analyze(notes,hits,Ranker.windows(ranker_difficulty),true)
	last_report.grade=Ranker.grade(last_report.accuracy)
	last_report_mine=true;phase="result";match_finished=true
	if not ranker_training:new_best=preferences.remember(Ranker.record_id(ranker_id,ranker_kind,ranker_difficulty),last_report)
	result.text="연습 완료" if ranker_training else "RANKER CLEAR" if last_report.accuracy>=75 else "RETRY THE LIMIT"
	next_button.hide()
	if not ranker_training and not ranker_session.is_empty():
		ranker_upload_key=Ranker.board_id(ranker_id,ranker_kind,ranker_difficulty);ranker_upload_pending=true;ranker_upload_at=now();reward_text="글로벌 기록 등록 중…"
		queue_request({"type":"ranker_result","session":ranker_session,"hits":hits,"difficulty":ranker_difficulty})
		ranker_session=""
	if last_report.accuracy>=75:sounds.fanfare();effects.confetti()

func scroll_pixels() -> float:
	return 260*1.55*float(preferences.values.ranker_scroll) if not ranker_id.is_empty() else 260.0
func restart_practice_current() -> void:
	if not practice:return
	if not ranker_id.is_empty():launch_ranker(ranker_id,ranker_kind,true,speed,ranker_seek,ranker_end,ranker_difficulty)
	elif not map_id.is_empty():start_map(map_id,map_training,speed,map_guide)
	elif not solo_id.is_empty():start_challenge(solo_id)
	else:begin_play()

func web_key_delay(event: InputEventKey) -> float:
	if event.has_meta("pointer"):return float(event.get_meta("pointer_delay",0.0))
	if web_input==null:return 0
	var code:String={KEY_SPACE:"Space",KEY_D:"KeyD",KEY_F:"KeyF",KEY_J:"KeyJ",KEY_K:"KeyK"}.get(event.keycode,"")
	if code.is_empty():return 0
	var lag=web_input.take(code,event.pressed)
	return clampf(float(lag)/1000.0,0,.5) if lag!=null else 0.0

func web_pointer_delay(pressed:bool)->float:
	if web_input==null:return 0
	return clampf(float(web_input.takePointer(pressed))/1000.0,0,.5)
