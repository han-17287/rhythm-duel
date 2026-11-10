extends RefCounted

const MINT = Color("54f4d4")
const PURPLE = Color("a38aff")
const MUTED = Color("8b99b5")
var g: Control
var home: Control
var rooms: Control
var waiting: Control
var waiting_code: Label
var role: Label
var budget: Label
var tips: Label
var room_code := ""
var page := "home"

func _init(game: Control) -> void:
	g = game

func style(color: Color, border: Color, width := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(16)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s

func group() -> Control:
	var c := Control.new()
	g.add_child(c)
	return c

func text(parent: Node, value: String, x: float, y: float, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = value
	l.position = Vector2(x,y)
	l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",color)
	parent.add_child(l)
	return l

func card(parent: Node, rect: Rect2, accent := Color("263454")) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel",style(Color("111a30"),accent))
	parent.add_child(p)
	return p

func button(parent: Node, value: String, rect: Rect2, action: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = value
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size",20)
	b.add_theme_color_override("font_color",Color("091322") if primary else Color.WHITE)
	b.add_theme_color_override("font_hover_color",Color("091322"))
	b.add_theme_stylebox_override("normal",style(MINT if primary else Color("17233f"),MINT if primary else Color("354365")))
	b.add_theme_stylebox_override("hover",style(Color("b8fff1"),MINT,2))
	b.add_theme_stylebox_override("pressed",style(PURPLE,PURPLE,2))
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func edit(parent: Node, placeholder: String, rect: Rect2) -> LineEdit:
	var e := LineEdit.new()
	e.position = rect.position
	e.size = rect.size
	e.placeholder_text = placeholder
	e.add_theme_font_size_override("font_size",24)
	e.add_theme_stylebox_override("normal",style(Color("090f20"),Color("354365")))
	e.add_theme_stylebox_override("focus",style(Color("101b30"),MINT,2))
	parent.add_child(e)
	return e

func build() -> void:
	g.title = text(g,"P / PERFECTO",48,25,25,MINT)
	text(g,"RHYTHM BATTLE CLUB",810,33,14,MUTED)
	g.status = text(g,"",50,118,18,MUTED)
	g.result = text(g,"",50,230,38)
	g.tally = text(g,"P1  00000    :    00000  P2",650,114,21,PURPLE)
	g.hint = text(g,"",50,582,18,MUTED)
	role = text(g,"",50,176,16,MINT)
	budget = text(g,"",50,321,15,MINT)
	tips = text(g,"TAP  짧게 누르기         HOLD  끝까지 유지하기         SPACE  리듬 입력",50,632,17)
	button(g,"메인으로",Rect2(964,642,140,44),func():
		g.socket.close()
		g.get_tree().reload_current_scene())
	g.next_button = button(g,"다음 공수 시작  →",Rect2(50,455,280,64),func():
		if g.practice: g.start_practice()
		else: g.send_packet({"type":"next"})
		g.next_button.hide(),true)
	g.next_button.hide()
	home = group()
	text(home,"YOUR RHYTHM. YOUR RULES.",50,140,15,PURPLE)
	text(home,"리듬을 만들고,\n상대를 흔들어.",46,180,56)
	text(home,"네가 누른 순간이 공격이 된다.\n친구의 리듬을 따라 치고, 더 높은 점수에 도전해.",50,352,20,MUTED)
	button(home,"온라인 대전  →",Rect2(50,461,300,70),func():
		page = "rooms"
		g.status.text = "방을 만들거나 친구에게 받은 6자리 코드를 입력하세요",true)
	g.practice_button = button(home,"혼자 연습",Rect2(370,461,210,70),g.start_practice)
	text(home,"STORY  /  준비 중",50,564,16,MUTED)
	var feature := card(home,Rect2(665,166,438,390),Color("564687"))
	text(feature,"01 / CREATE",28,24,15,MINT)
	text(feature,"누르는 순간, 리듬이 된다",28,65,25)
	text(feature,"● ━━━  ●   ● ━━",28,140,31,PURPLE)
	text(feature,"02 / DEFEND",28,222,15,MINT)
	text(feature,"같은 타이밍으로 받아쳐!",28,259,25)
	text(feature,"8 NOTES     /     3 ROUNDS     /     1 WINNER",28,334,13,MUTED)

	rooms = group()
	text(rooms,"친구와 한 판",50,175,42)
	var a := card(rooms,Rect2(50,258,506,269))
	text(a,"01 / HOST",24,20,14,MINT)
	text(a,"새로운 방 만들기",24,54,28)
	text(a,"방을 만들고 코드를 친구에게 공유하세요.",24,108,17,MUTED)
	button(a,"방 만들기  →",Rect2(24,175,455,64),func(): g.connect_room("create"),true)
	var b := card(rooms,Rect2(578,258,526,269),Color("564687"))
	text(b,"02 / JOIN",24,20,14,PURPLE)
	text(b,"친구의 방에 참가",24,54,28)
	g.code = edit(b,"6자리 방 코드",Rect2(24,113,260,58))
	g.code.max_length = 6
	button(b,"참가  →",Rect2(302,113,198,58),func(): g.connect_room("join"))
	text(b,"영문과 숫자 6자리 · 같은 서버의 친구와 연결",24,201,16,MUTED)
	var settings := button(rooms,"서버 설정",Rect2(50,553,150,48),func(): g.endpoint.visible = not g.endpoint.visible)
	settings.add_theme_font_size_override("font_size",16)
	g.endpoint = edit(rooms,"wss://서버주소",Rect2(216,553,690,54))
	g.endpoint.text = str(ProjectSettings.get_setting("application/config/server_url","wss://rhythm-duel.onrender.com"))
	g.endpoint.add_theme_font_size_override("font_size",17)
	g.endpoint.hide()
	# Compatibility holder; screen visibility is managed by sync().
	g.lobby = HBoxContainer.new()
	g.add_child(g.lobby)
	g.lobby.hide()

	waiting = group()
	var w := card(waiting,Rect2(180,190,792,347),Color("564687"))
	text(w,"PRIVATE ROOM / 친구 초대",32,25,16,PURPLE)
	waiting_code = text(w,"연결 중…",32,75,62,MINT)
	button(w,"코드 복사",Rect2(561,99,190,55),func(): DisplayServer.clipboard_set(room_code))
	text(w,"P1  ●  방장         VS         P2  ○  친구 기다리는 중",32,204,22)
	text(w,"친구가 코드를 입력하면 자동으로 대전이 시작돼요.",32,270,18,MUTED)
	sync()

func sync() -> void:
	var menu: bool = g.phase == "lobby"
	var in_game: bool = g.phase in ["record","play"] or (g.phase=="waiting" and not room_code.is_empty() and g.turn_index>=0 and not g.status.text.contains("상대 기다리는 중"))
	home.visible = menu and page=="home"
	rooms.visible = menu and page=="rooms"
	waiting.visible = g.phase=="connecting" or (g.phase=="waiting" and g.status.text.contains("상대 기다리는 중"))
	waiting_code.text = room_code if not room_code.is_empty() else "연결 중…"
	g.status.visible = not home.visible
	g.result.visible = in_game or g.phase in ["result","timeout","disconnected"]
	g.tally.visible = not menu and not waiting.visible
	g.hint.visible = g.result.visible
	role.visible = in_game
	budget.visible = g.phase=="record"
	tips.visible = in_game
	if g.phase=="record":
		role.text = "01 / CREATE YOUR RHYTHM   ·   공격 리듬 제작"
		budget.text = "NOTE BUDGET   %d / 8     ·     롱 노트는 1초당 1개" % g.used
	elif g.phase=="play":
		role.text = "02 / ECHO THE RHYTHM   ·   수비" if g.practice or g.slot!=g.attacker else "02 / WATCH THE BATTLE   ·   상대의 수비"
	else:
		role.text = "상대의 리듬을 기다리는 중…"
	g.result.position.y = 250 if in_game else 270
	g.hint.position.y = 580 if in_game else 360
