extends Control
static var face: AtlasTexture
var tint:=Color("68ffe0")
var occupied:=true
var motion_enabled:=true
var elapsed:=0.0
var art: TextureRect
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_to_group("perfecto_art")
	if face==null:
		var texture: Texture2D=preload("res://assets/ui/mascot.webp")
		face=AtlasTexture.new();face.atlas=texture;face.region=Rect2(texture.get_width()*.33,texture.get_height()*.07,texture.get_width()*.52,texture.get_height()*.43);face.filter_clip=true
	art=TextureRect.new();art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.texture=face;var inset:=minf(7,size.x*.08);art.position=Vector2.ONE*inset;art.size=size-Vector2.ONE*inset*2;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(art)
func _process(delta: float) -> void:
	if not is_visible_in_tree():return
	if motion_enabled:elapsed+=delta
	art.visible=occupied
	queue_redraw()
func _draw() -> void:
	var c:=size/2
	var r:=minf(size.x,size.y)*.49
	draw_circle(c,r,Color(tint,.07))
	draw_arc(c,r,0,TAU,48,Color(tint,.4 if occupied else .14),1.5,true)
	if occupied:draw_arc(c,r,elapsed*.35,elapsed*.35+PI*.65,32,tint,2,true)
	else:
		draw_circle(c-Vector2(0,r*.2),r*.18,Color(tint,.25))
		draw_arc(c+Vector2(0,r*.47),r*.36,PI,TAU,24,Color(tint,.25),4,true)
