extends RefCounted

const MINT = Color("ff715c")
const INK = Color("29263d")
const PURPLE = Color("7961bc")
const MUTED = Color("706b7c")
var g: Control
var home: Control
var rooms: Control
var waiting: Control
var auth: Control
var shop: Control
var waiting_code: Label
var waiting_players: Label
var waiting_rules: Label
var start_button: Button
var reward_shop: Button
var role: Label
var budget: Label
var tips: Label
var key_hint: Label
var account_button: Button
var profile_summary: Label
var auth_notice: Label
var shop_balance: Label
var name_edit: LineEdit
var password_edit: LineEdit
var waiting_mode: OptionButton
var waiting_rounds: OptionButton
var waiting_speed: OptionButton
var mode_select: OptionButton
var rounds_select: OptionButton
var speed_select: OptionButton
var shop_buttons: Array = []
var room_code := ""
var page := "home"
var last_page := ""
var heartbeat := 0.0
var round_values := [1,2,3,4,5,6,7,8,9]
var speed_values := [0.5,0.75,1.0,1.25,1.5,1.75,2.0]
var mode_values := ["casual","rush","ranked"]

func _init(game: Control) -> void:
	g = game

func style(color: Color, border: Color, width := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(22)
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.shadow_color = Color(0.2,0.14,0.3,0.07)
	s.shadow_offset = Vector2(0,5)
	s.shadow_size = 12
	return s

func group() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(c)
	return c

func text(parent: Node, value: String, x: float, y: float, size: int, color := INK) -> Label:
	var l := Label.new()
	l.text = value
	l.position = Vector2(x,y)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",Color("bf4939") if color==MINT else color)
	parent.add_child(l)
	return l

func card(parent: Node, rect: Rect2, accent := Color("e4ded8")) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel",style(Color("fffdf9"),accent))
	parent.add_child(p)
	return p

func button(parent: Node, value: String, rect: Rect2, action: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = value
	b.position = rect.position
	b.size = rect.size
	b.pivot_offset = rect.size/2
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size",18)
	b.add_theme_color_override("font_color",INK if primary else INK)
	b.add_theme_color_override("font_hover_color",INK)
	b.add_theme_color_override("font_pressed_color",INK)
	b.add_theme_color_override("font_disabled_color",MUTED)
	b.add_theme_stylebox_override("normal",style(MINT if primary else Color("fffdf9"),MINT if primary else Color("ded6d0")))
	b.add_theme_stylebox_override("hover",style(Color("ffe4dc"),MINT))
	b.add_theme_stylebox_override("pressed",style(PURPLE,PURPLE))
	b.add_theme_stylebox_override("disabled",style(Color("ece7e1"),Color("ded6d0")))
	b.pressed.connect(action)
	b.mouse_entered.connect(func():
		if not b.disabled: b.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(b,"scale",Vector2(1.018,1.018),0.16))
	b.mouse_exited.connect(func(): b.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(b,"scale",Vector2.ONE,0.18))
	parent.add_child(b)
	return b

func edit(parent: Node, placeholder: String, rect: Rect2) -> LineEdit:
	var e := LineEdit.new()
	e.position = rect.position
	e.size = rect.size
	e.placeholder_text = placeholder
	e.add_theme_font_size_override("font_size",21)
	e.add_theme_color_override("font_color",INK)
	e.add_theme_color_override("font_placeholder_color",MUTED)
	e.add_theme_color_override("caret_color",INK)
	e.add_theme_color_override("selection_color",Color("d9c9f3"))
	e.add_theme_stylebox_override("normal",style(Color("f4f0ea"),Color("ded6d0")))
	e.add_theme_stylebox_override("focus",style(Color("fffdf9"),MINT,2))
	parent.add_child(e)
	return e

func selector(parent: Node, rect: Rect2, values: Array) -> OptionButton:
	var o := OptionButton.new()
	o.position = rect.position
	o.size = rect.size
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_size_override("font_size",17)
	o.add_theme_color_override("font_color",INK)
	o.add_theme_color_override("font_hover_color",INK)
	o.add_theme_color_override("font_pressed_color",INK)
	o.add_theme_color_override("font_disabled_color",MUTED)
	o.add_theme_constant_override("modulate_arrow",1)
	var popup := o.get_popup()
	popup.add_theme_color_override("font_color",INK)
	popup.add_theme_color_override("font_hover_color",INK)
	popup.add_theme_font_size_override("font_size",17)
	popup.add_theme_stylebox_override("panel",style(Color("fffdf9"),Color("ded6d0")))
	popup.add_theme_stylebox_override("hover",style(Color("f1e8fc"),Color("f1e8fc")))
	o.add_theme_stylebox_override("normal",style(Color("f4f0ea"),Color("ded6d0")))
	o.add_theme_stylebox_override("hover",style(Color("f1e8fc"),MINT))
	o.add_theme_stylebox_override("pressed",style(Color("e7dbf6"),PURPLE))
	o.add_theme_stylebox_override("disabled",style(Color("eee8e2"),Color("ded6d0")))
	for v in values: o.add_item(str(v))
	parent.add_child(o)
	return o

func build() -> void:
	g.title = text(g,"perfecto!",48,26,25,MINT)
	button(g,"대전",Rect2(520,24,100,44),func():
		if g.phase=="lobby": page="rooms")
	button(g,"스킨 상점",Rect2(635,24,160,44),func():
		if g.phase=="lobby": page="shop")
	account_button = button(g,"로그인 / 가입",Rect2(810,24,294,44),func():
		if g.phase=="lobby": page="auth")
	account_button.add_theme_font_size_override("font_size",16)
	g.status = text(g,"",50,124,17,MUTED)
	g.result = text(g,"",50,240,34)
	g.tally = text(g,"P1  00000    :    00000  P2",680,124,19,PURPLE)
	g.hint = text(g,"",50,580,17,MUTED)
	role = text(g,"",50,182,16,PURPLE)
	budget = text(g,"",50,321,15,MINT)
	key_hint = text(g,"SPACE",932,555,19,INK)
	tips = text(g,"SPACE  리듬 입력     ·     TAP  짧게 누르기     ·     HOLD  끝까지 유지",50,630,16,MUTED)
	button(g,"메인으로",Rect2(964,642,140,44),func():
		g.socket.close()
		g.get_tree().reload_current_scene())
	g.next_button = button(g,"다음 공수 시작  →",Rect2(50,455,280,64),func():
		if g.practice: g.start_practice()
		else: g.send_packet({"type":"next"})
		g.next_button.hide(),true)
	g.next_button.hide()
	reward_shop = button(g,"스킨 상점으로  →",Rect2(355,455,280,64),func(): g.open_menu("shop"))
	reward_shop.hide()

	home = group()
	text(home,"PLAY IT. FEEL IT. SEND IT.",50,143,15,PURPLE)
	text(home,"리듬을 던져.\n완벽하게 받아쳐.",46,184,54)
	text(home,"네 손끝에서 시작되는 리듬 배틀.\n8개의 비트를 만들고, 친구의 한 수를 받아쳐!",50,355,19,MUTED)
	button(home,"친구와 대전  →",Rect2(50,462,300,66),func(): page="rooms",true)
	g.practice_button = button(home,"가볍게 연습",Rect2(370,462,210,66),g.start_practice)
	profile_summary = text(home,"게스트로 바로 플레이할 수 있어요.",50,565,17,MUTED)
	var illustration := preload("res://art.gd").new()
	illustration.position = Vector2(658,133)
	illustration.size = Vector2(450,400)
	home.add_child(illustration)
	text(home,"YOUR BEAT. YOUR BATTLE.",713,541,16,PURPLE)
	var features := ["01   비트를 만들고","02   타이밍을 맞추고","03   나만의 스킨으로"]
	for i in range(3):
		var strip := card(home,Rect2(50+i*304,607,286,49))
		text(strip,str(features[i]),18,11,16,MUTED)

	rooms = group()
	text(rooms,"오늘은 어떤 한 판?",50,169,35)
	var a := card(rooms,Rect2(50,231,506,347))
	text(a,"새로운 방 만들기",24,20,25)
	mode_select = selector(a,Rect2(24,74,458,47),["일반전 · 자유로운 친구 대전","스피드전 · 더 빠른 라운드","랭크전 β · 레이팅 도전"])
	text(a,"라운드 수",24,139,14,MUTED)
	text(a,"시작 배속",260,139,14,MUTED)
	rounds_select = selector(a,Rect2(24,164,218,47),["1 라운드","2 라운드","3 라운드","4 라운드","5 라운드","6 라운드","7 라운드","8 라운드","9 라운드"])
	speed_select = selector(a,Rect2(260,164,222,47),["0.50x","0.75x","1.00x","1.25x","1.50x","1.75x","2.00x"])
	mode_select.item_selected.connect(func(_i): options_changed())
	rounds_select.item_selected.connect(func(_i): options_changed())
	speed_select.item_selected.connect(func(_i): options_changed())
	text(a,"랭크전은 3라운드 · 1.0x 고정 / 양쪽 로그인 필요",24,227,14,MUTED)
	button(a,"이 설정으로 방 만들기  →",Rect2(24,270,458,55),func(): g.connect_room("create"),true)
	var b := card(rooms,Rect2(578,231,526,347),Color("c8b6e6"))
	text(b,"친구의 방에 참가",24,20,25)
	text(b,"친구가 알려준 코드를 입력하세요.",24,78,17,MUTED)
	g.code = edit(b,"6자리 방 코드",Rect2(24,125,478,60))
	g.code.max_length = 6
	button(b,"코드로 참가  →",Rect2(24,206,478,55),func(): g.connect_room("join"))
	text(b,"일반전·스피드전은 게스트로도 즐길 수 있어요.",24,288,15,MUTED)
	button(rooms,"서버 설정",Rect2(50,599,150,43),func(): g.endpoint.visible = not g.endpoint.visible)
	g.endpoint = edit(rooms,"wss://서버주소",Rect2(216,599,690,46))
	g.endpoint.text = str(ProjectSettings.get_setting("application/config/server_url","wss://rhythm-duel.onrender.com"))
	if OS.has_feature("web"):
		g.endpoint.text = str(JavaScriptBridge.eval("window.location.origin")).replace("https://","wss://").replace("http://","ws://")
	g.endpoint.add_theme_font_size_override("font_size",17)
	g.endpoint.hide()
	g.lobby = HBoxContainer.new()
	g.add_child(g.lobby)
	g.lobby.hide()

	waiting = group()
	var w := card(waiting,Rect2(100,185,952,390),Color("c8b6e6"))
	text(w,"OUR PRIVATE ROOM",32,25,15,PURPLE)
	waiting_code = text(w,"연결 중…",32,66,54,MINT)
	button(w,"코드 복사",Rect2(708,82,208,50),func(): DisplayServer.clipboard_set(room_code))
	waiting_rules = text(w,"",32,161,19,PURPLE)
	waiting_mode = selector(w,Rect2(32,203,280,44),["일반전","스피드전","랭크전 β"])
	waiting_rounds = selector(w,Rect2(330,203,276,44),["1 라운드","2 라운드","3 라운드","4 라운드","5 라운드","6 라운드","7 라운드","8 라운드","9 라운드"])
	waiting_speed = selector(w,Rect2(624,203,288,44),["0.50x","0.75x","1.00x","1.25x","1.50x","1.75x","2.00x"])
	waiting_mode.item_selected.connect(func(_i): waiting_options_changed())
	waiting_rounds.item_selected.connect(func(_i): waiting_options_changed())
	waiting_speed.item_selected.connect(func(_i): waiting_options_changed())
	waiting_players = text(w,"친구를 기다리는 중…",32,257,16)
	start_button = button(w,"대전 시작  →",Rect2(32,292,880,60),func(): g.send_packet({"type":"start"}),true)

	auth = group()
	text(auth,"다시 만나서 반가워요.",50,175,35)
	var login_card := card(auth,Rect2(50,239,646,350))
	text(login_card,"닉네임",24,20,15,MUTED)
	name_edit = edit(login_card,"한글·영문·숫자 2~16자",Rect2(24,49,598,55))
	name_edit.max_length = 16
	text(login_card,"비밀번호",24,122,15,MUTED)
	password_edit = edit(login_card,"8자 이상",Rect2(24,151,598,55))
	password_edit.secret = true
	password_edit.max_length = 128
	button(login_card,"로그인",Rect2(24,238,284,60),func(): submit_auth("login"),true)
	button(login_card,"새 계정 만들기",Rect2(326,238,296,60),func(): submit_auth("register"))
	var p := card(auth,Rect2(720,239,384,350),Color("c8b6e6"))
	text(p,"YOUR PLAYER CARD",24,24,15,PURPLE)
	auth_notice = text(p,"게스트로도 친구 대전이 가능해요.",24,83,17,MUTED)
	button(p,"로그아웃",Rect2(24,262,336,55),func(): g.account_action("logout"))
	text(auth,"비밀번호 대신 로그인 토큰만 이 기기에 저장합니다. 공용 PC에서는 로그아웃하세요.",50,612,14,MUTED)

	shop = group()
	text(shop,"작은 변화, 새로운 리듬.",50,175,35)
	shop_balance = text(shop,"",50,231,18,PURPLE)
	for i in range(4):
		var item: Dictionary = g.catalog[i]
		var c := card(shop,Rect2(50+i*268,289,250,278),Color(str(item.color)))
		text(c,str(item.name),20,22,22)
		var swatch := preload("res://art.gd").new()
		swatch.mode = "skin"
		swatch.tint = Color(str(item.color))
		swatch.position = Vector2(18,75)
		swatch.size = Vector2(214,72)
		c.add_child(swatch)
		text(c,"기본 스킨" if int(item.price)==0 else "%d 코인" % int(item.price),22,151,18,MUTED)
		var skin_id: String = str(item.id)
		var buy := button(c,"",Rect2(18,204,214,52),func(): skin_action(skin_id))
		shop_buttons.append(buy)
	text(shop,"승리 +60 · 패배 +15 · 무승부 +25 코인 / 양쪽이 로그인한 경기에서 지급",50,605,15,MUTED)
	update_options()
	sync()

func submit_auth(action: String) -> void:
	g.account_action(action,name_edit.text,password_edit.text)
	password_edit.clear()

func skin_action(id: String) -> void:
	if g.profile.is_empty():
		page="auth"
		return
	g.queue_request({"type":"equip" if id in g.profile.get("owned",[]) else "buy","skin":id})

func options_changed() -> void:
	var mode: String = mode_values[mode_select.selected]
	g.configure_room({"mode":mode,"rounds":3 if mode=="ranked" else round_values[rounds_select.selected],"speed":1.0 if mode=="ranked" else speed_values[speed_select.selected]})
	update_options()

func waiting_options_changed() -> void:
	var mode: String = mode_values[waiting_mode.selected]
	g.configure_room({"mode":mode,"rounds":3 if mode=="ranked" else round_values[waiting_rounds.selected],"speed":1.0 if mode=="ranked" else speed_values[waiting_speed.selected]})
	update_options()

func update_options() -> void:
	mode_select.select(maxi(0,mode_values.find(g.room_settings.mode)))
	rounds_select.select(maxi(0,round_values.find(int(g.room_settings.rounds))))
	speed_select.select(maxi(0,speed_values.find(float(g.room_settings.speed))))
	waiting_mode.select(maxi(0,mode_values.find(g.room_settings.mode)))
	waiting_rounds.select(maxi(0,round_values.find(int(g.room_settings.rounds))))
	waiting_speed.select(maxi(0,speed_values.find(float(g.room_settings.speed))))
	rounds_select.disabled = g.room_settings.mode=="ranked"
	speed_select.disabled = g.room_settings.mode=="ranked"

func reveal(node: Control, visible_now: bool) -> void:
	if node.visible == visible_now: return
	node.visible = visible_now
	if visible_now:
		node.modulate.a = 0
		node.position.y = 10
		var t := node.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(node,"modulate:a",1.0,0.24)
		t.tween_property(node,"position:y",0.0,0.24)

func sync(delta := 0.0) -> void:
	heartbeat += delta
	var menu: bool = g.phase=="lobby"
	reward_shop.visible = g.phase=="result" and g.match_finished
	var in_game: bool = g.phase in ["record","play","waiting"]
	reveal(home,menu and page=="home")
	reveal(rooms,menu and page=="rooms")
	reveal(auth,menu and page=="auth")
	reveal(shop,menu and page=="shop")
	reveal(waiting,g.phase in ["connecting","room"])
	waiting_code.text = room_code if g.phase=="room" else "연결 중…"
	waiting_rules.text = "%s  ·  %d 라운드  ·  시작 %.2fx" % [["일반전","스피드전","랭크전 β"][maxi(0,mode_values.find(g.room_settings.mode))],int(g.room_settings.rounds),float(g.room_settings.speed)]
	waiting_players.text = "  vs  ".join(g.room_players) if g.room_players.size()==2 else "친구에게 방 코드를 보내주세요."
	waiting_mode.disabled = g.slot!=0 or g.phase!="room"
	waiting_rounds.disabled = waiting_mode.disabled or g.room_settings.mode=="ranked"
	waiting_speed.disabled = waiting_rounds.disabled
	start_button.disabled = g.phase!="room" or g.slot!=0 or g.room_players.size()!=2
	start_button.text = "대전 시작  →" if g.slot==0 else "방장이 시작하기를 기다리는 중…"
	g.status.visible = not home.visible
	g.result.visible = in_game or g.phase in ["result","timeout","disconnected"]
	g.tally.visible = not menu and not waiting.visible
	g.hint.visible = g.result.visible
	role.visible = in_game
	budget.visible = g.phase=="record"
	tips.visible = in_game
	key_hint.visible = g.phase in ["record","play"]
	if g.phase=="record":
		role.text = "01 / CREATE   ·   너의 리듬을 만들어봐"
		budget.text = "NOTE BUDGET   %d / 8     ·     롱 노트는 1초당 1개" % g.used
	elif g.phase=="play":
		role.text = "02 / ECHO   ·   수비" if g.practice or g.slot!=g.attacker else "02 / WATCH   ·   상대의 수비"
	else: role.text = "상대의 리듬을 기다리는 중…"
	g.result.position.y = 250 if in_game else 270
	g.hint.position.y = 580 if in_game else 360
	if g.profile.is_empty():
		account_button.text = "로그인 / 가입"
		profile_summary.text = "게스트로 바로 시작 · 로그인하면 보상과 전적 저장"
		auth_notice.text = "가입하면 레이팅과 스킨을\n계정에 모아둘 수 있어요." if g.accounts_enabled else "계정 저장소 준비 중이에요.\n지금은 게스트 대전을 즐겨요."
		shop_balance.text = "로그인하고 대전 보상으로 스킨을 모아보세요."
	else:
		account_button.text = "%s  ·  %d 코인" % [str(g.profile.name).left(8)+( "…" if str(g.profile.name).length()>8 else ""),int(g.profile.coins)]
		profile_summary.text = "%s   ·   %d RP   ·   %d승 %d패 %d무" % [g.profile.name,int(g.profile.rating),int(g.profile.wins),int(g.profile.losses),int(g.profile.draws)]
		auth_notice.text = "%s\n\n%d RP  ·  %d 코인\n\n%d승  %d패  %d무" % [g.profile.name,int(g.profile.rating),int(g.profile.coins),int(g.profile.wins),int(g.profile.losses),int(g.profile.draws)]
		shop_balance.text = "내 지갑   %d 코인   ·   구매한 스킨은 바로 장착돼요." % int(g.profile.coins)
	for i in range(shop_buttons.size()):
		var item: Dictionary = g.catalog[i]
		var b: Button = shop_buttons[i]
		var equipped: bool = g.profile.get("skin","mint")==item.id
		var owned: bool = item.id in g.profile.get("owned",["mint"])
		b.text = "사용 중" if equipped else "로그인 필요" if g.profile.is_empty() else "장착하기" if owned else "%d 코인 · 구매" % int(item.price)
		b.disabled = equipped
