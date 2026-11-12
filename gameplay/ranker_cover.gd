extends Control
var index:=0
var tint:=Color("68ffe0")
var motion_enabled:=true
var elapsed:=0.0
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_to_group("perfecto_art")
func _process(delta:float)->void:
	if not is_visible_in_tree():return
	if motion_enabled:elapsed+=delta
	queue_redraw()
func _draw()->void:
	paint(self,size/2,minf(size.x,size.y)*.39,index,tint,elapsed,0)
static func paint(canvas:CanvasItem,center:Vector2,r:float,kind:int,color:Color,time:float,pulse:float)->void:
	canvas.draw_circle(center,r*1.22,Color(color,color.a*.055))
	canvas.draw_arc(center,r*1.12,0,TAU,48,Color(color,color.a*.25),1,true)
	var angle:=time*.22
	if kind==0:
		var shape:=PackedVector2Array()
		for i in range(7):shape.append(center+Vector2.from_angle(angle+i*TAU/6)*r*(.8+pulse*.08))
		canvas.draw_polyline(shape,color,2,true)
		canvas.draw_circle(center,r*.24,Color(color,color.a*.7))
		for i in range(6):
			var direction:=Vector2.from_angle(angle+i*TAU/6)
			canvas.draw_line(center+direction*r*.38,center+direction*r*.66,Color(color,color.a*.55),2,true)
	elif kind==1:
		for i in range(4):
			var a:=angle+i*TAU/4
			var points:=PackedVector2Array([center+Vector2.from_angle(a)*r*.16,center+Vector2.from_angle(a+.15)*r,center+Vector2.from_angle(a+.85)*r*.74])
			canvas.draw_colored_polygon(points,Color(color,color.a*.2))
			canvas.draw_polyline(points,color,1.5,true)
	elif kind==2:
		for i in range(3):
			var a:=angle+i*TAU/3
			canvas.draw_arc(center,r*(.46+i*.2),a,a+PI*1.3,40,Color(color,color.a*(.4+i*.2)),1.5,true)
			canvas.draw_circle(center+Vector2.from_angle(a+PI*1.3)*r*(.46+i*.2),2.5,color)
		canvas.draw_circle(center,r*.16,color)
	else:
		canvas.draw_circle(center,r*.46,Color("080b17"))
		canvas.draw_arc(center,r*.52,angle,angle+PI*1.6,48,color,2.5,true)
		for i in range(12):
			var a:=angle+i*TAU/12
			canvas.draw_line(center+Vector2.from_angle(a)*r*.7,center+Vector2.from_angle(a+.19)*r,Color(color,color.a*.65),1.5,true)
