extends Control

const CYAN = Color("54f4d4")
const GOLD = Color("ffcc66")
const NAMES = ["perfecto!!!", "greato!!", "nice", "water XXXX"]
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
	if ResourceLoader.exists("res://assets/NotoSansKR.ttf"):
		var korean_theme := Theme.new()
		var korean_font := FontVariation.new()
		korean_font.base_font = load("res://assets/NotoSansKR.ttf")
		korean_font.variation_opentype = {"wght":450.0}
		korean_font.variation_embolden = 0.7
		korean_theme.default_font = korean_font
		theme = korean_theme
	interface = preload("res://interface.gd").new(self)
	interface.build()
	audio = AudioStreamPlayer.new()
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var pcm := PackedByteArray()
	pcm.resize(2204)
	for i in range(1102):
		pcm.encode_s16(i*2, int(sin(i*TAU*880/22050.0)*10000*(1.0-i/1102.0)))
	wav.data = pcm
	audio.stream = wav
	add_child(audio)
	load_session()
	open_transport()

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
		socket.send_text(JSON.stringify(packet))

func load_session() -> void:
	if OS.has_feature("web"):
		var saved = JavaScriptBridge.eval("localStorage.getItem('perfecto_session') || ''")
		session_token = str(saved) if saved else ""
	else:
		var cfg := ConfigFile.new()
		if cfg.load("user://session.cfg")==OK: session_token = str(cfg.get_value("auth","token",""))

func save_session(token: String) -> void:
	session_token = token
	if OS.has_feature("web"):
		JavaScriptBridge.eval("localStorage.setItem('perfecto_session', %s)" % JSON.stringify(token))
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
	interface.page = destination
	interface.room_code = ""
	room_players.clear()
	status.text = reward_text

func configure_room(config: Dictionary) -> void:
	room_settings = config
	if phase=="room" and slot==0: send_packet({"type":"configure","settings":room_settings})

func start_practice() -> void:
	practice = true
	lobby.hide()
	slot = 0
	attacker = 0
	speed = float(room_settings.speed)
	reward_text = ""
	begin_record()
	status.text = "연습 / 공격 리듬 만들기"

func begin_record() -> void:
	phase = "record"
	match_finished = false
	notes.clear()
	hits.clear()
	resolved.clear()
	used = 0
	down = -1
	origin = -1
	next_button.hide()
	result.add_theme_color_override("font_color",Color.WHITE)
	result.text = "SPACE로 리듬을 만드세요"
	hint.text = "첫 입력부터 녹음 · 8개를 채우면 자동 전송 · 최대 30초"

func receive(m: Dictionary) -> void:
	match m.get("type", ""):
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
			reward_text = ""
			status.text = "방 코드: %s  /  나: P%d  /  상대 기다리는 중" % [m.code, slot+1]
		"turn":
			room_settings = m.get("settings",room_settings)
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
			match_finished = bool(m.finished)
			phase = "result"
			update_scores(m.scores)
			result.add_theme_color_override("font_color",Color.WHITE)
			result.text = "수비 점수 +%d" % int(m.points)
			if m.finished:
				result.text = "무승부!" if m.scores[0] == m.scores[1] else "P%d 승리!" % (1 if m.scores[0]>m.scores[1] else 2)
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
			phase = "disconnected"
			result.text = "상대가 방을 나갔습니다"
			hint.text = reward_text

func update_scores(scores: Array) -> void:
	tally.text = "P1  %05d     :     %05d  P2" % [int(scores[0]), int(scores[1])]

func begin_play() -> void:
	phase = "play"
	origin = now() + 4.0
	down = -1
	hits.clear()
	resolved.clear()
	result.text = "READY"
	hint.text = "노트가 왼쪽 판정선에 닿으면 SPACE · 롱 노트는 끝까지 유지"

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.keycode != KEY_SPACE or event.echo: return
	if phase == "record" and slot == attacker:
		if event.pressed and down < 0:
			if not notes.is_empty() and now()-origin < float(notes[-1].t)+float(notes[-1].d)+0.08:
				return
			if origin < 0: origin = now()
			down = now()-origin
			flash = 1.0
			queue_redraw()
			audio.play()
		elif not event.pressed and down >= 0:
			finish_record_note()
	elif phase == "play" and (practice or slot != attacker):
		var t := (now()-origin)*speed
		if t < -0.2: return
		if event.pressed and down < 0:
			down = t
			audio.play()
			flash = 1.0
			judge_tap(t)
		elif not event.pressed and down >= 0:
			var d := maxf(0, t-down)
			hits.append({"t":down,"d":d})
			judge_hold(down,d)
			down = -1

func finish_record_note() -> void:
	var duration := now()-origin-down
	if duration < 0.3: duration = 0
	duration = minf(duration, 8-used)
	notes.append({"t":down,"d":duration})
	used += maxi(1,ceili(duration))
	down = -1
	result.text = "%d / 8" % used
	if used >= 8:
		if practice: begin_play()
		else:
			phase = "waiting"
			send_packet({"type":"pattern","notes":notes})

func show_judgment(error: float) -> void:
	var j := 0 if error<=0.035 else 1 if error<=0.08 else 2 if error<=0.18 else 3
	result.text = NAMES[j]
	result.add_theme_color_override("font_color", [CYAN,GOLD,Color.WHITE,Color("ff688b")][j])

func judge_tap(t: float) -> void:
	var best := -1
	var error := 0.181
	for i in range(notes.size()):
		if resolved.has(i): continue
		var e := absf(t-float(notes[i].t))
		if e < error:
			error = e
			best = i
	if best < 0:
		show_judgment(999)
	elif float(notes[best].d)<0.3:
		resolved[best] = true
		show_judgment(error)

func judge_hold(t: float, d: float) -> void:
	for i in range(notes.size()):
		if not resolved.has(i) and float(notes[i].d)>=0.3 and absf(t-float(notes[i].t))<=0.18:
			resolved[i] = true
			show_judgment(maxf(absf(t-float(notes[i].t)), absf(t+d-float(notes[i].t)-float(notes[i].d))))
			return

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
		status.text = "연결이 지연되고 있어요. 잠시 후 다시 시도하세요."
		if phase=="connecting": phase = "lobby"
	elif connected and state == WebSocketPeer.STATE_CLOSED:
		connected = false
		if phase not in ["lobby","record","result"] or (not practice and phase=="record"):
			phase = "disconnected"
			result.text = "연결이 종료되었습니다"
		status.text = "연결이 종료되었습니다. 다시 접속해 주세요."
	if phase == "record" and origin>=0 and slot==attacker:
		if down>=0:
			var elapsed := minf(now()-origin-down, 8-used)
			result.text = "%d / 8  ·  HOLD %.1fs" % [used+maxi(1,ceili(elapsed)),elapsed]
		if down>=0 and now()-origin-down >= 8-used: finish_record_note()
		elif now()-origin>30:
			phase = "timeout"
			result.text = "녹음 시간 초과 · 처음으로 돌아가세요"
	if phase == "play":
		var t := (now()-origin)*speed
		if t<0: result.text = "READY  %d" % ceili(-t/speed)
		elif not practice and slot==attacker: result.text = "상대가 수비하는 중…"
		for i in range(notes.size()):
			if not resolved.has(i) and t>float(notes[i].t)+float(notes[i].d)+0.18:
				resolved[i] = true
				if practice or slot!=attacker: show_judgment(999)
		var end := float(notes[-1].t)+float(notes[-1].d)+0.5
		if t>end:
			if down>=0:
				hits.append({"t":down,"d":maxf(0,t-down)})
				down = -1
			phase = "result"
			if practice:
				result.text = "연습 완료!"
				next_button.show()
			elif slot!=attacker: send_packet({"type":"result","hits":hits})
			else: result.text = "수비 결과를 기다리는 중…"
	interface.sync(delta)
	flash = maxf(0,flash-delta*4)
	queue_redraw()

func _draw() -> void:
	for gx in range(0,1152,96):
		draw_line(Vector2(gx,0),Vector2(gx,720),Color(0.2,0.25,0.36,0.07),1)
	for gy in range(0,720,96):
		draw_line(Vector2(0,gy),Vector2(1152,gy),Color(0.2,0.25,0.36,0.07),1)
	draw_arc(Vector2(1100,80),210,0,TAU,80,Color(0.64,0.54,1,0.1),60)
	draw_line(Vector2(48,84),Vector2(1104,84),Color("29334d"),1)
	if not phase in ["record","play"]: return
	var y := 460.0
	var left := 180.0
	draw_style_box(panel_style(), Rect2(48,355,1056,165))
	for x in range(200,1080,80): draw_line(Vector2(x,370),Vector2(x,505),Color(0.15,0.2,0.3),1)
	draw_line(Vector2(65,y),Vector2(1085,y),Color("445471"),2)
	draw_line(Vector2(left,370),Vector2(left,505),CYAN,3+flash*5)
	draw_circle(Vector2(left,y),19+flash*7,Color(CYAN,0.12+flash*0.3))
	if phase=="play":
		var t := (now()-origin)*speed
		for i in range(notes.size()):
			var n: Dictionary = notes[i]
			var x := left+(float(n.t)-t)*260
			var tail := x+float(n.d)*260
			if tail<60 or x>1090 or resolved.has(i): continue
			if float(n.d)>0:
				draw_line(Vector2(maxf(x,65),y),Vector2(minf(tail,1090),y),Color(skin_color,0.45),16)
				draw_circle(Vector2(clampf(tail,65,1090),y),8,skin_color)
			if x>=65: draw_circle(Vector2(x,y),13,GOLD if float(n.d)>0 else skin_color)
	elif phase=="record":
		var current := maxf(0,now()-origin) if origin>=0 else 0.0
		var pending_units := maxi(1,ceili(minf(current-down,8-used))) if down>=0 else 0
		for i in range(8):
			draw_circle(Vector2(280+i*90,390),8,CYAN if i<used else (GOLD if i<used+pending_units else Color("283751")))
		for n in notes:
			draw_record_note(float(n.t),float(n.d),current,false)
		if down>=0:
			draw_record_note(down,minf(current-down,8-used),current,true)
			draw_circle(Vector2(1050,y),19+flash*7,Color(GOLD,0.3))

func draw_record_note(start: float, duration: float, current: float, active: bool) -> void:
	var x := 1050.0-(current-start)*260.0
	var tail := x+duration*260.0
	if tail<65 or x>1090: return
	var color := GOLD if active or duration>=0.3 else skin_color
	if duration>0:
		draw_line(Vector2(clampf(x,65,1090),460),Vector2(clampf(tail,65,1090),460),Color(color,0.6),16)
		draw_circle(Vector2(clampf(tail,65,1090),460),8,color)
	if x>=65: draw_circle(Vector2(x,460),13,color)

func panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("17223a")
	s.corner_radius_top_left = 16
	s.corner_radius_top_right = 16
	s.corner_radius_bottom_left = 16
	s.corner_radius_bottom_right = 16
	return s
