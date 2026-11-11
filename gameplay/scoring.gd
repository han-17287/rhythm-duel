extends RefCounted

const WINDOWS = [0.035,0.08,0.18]
const POINTS = [1000,700,400,0]

static func judgment(error: float) -> int:
	return 0 if error<=WINDOWS[0]+0.000001 else 1 if error<=WINDOWS[1]+0.000001 else 2 if error<=WINDOWS[2]+0.000001 else 3

static func analyze(notes: Array, hits: Array) -> Dictionary:
	var used: Dictionary = {}
	var events: Array = []
	var points := 0
	var maximum := 0
	var combo := 0
	var best_combo := 0
	var counts := [0,0,0,0]
	var outcomes: Array = []
	var offsets: Array = []
	for note in notes:
		var best := -1
		var best_error := INF
		for i in range(hits.size()):
			if used.has(i): continue
			var error := absf(float(hits[i].t)-float(note.t))
			if error<best_error:
				best_error = error
				best = i
		var signed_error = null
		var error := INF
		if best>=0 and best_error<=0.180001:
			used[best] = true
			signed_error = float(hits[best].t)-float(note.t)
			error = best_error
			if float(note.d)>=0.3:
				var release_offset := float(hits[best].t)+float(hits[best].d)-float(note.t)-float(note.d)
				if absf(release_offset)>absf(float(signed_error)): signed_error=release_offset
				error = maxf(error,absf(release_offset))
		var j := judgment(error)
		var weight := maxi(1,ceili(float(note.d)))
		points += POINTS[j]*weight
		maximum += 1000*weight
		events.append({"t":float(note.t),"j":j,"order":events.size()})
		counts[j] += 1
		outcomes.append(j)
		offsets.append(null if signed_error==null else snappedf(float(signed_error)*1000,0.1))
		combo = 0 if j==3 else combo+1
		best_combo = maxi(best_combo,combo)
	for i in range(hits.size()):
		if not used.has(i): events.append({"t":float(hits[i].t),"j":3,"order":events.size()})
	events.sort_custom(func(a,b): return a.t<b.t or (a.t==b.t and a.order<b.order))
	combo=0
	best_combo=0
	var combo_events: Array = []
	for event in events:
		combo=0 if int(event.j)==3 else combo+1
		best_combo=maxi(best_combo,combo)
		combo_events.append(int(event.j))
	var extra := hits.size()-used.size()
	points = maxi(0,points-200*extra)
	var accuracy := 100.0*points/maxi(1,maximum)
	var grade := "S" if accuracy>=95 else "A" if accuracy>=85 else "B" if accuracy>=70 else "C" if accuracy>=50 else "D"
	return {"points":points,"maximum":maximum,"accuracy":snappedf(accuracy,0.1),"grade":grade,"counts":counts,"judgments":outcomes,"offsets":offsets,"max_combo":best_combo,"combo_events":combo_events,"extra":extra,"full_combo":counts[3]==0 and extra==0 and notes.size()>0,"all_perfect":counts[0]==notes.size() and extra==0 and notes.size()>0}
