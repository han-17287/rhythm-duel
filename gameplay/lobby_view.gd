extends RefCounted
const Design=preload("res://gameplay/ui_theme.gd")
const Maps=preload("res://gameplay/maps.gd")
var g: Control
var ui_ref: WeakRef
var ui: RefCounted:
	get:return ui_ref.get_ref()
var page: Control
var mastery: Label
var continue_label: Label
var daily_label: Label
var progress: ProgressBar
var recommended:="m01"
var signature:=""
func _init(game: Control,base: RefCounted) -> void:g=game;ui_ref=weakref(base)
func tile(title: String,subtitle: String,rect: Rect2,kind: String,action: Callable,primary:=false) -> Button:
	var b: Button=ui.button(page,"",rect,action,primary)
	b.tooltip_text=title+" · "+subtitle
	var icon:=preload("res://gameplay/ui_icon.gd").new()
	icon.kind=kind
	icon.position=Vector2(16,(rect.size.y-32)/2)
	icon.size=Vector2(32,32)
	icon.color=Color("102a30") if primary else Design.MINT
	b.add_child(icon)
	ui.text(b,title,62,16,21,Color("102a30") if primary else Design.WHITE)
	ui.text(b,subtitle,62,47,13,Color("24574f") if primary else Design.MUTED)
	var arrow:=preload("res://gameplay/ui_icon.gd").new()
	arrow.kind="arrow";arrow.size=Vector2(18,18);arrow.position=Vector2(rect.size.x-30,(rect.size.y-18)/2)
	arrow.color=Color("102a30") if primary else Design.MUTED
	b.add_child(arrow)
	return b
func build() -> void:
	page=ui.group()
	ui.text(page,"PLAYER / RHYTHM STATION",50,126,12,Design.MUTED).add_theme_font_override("font",Design.font("display"))
	mastery=ui.text(page,"",302,125,13,Design.MINT)
	progress=ProgressBar.new()
	progress.position=Vector2(302,151);progress.custom_minimum_size=Vector2(276,4);progress.size=Vector2(276,4);progress.max_value=36;progress.show_percentage=false
	var bg:=StyleBoxFlat.new();bg.bg_color=Color("26364c");bg.set_corner_radius_all(2)
	var fill:=StyleBoxFlat.new();fill.bg_color=Design.MINT;fill.set_corner_radius_all(2)
	progress.add_theme_stylebox_override("background",bg);progress.add_theme_stylebox_override("fill",fill);page.add_child(progress);progress.size=Vector2(276,4)
	var hero:=preload("res://gameplay/lobby_hero.gd").new()
	hero.position=Vector2(638,100);hero.size=Vector2(472,492);page.add_child(hero)
	ui.text(page,"YOUR RHYTHM. YOUR RULES.",50,183,16,Design.MINT).add_theme_font_override("font",Design.font("display"))
	ui.text(page,"네 비트가,\n게임의 룰이 된다.",46,216,52)
	ui.text(page,"여덟 개의 비트를 던지고, 완벽하게 받아쳐.\n친구와 겨루거나 음악을 따라 스토리 여정을 시작해봐.",50,374,18,Design.MUTED)
	tile("친구와 대전","ONLINE DUEL / 방 코드로 함께",Rect2(50,453,264,88),"battle",func():ui.page="rooms",true)
	g.practice_button=tile("스토리 모드","12 SONGS / 스토리 여정",Rect2(330,453,248,88),"map",func():open_recommended())
	ui.profile_summary=ui.text(page,"",50,553,14,Design.MUTED)
	var a:=tile("이어서 도전","",Rect2(50,594,336,82),"crown",func():open_recommended())
	continue_label=ui.text(a,"",62,48,13,Design.MUTED)
	var b:=tile("랭커 모드","",Rect2(408,594,336,82),"disc",func():ui.page="ranker")
	daily_label=ui.text(b,"",62,48,13,Design.MUTED)
	tile("스킨 컬렉션","새로운 노트, 새로운 분위기",Rect2(766,594,338,82),"play",func():ui.page="shop")
	ui.text(page,"CREATE · ECHO · PERFECTO",753,562,12,Design.VIOLET).add_theme_font_override("font",Design.font("display"))
func open_recommended() -> void:
	ui.gameplay_ui.map_ui.selected=recommended
	ui.page="solo"
func sync() -> void:
	if not page.visible:return
	var key:=str(g.preferences.records.hash())
	if key==signature:return
	signature=key
	var total:=Maps.total_stars(g.preferences.records)
	var cleared:=0
	recommended="m12"
	var found:=false
	for item in Maps.catalog():
		var stars:=int(g.preferences.records.get(Maps.record_id(item.id),{}).get("stars",0))
		if stars>0:cleared+=1
		if not found and stars==0 and Maps.unlocked(item.id,g.preferences.records):recommended=item.id;found=true
	if not found:
		for item in Maps.catalog():
			if int(g.preferences.records.get(Maps.record_id(item.id),{}).get("stars",0))<3:recommended=item.id;break
	mastery.text="MAP MASTERY   ★ %d / 36  ·  %d / 12 CLEAR"%[total,cleared]
	progress.value=total
	continue_label.text="MAP %s  %s"%[recommended.substr(1),str(Maps.find(recommended).name)]
	var daily: Dictionary=g.preferences.records.get(g.Challenges.record_id("daily"),{})
	daily_label.text="ONE BEAT / DOUBLE · 극한 난이도"
