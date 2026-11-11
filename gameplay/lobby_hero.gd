extends Control
var moving:=true
var elapsed:=0.0
var art: TextureRect
var origin:=Vector2(0,0)
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_to_group("perfecto_art")
	art=TextureRect.new()
	art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	art.texture=preload("res://assets/ui/mascot.webp")
	art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	art.size=size
	art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(art)
var motion_enabled: bool:
	get:return moving
	set(value):moving=value
func _process(delta: float) -> void:
	if not is_visible_in_tree():return
	if moving:elapsed+=delta
	var cursor: Vector2=(get_global_mouse_position()-global_position-size/2)/size
	var offset:=Vector2(clampf(cursor.x,-1,1)*5,clampf(cursor.y,-1,1)*3+sin(elapsed*1.7)*4) if moving else Vector2.ZERO
	art.position=art.position.lerp(offset,minf(1,delta*5))
	queue_redraw()
func _draw() -> void:
	var center:=Vector2(size.x*.52,size.y*.7)
	for i in range(3):
		var radius:=125+i*22
		var angle:=elapsed*.15+i
		draw_arc(center,radius,angle,angle+PI*.65,40,Color(.48,.36,.9,.12),1.5,true)
