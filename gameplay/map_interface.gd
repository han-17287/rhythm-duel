extends RefCounted
const Maps=preload("res://gameplay/maps.gd")
const Design=preload("res://gameplay/ui_theme.gd")
var g: Control
var ui_ref: WeakRef
var ui: RefCounted:
	get:return ui_ref.get_ref()
var page: Control
var route: Control
var selected:="m01"
var signature:=""
var nodes: Array=[]
var world_buttons: Array=[]
var world_labels: Array=[]
var node_names: Array=[]
var node_stars: Array=[]
var map_image: TextureRect
var world_title: Label
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
var world:=0
const COLORS=[Color("68ffe0"),Color("ffcf86"),Color("c09aff")]
const WORLD_NAMES=["민트 스타트","홀드 밸리","프리즘 시티"]
const WORLD_TAGS=["MINT START","HOLD VALLEY","PRISM CITY"]
func _init(game: Control,base: RefCounted) -> void:g=game;ui_ref=weakref(base)
func image(parent: Node,rect: Rect2,texture: Texture2D) -> TextureRect:
	var node:=TextureRect.new()
	node.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	node.texture=texture;node.position=rect.position;node.size=rect.size
	node.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;node.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node
func shade(parent: Node,rect: Rect2,color: Color) -> void:
	var node:=ColorRect.new();node.position=rect.position;node.size=rect.size;node.color=color;node.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(node)
func build() -> void:
	page=ui.group()
	ui.text(page,"SOLO / RHYTHM JOURNEY",50,122,12,Design.MINT).add_theme_font_override("font",Design.font("display"))
	headline=ui.text(page,"맵 여정",48,148,36)
	ui.button(page,"더블 비트 F / J",Rect2(464,148,202,46),g.start_double_training)
	ui.button(page,"아케이드 코스",Rect2(678,148,202,46),func():ui.page="arcade")
	ui.button(page,"내 비트 보관함",Rect2(896,148,208,46),g.open_library)
	for w in range(3):
		var index: int=w
		var b: Button=ui.button(page,"",Rect2(50,232+w*140,178,124),func():select_world(index))
		b.tooltip_text=WORLD_NAMES[w]
		image(b,Rect2(3,3,172,118),Design.world(w)).modulate=Color(.8,.8,.9,1)
		shade(b,Rect2(3,3,172,118),Color(.025,.05,.11,.55))
		shade(b,Rect2(3,3,3,118),COLORS[w])
		ui.text(b,"WORLD 0%d"%(w+1),15,13,11,COLORS[w]).add_theme_font_override("font",Design.font("display"))
		ui.text(b,WORLD_NAMES[w],15,39,20)
		world_labels.append(ui.text(b,"",15,88,12,Color("d9eafa")))
		world_buttons.append(b)
	var panel: Panel=ui.card(page,Rect2(248,232,500,404))
	panel.clip_contents=true
	map_image=image(panel,Rect2(2,2,496,400),Design.world(0))
	shade(panel,Rect2(2,2,496,400),Color(.025,.04,.09,.57))
	world_title=ui.text(page,"",269,249,14,Design.MINT)
	world_title.add_theme_font_override("font",Design.font("display"))
	route=preload("res://gameplay/map_scene.gd").new();page.add_child(route)
	var all:=Maps.catalog()
	for i in range(all.size()):
		var item: Dictionary=all[i]
		var pos: Vector2=route.point(i)
		var id: String=str(item.id)
		var b: Button=ui.button(page,"%02d"%(i+1),Rect2(pos-Vector2(34,34),Vector2(68,68)),func():selected=id)
		b.add_theme_font_override("font",Design.font("display"));b.add_theme_font_size_override("font_size",26)
		b.tooltip_text="MAP %02d · %s"%[i+1,str(item.name)]
		nodes.append(b)
		var name: Label=ui.text(b,str(item.name),-45,73,14)
		name.size.x=158;name.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;node_names.append(name)
		var stars: Label=ui.text(b,"",-35,95,13,Color("ffdc95"))
		stars.size.x=138;stars.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;node_stars.append(stars)
	var detail: Panel=ui.card(page,Rect2(768,232,336,404),Color("5a6b90"))
	tag=ui.text(detail,"",20,15,11,Design.VIOLET)
	title=ui.text(detail,"",20,41,25);title.add_theme_font_override("font",Design.font("headline"))
	description=ui.text(detail,"",20,84,14,Design.MUTED)
	facts=ui.text(detail,"",20,140,13,Design.VIOLET)
	preview=preload("res://gameplay/pattern_preview.gd").new();preview.position=Vector2(20,178);preview.size=Vector2(296,32);detail.add_child(preview)
	record=ui.text(detail,"",20,222,17,Design.MINT)
	notice=ui.text(detail,"",20,255,12,Design.MUTED)
	ui.text(detail,"PRACTICE / 배속과 가이드음",20,285,11,Design.MUTED)
	speed_select=ui.selector(detail,Rect2(20,307,124,38),["0.50x","0.75x","1.00x","1.25x"]);speed_select.select(1)
	guide_button=ui.button(detail,"가이드 ON",Rect2(158,307,158,38),func():guide=not guide);guide_button.add_theme_font_size_override("font_size",14)
	play_button=ui.button(detail,"맵 시작",Rect2(20,355,142,38),func():g.start_map(selected,false,1.0,false),true)
	train_button=ui.button(detail,"연습하기",Rect2(174,355,142,38),func():g.start_map(selected,true,float(speeds[speed_select.selected]),guide))
	for b in [play_button,train_button]:b.add_theme_font_size_override("font_size",15)
	ui.text(page,"★ 60%  ·  ★★ 80%  ·  ★★★ 95%   /   별 1개로 다음 맵 해금",50,651,13,Design.MUTED)
	ui.text(page,"← → 맵 이동   ↑ ↓ 구역   ENTER 시작   P 연습",50,676,11,Design.MUTED)
	stage_caption=ui.text(g,"",50,548,16,Design.VIOLET)
	for key in ["normal","locked","selected","clear","hover","pressed"]:
		var fill: Color={"normal":Color("142e41"),"locked":Color("0c1525"),"selected":Color("2e4a56"),"clear":Color("174139"),"hover":Color("325577"),"pressed":Color("477590")}[key]
		var border: Color=Design.MINT if key in ["selected","clear"] else Color("7697bb") if key=="hover" else Color("425574")
		var style: StyleBoxFlat=ui.style(fill,border,2 if key=="selected" else 1)
		style.set_corner_radius_all(34);style.content_margin_left=4;style.content_margin_right=4
		styles[key]=style
func select_world(index: int) -> void:selected=str(Maps.catalog()[clampi(index,0,2)*4].id)
func handle_input(event: InputEventKey) -> bool:
	if not page.visible or not event.pressed or speed_select.get_popup().visible:return false
	var index:=int(selected.substr(1))-1
	var change:=0
	match event.keycode:
		KEY_LEFT:change=-1
		KEY_RIGHT:change=1
		KEY_UP:change=-4
		KEY_DOWN:change=4
		KEY_ENTER:
			if Maps.unlocked(selected,g.preferences.records):g.start_map(selected)
			else:g.emote_text="잠긴 맵도 P키로 연습할 수 있어요.";g.emote_until=g.now()+2.5
			return true
		KEY_ESCAPE:ui.page="home";return true
		KEY_P:g.start_map(selected,true,float(speeds[speed_select.selected]),guide);return true
	if change!=0:
		selected=str(Maps.catalog()[posmod(index+change,12)].id);g.sounds.play("tick",.1);return true
	return false
func sync() -> void:
	ui.reveal(page,g.phase=="lobby" and ui.page=="solo")
	stage_caption.visible=g.phase=="play" and not g.map_id.is_empty() and not g.paused
	if stage_caption.visible:
		var data: Dictionary=Maps.find(g.map_id)
		var time: float=maxf(0,g.input_time())
		var bar:=mini(int(data.bars),int(time/(60.0/float(data.bpm)*4))+1)
		var section:=mini(3,int(float(bar-1)/float(data.bars)*4))
		stage_caption.text="%s  ·  %d / %d 마디  ·  %s"%[["INTRO","GROOVE","BRIDGE","FINALE"][section],bar,int(data.bars),"가이드와 함께 연습" if g.map_training and g.map_guide else "목표 정확도 60% · 끝까지 완주해봐"]
	if not page.visible:signature="";return
	guide_button.text="가이드 ON" if guide else "가이드 OFF"
	var key:=selected+str(g.preferences.records.hash())
	if key==signature:return
	signature=key
	var data:=Maps.find(selected);world=int(data.region)
	route.records=g.preferences.records;route.selected=selected;route.world=world;route.moving=not g.preferences.values.reduced_motion
	map_image.texture=Design.world(world)
	world_title.text="WORLD %02d / %s"%[world+1,WORLD_TAGS[world]]
	world_title.add_theme_color_override("font_color",COLORS[world])
	var total:=Maps.total_stars(g.preferences.records)
	headline.text="맵 여정   ·   ★ %d / 36"%total
	var all:=Maps.catalog()
	for w in range(3):
		var earned:=0;var clears:=0
		for i in range(4):
			var value:=int(g.preferences.records.get(Maps.record_id(all[w*4+i].id),{}).get("stars",0));earned+=value
			if value>0:clears+=1
		world_labels[w].text="★ %d / 12   ·   %d / 4 CLEAR"%[earned,clears]
		world_buttons[w].modulate=Color.WHITE if w==world else Color(.65,.7,.8,1)
	var notes:=Maps.chart(selected);var available:=Maps.unlocked(selected,g.preferences.records)
	tag.text="MAP %02d  /  LV.%d  /  %s"%[int(selected.substr(1)),int(data.level),"BOSS" if int(selected.substr(1))%4==0 else "CHALLENGE"]
	title.text=str(data.name);description.text=str(data.description)
	facts.text="%d BPM  ·  %d초  ·  %d NOTES"%[int(data.bpm),ceili(float(notes[-1].t)+float(notes[-1].d)),notes.size()]
	preview.notes=notes;preview.queue_redraw()
	var best: Dictionary=g.preferences.records.get(Maps.record_id(selected),{})
	record.text="☆☆☆  첫 클리어에 도전" if best.is_empty() else "★".repeat(int(best.stars))+"☆".repeat(3-int(best.stars))+"  BEST %.1f%%"%float(best.accuracy)
	notice.text="ENTER · 1.0배 정식 도전" if available else "이전 맵을 ★ 1개로 클리어해 열어봐."
	play_button.disabled=not available;play_button.text="맵 시작" if available else "잠긴 맵"
	for i in range(all.size()):
		var item: Dictionary=all[i];nodes[i].visible=int(item.region)==world
		var earned:=int(g.preferences.records.get(Maps.record_id(item.id),{}).get("stars",0));var opened:=Maps.unlocked(item.id,g.preferences.records)
		for state in ["normal","hover","pressed","disabled"]:nodes[i].add_theme_stylebox_override(state,styles.selected if state=="normal" and item.id==selected else styles.clear if state=="normal" and earned>0 else styles.locked if state=="normal" and not opened else styles.normal if state in ["normal","disabled"] else styles[state])
		nodes[i].add_theme_color_override("font_color",Design.WHITE if opened else Color("8f9eb3"))
		node_stars[i].text="★".repeat(earned)+"☆".repeat(3-earned) if earned>0 else "BOSS" if (i+1)%4==0 else "도전 대기" if opened else "PRACTICE OPEN"
