extends Node

static var shared_streams: Dictionary = {}

var enabled := true
var volume := 0.55
var players: Array[AudioStreamPlayer] = []
var streams: Dictionary = {}
var cursor := 0
var ranker_miss_at := -10.0
var ranker_accent_at := -10.0

func _ready() -> void:
	if shared_streams.is_empty():
		for i in range(8):
			streams["note%d"%i] = tone([261.63,293.66,329.63,392.0,440.0,523.25,587.33,659.25][i],0.13,0)
		streams["tick"] = tone(1100,0.035,1)
		streams["count"] = tone(660,0.08,0)
		streams["go"] = tone(880,0.14,0)
		streams["miss"] = tone(110,0.09,2)
		streams["perfect"] = tone(1046.5,0.065,0)
		streams["hold"] = tone(392,0.045,0)
		streams["kick"] = tone(75,.11,2)
		streams["hat"] = tone(6200,.025,1)
		for i in range(4):streams["bass%d"%i]=tone([65.41,73.42,87.31,98.0][i],.22,0)
		# Dry, unpitched transients leave the song's actual melody in front.
		for kind in ["upper","lower","accent","release","soft_miss","phrase"]:
			streams["ranker_"+kind]=ranker_transient(kind)
		shared_streams=streams
	else:
		streams=shared_streams
	for i in range(6):
		var player := AudioStreamPlayer.new()
		player.max_polyphony = 2
		add_child(player)
		players.append(player)

func tone(frequency: float, duration: float, kind: int) -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate*duration)
	var data := PackedByteArray()
	data.resize(count*2)
	for i in range(count):
		var t := float(i)/rate
		var envelope := minf(1,t/0.004)*pow(1-float(i)/count,2)
		var wave := sin(t*TAU*frequency)*0.72+sin(t*TAU*frequency*2)*0.2+sin(t*TAU*frequency*3)*0.08
		if kind==1: wave = sin(t*TAU*frequency)*sin(t*TAU*1897)
		elif kind==2: wave = sin(t*TAU*(frequency*(1-t/duration*0.5)))
		data.encode_s16(i*2,int(clampf(wave*envelope*11000,-32767,32767)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream

func play(key: String, gain := 1.0) -> void:
	if not enabled or volume<=0 or players.is_empty() or not streams.has(key): return
	var player := players[cursor%players.size()]
	cursor += 1
	player.stream = streams[key]
	player.volume_db = linear_to_db(maxf(0.001,volume*gain))
	player.play()

func note(index: int, gain := 1.0) -> void:
	play("note%d"%posmod(index,8),gain)

func ranker_transient(kind:String) -> AudioStreamWAV:
	var durations:Dictionary={"upper":.037,"lower":.043,"accent":.024,"release":.060,"soft_miss":.070,"phrase":.125}
	var duration:float=durations.get(kind,.037)
	var rate:=22050
	var count:=roundi(duration*rate)
	var data:=PackedByteArray();data.resize(count*2)
	var noise_seed:=81729
	var previous:=0.0
	var low:=0.0
	for i in range(count):
		noise_seed=(noise_seed*1664525+1013904223)&0x7fffffff
		var noise:=float(noise_seed)/1073741824.0-1.0
		var high:float=(noise-previous)*.5
		previous=noise;low=lerpf(low,noise,.16)
		var t:=float(i)/rate
		var envelope:=minf(1,t/.0007)*minf(1,(duration-t)/.004)
		var sample:=0.0
		match kind:
			"upper":sample=(high*.50+sin(TAU*(1380*t-4100*t*t))*.37)*exp(-t*104)
			"lower":sample=(high*.30+sin(TAU*(780*t-2300*t*t))*.48)*exp(-t*87)
			"accent":sample=(high*.69+sin(TAU*3200*t)*.14)*exp(-t*150)
			"release":sample=(high*.52+low*.20)*exp(-t*51)
			"soft_miss":sample=(low*.68+sin(TAU*145*t)*.15)*exp(-t*58)
			"phrase":
				# A tiny brushed double-clap confirms a phrase without adding a tune.
				var response:=maxf(0,t-.043)
				var echo:float=.52*exp(-response*90)*minf(1,response/.001) if t>.043 else 0
				sample=(high*.58+low*.12)*(exp(-t*70)+echo)
		data.encode_s16(i*2,roundi(clampf(sample*envelope*15000,-30000,30000)))
	var stream:=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=rate;stream.data=data
	return stream

func ranker_press(lane:int) -> void:
	play("ranker_upper" if lane==0 else "ranker_lower",.40)

func ranker_judge(judgment:int,lane:int,is_hold:=false) -> void:
	if not enabled or volume<=0:return
	var time:=Time.get_ticks_usec()/1000000.0
	if judgment>=3:
		# Simultaneous misses and a late frame produce one soft acknowledgement.
		if time-ranker_miss_at>=.075:
			ranker_miss_at=time;play("ranker_soft_miss",.22)
	elif is_hold:
		play("ranker_release",.24 if lane==0 else .22)
	elif judgment==0 and time-ranker_accent_at>=.035:
		ranker_accent_at=time;play("ranker_accent",.10)

func ranker_phrase(quality:int) -> void:
	if quality<0 or quality>=3:return
	play("ranker_phrase",.18 if quality==0 else .13 if quality==1 else .09)

func fanfare() -> void:
	var t := create_tween()
	for i in [0,2,3,5]:
		t.tween_callback(note.bind(i))
		t.tween_interval(0.09)


func backing(step: int, region: int) -> void:
	play("hat",.08)
	if step%2==0:play("kick",.25)
	if step%4==2:play("tick",.09)
	if step%4==0:play("bass%d"%posmod(step/8+region,4),.28)
