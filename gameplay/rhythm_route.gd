extends RefCounted
## A second, deliberately quiet reading of the music: note spacing is time,
## and the moving cue uses the same audio clock as the actual judgment lane.
const Design=preload("res://gameplay/ui_theme.gd")
const COLORS=[Color("68ffe0"),Color("b89aff")]
const MAX_PREVIEW=16
var game_ref:WeakRef
var plate:StyleBoxFlat
var g:Control:
	get:return game_ref.get_ref()

func _init(game:Control)->void:
	game_ref=weakref(game)
	plate=StyleBoxFlat.new()
	plate.bg_color=Color("101c2d")
	plate.border_color=Color("30475e")
	plate.set_border_width_all(1)
	plate.set_corner_radius_all(12)

static func lower_bound(items:Array,time:float)->int:
	var low:=0
	var high:=items.size()
	while low<high:
		var middle:=(low+high)/2
		if float(items[middle].t)<time:low=middle+1
		else:high=middle
	return low

static func bar_index(bars:Array,time:float)->int:
	return clampi(lower_bound(bars,time+.000001)-1,0,maxi(0,bars.size()-1))

static func preview_indices(notes:Array,time:float,span:float)->Array:
	var first:=lower_bound(notes,time-.000001)
	var result:Array=[]
	for index in range(first,mini(notes.size(),first+MAX_PREVIEW)):
		if float(notes[index].t)>time+span:break
		result.append(index)
	return result

func grid(top:=370.0,bottom:=505.0)->bool:
	if g.ranker_id.is_empty() or g.phase!="play":return false
	var song:Dictionary=g.Ranker.find(g.ranker_id)
	var bars:Array=song.get("bars",[])
	if bars.is_empty():return false
	var time:float=g.play_time()+g.ranker_seek
	var first:=maxi(0,bar_index(bars,time)-1)
	var pixels:float=g.scroll_pixels()
	var horizon:float=time+(1090.0-180.0)/pixels
	# At most a handful of bars are on screen, even at the slowest scroll speed.
	for index in range(first,mini(bars.size(),first+12)):
		var bar:Dictionary=bars[index]
		if float(bar.t)>horizon:break
		var beat:=60.0/float(bar.bpm)
		for division in range(int(bar.beats)*2):
			var x:float=180.0+(float(bar.t)+division*.5*beat-time)*pixels
			if x<65 or x>1090:continue
			var downbeat:=division==0
			var whole:=division%2==0
			var color:=Color("8baac4")
			color.a=.28 if downbeat else .14 if whole else .055
			g.draw_line(Vector2(x,top),Vector2(x,bottom),color,1.5 if downbeat else 1.0,true)
			if downbeat:
				g.draw_string(Design.font("display"),Vector2(x+4,top+12),"%03d"%(index+1),HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("7d94ad"))
	return true

func draw()->void:
	if g.ranker_id.is_empty() or g.phase!="play" or g.paused or g.play_time()<0:return
	var song:Dictionary=g.Ranker.find(g.ranker_id)
	var bars:Array=song.get("bars",[])
	if bars.is_empty():return
	var time:float=g.play_time()
	var absolute:float=time+g.ranker_seek
	var bar:Dictionary=bars[bar_index(bars,absolute)]
	var beat:=60.0/float(bar.bpm)
	var phase:=fposmod((absolute-float(bar.t))/beat,1.0)
	var count:=clampi(int(floor((absolute-float(bar.t))/beat))+1,1,int(bar.beats))
	var motion:bool=not g.preferences.values.reduced_motion
	var pulse:=pow(1.0-phase,4) if motion else 0.0
	var dual:bool=g.ranker_kind=="double"
	var span:=beat*4.0
	var selected:=preview_indices(g.notes,time,span)
	var start:=242.0
	var finish:=824.0
	var unit:=(finish-start)/span
	g.draw_style_box(plate,Rect2(50,574,792,64))
	g.draw_string(Design.font("display"),Vector2(66,591),"RHYTHM ROUTE",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Design.WHITE)
	g.draw_string(Design.font("body"),Vector2(66,610),"듣고 · 치고 · 쉬기",HORIZONTAL_ALIGNMENT_LEFT,112,10,Design.MUTED)
	var next_gap:float=float(g.notes[selected[0]].t)-time if not selected.is_empty() else span
	var first:=lower_bound(g.notes,time)
	var held:=false
	for index in range(maxi(0,first-12),first):
		var note:Dictionary=g.notes[index]
		if float(note.d)>=.3 and float(note.t)+float(note.d)>time:held=true;break
	var resting:=not held and next_gap>beat*.75
	var state:="HOLD" if held else "REST" if resting else "F / J" if dual else "ONE BEAT"
	g.draw_circle(Vector2(69,623),2.5,Color("ffda92") if resting else COLORS[0])
	g.draw_string(Design.font("display"),Vector2(78,627),state,HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("ffda92") if resting else COLORS[0])
	# The orbit completes exactly one turn per musical beat. Reduced motion keeps
	# the beat count and essential note scroll but removes orbit and bloom.
	var center:=Vector2(207,607)
	g.draw_circle(center,22,Color(COLORS[0],.025+pulse*.035))
	g.draw_arc(center,20,-PI/2,TAU-PI/2,32,Color("31445a"),1.5,true)
	for step in range(int(bar.beats)):
		var angle:float=-PI/2+TAU*step/int(bar.beats)
		g.draw_circle(center+Vector2.from_angle(angle)*25,1.8,COLORS[0] if step<count else Color("42566d"))
	if motion:
		var angle:float=-PI/2+phase*TAU
		g.draw_arc(center,20,-PI/2,angle,32,Color(COLORS[0],.5),2.0,true)
		g.draw_circle(center+Vector2.from_angle(angle)*20,3,COLORS[0])
	g.draw_string(Design.font("display"),center+Vector2(-6,6),str(count),HORIZONTAL_ALIGNMENT_LEFT,-1,17,Design.WHITE)
	g.draw_string(Design.font("display"),Vector2(start,588),"NOW",HORIZONTAL_ALIGNMENT_LEFT,-1,9,Design.MINT)
	g.draw_string(Design.font("display"),Vector2(finish-88,588),"NEXT RHYTHM",HORIZONTAL_ALIGNMENT_LEFT,-1,9,Design.MUTED)
	var main_y:=613.0
	var current_bar:=bar_index(bars,absolute)
	for index in range(current_bar,mini(bars.size(),current_bar+5)):
		var next_bar:Dictionary=bars[index]
		if float(next_bar.t)>absolute+span:break
		var next_beat:=60.0/float(next_bar.bpm)
		for division in range(int(next_bar.beats)*2):
			var delta:float=float(next_bar.t)+division*.5*next_beat-absolute
			if delta<0 or delta>span:continue
			var x:float=start+delta*unit
			g.draw_line(Vector2(x,598),Vector2(x,630),Color("607a91")*Color(1,1,1,.28 if division==0 else .16 if division%2==0 else .055),1,true)
	g.draw_line(Vector2(start,main_y),Vector2(finish,main_y),Color("30465a"),1,true)
	g.draw_line(Vector2(start,598),Vector2(start,631),Color(COLORS[0],.5),2,true)
	var previous:=Vector2(start,main_y)
	for index in selected:
		var note:Dictionary=g.notes[index]
		var lane:=int(note.get("lane",0))
		var color:Color=COLORS[lane]
		var x:float=start+maxf(0,float(note.t)-time)*unit
		var y:float=604.0+lane*19.0 if dual else main_y+(-6.0 if index%2==0 else 6.0)
		var position:=Vector2(x,y)
		var turn:=Vector2(lerpf(previous.x,x,.5),previous.y)
		g.draw_polyline(PackedVector2Array([previous,turn,position]),Color(color,.32),1.5,true)
		if float(note.d)>=.3:
			var tail:=minf(finish,x+float(note.d)*unit)
			g.draw_line(position,Vector2(tail,y),Color(color,.65),3,true)
			var release:=Vector2(tail,y)
			g.draw_polyline(PackedVector2Array([release+Vector2(0,-4),release+Vector2(4,0),release+Vector2(0,4),release+Vector2(-4,0),release+Vector2(0,-4)]),Color("ffe0a1"),1.1,true)
		g.draw_circle(position,6,Color(color,.07))
		g.draw_circle(position,3.2,color)
		if index==selected[0]:g.draw_arc(position,5.8,0,TAU,12,Color(color,.5),1,true)
		previous=position
	# Continue through an actual gap rather than inserting decorative fake notes.
	if selected.is_empty():
		g.draw_string(Design.font("display"),Vector2(start+210,618),"BREATHE",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("ffda92"))
