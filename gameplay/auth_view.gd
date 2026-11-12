extends RefCounted
# Login and registration share the existing account protocol and session storage.
const Design=preload("res://gameplay/ui_theme.gd")
const LOGIN:="login"
const REGISTER:="register"
var game_ref:WeakRef
var ui_ref:WeakRef
var g:Control:
	get:return game_ref.get_ref()
var ui:RefCounted:
	get:return ui_ref.get_ref()
var page:Control
var mode:=LOGIN
var login_tab:Button
var register_tab:Button
var submit_button:Button
var show_button:Button
var retry_button:Button
var confirmation:LineEdit
var confirmation_label:Label
var heading:Label
var explanation:Label
var login_hint:Label
var feedback:Label
var identity:Label
var identity_stats:Label
var avatar:Control
var local_message:=""
var was_visible:=false
var waiting_response:=false
var submitted_status:=""

func _init(game:Control,base:RefCounted)->void:
	game_ref=weakref(game);ui_ref=weakref(base)

func build()->void:
	page=ui.group();ui.auth=page
	ui.text(page,"ACCOUNT / YOUR RHYTHM IDENTITY",50,123,12,Design.MINT).add_theme_font_override("font",Design.font("display"))
	heading=ui.text(page,"다시 만나서 반가워.",48,149,35)
	explanation=ui.text(page,"",50,203,14,Design.MUTED)
	var left:Panel=ui.card(page,Rect2(50,230,620,412))
	login_tab=ui.button(left,"로그인",Rect2(24,20,274,44),func():select_mode(LOGIN))
	register_tab=ui.button(left,"회원가입",Rect2(314,20,282,44),func():select_mode(REGISTER))
	ui.text(left,"닉네임",24,82,14,Design.MUTED)
	ui.name_edit=ui.edit(left,"한글·영문·숫자·밑줄 2~16자",Rect2(24,106,572,48));ui.name_edit.max_length=16
	ui.name_edit.add_theme_font_size_override("font_size",19)
	ui.text(left,"비밀번호",24,164,14,Design.MUTED)
	ui.password_edit=ui.edit(left,"8자 이상",Rect2(24,188,572,48));ui.password_edit.secret=true;ui.password_edit.max_length=128
	ui.password_edit.add_theme_font_size_override("font_size",19)
	show_button=ui.button(left,"비밀번호 보기",Rect2(458,157,138,31),toggle_password)
	show_button.add_theme_font_size_override("font_size",12)
	confirmation_label=ui.text(left,"비밀번호 확인",24,246,14,Design.MUTED)
	confirmation=ui.edit(left,"한 번 더 입력하세요",Rect2(24,270,572,48));confirmation.secret=true;confirmation.max_length=128
	confirmation.add_theme_font_size_override("font_size",19)
	login_hint=ui.text(left,"처음 왔다면 위의 회원가입을 선택해줘.\n비밀번호는 이 기기에 저장하지 않아.",24,266,15,Design.MUTED)
	submit_button=ui.button(left,"로그인 →",Rect2(24,338,572,52),submit,true)
	# Preserve the root interface's legacy references while using one explicit action.
	ui.auth_login=submit_button;ui.auth_register=submit_button
	for edit:LineEdit in [ui.name_edit,ui.password_edit,confirmation]:
		edit.text_submitted.connect(func(_value):submit())
	var right:Panel=ui.card(page,Rect2(696,230,408,412),Color("7662a5"))
	ui.text(right,"PLAYER IDENTITY",24,19,12,Design.VIOLET).add_theme_font_override("font",Design.font("display"))
	avatar=preload("res://gameplay/player_badge.gd").new();avatar.position=Vector2(140,44);avatar.size=Vector2(128,128);right.add_child(avatar)
	identity=ui.text(right,"",24,190,25);identity.size=Vector2(360,34);identity.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;identity.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	identity_stats=ui.text(right,"",24,233,15,Design.MINT);identity_stats.size=Vector2(360,25);identity_stats.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	ui.auth_notice=ui.text(right,"",24,271,15,Design.MUTED);ui.auth_notice.size=Vector2(360,64);ui.auth_notice.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;ui.auth_notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	retry_button=ui.button(right,"연결 다시 시도",Rect2(104,303,200,29),retry_connection);retry_button.add_theme_font_size_override("font_size",12)
	ui.auth_session=ui.button(right,"게스트로 계속 →",Rect2(24,338,360,52),session_action)
	feedback=ui.text(page,"",50,657,14,Design.MUTED);feedback.size=Vector2(895,45);feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	select_mode(LOGIN)

func select_mode(value:String)->void:
	if value not in [LOGIN,REGISTER] or g.auth_pending:return
	mode=value;local_message="";waiting_response=false;clear_secrets()
	confirmation.visible=mode==REGISTER;confirmation_label.visible=confirmation.visible
	login_hint.visible=mode==LOGIN
	heading.text="새로운 플레이어의 시작." if mode==REGISTER else "다시 만나서 반가워."
	explanation.text="닉네임 하나로 레이팅·보상·스킨을 이어가자." if mode==REGISTER else "네가 쌓은 기록과 수집한 스킨을 다시 만나봐."
	ui.name_edit.focus_next=ui.name_edit.get_path_to(ui.password_edit)
	ui.password_edit.focus_previous=ui.password_edit.get_path_to(ui.name_edit)
	ui.password_edit.focus_next=ui.password_edit.get_path_to(confirmation if mode==REGISTER else ui.name_edit)
	ui.name_edit.focus_previous=ui.name_edit.get_path_to(confirmation if mode==REGISTER else ui.password_edit)
	confirmation.focus_previous=confirmation.get_path_to(ui.password_edit);confirmation.focus_next=confirmation.get_path_to(ui.name_edit)
	refresh_tabs()

func refresh_tabs()->void:
	for tab:Button in [login_tab,register_tab]:
		var selected:bool=(tab==login_tab and mode==LOGIN) or (tab==register_tab and mode==REGISTER)
		tab.add_theme_stylebox_override("normal",ui.style(Color("203b45") if selected else Design.PANEL,Design.MINT if selected else Design.LINE,2 if selected else 1))
		tab.add_theme_color_override("font_color",Design.MINT if selected else Design.MUTED)

func toggle_password()->void:
	var secret:bool=not ui.password_edit.secret
	ui.password_edit.secret=secret;confirmation.secret=secret
	show_button.text="비밀번호 보기" if secret else "비밀번호 숨기기"

func clear_secrets()->void:
	ui.password_edit.clear();confirmation.clear();ui.password_edit.secret=true;confirmation.secret=true
	show_button.text="비밀번호 보기"

static func validation_error(name:String,password:String,repeated:String,registering:bool)->String:
	var pattern:=RegEx.new();pattern.compile("^[A-Za-z0-9_가-힣]{2,16}$")
	if pattern.search(name)==null:return "닉네임은 한글·영문·숫자·밑줄 2~16자로 입력해줘."
	if password.length()<8 or password.length()>128:return "비밀번호는 8~128자로 입력해줘."
	if registering and repeated!=password:return "비밀번호 확인이 같지 않아. 다시 입력해줘."
	return ""

func submit()->void:
	if ui.page!="auth" or g.phase!="lobby" or not page.visible or g.auth_pending:return
	if not g.connected:
		local_message="서버에 연결한 뒤 다시 시도해줘.";return
	if not g.accounts_enabled:
		local_message="계정 서비스를 준비 중이에요. 게스트로 대전할 수 있어요.";return
	var name:String=ui.name_edit.text.strip_edges()
	var password:String=ui.password_edit.text
	var problem:=validation_error(name,password,confirmation.text,mode==REGISTER)
	if not problem.is_empty():local_message=problem;return
	ui.name_edit.text=name;local_message="";waiting_response=true
	g.account_action(mode,name,password);submitted_status=g.status.text
	clear_secrets()

func retry_connection()->void:
	if g.auth_pending:return
	local_message="서버 연결을 다시 확인하고 있어요.";g.open_transport()

func session_action()->void:
	if g.auth_pending:return
	clear_secrets();local_message=""
	if g.profile.is_empty():ui.page="rooms"
	else:
		waiting_response=true;g.account_action("logout");submitted_status=g.status.text

func handle_input(event:InputEventKey)->bool:
	if ui.page!="auth" or g.phase!="lobby" or not page.visible or not event.pressed or event.echo:return false
	if event.keycode not in [KEY_ENTER,KEY_KP_ENTER]:return false
	var focus:Control=g.get_viewport().gui_get_focus_owner()
	if focus not in [ui.name_edit,ui.password_edit,confirmation]:return false
	submit();return true

func sync()->void:
	var visible_now:bool=g.phase=="lobby" and ui.page=="auth" and page.visible
	if was_visible and not visible_now:clear_secrets();local_message=""
	was_visible=visible_now
	var pending:bool=g.auth_pending
	login_tab.disabled=pending;register_tab.disabled=pending
	submit_button.disabled=pending or not g.connected or not g.accounts_enabled
	submit_button.text="계정 확인 중…" if pending else "계정 만들기 →" if mode==REGISTER else "로그인 →"
	ui.name_edit.editable=not pending;ui.password_edit.editable=not pending;confirmation.editable=not pending;show_button.disabled=pending
	ui.auth_session.disabled=pending;ui.auth_session.text="로그아웃" if not g.profile.is_empty() else "게스트로 계속 →"
	retry_button.visible=not g.connected and not pending
	avatar.motion_enabled=not bool(g.preferences.values.reduced_motion)
	identity.text=str(g.profile.get("name","게스트 플레이어"));identity.tooltip_text=identity.text
	identity_stats.text="%d RP  ·  %d COINS"%[int(g.profile.get("rating",1000)),int(g.profile.get("coins",0))] if not g.profile.is_empty() else "RATING  ·  REWARDS  ·  SKINS"
	if not g.connected:
		ui.auth_notice.text="서버에 연결하고 있어요." if pending else "서버 연결을 다시 확인해줘."
	elif not g.profile.is_empty():
		ui.auth_notice.text="%d승  ·  %d패  ·  %d무\n계정에 연결된 플레이어야."%[int(g.profile.get("wins",0)),int(g.profile.get("losses",0)),int(g.profile.get("draws",0))]
	elif not g.accounts_enabled:ui.auth_notice.text="계정 서비스를 준비 중이에요.\n게스트로 대전할 수 있어요."
	else:ui.auth_notice.text="가입하면 레이팅과 보상을\n같은 계정에 모아둘 수 있어요."
	if waiting_response and not pending:
		if g.status.text!=submitted_status:local_message=g.status.text
		waiting_response=false
	feedback.text="계정 서버에서 안전하게 확인하고 있어요…" if pending else local_message
	feedback.add_theme_color_override("font_color",Design.MINT if pending else Color("ffbd83") if not local_message.is_empty() else Design.MUTED)
