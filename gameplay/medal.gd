extends Control
var grade:="S"
var moving:=true
var elapsed:=0.0
func _ready() -> void:mouse_filter=Control.MOUSE_FILTER_IGNORE
func _process(delta: float) -> void:
	if not is_visible_in_tree():return
	if moving:elapsed+=delta
	queue_redraw()
func _draw() -> void:
	var color: Color={"EX":Color("fff0af"),"SS":Color("80faff"),"F":Color("ff719b"),"S":Color("ffd477"),"A":Color("6be8c7"),"B":Color("b79cff"),"C":Color("91c6ff"),"D":Color("ff9caa")}.get(grade,Color("b79cff"))
	var center:=Vector2(75,80)
	for i in range(12):
		var angle:=i*TAU/12+elapsed*.12
		draw_line(center+Vector2(cos(angle),sin(angle))*55,center+Vector2(cos(angle),sin(angle))*66,Color(color,.3),3,true)
	draw_circle(center,54,Color(color,.12))
	draw_arc(center,49,0,TAU,64,color,2,true)
	draw_circle(center,43,Color(color,.2))
	var a:=elapsed*.8
	draw_arc(center,58,a,a+PI*.7,32,Color(color,.7),2,true)
