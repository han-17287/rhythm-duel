extends SceneTree
const Scoring = preload("res://gameplay/scoring.gd")
func _initialize() -> void:
	var path:=OS.get_environment("SCORING_FIXTURES")
	var cases=JSON.parse_string(FileAccess.get_file_as_string(path))
	for i in range(cases.size()):
		var c: Dictionary=cases[i]
		var actual:=Scoring.analyze(c.notes,c.hits)
		for key in ["points","maximum","grade","counts","judgments","max_combo","extra","full_combo","all_perfect","combo_events"]:
			var equal: bool=true
			if actual[key] is Array:
				equal=actual[key].size()==c.report[key].size()
				for index in range(actual[key].size()):
					if int(actual[key][index])!=int(c.report[key][index]): equal=false
			else: equal=actual[key]==c.report[key]
			if not equal:
				push_error("case %d %s: %s != %s"%[i,key,str(actual[key]),str(c.report[key])])
				quit(1)
				return
		assert(absf(actual.accuracy-float(c.report.accuracy))<0.051,"accuracy case %d"%i)
	print("SCORING_PARITY_OK: %d client/server reports"%cases.size())
	quit()
