extends RefCounted
const Design=preload("res://gameplay/ui_theme.gd")
const Ranker=preload("res://gameplay/ranker.gd")
var game_ref: WeakRef
var ui_ref: WeakRef
var g: Control:
	get:return game_ref.get_ref()
var ui: RefCounted:
	get:return ui_ref.get_ref()
var page: Control
var selected:="r01"
var kind:="one"
var difficulty:="hard"
var difficulty_tabs:Array=[]
var timing_info:Label
var board_request_key:=""
var board_mode:=false
var signature:=""
var cards:Array=[]
var levels:Array=[]
var card_records:Array=[]
var tabs:Array=[]
var detail:Panel
var board:Panel
var title:Label
var subtitle:Label
var facts:Label
var best:Label
var power:Label
var board_text:Label
var preview:Control
var audition_music:Node
var audition_button:Button
var audition_id:=""
var audition_start:=0.0
var audition_end:=0.0
var auditioning:=false
var scroll_select:OptionButton
var speed:OptionButton
var section_select:OptionButton
var loop_toggle:CheckButton
var practice_ranges:Array=[]
var practice_song:=""
var play:Button
var train:Button
var board_button:Button
var transition:Panel
var transition_title:Label
var transition_caption:Label
var song_status:Label
var board_at:=-10.0
func _init(game:Control,base:RefCounted)->void:game_ref=weakref(game);ui_ref=weakref(base)
func build()->void:
	page=ui.group()
	ui.text(page,"RHYTHM RE:FORM / NEW ARRANGEMENT",50,123,12,Design.MINT).add_theme_font_override("font",Design.font("display"))
	ui.text(page,"RANKER ARENA",48,149,38).add_theme_font_override("font",Design.font("display"))
	power=ui.text(page,"",50,203,14,Design.MUTED)
	for i in range(2):
		var value:String=["one","double"][i]
		var tab:Button=ui.button(page,["ONE BEAT / 한 줄","DOUBLE / 두 줄"][i],Rect2(706+i*204,153,194,46),func():kind=value;refresh_board())
		tab.add_theme_font_size_override("font_size",16);tabs.append(tab)
	for i in range(3):
		var value:String=Ranker.DIFFICULTIES[i]
		var tier:Button=ui.button(page,value.to_upper(),Rect2(525+i*101,207,94,32),func():difficulty=value;refresh_board())
		tier.add_theme_font_size_override("font_size",12);difficulty_tabs.append(tier)
	ui.button(page,"판정 보정",Rect2(846,207,126,32),func():ui.page="calibration").add_theme_font_size_override("font_size",13)
	board_button=ui.button(page,"기록판",Rect2(984,207,120,32),func():board_mode=not board_mode;refresh_board());board_button.add_theme_font_size_override("font_size",13)
	for i in range(4):
		var song:Dictionary=Ranker.catalog()[i];var id:String=song.id
		var tile:Button=ui.button(page,"",Rect2(50,248+i*99,455,88),func():selected=id;refresh_board())
		var accent:=Color(str(song.color))
		var cover:=preload("res://gameplay/ranker_cover.gd").new();cover.position=Vector2(13,10);cover.size=Vector2(66,66);cover.index=i;cover.tint=accent;tile.add_child(cover)
		ui.text(tile,str(song.title),96,12,21,Design.WHITE).add_theme_font_override("font",Design.font("display"))
		card_records.append(ui.text(tile,"",96,48,13,Design.MUTED))
		var badge:Label=ui.text(tile,"LV.%d"%(int(song.level)+(2 if kind=="double" else 0)),365,16,16,accent);badge.add_theme_font_override("font",Design.font("display"));levels.append(badge)
		cards.append(tile)
	detail=ui.card(page,Rect2(525,248,579,388),Color("667891"))
	title=ui.text(detail,"",24,18,29);title.add_theme_font_override("font",Design.font("display"))
	subtitle=ui.text(detail,"",24,60,15,Design.MUTED)
	facts=ui.text(detail,"",24,95,13,Design.VIOLET)
	preview=preload("res://gameplay/pattern_preview.gd").new();preview.position=Vector2(24,130);preview.size=Vector2(347,34);detail.add_child(preview)
	audition_music=preload("res://gameplay/story_music.gd").new();g.add_child(audition_music)
	audition_button=ui.button(detail,"♫ 곡 미리듣기",Rect2(389,130,166,34),audition)
	audition_button.add_theme_font_size_override("font_size",13)
	audition_button.tooltip_text="첫 드롭부터 18초를 들어봐요. 박자 그림은 첫 6초이며, 다시 누르면 멈춰요."
	best=ui.text(detail,"",24,176,18,Design.MINT)
	timing_info=ui.text(detail,"",24,209,12,Design.MUTED)
	timing_info.size=Vector2(531,38);timing_info.clip_text=true
	loop_toggle=CheckButton.new();loop_toggle.text="선택 구간 반복"
	loop_toggle.position=Vector2(20,245);loop_toggle.size=Vector2(214,29)
	loop_toggle.add_theme_font_size_override("font_size",13)
	loop_toggle.add_theme_color_override("font_color",Design.MINT)
	loop_toggle.tooltip_text="연습에서만 적용돼요. 같은 구간을 카운트다운과 함께 반복하며 기록·보상에는 반영되지 않아요."
	detail.add_child(loop_toggle)
	ui.text(detail,"쉼표도 리듬 · 구간을 느리게 익혀요",260,251,12,Design.MUTED)
	speed=ui.selector(detail,Rect2(24,278,128,40),["0.50x","0.75x","1.00x"]);speed.select(1)
	section_select=ui.selector(detail,Rect2(166,278,205,40),["전체 곡 연습","SECTION 01","SECTION 02","SECTION 03","SECTION 04"])
	section_select.fit_to_longest_item=false
	section_select.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	section_select.get_popup().max_size=Vector2i(560,420)
	section_select.item_selected.connect(func(_i):signature="";stop_audition())
	speed.tooltip_text="연습 재생 속도예요. 기록 도전은 항상 원래 속도로 진행해요."
	scroll_select=ui.selector(detail,Rect2(389,278,166,40),["노트 0.8x","노트 1.0x","노트 1.2x","노트 1.4x"])
	scroll_select.select(maxi(0,[.8,1.0,1.2,1.4].find(float(g.preferences.values.ranker_scroll))))
	scroll_select.tooltip_text="스크롤 속도만 바뀌며 곡과 판정에는 영향을 주지 않아요."
	scroll_select.item_selected.connect(func(i):g.preferences.values.ranker_scroll=[.8,1.0,1.2,1.4][i];g.preferences.save())
	play=ui.button(detail,"기록 도전 →",Rect2(24,332,252,44),func():g.start_ranker(selected,kind,false,1.0,0.0,0.0,difficulty),true)
	train=ui.button(detail,"구간 연습",Rect2(294,332,261,44),practice_selected)
	board=ui.card(page,Rect2(525,248,579,388),Color("667891"))
	ui.text(board,"LEADERBOARD / TOP 10",24,20,22,Design.MINT).add_theme_font_override("font",Design.font("display"))
	board_text=ui.text(board,"",24,70,16,Design.WHITE)
	board_text.size=Vector2(531,290);board_text.clip_text=true
	ui.text(page,"↑ ↓ 곡   ← → 종목   Q E 난이도   ENTER 도전   P 연습   G 기록판",50,661,13,Design.MUTED)
	song_status=ui.text(g,"",50,548,13,Design.VIOLET)
	song_status.size=Vector2(792,24);song_status.clip_text=true
	transition=ui.card(g,Rect2(424,168,292,60),Design.VIOLET);transition.z_index=2;transition.mouse_filter=Control.MOUSE_FILTER_IGNORE
	transition_title=ui.text(transition,"",14,8,19,Design.MINT);transition_title.add_theme_font_override("font",Design.font("display"))
	transition_caption=ui.text(transition,"",14,36,11,Design.MUTED)
	transition.hide()
func stop_audition()->void:
	if audition_music:audition_music.stop()
	auditioning=false;audition_id=""
	if audition_button:audition_button.text="♫ 곡 미리듣기"
func audition()->void:
	if auditioning:stop_audition();return
	var song:=Ranker.find(selected)
	rebuild_practice_options()
	var bounds:=preview_bounds(song)
	audition_id=selected;auditioning=true
	audition_start=float(song.audio_offset)+float(bounds.t)
	audition_end=float(song.audio_offset)+minf(float(bounds.end),float(bounds.t)+18)
	audition_music.prepare(selected,1,0,"ranker")
	audition_music.volume(float(g.preferences.values.volume),float(g.preferences.values.music_volume))
	audition_music.start(audition_start)
	audition_button.text="■ 미리듣기 중지"
func practice_selected()->void:
	rebuild_practice_options()
	var bounds:Dictionary=practice_ranges[clampi(section_select.selected,0,practice_ranges.size()-1)]
	g.start_ranker(selected,kind,true,[.5,.75,1.0][speed.selected],float(bounds.t),float(bounds.end),difficulty,loop_toggle.button_pressed)
func rebuild_practice_options()->void:
	if practice_song==selected and not practice_ranges.is_empty():return
	practice_song=selected
	var song:=Ranker.find(selected)
	var section_bars:=maxi(1,int(song.get("section_bars",12)))
	practice_ranges=[{"t":0.0,"end":0.0}]
	section_select.clear();section_select.add_item("전체 곡 연습")
	for section in range(4):
		var index:=section*section_bars
		practice_ranges.append({"t":float(song.bars[index].t),"end":float(song.bars[index+section_bars].t) if index+section_bars<song.bars.size() else float(song.duration)})
		section_select.add_item("SECTION %02d"%(section+1))
	var phrases:Array=song.get("phrases",[])
	for i in range(phrases.size()):
		var phrase:Dictionary=phrases[i]
		practice_ranges.append({"t":float(phrase.t),"end":float(phrase.end)})
		section_select.add_item("%02d · %s"%[i+1,str(phrase.get("technique",phrase.get("label","PHRASE")))])
	section_select.select(0)
func preview_bounds(song:Dictionary)->Dictionary:
	if section_select.selected>0 and section_select.selected<practice_ranges.size():return practice_ranges[section_select.selected]
	return {"t":float(song.bars[int(song.get("section_bars",12))].t),"end":float(song.duration)}
func refresh_board()->void:
	g.ranker_waiting.clear()
	signature=""
	board_request_key=Ranker.board_id(selected,kind,difficulty) if board_mode else ""
	request_board_if_ready()
func request_board_if_ready()->void:
	if board_request_key.is_empty() or not board_mode or g.now()-board_at<.4:return
	board_request_key="";board_at=g.now()
	g.queue_request({"type":"ranker_board","id":selected,"kind":kind,"difficulty":difficulty,"revision":Ranker.revision(selected)})
func handle_input(event:InputEventKey)->bool:
	if ui.page!="ranker" or not page.visible or not event.pressed or speed.get_popup().visible or section_select.get_popup().visible or scroll_select.get_popup().visible:return false
	var index:=int(selected.substr(1))-1
	match event.keycode:
		KEY_UP:selected="r%02d"%(posmod(index-1,4)+1);refresh_board();return true
		KEY_DOWN:selected="r%02d"%(posmod(index+1,4)+1);refresh_board();return true
		KEY_LEFT,KEY_RIGHT:kind="double" if kind=="one" else "one";refresh_board();return true
		KEY_Q,KEY_E:
			difficulty=Ranker.DIFFICULTIES[posmod(Ranker.DIFFICULTIES.find(difficulty)+(-1 if event.keycode==KEY_Q else 1),3)];refresh_board();return true
		KEY_ENTER:g.start_ranker(selected,kind,false,1.0,0.0,0.0,difficulty);return true
		KEY_P:practice_selected();return true
		KEY_G:board_mode=not board_mode;refresh_board();return true
		KEY_ESCAPE:g.open_menu("home");return true
	return false
func sync()->void:
	ui.reveal(page,g.phase=="lobby" and ui.page=="ranker")
	if page.visible:request_board_if_ready()
	if auditioning:
		if not page.visible or audition_id!=selected:stop_audition()
		elif not audition_music.failure().is_empty():
			stop_audition();audition_button.text="↻ 미리듣기 재시도"
		elif audition_music.time()>=audition_end:stop_audition()
		else:
			audition_music.volume(float(g.preferences.values.volume),float(g.preferences.values.music_volume))
			audition_button.text="불러오는 중…" if audition_music.loading() else "■ 미리듣기 중지"

	song_status.visible=g.phase=="play" and not g.ranker_id.is_empty() and not g.paused and g.play_time()>=0
	transition.visible=false
	if song_status.visible:
		var now:float=g.play_time()+g.ranker_seek
		var song:=Ranker.find(g.ranker_id);var bar:=Ranker.section(g.ranker_id,now)
		var section_bars:=maxi(1,int(song.get("section_bars",12)))
		var elapsed:float=now-float(song.bars[int(bar.section)*section_bars].t)
		transition.visible=elapsed>=0 and elapsed<1.4
		if transition.visible:
			transition_title.text="%s · %d BPM"%[["IGNITION","OVERDRIVE","SHIFT","FINAL BURST"][int(bar.section)],int(bar.bpm)]
			transition_caption.text="SECTION %02d / %s / %s"%[int(bar.section)+1,g.ranker_difficulty.to_upper(),"DOUBLE" if g.ranker_kind=="double" else "ONE BEAT"]
			transition.modulate.a=1 if g.preferences.values.reduced_motion else clampf((1.4-elapsed)/.4,0,1)
		var upcoming:Dictionary={}
		var next_section:=(int(bar.section)+1)*section_bars
		if next_section<song.bars.size():upcoming=song.bars[next_section]
		var warning:bool=not upcoming.is_empty() and float(upcoming.t)-now<2
		var phrase_index:=-1
		var phrases:Array=song.get("phrases",[])
		for i in range(phrases.size()):
			if float(phrases[i].t)>now:break
			phrase_index=i
		var phrase_text:="SECTION %02d"%(int(bar.section)+1)
		var next_text:=""
		if phrase_index>=0:
			var phrase:Dictionary=phrases[phrase_index]
			phrase_text="%02d · %s"%[phrase_index+1,str(phrase.get("technique",phrase.get("label","")))]
			if phrase_index+1<phrases.size() and float(phrase.end)-now<4*60.0/float(bar.bpm):
				next_text="  → 다음: %s"%str(phrases[phrase_index+1].get("technique",""))
		if warning:next_text="  → %d BPM · %d박 뒤"%[int(upcoming.bpm),maxi(1,ceili((float(upcoming.t)-now)*float(bar.bpm)/60))]
		song_status.text="%d BPM · %d/4  |  %s%s"%[int(bar.bpm),int(bar.beats),phrase_text,next_text]
		if g.ranker_loop:song_status.text="반복 %d · 최고 %.1f%%  |  "%[g.ranker_loop_count,g.ranker_loop_best]+song_status.text
		song_status.add_theme_color_override("font_color",Color("ffbd73") if warning else Design.VIOLET)
	if not page.visible:signature="";return
	rebuild_practice_options()
	power.text="V%d · %s · ONE %d / DOUBLE %d POWER"%[Ranker.revision(selected),difficulty.to_upper(),Ranker.power(g.preferences.records,"one",difficulty),Ranker.power(g.preferences.records,"double",difficulty)]
	var key:=selected+kind+difficulty+str(section_select.selected)+str(g.preferences.records.hash())+str(board_mode)+str(g.ranker_boards.hash())+str(g.ranker_waiting.is_empty())+str(g.now()-board_at>12)+str(g.profile.get("id",""))+str(g.accounts_enabled)
	if key==signature:return
	signature=key
	detail.visible=not board_mode;board.visible=board_mode
	board_button.text="곡 정보" if board_mode else "기록판"
	var scroll_index:=maxi(0,[.8,1.0,1.2,1.4].find(float(g.preferences.values.ranker_scroll)))
	if scroll_select.selected!=scroll_index:scroll_select.select(scroll_index)
	var song:=Ranker.find(selected)
	title.text=str(song.title);title.add_theme_color_override("font_color",Color(str(song.color)))
	subtitle.text="%s / %s / %s / LV.%d"%[str(song.subtitle),difficulty.to_upper(),"DOUBLE" if kind=="double" else "ONE BEAT",Ranker.level(selected,kind,difficulty)]
	var duration:=ceili(float(song.duration))
	facts.text="%d → %d BPM · %d:%02d · %d NOTES"%[int(song.bpms[0]),int(song.bpms.max()),duration/60,duration%60,Ranker.source_chart(selected,kind,difficulty).size()]
	var bounds:=preview_bounds(song)
	var preview_start:float=bounds.t
	preview.notes=Ranker.chart(selected,kind,preview_start,minf(preview_start+6,float(bounds.end)),difficulty);preview.queue_redraw()
	section_select.tooltip_text=section_select.get_item_text(section_select.selected)+" · 짧은 프레이즈를 골라 반복하면 쉼표와 엇박을 익히기 좋아요."
	audition_button.tooltip_text="선택 구간부터 최대 18초를 들어봐요. 전체 곡을 선택하면 첫 드롭부터 시작해요."
	var record:Dictionary=g.preferences.records.get(Ranker.record_id(selected,kind,difficulty),{})
	best.text="첫 기록에 도전해봐" if record.is_empty() else "%s  %.1f%%  /  MAX %d COMBO"%[str(record.grade),float(record.accuracy),int(record.max_combo)]
	if bool(record.get("all_perfect",false)):best.text+=" · AP 달성"
	elif bool(record.get("full_combo",false)):best.text+=" · FC 달성"
	var windows:=Ranker.windows(difficulty)
	timing_info.text="%s · %.0f / %.0f / %.0fms · 75%% 클리어\n빈 박 추가 입력 -%d점 · 연습은 기록·보상 제외"%[difficulty.to_upper(),windows[0]*1000,windows[1]*1000,windows[2]*1000,Ranker.EXTRA_PENALTY]
	for i in range(3):
		var selected_tier:bool=Ranker.DIFFICULTIES[i]==difficulty
		var accent:Color=[Design.MINT,Color("ffbd73"),Color("ff719b")][i]
		difficulty_tabs[i].add_theme_stylebox_override("normal",ui.style(Color("293246") if selected_tier else Design.PANEL,accent if selected_tier else Design.LINE,2 if selected_tier else 1))
		difficulty_tabs[i].add_theme_color_override("font_color",accent if selected_tier else Design.MUTED)
	play.disabled=not g.ranker_waiting.is_empty();train.disabled=play.disabled;play.text="준비 중…" if play.disabled else "글로벌 도전 →" if not g.profile.is_empty() and g.accounts_enabled else "기기 기록 도전 →"
	for i in range(2):
		tabs[i].add_theme_stylebox_override("normal",ui.style(Color("254252") if i==int(kind=="double") else Design.PANEL,Design.MINT if i==int(kind=="double") else Design.LINE,2 if i==int(kind=="double") else 1))
	for i in range(4):
		var item:Dictionary=Ranker.catalog()[i];levels[i].text="LV.%d"%Ranker.level(item.id,kind,difficulty);var r:Dictionary=g.preferences.records.get(Ranker.record_id(item.id,kind,difficulty),{})
		card_records[i].text="%s · %d BPM · NO RECORD"%[str(item.subtitle),int(item.bpms.max())] if r.is_empty() else "%s · %.1f%% · %d COMBO"%[str(r.grade),float(r.accuracy),int(r.max_combo)]
		if bool(r.get("all_perfect",false)):card_records[i].text+=" · AP"
		elif bool(r.get("full_combo",false)):card_records[i].text+=" · FC"
		cards[i].add_theme_stylebox_override("normal",ui.style(Color("213247") if item.id==selected else Design.PANEL,Color(str(item.color)) if item.id==selected else Design.LINE,2 if item.id==selected else 1))
	var data:Dictionary=g.ranker_boards.get(Ranker.board_id(selected,kind,difficulty),{})
	if data.is_empty():board_text.text=("연결을 확인해 주세요." if g.now()-board_at>12 else "연결 중…")+"\n\n내 로컬 기록\n"+best.text
	elif not data.get("enabled",false):board_text.text="글로벌 기록판은 준비 중이에요.\n지금은 기기 기록으로 도전해요.\n\n내 로컬 기록\n"+best.text
	else:
		var lines:Array=[]
		for i in range(mini(10,data.rows.size())):
			var row:Dictionary=data.rows[i];lines.append("%02d  %s  ·  %s %.1f%%"%[i+1,str(row.name).left(12),str(row.grade),float(row.accuracy)])
		board_text.text="\n".join(lines) if not lines.is_empty() else "아직 등록된 기록이 없어요.\n첫 번째 랭커가 되어봐!"
		if data.get("own") is Dictionary:board_text.text+="\n\n내 기록 · %s %.1f%%"%[str(data.own.grade),float(data.own.accuracy)]
		elif g.profile.is_empty():board_text.text+="\n\n로그인하면 정식 기록을 등록할 수 있어요."
