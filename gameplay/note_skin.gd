extends RefCounted

# Every skin keeps the same center and visual footprint; timing rules never change.
static func draw(canvas: CanvasItem, pos: Vector2, color: Color, kind := "mint", radius := 18.0) -> void:
	canvas.draw_circle(pos,radius+11,Color(color,.07))
	canvas.draw_circle(pos,radius+4,Color(color,.18))
	canvas.draw_circle(pos+Vector2(0,4),radius,Color(0,0,0,.3))
	if kind=="lavender":
		var points:=PackedVector2Array([pos+Vector2(0,-radius),pos+Vector2(radius,0),pos+Vector2(0,radius),pos+Vector2(-radius,0)])
		canvas.draw_colored_polygon(points,color)
		canvas.draw_polyline(PackedVector2Array([points[0],points[1],points[2],points[3],points[0]]),color.lightened(.5),2,true)
		canvas.draw_line(pos+Vector2(-radius*.5,0),pos+Vector2(0,-radius*.5),Color.WHITE,2,true)
	elif kind=="sunset":
		var points:=PackedVector2Array()
		for i in range(7):
			var angle: float=(i%6)*TAU/6
			points.append(pos+Vector2(cos(angle),sin(angle))*radius)
		canvas.draw_colored_polygon(points.slice(0,6),color)
		canvas.draw_polyline(points,color.lightened(.5),2,true)
		canvas.draw_arc(pos,radius*.55,PI,TAU,20,Color(1,1,1,.7),2,true)
	elif kind=="ice":
		var points:=PackedVector2Array()
		for i in range(8):
			var angle:=i*TAU/8-PI/2
			points.append(pos+Vector2(cos(angle),sin(angle))*(radius if i%2==0 else radius*.55))
		canvas.draw_colored_polygon(points,color)
		canvas.draw_line(pos+Vector2(0,-radius*.65),pos+Vector2(0,radius*.65),Color(1,1,1,.7),2,true)
		canvas.draw_line(pos+Vector2(-radius*.65,0),pos+Vector2(radius*.65,0),Color(1,1,1,.7),2,true)
	else:
		canvas.draw_circle(pos,radius,color)
		canvas.draw_arc(pos,radius,0,TAU,40,color.lightened(.55),1.5,true)
		canvas.draw_arc(pos,radius*.72,PI*1.12,PI*1.8,14,Color(1,1,1,.65),2,true)
