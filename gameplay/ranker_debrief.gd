extends RefCounted
## A result is a route back into the music: inspect a phrase, then rehearse it.
const Design=preload("res://gameplay/ui_theme.gd")
const Ranker=preload("res://gameplay/ranker.gd")
const JUDGMENT_COLORS=[Color("68ffe0"),Color("ffda92"),Color("b89aff"),Color("ff719b")]
var game_ref:WeakRef
var ui_ref:WeakRef
var g:Control:
	get:return game_ref.get_ref()
var ui:RefCounted:
	get:return ui_ref.get_ref()
var page:Control
var heading:Label
var subtitle:Label
var outcome:Label
var grade:Label
var badge:Label
var accuracy:Label
var score:Label
var personal_best:Label
var combo:Label
var timing:Label
var timing_plot:Control
var count_labels:Array=[]
var phrase_buttons:Array=[]
var phrase_caption:Label
var phrase_detail:Label
var phrase_hint:Label
var footer:Label
var replay:Button
var train:Button
var weakest:Button
var rows:Array=[]
var selected:=-1
var signature:=""
var gloss:Control

class TimingPlot extends Control:
	var bins:Array=[]
	var limit:=100.0
	var perfect:=22.0
	var great:=50.0
	var valid_count:=0
	func _ready()->void:mouse_filter=Control.MOUSE_FILTER_IGNORE
	func prepare(offsets:Array,windows:Array)->void:
		limit=maxf(1,float(windows[2])*1000);perfect=float(windows[0])*1000;great=float(windows[1])*1000
		bins.clear();bins.resize(49);bins.fill(0);valid_count=0
		for offset in offsets:
			if offset==null:continue
			var value:float=float(offset)
			if not is_finite(value):continue
			var index:=clampi(roundi((clampf(value,-limit,limit)+limit)/(2*limit)*48),0,48)
			bins[index]+=1;valid_count+=1
		queue_redraw()
	func _draw()->void:
		var center:=size.x*.5
		for window in [limit,great,perfect]:
			var half:float=window/(2*limit)*size.x
			draw_rect(Rect2(center-half,0,half*2,size.y),Color("182d30") if window==perfect else Color("25273e") if window==great else Color("291e33"))
		draw_line(Vector2(center,0),Vector2(center,size.y),Color("88a8b5"),1,true)
		if bins.is_empty():return
		var peak:=maxi(1,int(bins.max()))
		var width:=size.x/bins.size()
		for i in range(bins.size()):
			if int(bins[i])==0:continue
			var offset:float=(float(i)/48*2-1)*limit
			var color:=Color("68ffe0") if absf(offset)<=perfect else Color("ffda92") if absf(offset)<=great else Color("b89aff")
			var height:=maxf(2,float(bins[i])/peak*(size.y-5))
			draw_rect(Rect2(i*width+1,size.y-height,maxf(1,width-2),height),color)

func _init(game:Control,base:RefCounted)->void:
	game_ref=weakref(game);ui_ref=weakref(base)

func display(parent:Node,value:String,x:float,y:float,font_size:int,color:=Design.WHITE)->Label:
	var label:Label=ui.text(parent,value,x,y,font_size,color)
	label.add_theme_font_override("font",Design.font("display"))
	return label

func clipped(label:Label,width:float,height:=24.0)->Label:
	label.size=Vector2(width,height);label.clip_text=true
	return label

func build()->void:
	page=ui.group();page.hide()
	heading=display(page,"PERFORMANCE / RESULT",50,113,29)
	subtitle=clipped(ui.text(page,"",50,153,13,Design.MUTED),770)
	outcome=display(page,"",827,122,23,Design.MINT);outcome.size=Vector2(277,35);outcome.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var medal:Panel=ui.card(page,Rect2(50,181,250,153),Design.MINT)
	gloss=preload("res://gameplay/result_gloss.gd").new();gloss.size=medal.size;medal.add_child(gloss)
	grade=display(medal,"S",20,3,80,Design.MINT);grade.size=Vector2(210,102);grade.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	badge=display(medal,"",12,106,15,Design.MINT);badge.size=Vector2(226,26);badge.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var totals:Panel=ui.card(page,Rect2(316,181,366,153),Color("3e6174"))
	accuracy=display(totals,"",20,10,43,Design.WHITE)
	score=display(totals,"",22,64,18,Design.MUTED)
	combo=display(totals,"",22,91,15,Design.VIOLET)
	personal_best=clipped(ui.text(totals,"",22,120,12,Design.MINT),322)
	var precision:Panel=ui.card(page,Rect2(698,181,406,153),Color("485778"))
	display(precision,"TIMING DISTRIBUTION",22,12,13,Design.VIOLET)
	timing_plot=TimingPlot.new();timing_plot.position=Vector2(22,43);timing_plot.size=Vector2(362,53);precision.add_child(timing_plot)
	display(precision,"EARLY",22,99,10,Design.MUTED)
	var right:=display(precision,"LATE",342,99,10,Design.MUTED);right.size.x=42;right.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	timing=clipped(ui.text(precision,"",22,121,12,Design.MUTED),362)
	for i in range(4):
		var card:Panel=ui.card(page,Rect2(50+i*267,347,253,58),Color(JUDGMENT_COLORS[i],.48))
		ui.text(card,g.NAMES[i],14,7,12,JUDGMENT_COLORS[i])
		var count:=display(card,"0",14,24,24,JUDGMENT_COLORS[i]);count_labels.append(count)
	var phrases:Panel=ui.card(page,Rect2(50,419,1054,128),Color("435c76"))
	display(phrases,"PHRASE REPORT",18,10,14,Design.MINT)
	phrase_hint=clipped(ui.text(phrases,"",260,10,12,Design.MUTED),772)
	phrase_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	for i in range(24):
		var index:=i
		var button:Button=ui.button(phrases,"",Rect2(18+i*42.5,40,39,29),func():choose(index))
		button.add_theme_font_size_override("font_size",11)
		for state in ["normal","hover","pressed","disabled","focus"]:
			var button_style:StyleBox=button.get_theme_stylebox(state).duplicate()
			button_style.content_margin_left=3;button_style.content_margin_right=3
			button_style.content_margin_top=3;button_style.content_margin_bottom=3
			button.add_theme_stylebox_override(state,button_style)
		phrase_buttons.append(button)
	phrase_caption=clipped(ui.text(phrases,"",18,80,14,Design.WHITE),1018)
	phrase_detail=clipped(ui.text(phrases,"",18,103,11,Design.MUTED),1018)
	replay=ui.button(page,"R  다시 도전",Rect2(50,566,230,52),func():g.replay_last())
	train=ui.button(page,"선택 구간 연습",Rect2(296,566,260,52),practice_selected,true)
	weakest=ui.button(page,"약한 구간 연습",Rect2(572,566,260,52),func():g.practice_weakest_phrase())
	ui.button(page,"곡 선택으로",Rect2(848,566,256,52),func():g.open_menu("ranker"))
	footer=clipped(ui.text(page,"",50,628,12,Design.MUTED),1054)
	ui.text(page,"← → 구간 선택 · P 선택 구간 연습 · R 다시 도전",50,660,12,Design.MUTED)

func choose(index:int)->void:
	if index<0 or index>=rows.size():return
	selected=index
	refresh_phrase()

func weakest_index()->int:
	var best:=-1
	for i in range(rows.size()):
		var row:Dictionary=rows[i]
		if int(row.get("notes",0))<=0:continue
		if best<0:best=i;continue
		var other:Dictionary=rows[best]
		var loss:float=float(row.accuracy)-float(other.accuracy)
		var mistakes:int=int(row.counts[3])+int(row.extra)
		var other_mistakes:int=int(other.counts[3])+int(other.extra)
		if loss<-.00001 or (absf(loss)<.00001 and (mistakes>other_mistakes or mistakes==other_mistakes and int(row.index)<int(other.index))):best=i
	return best

func tint(row:Dictionary)->Color:
	if int(row.get("notes",0))==0:return Design.MUTED
	var value:float=float(row.accuracy)
	return Design.MINT if value>=95 else Color("a9bbff") if value>=85 else Color("ffda92") if value>=75 else Color("ff719b")

func refresh_phrase()->void:
	for i in range(phrase_buttons.size()):
		var button:Button=phrase_buttons[i]
		button.visible=i<rows.size()
		if not button.visible:continue
		var row:Dictionary=rows[i]
		var accent:=tint(row)
		button.text="%02d"%(int(row.index)+1)
		button.tooltip_text="%s · %.1f%% · %d NOTES%s"%[str(row.label),float(row.accuracy),int(row.notes)," · 부분 연습" if not bool(row.get("complete",true)) else ""]
		for state in ["normal","hover","pressed","disabled","focus"]:
			var selected_style:StyleBoxFlat=ui.style(Color(accent,.22) if i==selected or state!="normal" else Color(accent,.08),accent if i==selected or state!="normal" else Color(accent,.4),2 if i==selected else 1)
			selected_style.content_margin_left=3;selected_style.content_margin_right=3
			selected_style.content_margin_top=3;selected_style.content_margin_bottom=3
			button.add_theme_stylebox_override(state,selected_style)
		button.size=Vector2(39,29)
		button.add_theme_color_override("font_color",accent)
	train.disabled=selected<0 or selected>=rows.size() or int(rows[selected].get("notes",0))==0
	weakest.disabled=weakest_index()<0
	weakest.text="약한 구간 연습" if weakest.disabled or float(rows[weakest_index()].accuracy)<99.95 else "프레이즈 다시 연습"
	if selected<0 or selected>=rows.size():
		phrase_caption.text="분석할 구간이 없어요."
		phrase_detail.text="전체 곡을 연주하고 구간별 흐름을 확인해 보세요."
		return
	var row:Dictionary=rows[selected]
	var status:="ALL PERFECT" if bool(row.get("all_perfect",false)) else "FULL COMBO" if bool(row.get("full_combo",false)) else "부분 연습" if not bool(row.get("complete",true)) else "다시 익혀보기" if float(row.accuracy)<75 else "KEEP THE FLOW"
	phrase_caption.text="%02d  %s  ·  %.1f%%  ·  %s"%[int(row.index)+1,str(row.label),float(row.accuracy),status]
	phrase_caption.add_theme_color_override("font_color",tint(row))
	phrase_detail.text="%s  ·  %d NOTES  ·  놓침 %d / 추가 입력 %d  ·  선택하면 이 구간을 0.75배로 반복 연습해요."%[str(row.technique),int(row.notes),int(row.counts[3]),int(row.extra)]

func practice_selected()->void:
	if selected<0 or selected>=rows.size() or int(rows[selected].get("notes",0))<=0:return
	g.practice_ranker_phrase(int(rows[selected].index))

func handle_input(event:InputEventKey)->bool:
	if not page.visible or not event.pressed or event.echo:return false
	if event.keycode in [KEY_LEFT,KEY_RIGHT] and not rows.is_empty():
		choose(posmod(selected+(-1 if event.keycode==KEY_LEFT else 1),rows.size()));return true
	if event.keycode==KEY_P:practice_selected();return true
	return false

func sync()->void:
	page.visible=g.phase=="result" and not g.ranker_id.is_empty() and not g.last_report.is_empty()
	if not page.visible:signature="";return
	var report:Dictionary=g.last_report
	var next_signature:="%s/%s/%s/%s/%s/%s"%[g.ranker_id,g.ranker_kind,g.ranker_difficulty,str(report.points),str(report.counts),str(g.ranker_phrase_report.hash())]
	if next_signature!=signature:
		signature=next_signature
		rows=g.ranker_phrase_report
		selected=weakest_index()
		if selected<0 and not rows.is_empty():selected=0
		var song:=Ranker.find(g.ranker_id)
		subtitle.text="%s · %s / %s · %s"%[str(song.title),str(g.ranker_difficulty).to_upper(),"DOUBLE" if g.ranker_kind=="double" else "ONE BEAT","%.2fx 연습"%g.speed if g.ranker_training else "정식 기록 도전"]
		outcome.text="PRACTICE COMPLETE" if g.ranker_training else "TRACK CLEARED" if float(report.accuracy)>=75 else "KEEP CHALLENGING"
		outcome.add_theme_color_override("font_color",Design.VIOLET if g.ranker_training else Design.MINT if float(report.accuracy)>=75 else Color("ffda92"))
		grade.text=str(report.grade)
		var accent:Color={"EX":Color("ffe39e"),"SS":Color("83faff"),"S":Color("68ffe0"),"A":Color("b89aff"),"B":Color("ffda92"),"F":Color("ff719b")}.get(str(report.grade),Design.MUTED)
		grade.add_theme_color_override("font_color",accent)
		badge.text="ALL PERFECT" if bool(report.all_perfect) else "FULL COMBO" if bool(report.full_combo) else "TRAIN / REFINE / REPEAT"
		badge.add_theme_color_override("font_color",accent)
		accuracy.text="%.1f%%"%float(report.accuracy)
		score.text="%s POINTS"%commas(int(report.points))
		combo.text="MAX %d COMBO · 추가 입력 %d"%[int(report.max_combo),int(report.extra)]
		var previous:Dictionary=g.ranker_best_before
		personal_best.text="연습 기록 · 정식 최고 기록에 반영하지 않아요." if g.ranker_training else "FIRST RECORD" if previous.is_empty() else "%s  %+.1f%% / %+d점"%["NEW BEST" if g.new_best else "PREVIOUS BEST 대비",float(report.accuracy)-float(previous.get("accuracy",0)),int(report.points)-int(previous.get("points",0))]
		timing_plot.prepare(report.offsets,Ranker.windows(g.ranker_difficulty))
		var sum:=0.0
		var count:=0
		for offset in report.offsets:
			if offset!=null and is_finite(float(offset)):sum+=float(offset);count+=1
		timing.text="유효 타이밍 입력 없음" if count==0 else "평균 %+.1fms · %.0fms PERFECT 판정"%[sum/count,float(Ranker.windows(g.ranker_difficulty)[0])*1000]
		for i in range(4):count_labels[i].text=commas(int(report.counts[i]))
		phrase_hint.text="실제로 연주한 %d개 구간 · 색이 붉을수록 다시 연습할 부분"%rows.size()
		replay.text="R  같은 구간 다시 연습" if g.ranker_training else "R  전체 곡 재도전"
		replay.add_theme_font_size_override("font_size",14)
		refresh_phrase()
		gloss.restart(not g.preferences.values.reduced_motion)
	footer.text="연습은 순위·코인·최고 기록에 반영되지 않아요." if g.ranker_training else g.reward_text if not str(g.reward_text).is_empty() else "정확도 75% 이상 클리어 · 기록은 이 기기에 저장돼요."
	if not g.ranker_training and not g.preferences.persist_ok:footer.text="저장이 차단되어 이 기록은 현재 창에서만 유지돼요."

static func commas(value:int)->String:
	var digits:=str(value)
	var result:=""
	for i in range(digits.length()):
		if i>0 and (digits.length()-i)%3==0:result+="," 
		result+=digits[i]
	return result
