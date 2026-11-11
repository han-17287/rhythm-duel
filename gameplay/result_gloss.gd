extends Control

var elapsed:=3.0
var moving:=true

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip_contents=true

func restart(enabled: bool) -> void:
	moving=enabled
	elapsed=0 if enabled else 3
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not moving or elapsed>1.2:return
	elapsed+=delta
	queue_redraw()

func _draw() -> void:
	if not moving or elapsed>1.2:return
	var x:=lerpf(-180,size.x+200,elapsed/1.2)
	var alpha:=sin(clampf(elapsed/1.2,0,1)*PI)*.045
	draw_colored_polygon(PackedVector2Array([Vector2(x,0),Vector2(x+55,0),Vector2(x-100,size.y),Vector2(x-155,size.y)]),Color(1,1,1,alpha))
