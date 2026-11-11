extends Control
const Maps=preload("res://gameplay/maps.gd")
var records: Dictionary={}
var selected:="m01"
var world:=0
var moving:=true
var elapsed:=0.0
static func point(index: int) -> Vector2:
	return [Vector2(328,384),Vector2(477,306),Vector2(662,388),Vector2(523,541)][index%4]
func _ready() -> void:mouse_filter=Control.MOUSE_FILTER_IGNORE
func _process(delta: float) -> void:
	if not is_visible_in_tree():return
	if moving:elapsed+=delta
	queue_redraw()
func _draw() -> void:
	var color: Color=[Color("68ffe0"),Color("ffcf86"),Color("c09aff")][world]
	var all:=Maps.catalog()
	for i in range(3):
		var a:=point(i)
		var b:=point(i+1)
		var cleared:=int(records.get(Maps.record_id(all[world*4+i].id),{}).get("stars",0))>0
		var c:=color if cleared else Color("a8b9d2")
		draw_line(a,b,Color(c,.09),9,true)
		draw_line(a,b,Color(c,.55 if cleared else .22),2,true)
		var distance:=a.distance_to(b)
		for j in range(int(distance/16)):
			var pos:=a.lerp(b,(j+.5)/maxf(1,distance/16))
			draw_circle(pos,1.5,Color(c,.8 if cleared else .4))
	for i in range(4):
		var pos:=point(i)
		var is_selected: bool=all[world*4+i].id==selected
		draw_set_transform(pos+Vector2(0,25),0,Vector2(1,.32))
		draw_circle(Vector2.ZERO,56,Color(color,.035))
		draw_arc(Vector2.ZERO,49,0,TAU,48,Color(color,.5 if is_selected else .18),2,true)
		draw_arc(Vector2.ZERO,56,elapsed*.3,elapsed*.3+PI*.7,24,Color(color,.4 if is_selected else .1),2,true)
		draw_set_transform(Vector2.ZERO)
		if is_selected:draw_circle(pos,47+(sin(elapsed*2)*2 if moving else 0),Color(color,.08))
