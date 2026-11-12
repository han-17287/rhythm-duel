extends RefCounted
const WINDOWS=[.022,.05,.1]
const EXTRA_PENALTY=600
const DIFFICULTIES=["hard","expert","inferno"]
const TIER_WINDOWS={"hard":[.022,.05,.1],"expert":[.020,.045,.090],"inferno":[.018,.040,.080]}
static var songs: Array=[]
static func catalog() -> Array:
	if songs.is_empty():songs=JSON.parse_string(FileAccess.get_file_as_string("res://assets/ranker/catalog.json"))
	return songs
static func find(id: String) -> Dictionary:
	for song in catalog():
		if song.id==id:return song
	return {}
static func windows(difficulty := "hard") -> Array:return TIER_WINDOWS.get(difficulty,WINDOWS)
static func level(id: String,kind: String,difficulty := "hard") -> int:
	var song:=find(id)
	return int(song.get("difficulty_levels",{}).get(difficulty,song.get("level",0)))+(2 if kind=="double" else 0)
static func source_chart(id: String,kind: String,difficulty := "hard") -> Array:
	var song:=find(id)
	if song.is_empty():return []
	return song.charts.get(kind,[]) if difficulty=="hard" else song.get("extras",{}).get(difficulty,{}).get(kind,[])
static func chart(id: String,kind: String,seek := 0.0,end := 0.0,difficulty := "hard") -> Array:
	var result:Array=[]
	for note in source_chart(id,kind,difficulty):
		if float(note.t)+.00001<seek or (end>0 and float(note.t)>=end-.00001):continue
		var n:Dictionary=note.duplicate();n.t=float(n.t)-seek;result.append(n)
	return result
static func revision(id: String) -> int:return int(find(id).get("revision",1))
static func board_id(id: String,kind: String,difficulty := "hard") -> String:
	var version:=revision(id)
	return id+":"+kind+(":"+difficulty if difficulty!="hard" else "")+(":v%d"%version if version>1 else "")
static func record_id(id: String,kind: String,difficulty := "hard") -> String:return "ranker:"+board_id(id,kind,difficulty)
static func section(id: String,time: float) -> Dictionary:
	var bars:Array=find(id).bars
	var current:Dictionary=bars[0]
	for bar in bars:
		if float(bar.t)>time:break
		current=bar
	return current
static func grade(accuracy: float) -> String:
	return "EX" if accuracy>=99.5 else "SS" if accuracy>=98 else "S" if accuracy>=95 else "A" if accuracy>=85 else "B" if accuracy>=75 else "F"
static func power(records: Dictionary,kind: String,difficulty := "hard") -> int:
	var total:=0
	for song in catalog():
		var record:Dictionary=records.get(record_id(song.id,kind,difficulty),{})
		total+=roundi(float(record.get("accuracy",0))*level(song.id,"one",difficulty)/10)
	return total
