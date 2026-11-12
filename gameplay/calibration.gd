extends RefCounted
var game_ref:WeakRef
var ui_ref:WeakRef
var g:Control:
	get:return game_ref.get_ref()
var ui:RefCounted:
	get:return ui_ref.get_ref()
var page:Control
var player:AudioStreamPlayer
var music:Node
var status:Label
var detail:Label
var count:Label
var start_button:Button
var apply_button:Button
var pulse:ProgressBar
var samples:Array=[]
var used:Dictionary={}
var running:=false
var last_clock:=0.0
var proposed:=0
func _init(game:Control,base:RefCounted)->void:game_ref=weakref(game);ui_ref=weakref(base)
func build()->void:
	page=ui.group()
	ui.text(page,"TIMING LAB / HEAR · TAP · SYNC",50,123,12,ui.MINT).add_theme_font_override("font",ui.Design.font("display"))
	ui.text(page,"소리와 손끝을 맞춰봐.",48,162,36)
	ui.text(page,"120 BPM 클릭음을 듣고 누르세요. 화면보다 소리에 집중해요.\n처음 네 박자는 준비 · 그다음 16번 SPACE/F/J 또는 아래 영역을 터치하세요.",50,229,18,ui.MUTED)
	var panel:Panel=ui.card(page,Rect2(50,315,1054,232),Color("63879f"))
	status=ui.text(panel,"헤드폰을 쓰면 더 정확해요.",28,24,25,ui.MINT)
	count=ui.text(panel,"READY",28,74,48,ui.INK);count.add_theme_font_override("font",ui.Design.font("display"))
	detail=ui.text(panel,"현재 보정 %+.0fms"%float(g.preferences.values.offset_ms),28,161,16,ui.MUTED)
	pulse=ProgressBar.new();pulse.show_percentage=false;pulse.position=Vector2(560,90);pulse.max_value=16;pulse.size=Vector2(460,12)
	var bg:StyleBoxFlat=ui.style(Color("263750"),Color("263750"),0);var fill:StyleBoxFlat=ui.style(ui.MINT,ui.MINT,0);bg.content_margin_top=0;bg.content_margin_bottom=0;fill.content_margin_top=0;fill.content_margin_bottom=0
	pulse.add_theme_stylebox_override("background",bg);pulse.add_theme_stylebox_override("fill",fill);panel.add_child(pulse);pulse.size=Vector2(460,12)
	var touch:=Button.new();touch.size=Vector2(1054,232);touch.focus_mode=Control.FOCUS_NONE
	for state in ["normal","hover","pressed","focus"]:touch.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	touch.button_down.connect(func():
		if running:tap(clock()-g.web_pointer_delay(true)))
	panel.add_child(touch)
	start_button=ui.button(page,"보정 시작",Rect2(50,590,250,56),start,true)
	apply_button=ui.button(page,"결과 적용",Rect2(320,590,250,56),apply);apply_button.disabled=true
	ui.button(page,"수동 보정 설정",Rect2(590,590,244,56),func():stop();ui.page="settings")
	ui.button(page,"랭커 아레나",Rect2(854,590,250,56),func():stop();ui.page="ranker")
	ui.text(page,"블루투스·출력 장치를 바꾸면 다시 보정해 주세요. 곡·노트 속도는 바뀌지 않아요.",50,670,13,ui.MUTED)
	music=preload("res://gameplay/story_music.gd").new();g.add_child(music);music.prepare("calibration",1);player=music.player
func start()->void:
	if g.web_input!=null:g.web_input.clearPointers()
	samples.clear();used.clear();last_clock=0;music.prepare("calibration",1);running=true;proposed=0;apply_button.disabled=true
	music.volume(float(g.preferences.values.volume),.82);music.start(0)
	status.text="처음 네 박자는 듣기만 해요.";start_button.text="다시 시작"
func stop()->void:
	if music:music.stop()
	running=false
func clock()->float:
	return music.time()
func tap(time:float)->void:
	var beat:=roundi((time-2)/.5)
	if beat<0 or beat>=16 or used.has(beat):return
	var error:float=time-(2+beat*.5)
	if absf(error)>.2:return
	used[beat]=true;samples.append(error*1000)
	proposed=estimate(samples);apply_button.disabled=samples.size()<8
	detail.text="%d / 16 입력 · 평균 차이 %+.0fms · 제안 보정 %+.0fms"%[samples.size(),-proposed,proposed]
func handle_input(event:InputEventKey,delay:=0.0)->bool:
	if ui.page!="calibration" or not page.visible:return false
	if event.pressed and event.keycode==KEY_ESCAPE:stop();ui.page="ranker";return true
	if running and event.pressed and event.keycode in [KEY_SPACE,KEY_D,KEY_F,KEY_J,KEY_K]:tap(clock()-delay);return true
	return false
static func estimate(values:Array)->int:
	if values.is_empty():return 0
	var sorted:Array=values.duplicate();sorted.sort();var size:=sorted.size()
	var median:float=float(sorted[size/2]) if size%2 else (float(sorted[size/2-1])+float(sorted[size/2]))/2
	return clampi(-roundi(median),-150,150)
func apply()->void:
	if samples.size()<8:return
	g.preferences.values.offset_ms=proposed;g.preferences.save();g.apply_preferences();stop()
	status.text="보정 %+.0fms 적용 완료!"%proposed
	detail.text="이 기기에 저장했어요. 수동 설정에서도 조절할 수 있어요."
func sync()->void:
	ui.reveal(page,g.phase=="lobby" and ui.page=="calibration")
	if not page.visible:
		if running:stop()
		return
	if not running:return
	if not music.failure().is_empty():
		stop();count.text="RETRY";status.text="보정음을 불러오지 못했어요.";detail.text="연결을 확인하고 다시 시작해 주세요.";return
	var t:=clock()
	pulse.value=samples.size()
	if t<2:count.text="LISTEN %d"%maxi(1,ceili((2-t)/.5))
	else:
		count.text="TAP %02d / 16"%mini(16,int((t-2)/.5)+1)
		status.text="소리에 맞춰 일정하게 눌러요."
	if t>=10 or (not music.web_enabled and not player.playing):
		running=false;music.stop();count.text="%d / 16 TAPS"%samples.size()
		status.text="보정 결과를 적용해 볼까요?" if samples.size()>=8 else "8번 이상 입력해 주세요. 다시 시작할 수 있어요."
