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
	title = label_at("PERFECTO / RHYTHM DUEL", Vector2(48, 28), 30, CYAN)
	label_at("01  CREATE A RHYTHM     /     02  ECHO IT     /     03  WIN", Vector2(50, 76), 15, Color("8395b8"))
	status = label_at("방을 만들거나 코드로 참가하세요", Vector2(50, 185), 24)
	tally = label_at("P1  00000     :     00000  P2", Vector2(730, 36), 20, GOLD)
	result = label_at("MAKE YOUR MOVE", Vector2(50, 275), 40, GOLD)
	hint = label_at("SPACE · 짧게 누르면 노트 / 길게 누르면 롱 노트", Vector2(50, 605), 20)
	label_at("노트 예산 8  ·  롱 노트 1초당 1  ·  공수 교대  ·  총 3라운드", Vector2(50, 650), 16, Color("8395b8"))
	lobby = HBoxContainer.new()
	lobby.position = Vector2(50, 120)
	lobby.add_theme_constant_override("separation", 10)
	add_child(lobby)
	endpoint = LineEdit.new()
	endpoint.text = str(ProjectSettings.get_setting("application/config/server_url", "ws://127.0.0.1:8765"))
	endpoint.custom_minimum_size.x = 285
	lobby.add_child(endpoint)
	var create := Button.new()
	create.text = "방 만들기"
	create.pressed.connect(func(): connect_room("create"))
	lobby.add_child(create)
	code = LineEdit.new()
	code.placeholder_text = "방 코드"
	code.max_length = 6
	code.custom_minimum_size.x = 130
	lobby.add_child(code)
	var join := Button.new()
	join.text = "참가"
	join.pressed.connect(func(): connect_room("join"))
	lobby.add_child(join)
	practice_button = Button.new()
	practice_button.text = "혼자 연습"
	practice_button.pressed.connect(start_practice)
	lobby.add_child(practice_button)
	next_button = Button.new()
	next_button.position = Vector2(50, 545)
	next_button.text = "다음 공수 →"
	next_button.visible = false
	next_button.pressed.connect(func():
		if practice: start_practice()
		else: send_packet({"type":"next"})
		next_button.hide())
	add_child(next_button)
	var back := Button.new()
	back.text = "처음으로"
	back.position = Vector2(970, 650)
	back.pressed.connect(func():
		socket.close()
		get_tree().reload_current_scene())
	add_child(back)
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

func connect_room(action: String) -> void:
	if phase != "lobby": return
	pending = action
	connected = false
	socket = WebSocketPeer.new()
	var err := socket.connect_to_url(endpoint.text.strip_edges())
	if err != OK:
		status.text = "서버 주소를 확인하세요"
		return
	phase = "connecting"
	origin = now()
	status.text = "서버 연결 중…"
	lobby.hide()

func send_packet(packet: Dictionary) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(packet))

func start_practice() -> void:
	practice = true
	lobby.hide()
	slot = 0
	attacker = 0
	speed = 1.0
	begin_record()
	status.text = "연습 / 공격 리듬 만들기"

func begin_record() -> void:
	phase = "record"
	notes.clear()
	hits.clear()
	resolved.clear()
	used = 0
	down = -1
	origin = -1
	next_button.hide()
	result.text = "SPACE로 리듬을 만드세요"
	hint.text = "첫 입력부터 녹음 · 8개를 채우면 자동 전송 · 최대 30초"

func receive(m: Dictionary) -> void:
	match m.get("type", ""):
		"joined":
			slot = int(m.slot)
			phase = "waiting"
			status.text = "방 코드: %s  /  나: P%d  /  상대 기다리는 중" % [m.code, slot+1]
		"turn":
			turn_index = int(m.turn)
			attacker = int(m.attacker)
			speed = float(m.speed)
			update_scores(m.scores)
			begin_record()
			status.text = "라운드 %d / 3 · %.2fx · 나: P%d · 공격: P%d" % [turn_index/2+1,speed,slot+1,attacker+1]
			if slot != attacker:
				phase = "waiting"
				result.text = "상대가 리듬을 만드는 중…"
				hint.text = "잠시 후 노트가 오른쪽에서 나타납니다"
		"pattern":
			notes = m.notes
			speed = float(m.speed)
			begin_play()
		"result":
			phase = "result"
			update_scores(m.scores)
			result.text = "수비 점수 +%d" % int(m.points)
			if m.finished:
				result.text = "무승부!" if m.scores[0] == m.scores[1] else "P%d 승리!" % (1 if m.scores[0]>m.scores[1] else 2)
				hint.text = "경기 종료 · 처음으로 버튼으로 새 경기를 시작하세요"
			else:
				next_button.visible = slot == 0
				hint.text = "방장이 다음 공수를 시작합니다"
		"error":
			status.text = str(m.message)
			if phase == "connecting":
				socket.close()
				connected = false
				phase = "lobby"
				lobby.show()
		"left":
			phase = "disconnected"
			result.text = "상대가 방을 나갔습니다"

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
			send_packet({"type":pending,"code":code.text.to_upper()})
		while socket.get_available_packet_count()>0:
			var packet = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if packet is Dictionary: receive(packet)
	elif phase == "connecting" and (state==WebSocketPeer.STATE_CLOSED or now()-origin>10):
		socket.close()
		phase = "lobby"
		status.text = "연결 실패 · 중계 서버 실행과 주소를 확인하세요"
		lobby.show()
	elif connected and state == WebSocketPeer.STATE_CLOSED:
		connected = false
		phase = "disconnected"
		status.text = "연결이 종료되었습니다 · 처음으로 버튼으로 재접속"
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
		for i in range(notes.size()):
			if not resolved.has(i) and t>float(notes[i].t)+float(notes[i].d)+0.18:
				resolved[i] = true
				show_judgment(999)
		var end := float(notes[-1].t)+float(notes[-1].d)+0.5
		if t>end:
			if down>=0:
				hits.append({"t":down,"d":maxf(0,t-down)})
				down = -1
			phase = "result"
			if practice:
				result.text = "연습 완료!"
				next_button.show()
			else: send_packet({"type":"result","hits":hits})
	flash = maxf(0,flash-delta*4)
	queue_redraw()

func _draw() -> void:
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
				draw_line(Vector2(maxf(x,65),y),Vector2(minf(tail,1090),y),Color(CYAN,0.45),16)
				draw_circle(Vector2(clampf(tail,65,1090),y),8,CYAN)
			if x>=65: draw_circle(Vector2(x,y),13,GOLD if float(n.d)>0 else CYAN)
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
	var color := GOLD if active or duration>=0.3 else CYAN
	if duration>0:
		draw_line(Vector2(clampf(x,65,1090),460),Vector2(clampf(tail,65,1090),460),Color(color,0.6),16)
		draw_circle(Vector2(clampf(tail,65,1090),460),8,color)
	if x>=65: draw_circle(Vector2(x,460),13,color)

func panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("0d172b")
	s.corner_radius_top_left = 16
	s.corner_radius_top_right = 16
	s.corner_radius_bottom_left = 16
	s.corner_radius_bottom_right = 16
	return s
