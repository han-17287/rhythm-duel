extends RefCounted
const Maps=preload("res://gameplay/maps.gd")
var g: Control
var ui_ref: WeakRef
var ui: RefCounted:
	get:return ui_ref.get_ref()
var page: Control
var route: Control
var selected:="m01"
var signature:=""
var nodes: Array=[]
var headline: Label
var tag: Label
var title: Label
var description: Label
var facts: Label
var record: Label
var notice: Label
var preview: Control
var play_button: Button
var train_button: Button
var guide_button: Button
var speed_select: OptionButton
var speeds: Array=[.5,.75,1.0,1.25]
var guide:=true
var stage_caption: Label
var styles: Dictionary={}
func _init(game: Control,base: RefCounted) -> void:
	g=game
	ui_ref=weakref(base)
func build() -> void:
	page=ui.group()
	headline=ui.text(page,"리듬 연습 맵",50,154,34)
	ui.button(page,"아케이드 코스",Rect2(648,160,208,48),func():ui.page="arcade")
	ui.button(page,"내 비트 보관함",Rect2(876,160,228,48),g.open_library)
	ui.card(page,Rect2(50,232,650,368))
	route=preload("res://gameplay/map_route.gd").new()
	page.add_child(route)
	var regions: Array=["01 / MINT START","02 / HOLD VALLEY","03 / PRISM CITY"]
	var colors: Array=[Color("6fffe0"),Color("ffc784"),Color("c0a2ff")]
	for row in range(3):ui.text(page,regions[row],72,239+row*115,12,colors[row])
	var all:=Maps.catalog()
	for i in range(all.size()):
		var item: Dictionary=all[i]
		var pos: Vector2=route.point(i)
		var id: String=str(item.id)
		var b: Button=ui.button(page,"",Rect2(pos-Vector2(49,27),Vector2(98,54)),func():selected=id)
		b.add_theme_font_size_override("font_size",15)
		nodes.append(b)
		var name: Label=ui.text(page,str(item.name),pos.x-65,pos.y+33,13,colors[int(item.region)])
		name.size.x=130
		name.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var detail: Panel=ui.card(page,Rect2(734,232,370,410),Color("8c6cbd"))
	tag=ui.text(detail,"",24,16,12,ui.PURPLE)
	title=ui.text(detail,"",24,43,27)
	description=ui.text(detail,"",24,91,16,ui.MUTED)
	facts=ui.text(detail,"",24,150,14,ui.PURPLE)
	preview=preload("res://gameplay/pattern_preview.gd").new()
	preview.position=Vector2(24,182)
	preview.size=Vector2(322,32)
	detail.add_child(preview)
	record=ui.text(detail,"",24,224,18,ui.MINT)
	notice=ui.text(detail,"",24,255,12,ui.MUTED)
	ui.text(detail,"연습 배속 / 가이드음",24,285,12,ui.MUTED)
	speed_select=ui.selector(detail,Rect2(24,310,144,40),["0.50x","0.75x","1.00x","1.25x"])
	speed_select.select(1)
	guide_button=ui.button(detail,"가이드 ON",Rect2(184,310,162,40),func():guide=not guide)
	guide_button.add_theme_font_size_override("font_size",15)
	play_button=ui.button(detail,"맵 플레이",Rect2(24,356,154,42),func():g.start_map(selected,false,1.0,false),true)
	train_button=ui.button(detail,"연습하기",Rect2(194,356,152,42),func():g.start_map(selected,true,float(speeds[speed_select.selected]),guide))
	play_button.add_theme_font_size_override("font_size",15)
	train_button.add_theme_font_size_override("font_size",15)
	ui.text(page,"★ 60% · ★★ 80% · ★★★ 95%  /  별 1개로 다음 맵 해금",50,614,15,ui.MUTED)
	ui.text(page,"잠긴 맵도 연습 가능 · 연습 모드에서는 맵 기록과 해금이 바뀌지 않아요.",50,645,13,ui.MUTED)
	stage_caption=ui.text(g,"",50,548,16,ui.PURPLE)
	styles={"normal":ui.style(Color("28233f"),Color("645080")),"locked":ui.style(Color("1a1729"),Color("3b324d")),"selected":ui.style(Color("493663"),Color("bb9af8"),2),"clear":ui.style(Color("173d3c"),Color("6acbb7"))}
func sync() -> void:
	ui.reveal(page,g.phase=="lobby" and ui.page=="solo")
	stage_caption.visible=g.phase=="play" and not g.map_id.is_empty() and not g.paused
	if stage_caption.visible:
		var data: Dictionary=Maps.find(g.map_id)
		var time: float=maxf(0,g.input_time())
		var bar:=mini(int(data.bars),int(time/(60.0/float(data.bpm)*4))+1)
		var section:=mini(3,int(float(bar-1)/float(data.bars)*4))
		stage_caption.text="%s  ·  %d / %d 마디  ·  %s"%[["INTRO","GROOVE","BRIDGE","FINALE"][section],bar,int(data.bars),"가이드와 함께 연습" if g.map_training and g.map_guide else "판정선에 맞춰 끝까지 완주해봐"]
	if not page.visible:
		signature=""
		return
	guide_button.text="가이드 ON" if guide else "가이드 OFF"
	var key:=selected+str(g.preferences.records.hash())
	if key==signature:return
	signature=key
	route.records=g.preferences.records
	route.selected=selected
	route.moving=not g.preferences.values.reduced_motion
	var all:=Maps.catalog()
	var total:=Maps.total_stars(g.preferences.records)
	headline.text="리듬 연습 맵   ·   ★ %d / 36"%total
	var data:=Maps.find(selected)
	var notes:=Maps.chart(selected)
	var unlocked:=Maps.unlocked(selected,g.preferences.records)
	tag.text="MAP %02d  /  LEVEL %d  /  %s"%[int(selected.substr(1)),int(data.level),"BOSS" if int(selected.substr(1))%4==0 else "RHYTHM TRAINING"]
	title.text=str(data.name)
	description.text=str(data.description)
	facts.text="%d BPM  ·  약 %d초  ·  %d NOTES"%[int(data.bpm),ceili((float(notes[-1].t)+float(notes[-1].d))),notes.size()]
	preview.notes=notes
	preview.queue_redraw()
	var best: Dictionary=g.preferences.records.get(Maps.record_id(selected),{})
	record.text="☆☆☆  첫 클리어에 도전!" if best.is_empty() else "★".repeat(int(best.stars))+"☆".repeat(3-int(best.stars))+"   BEST %.1f%%"%float(best.accuracy)
	notice.text="1.0배로 도전 · 기록은 이 기기에 저장돼요." if unlocked else "앞 맵을 ★ 1개로 클리어하면 열려요."
	play_button.disabled=not unlocked
	play_button.text="맵 플레이" if unlocked else "아직 잠겨 있어요"
	for i in range(all.size()):
		var item: Dictionary=all[i]
		var earned:=int(g.preferences.records.get(Maps.record_id(item.id),{}).get("stars",0))
		var available:=Maps.unlocked(item.id,g.preferences.records)
		nodes[i].text="%02d  %s"%[i+1,"★".repeat(earned) if earned>0 else "BOSS" if available and (i+1)%4==0 else "START" if available else "LOCK"]
		nodes[i].add_theme_stylebox_override("normal",styles.selected if item.id==selected else styles.clear if earned>0 else styles.normal if available else styles.locked)
