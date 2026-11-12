extends SceneTree
const Analysis=preload("res://gameplay/ranker_analysis.gd")
const Score=preload("res://gameplay/scoring.gd")
const Ranker=preload("res://gameplay/ranker.gd")
var checks:=0

func _initialize()->void:call_deferred("run")

func check(condition:bool,message:String)->bool:
	checks+=1
	if not condition:push_error("RANKER_ANALYSIS_FAILED: "+message)
	return condition

func fixture()->Dictionary:
	return {"duration":12.0,"phrases":[
		{"t":0.0,"end":4.0,"label":"CALL","technique":"엇박","section":0},
		{"t":4.0,"end":8.0,"label":"RESPONSE","technique":"쉼표","section":1},
		{"t":8.0,"end":12.0,"label":"RETURN","technique":"홀드","section":2}]}

func totals_match(rows:Array,report:Dictionary,context:String)->bool:
	var raw:=0
	var maximum:=0
	var extras:=0
	var counts:=[0,0,0,0]
	for row in rows:
		raw+=int(row.raw_points);maximum+=int(row.maximum);extras+=int(row.extra)
		for j in range(4):counts[j]+=int(row.counts[j])
	return check(maxi(0,raw)==int(report.points),context+" raw score") and check(maximum==int(report.maximum),context+" maximum") and check(extras==int(report.extra),context+" extra inputs") and check(counts==report.counts,context+" judgments")

func boundary_hold_debt()->bool:
	var notes:Array=[{"t":.4,"d":0.0,"lane":0},{"t":3.8,"d":1.0,"lane":0},{"t":4.0,"d":0.0,"lane":1},{"t":8.0,"d":0.0,"lane":0}]
	var hits:Array=[{"t":-.12,"d":.01,"lane":0},{"t":.4,"d":.01,"lane":0},{"t":3.8,"d":.5,"lane":0},{"t":4.0,"d":.01,"lane":0},{"t":4.0,"d":.01,"lane":1},{"t":9.0,"d":.01,"lane":0},{"t":12.2,"d":.01,"lane":0}]
	var report:=Score.analyze(notes,hits,Ranker.windows("inferno"),true,Ranker.EXTRA_PENALTY)
	var rows:=Analysis.summarize(fixture(),notes,hits,report,0,0,Ranker.windows("inferno"))
	if not check(rows.size()==3,"Every played phrase is present"):return false
	if not check(rows[0].counts==[1,0,0,1] and rows[0].extra==1,"Failed hold belongs to onset phrase and is not an extra"):return false
	if not check(rows[1].counts==[1,0,0,0] and rows[1].extra==1,"Boundary stray belongs to following phrase; opposite lane still hits"):return false
	if not check(rows[2].counts==[0,0,0,1] and rows[2].extra==2,"Late/tail strays stay in final played phrase"):return false
	if not check(rows[0].raw_points==400 and rows[1].raw_points==400 and rows[2].raw_points==-1200,"Phrase penalty debt is preserved"):return false
	if not check(rows[2].points==0 and rows[2].accuracy==0 and report.points==0,"Only displayed phrase score clamps debt"):return false
	if not check(rows[0].offset_count==2 and rows[0].mean_offset==-250 and rows[2].mean_offset==null,"Hold release offset mean and no-input null"):return false
	if not check(Analysis.weakest(rows).index==2,"Weakest phrase picks actual missed passage"):return false
	return totals_match(rows,report,"Hold/boundary/debt")

func selected_ranges()->bool:
	var notes:Array=[{"t":.8,"d":1.0},{"t":1.0,"d":0.0,"lane":1},{"t":5.0,"d":0.0}]
	var report:=Score.analyze(notes,notes,Ranker.WINDOWS,true,Ranker.EXTRA_PENALTY)
	var rows:=Analysis.summarize(fixture(),notes,notes,report,3.0,9.0)
	if not check(rows.size()==3 and rows[0].played_start==3.0 and rows[2].played_end==9.0,"Practice clips only its covered interval"):return false
	if not check(not rows[0].complete and rows[1].complete and not rows[2].complete,"Partial phrases are explicitly marked"):return false
	if not check(not rows[0].all_perfect and rows[1].all_perfect and not rows[2].full_combo,"Partial practice cannot claim whole-phrase mastery"):return false
	if not totals_match(rows,report,"Selected range"):return false
	var one:Array=[{"t":0.0,"d":0.0,"lane":1}]
	var one_report:=Score.analyze(one,one,Ranker.WINDOWS,true,Ranker.EXTRA_PENALTY)
	rows=Analysis.summarize(fixture(),one,one,one_report,4.0,8.0)
	if not check(rows.size()==1 and rows[0].index==1 and rows[0].t==4.0 and rows[0].end==8.0,"Untouched neighbouring phrases excluded"):return false
	if not check(rows[0].all_perfect and rows[0].full_combo,"Full selected phrase can earn mastery"):return false
	var empty_report:=Score.analyze([],[],Ranker.WINDOWS,true,Ranker.EXTRA_PENALTY)
	rows=Analysis.summarize(fixture(),[],[],empty_report)
	if not check(rows.size()==3 and Analysis.weakest(rows).is_empty(),"Empty phrases have no weakest recommendation"):return false
	for row in rows:
		if not check(not row.full_combo and not row.all_perfect and row.mean_offset==null,"No false empty phrase awards"):return false
	return check(Analysis.summarize(fixture(),[],[],empty_report,8,8).is_empty(),"Zero-duration range excluded")

func window_and_matching()->bool:
	var notes:Array=[{"t":4.09,"d":0.0}]
	var hits:Array=[{"t":4.0,"d":.01}]
	for tier in ["hard","inferno"]:
		var windows:=Ranker.windows(tier)
		var report:=Score.analyze(notes,hits,windows,true,Ranker.EXTRA_PENALTY)
		var rows:=Analysis.summarize(fixture(),notes,hits,report,0,0,windows)
		if not check(rows[1].extra==(0 if tier=="hard" else 1),"Tier hit window "+tier):return false
		if not totals_match(rows,report,"Tier "+tier):return false
	# The earliest unmatched note wins, even when the following note is closer.
	notes=[{"t":3.98,"d":0.0},{"t":4.02,"d":0.0}]
	hits=[{"t":4.05,"d":.01},{"t":3.96,"d":.01},{"t":4.051,"d":.01}]
	var report:=Score.analyze(notes,hits,Ranker.WINDOWS,true,Ranker.EXTRA_PENALTY)
	var rows:=Analysis.summarize(fixture(),notes,hits,report)
	if not check(rows[0].notes==1 and rows[0].extra==0 and rows[1].notes==1 and rows[1].extra==1,"Out-of-order replay/nearby notes preserve earliest assignment"):return false
	return totals_match(rows,report,"Dense matching")

func randomized_parity()->bool:
	var rng:=RandomNumberGenerator.new();rng.seed=510827
	for trial in range(120):
		var notes:Array=[]
		var hits:Array=[]
		for index in range(24):
			var time:=.2+index*.46
			var lane:=index%2
			var duration:=.42 if index%7==0 else 0.0
			notes.append({"t":time,"d":duration,"lane":lane})
			if rng.randf()>.18:hits.append({"t":time+rng.randf_range(-.13,.13),"d":maxf(.01,duration+rng.randf_range(-.11,.11)),"lane":lane})
			if rng.randf()<.24:hits.append({"t":time+rng.randf_range(-.4,.4),"d":.01,"lane":rng.randi_range(0,1)})
		hits.reverse()
		var windows:=Ranker.windows(Ranker.DIFFICULTIES[trial%3])
		var report:=Score.analyze(notes,hits,windows,true,Ranker.EXTRA_PENALTY)
		var rows:=Analysis.summarize(fixture(),notes,hits,report,0,0,windows)
		if not totals_match(rows,report,"Random replay %d"%trial):return false
	return true

func weakest_ties()->bool:
	var rows:Array=[{"index":2,"notes":3,"accuracy":50.0,"counts":[0,0,0,1],"extra":0},{"index":1,"notes":3,"accuracy":50.0,"counts":[0,0,0,0],"extra":1},{"index":0,"notes":0,"accuracy":0.0,"counts":[0,0,0,0],"extra":8}]
	if not check(Analysis.weakest(rows).index==1,"Equal performance prefers earlier phrase; empty excluded"):return false
	rows[0].extra=1
	return check(Analysis.weakest(rows).index==2,"Equal accuracy prefers more breaks")

func real_charts()->bool:
	var checked:=0
	for song in Ranker.catalog():
		for tier in Ranker.DIFFICULTIES:
			for kind in ["one","double"]:
				var notes:=Ranker.chart(song.id,kind,0,0,tier)
				var report:=Score.analyze(notes,notes,Ranker.windows(tier),true,Ranker.EXTRA_PENALTY)
				var rows:=Analysis.summarize(song,notes,notes,report,0,0,Ranker.windows(tier))
				if not check(rows.size()==song.phrases.size(),"Every original phrase represented: "+song.id+kind+tier):return false
				for row in rows:
					if not check(row.accuracy==100 and row.complete and row.all_perfect,"Perfect phrase classification: "+song.id+kind+tier):return false
				if not totals_match(rows,report,"Real "+song.id+kind+tier):return false
				checked+=1
	return check(checked==24,"All 24 canonical charts checked")

func run()->void:
	if not boundary_hold_debt() or not selected_ranges() or not window_and_matching() or not randomized_parity() or not weakest_ties() or not real_charts():quit(1);return
	print("RANKER_ANALYSIS_OK: %d checks; 24 charts, 120 mixed replays, tier windows, holds, boundary/tail strays, penalty debt, partial practice, weakest ties"%checks)
	quit()
