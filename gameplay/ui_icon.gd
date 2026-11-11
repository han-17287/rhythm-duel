extends Control
var kind:="play"
var color:=Color("bfffee")
func _ready() -> void:mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	var c:=size/2
	var r:=minf(size.x,size.y)*.38
	if kind=="play":draw_colored_polygon(PackedVector2Array([c+Vector2(-r*.6,-r),c+Vector2(r,0),c+Vector2(-r*.6,r)]),color)
	elif kind=="battle":
		for sign in [-1,1]:
			draw_line(c+Vector2(-r*sign,r),c+Vector2(r*sign,-r),color,2.5,true)
			draw_line(c+Vector2(-r*sign*.8,r*.2),c+Vector2(-r*sign*.2,r*.8),color,2.5,true)
			draw_colored_polygon(PackedVector2Array([c+Vector2(r*sign,-r),c+Vector2(r*sign*.2,-r*.8),c+Vector2(r*sign*.8,-r*.2)]),color)
	elif kind=="map":
		var a:=c+Vector2(-r,r*.6)
		var b:=c+Vector2(0,-r*.6)
		var d:=c+Vector2(r,r*.3)
		draw_polyline(PackedVector2Array([a,b,d]),color,2,true)
		for p in [a,b,d]:draw_circle(p,3,color)
	elif kind=="gear":
		draw_arc(c,r*.7,0,TAU,24,color,2,true)
		draw_circle(c,2.5,color)
		for i in range(8):
			var v:=Vector2.from_angle(i*TAU/8)
			draw_line(c+v*r*.65,c+v*r,color,2.5,true)
	elif kind=="expand":
		for x in [-1,1]:
			for y in [-1,1]:
				var p:=c+Vector2(x*r,y*r)
				draw_polyline(PackedVector2Array([p-Vector2(x*r*.5,0),p,p-Vector2(0,y*r*.5)]),color,2,true)
	elif kind=="crown":
		var ps:=PackedVector2Array([c+Vector2(-r,-r*.5),c+Vector2(-r*.4,0),c+Vector2(0,-r),c+Vector2(r*.4,0),c+Vector2(r,-r*.5),c+Vector2(r*.7,r*.7),c+Vector2(-r*.7,r*.7)])
		draw_colored_polygon(ps,Color(color,.2))
		ps.append(ps[0]);draw_polyline(ps,color,2,true)
	elif kind=="disc":
		for radius in [r,r*.65,r*.22]:draw_arc(c,radius,0,TAU,32,color,1.5,true)
	elif kind=="arrow":draw_polyline(PackedVector2Array([c+Vector2(-r*.4,-r),c+Vector2(r*.5,0),c+Vector2(-r*.4,r)]),color,2,true)
	elif kind=="home":
		draw_polyline(PackedVector2Array([c+Vector2(-r,0),c+Vector2(0,-r),c+Vector2(r,0)]),color,2,true)
		draw_polyline(PackedVector2Array([c+Vector2(-r*.7,-r*.2),c+Vector2(-r*.7,r),c+Vector2(r*.7,r),c+Vector2(r*.7,-r*.2)]),color,2,true)
