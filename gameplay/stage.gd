extends RefCounted

static var glows: Dictionary = {}
var g: Control
var panels: Dictionary = {}
var rhythm_route:RefCounted
var ranker_stage:RefCounted

func _init(game: Control) -> void:
	g=game
	rhythm_route=preload("res://gameplay/rhythm_route.gd").new(game)
	ranker_stage=preload("res://gameplay/ranker_stage.gd").new(game)
	if glows.is_empty():
		for key in ["cyan","violet","coral"]:
			var color: Color={"cyan":Color("36d9d0"),"violet":Color("965dff"),"coral":Color("ff6f8b")}[key]
			var gradient:=Gradient.new()
			gradient.colors=PackedColorArray([Color(color,0.23),Color(color,0)])
			var texture:=GradientTexture2D.new()
			texture.gradient=gradient
			texture.width=256
			texture.height=256
			texture.fill=GradientTexture2D.FILL_RADIAL
			texture.fill_from=Vector2(.5,.5)
			texture.fill_to=Vector2(1,.5)
			glows[key]=texture

func active() -> bool:
	return g.phase in ["record","play","review","preview","waiting"] or (g.phase=="result" and not g.last_report.is_empty())

func draw_menu() -> void:
	var t: float=0 if g.preferences.values.reduced_motion else g.now()
	g.draw_rect(Rect2(0,0,1152,720),Color("090f1e"))
	g.draw_texture_rect(glows.violet,Rect2(420,-180,950,950),false)
	g.draw_texture_rect(glows.cyan,Rect2(-340,240,800,800),false)
	for i in range(22):
		var x:=float((i*157+83)%1152)
		var y:=float((i*113+100)%720)
		g.draw_circle(Vector2(x,y),1.2,Color("bb9ff5")*Color(1,1,1,.13+.08*sin(t*.6+i)))
	g.draw_line(Vector2(48,92),Vector2(1104,92),Color("26384f"),1)
	g.draw_line(Vector2(48,92),Vector2(166,92),Color("6fffe0"),3,true)
	if g.phase=="lobby" and g.interface:
		var tabs: Dictionary={"home":Vector2(269,329),"rooms":Vector2(367,427),"solo":Vector2(465,525),"arcade":Vector2(465,525),"library":Vector2(465,525),"ranker":Vector2(563,623),"shop":Vector2(661,721),"auth":Vector2(784,986),"settings":Vector2(1022,1050)}
		if tabs.has(g.interface.page):
			var span: Vector2=tabs[g.interface.page]
			g.draw_line(Vector2(span.x,78),Vector2(span.y,78),Color("6fffe0"),2,true)
	g.draw_line(Vector2(50,694),Vector2(1104,694),Color("26384f"),1)
	for i in range(5):
		var x: float=1023+i*17
		var height: float=6+absf(sin(t*1.8+i*.8))*13
		g.draw_line(Vector2(x,683),Vector2(x,683-height),Color("6fffe0")*Color(1,1,1,.45),5,true)

func panel(rect: Rect2, fill: Color, border: Color, radius := 18) -> void:
	var key:=str(rect.position)
	if not panels.has(key): panels[key]=StyleBoxFlat.new()
	var style: StyleBoxFlat=panels[key]
	style.bg_color=fill
	style.border_color=border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	g.draw_style_box(style,rect)

func draw() -> void:
	if not g.ranker_id.is_empty() and g.phase=="play":
		ranker_stage.draw(glows)
		return
	var moving: bool=not g.preferences.values.reduced_motion
	var t: float=g.now() if moving else 0.0
	if not g.ranker_id.is_empty() and g.phase=="play":t=maxf(0,g.play_time()+g.ranker_seek) if moving else 0.0
	var accent: Color=Color("ff86a5") if g.phase in ["record","review"] else Color("66ffe3")
	var glow_key: String="coral" if g.phase in ["record","review"] else "cyan"
	if not g.map_id.is_empty():
		var region: int=int(g.Maps.find(g.map_id).region)
		accent=[Color("66ffe3"),Color("ffd388"),Color("c3a3ff")][region]
		glow_key=["cyan","coral","violet"][region]
	if not g.ranker_id.is_empty():
		accent=Color(str(g.Ranker.find(g.ranker_id).color));glow_key="violet" if int(g.ranker_id.substr(1))>=3 else "cyan"
	g.draw_rect(Rect2(0,0,1152,720),Color("070e1c"))
	g.draw_texture_rect(glows.violet,Rect2(480+sin(t*.25)*30,-160,900,900),false)
	g.draw_texture_rect(glows[glow_key],Rect2(-220,100,800,800),false)
	g.draw_colored_polygon(PackedVector2Array([Vector2(110,-20),Vector2(650+sin(t*.3)*40,720),Vector2(180,720)]),Color(accent,.025))
	g.draw_colored_polygon(PackedVector2Array([Vector2(1040,-20),Vector2(470,720),Vector2(980,720)]),Color("aa8aff")*Color(1,1,1,.035))
	# A moving stage floor adds depth while keeping the timing gate perfectly stationary.
	for x in range(-700,1900,150):
		g.draw_line(Vector2(576+(x-576)*.1,505),Vector2(x,720),Color(.46,.36,.7,.14),1,true)
	for i in range(6):
		var y: float=505+fmod(t*20+i*42,215)
		g.draw_line(Vector2(0,y),Vector2(1152,y),Color(.46,.36,.7,.11),1,true)
	for i in range(18):
		var x:=float((i*173+61)%1152)
		var y: float=fmod(130+i*71-t*(4+i%3),570)+100
		g.draw_circle(Vector2(x,y),1.2,Color(accent,.1+.08*sin(t+i)))
	g.draw_line(Vector2(48,92),Vector2(1104,92),Color("4a3d69"),1)
	g.draw_line(Vector2(48,92),Vector2(210,92),accent,3,true)
	var captions: Dictionary={"record":"CREATE YOUR BEAT","review":"CHECK & SEND","preview":"LISTEN TO YOUR BEAT","play":"ECHO THE RHYTHM","waiting":"OPPONENT IS CREATING","result":"BATTLE REPORT"}
	var caption: String=captions.get(g.phase,"")
	if not g.ranker_id.is_empty():caption="RANKER / "+("DOUBLE" if g.ranker_kind=="double" else "ONE BEAT")
	if not g.map_id.is_empty():caption="MAP "+g.map_id.substr(1)+(" / PRACTICE" if g.map_training else " / RHYTHM JOURNEY")
	g.draw_circle(Vector2(430,47),3,Color(accent,.7+(.25*sin(t*4) if moving else 0)))
	g.draw_string(ThemeDB.fallback_font,Vector2(445,53),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("a99bbe"))
	var steps:=0
	var current:=0
	if not g.map_id.is_empty():
		var data: Dictionary=g.Maps.find(g.map_id)
		steps=4
		current=mini(3,int(maxf(0,g.play_time())/(float(data.bars)*60.0/float(data.bpm))))
	elif not g.practice:
		steps=int(g.room_settings.rounds)*2
		current=g.turn_index
	elif not g.solo_id.is_empty() and g.solo_id!="survival":
		steps=3
		current=g.solo_wave
	for i in range(steps):
		var pos:=Vector2(55+i*18,165)
		g.draw_circle(pos,3,Color(accent,.8 if i<current else .18))
		if i==current:
			g.draw_arc(pos,5,0,TAU,20,accent,1.5,true)
	if g.phase in ["record","play","preview","review"]:
		panel(Rect2(730,190,374,144),Color(.12,.12,.23,.78),Color("4f436f"))
		for i in range(9):
			var height: float=8+absf(sin(t*2.3+i*.8))*22+g.flash*13
			g.draw_line(Vector2(1059+i*4,314),Vector2(1059+i*4,314-height),Color(accent,.4),2,true)
		panel(Rect2(46,353,1060,170),Color(accent,.07),Color(accent,.4),21)
	if not g.ranker_id.is_empty() and g.phase=="play" and g.play_time()>=0:
		var bar:Dictionary=g.Ranker.section(g.ranker_id,g.play_time()+g.ranker_seek)
		var beat_phase:float=fposmod((g.play_time()+g.ranker_seek-float(bar.t))*float(bar.bpm)/60.0,1)
		var pulse:float=maxf(0,1-beat_phase*4) if moving else 0
		g.draw_rect(Rect2(48,95,1056,230),Color(accent,pulse*.035))
		preload("res://gameplay/ranker_cover.gd").paint(g,Vector2(570,254),70,int(g.ranker_id.substr(1))-1,Color(accent,.34),t,pulse)
	# Edge equalizers react to every hit instead of moving the target notes.
	for side in [0,1]:
		for i in range(5):
			var h: float=9+absf(sin(t*2.8+i*.9))*27+g.flash*35
			var x: float=10+i*5 if side==0 else 1118+i*5
			g.draw_line(Vector2(x,665),Vector2(x,665-h),Color(accent,.35),3,true)
	if g.phase=="play" and not g.paused:
		var until: float=-g.play_time()/(60.0/g.song_bpm() if g.is_song() else g.speed)
		if until>0:
			var fraction: float=until-floorf(until)
			var center:=Vector2(570,254)
			g.draw_circle(center,50,Color(accent,.05))
			g.draw_arc(center,49,0,TAU,64,Color(accent,.12),2,true)
			g.draw_arc(center,49,-PI/2,-PI/2+TAU*fraction,64,Color(accent,.75),3,true)
			for i in range(4):
				g.draw_circle(Vector2(540+i*20,321),3,Color(accent,.8 if i<ceili(until) else .15))
			g.draw_string(ThemeDB.fallback_font,center+Vector2(-15,17),str(ceili(until)),HORIZONTAL_ALIGNMENT_LEFT,-1,48,accent)
	if g.flash>0 and moving:
		g.draw_line(Vector2(48,93),Vector2(1104,93),Color(g.feedback_color,g.flash*.4),2,true)

func draw_progress() -> void:
	if not g.ranker_id.is_empty() and g.phase=="play":
		ranker_stage.draw_phrase_progress()
		rhythm_route.draw()
		return
	if not g.phase in ["record","play","preview","review"]: return
	var ratio:=0.0
	if g.phase in ["record","review"]:
		ratio=float(g.used)/8
		if g.key_held: ratio=minf(1,(g.used+maxf(1,g.now()-g.origin-g.down))/8)
	else:
		var end:=maxf(1,g.round_end())
		var time: float=g.play_time()
		ratio=clampf(time/end,0,1)
	g.draw_line(Vector2(50,529),Vector2(1102,529),Color("332b4c"),4,true)
	if ratio>0:g.draw_line(Vector2(50,529),Vector2(50+1052*ratio,529),Color("ff86a5") if g.phase in ["record","review"] else Color("66ffe3"),4,true)
	rhythm_route.draw()

func draw_rhythm_grid(top:=370.0,bottom:=505.0)->bool:
	return rhythm_route.grid(top,bottom)
