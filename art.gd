extends Control

var elapsed := 0.0
var motion_enabled := true
var mode := "hero"
var tint := Color("83d9c2")
var badge_kind := "first"
var badge_level := 1
var skin_kind := "mint"
var box_styles: Dictionary = {}
const INK = Color("ddd5ff")
const CORAL = Color("ff83b2")
const LILAC = Color("8360d8")
const MINT = Color("6fffe0")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("perfecto_art")

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not motion_enabled: return
	elapsed += delta
	queue_redraw()

func box(rect: Rect2, color: Color, radius := 20, border := Color.TRANSPARENT) -> void:
	var key:=str(color)+str(radius)+str(border)
	if not box_styles.has(key): box_styles[key]=StyleBoxFlat.new()
	var s: StyleBoxFlat=box_styles[key]
	s.bg_color = color
	s.set_corner_radius_all(radius)
	if border.a>0:
		s.border_color = border
		s.set_border_width_all(2)
	draw_style_box(s,rect)

func star(pos: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(8):
		var angle := i*PI/4-PI/2
		points.append(pos+Vector2(cos(angle),sin(angle))*(r if i%2==0 else r*0.3))
	draw_colored_polygon(points,color)

func draw_skin() -> void:
	box(Rect2(0,0,214,72),Color("29213e"),18)
	var y := 37.0+sin(elapsed*1.8)*2
	draw_line(Vector2(42,y+4),Vector2(164,y+4),Color(0.2,0.15,0.25,0.08),18,true)
	draw_line(Vector2(42,y),Vector2(164,y),tint,15,true)
	preload("res://gameplay/note_skin.gd").draw(self,Vector2(37,y),tint,skin_kind,19)
	draw_circle(Vector2(167,y),10,tint)
	star(Vector2(188,16),7,tint)

func draw_badge() -> void:
	box(Rect2(0,0,50,50),Color(tint,.14),16)
	var color:=tint
	for i in range(4):
		draw_line(Vector2(3+i*12,58),Vector2(10+i*12,58),Color(tint,.8 if i<badge_level else .16),3,true)
	if badge_kind=="hold":
		draw_line(Vector2(14,25),Vector2(36,25),color,9,true)
		draw_circle(Vector2(13,25),7,color)
	elif badge_kind=="rush":
		for x in [10,24]: draw_polyline(PackedVector2Array([Vector2(x,14),Vector2(x+12,25),Vector2(x,36)]),color,4,true)
	elif badge_kind=="survival":
		draw_colored_polygon(PackedVector2Array([Vector2(28,8),Vector2(13,28),Vector2(24,28),Vector2(21,42),Vector2(38,21),Vector2(27,21)]),color)
	elif badge_kind=="daily":
		star(Vector2(25,25),17,color)
		draw_circle(Vector2(25,25),5,Color("fffdf9"))
	elif badge_kind=="swing":
		draw_circle(Vector2(14,31),6,color)
		draw_circle(Vector2(35,19),6,color)
		draw_line(Vector2(18,28),Vector2(31,22),color,3,true)
	else:
		draw_circle(Vector2(18,33),8,color)
		draw_line(Vector2(25,33),Vector2(25,13),color,4,true)
		draw_line(Vector2(25,13),Vector2(36,18),color,4,true)

func _draw() -> void:
	if mode=="badge":
		draw_badge()
		return
	if mode=="skin":
		draw_skin()
		return
	var bob := sin(elapsed*1.8)*5
	# Layered sleeves and a floating turntable: actual game artwork, no placeholder image.
	box(Rect2(15,30,420,355),Color("201b35"),32)
	box(Rect2(37,56,374,307),LILAC,28)
	for i in range(8):
		draw_line(Vector2(60+i*42,73),Vector2(60+i*42,342),Color(1,1,1,0.2),1)
	box(Rect2(56,106+bob,333,228),Color("141324"),22)
	box(Rect2(50,96+bob,333,228),Color("28233e"),22,INK)
	var center := Vector2(192,207+bob)
	draw_circle(center+Vector2(0,5),89,Color("141222"))
	draw_circle(center,89,Color("11121e"))
	for radius in [56,65,74,82]: draw_arc(center,radius,0,TAU,80,Color("3b3354"),1.5,true)
	draw_arc(center,75,elapsed*0.35,elapsed*0.35+1.7,30,Color("9b80d1"),3,true)
	draw_circle(center,36,CORAL)
	draw_circle(center,13,Color("ffb3a2"))
	draw_circle(center,4,INK)
	# Needle, transport key, and a tiny equalizer.
	draw_circle(Vector2(337,137+bob),9,LILAC)
	draw_polyline(PackedVector2Array([Vector2(337,137+bob),Vector2(322,218+bob),Vector2(280,245+bob)]),INK,6,true)
	box(Rect2(268,241+bob,23,12),MINT,4,INK)
	box(Rect2(312,279+bob,42,23),CORAL,7,INK)
	for i in range(5):
		var h := 8+absf(sin(elapsed*3+i))*18
		box(Rect2(73+i*9,307+bob-h,5,h),MINT,2)
	# Note chips orbit the composition and convey a playable rhythm.
	var offset := sin(elapsed*2.2)*6
	box(Rect2(1,72+offset,112,53),MINT,16,INK)
	draw_circle(Vector2(24,98+offset),8,INK)
	draw_line(Vector2(44,98+offset),Vector2(91,98+offset),INK,7,true)
	box(Rect2(309,48-offset,126,49),CORAL,16,INK)
	for i in range(3): draw_circle(Vector2(336+i*30,72-offset),6,INK)
	box(Rect2(237,328-offset,181,53),Color("f4bd65"),16,INK)
	for i in range(8):
		var h := 9+absf(sin(elapsed*2+i*.7))*20
		draw_line(Vector2(259+i*19,355-offset-h/2),Vector2(259+i*19,355-offset+h/2),INK,5,true)
	star(Vector2(27,270),16,CORAL)
	star(Vector2(408,213),20,INK)
	star(Vector2(173,30),12,CORAL)
	draw_arc(Vector2(90,364),17,0,PI*1.6,24,INK,3,true)
