extends RefCounted
## Phrase feedback is a view of the canonical report, never a second scoring rule.
## Times in notes/hits are relative to seek; phrase bounds stay song-absolute so
## a result can open the complete phrase directly in practice.
const Ranker=preload("res://gameplay/ranker.gd")
const Scoring=preload("res://gameplay/scoring.gd")
const EPSILON=0.000001

static func summarize(song:Dictionary,notes:Array,hits:Array,report:Dictionary,seek:=0.0,end:=0.0,windows:=Ranker.WINDOWS)->Array:
	var rows:Array=[]
	var phrases:Array=song.get("phrases",[])
	var limit:float=float(song.get("duration",0.0)) if end<=0 else minf(end,float(song.get("duration",end)))
	if phrases.is_empty() or limit<=seek:return rows
	for index in range(phrases.size()):
		var phrase:Dictionary=phrases[index]
		var start:float=maxf(seek,float(phrase.t))
		var finish:float=minf(limit,float(phrase.end))
		if finish<=start+EPSILON:continue
		rows.append({"index":index,"t":float(phrase.t),"end":float(phrase.end),
			"played_start":start,"played_end":finish,"label":str(phrase.get("label","PHRASE %02d"%(index+1))),
			"technique":str(phrase.get("technique","")),"section":int(phrase.get("section",0)),
			"complete":seek<=float(phrase.t)+EPSILON and limit>=float(phrase.end)-EPSILON,
			"notes":0,"points":0,"raw_points":0,"maximum":0,"accuracy":0.0,
			"counts":[0,0,0,0],"extra":0,"full_combo":false,"all_perfect":false,
			"mean_offset":null,"offset_count":0,"offset_sum":0.0})
	if rows.is_empty():return rows
	var outcomes:Array=report.get("judgments",[])
	var offsets:Array=report.get("offsets",[])
	for index in range(notes.size()):
		var note:Dictionary=notes[index]
		var row:Dictionary=rows[_row_at(rows,float(note.t)+seek)]
		var judgment:int=clampi(int(outcomes[index]),0,3) if index<outcomes.size() else 3
		var weight:=maxi(1,ceili(float(note.d)))
		row.notes+=1
		row.maximum+=1000*weight
		row.raw_points+=int(Scoring.POINTS[judgment])*weight
		row.counts[judgment]+=1
		if index<offsets.size() and offsets[index]!=null and is_finite(float(offsets[index])):
			row.offset_count+=1
			row.offset_sum+=float(offsets[index])
	# The report contains one judgment per note, but no hit-to-note map. Recover
	# only which hits were used with the same earliest-unassigned-note rule.
	# Each lane cursor advances monotonically; after sorting hits this is O(n+h).
	var used:=_used_hits(notes,hits,float(windows[2])+EPSILON)
	var penalty:=maxi(0,int(report.get("extra_penalty",Ranker.EXTRA_PENALTY)))
	for index in range(hits.size()):
		if used.has(index):continue
		var row:Dictionary=rows[_row_at(rows,float(hits[index].t)+seek)]
		row.extra+=1
		row.raw_points-=penalty
	for row in rows:
		# Keep the debt as raw_points. Summing individually clamped phrase scores
		# would erase excess penalties in an empty/missed phrase and inflate a run.
		row.points=maxi(0,int(row.raw_points))
		row.accuracy=snappedf(100.0*float(row.points)/maxi(1,int(row.maximum)),0.1)
		row.full_combo=bool(row.complete) and int(row.notes)>0 and int(row.counts[3])==0 and int(row.extra)==0
		row.all_perfect=bool(row.complete) and int(row.notes)>0 and int(row.counts[0])==int(row.notes) and int(row.extra)==0
		row.mean_offset=snappedf(float(row.offset_sum)/int(row.offset_count),0.1) if int(row.offset_count)>0 else null
		row.erase("offset_sum")
	return rows

static func weakest(rows:Array)->Dictionary:
	var answer:Dictionary={}
	for row in rows:
		if int(row.get("notes",0))<=0:continue
		if answer.is_empty():answer=row;continue
		var accuracy:float=float(row.get("accuracy",0.0))
		var old_accuracy:float=float(answer.get("accuracy",0.0))
		var mistakes:int=int(row.get("counts",[0,0,0,0])[3])+int(row.get("extra",0))
		var old_mistakes:int=int(answer.get("counts",[0,0,0,0])[3])+int(answer.get("extra",0))
		if accuracy<old_accuracy or (is_equal_approx(accuracy,old_accuracy) and (mistakes>old_mistakes or (mistakes==old_mistakes and int(row.index)<int(answer.index)))):
			answer=row
	return answer

static func _row_at(rows:Array,time:float)->int:
	var low:=0
	var high:=rows.size()
	while low<high:
		var middle:=(low+high)/2
		if float(rows[middle].t)<=time:low=middle+1
		else:high=middle
	# Inputs before the first phrase and after the selected end still count as
	# strays: attach them to the first/last played phrase instead of dropping them.
	return clampi(low-1,0,rows.size()-1)

static func _used_hits(notes:Array,hits:Array,window:float)->Dictionary:
	var lanes:Dictionary={}
	for index in range(notes.size()):
		var lane:=int(notes[index].get("lane",0))
		if not lanes.has(lane):lanes[lane]=[]
		lanes[lane].append(index)
	var cursors:Dictionary={}
	var order:Array=range(hits.size())
	order.sort_custom(func(a,b):return float(hits[a].t)<float(hits[b].t) or (hits[a].t==hits[b].t and a<b))
	var used:Dictionary={}
	for hit_index in order:
		var lane:=int(hits[hit_index].get("lane",0))
		if not lanes.has(lane):continue
		var candidates:Array=lanes[lane]
		var cursor:=int(cursors.get(lane,0))
		var time:=float(hits[hit_index].t)
		while cursor<candidates.size() and float(notes[candidates[cursor]].t)<time-window:
			cursor+=1
		if cursor<candidates.size() and absf(float(notes[candidates[cursor]].t)-time)<=window:
			used[hit_index]=true
			cursor+=1
		cursors[lane]=cursor
	return used
