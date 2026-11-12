extends RefCounted
## Incremental phrase feedback. Final results still use the canonical scorer.
var game_ref:WeakRef
var note_rows:Array[int]=[]
var g:Control:
	get:return game_ref.get_ref()

func _init(game:Control)->void:game_ref=weakref(game)

func reset()->void:
	note_rows.clear()
	g.ranker_phrase_live.clear()
	g.ranker_phrase_notice=""
	g.ranker_phrase_notice_until=-1
	if g.ranker_id.is_empty():return
	var song:Dictionary=g.Ranker.find(g.ranker_id)
	var end:float=g.ranker_end if g.ranker_end>0 else float(song.duration)
	var phrases:Array=song.get("phrases",[])
	for index in range(phrases.size()):
		var phrase:Dictionary=phrases[index]
		if float(phrase.end)<=g.ranker_seek+.000001 or float(phrase.t)>=end-.000001:continue
		g.ranker_phrase_live.append({"index":index,"t":float(phrase.t),"end":float(phrase.end),"label":str(phrase.label),"technique":str(phrase.technique),"notes":0,"judged":0,"points":0.0,"maximum":0.0,"counts":[0,0,0,0],"extra":0,"closed":false,"complete":g.ranker_seek<=float(phrase.t)+.000001 and end>=float(phrase.end)-.000001})
	for note in g.notes:
		var row_index:=row_at(float(note.t)+g.ranker_seek)
		note_rows.append(row_index)
		if row_index<0:continue
		var row:Dictionary=g.ranker_phrase_live[row_index]
		row.notes+=1
		row.maximum+=1000*maxi(1,ceili(float(note.d)))

func row_at(absolute:float)->int:
	var rows:Array=g.ranker_phrase_live
	if rows.is_empty():return -1
	for i in range(rows.size()):
		if absolute<float(rows[i].end)-.000001:return i
	return rows.size()-1

func judgment(index:int,value:int)->void:
	if index<0 or index>=note_rows.size():return
	var row_index:=note_rows[index]
	if row_index<0:return
	var row:Dictionary=g.ranker_phrase_live[row_index]
	row.judged+=1
	row.counts[value]+=1
	row.points+=g.Scoring.POINTS[value]*maxi(1,ceili(float(g.notes[index].d)))

func stray(time:float)->void:
	var index:=row_at(time+g.ranker_seek)
	if index<0:return
	g.ranker_phrase_live[index].extra+=1
	g.ranker_phrase_live[index].points-=g.Ranker.EXTRA_PENALTY

func advance(time:float,visual_time:=INF)->void:
	if g.ranker_id.is_empty():return
	var display_time:float=time if is_inf(visual_time) else visual_time
	for index in range(g.ranker_phrase_live.size()):
		var row:Dictionary=g.ranker_phrase_live[index]
		if bool(row.closed):continue
		if time+g.ranker_seek<float(row.end)+g.hit_window():break
		if int(row.judged)<int(row.notes):continue
		# Trailing inputs belong to the last phrase until this run finishes.
		if index==g.ranker_phrase_live.size()-1 and display_time<=g.round_end()+absf(float(g.preferences.values.offset_ms))/1000*g.speed:continue
		row.closed=true
		if not bool(row.complete) or int(row.notes)==0:continue
		var clean:bool=int(row.counts[3])==0 and int(row.extra)==0
		var quality:=0 if clean and int(row.counts[0])==int(row.notes) else 1 if clean else 2 if float(row.points)/maxf(1,float(row.maximum))>=.75 else 3
		g.ranker_phrase_notice="PHRASE %02d · %s"%[int(row.index)+1,["ALL PERFECT","FULL COMBO","CLEAR","다시 도전"][quality]]
		g.ranker_phrase_notice_until=display_time+1.5
		g.sounds.ranker_phrase(quality)
		if g.ranker_feedback:g.ranker_feedback.phrase(quality,str(row.label))
