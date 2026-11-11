extends Control
var notes: Array=[]
func _ready() -> void: mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	if notes.is_empty(): return
	var end:=maxf(1,float(notes[-1].t)+float(notes[-1].d))
	var unit: float=(size.x-12)/end
	var y:=size.y/2
	draw_line(Vector2(6,y),Vector2(size.x-6,y),Color("51436f"),2)
	for n in notes:
		var x:=6+float(n.t)*unit
		var color:=Color("c4a2ff") if float(n.d)>0 else Color("6fffe0")
		if float(n.d)>0: draw_line(Vector2(x,y),Vector2(x+float(n.d)*unit,y),color,7,true)
		draw_circle(Vector2(x,y),5,color)
