extends RefCounted

static func courses() -> Array:
	return [
		{"id":"first","name":"첫 번째 비트","tag":"BEGINNER","description":"일정한 박자로 타이밍을 익혀봐.","speed":0.8,"level":1},
		{"id":"hold","name":"길게, 더 길게","tag":"HOLD SCHOOL","description":"롱 노트의 끝까지 정확하게.","speed":0.9,"level":2},
		{"id":"swing","name":"엇박자의 매력","tag":"OFFBEAT","description":"짧고 긴 간격을 번갈아 받아쳐.","speed":1.0,"level":3},
		{"id":"rush","name":"스피드 러너","tag":"SPEED RUN","description":"빠른 비트 속에서도 침착하게.","speed":1.4,"level":4},
		{"id":"survival","name":"끝없는 앙코르","tag":"SURVIVAL","description":"에너지가 남아 있는 한 계속!","speed":1.0,"level":3},
		{"id":"daily","name":"오늘의 챌린지","tag":"DAILY MIX","description":"매일 바뀌는 모두의 비트.","speed":1.15,"level":3}
	]

static func today() -> String:
	return Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system())+9*3600)

static func pattern(id: String, wave: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi((id+(today() if id=="daily" else "")+str(wave)).hash())
	var notes: Array = []
	var remaining := 8
	var time := 0.0
	while remaining>0:
		var duration := 0.0
		if id=="hold": duration = 1.0 if notes.size()%2==0 else 0.0
		elif id in ["daily","survival","rush"] and rng.randf()<0.3: duration = 2.0 if remaining>=2 and rng.randf()<0.3 else 1.0
		elif id=="first" and wave==2 and remaining in [3,5]: duration = 1.0
		var cost := maxi(1,ceili(duration))
		notes.append({"t":snappedf(time,0.001),"d":duration})
		remaining -= cost
		var gap := 0.5
		if id=="swing": gap = [0.25,0.75,0.375,0.625][(notes.size()+wave)%4]
		elif id in ["daily","survival","rush"]: gap = [0.25,0.375,0.5,0.75][rng.randi_range(0,3)]
		elif id=="first": gap = [0.75,0.5,0.5][mini(wave,2)]
		time += duration+gap
	return notes

static func record_id(id: String) -> String:
	return id+":"+today() if id=="daily" else id

static func combine(reports: Array) -> Dictionary:
	var combined := {"points":0,"maximum":0,"counts":[0,0,0,0],"judgments":[],"offsets":[],"max_combo":0,"extra":0}
	var streak := 0
	for r in reports:
		combined.points += int(r.points)
		combined.maximum += int(r.maximum)
		combined.extra += int(r.extra)
		for j in range(4): combined.counts[j] += int(r.counts[j])
		for j in r.get("combo_events",r.judgments):
			streak = 0 if int(j)==3 else streak+1
			combined.max_combo = maxi(int(combined.max_combo),streak)
		combined.judgments.append_array(r.judgments)
		combined.offsets.append_array(r.offsets)
	combined.accuracy = snappedf(100.0*combined.points/maxi(1,combined.maximum),0.1)
	combined.grade = "S" if combined.accuracy>=95 else "A" if combined.accuracy>=85 else "B" if combined.accuracy>=70 else "C" if combined.accuracy>=50 else "D"
	combined.full_combo = combined.counts[3]==0 and combined.extra==0
	combined.all_perfect = combined.counts[0]==combined.judgments.size() and combined.extra==0
	return combined
