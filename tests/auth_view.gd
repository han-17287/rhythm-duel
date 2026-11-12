extends SceneTree
const Auth=preload("res://gameplay/auth_view.gd")
const BaseUI=preload("res://interface.gd")
class QuietSound extends RefCounted:
	func play(_name,_gain=1.0):pass
class TestGame extends Control:
	var phase:="lobby"
	var accounts_enabled:=true
	var connected:=true
	var auth_pending:=false
	var auth_started_at:=0.0
	var profile:Dictionary={}
	var status:=Label.new()
	var sounds:=QuietSound.new()
	var preferences=preload("res://gameplay/preferences.gd").new()
	var requests:Array=[]
	var reconnects:=0
	func _init():add_child(status)
	func account_action(action:String,name_value:="",password_value:=""):
		auth_pending=true;status.text="pending"
		requests.append({"action":action,"name":name_value,"password":password_value})
	func open_transport():reconnects+=1
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(Auth.validation_error("플레이어_1","password123","password123",true).is_empty())
	assert(not Auth.validation_error("name!","password123","password123",true).is_empty())
	assert(not Auth.validation_error("name","short","short",true).is_empty())
	assert(not Auth.validation_error("name","password123","different",true).is_empty())
	var g:=TestGame.new();root.add_child(g);var ui=BaseUI.new(g);ui.page="auth"
	var auth=Auth.new(g,ui);auth.build();auth.page.show();await process_frame;auth.sync()
	assert(auth.submit_button==ui.auth_login and auth.submit_button==ui.auth_register)
	auth.select_mode(Auth.REGISTER);assert(auth.confirmation.visible and not auth.login_hint.visible)
	ui.name_edit.text="새플레이어";ui.password_edit.text="password123";auth.confirmation.text="notthesame";auth.submit()
	assert(g.requests.is_empty() and not auth.local_message.is_empty())
	auth.confirmation.text="password123";auth.submit();auth.submit()
	assert(g.requests.size()==1 and g.requests[0].action=="register")
	assert(g.auth_pending and ui.password_edit.text.is_empty() and auth.confirmation.text.is_empty())
	assert(not g.preferences.values.has("password"))
	auth.sync();assert(auth.submit_button.disabled and not ui.name_edit.editable)
	g.auth_pending=false;g.status.text="이미 사용 중인 닉네임입니다.";auth.sync();assert(auth.feedback.text.contains("닉네임"))
	auth.select_mode(Auth.LOGIN);assert(not auth.confirmation.visible and auth.login_hint.visible)
	g.accounts_enabled=false;auth.sync();assert(auth.submit_button.disabled and ui.auth_notice.text.contains("게스트"))
	ui.password_edit.text="password123";auth.submit();assert(g.requests.size()==1)
	g.accounts_enabled=true;g.connected=false;auth.sync();assert(auth.retry_button.visible)
	auth.retry_connection();assert(g.reconnects==1)
	g.connected=true;g.profile={"name":"테스터","rating":1234,"coins":55,"wins":2,"losses":1,"draws":0};auth.sync()
	assert(auth.identity.text=="테스터" and auth.identity_stats.text.contains("1234") and ui.auth_notice.text.contains("2승"))
	ui.password_edit.text="forgotten secret";auth.confirmation.text="forgotten secret";auth.was_visible=true;ui.page="rooms";auth.sync()
	assert(ui.password_edit.text.is_empty() and auth.confirmation.text.is_empty())
	auth=null;ui=null;g.queue_free();await process_frame
	print("AUTH_VIEW_OK: explicit modes, validation, pending deduplication, no password persistence, unavailable/real profile states and page-exit cleanup")
	quit()
