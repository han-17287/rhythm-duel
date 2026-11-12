extends Node

static var shared_streams: Dictionary = {}

var enabled := true
var volume := 0.55
var players: Array[AudioStreamPlayer] = []
var streams: Dictionary = {}
var cursor := 0

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
