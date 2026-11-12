extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var g=load("res://main.tscn").instantiate();root.add_child(g);await process_frame
	g.interface.page="calibration";g.interface.sync()
	var lab:RefCounted=g.interface.gameplay_ui.calibration_ui
	assert(lab.page.visible and not g.interface.gameplay_ui.ranker_ui.page.visible)
	lab.start()
	for i in range(16):lab.tap(2+i*.5+(.047 if i not in [3,11] else -.12))
	assert(lab.samples.size()==16 and lab.proposed==-47 and not lab.apply_button.disabled)
	lab.apply();assert(g.preferences.values.offset_ms==-47 and not lab.running and not lab.player.playing)
	g.preferences.load_data();assert(g.preferences.values.offset_ms==-47)
	lab.start();g.open_menu("ranker");g.interface.sync();assert(not lab.running and not lab.player.playing)
	g.preferences.values.offset_ms=0;g.preferences.save()
	g.queue_free();await process_frame
	print("CALIBRATION_OK: sixteen audio-time taps, robust median/outliers, signed compensation, durable save, exit cleanup");quit()
