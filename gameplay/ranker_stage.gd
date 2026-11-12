extends RefCounted
## Music-first performance display. Every moving beat cue follows the audio
## transport; the judgement target, notes and input geometry stay stationary.
const Design=preload("res://gameplay/ui_theme.gd")
const Ranker=preload("res://gameplay/ranker.gd")
const Route=preload("res://gameplay/rhythm_route.gd")
const COLORS=[Color("68ffe0"),Color("b89aff")]
var game_ref:WeakRef
var cards:Dictionary={}
var next_bar_key:=""
var next_tempo:Dictionary={}
var g:Control:
	get:return game_ref.get_ref()

func _init(game:Control)->void:
	game_ref=weakref(game)

func text(value:String,at:Vector2,size:int,color:Color=Design.WHITE,width:float=-1,align:=HORIZONTAL_ALIGNMENT_LEFT,kind:="display")->void:
	g.draw_string(Design.font(kind),at,value,align,width,size,color)

func panel(rect:Rect2,fill:Color,border:Color,radius:=14)->void:
	var key:=str(rect)
	if not cards.has(key):
		var card:=StyleBoxFlat.new();card.set_corner_radius_all(radius);card.set_border_width_all(1);cards[key]=card
	var style:StyleBoxFlat=cards[key]
	style.bg_color=fill;style.border_color=border
	g.draw_style_box(style,rect)

static func stamp(seconds:float)->String:
	var whole:=maxi(0,int(seconds))
	return "%d:%02d"%[whole/60,whole%60]

static func number(value:int)->String:
	var digits:=str(maxi(0,value));var groups:Array=[]
	while digits.length()>3:
		groups.push_front(digits.right(3));digits=digits.left(digits.length()-3)
	groups.push_front(digits)
	return ",".join(groups)

func phrase(song:Dictionary,time:float)->Dictionary:
	var phrases:Array=song.get("phrases",[])
	if phrases.is_empty():return {}
	return phrases[clampi(Route.lower_bound(phrases,time+.000001)-1,0,phrases.size()-1)]

func draw(glows:Dictionary)->void:
	var song:Dictionary=Ranker.find(g.ranker_id)
	if song.is_empty():return
	var time:float=g.play_time()
	var absolute:float=maxf(g.ranker_seek,time+g.ranker_seek)
	var bar_index:=Route.bar_index(song.bars,absolute)
	var bar:Dictionary=song.bars[bar_index]
	var boundary_key:="%s:%d"%[g.ranker_id,bar_index]
	if next_bar_key!=boundary_key:
		next_bar_key=boundary_key;next_tempo={}
		for index in range(bar_index+1,song.bars.size()):
			if int(song.bars[index].bpm)!=int(bar.bpm):next_tempo=song.bars[index];break
	var beat:=60.0/float(bar.bpm)
	var phase:=fposmod((absolute-float(bar.t))/beat,1.0)
	var motion:bool=not g.preferences.values.reduced_motion
	var pulse:=pow(1-phase,5) if motion and time>=0 else 0.0
	var accent:=Color(str(song.color))
	var duration:float=maxf(.001,(g.ranker_end if g.ranker_end>0 else float(song.duration))-g.ranker_seek)
	var progress:=clampf(time/duration,0,1)
	var dual:bool=g.ranker_kind=="double"
	var live:bool=g.live_possible>0
	var accuracy:float=clampf(100*g.live_points/maxf(1,g.live_possible),0,100)
	var performance_tint:Color=Design.MINT if accuracy>=95 else Color("ffd78d") if accuracy>=75 else Color("ff719b")
	var background:float=maxf(0,time) if motion else 0.0

	g.draw_rect(Rect2(0,0,1152,720),Color("070c17"))
	g.draw_texture_rect(glows.violet,Rect2(400,-280,1080,1080),false,Color(1,1,1,.52))
	g.draw_texture_rect(glows.cyan,Rect2(-350,40,1000,1000),false,Color(1,1,1,.36))
	# Architectural light bands reinforce the beat without pretending to be an
	# amplitude analyser or placing flashes over the actual note-reading area.
	for side in range(2):
		var edge:=48.0 if side==0 else 1104.0
		var sign_value:=1.0 if side==0 else -1.0
		for i in range(5):
			var x:=edge+sign_value*(i*9)
			var height:=13.0+float(i%3)*5+pulse*(12-i)
			g.draw_line(Vector2(x,688),Vector2(x,688-height),Color(accent,.12+pulse*.12),2,true)
	for i in range(7):
		var x:=100.0+i*160.0
		g.draw_line(Vector2(576+(x-576)*.14,524),Vector2(x,720),Color("45637b")*Color(1,1,1,.09),1,true)
	for i in range(4):
		var y:=530.0+fposmod(background*10+i*52,190)
		g.draw_line(Vector2(50,y),Vector2(1104,y),Color("53708c")*Color(1,1,1,.045),1,true)
	g.draw_line(Vector2(48,92),Vector2(1104,92),Color("2b3f56"),1,true)
	g.draw_line(Vector2(48,92),Vector2(214,92),accent,3,true)
	g.draw_circle(Vector2(430,47),3,Color(accent,.8))
	text("PRACTICE SESSION" if g.ranker_training else "RANKER / LIVE SESSION",Vector2(445,52),13,Design.MUTED)

	text(str(song.title),Vector2(50,136),27,Design.WHITE,730)
	var mode:="DOUBLE" if dual else "ONE BEAT"
	text("%s  /  %s  /  LV.%d  /  %d BPM"%[mode,g.ranker_difficulty.to_upper(),Ranker.level(g.ranker_id,g.ranker_kind,g.ranker_difficulty),int(bar.bpm)],Vector2(51,160),12,accent)
	if not g.ranker_loop:
		text("%.2fx PRACTICE"%g.speed if g.ranker_training else str(song.get("genre","PERFECTO ORIGINAL")),Vector2(850,137),12,Design.MUTED,254,HORIZONTAL_ALIGNMENT_RIGHT)
	text("%s / %s"%[stamp(maxf(0,time)),stamp(duration)],Vector2(870,115 if g.ranker_loop else 162),13,Design.WHITE,234,HORIZONTAL_ALIGNMENT_RIGHT)
	g.draw_line(Vector2(50,178),Vector2(1104,178),Color("23374d"),3,true)
	if progress>0:g.draw_line(Vector2(50,178),Vector2(50+1054*progress,178),accent,3,true)
	# Section boundaries are honest musical landmarks and include partial
	# practice ranges; no timeline is manufactured from frame count.
	for phrase_value in song.get("phrases",[]):
		var marker:float=(float(phrase_value.t)-g.ranker_seek)/duration
		if marker<=0 or marker>=1:continue
		g.draw_line(Vector2(50+1054*marker,175),Vector2(50+1054*marker,181),Color("71869c"),1,true)

	panel(Rect2(50,194,296,99),Color("0e1929"),Color("273b51"))
	panel(Rect2(360,194,392,99),Color("142437"),Color(accent,.30+pulse*.12))
	panel(Rect2(766,194,338,99),Color("0e1929"),Color("273b51"))
	text("LIVE SCORE",Vector2(70,216),11,Design.MUTED)
	text(number(roundi(g.live_points)),Vector2(70,257),33,Design.WHITE,256)
	text("%d / %d NOTES"%[g.live_judgments.size(),g.notes.size()],Vector2(70,280),11,Design.MUTED)
	text("COMBO",Vector2(370,213),10,accent,372,HORIZONTAL_ALIGNMENT_CENTER)
	text(str(g.combo),Vector2(371,270),55,Design.WHITE,370,HORIZONTAL_ALIGNMENT_CENTER)
	for side in range(2):
		for i in range(3):
			var x:=386+i*10 if side==0 else 716-i*10
			g.draw_line(Vector2(x,263),Vector2(x,263-10-i*5-pulse*6),Color(accent,.18+pulse*.2),3,true)
	text("ACCURACY",Vector2(786,216),11,Design.MUTED)
	text("%.1f%%"%accuracy if live else "--.-%",Vector2(786,257),33,performance_tint if live else Design.MUTED)
	var grade:=Ranker.grade(accuracy) if live else "--"
	panel(Rect2(1014,219,70,48),Color(performance_tint,.055),Color(performance_tint,.22),10)
	text(grade,Vector2(1015,253),27,performance_tint if live else Design.MUTED,68,HORIZONTAL_ALIGNMENT_CENTER)
	var previous=g.get("ranker_best_before")
	var best:Dictionary=previous if previous is Dictionary else g.preferences.records.get(Ranker.record_id(g.ranker_id,g.ranker_kind,g.ranker_difficulty),{})
	var target:="TARGET 75.0% CLEAR" if best.is_empty() else "BEST %.1f%%  /  CLEAR 75%%"%float(best.accuracy)
	text(target,Vector2(786,280),11,Design.MUTED)

	draw_judgment(time,accent)
	draw_timing()
	panel(Rect2(46,353,1060,170),Color(accent,.035),Color(accent,.36),18)
	if time<0:draw_countin(time,60.0/g.song_bpm(),accent)
	var current:=phrase(song,absolute)
	var cue:=str(current.get("technique","리듬을 듣고 · 치고 · 쉬기"))
	var cue_color:=Design.MUTED
	var phrases:Array=song.get("phrases",[])
	var next_index:=Route.lower_bound(phrases,absolute+.000001)
	if time>=0 and next_index<phrases.size() and float(phrases[next_index].t)-absolute<=beat*4:
		cue="다음 구간 · %s"%str(phrases[next_index].technique);cue_color=Design.VIOLET
	if time>=0 and not next_tempo.is_empty() and float(next_tempo.t)-absolute<=beat*4:
		cue="변속 예고 · %d → %d BPM · %.1f초"%[int(bar.bpm),int(next_tempo.bpm),maxf(0,float(next_tempo.t)-absolute)/g.speed]
		cue_color=Color("ffd78d")
	var prefix:="%d/%d박 · %s"%[clampi(int((absolute-float(bar.t))/beat)+1,1,int(bar.beats)),int(bar.beats),str(current.get("label",""))]
	if g.ranker_training and g.ranker_loop:prefix="반복 %d · 최고 %.1f%% · %s"%[g.ranker_loop_count,g.ranker_loop_best,str(current.get("label",""))]
	var notice=g.get("ranker_phrase_notice")
	var notice_until=g.get("ranker_phrase_notice_until")
	if notice is String and not notice.is_empty() and notice_until!=null and time<float(notice_until):
		prefix=notice
	text(prefix,Vector2(50,548),12,accent,792,HORIZONTAL_ALIGNMENT_LEFT,"body")
	text(cue,Vector2(50,567),11,cue_color,792,HORIZONTAL_ALIGNMENT_LEFT,"body")
	var instruction:="F 위 / J 아래 · 홀드는 꼬리까지" if dual else "SPACE / F / J · 한 줄 교차 입력 · 홀드는 꼬리까지"
	instruction+="  |  R 다시 시작 · ESC 일시정지" if g.ranker_training else "  |  쉼표에서는 쉬기 · 추가 입력 -600"
	text(instruction,Vector2(50,660),12,Design.MUTED,900,HORIZONTAL_ALIGNMENT_LEFT,"body")

func draw_judgment(time:float,accent:Color)->void:
	var value:="LISTEN TO THE RHYTHM"
	var color:=Design.MUTED
	if time<0:
		value="READY · 리듬을 들어봐";color=accent
	elif g.judgment_age<.8 and not str(g.last_judgment).is_empty():
		value=str(g.result.text) if str(g.result.text).begins_with("OFF BEAT") else str(g.last_judgment)
		var grade_index:int=g.NAMES.find(g.last_judgment)
		color=[Color("72ffe4"),Color("ffdc88"),Color("c4a6ff"),Color("ff719b")][clampi(grade_index,0,3)]
		color.a=clampf((.8-g.judgment_age)/.22,.25,1)
	elif g.key_held and g.active_hold>=0 or g.is_double() and (g.double_beat.holds[0]>=0 or g.double_beat.holds[1]>=0):
		value="HOLD · 끝까지 유지";color=Color("ffd78d")
	text(value,Vector2(50,330),25,color,530,HORIZONTAL_ALIGNMENT_LEFT,"body")
	if g.last_hit_offset!=null and g.judgment_age<.8:
		var offset:float=g.last_hit_offset
		var timing:="JUST" if absf(offset)<=8 else "EARLY %dms"%int(-offset) if offset<0 else "LATE %dms"%int(offset)
		text(timing,Vector2(422,329),12,Design.MUTED,165,HORIZONTAL_ALIGNMENT_RIGHT)

func draw_timing()->void:
	var center:=858.0
	var extent:=244.0
	var windows:Array=g.judge_windows()
	var scale:float=extent/float(windows[2])/1000.0
	var line_y:=326.0
	for index in [2,1,0]:
		var half:float=float(windows[index])*1000*scale
		g.draw_rect(Rect2(center-half,line_y-3,half*2,6),Color([Color("68ffe0"),Color("c9b48e"),Color("796d8b")][index],.22))
	g.draw_line(Vector2(center,316),Vector2(center,336),Color("d6ffff"),1.5,true)
	text("EARLY",Vector2(center-extent,310),9,Design.MUTED)
	text("TIMING",Vector2(center-40,310),9,Design.MUTED,80,HORIZONTAL_ALIGNMENT_CENTER)
	text("LATE",Vector2(center+extent-36,310),9,Design.MUTED)
	var count:int=g.hit_offsets.size()
	for index in range(maxi(0,count-20),count):
		var offset:float=g.hit_offsets[index]
		var x:float=center+clampf(offset*scale,-extent,extent)
		var latest:bool=index==count-1
		var shade:Color=Design.MINT if absf(offset)<=float(windows[0])*1000 else Color("ffda92") if absf(offset)<=float(windows[1])*1000 else Color("ff87a4")
		shade.a=1 if latest else .12+.35*float(index-maxi(0,count-20))/20
		g.draw_line(Vector2(x,line_y-(9 if latest else 5)),Vector2(x,line_y+(9 if latest else 5)),shade,2 if latest else 1,true)

func draw_countin(time:float,beat:float,accent:Color)->void:
	var beats:=maxf(0,-time/beat)
	var count:=ceili(beats)
	var fraction:=fposmod(beats,1.0)
	var center:=Vector2(556,243)
	panel(Rect2(360,194,392,99),Color("13273a"),Color(accent,.5))
	text(str(count),Vector2(370,270),55,accent,372,HORIZONTAL_ALIGNMENT_CENTER)
	text("GET READY",Vector2(370,213),10,Design.WHITE,372,HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(4):
		g.draw_circle(Vector2(center.x-30+i*20,283),2.5,Color(accent,.9 if i<count else .15))
	if not g.preferences.values.reduced_motion:
		g.draw_arc(center,39,-PI/2,-PI/2+TAU*fraction,40,Color(accent,.3),2,true)

func draw_phrase_progress()->void:
	var values=g.get("ranker_phrase_live")
	if not values is Array or values.is_empty():return
	var duration:float=maxf(.001,(g.ranker_end if g.ranker_end>0 else float(Ranker.find(g.ranker_id).duration))-g.ranker_seek)
	for row in values:
		var from_time:=maxf(float(row.t),g.ranker_seek)
		var to_time:=minf(float(row.end),g.ranker_seek+duration)
		if to_time<=from_time:continue
		var start:float=50+1052*(from_time-g.ranker_seek)/duration
		var end:float=50+1052*(to_time-g.ranker_seek)/duration
		var color:=Color("26374c")
		if bool(row.get("closed",false)) and bool(row.get("complete",false)) and int(row.get("notes",0))>0:
			var counts:Array=row.get("counts",[0,0,0,0])
			var extra:=int(row.get("extra",0))
			if int(counts[0])==int(row.get("notes",0)) and extra==0:color=Design.MINT
			elif int(counts[3])==0 and extra==0:color=Design.VIOLET
			elif 100*float(row.get("points",0))/maxf(1,float(row.get("maximum",0)))>=75:color=Color("ffd78d")
			else:color=Color("ff719b")
		elif g.play_time()+g.ranker_seek>=from_time:
			color=Color("668ba7")
		g.draw_line(Vector2(start+1,529),Vector2(maxf(start+1,end-2),529),color,4,true)
