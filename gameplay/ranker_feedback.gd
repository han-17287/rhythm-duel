extends Node2D
## Small feedback around a fixed judgment target. It never moves the notes,
## judges an input, or invents a beat that the music did not play.
const COLORS=[Color("68ffe0"),Color("b89aff")]
const MAX_EVENTS=32
var game_ref:WeakRef
var events:Array=[]
var phrase_life:=0.0
var phrase_quality:=3
var phrase_label:=""
var g:Control:
	get:return game_ref.get_ref() if game_ref else null

func _ready()->void:
	z_index=6

func setup(game:Control)->void:
	game_ref=weakref(game)
	reset()

func reset()->void:
	events.clear();phrase_life=0;phrase_quality=3;phrase_label=""
	queue_redraw()

func allowed()->bool:
	return g!=null and not g.ranker_id.is_empty() and g.phase=="play" and bool(g.preferences.values.effects) and not bool(g.preferences.values.reduced_motion)

func hit(lane:int,judgment:int,is_hold:=false)->void:
	if not allowed() or g.paused:return
	if lane not in [0,1]:return
	if events.size()>=MAX_EVENTS:events.pop_front()
	events.append({"lane":lane,"j":clampi(judgment,0,3),"hold":is_hold,"extra":false,"life":.22,"duration":.22})
	queue_redraw()

func stray(lane:int)->void:
	if lane not in [0,1] or not allowed() or g.paused:return
	hit(lane,3)
	if not events.is_empty():events[-1].extra=true

func phrase(quality:int,label:String)->void:
	if not allowed() or g.paused:return
	phrase_quality=clampi(quality,0,3);phrase_label=label.left(64)
	phrase_life=.55 if quality<3 else 0.0
	queue_redraw()

func _process(delta:float)->void:
	if not allowed():
		if not events.is_empty() or phrase_life>0:reset()
		return
	if g.paused:
		queue_redraw()
		return
	for index in range(events.size()-1,-1,-1):
		events[index].life-=delta
		if events[index].life<=0:events.remove_at(index)
	phrase_life=maxf(0,phrase_life-delta)
	queue_redraw()

func _draw()->void:
	if not allowed() or g.paused:return
	# Only the latest event per lane is painted. Rapid inputs cannot layer a
	# blinding stack of rings, while the small queue stays bounded for testing.
	var seen:=[false,false]
	for index in range(events.size()-1,-1,-1):
		var event:Dictionary=events[index]
		var lane:=int(event.lane)
		if seen[lane]:continue
		seen[lane]=true
		var progress:=1.0-float(event.life)/float(event.duration)
		var opacity:=pow(1.0-progress,1.5)
		var y:float=406+lane*76 if g.is_double() else 460
		var center:=Vector2(180,y)
		var color:Color=COLORS[lane]
		if int(event.j)>=3:
			color=Color("ff7898")
			# Failure sits to the left of the gate, keeping incoming notes clear.
			var x:=153.0
			draw_line(Vector2(x-4,y-5),Vector2(x+4,y+5),Color(color,opacity*.7),1.8,true)
			draw_line(Vector2(x+4,y-5),Vector2(x-4,y+5),Color(color,opacity*.7),1.8,true)
			continue
		if int(event.j)==1:color=Color("ffdb8a")
		elif int(event.j)==2:color=Color("b5c4dc")
		var radius:float=20+progress*(17 if int(event.j)==0 else 10)
		draw_arc(center,radius,-PI*.68,PI*.68,24,Color(color,opacity*.68),1.8,true)
		draw_arc(center,radius,PI*.78,PI*1.22,12,Color(color,opacity*.35),1.1,true)
		# The short streak travels behind the target, not into the approaching lane.
		draw_line(Vector2(172-progress*25,y),Vector2(172,y),Color(color,opacity*.7),2.2,true)
		if bool(event.hold):
			var edge:=center+Vector2(-8,0)
			draw_polyline(PackedVector2Array([edge+Vector2(0,-9),edge+Vector2(9,0),edge+Vector2(0,9),edge+Vector2(-9,0),edge+Vector2(0,-9)]),Color("ffe3a5",opacity*.7),1.5,true)
	if phrase_life>0:
		var color:Color=Color("ffe3a5") if phrase_quality==0 else COLORS[0]
		var alpha:=sin((phrase_life/.55)*PI)*.20
		draw_line(Vector2(52,355),Vector2(1100,355),Color(color,alpha),2,true)
		draw_line(Vector2(52,520),Vector2(1100,520),Color(color,alpha),2,true)
