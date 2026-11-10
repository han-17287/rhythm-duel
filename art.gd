extends Control

var elapsed := 0.0
var mode := "hero"
var tint := Color("83d9c2")
const INK = Color("29263d")
const CORAL = Color("ff715c")
const LILAC = Color("c9b7f1")
const MINT = Color("83d9c2")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	elapsed += delta
	queue_redraw()

func box(rect: Rect2, color: Color, radius := 20, border := Color.TRANSPARENT) -> void:
	var s := StyleBoxFlat.new()
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
	box(Rect2(0,0,214,72),tint.lightened(0.86),18)
	var y := 37.0+sin(elapsed*1.8)*2
	draw_line(Vector2(42,y+4),Vector2(164,y+4),Color(0.2,0.15,0.25,0.08),18,true)
	draw_line(Vector2(42,y),Vector2(164,y),tint.darkened(0.12),15,true)
	draw_circle(Vector2(37,y+3),19,Color(0.2,0.15,0.25,0.12))
	draw_circle(Vector2(37,y),19,tint.darkened(0.1))
	draw_arc(Vector2(37,y),14,PI*1.1,PI*1.8,18,Color(1,1,1,0.7),3,true)
	draw_circle(Vector2(167,y),10,tint.darkened(0.1))
	star(Vector2(188,16),7,tint.darkened(0.25))

func _draw() -> void:
	if mode=="skin":
		draw_skin()
		return
	var bob := sin(elapsed*1.8)*5
	# Layered sleeves and a floating turntable: actual game artwork, no placeholder image.
	box(Rect2(15,30,420,355),Color("e9dff8"),32)
	box(Rect2(37,56,374,307),LILAC,28)
	for i in range(8):
		draw_line(Vector2(60+i*42,73),Vector2(60+i*42,342),Color(1,1,1,0.2),1)
	box(Rect2(56,106+bob,333,228),Color("b6a0de"),22)
	box(Rect2(50,96+bob,333,228),Color("fffdf8"),22,INK)
	var center := Vector2(192,207+bob)
	draw_circle(center+Vector2(0,5),89,Color("dbd5dd"))
	draw_circle(center,89,INK)
	for radius in [56,65,74,82]: draw_arc(center,radius,0,TAU,80,Color("504a66"),1.5,true)
	draw_arc(center,75,elapsed*0.35,elapsed*0.35+1.7,30,Color("77718b"),3,true)
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
	box(Rect2(237,328-offset,181,53),Color("ffe59a"),16,INK)
	for i in range(8):
		var h := 9+absf(sin(elapsed*2+i*.7))*20
		draw_line(Vector2(259+i*19,355-offset-h/2),Vector2(259+i*19,355-offset+h/2),INK,5,true)
	star(Vector2(27,270),16,CORAL)
	star(Vector2(408,213),20,INK)
	star(Vector2(173,30),12,CORAL)
	draw_arc(Vector2(90,364),17,0,PI*1.6,24,INK,3,true)
