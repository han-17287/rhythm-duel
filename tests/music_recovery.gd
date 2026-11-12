extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var g=load("res://main.tscn").instantiate();root.add_child(g);await process_frame
	g.open_menu("ranker")
	g.preferences.values.offset_ms=35;g.preferences.values.music_volume=0.0;g.preferences.values.volume=0.0
	g.interface.sync();var ui=g.interface.gameplay_ui
	assert(ui.music_restore.visible and not ui.music_restore_settings.disabled)
	ui.restore_music();ui.sync()
	assert(g.preferences.values.volume==.55 and g.preferences.values.music_volume==.8)
	assert(g.preferences.values.offset_ms==35 and not ui.music_restore.visible)
	g.preferences.values.volume=.3;g.preferences.values.music_volume=0.0;ui.restore_music()
	assert(g.preferences.values.volume==.3 and g.preferences.values.music_volume==.8)
	g.preferences.values.music_volume=.25;ui.restore_music();assert(g.preferences.values.music_volume==.25)
	g.queue_free();await process_frame
	print("MUSIC_RECOVERY_OK: explicit saved-mute repair, preserves nonzero volumes and input settings")
	quit()
