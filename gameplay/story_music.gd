extends Node
# Browser transport reads the audible hardware timestamp. Native playback
# interpolates mixer positions and corrects slow drift without jumping notes.
static var serial:=0
var web_id:=0
var web_enabled:=false
var web_driver:JavaScriptObject
var player:AudioStreamPlayer
var track_id:=""
var started:=false
var rate:=1.0
var pre_roll:=0.0
var ended_at:=-1.0
var output_latency:=0.0
var last_clock:=0.0
var cache_id:=""
var cached:AudioStream
var clock_locked:=false
var clock_offset:=0.0
var start_position:=0.0
var sample_at:=-1.0
var offsets:Array=[]
func _ready()->void:
	if OS.has_feature("web"):
		web_driver=JavaScriptBridge.get_interface("PerfectoMusic")
		web_enabled=web_driver!=null
		if web_enabled:
			serial+=1;web_id=serial;web_driver.create(web_id)
	player=AudioStreamPlayer.new()
	# Native/fallback mixer. The official Web build uses the browser transport.
	player.playback_type=AudioServer.PLAYBACK_TYPE_STREAM
	add_child(player)
func prepare(id:String,speed:float,lead_in:=0.0,folder:="music")->void:
	stop();track_id=id;rate=speed;pre_roll=lead_in
	if web_enabled:
		var url:="audio/%s/%s.ogg"%[folder,id]
		if folder=="ranker":url+="?revision=%d"%preload("res://gameplay/ranker.gd").revision(id)
		web_driver.prepare(web_id,url,rate);return
	# The driver latency query is expensive; refresh at track start / resume.
	output_latency=AudioServer.get_output_latency()
	if cache_id!=folder+":"+id:
		cached=load("res://assets/%s/%s.ogg"%[folder,id]);cache_id=folder+":"+id
	player.stream=cached;player.pitch_scale=rate
func start(at:float)->void:
	if started:return
	if web_enabled:
		started=true;last_clock=maxf(0,at);web_driver.start(web_id,at);return
	if player.stream==null:return
	started=true;last_clock=maxf(0,at);start_position=last_clock;player.play(last_clock)
func raw_time()->float:
	if web_enabled:return float(web_driver.time(web_id))
	return player.get_playback_position()+(AudioServer.get_time_since_last_mix()-output_latency)*rate
func time()->float:
	if not started:return 0
	if web_enabled:
		last_clock=maxf(last_clock,raw_time());return last_clock
	var wall:=Time.get_ticks_usec()/1000000.0
	if not player.playing and not player.stream_paused:
		if ended_at<0:ended_at=wall
		last_clock=maxf(last_clock,player.stream.get_length()+(wall-ended_at)*rate)
		return last_clock
	if player.stream_paused:return last_clock
	var raw:=raw_time()
	# The count-in absorbs decoder startup before locking the clock.
	if raw-start_position>=.25 and wall-sample_at>=.02:
		sample_at=wall;offsets.append(raw-wall*rate)
		if offsets.size()>31:offsets.pop_front()
		if offsets.size()>=6:
			var sorted:Array=offsets.duplicate();sorted.sort()
			var target:float=sorted[sorted.size()/2]
			if not clock_locked:clock_offset=target;clock_locked=true
			else:clock_offset+=clampf((target-clock_offset)*.02,-.0005,.0005)
	var value:float=wall*rate+clock_offset if clock_locked else raw
	last_clock=maxf(last_clock,value)
	return last_clock
func pause(value:bool)->void:
	if web_enabled:
		web_driver.pause(web_id,value);last_clock=maxf(last_clock,raw_time());return
	if value and started:time()
	player.stream_paused=value
	if not value:
		output_latency=AudioServer.get_output_latency()
		var wall:=Time.get_ticks_usec()/1000000.0
		clock_offset=last_clock-wall*rate;sample_at=wall;offsets.clear()
func volume(master:float,music:float)->void:
	if web_enabled:
		web_driver.volume(web_id,master*music*.85);return
	player.volume_db=linear_to_db(maxf(.00001,master*music*.85))
func stop()->void:
	if web_enabled:web_driver.stop(web_id)
	if is_instance_valid(player):player.stop();player.stream_paused=false
	started=false;last_clock=0;track_id="";ended_at=-1;clock_locked=false;offsets.clear();sample_at=-1

func loading()->bool:
	return web_enabled and str(web_driver.state(web_id)) in ["loading","ready","locked"]
func failure()->String:
	return str(web_driver.error(web_id)) if web_enabled else ""
func _exit_tree()->void:
	if web_enabled:web_driver.dispose(web_id)
