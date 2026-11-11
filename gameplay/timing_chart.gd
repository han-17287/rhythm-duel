extends Control
var offsets: Array = []
var judgments: Array = []
func _ready() -> void: mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	var center := size.x/2
	var y := size.y/2
	for window in [180,80,35]:
		var half: float = size.x*float(window)/360.0
		draw_rect(Rect2(center-half,8,half*2,size.y-16),[Color("3b263b"),Color("30274b"),Color("193e3b")][[180,80,35].find(window)])
	draw_line(Vector2(center,4),Vector2(center,size.y-4),Color("b8a8d2"),1)
	for i in range(offsets.size()):
		if offsets[i]==null: continue
		var x := center+clampf(float(offsets[i]),-180,180)/360*size.x
		var color: Color = [Color("72ffe4"),Color("ffdc88"),Color("c4a6ff"),Color("ff719b")][int(judgments[i])]
		draw_circle(Vector2(x,y+(i%3-1)*9),4,color)
