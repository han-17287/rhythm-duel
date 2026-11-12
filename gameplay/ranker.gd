extends RefCounted
const WINDOWS=[.022,.05,.1]
static var songs: Array=[]
static func catalog() -> Array:
	if songs.is_empty():songs=JSON.parse_string(FileAccess.get_file_as_string("res://assets/ranker/catalog.json"))
	return songs
static func find(id: String) -> Dictionary:
	for song in catalog():
		if song.id==id:return song
	return {}
static func chart(id: String,kind: String,seek := 0.0,end := 0.0) -> Array:
	var result:Array=[]
	for note in find(id).charts[kind]:
		if float(note.t)+.00001<seek or (end>0 and float(note.t)>=end-.00001):continue
		var n:Dictionary=note.duplicate();n.t=float(n.t)-seek;result.append(n)
	return result
static func record_id(id: String,kind: String) -> String:return "ranker:"+id+":"+kind
static func section(id: String,time: float) -> Dictionary:
	var bars:Array=find(id).bars
	var current:Dictionary=bars[0]
	for bar in bars:
		if float(bar.t)>time:break
		current=bar
	return current
static func grade(accuracy: float) -> String:
	return "EX" if accuracy>=99.5 else "SS" if accuracy>=98 else "S" if accuracy>=95 else "A" if accuracy>=85 else "B" if accuracy>=75 else "F"
static func power(records: Dictionary,kind: String) -> int:
	var total:=0
	for song in catalog():
		var record:Dictionary=records.get(record_id(song.id,kind),{})
		total+=roundi(float(record.get("accuracy",0))*float(song.level)/10)
	return total
