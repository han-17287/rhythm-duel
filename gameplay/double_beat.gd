extends RefCounted
# Independent key and hold state: a held upper note never blocks the lower lane.
var game_ref: WeakRef
var g: Control:
	get:return game_ref.get_ref()
var held := [false,false]
var starts := [-1.0,-1.0]
var holds := [-1,-1]
var ends := [-0.08,-0.08]
var pad_styles:Array=[]
const COLORS=[Color("68ffe0"),Color("ba9aff")]
func _init(game: Control) -> void:
	game_ref=weakref(game)
	for i in range(2):
		var style:=StyleBoxFlat.new();style.set_corner_radius_all(12);style.set_border_width_all(2);pad_styles.append(style)
func reset() -> void:
	held=[false,false];starts=[-1.0,-1.0];holds=[-1,-1];ends=[-0.08,-0.08]
func input(event: InputEventKey,delay := 0.0) -> void:
	var lane:=0 if event.keycode==KEY_F else 1 if event.keycode==KEY_J else -1
	if lane<0:return
	press(lane,event.pressed,delay)
func pointer(lane:int,pressed:bool)->void:
	if held[lane]==pressed:return
	press(lane,pressed,g.web_pointer_delay(pressed))

func press(lane: int, pressed: bool,delay := 0.0) -> void:
	var event_now:float=g.now()-delay
	if g.paused or lane not in [0,1]:return
	if g.phase=="record" and g.slot==g.attacker:
		if pressed and not held[lane]:
			var reserved:=int(held[1-lane])
			if g.used+reserved>=8:return
			if g.origin<0:g.origin=event_now
			var t:float=event_now-g.origin
			if t<ends[lane]+.08:return
			held[lane]=true;starts[lane]=t
			g.flash=1;g.feedback_color=COLORS[lane];g.sounds.note(lane*3)
		elif not pressed and held[lane]:finish(lane,event_now)
	elif g.phase=="play" and (g.practice or g.slot!=g.attacker):
		var t:float=g.input_time()-delay*g.speed
		if pressed and not held[lane] and t>=-.180001:
			held[lane]=true;starts[lane]=t
			g.active_hold=-1
			g.judge_tap(t,lane)
			holds[lane]=g.active_hold;g.active_hold=-1
			g.flash=1;g.feedback_color=COLORS[lane];g.sounds.note(lane*3)
		elif not pressed and held[lane]:release(lane,t)
func finish(lane: int,at := -1.0) -> void:
	var duration:float=maxf(0,(g.now() if at<0 else at)-g.origin-starts[lane])
	if duration<.3:duration=0
	duration=minf(duration,8-g.used-int(held[1-lane]))
	g.notes.append({"t":starts[lane],"d":duration,"lane":lane})
	g.notes.sort_custom(func(a,b):return float(a.t)<float(b.t))
	g.used+=maxi(1,ceili(duration));ends[lane]=starts[lane]+duration;held[lane]=false
	g.result.text="%d / 8"%g.used
	if g.used>=8:
		g.phase="review";g.stage_deadline=INF if g.practice else minf(g.now()+90,g.turn_started_client+150)
		g.result.text="더블 비트 완성!";g.hint.text="F 위 / J 아래 · P 미리듣기 · R 다시 만들기 · ENTER 전송"
		if not g.practice:g.send_packet({"type":"draft","notes":g.notes})
	elif not g.practice:g.send_packet({"type":"activity","units":g.used})
func release(lane: int,at := INF) -> void:
	var duration:float=maxf(0,(g.input_time() if is_inf(at) else at)-starts[lane])
	g.hits.append({"t":starts[lane],"d":duration,"lane":lane})
	if holds[lane]>=0:
		g.active_hold=holds[lane];g.judge_hold(starts[lane],duration);g.active_hold=-1
	held[lane]=false;holds[lane]=-1
func release_all() -> void:
	for lane in range(2):
		if held[lane]:
			if g.phase=="record":finish(lane)
			elif g.phase=="play":release(lane)
func update() -> void:
	if g.phase=="record":
		for lane in range(2):
			if held[lane] and g.now()-g.origin-starts[lane]>=8-g.used-int(held[1-lane]):finish(lane)
func draw_note(t: float,d: float,lane: int,clock: float,review: bool,active: bool=false) -> void:
	var y:=406.0+lane*76
	var unit:float=900.0/maxf(g.pattern_end(),1) if review else g.scroll_pixels()
	var x:float=100+t*unit if review else (1050.0 if g.phase=="record" else 180.0)+(t-clock)*unit
	var tail:float=x+d*unit
	if tail<65 or x>1090:return
	var color:Color=COLORS[lane]
	if d>0:
		g.draw_line(Vector2(clampf(x,65,1090),y),Vector2(clampf(tail,65,1090),y),Color(color,.22),24,true)
		g.draw_line(Vector2(clampf(x,65,1090),y),Vector2(clampf(tail,65,1090),y),Color(color,.85 if active else .6),12,true)
		g.draw_circle(Vector2(clampf(tail,65,1090),y),6,color)
	if x>=65:g.draw_note(Vector2(x,y),color)
func draw() -> void:
	g.draw_style_box(g.panel_style(),Rect2(48,355,1056,165))
	var target:=1050.0 if g.phase in ["record","review"] else 180.0
	var clock:float=maxf(0,g.now()-g.origin) if g.phase=="record" else g.play_time()
	for lane in range(2):
		var y:=406.0+lane*76
		g.draw_line(Vector2(65,y),Vector2(1085,y),Color(COLORS[lane],.3),2)
		g.draw_line(Vector2(target,y-29),Vector2(target,y+29),COLORS[lane],3,true)
		g.draw_circle(Vector2(target,y),23,Color(COLORS[lane],.22 if held[lane] else .07))
		g.draw_string(g.theme.default_font,Vector2(76,y-19),"F / UPPER" if lane==0 else "J / LOWER",HORIZONTAL_ALIGNMENT_LEFT,-1,11,COLORS[lane])
		if g.phase=="record" and held[lane]:draw_note(starts[lane],minf(clock-starts[lane],8-g.used-int(held[1-lane])),lane,clock,false,true)
		if g.phase=="record" or (g.phase=="play" and (g.practice or g.slot!=g.attacker)):
			var rect:=Rect2(870+lane*122,541,110,82)
			var style:StyleBoxFlat=pad_styles[lane];style.bg_color=Color(COLORS[lane],.24 if held[lane] else .08);style.border_color=Color(COLORS[lane],.8)
			g.draw_style_box(style,rect)
			g.draw_string(g.theme.default_font,rect.position+Vector2(43,50),"F" if lane==0 else "J",HORIZONTAL_ALIGNMENT_LEFT,-1,25,COLORS[lane])
	for i in range(g.notes.size()):
		if g.phase in ["play","preview"] and g.resolved.has(i):continue
		var n:Dictionary=g.notes[i]
		draw_note(float(n.t),float(n.d),int(n.get("lane",0)),clock,g.phase=="review",holds.has(i))
