extends RefCounted
const Design=preload("res://gameplay/ui_theme.gd")
const MODES=["casual","rush","double","ranked"]
const MODE_NAMES=["일반전","스피드전","더블 비트","랭크전 β"]
var game_ref:WeakRef
var ui_ref:WeakRef
var g:Control:
	get:return game_ref.get_ref()
var ui:RefCounted:
	get:return ui_ref.get_ref()
var page:Control
var groups:Array=[]
var tabs:Array=[]
var tab:=0
var was_visible:=false
var connection_label:Label
var quick_mode:OptionButton
var quick_title:Label
var quick_caption:Label
var quick_button:Button
var cancel_button:Button
var profile_label:Label
var filter:OptionButton
var refresh_button:Button
var room_count:Label
var room_message:Label
var rows:Array=[]
var row_titles:Array=[]
var row_details:Array=[]
var row_counts:Array=[]
var row_codes:Array=[]
var page_number:=0
var page_label:Label
var previous:Button
var next:Button
var visibility:OptionButton
var title_edit:LineEdit
var host_notice:Label
var create_button:Button
var refresh_due:=true
var last_refresh:=-10.0
var signature:=""
func _init(game:Control,base:RefCounted)->void:
	game_ref=weakref(game);ui_ref=weakref(base)
func section()->Control:
	var c:=Control.new();c.mouse_filter=Control.MOUSE_FILTER_IGNORE;page.add_child(c);groups.append(c);return c
func build()->void:
	page=ui.group();ui.rooms=page
	ui.text(page,"ONLINE / FIND YOUR RIVAL",50,123,12,Design.MINT).add_theme_font_override("font",Design.font("display"))
	ui.text(page,"DUEL STATION",48,149,38).add_theme_font_override("font",Design.font("display"))
	for i in range(3):
		var index:=i
		var b:Button=ui.button(page,["자동 매칭","공개방 찾기","친구 · 방 만들기"][i],Rect2(50+i*234,207,222,43),func():select_tab(index))
		b.add_theme_font_size_override("font_size",17);tabs.append(b)
	connection_label=ui.text(page,"",832,220,14,Design.MUTED)
	connection_label.size.x=272;connection_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var quick:=section()
	var q:Panel=ui.card(quick,Rect2(50,270,640,338),Color("4e8b8d"))
	ui.text(q,"QUICK MATCH",24,18,14,Design.MINT).add_theme_font_override("font",Design.font("display"))
	quick_mode=ui.selector(q,Rect2(24,57,592,46),["일반전 / ONE BEAT","스피드전 / 가속 대전","더블 비트 / F · J","랭크전 β / 레이팅"])
	quick_title=ui.text(q,"어떤 리듬이 기다릴까?",24,127,28)
	quick_caption=ui.text(q,"같은 모드를 선택한 실제 플레이어와 연결해요.\n3라운드 · 1.00x 시작 · 먼저 들어온 순서로 매칭",24,177,16,Design.MUTED)
	quick_button=ui.button(q,"상대 찾기  →",Rect2(24,258,592,55),start_match,true)
	cancel_button=ui.button(q,"검색 취소",Rect2(24,258,592,55),g.cancel_match)
	cancel_button.hide()
	var rules:Panel=ui.card(quick,Rect2(710,270,394,338),Color("635782"))
	ui.text(rules,"YOUR NEXT DUEL",24,20,19,Design.VIOLET).add_theme_font_override("font",Design.font("display"))
	ui.text(rules,"01  모드를 선택해 검색\n\n02  상대를 만나면 3초 준비\n\n03  리듬을 만들고, 받아쳐요",24,72,17,Design.WHITE)
	profile_label=ui.text(rules,"",24,256,14,Design.MUTED)
	ui.text(quick,"대기 중 다른 메뉴로 이동하면 검색이 취소됩니다. 검색 시간은 실제 대기 시간이에요.",50,638,14,Design.MUTED)
	var public_page:=section()
	filter=ui.selector(public_page,Rect2(50,266,250,42),["모든 모드","일반전","스피드전","더블 비트","랭크전 β"])
	filter.item_selected.connect(func(_i):page_number=0;refresh_due=true;signature="")
	room_count=ui.text(public_page,"",324,276,16,Design.MUTED)
	refresh_button=ui.button(public_page,"새로고침",Rect2(938,266,166,42),func():refresh_due=true)
	refresh_button.add_theme_font_size_override("font_size",15)
	for i in range(5):
		var index:=i
		var row:Button=ui.button(public_page,"",Rect2(50,320+i*56,1054,50),func():join_row(index))
		row_titles.append(ui.text(row,"",18,3,18,Design.WHITE))
		row_titles[-1].size.x=704;row_titles[-1].clip_text=true
		row_details.append(ui.text(row,"",18,28,12,Design.MUTED))
		row_counts.append(ui.text(row,"",864,13,16,Design.MINT))
		ui.text(row,"참가 →",948,13,16,Design.MINT)
		rows.append(row);row_codes.append("")
	room_message=ui.text(public_page,"",50,609,15,Design.MUTED)
	ui.button(public_page,"공개방 만들기  +",Rect2(50,642,260,44),func():visibility.select(1);select_tab(2))
	page_label=ui.text(public_page,"",604,654,14,Design.MUTED)
	previous=ui.button(public_page,"이전",Rect2(712,642,82,44),func():page_number=maxi(0,page_number-1);signature="")
	next=ui.button(public_page,"다음",Rect2(808,642,82,44),func():page_number+=1;signature="")
	var friends:=section()
	var host:Panel=ui.card(friends,Rect2(50,270,506,342))
	ui.text(host,"방 만들기",24,14,25)
	visibility=ui.selector(host,Rect2(24,59,218,40),["비공개 / 코드 초대","공개 / 목록에 표시"])
	title_edit=ui.edit(host,"방 제목 (최대 32자)",Rect2(260,59,222,40));title_edit.max_length=32
	ui.mode_select=ui.selector(host,Rect2(24,111,458,40),["일반전","스피드전","랭크전 β","더블 비트"])
	ui.text(host,"라운드 수",24,163,13,Design.MUTED);ui.text(host,"시작 배속",260,163,13,Design.MUTED)
	ui.rounds_select=ui.selector(host,Rect2(24,186,218,40),["1 라운드","2 라운드","3 라운드","4 라운드","5 라운드","6 라운드","7 라운드","8 라운드","9 라운드"])
	ui.speed_select=ui.selector(host,Rect2(260,186,222,40),["0.50x","0.75x","1.00x","1.25x","1.50x","1.75x","2.00x"])
	for selector in [ui.mode_select,ui.rounds_select,ui.speed_select]:selector.item_selected.connect(func(_i):ui.options_changed())
	host_notice=ui.text(host,"",24,239,13,Design.MUTED)
	create_button=ui.button(host,"이 설정으로 방 만들기 →",Rect2(24,279,458,45),create_room,true)
	var join:Panel=ui.card(friends,Rect2(578,270,526,342),Color("635782"))
	ui.text(join,"친구 방 참가",24,14,25)
	ui.text(join,"친구가 알려준 6자리 코드를 입력하세요.",24,67,16,Design.MUTED)
	g.code=ui.edit(join,"ROOM CODE",Rect2(24,108,478,60));g.code.max_length=6;g.code.alignment=HORIZONTAL_ALIGNMENT_CENTER
	g.code.add_theme_font_override("font",Design.font("display"));g.code.add_theme_font_size_override("font_size",26)
	g.code.text_submitted.connect(func(_value):g.connect_room("join"))
	ui.button(join,"코드로 참가  →",Rect2(24,196,478,55),func():g.connect_room("join"))
	ui.text(join,"일반전·스피드전·더블은 게스트도 가능해요.",24,282,14,Design.MUTED)
	ui.button(friends,"서버 설정",Rect2(50,640,150,42),func():g.endpoint.visible=not g.endpoint.visible)
	g.endpoint=ui.edit(friends,"wss://서버주소",Rect2(216,640,690,42));g.endpoint.text=str(ProjectSettings.get_setting("application/config/server_url","wss://rhythm-duel.onrender.com"));g.endpoint.add_theme_font_size_override("font_size",16)
	if OS.has_feature("web"):g.endpoint.text=str(JavaScriptBridge.eval("window.location.origin")).replace("https://","wss://").replace("http://","ws://")
	g.endpoint.hide()
	g.lobby=HBoxContainer.new();g.add_child(g.lobby);g.lobby.hide()
func select_tab(index:int)->void:
	if index!=0 and g.match_active:g.cancel_match()
	tab=index;signature=""
	if tab==1:refresh_due=true
func selected_filter()->String:return "all" if filter.selected==0 else MODES[filter.selected-1]
func start_match()->void:
	var mode:String=MODES[quick_mode.selected]
	if mode=="ranked" and g.profile.is_empty():
		ui.page="auth";g.status.text="랭크전은 로그인이 필요해요.";g.open_transport();return
	g.start_matchmaking(mode)
func create_room()->void:
	if g.room_settings.mode=="ranked" and g.profile.is_empty():ui.page="auth";g.status.text="랭크전은 로그인이 필요해요.";return
	g.create_social_room(visibility.selected==1,title_edit.text)
func join_row(index:int)->void:
	if index<row_codes.size() and not str(row_codes[index]).is_empty():g.join_public_room(str(row_codes[index]))
func sync()->void:
	var visible_now:bool=g.phase=="lobby" and ui.page=="rooms"
	ui.reveal(page,visible_now)
	if not visible_now and g.phase=="lobby" and g.match_active:g.cancel_match()
	if visible_now and not was_visible:g.open_transport();refresh_due=true
	was_visible=visible_now
	if not visible_now:return
	for i in range(3):
		groups[i].visible=i==tab
		tabs[i].disabled=g.match_cancel_pending
		tabs[i].add_theme_stylebox_override("normal",ui.style(Color("254252") if i==tab else Design.PANEL,Design.MINT if i==tab else Design.LINE,2 if i==tab else 1))
	connection_label.text="● ONLINE" if g.connected else "서버에 연결하는 중…" if g.connection_started>=0 else "서버 연결 필요"
	connection_label.add_theme_color_override("font_color",Design.MINT if g.connected else Design.MUTED)
	quick_mode.disabled=g.match_active or g.match_cancel_pending
	quick_button.visible=not g.match_active;cancel_button.visible=g.match_active
	quick_button.disabled=g.match_cancel_pending
	quick_button.text="검색을 취소하는 중…" if g.match_cancel_pending else "로그인하고 랭크 매칭 →" if quick_mode.selected==3 and g.profile.is_empty() else "상대 찾기  →"
	quick_title.text="상대를 찾는 중… %02d:%02d"%[int(g.now()-g.match_started_at)/60,int(g.now()-g.match_started_at)%60] if g.match_active else "어떤 리듬이 기다릴까?"
	quick_caption.text="%s · 대기 %d명 · 내 순서 %d\n실제 플레이어가 들어오면 자동으로 연결돼요."%[MODE_NAMES[maxi(0,MODES.find(g.match_mode))],g.match_waiting,maxi(1,g.match_position)] if g.match_active else "같은 모드를 선택한 실제 플레이어와 연결해요.\n3라운드 · 1.00x 시작 · 먼저 들어온 순서로 매칭"
	profile_label.text="게스트 플레이 · 랭크전은 로그인 후" if g.profile.is_empty() else "%s\nRATING %d · %d COINS"%[str(g.profile.name),int(g.profile.rating),int(g.profile.coins)]
	host_notice.text="공개방은 목록에 표시돼요. 랭크전은 로그인 필요." if visibility.selected==1 else "비공개방은 코드를 아는 친구만 참가할 수 있어요."
	if tab!=1:return
	if g.public_room_loading and g.now()-g.public_room_requested_at>12:
		g.public_room_loading=false;g.public_room_error="목록을 불러오지 못했어요. 다시 새로고침해 주세요."
	if (refresh_due or g.now()-last_refresh>5) and not g.public_room_loading and g.now()-last_refresh>.7:
		refresh_due=false;last_refresh=g.now();g.browse_public_rooms(selected_filter())
	refresh_button.disabled=g.public_room_loading
	refresh_button.text="불러오는 중…" if g.public_room_loading else "새로고침"
	var key:String=str(g.public_rooms.hash())+str(g.public_room_loading)+g.public_room_error+str(filter.selected)+str(page_number)+str(g.profile.is_empty())
	if key==signature:return
	signature=key
	var available:Array=[]
	for item in g.public_rooms:
		if selected_filter()=="all" or str(item.settings.mode)==selected_filter():available.append(item)
	var pages:=maxi(1,ceili(available.size()/5.0));page_number=clampi(page_number,0,pages-1)
	room_count.text="참가 가능한 공개방 %d개"%available.size()
	page_label.text="%d / %d"%[page_number+1,pages];previous.disabled=page_number==0;next.disabled=page_number>=pages-1
	room_message.text=g.public_room_error if not g.public_room_error.is_empty() else "공개방을 불러오는 중…" if g.public_room_loading and available.is_empty() else "아직 열린 방이 없어요. 첫 공개방을 만들어봐요." if available.is_empty() else "방을 누르면 바로 참가해요. 꽉 찬 방과 진행 중인 방은 표시되지 않아요."
	for i in range(5):
		var index:=page_number*5+i;rows[i].visible=index<available.size();row_codes[i]=""
		if index>=available.size():continue
		var item:Dictionary=available[index];row_codes[i]=str(item.code)
		row_titles[i].text=str(item.title);row_counts[i].text="%d / 2"%int(item.count)
		var config:Dictionary=item.settings;var mode_index:=maxi(0,MODES.find(str(config.mode)))
		row_details[i].text="%s · %s · %d라운드 · %.2fx%s"%[str(item.host),MODE_NAMES[mode_index],int(config.rounds),float(config.speed)," · 로그인 필요" if item.get("requires_login",false) else ""]
		rows[i].disabled=bool(item.get("requires_login",false)) and g.profile.is_empty()
