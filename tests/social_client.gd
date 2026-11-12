extends SceneTree
func _initialize()->void:call_deferred("run")
func room(code:String,mode:String)->Dictionary:
	return {"code":code,"title":"실제 공개방 "+code,"host":"게스트-TEST","count":1,"settings":{"mode":mode,"rounds":3,"speed":1.0},"requires_login":mode=="ranked"}
func run()->void:
	var g=load("res://main.tscn").instantiate();root.add_child(g);await process_frame
	g.endpoint.text="ws://127.0.0.1:1";g.open_menu("rooms");g.interface.sync()
	var social=g.interface.social_view
	assert(social.page.visible and social.groups.size()==3 and social.tabs.size()==3)
	g.public_room_filter="all";g.receive({"type":"room_list","mode":"all","rooms":[room("ABCD12","casual"),room("DOUBLE","double"),room("RANKED","ranked")]})
	social.select_tab(1);social.last_refresh=g.now();social.refresh_due=false;social.sync()
	assert(social.row_codes[0]=="ABCD12" and social.rows[0].visible)
	social.filter.select(3);social.signature="";social.sync()
	assert(social.row_codes[0]=="DOUBLE" and not social.rows[1].visible)
	# Cancelled queued and matched messages may never resurrect a search/room.
	social.select_tab(0);g.start_matchmaking("casual")
	assert(g.match_active and g.outgoing.any(func(p):return p.type=="match_join"))
	g.receive({"type":"match_status","queued":true,"mode":"casual","waiting":2,"position":1,"elapsed":4.0})
	assert(g.match_waiting==2 and g.now()-g.match_started_at>=4)
	g.cancel_match();assert(not g.match_active and not g.outgoing.any(func(p):return p.type=="match_join"))
	g.receive({"type":"match_status","queued":true,"mode":"casual","waiting":1,"position":1});assert(not g.match_active)
	g.receive({"type":"joined","auto":true,"code":"CANCEL","slot":0,"settings":{"mode":"casual","rounds":3,"speed":1.0}});assert(g.phase=="lobby")
	g.receive({"type":"room","auto":true,"settings":{"mode":"casual","rounds":3,"speed":1.0},"players":["A","B"]});assert(g.phase=="lobby")
	g.start_matchmaking("double")
	g.receive({"type":"joined","auto":true,"public":false,"title":"빠른 더블","code":"MATCH1","slot":0,"settings":{"mode":"double","rounds":3,"speed":1.0}})
	g.receive({"type":"room","auto":true,"public":false,"title":"빠른 더블","settings":{"mode":"double","rounds":3,"speed":1.0},"players":["A","B"]})
	g.receive({"type":"match_found","mode":"double","opponent":"B","starts_in":3.0});g.interface.sync()
	assert(g.room_auto and g.phase=="room" and g.match_start_at>g.now())
	assert(g.interface.start_button.disabled and g.interface.waiting_mode.disabled and g.interface.waiting_speed.disabled)
	g.receive({"type":"turn","turn":0,"attacker":0,"scores":[0,0],"speed":1.0,"settings":{"mode":"double","rounds":3,"speed":1.0}})
	assert(g.phase=="record" and not g.match_active)
	g.open_menu("rooms");g.start_matchmaking("casual");g.interface.page="home";social.sync();assert(not g.match_active)
	g.open_menu("rooms");g.start_matchmaking("casual")
	for nav in g.get_tree().get_nodes_in_group("perfecto_menu_nav"):
		if nav.get_meta("route","")=="auth":nav.pressed.emit();break
	assert(not g.match_active and g.interface.page=="auth" and g.status.text.is_empty())
	g.receive({"type":"joined","auto":true,"code":"LATE99","slot":0,"settings":{"mode":"casual","rounds":3,"speed":1.0}})
	assert(g.phase=="lobby","A late match must not override immediate header navigation")
	g.account_action("login","TestName","password123");assert(g.auth_pending)
	g.receive({"type":"error","action":"login","message":"테스트 오류"});assert(not g.auth_pending)
	g.account_action("login","TestName","password123");g.receive({"type":"profile","profile":{}});assert(not g.auth_pending)
	g.socket.close();g.connected=false;g.connection_started=-1
	g.interface.page="auth";g.account_action("login","TimeoutName","password123")
	g.socket.close();g.connected=false;g.connection_started=-1;g.auth_started_at=g.now()-13
	assert(g.outgoing.any(func(p):return p.type=="login"))
	g._process(0);assert(not g.auth_pending and not g.outgoing.any(func(p):return p.type in ["login","register","resume","logout"]))
	g.open_menu("home");social=null;g.queue_free();await process_frame
	print("SOCIAL_CLIENT_OK: public filtering, cancellation races, automatic countdown, normal turn, navigation cleanup, auth pending lifecycle")
	quit()
