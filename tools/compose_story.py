"""Render original PERFECTO songs from the same authored grids as Maps.chart.
Developer regeneration: python tools/compose_story.py (requires numpy and ffmpeg).
No samples, external songs or recordings are used. Runtime uses committed Oggs.
"""
import json,math,re,subprocess,tempfile,wave
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
RATE=22050
ARRANGEMENT=[0,1,0,2,0,1,3,2,0,2,1,3,2,1,0,3,0,2,1,3]
TITLES=['First Signal','Pocket Lights','Little Satellites','Neon Guardian','Amber Breath','Crystal Bridge','Crossing Signals','Prism Sentinel','Swing Skyline','Electric Steps','Glass Tempest','Perfect Sky']
def catalog():
    text=(ROOT/'gameplay/maps.gd').read_text()
    return json.loads(re.search(r'cached = (\[.*?\n\t\])',text,re.S).group(1))
def events(item):
    beat=60/item['bpm'];out=[]
    for bar in range(item['bars']):
        for cell,token in enumerate(item['phrases'][ARRANGEMENT[bar]]):
            if token in 'xHL':out.append(dict(t=(bar*4+cell*.5)*beat,d=(2 if token=='L' else 1)*beat if token!='x' else 0,bar=bar,cell=cell))
    return out
def compose(item):
    beat=60/item['bpm'];length=item['bars']*4*beat+.8
    mix=np.zeros((math.ceil(length*RATE),2),dtype=np.float64)
    rng=np.random.default_rng(17287+int(item['id'][1:]))
    region=item['region'];root=[48,50,45][region]
    scale=[[0,2,4,7,9,12,14,16],[0,2,3,7,10,12,14,15],[0,3,5,7,10,12,15,17]][region]
    progression=[0,5,9,7] if region==0 else [0,8,3,10] if region==1 else [0,5,8,7]
    def add(at,sound,gain=1,pan=0):
        start=round(at*RATE)
        n=min(len(sound),len(mix)-start)
        if n<=0:return
        mix[start:start+n,0]+=sound[:n]*gain*math.sqrt((1-pan)/2)
        mix[start:start+n,1]+=sound[:n]*gain*math.sqrt((1+pan)/2)
    def synth(midi,duration,kind='pluck'):
        t=np.arange(max(1,round(duration*RATE)))/RATE;freq=440*2**((midi-69)/12)
        if kind=='pad':
            env=np.minimum(t/.045,1)*np.minimum((duration-t)/.12,1)
            sig=np.sin(2*np.pi*freq*t)+.25*np.sin(2*np.pi*freq*2.003*t)
        elif kind=='bass':
            env=np.minimum(t/.006,1)*np.exp(-t*5)*np.minimum((duration-t)/.02,1)
            sig=np.sin(2*np.pi*freq*t)+.3*np.sin(2*np.pi*freq*2*t)
        else:
            env=np.minimum(t/.004,1)*(.55+.45*np.exp(-t*12))*np.minimum((duration-t)/.045,1)
            sig=np.sin(2*np.pi*freq*t)+.28*np.sin(2*np.pi*freq*2*t)*np.exp(-t*8)+.12*np.sin(2*np.pi*freq*3*t)*np.exp(-t*10)
        return sig*env
    def drum(kind):
        duration={'kick':.2,'snare':.13,'hat':.05}[kind];t=np.arange(round(duration*RATE))/RATE
        if kind=='kick':return np.sin(2*np.pi*(47*t+80*.022*(1-np.exp(-t/.022))))*np.exp(-t*22)
        noise=rng.uniform(-1,1,len(t));noise=np.concatenate(([0],np.diff(noise)))*.5
        return noise*np.exp(-t*(42 if kind=='snare' else 100))+(np.sin(2*np.pi*180*t)*np.exp(-t*40)*.18 if kind=='snare' else 0)
    for bar in range(item['bars']):
        chord=root+progression[(bar//2)%4];section=min(3,bar*4//item['bars']);power=[.65,.9,.72,1][section]
        for interval in ([0,4,7] if region==0 else [0,3,7]):
            add(bar*4*beat,synth(chord+interval,beat*3.85,'pad'),.045*power,pan=(interval-3)/12)
        for b in range(4):
            at=(bar*4+b)*beat
            add(at,drum('kick'),.24*power)
            if b%2:add(at,drum('snare'),.14*power,.12)
            add(at,synth(chord-12+(7 if b==3 else 0),beat*.65,'bass'),.19*power,-.15)
            for half in range(2):add(at+half*.5*beat,drum('hat'),(.045 if half else .035)*power,.3 if half else -.3)
        if (bar+1)%4==0:
            for cell in [6,7]:add((bar*4+cell*.5)*beat,drum('snare'),.075*power)
    notes=events(item)
    for i,n in enumerate(notes):
        degree=(n['cell']+ARRANGEMENT[n['bar']]*2+n['bar']//4)%len(scale)
        midi=root+12+scale[degree]
        duration=n['d'] if n['d'] else min(.20,beat*.37)
        tone=synth(midi,duration+.035)
        add(n['t'],tone,.25,pan=.12*math.sin(i))
        # Quiet ping-pong echoes stay behind the note-aligned lead.
        add(n['t']+beat*.75,tone,.028,-.5)
        if int(item['id'][1:])%4==0 and n['bar']>=item['bars']*3//4:
            add(n['t'],synth(midi+12,min(duration,.16)),.055,.35)
    # Let the final chord release cleanly; no abrupt end, no loop seam.
    fade=np.minimum(1,np.arange(len(mix),0,-1)/(RATE*.55))
    mix=np.tanh(mix*1.3)*fade[:,None]
    peak=float(np.max(np.abs(mix)));mix*=.86/max(.86,peak)
    pcm=np.rint(mix*32767).astype('<i2')
    return pcm,notes,length,float(np.sqrt(np.mean(mix**2)))
def main():
    folder=ROOT/'assets/music';folder.mkdir(exist_ok=True);manifest=[]
    with tempfile.TemporaryDirectory() as tmp:
        for index,item in enumerate(catalog()):
            pcm,notes,length,rms=compose(item);wav=Path(tmp)/'song.wav'
            lead_in=4*60/item['bpm'];intro=np.zeros((round(lead_in*RATE),2),dtype=np.float64)
            for count in range(4):
                t=np.arange(round(.045*RATE))/RATE;click=np.sin(2*np.pi*(1320 if count==0 else 990)*t)*np.exp(-t*75)*np.minimum(t/.002,1)*.22
                at=round(count*60/item['bpm']*RATE);intro[at:at+len(click)]+=click[:,None]
            pcm=np.concatenate((np.rint(intro*32767).astype('<i2'),pcm));length+=lead_in
            with wave.open(str(wav),'wb') as w:w.setnchannels(2);w.setsampwidth(2);w.setframerate(RATE);w.writeframes(pcm.tobytes())
            path=folder/(item['id']+'.ogg')
            subprocess.run(['ffmpeg','-v','error','-y','-i',str(wav),'-c:a','libvorbis','-q:a','2','-metadata','title='+TITLES[index],'-metadata','artist=PERFECTO Original Soundtrack',str(path)],check=True)
            manifest.append(dict(id=item['id'],title=TITLES[index],bpm=item['bpm'],bars=item['bars'],duration=length,audio_offset=lead_in,notes=[{'t':round(n['t'],5),'d':round(n['d'],5)} for n in notes],rms=round(rms,4)))
            print(item['id'],TITLES[index],round(length,2),'seconds',path.stat().st_size,'bytes',flush=True)
    (folder/'score.json').write_text(json.dumps(manifest,ensure_ascii=False,separators=(',',':'))+'\n')
if __name__=='__main__':main()
