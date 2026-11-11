extends Control
var records: Dictionary={}
var selected:="m01"
var moving:=true
var elapsed:=0.0
const Maps=preload("res://gameplay/maps.gd")
static func point(index: int) -> Vector2:
	var col:=index%4 if index/4!=1 else 3-index%4
	return Vector2(131+col*155,287+(index/4)*115)
func _ready() -> void:mouse_filter=Control.MOUSE_FILTER_IGNORE
func _process(delta: float) -> void:
	if not is_visible_in_tree():return
	if moving:elapsed+=delta
	queue_redraw()
func _draw() -> void:
	var all:=Maps.catalog()
	for i in range(11):
		var color:=Color("6fffe0") if int(records.get(Maps.record_id(all[i].id),{}).get("stars",0))>0 else Color("514166")
		draw_line(point(i),point(i+1),Color(color,.4),3,true)
	for i in range(12):
		if all[i].id==selected:
			var radius: float=33+(sin(elapsed*2)*2 if moving else 0)
			draw_arc(point(i),radius,0,TAU,48,Color("bda0ff"),2,true)
