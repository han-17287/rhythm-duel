extends RefCounted

var g: Control
var ui_ref: WeakRef
var ui: RefCounted:
	get: return ui_ref.get_ref()
var calibration_ui: RefCounted
var ranker_ui: RefCounted
var story_hud: RefCounted
var music_slider: HSlider
var music_value: Label
var map_ui: RefCounted
var course_page: Control
var settings_page: Control
var library_page: Control
var library_rows: Array = []
var library_labels: Array = []
var library_previews: Array = []
var library_empty: Label
var library_open: Button
var save_pattern: Button
var review: Control
var stop_preview: Button
var reset_record: Button
var summary: Control
var pause_panel: Control
var combo_label: Label
var precision: Label
var live_note: Label
var activity: Label
var toast: Label
var toast_panel: Panel
var summary_signature := ""
var score_tween: Tween
var summary_panel: Panel
var medal_art: Control
var result_gloss: Control
var theme_stage_last := false
var theme_ready := false
var stage_styles: Dictionary = {}
var light_styles: Dictionary = {}
var grade: Label
var points: Label
var score_caption: Label
var accuracy: Label
var medal: Label
var max_combo: Label
var timing_caption: Label
var chart: Control
var counts: Array = []
var course_records: Array = []
var replay: Button
var advance: Button
var course_back: Button
var rematch: Button
var volume_value: Label
var offset_value: Label
var volume_slider: HSlider
var offset_slider: HSlider
var effects_button: Button
var motion_button: Button
var click_button: Button
var key_select: OptionButton
var bpm_select: OptionButton
var stage_timer: Label
var energy: Label
var footer: Label
var emotes: OptionButton
var double_touch: Array=[]
var touch_input: Button

func _init(game: Control, base_ui: RefCounted) -> void:
	g=game
	ui_ref=weakref(base_ui)

func build() -> void:
	map_ui=preload("res://gameplay/map_interface.gd").new(g,ui)
	map_ui.build()
	ranker_ui=preload("res://gameplay/ranker_interface.gd").new(g,ui)
	ranker_ui.build()
	calibration_ui=preload("res://gameplay/calibration.gd").new(g,ui)
	calibration_ui.build()

	touch_input=Button.new()
	touch_input.position=Vector2(870,541)
	touch_input.size=Vector2(232,82)
	touch_input.focus_mode=Control.FOCUS_NONE
	for state in ["normal","hover","pressed","focus"]: touch_input.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	touch_input.button_down.connect(func(): g.pointer_input(true))
	touch_input.button_up.connect(func(): g.pointer_input(false))
	g.add_child(touch_input)
	var touch_image:=Image.create(110,82,false,Image.FORMAT_RGBA8);touch_image.fill(Color(0,0,0,0))
	var touch_texture:=ImageTexture.create_from_image(touch_image)
	for lane in range(2):
		var pad:=Button.new()
		pad.position=Vector2(870+lane*122,541);pad.size=Vector2(110,82);pad.focus_mode=Control.FOCUS_NONE
		for state in ["normal","hover","pressed","focus"]:pad.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		pad.button_down.connect(g.double_beat.pointer.bind(lane,true));pad.button_up.connect(g.double_beat.pointer.bind(lane,false))
		g.add_child(pad);double_touch.append(pad)
		var touch:=TouchScreenButton.new();touch.position=Vector2(870+lane*122,541);touch.texture_normal=touch_texture;touch.shape_centered=true;touch.visibility_mode=TouchScreenButton.VISIBILITY_TOUCHSCREEN_ONLY
		var shape:=RectangleShape2D.new();shape.size=Vector2(110,82);touch.shape=shape
		touch.pressed.connect(g.double_beat.pointer.bind(lane,true));touch.released.connect(g.double_beat.pointer.bind(lane,false))
		g.add_child(touch);double_touch.append(touch)
	emotes=ui.selector(g,Rect2(785,124,319,44),["친구에게 한마디","준비 완료!","좋은 리듬!","한 판 더!","멋진 수비!"])
	emotes.item_selected.connect(func(i):
		if i>0: g.send_packet({"type":"emote","emote":["","준비 완료!","좋은 리듬!","한 판 더!","멋진 수비!"][i]})
		emotes.select(0))
	combo_label=ui.text(g,"",752,210,44,Color("e6d7ff"))
	combo_label.add_theme_font_override("font",ui.Design.font("display"))
	combo_label.add_theme_color_override("font_outline_color",Color("302246"))
	combo_label.add_theme_constant_override("outline_size",4)
	precision=ui.text(g,"",755,275,15,Color("b9acd0"))
	live_note=ui.text(g,"",50,301,14,ui.MUTED)
	stage_timer=ui.text(g,"",845,334,12,ui.MUTED)
	energy=ui.text(g,"",755,306,15,ui.PURPLE)
	activity=ui.text(g,"",50,322,18,ui.PURPLE)
	toast_panel=ui.card(g,Rect2(50,647,804,42),Color("5a8b9d"))
	toast_panel.z_index=20
	toast_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	toast=ui.text(toast_panel,"",20,9,14,Color("d9fff3"))
	toast.clip_text=true;toast.size.x=764
	course_page=ui.group()
	ui.text(course_page,"아케이드 코스",50,166,35)
	ui.button(course_page,"내 비트 보관함",Rect2(408,166,210,48),g.open_library)
	ui.button(course_page,"직접 비트 만들기  →",Rect2(798,166,306,48),g.start_practice)
	ui.button(course_page,"더블 비트 F / J",Rect2(630,166,156,48),g.start_double_training).add_theme_font_size_override("font_size",14)
	var courses: Array = g.Challenges.courses()
	for i in range(courses.size()):
		var c: Dictionary = courses[i]
		var panel: Panel=ui.card(course_page,Rect2(50+(i%3)*358,233+(i/3)*188,338,173))
		var icon=preload("res://art.gd").new()
		icon.mode="badge"
		icon.badge_kind=str(c.id)
		icon.badge_level=int(c.level)
		icon.tint=[Color("83d9c2"),Color("c9b7f1"),Color("ffbd9e"),Color("ffcf71"),Color("a7cced"),Color("f0b3d3")][i]
		icon.position=Vector2(270,12)
		icon.size=Vector2(50,50)
		panel.add_child(icon)
		ui.text(panel,str(c.tag),18,12,12,ui.PURPLE)
		ui.text(panel,str(c.name),18,38,23)
		ui.text(panel,str(c.description),18,76,14,ui.MUTED)
		var record: Label=ui.text(panel,"",18,102,12,ui.PURPLE)
		course_records.append(record)
		var id: String=str(c.id)
		var start: Button=ui.button(panel,"도전하기  →",Rect2(18,128,302,34),func(): g.start_challenge(id))
		start.add_theme_font_size_override("font_size",14)
	ui.text(course_page,"일반 코스 3웨이브 · 생존은 무제한 · ★ 60% / ★★ 80% / ★★★ 95% · 이 기기에 기록 저장",50,627,14,ui.MUTED)

	library_page=ui.group()
	ui.text(library_page,"내가 만든 여덟 개의 비트.",50,166,35)
	ui.button(library_page,"돌아가기",Rect2(798,166,306,48),g.close_library)
	library_empty=ui.text(library_page,"아직 저장한 리듬이 없어요. 리듬을 만든 뒤 '보관함에 저장'을 눌러봐요.",50,280,20,ui.MUTED)
	for i in range(8):
		var row: Panel=ui.card(library_page,Rect2(50+(i%2)*548,240+(i/2)*90,506,80))
		library_rows.append(row)
		library_labels.append(ui.text(row,"",18,8,17))
		var preview: Control=preload("res://gameplay/pattern_preview.gd").new()
		preview.position=Vector2(18,39)
		preview.size=Vector2(240,25)
		row.add_child(preview)
		library_previews.append(preview)
		var index: int=i
		var use: Button=ui.button(row,"사용",Rect2(278,17,100,46),func(): g.use_saved_pattern(index),true)
		var remove: Button=ui.button(row,"삭제",Rect2(392,17,100,46),func(): g.preferences.delete_pattern(index))
		use.add_theme_font_size_override("font_size",14)
		remove.add_theme_font_size_override("font_size",14)
	ui.text(library_page,"최대 8개 · 이 기기에 저장돼요. 대전 중에는 공격을 만들기 전에 가져올 수 있어요.",50,623,14,ui.MUTED)
	library_open=ui.button(g,"내 비트 가져오기",Rect2(620,280,232,44),g.open_library)
	save_pattern=ui.button(g,"보관함에 저장",Rect2(870,280,232,44),g.save_current_pattern)

	review=ui.group()
	ui.button(review,"R  다시 만들기",Rect2(50,550,290,58),g.retry_recording)
	ui.button(review,"P  미리듣기",Rect2(358,550,290,58),g.preview_pattern)
	ui.button(review,"ENTER  이 비트로 시작  →",Rect2(666,550,438,58),g.confirm_pattern,true)

	stop_preview=ui.button(g,"P  미리듣기 중지",Rect2(50,550,1054,58),g.stop_preview)
	reset_record=ui.button(g,"처음부터 다시",Rect2(870,280,232,44),g.retry_recording)

	summary=ui.group()
	var panel: Panel=ui.card(summary,Rect2(50,237,1054,315))
	summary_panel=panel
	var summary_style=ui.style(Color("19182d"),Color("695487"))
	summary_style.shadow_color=Color(0,0,0,.2)
	summary_style.shadow_size=18
	summary_panel.add_theme_stylebox_override("panel",summary_style)
	result_gloss=preload("res://gameplay/result_gloss.gd").new()
	result_gloss.size=panel.size
	panel.add_child(result_gloss)
	medal_art=preload("res://gameplay/medal.gd").new()
	medal_art.position=Vector2(0,5)
	medal_art.size=Vector2(150,165)
	panel.add_child(medal_art)
	grade=ui.text(panel,"S",0,5,82,Color("fff0c0"))
	grade.size=Vector2(150,160);grade.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;grade.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	grade.add_theme_font_override("font",ui.Design.font("display"))
	medal=ui.text(panel,"",24,171,13,Color("d0b3ff"))
	score_caption=ui.text(panel,"ROUND SCORE",190,16,13,Color("a8a0c3"))
	points=ui.text(panel,"0",190,42,46,Color("ffffff"))
	points.add_theme_font_override("font",ui.Design.font("display"))
	accuracy=ui.text(panel,"정확도 0%",190,107,20,Color("bcb5d1"))
	max_combo=ui.text(panel,"MAX COMBO 0",190,145,18,Color("cfb6ff"))
	chart=preload("res://gameplay/timing_chart.gd").new()
	chart.position=Vector2(680,35)
	chart.size=Vector2(330,100)
	panel.add_child(chart)
	ui.text(panel,"EARLY",680,145,12,Color("b5aec9"))
	ui.text(panel,"PERFECT",810,145,12,Color("b5aec9"))
	ui.text(panel,"LATE",976,145,12,Color("b5aec9"))
	timing_caption=ui.text(panel,"",680,172,13,Color("b5aec9"))
	for i in range(4):
		var color: Color=[Color("72ffe4"),Color("ffdc88"),Color("c4a6ff"),Color("ff719b")][i]
		ui.text(panel,["perfecto!!!","greato!!","nice","water XXXX"][i],28+i*254,219,15,color)
		counts.append(ui.text(panel,"0",28+i*254,247,31,Color("f2efff")))
	footer=ui.text(g,"",50,559,14,ui.MUTED)
	replay=ui.button(g,"같은 비트 다시 도전",Rect2(50,590,268,55),g.replay_last,true)
	advance=ui.button(g,"다음 웨이브  →",Rect2(337,590,268,55),g.next_solo_wave,true)
	course_back=ui.button(g,"연습실로",Rect2(624,590,230,55),func(): g.open_menu("ranker" if not g.ranker_id.is_empty() else "solo"))
	rematch=ui.button(g,"한 판 더!  →",Rect2(50,590,280,55),func(): g.send_packet({"type":"rematch"}),true)

	settings_page=ui.group()
	ui.text(settings_page,"손끝에 맞춰, 편하게.",50,166,35)
	var left: Panel=ui.card(settings_page,Rect2(50,238,506,337))
	ui.text(left,"사운드",24,18,24)
	volume_value=ui.text(left,"",24,68,17,ui.MUTED)
	volume_slider=HSlider.new()
	volume_slider.position=Vector2(24,108)
	volume_slider.size=Vector2(458,32)
	volume_slider.max_value=1
	volume_slider.step=0.05
	volume_slider.value=float(g.preferences.values.volume)
	ui.decorate_slider(volume_slider)
	left.add_child(volume_slider)
	volume_slider.value_changed.connect(func(v):
		g.preferences.values.volume=v
		changed())
	click_button=ui.button(left,"",Rect2(24,166,218,48),func():
		g.preferences.values.metronome=not g.preferences.values.metronome
		changed())
	bpm_select=ui.selector(left,Rect2(260,166,222,48),["80 BPM","100 BPM","120 BPM","140 BPM","160 BPM"])
	bpm_select.select([80,100,120,140,160].find(int(g.preferences.values.bpm)))
	bpm_select.item_selected.connect(func(i):
		g.preferences.values.bpm=[80,100,120,140,160][i]
		changed())
	music_value=ui.text(left,"",24,246,15,ui.MUTED)
	music_slider=HSlider.new();music_slider.position=Vector2(24,282);music_slider.size=Vector2(458,28);music_slider.max_value=1;music_slider.step=.05;music_slider.value=float(g.preferences.values.music_volume)
	ui.decorate_slider(music_slider);left.add_child(music_slider)
	music_slider.value_changed.connect(func(v):g.preferences.values.music_volume=v;changed())
	var right: Panel=ui.card(settings_page,Rect2(578,238,526,337))
	ui.text(right,"입력과 화면",24,18,24)
	key_select=ui.selector(right,Rect2(24,68,478,44),["SPACE","D","F","J","K"])
	key_select.select(["SPACE","D","F","J","K"].find(str(g.preferences.values.key)))
	key_select.item_selected.connect(func(i):
		g.preferences.values.key=["SPACE","D","F","J","K"][i]
		changed())
	offset_value=ui.text(right,"",24,131,15,ui.MUTED)
	offset_slider=HSlider.new()
	offset_slider.position=Vector2(24,163)
	offset_slider.size=Vector2(478,27)
	offset_slider.min_value=-150
	offset_slider.max_value=150
	offset_slider.step=5
	offset_slider.value=int(g.preferences.values.offset_ms)
	ui.decorate_slider(offset_slider)
	right.add_child(offset_slider)
	offset_slider.value_changed.connect(func(v):
		g.preferences.values.offset_ms=int(v)
		changed())
	effects_button=ui.button(right,"",Rect2(24,219,230,49),func():
		g.preferences.values.effects=not g.preferences.values.effects
		changed())
	motion_button=ui.button(right,"",Rect2(272,219,230,49),func():
		g.preferences.values.reduced_motion=not g.preferences.values.reduced_motion
		changed())
	ui.text(settings_page,"입력 보정은 조금씩 바꾸며 연습실에서 확인해봐요. 설정은 이 기기에 자동 저장됩니다.",50,609,15,ui.MUTED)
	ui.button(settings_page,"기본값 복원",Rect2(798,166,306,48),reset_settings)

	pause_panel=ui.group()
	var shade:=ColorRect.new()
	shade.size=Vector2(1152,720)
	shade.color=Color(0.12,0.1,0.18,0.25)
	pause_panel.add_child(shade)
	var p: Panel=ui.card(pause_panel,Rect2(300,230,552,276))
	p.add_theme_stylebox_override("panel",ui.style(Color("211d36"),Color("8e6fb0")))
	ui.text(p,"잠깐, 쉬어갈까?",38,31,33,Color("f1ecff"))
	ui.text(p,"ESC 계속하기 · R 이 구간 다시 시작",38,99,17,Color("c0b5d2"))
	ui.button(p,"ESC  계속하기",Rect2(38,159,476,65),g.toggle_pause,true)
	story_hud=preload("res://gameplay/story_hud.gd").new(g,ui)

func changed() -> void:
	g.apply_preferences()
	g.preferences.save()

func reset_settings() -> void:
	g.preferences.values=g.preferences.DEFAULTS.duplicate()
	volume_slider.value=float(g.preferences.values.volume)
	music_slider.value=float(g.preferences.values.music_volume)
	offset_slider.value=0
	key_select.select(0)
	bpm_select.select(2)
	changed()

func sync() -> void:
	apply_stage_theme(g.stage.active())
	map_ui.sync()
	ranker_ui.sync()
	calibration_ui.sync()
	for nav in g.get_tree().get_nodes_in_group("perfecto_menu_nav"):
		if g.is_ancestor_of(nav) and nav.get_meta("menu_action","")!="전체 화면":
			nav.disabled=g.phase!="lobby"
			nav.modulate=Color(.55,.65,.75,1) if nav.disabled else Color.WHITE
	if g.stage.active() and not g.result.text in g.NAMES: g.result.add_theme_color_override("font_color",Color("f1ecff"))
	var menu: bool=g.phase=="lobby"
	ui.reveal(course_page,menu and ui.page=="arcade")
	ui.reveal(settings_page,menu and ui.page=="settings")
	ui.reveal(library_page,(menu and ui.page=="library") or g.phase=="library")
	library_empty.visible=g.preferences.patterns.is_empty()
	library_open.visible=g.phase=="record" and g.used==0 and not g.key_held
	save_pattern.visible=g.phase=="review"
	for i in range(8):
		library_rows[i].visible=i<g.preferences.patterns.size()
		if i<g.preferences.patterns.size():
			library_labels[i].text=str(g.preferences.patterns[i].name)
			library_previews[i].notes=g.preferences.patterns[i].notes
			library_previews[i].queue_redraw()
	ui.reveal(review,g.phase=="review")
	stop_preview.visible=g.phase=="preview"
	reset_record.visible=(g.phase=="record" and g.used>0) or g.phase=="timeout"
	touch_input.visible=not g.is_double() and (g.phase=="record" or (g.phase=="play" and (g.practice or g.slot!=g.attacker))) and not g.paused
	for pad in double_touch:pad.visible=g.is_double() and (g.phase=="record" or (g.phase=="play" and (g.practice or g.slot!=g.attacker))) and not g.paused
	emotes.visible=not g.practice and not g.opponent_left and g.phase in ["room","waiting","result"]
	emotes.position.y=590 if g.phase=="result" else 124
	var playing: bool=g.phase=="play" and not g.paused
	var mine: bool=g.practice or g.slot!=g.attacker
	combo_label.visible=playing or g.phase in ["record","review","preview"]
	precision.visible=playing
	live_note.visible=playing and mine and g.judgment_age<0.8 and g.last_hit_offset!=null
	stage_timer.visible=not g.practice and g.phase in ["record","review","preview"]
	if stage_timer.visible:
		var remaining:=maxi(0,ceili(g.stage_deadline-g.now()))
		stage_timer.text="%s까지 %d초"%["전송" if g.phase!="record" else "제작",remaining]
		stage_timer.add_theme_color_override("font_color",Color("dc4d65") if remaining<10 else ui.MUTED)
	energy.visible=playing and g.solo_id=="survival"
	activity.visible=g.phase=="waiting"
	combo_label.text="%d COMBO"%int(g.combo if mine else g.spectator_combo)
	if g.phase in ["record","review"]:combo_label.text="%d / 8"%int(g.used)
	elif g.phase=="preview":combo_label.text="LISTEN"
	if g.phase=="record" and g.key_held:
		var pending:=mini(8-g.used,maxi(1,ceili(g.now()-g.origin-g.down)))
		combo_label.text="%d + %d / 8"%[g.used,pending]
	var resolved_count: int=g.live_judgments.size() if mine else g.spectator_resolved
	precision.text="%d / %d NOTES"%[resolved_count,g.notes.size()]
	live_note.text=""
	if g.last_hit_offset!=null:
		var offset: float=g.last_hit_offset
		live_note.text="JUST RIGHT" if absf(offset)<=8 else "EARLY  %dms"%int(-offset) if offset<0 else "LATE  %dms"%int(offset)
	energy.text="ENERGY  %d%%"%int(g.energy)
	energy.add_theme_color_override("font_color",Color("ff719b") if g.energy<30 else Color("b8a3ff"))
	activity.text="공격 준비   %d / 8"%int(g.activity_units)
	toast.visible=g.now()<g.emote_until
	toast_panel.visible=toast.visible
	toast.text=g.emote_text
	if g.phase in ["review","preview"]:
		g.result.visible=true
		g.hint.visible=false
		ui.role.visible=true
		ui.role.text="01 / CHECK YOUR BEAT   ·   듣고, 다듬고, 보내기"
		ui.key_hint.visible=false
		ui.tips.visible=false
		g.result.position.y=250
	if g.phase=="play":
		ui.tips.text="%s  리듬 입력   ·   %s"%[("F 위 / J 아래" if g.is_double() else "SPACE / F / J" if not g.ranker_id.is_empty() else str(g.preferences.values.key)),"ESC 잠시 멈춤" if g.practice else "타이밍을 맞춰 연속 콤보!"]
	elif g.phase=="record":
		ui.tips.text="%s  리듬 입력   ·   8개를 채운 뒤 미리듣기로 확인해봐"%("F 위 / J 아래" if g.is_double() else "SPACE / F / J" if not g.ranker_id.is_empty() else str(g.preferences.values.key))
	if g.phase=="play" and not g.ranker_id.is_empty():ui.role.text="RANKER / %s · LV.%d"%["DOUBLE" if g.ranker_kind=="double" else "ONE BEAT",int(g.Ranker.find(g.ranker_id).level)+(2 if g.ranker_kind=="double" else 0)]
	if g.phase=="play" and not g.map_id.is_empty():ui.role.text="MAP / %s  ·  %s"%["PRACTICE" if g.map_training else "CHALLENGE",str(g.Maps.find(g.map_id).skill)]
	ui.key_hint.text="" if g.is_double() else "SPACE / F / J" if not g.ranker_id.is_empty() else str(g.preferences.values.key)
	ui.key_hint.position.x=870;ui.key_hint.size.x=232;ui.key_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	ui.key_hint.position.y=566
	if g.phase=="play" and not mine: ui.key_hint.hide()
	var report_ready: bool=g.phase=="result" and not g.last_report.is_empty()
	ui.reveal(summary,report_ready)
	footer.visible=report_ready
	replay.visible=report_ready and g.practice
	advance.visible=report_ready and g.practice and ((not g.solo_id.is_empty() and not g.match_finished) or (not g.map_id.is_empty() and not g.Maps.next_id(g.map_id).is_empty()))
	advance.text="다음 맵 연습 →" if not g.map_id.is_empty() and g.map_training else "다음 맵 →" if not g.map_id.is_empty() else "다음 웨이브 →"
	advance.disabled=not g.map_id.is_empty() and not g.map_training and not g.Maps.unlocked(g.Maps.next_id(g.map_id),g.preferences.records)
	replay.text=("같은 구간 다시 연습" if g.ranker_training and (g.ranker_seek>0 or g.ranker_end>0) else "같은 곡 다시 연습" if g.ranker_training else "같은 곡 다시 도전") if not g.ranker_id.is_empty() else "같은 맵 다시 도전" if not g.map_id.is_empty() else "같은 비트 다시 도전"
	course_back.text="랭커 아레나" if not g.ranker_id.is_empty() else "맵 선택" if not g.map_id.is_empty() else "연습실로"
	course_back.visible=report_ready and g.practice
	rematch.visible=report_ready and not g.practice and g.match_finished and not g.opponent_left
	if rematch.visible:
		rematch.disabled=g.slot in g.rematch_votes
		rematch.text="재대전 준비 %d / 2"%g.rematch_votes.size() if not g.rematch_votes.is_empty() else "한 판 더!  →"
	if report_ready:
		var r: Dictionary=g.last_report
		score_caption.text=("PRACTICE SCORE" if g.ranker_training else "RANKER SCORE") if not g.ranker_id.is_empty() else "MAP SCORE" if not g.map_id.is_empty() else "TOTAL SCORE" if g.practice and not g.solo_id.is_empty() and g.match_finished else "ROUND SCORE"
		g.result.position.y=175
		g.result.add_theme_font_size_override("font_size",32)
		g.hint.visible=false
		g.tally.visible=not g.practice
		grade.text=str(r.grade)
		grade.add_theme_font_size_override("font_size",54 if str(r.grade).length()>1 else 82)
		grade.add_theme_color_override("font_color",{"EX":Color("fff0af"),"SS":Color("80faff"),"F":Color("ff719b"),"S":Color("ffd477"),"A":Color("6be8c7"),"B":Color("b79cff"),"C":Color("91c6ff"),"D":Color("ff9caa")}.get(str(r.grade),Color("b79cff")))
		medal_art.grade=str(r.grade)
		medal_art.moving=not g.preferences.values.reduced_motion
		var signature: String=str(r.points)+str(r.counts)+str(g.solo_wave)+str(g.turn_index)
		if signature!=summary_signature:
			summary_signature=signature
			result_gloss.restart(not g.preferences.values.reduced_motion)
			if score_tween and score_tween.is_valid(): score_tween.kill()
			if g.preferences.values.reduced_motion: set_points_counter(float(r.points))
			else:
				set_points_counter(0)
				score_tween=g.create_tween().set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
				score_tween.tween_method(set_points_counter,0.0,float(r.points),.55)
				medal_art.pivot_offset=Vector2(75,80)
				medal_art.scale=Vector2(.75,.75)
				medal_art.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(medal_art,"scale",Vector2.ONE,.45)
		accuracy.text="정확도 %.1f%%"%float(r.accuracy)
		max_combo.text="MAX COMBO  %d"%int(r.max_combo)
		medal.text="ALL PERFECT" if r.all_perfect else "FULL COMBO" if r.full_combo else "KEEP GROOVING"
		for i in range(4): counts[i].text=str(r.counts[i])
		chart.offsets=r.offsets
		chart.judgments=r.judgments
		chart.queue_redraw()
		var offsets: Array=r.offsets.filter(func(x): return x!=null)
		var mean:=0.0
		for v in offsets: mean+=float(v)
		mean/=maxi(1,offsets.size())
		timing_caption.text="입력 기록 없음" if offsets.is_empty() else "평균 %+.1fms · 롱 노트는 큰 오차 기준"%mean
		footer.text=g.reward_text if not g.reward_text.is_empty() else ("내 수비 결과" if g.last_report_mine else "상대의 수비 결과")+"   ·   추가 입력 %d회 / -%d점"%[int(r.extra),int(r.extra)*200]
		if r.has("warning"): footer.text=str(r.warning)
		if g.practice and g.new_best: footer.text="NEW BEST!  최고 기록을 이 기기에 저장했어요." if g.preferences.persist_ok else "NEW BEST!  브라우저 저장이 차단되어 이번 창에서만 유지돼요."
		if not g.map_id.is_empty():
			var stars: int=g.Maps.stars(float(r.accuracy))
			footer.text="연습 완료 · 배속/가이드 연습은 기록과 해금에 반영하지 않아요." if g.map_training else "★".repeat(stars)+"☆".repeat(3-stars)+"   ·   "+("NEW BEST!  ·  " if g.new_best else "")+(g.Story.ending(g.map_id) if stars>0 else "정확도 60%부터 클리어 · 느린 연습으로 먼저 익혀봐.")
			if not g.map_training and not g.preferences.persist_ok:footer.text="저장이 차단되어 기록과 해금은 이번 창에서만 유지돼요."

		if not g.ranker_id.is_empty():
			footer.text="구간 연습 완료 · 정식 기록에 반영하지 않아요." if g.ranker_training else ("NEW BEST! · " if g.new_best else "")+"%s / 엄격 판정 · 75%% 클리어 · %s"%["DOUBLE" if g.ranker_kind=="double" else "ONE BEAT",g.reward_text if not g.reward_text.is_empty() else "로컬 최고 기록 저장"]
		ui.reward_shop.visible=not g.practice and g.match_finished
		ui.reward_shop.position=Vector2(355,590)
		g.next_button.position=Vector2(50,590)
	else:
		summary_signature=""
		g.result.add_theme_font_size_override("font_size",34)
		g.next_button.position=Vector2(50,590)
	var courses: Array=g.Challenges.courses()
	for i in range(course_records.size()):
		var record: Dictionary=g.preferences.records.get(g.Challenges.record_id(str(courses[i].id)),{})
		course_records[i].text="아직 기록이 없어요 · 첫 도전!" if record.is_empty() else "%s  %s점  ·  %.1f%%"%["★".repeat(int(record.get("stars",0))),str(record.points),float(record.accuracy)]
	volume_slider.set_value_no_signal(float(g.preferences.values.volume))
	music_slider.set_value_no_signal(float(g.preferences.values.music_volume))
	offset_slider.set_value_no_signal(int(g.preferences.values.offset_ms))
	volume_value.text="볼륨 %d%%"%int(float(g.preferences.values.volume)*100)
	offset_value.text="입력 보정 %+.0fms   (- 빠르게 / + 늦게)"%float(g.preferences.values.offset_ms)
	click_button.text="메트로놈 ON" if g.preferences.values.metronome else "메트로놈 OFF"
	effects_button.disabled=bool(g.preferences.values.reduced_motion)
	effects_button.text="효과 쉬는 중" if g.preferences.values.reduced_motion else "입자 효과 ON" if g.preferences.values.effects else "입자 효과 OFF"
	motion_button.text="움직임 줄이기 ON" if g.preferences.values.reduced_motion else "움직임 줄이기 OFF"
	pause_panel.visible=g.paused
	if g.paused:
		combo_label.hide()
		precision.hide()
	if story_hud:story_hud.sync()
	music_value.text="곡 배경음악  %d%%"%int(float(g.preferences.values.music_volume)*100)

func apply_stage_theme(active: bool) -> void:
	if theme_ready and theme_stage_last==active: return
	theme_ready=true
	theme_stage_last=active
	if stage_styles.is_empty():
		stage_styles={"normal":ui.style(Color("15233b"),Color("344e70")),"hover":ui.style(Color("213e5a"),Color("8bdcff")),"pressed":ui.style(Color("334d73"),Color("b99cff")),"disabled":ui.style(Color("121c2d"),Color("2c3b50")),"primary":ui.style(Color("68ffe0"),Color("c0fff1")),"primary_hover":ui.style(Color("9affec"),Color("d6fff5")),"primary_pressed":ui.style(Color("52cbb4"),Color("93fff0"))}
		light_styles=stage_styles
	for nav in g.get_tree().get_nodes_in_group("perfecto_menu_nav"):
		if g.is_ancestor_of(nav): nav.visible=not active
	for button in g.get_tree().get_nodes_in_group("perfecto_buttons"):
		if not g.is_ancestor_of(button): continue
		var styles: Dictionary=stage_styles if active else light_styles
		button.add_theme_stylebox_override("normal",styles.primary if button.get_meta("primary",false) else styles.normal)
		for state in ["hover","pressed","disabled"]: button.add_theme_stylebox_override(state,styles["primary_"+state] if button.get_meta("primary",false) and state in ["hover","pressed"] else styles[state])
		button.add_theme_color_override("font_color",Color("152c32") if button.get_meta("primary",false) else ui.INK)
		button.add_theme_color_override("font_hover_color",Color("152c32") if button.get_meta("primary",false) else ui.INK)
		button.add_theme_color_override("font_pressed_color",Color("152c32") if button.get_meta("primary",false) else ui.INK)
		button.add_theme_color_override("font_disabled_color",Color("77718b") if active else ui.MUTED)
	ui.main_exit.text="나가기" if active else "메인으로"
	ui.main_exit.position=Vector2(978,24) if active else Vector2(964,642)
	ui.main_exit.size=Vector2(126,44) if active else Vector2(140,44)
	g.title.add_theme_color_override("font_color",Color("aafbea") if active else ui.MINT)
	g.status.add_theme_color_override("font_color",Color("b9b3cc") if active else ui.MUTED)
	g.tally.add_theme_color_override("font_color",Color("e9dcff") if active else ui.PURPLE)
	ui.role.add_theme_color_override("font_color",Color("b8a3ff") if active else ui.PURPLE)
	ui.budget.add_theme_color_override("font_color",Color("ffb5c4") if active else ui.MINT)
	ui.tips.add_theme_color_override("font_color",Color("a69dbd") if active else ui.MUTED)
	ui.key_hint.add_theme_color_override("font_color",Color("ddfff7") if active else ui.INK)
	activity.add_theme_color_override("font_color",Color("bba1f1") if active else ui.PURPLE)
	live_note.add_theme_color_override("font_color",Color("c4b8d9") if active else ui.MUTED)
	footer.add_theme_color_override("font_color",Color("b5aec9") if active else ui.MUTED)
	g.hint.add_theme_color_override("font_color",Color("a9a0bf") if active else ui.MUTED)
	toast.add_theme_color_override("font_color",Color("e1c7ff") if active else ui.PURPLE)
	if not active:g.result.add_theme_color_override("font_color",ui.INK)
	g.result.add_theme_constant_override("outline_size",3 if active else 0)
	g.result.add_theme_color_override("font_outline_color",Color("21172d"))

func set_points_counter(value: float) -> void:
	points.text=str(roundi(value))
