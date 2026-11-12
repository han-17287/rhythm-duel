extends RefCounted

const DEFAULTS = {"volume":0.55,"music_volume":0.8,"ranker_scroll":1.0,"effects":true,"reduced_motion":false,"metronome":false,"bpm":120,"offset_ms":0,"key":"SPACE"}
var values: Dictionary = DEFAULTS.duplicate()
var records: Dictionary = {}
var patterns: Array = []
var persist_ok := true
var next_pattern_number := 1

func load_data() -> void:
	values=DEFAULTS.duplicate()
	records.clear()
	patterns.clear()
	next_pattern_number=1
	var data: Dictionary = {}
	if OS.has_feature("web"):
		var raw = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('perfecto_preferences') || '{}'}catch(e){return '{}'}})()")
		var parsed = JSON.parse_string(str(raw))
		if parsed is Dictionary: data = parsed
	else:
		var cfg := ConfigFile.new()
		if cfg.load("user://preferences.cfg")==OK: data = cfg.get_value("game","data",{})
	if typeof(data.get("next_pattern_number",null)) in [TYPE_INT,TYPE_FLOAT]: next_pattern_number=maxi(1,int(data.next_pattern_number))
	var incoming = data.get("values",{})
	if incoming is Dictionary:
		for key in DEFAULTS:
			if not incoming.has(key): continue
			if typeof(DEFAULTS[key]) in [TYPE_FLOAT,TYPE_INT] and typeof(incoming[key]) in [TYPE_FLOAT,TYPE_INT]:
				values[key]=int(incoming[key]) if typeof(DEFAULTS[key])==TYPE_INT else float(incoming[key])
			elif typeof(incoming[key])==typeof(DEFAULTS[key]): values[key]=incoming[key]
	values.volume = clampf(float(values.volume),0,1)
	values.music_volume = clampf(float(values.music_volume),0,1)
	values.ranker_scroll=clampf(float(values.ranker_scroll),.8,1.4)
	values.bpm = clampi(int(values.bpm),60,200)
	values.offset_ms = clampi(int(values.offset_ms),-150,150)
	if not values.key in ["SPACE","D","F","J","K"]: values.key = "SPACE"
	if data.get("patterns",[]) is Array:
		for pattern in data.get("patterns",[]):
			if patterns.size()>=8: break
			if pattern is Dictionary and valid_pattern(pattern.get("notes",[])):
				patterns.append({"id":str(pattern.get("id",patterns.size())),"name":str(pattern.get("name","내 비트")).left(24),"notes":pattern.notes})
	if data.get("records",{}) is Dictionary:
		for id in data.get("records",{}):
			if records.size()>=1000: break
			var record=data.records[id]
			if not record is Dictionary: continue
			if not typeof(record.get("points",null)) in [TYPE_INT,TYPE_FLOAT]: continue
			if not typeof(record.get("accuracy",null)) in [TYPE_INT,TYPE_FLOAT]: continue
			if not is_finite(float(record.points)) or not is_finite(float(record.accuracy)): continue
			var perfect:bool=typeof(record.get("all_perfect",false))==TYPE_BOOL and bool(record.get("all_perfect",false))
			var full:bool=perfect or (typeof(record.get("full_combo",false))==TYPE_BOOL and bool(record.get("full_combo",false)))
			records[str(id)]={"points":clampi(int(record.points),0,1000000000),"accuracy":clampf(float(record.accuracy),0,100),"grade":str(record.get("grade","D")),"stars":clampi(int(record.get("stars",0)),0,3),"max_combo":maxi(0,int(record.get("max_combo",0))),"full_combo":full,"all_perfect":perfect}

func save() -> void:
	var data := {"values":values,"records":records,"patterns":patterns,"next_pattern_number":next_pattern_number}
	if OS.has_feature("web"):
		persist_ok=bool(JavaScriptBridge.eval("(function(){try{localStorage.setItem('perfecto_preferences', %s);return true}catch(e){return false}})()"%JSON.stringify(JSON.stringify(data,"",true,true))))
	else:
		var cfg := ConfigFile.new()
		cfg.set_value("game","data",data)
		persist_ok=cfg.save("user://preferences.cfg")==OK

func remember(id: String, report: Dictionary) -> bool:
	var previous: Dictionary = records.get(id,{})
	var better := int(report.points)>int(previous.get("points",-1)) or (int(report.points)==int(previous.get("points",-1)) and int(report.max_combo)>int(previous.get("max_combo",-1)))
	if better:
		records[id] = {"points":int(report.points),"accuracy":float(report.accuracy),"grade":str(report.grade),"stars":3 if report.accuracy>=95 else 2 if report.accuracy>=80 else 1 if report.accuracy>=60 else 0,"max_combo":int(report.max_combo)}
	var perfect:bool=bool(previous.get("all_perfect",false)) or bool(report.get("all_perfect",false))
	var full:bool=perfect or bool(previous.get("full_combo",false)) or bool(report.get("full_combo",false))
	var badges_changed:bool=perfect!=bool(previous.get("all_perfect",false)) or full!=bool(previous.get("full_combo",false))
	if records.has(id):
		records[id].full_combo=full;records[id].all_perfect=perfect
	if better or badges_changed:
		save()
	return better

static func valid_pattern(notes) -> bool:
	if not notes is Array or notes.is_empty() or notes.size()>8: return false
	var budget:=0
	var ends:=[-0.08,-0.08]
	for n in notes:
		if not n is Dictionary or not n.has("t") or not n.has("d"): return false
		if not typeof(n.t) in [TYPE_INT,TYPE_FLOAT] or not typeof(n.d) in [TYPE_INT,TYPE_FLOAT]: return false
		var t:=float(n.t)
		var d:=float(n.d)
		var lane=int(n.get("lane",0))
		if not typeof(n.get("lane",0)) in [TYPE_INT,TYPE_FLOAT] or float(n.get("lane",0))!=lane or lane not in [0,1]:return false
		if not is_finite(t+d) or t<0 or t>30 or d<0 or d>8 or t<ends[lane]+0.075: return false
		budget+=maxi(1,ceili(d)) if d>=0.3 else 1
		ends[lane]=t+d
	return budget==8

func save_pattern(notes: Array) -> bool:
	if not valid_pattern(notes): return false
	for pattern in patterns:
		var same: bool=pattern.notes.size()==notes.size()
		if same:
			for i in range(notes.size()):
				if float(pattern.notes[i].t)!=float(notes[i].t) or float(pattern.notes[i].d)!=float(notes[i].d) or int(pattern.notes[i].get("lane",0))!=int(notes[i].get("lane",0)): same=false
		if same: return true
	if patterns.size()>=8: return false
	patterns.append({"id":str(Time.get_unix_time_from_system())+str(randi()),"name":"내 비트 %d"%next_pattern_number,"notes":notes.duplicate(true)})
	next_pattern_number+=1
	save()
	return true

func delete_pattern(index: int) -> void:
	if index<0 or index>=patterns.size(): return
	patterns.remove_at(index)
	save()
