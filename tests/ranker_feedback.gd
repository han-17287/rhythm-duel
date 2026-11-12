extends SceneTree
const Bank=preload("res://gameplay/sound_bank.gd")
const Feedback=preload("res://gameplay/ranker_feedback.gd")
class Fixture extends Control:
	var ranker_id:="r01"
	var phase:="play"
	var paused:=false
	var double_mode:=false
	var preferences=preload("res://gameplay/preferences.gd").new()
	func is_double()->bool:return double_mode
var checks:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->bool:
	checks+=1
	if not value:push_error(message);quit(1)
	return value
func run()->void:
	var bank=Bank.new();root.add_child(bank);await process_frame
	for kind in ["upper","lower","accent","release","soft_miss","phrase"]:
		var stream:AudioStreamWAV=bank.streams["ranker_"+kind]
		if not check(stream.get_length()>=.02 and stream.get_length()<=.126,"Feedback sample duration "+kind):return
		var energy:=0.0;var peak:=0
		for index in range(stream.data.size()/2):
			var sample:=stream.data.decode_s16(index*2)
			energy+=float(sample)*sample;peak=maxi(peak,absi(sample))
		if not check(energy>100000 and peak<30000,"Feedback sample nonzero and unclipped "+kind):return
		if not check(absi(stream.data.decode_s16(stream.data.size()-2))<100,"Sample release ends quietly "+kind):return
	if not check(bank.streams.ranker_upper.data!=bank.streams.ranker_lower.data,"The two lanes need distinct transients"):return
	var before:int=bank.cursor
	bank.volume=0;bank.ranker_press(0);bank.ranker_judge(0,0);bank.ranker_phrase(0)
	if not check(bank.cursor==before,"Muted feedback cannot start a player"):return
	bank.volume=.55;bank.enabled=false;bank.ranker_press(1);bank.ranker_judge(3,1);bank.ranker_phrase(1)
	if not check(bank.cursor==before,"Disabled feedback cannot start a player"):return
	bank.enabled=true;bank.ranker_press(0)
	if not check(bank.players[(bank.cursor-1)%bank.players.size()].stream==bank.streams.ranker_upper,"Upper lane sample"):return
	bank.ranker_press(1)
	if not check(bank.players[(bank.cursor-1)%bank.players.size()].stream==bank.streams.ranker_lower,"Lower lane sample"):return
	bank.ranker_judge(1,0,true)
	if not check(bank.players[(bank.cursor-1)%bank.players.size()].stream==bank.streams.ranker_release,"Hold release sample"):return
	before=bank.cursor;bank.ranker_judge(3,0);bank.ranker_judge(3,1)
	if not check(bank.cursor==before+1,"Simultaneous misses have one quiet acknowledgement"):return
	before=bank.cursor;bank.ranker_phrase(3)
	if not check(bank.cursor==before,"An unfinished phrase is silent"):return
	bank.note(2)
	if not check(bank.players[(bank.cursor-1)%bank.players.size()].stream==bank.streams.note2,"Duel/story note API unchanged"):return
	var second=Bank.new();root.add_child(second)
	if not check(second.streams.ranker_upper==bank.streams.ranker_upper,"Ranker samples are synthesized once and shared"):return
	var fixture:=Fixture.new();root.add_child(fixture)
	var feedback=Feedback.new();fixture.add_child(feedback);feedback.setup(fixture)
	fixture.double_mode=true
	for index in range(100):feedback.hit(index%2,index%3,index%7==0)
	if not check(feedback.events.size()==Feedback.MAX_EVENTS,"Rapid input keeps a bounded queue"):return
	feedback.stray(1)
	if not check(feedback.events[-1].extra and feedback.events[-1].j==3,"Stray input uses miss feedback"):return
	feedback.phrase(0,"PERFECT PHRASE")
	if not check(feedback.phrase_life>0 and feedback.phrase_quality==0,"Phrase success has a restrained pulse"):return
	fixture.paused=true;var life:float=feedback.events[-1].life;feedback._process(.1);feedback.hit(0,0)
	if not check(feedback.events[-1].life==life and feedback.events.size()==Feedback.MAX_EVENTS,"Pause freezes event aging and blocks new feedback"):return
	fixture.paused=false;feedback._process(.6)
	if not check(feedback.events.is_empty() and feedback.phrase_life==0,"All effects expire"):return
	fixture.preferences.values.reduced_motion=true;feedback.hit(0,0);feedback.phrase(0,"quiet")
	if not check(feedback.events.is_empty() and feedback.phrase_life==0,"Reduced motion suppresses decorative motion"):return
	fixture.preferences.values.reduced_motion=false;feedback.hit(0,0);fixture.preferences.values.effects=false;feedback._process(.01)
	if not check(feedback.events.is_empty(),"Turning effects off clears existing effects"):return
	fixture.preferences.values.effects=true;feedback.hit(1,0);fixture.phase="lobby";feedback._process(.01)
	if not check(feedback.events.is_empty(),"Leaving play clears effects"):return
	for player in bank.players:player.stop();player.stream=null
	for player in second.players:player.stop();player.stream=null
	await create_timer(.15).timeout
	feedback=null;fixture.queue_free();bank.queue_free();second.queue_free();await process_frame
	print("RANKER_FEEDBACK_OK: %d checks; dry cached lane transients, gain/mute, hold release, bounded fixed-gate feedback, pause/reduced motion"%checks)
	quit()
