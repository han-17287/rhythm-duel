extends RefCounted
var game_ref: WeakRef
var g: Control:
	get:return game_ref.get_ref()
var intro_panel: Panel
var intro_line: Label
var dialogue: Label
var signal_meter: ProgressBar
func _init(game: Control,ui: RefCounted) -> void:
	game_ref=weakref(game)
	intro_panel=ui.card(g,Rect2(50,541,792,82),Color("68ffe0"))
	intro_panel.z_index=8;intro_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	intro_line=ui.text(intro_panel,"",18,10,17,Color("f0faff"))
	dialogue=ui.text(intro_panel,"",18,42,15,Color("68ffe0"))
	signal_meter=ProgressBar.new();signal_meter.position=Vector2(755,329);signal_meter.size=Vector2(315,4);signal_meter.show_percentage=false;signal_meter.max_value=100;signal_meter.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var bg:=StyleBoxFlat.new();bg.bg_color=Color("29354b");bg.set_corner_radius_all(2);signal_meter.add_theme_stylebox_override("background",bg)
	var fill:=StyleBoxFlat.new();fill.bg_color=Color("68ffe0");fill.set_corner_radius_all(2);signal_meter.add_theme_stylebox_override("fill",fill)
	g.add_child(signal_meter);signal_meter.size=Vector2(315,4);intro_panel.hide();signal_meter.hide()
func sync() -> void:
	var active:bool=g.phase=="play" and g.is_song() and not g.paused
	intro_panel.visible=active and g.play_time()<0
	signal_meter.visible=active and g.play_time()>=0
	if not active:return
	if intro_panel.visible:
		var lines:Array=g.Story.intro(g.map_id) if g.ranker_id.is_empty() else [str(g.Ranker.find(g.ranker_id).title)+" / "+g.ranker_difficulty.to_upper()+" / "+("DOUBLE" if g.ranker_kind=="double" else "ONE BEAT"),"%.0fms PERFECT · %.0fms GREAT · %.0fms NICE · 정확도 75%%에 도전!"%[g.judge_windows()[0]*1000,g.judge_windows()[1]*1000,g.judge_windows()[2]*1000]]
		intro_line.text=str(lines[0]);dialogue.text=str(lines[1])
		g.hint.hide()
	var value:float=100*g.live_points/maxf(1,g.live_possible)
	signal_meter.value=value
	var label:Label=g.interface.gameplay_ui.energy
	label.visible=active and not intro_panel.visible
	label.text=("SYNC %.1f%% / CLEAR 75%%" if not g.ranker_id.is_empty() else "SIGNAL %.1f%% / CLEAR 60%%")%value
	label.add_theme_color_override("font_color",Color("68ffe0") if value>=(75 if not g.ranker_id.is_empty() else 60) else Color("ffdc88"))
