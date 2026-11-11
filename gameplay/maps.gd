extends RefCounted

static var cached: Array=[]
static var charts: Dictionary={}

# Authored half-beat grids: x=tap, H=one-beat hold, L=two-beat hold.
# Empty cells intentionally leave breathing room after every hold.
static func catalog() -> Array:
	if not cached.is_empty():return cached
	cached = [
		{"id":"m01","name":"첫 빛","region":0,"bpm":84,"bars":8,"level":1,"skill":"일정한 박자","description":"큰 박자부터 천천히.\n판정선에 닿을 때 한 번씩 눌러봐.","phrases":["x.x.x.x.","x.x.x...","x...x.x.","x.x.x.x."]},
		{"id":"m02","name":"포켓 그루브","region":0,"bpm":92,"bars":12,"level":1,"skill":"쉬는 박자","description":"쉬는 곳도 리듬의 일부야.\n노트가 없는 순간엔 기다려봐.","phrases":["x.x...x.","x...x.x.","x.x.x.x.","x.x...x."]},
		{"id":"m03","name":"작은 발걸음","region":0,"bpm":100,"bars":12,"level":2,"skill":"두 번 연속 입력","description":"짧은 두 박자가 섞여 있어.\n연타 뒤에는 다시 호흡을 골라봐.","phrases":["x.xx..x.","x.x.xx..","x...xx..","x.x.x.x."]},
		{"id":"m04","name":"네온 산책","region":0,"bpm":108,"bars":16,"level":2,"skill":"첫 번째 보스","description":"기본 박자와 짧은 연타의 조합.\n배운 리듬으로 첫 관문에 도전해.","phrases":["x.x.xx..","xx..x.x.","x.xx..x.","x.x.x.xx"]},
		{"id":"m05","name":"길게 숨쉬기","region":1,"bpm":96,"bars":12,"level":2,"skill":"롱 노트 시작과 끝","description":"누르는 순간만큼 떼는 순간도!\n금색 노트는 꼬리까지 유지해.","phrases":["H...x.x.","x.x.H...","H...H...","x.x.x.x."]},
		{"id":"m06","name":"빛의 다리","region":1,"bpm":104,"bars":12,"level":2,"skill":"긴 유지 후 짧게","description":"긴 다리를 건너 짧은 박자로.\n유지 링을 보고 정확히 떼어봐.","phrases":["L.....x.","x.x.H...","H...x.x.","x.L....."]},
		{"id":"m07","name":"신호 교차로","region":1,"bpm":112,"bars":12,"level":3,"skill":"홀드와 연타 전환","description":"짧게, 길게, 다시 두 번.\n손에 힘을 빼고 전환해봐.","phrases":["H...xx..","xx..H...","x.H...x.","x.xx..x."]},
		{"id":"m08","name":"프리즘 게이트","region":1,"bpm":120,"bars":16,"level":3,"skill":"두 번째 보스","description":"롱 노트와 엇박자가 만나는 곳.\n서두르지 말고 리듬을 읽어봐.","phrases":["H..x.xx.","x.L....x",".x.x.H..","xx..x.x."]},
		{"id":"m09","name":"스윙 시티","region":2,"bpm":124,"bars":12,"level":3,"skill":"박자 사이의 입력","description":"정박 사이로 리듬이 들어와.\n엇박자의 흐름을 느껴봐.","phrases":[".x.x.x.x","x..x.xx.",".xx..x.x","x.x..xx."]},
		{"id":"m10","name":"빠른 손끝","region":2,"bpm":132,"bars":16,"level":4,"skill":"연속 입력 지구력","description":"짧은 연타를 이어가는 맵.\n정확한 간격으로 가볍게 눌러봐.","phrases":["xxxx..x.","x.x.xxx.","xx.xx.x.","xxx.x.x."]},
		{"id":"m11","name":"글라스 스톰","region":2,"bpm":140,"bars":16,"level":4,"skill":"혼합 패턴","description":"빠른 입력 사이로 홀드가 등장해.\n시선을 판정선 앞에 두고 집중!","phrases":["xxH...xx","x.xH...x","H..xxx..",".xxx.x.x"]},
		{"id":"m12","name":"퍼펙트 스카이","region":2,"bpm":148,"bars":20,"level":5,"skill":"마지막 보스","description":"모든 리듬을 담은 마지막 무대.\n천천히 연습한 뒤 완주에 도전해.","phrases":["x.xxxxxx","H..x.xxx","xxL....x",".xxxH..."]}
	]
	return cached

static func find(id: String) -> Dictionary:
	for item in catalog():
		if item.id==id:return item
	return {}

static func chart(id: String) -> Array:
	if charts.has(id):return charts[id]
	var item:=find(id)
	if item.is_empty():return []
	var beat:=60.0/float(item.bpm)
	var notes: Array=[]
	var arrangement: Array=[0,1,0,2,0,1,3,2,0,2,1,3,2,1,0,3,0,2,1,3]
	for bar in range(int(item.bars)):
		var grid: String=item.phrases[arrangement[bar]]
		for cell in range(8):
			var token:=grid.substr(cell,1)
			if not token in ["x","H","L"]:continue
			notes.append({"t":snappedf((bar*4+cell*.5)*beat,.00001),"d":snappedf(beat*(2 if token=="L" else 1),.00001) if token!="x" else 0.0})
	charts[id]=notes
	return notes

static func record_id(id: String) -> String:return "map:"+id
static func stars(accuracy: float) -> int:return 3 if accuracy>=95 else 2 if accuracy>=80 else 1 if accuracy>=60 else 0
static func unlocked(id: String, records: Dictionary) -> bool:
	var all:=catalog()
	for i in range(all.size()):
		if all[i].id==id:return i==0 or int(records.get(record_id(all[i-1].id),{}).get("stars",0))>=1
	return false
static func next_id(id: String) -> String:
	var all:=catalog()
	for i in range(all.size()-1):
		if all[i].id==id:return str(all[i+1].id)
	return ""
static func total_stars(records: Dictionary) -> int:
	var total:=0
	for item in catalog():total+=int(records.get(record_id(item.id),{}).get("stars",0))
	return total
