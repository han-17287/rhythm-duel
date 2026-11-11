extends RefCounted
const Design=preload("res://gameplay/ui_theme.gd")
var g: Control
var ui_ref: WeakRef
var ui: RefCounted:
	get:return ui_ref.get_ref()
var page: Control
var names: Array=[]
var tags: Array=[]
var avatars: Array=[]
var status_labels: Array=[]
var copy_button: Button
var copied_until:=0.0
var signature:=""
func _init(game: Control,base: RefCounted) -> void:g=game;ui_ref=weakref(base)
func build() -> void:
	page=ui.group()
	ui.text(page,"ONLINE / PRIVATE DUEL",50,123,12,Design.MINT).add_theme_font_override("font",Design.font("display"))
	ui.text(page,"대전 대기실",48,149,36)
	ui.text(page,"VS",552,153,32,Design.VIOLET).add_theme_font_override("font",Design.font("display"))
	for i in range(2):
		var p: Panel=ui.card(page,Rect2(50+i*774,232,280,340),Design.MINT if i==0 else Design.VIOLET)
		ui.text(p,"PLAYER 0%d"%(i+1),24,19,12,Design.MINT if i==0 else Design.VIOLET).add_theme_font_override("font",Design.font("display"))
		var avatar:=preload("res://gameplay/player_badge.gd").new();avatar.size=Vector2(126,126);avatar.position=Vector2(77,58);avatar.tint=Design.MINT if i==0 else Design.VIOLET;p.add_child(avatar);avatars.append(avatar)
		var name: Label=ui.text(p,"",18,203,23);name.clip_text=true;name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;name.size.x=244;name.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;names.append(name)
		var tag: Label=ui.text(p,"",18,246,13,Design.MUTED);tag.size.x=244;tag.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;tags.append(tag)
		var status: Label=ui.text(p,"",18,290,14,Design.MINT if i==0 else Design.VIOLET);status.size.x=244;status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;status_labels.append(status)
	var center: Panel=ui.card(page,Rect2(352,232,450,340),Color("60749a"))
	ui.text(center,"ROOM CODE",24,17,11,Design.MUTED).add_theme_font_override("font",Design.font("display"))
	ui.waiting_code=ui.text(center,"연결 중…",24,39,40,Design.MINT);ui.waiting_code.size.x=402;ui.waiting_code.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;ui.waiting_code.add_theme_font_override("font",Design.font("display"))
	copy_button=ui.button(center,"코드 복사",Rect2(140,100,170,38),g.copy_room_code);copy_button.add_theme_font_size_override("font_size",14)
	ui.waiting_rules=ui.text(center,"",24,150,14,Design.MUTED)
	ui.waiting_mode=ui.selector(center,Rect2(24,182,402,40),["일반전","스피드전","랭크전 β","더블 비트"])
	ui.waiting_rounds=ui.selector(center,Rect2(24,232,194,40),["1 라운드","2 라운드","3 라운드","4 라운드","5 라운드","6 라운드","7 라운드","8 라운드","9 라운드"])
	ui.waiting_speed=ui.selector(center,Rect2(232,232,194,40),["0.50x","0.75x","1.00x","1.25x","1.50x","1.75x","2.00x"])
	for selector in [ui.waiting_mode,ui.waiting_rounds,ui.waiting_speed]:selector.item_selected.connect(func(_i):ui.waiting_options_changed())
	ui.start_button=ui.button(center,"대전 시작 →",Rect2(24,286,402,42),func():g.send_packet({"type":"start"}),true)
	ui.start_button.add_theme_font_size_override("font_size",16)
	ui.waiting_players=ui.text(page,"",50,602,18,Design.MUTED);ui.waiting_players.size.x=1054;ui.waiting_players.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
func sync() -> void:
	if not page.visible:return
	copy_button.disabled=g.phase!="room" or ui.room_code.is_empty()
	copy_button.text="복사 완료" if g.now()<copied_until else "코드 복사"
	for i in range(2):
		var present: bool=i<g.room_players.size()
		avatars[i].occupied=present;avatars[i].motion_enabled=not g.preferences.values.reduced_motion
		names[i].text=g.player_name(i) if present else "친구를 기다리는 중"
		names[i].tooltip_text=names[i].text
		tags[i].text=("YOU / " if g.slot==i else "FRIEND / ")+("HOST" if i==0 else "CHALLENGER") if present else "방 코드를 공유해 초대해봐"
		status_labels[i].text="CONNECTED" if present else "WAITING"
