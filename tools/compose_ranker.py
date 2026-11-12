"""Original hard rhythm charts + electronic soundtrack. Regenerate with numpy/ffmpeg."""
import json,math,subprocess,tempfile,wave
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1];RATE=22050
SONGS=[
 dict(id='r01',title='PULSE ENGINE',subtitle='가속하는 심장',bpms=[168,192,168,210],level=11,color='68ffe0',root=45,section_bars=40,voice='anthem'),
 dict(id='r02',title='FRACTURE',subtitle='깨진 박자',bpms=[190,220,190,240],level=14,color='ffbd73',root=43,section_bars=40,voice='glitch'),
 dict(id='r03',title='IRREGULAR ORBIT',subtitle='궤도 이탈',bpms=[180,210,240,210],level=17,color='b89aff',root=47,section_bars=44,voice='orbit'),
 dict(id='r04',title='EVENT HORIZON',subtitle='사건의 지평선',bpms=[210,240,260,280],level=20,color='ff719b',root=42,section_bars=48,voice='finale'),
]
PATTERNS=[
 [0,.5,1,1.5,2,2.5,3,3.5],
 [0,.75,1,1.75,2,2.75,3,3.75],
 [0,.5,1,1.5,2,2.75,3.25,3.75],
 [0,1/3,2/3,1,1.5,2,7/3,8/3,3,3.5],
 [0,.5,1,1.75,2.25,2.75,3.25,3.75],
 [0,.5,.75,1.25,1.75,2.25,2.75,3.25,3.75],
 [i/3 for i in range(12)],
 [i*.4 for i in range(10)],
]
def chart(song):
    bars=[];one=[];double=[];time=0;ordinal=0
    for bar in range(song['section_bars']*4):
        section=bar//song['section_bars'];bpm=song['bpms'][section];beat=60/bpm
        beats=(3 if bar%4==2 else 5 if bar%4==3 else 4) if song['id']=='r03' else 4
        bars.append(dict(t=round(time,5),bpm=bpm,beats=beats,section=section))
        sequences={'r01':[0,2,1,0,0,2,1,3,0,2,0,1],'r02':[4,1,5,2,4,5,1,3,5,4,2,5],'r03':[3,0,6,4,3,6,2,3,6,4,0,3],'r04':[0,7,5,7,6,7,4,7,7,6,5,7]}
        index=sequences[song['id']][bar%12]
        local=bar%song['section_bars']
        if song['id']=='r01' and section==0:index=[0,2,1,0][bar%4]
        # Eight-bar call/response phrases and a genuine breakdown before the final build.
        breakdown=section==2 and local<8
        if breakdown:index=[0,1,2,0][bar%4]
        elif local>=song['section_bars']-8 and section in (1,3):index=([3,6,5,7][bar%4] if song['id'] in ('r03','r04') else [2,3,5,0][bar%4])
        offsets=[v for v in PATTERNS[index] if v<beats]
        if breakdown:offsets=offsets[::2]
        if local<4 and section==0:offsets=offsets[::2]
        if bar%8==7:offsets=[v for v in offsets if v<beats-.5]
        if beats==5:offsets += ([4,13/3,14/3] if index==6 else [4,4.5])
        # Single-key holds occur only in dedicated gaps. Double adds notes against them.
        hold=bar%12==10
        if hold:offsets=[0,.5,1,1.5,2];offsets=[v for v in offsets if v<beats]
        last=-10
        for j,value in enumerate(offsets):
            at=time+value*beat
            if at-last<.075:continue
            d=1.5*beat if hold and value==2 and beats>=4 else 0
            one.append(dict(t=round(at,5),d=round(d,5)))
            lane=ordinal%2
            double.append(dict(t=round(at,5),d=round(d,5),lane=lane))
            if d:
                for off in [.5,1,1.5]:double.append(dict(t=round(at+off*beat,5),d=0,lane=1-lane))
            last=at+d;ordinal+=1
        # Hand-to-hand sixteenth bursts and simultaneous chord accents.
        if not hold:
            if bar%4 in (1,3) and section>0 and not breakdown:
                for value in [k*.25 for k in range(beats*4)]:
                    if any(abs(time+value*beat-n['t'])<.001 for n in double[-24:]):continue
                    lane=(int(value*4)+bar)%2
                    double.append(dict(t=round(time+value*beat,5),d=0,lane=lane))
            if bar%4==0:
                at=time
                existing=next(n for n in double if abs(n['t']-at)<.001)
                double.append(dict(t=round(at,5),d=0,lane=1-existing['lane']))
        time+=beats*beat
    double.sort(key=lambda n:(n['t'],n['lane']))
    # Resolve lane-near collisions deterministically; cross-lane simultaneous notes remain.
    clean=[];ends=[-10,-10]
    for n in double:
        lane=n['lane']
        if n['t']-ends[lane]<.075:continue
        clean.append(n);ends[lane]=n['t']+n['d']
    single=[];last_end=-10
    for n in one:
        if n['t']-last_end>=.075:single.append(n);last_end=n['t']+n['d']
    one=single
    return dict(section_bars=song['section_bars'],bars=bars,duration=round(time+.65,5),audio_offset=round(4*60/song['bpms'][0],8),charts={'one':one,'double':clean})
def render(song,data,path):
    """Phrase-based arrangement; every playable attack is an audible lead/countervoice.

    Original motifs, modal chord progressions, synthesized instruments and drums.
    No recorded samples or melodies from reference tracks are used.
    """
    preroll=data['audio_offset'];duration=data['duration']+preroll
    mix=np.zeros((math.ceil(duration*RATE),2),dtype=np.float64)
    rng=np.random.default_rng(8172+int(song['id'][1:]));root=song['root']
    def add(at,sound,gain,pan=0):
        start=round((at+preroll)*RATE)
        if start<0:return
        n=min(len(sound),len(mix)-start)
        if n>0:
            mix[start:start+n,0]+=sound[:n]*gain*math.sqrt((1-pan)/2)
            mix[start:start+n,1]+=sound[:n]*gain*math.sqrt((1+pan)/2)
    def tone(midi,length,kind='lead',bright=1):
        t=np.arange(max(1,round(length*RATE)))/RATE;f=440*2**((midi-69)/12)
        release=np.minimum(np.maximum(length-t,0)/min(.04,length*.3),1)
        attack=np.minimum(t/(.045 if kind=='pad' else .0025),1)
        if kind=='bass':
            phase=2*np.pi*f*t
            return (np.sin(phase)+.22*np.sin(phase*2+1.7*np.sin(phase)*np.exp(-t*8)))*attack*release*np.exp(-t*6)
        if kind=='pad':
            signal=(np.sin(2*np.pi*f*t)+np.sin(2*np.pi*f*1.002*t)+.15*np.sin(2*np.pi*f*2*t))/2.15
            return signal*attack*release
        # Piano-like inharmonic hammer transient with a warm, stable pitched body.
        piano=np.sin(2*np.pi*f*t)*np.exp(-t*5)
        for harmonic in [2,3,4,6]:
            if f*harmonic<RATE*.45:piano+=.38/harmonic*np.sin(2*np.pi*f*(harmonic+.001*harmonic**2)*t)*np.exp(-t*(5+harmonic*2))
        if kind=='piano':return piano*attack*release
        signal=np.zeros(len(t))
        for harmonic in range(1,8):
            if f*harmonic<RATE*.45:
                signal+=(np.sin(2*np.pi*f*harmonic*t)+np.sin(2*np.pi*f*1.003*harmonic*t))*(.5/harmonic**1.6)*np.exp(-t*(2+harmonic*bright*1.8))
        return (signal*.72+piano*.38)*attack*release
    def drum(kind):
        length={'kick':.26,'snare':.17,'hat':.045,'crash':.75}[kind]
        t=np.arange(round(length*RATE))/RATE
        if kind=='kick':
            return (np.sin(2*np.pi*(47*t+108*.019*(1-np.exp(-t/.019))))*np.exp(-t*19)+.08*rng.uniform(-1,1,len(t))*np.exp(-t*180))*np.minimum(t/.0008,1)
        noise=rng.uniform(-1,1,len(t));high=np.concatenate(([0],np.diff(noise)))*.5
        if kind=='snare':return (.7*high*np.exp(-t*30)+.3*np.sin(2*np.pi*185*t)*np.exp(-t*35))*np.minimum(t/.001,1)
        return high*np.exp(-t*(110 if kind=='hat' else 6))*np.minimum(t/.001,1)
    drums={kind:drum(kind) for kind in ['kick','snare','hat','crash']}
    for count in range(4):
        t=np.arange(round(.045*RATE))/RATE
        click=np.sin(2*np.pi*(1320 if count==0 else 990)*t)*np.exp(-t*75)*np.minimum(t/.002,1)
        add(-preroll+count*60/song['bpms'][0],click,.18)
    scales={'anthem':[0,2,3,5,7,8,10,12],'glitch':[0,1,3,5,7,8,10,12],
            'orbit':[0,2,3,5,7,9,10,12],'finale':[0,2,3,5,7,8,11,12]}
    scale=scales[song['voice']]
    progression=[0,5,2,6,0,3,5,6]
    # Eight memorable phrases: recurring motifs with answering cadences.
    motifs=[[0,2,4,5,4,2,1,2],[4,5,7,6,5,4,2,1],
            [0,1,2,4,2,1,0,4],[7,6,4,5,4,2,1,0],
            [2,4,5,7,5,4,2,1],[0,2,1,4,2,5,4,2],
            [4,2,0,1,2,4,6,5],[7,5,4,2,1,2,1,0]]
    bar_for_note=[]
    for i,bar in enumerate(data['bars']):
        local=i%song['section_bars'];section=bar['section'];beat=60/bar['bpm']
        bar_length=bar['beats']*beat
        degree=progression[(i//2)%8] if i<len(data['bars'])-2 else 0
        chord=root+scale[degree]-(12 if degree>=4 else 0)
        intervals=[scale[(degree+step)%7]+12*((degree+step)//7)-scale[degree] for step in [0,2,4,6]]
        breakdown=section==2 and local<8
        intro=section==0 and local<4
        energy=[.73,1.0,.88,1.1][section]
        if breakdown:energy=.38
        elif intro:energy=.48+local*.07
        for step in range(bar['beats']):
            at=bar['t']+step*beat
            if not breakdown or step==0:add(at,drums['kick'],.37*energy)
            if step%2 and not intro:add(at,drums['snare'],.22*energy,.08)
            add(at,tone(chord-12+(intervals[2] if step==3 else 0),beat*.75,'bass'),.25*energy,-.05)
            if not breakdown:
                add(at+.5*beat,tone(chord-12,beat*.28,'bass'),.08*energy,-.05)
            for half in range(2):add(at+half*.5*beat,drums['hat'],.055*energy,(-.4 if half else .4))
        # Spacious chords; leave the beat's transient clear using slow pad attacks.
        for interval in intervals:add(bar['t'],tone(chord+interval,bar_length*.94,'pad'),.035*energy,(interval-5)*.085)
        if i%8==0 and not intro:add(bar['t'],drums['crash'],.14*energy,-.3)
        if i%8==7 and not breakdown:
            for fill in range(4):add(bar['t']+bar_length-(4-fill)*beat*.25,drums['snare'],(.025+fill*.012)*energy,(fill-1.5)*.2)
        # A rising four-beat swell and a clean impact prepare every tempo change.
        if local==song['section_bars']-1 and section<3:
            t=np.arange(round(bar_length*RATE))/RATE;u=t/bar_length
            sweep=np.sin(2*np.pi*(220*t+550*t*t/bar_length))*.25
            noise=rng.uniform(-1,1,len(t));noise=np.concatenate(([0],np.diff(noise)))*.25
            add(bar['t'],(sweep+noise)*u**2*np.minimum((bar_length-t)/.02,1),.10,.25)
        bar_for_note.append((bar,energy,breakdown,chord))
    bar_index=0
    for i,n in enumerate(data['charts']['one']):
        while bar_index+1<len(data['bars']) and data['bars'][bar_index+1]['t']<=n['t']+.00001:bar_index+=1
        bar,energy,breakdown,chord=bar_for_note[bar_index];beat=60/bar['bpm']
        position=(n['t']-bar['t'])/beat
        motif=motifs[(bar_index//2)%8]
        degree=motif[int(position*2+.001)%8]
        octave=12 if bar['section'] in (1,3) and bar_index%8>=4 else 0
        midi=root+12+scale[degree]+octave
        if i==len(data['charts']['one'])-1:midi=root+12
        next_gap=(data['charts']['one'][i+1]['t']-n['t']) if i+1<len(data['charts']['one']) else .3
        length=n['d']+.025 if n['d']>0 else max(.06,min(.23,next_gap*.85))
        kind='piano' if breakdown or song['voice']=='orbit' and bar['section']==0 else 'lead'
        sound=tone(midi,length,kind,1.3 if song['voice']=='glitch' else .8)
        add(n['t'],sound,.30 if breakdown else .27,.12*math.sin(bar_index*.45))
        # Stereo eighth-note echoes have much lower gain than the playable attacks.
        add(n['t']+beat*.75,sound,.025,-.52)
        add(n['t']+beat*1.5,sound,.012,.52)
    primary={round(n['t'],4) for n in data['charts']['one']}
    bar_index=0
    for i,n in enumerate(data['charts']['double']):
        if round(n['t'],4) in primary:continue
        while bar_index+1<len(data['bars']) and data['bars'][bar_index+1]['t']<=n['t']+.00001:bar_index+=1
        bar,energy,breakdown,chord=bar_for_note[bar_index]
        midi=root+24+scale[motifs[(bar_index//2)%8][i%8]]
        add(n['t'],tone(midi,max(.055,min(.14,n['d']+.07)),'piano'),.11,-.48 if n['lane']==0 else .48)
    # Gentle bus saturation and high-pass DC removal; peak-normalize without clipping.
    mix-=mix.mean(axis=0)
    mix=np.tanh(mix*1.25)
    mix*=np.minimum(1,np.arange(len(mix),0,-1)/(RATE*.55))[:,None]
    mix*=.90/max(.90,float(np.max(np.abs(mix))))
    pcm=np.rint(mix*32767).astype('<i2')
    with tempfile.TemporaryDirectory() as folder:
        wav=Path(folder)/'song.wav'
        with wave.open(str(wav),'wb') as w:
            w.setnchannels(2);w.setsampwidth(2);w.setframerate(RATE);w.writeframes(pcm.tobytes())
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(wav),'-c:a','libvorbis','-q:a','4','-metadata','title='+song['title'],'-metadata','artist=PERFECTO Ranker Original',str(path)],check=True)

def main():
    folder=ROOT/'assets/ranker';folder.mkdir(exist_ok=True);catalog=[]
    for song in SONGS:
        data={**song,**chart(song)};render(song,data,folder/(song['id']+'.ogg'));catalog.append(data)
        print(song['id'],data['duration'],{k:len(v) for k,v in data['charts'].items()},flush=True)
    (folder/'catalog.json').write_text(json.dumps(catalog,separators=(',',':'),ensure_ascii=False)+'\n')
if __name__=='__main__':main()
