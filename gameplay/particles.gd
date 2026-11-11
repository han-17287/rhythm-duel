extends Node2D

var enabled := true
var bits: Array = []
var rings: Array = []
var callouts: Array = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	z_index = 10
	rng.randomize()

func burst(pos: Vector2, color: Color, perfect := false) -> void:
	if not enabled: return
	rings.append({"pos":pos,"color":color,"life":0.35,"max":0.35})
	for i in range(14 if perfect else 7):
		if bits.size()>=100: bits.pop_front()
		var angle := rng.randf_range(-PI,PI)
		bits.append({"pos":pos,"v":Vector2(cos(angle),sin(angle))*rng.randf_range(65,190),"color":color,"life":rng.randf_range(0.25,0.55),"max":0.55,"size":rng.randf_range(2,5)})

func confetti() -> void:
	if not enabled: return
	for i in range(45):
		var color: Color = [Color("ff715c"),Color("b4a5ed"),Color("54f4d4"),Color("ffcc66")][i%4]
		bits.append({"pos":Vector2(600,200),"v":Vector2(rng.randf_range(-270,270),rng.randf_range(-250,80)),"color":color,"life":1.3,"max":1.3,"size":rng.randf_range(3,6)})

func combo_pop(count: int) -> void:
	if not enabled: return
	callouts.append({"text":"%d COMBO!"%count,"life":.7,"max":.7,"pos":Vector2(60,420)})
	rings.append({"pos":Vector2(180,460),"color":Color("ffdc88"),"life":.45,"max":.45})

func _process(delta: float) -> void:
	for i in range(callouts.size()-1,-1,-1):
		callouts[i].life-=delta
		callouts[i].pos.y-=delta*30
		if callouts[i].life<=0:callouts.remove_at(i)
	for i in range(bits.size()-1,-1,-1):
		bits[i].life -= delta
		if bits[i].life<=0:
			bits.remove_at(i)
			continue
		bits[i].pos += bits[i].v*delta
		bits[i].v.y += 220*delta
	for i in range(rings.size()-1,-1,-1):
		rings[i].life -= delta
		if rings[i].life<=0: rings.remove_at(i)
	queue_redraw()

func _draw() -> void:
	if not enabled: return
	for callout in callouts:
		var alpha: float=clampf(callout.life/callout.max,0,1)
		draw_string_outline(ThemeDB.fallback_font,callout.pos,callout.text,HORIZONTAL_ALIGNMENT_CENTER,240,24,5,Color(0,0,0,alpha*.6))
		draw_string(ThemeDB.fallback_font,callout.pos,callout.text,HORIZONTAL_ALIGNMENT_CENTER,240,24,Color(1,.88,.55,alpha))
	for bit in bits:
		var color: Color = bit.color
		color.a = clampf(bit.life/bit.max,0,1)
		draw_rect(Rect2(bit.pos,Vector2.ONE*bit.size),color)
	for ring in rings:
		var color: Color = ring.color
		color.a = ring.life/ring.max
		draw_arc(ring.pos,18+(1-ring.life/ring.max)*45,0,TAU,40,color,2,true)
