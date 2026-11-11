extends Control
var notes: Array=[]
func _ready() -> void: mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	if notes.is_empty(): return
	var end:=1.0
	for n in notes:end=maxf(end,float(n.t)+float(n.d))
	var double_mode:bool=notes.any(func(n):return n.has("lane"))
	var unit: float=(size.x-12)/end
	var y:=size.y/2
	draw_line(Vector2(6,y),Vector2(size.x-6,y),Color("51436f"),2)
	for n in notes:
		y=size.y*(.3+.4*int(n.get("lane",0))) if double_mode else size.y/2
		var x:=6+float(n.t)*unit
		var color:=Color("c4a2ff") if (int(n.get("lane",0))==1 if double_mode else float(n.d)>0) else Color("6fffe0")
		if float(n.d)>0: draw_line(Vector2(x,y),Vector2(x+float(n.d)*unit,y),color,3 if notes.size()>8 else 7,true)
		draw_circle(Vector2(x,y),1.8 if notes.size()>8 else 5,color)
