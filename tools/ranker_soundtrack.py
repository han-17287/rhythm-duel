"""Original sampled-instrument arrangements. Development-only FluidSynth renderer.

Foreground onsets come directly from the playable score. Accompaniment, harmony,
phrasing and GM instruments differ by song; no external melodies are copied.
Requires libfluidsynth, numpy, ffmpeg and the MIT-licensed FluidR3_GM SoundFont.
Set RANKER_SOUNDFONT to its path. Finished Oggs need none of these at runtime.
"""
import ctypes as C
import ctypes.util
import hashlib
import math
import os
from pathlib import Path
import subprocess
import tempfile
import wave

RATE=44100
PROFILES={
 'r01':dict(genre='PIANO FUSION',subtitle='피아노 · 어쿠스틱 드럼 · 클린 기타',programs=[0,26,11,48,33],key=57,scale=[0,2,3,5,7,9,10],progression=[0,5,3,4,0,2,5,4],motif=[0,2,4,6,5,2,1,4],drums='fusion'),
 'r02':dict(genre='GUITAR ROCK',subtitle='일렉 기타 · 록 드럼 · 피아노',programs=[30,0,29,48,34,0],key=52,scale=[0,2,3,5,7,8,10],progression=[0,0,5,3,0,6,3,4],motif=[0,4,7,4,3,2,0,-1],drums='rock'),
 'r03':dict(genre='VIOLIN CHAMBER',subtitle='바이올린 · 피아노 · 피치카토',programs=[40,0,45,42,43],key=62,scale=[0,2,3,5,7,8,11],progression=[0,3,5,1,4,0,3,4],motif=[4,5,7,6,4,2,3,1],drums='chamber'),
 'r04':dict(genre='SYMPHONIC ROCK',subtitle='피아노 · 바이올린 · 기타 · 드럼',programs=[0,40,30,48,34,40],key=54,scale=[0,2,3,5,7,8,11],progression=[0,5,3,4,0,2,5,4],motif=[0,7,4,5,2,6,4,1],drums='symphonic'),
}

def pitch(profile,degree,octave=0):
    return profile['key']+profile['scale'][degree%7]+12*(degree//7+octave)


def arrange(song,data):
    """Return one canonical performance used by rendering and onset-contract tests.

    Each note records its source ('score' or 'backing'), instrument and exact
    chart-relative time. GM programs are zero-based; channel 9 is acoustic drums.
    """
    p=PROFILES[song['id']];bars=data['bars'];events=[]
    def add(t,d,ch,n,v,source='backing',score_index=-1):
        if t>=data['duration'] or d<=0:return
        events.append(dict(t=round(t,5),d=round(min(d,data['duration']-t),5),ch=ch,midi=max(21,min(108,int(n))),velocity=max(1,min(120,int(v))),source=source,score_index=score_index))
    # Acoustic stick count-in, with the exact existing four-beat pre-roll.
    for i in range(4):add(-data['audio_offset']+i*60/song['bpms'][0],.035,9,37,65 if i==0 else 46)
    for i,b in enumerate(bars):
        beat=60/b['bpm'];beats=b['beats'];sec=b['section'];local=i%song['section_bars'];pos=local%8
        intro=sec==0 and local<4;bridge=sec==2 and local<8;rest=pos==7
        chord=p['progression'][(local//4+sec*2)%8]
        energy=[.78,.94,.72,1.0][sec]*(.65 if intro else .55 if bridge else 1)
        root=pitch(p,chord,-2)
        length=(beats-(1 if rest else .1))*beat
        # Voiced piano/strings support chord changes, not a constant synth pad.
        if song['id'] in ('r03','r04') or bridge:
            for j,degree in enumerate([chord,chord+2,chord+4]):
                add(b['t'],length,3,pitch(p,degree,-1),int((37 if song['id']=='r03' else 31)*energy)+j*2)
        if song['id']=='r01':
            # Left-hand broken chords and syncopated clean-guitar comping.
            for k in range(beats):
                if rest and k>=beats-1:continue
                add(b['t']+k*beat,.55*beat,4,root+(12 if k%2 else 0),69*energy)
                if not bridge and k in (1,3):
                    for j in range(3):add(b['t']+(k+.5)*beat+j*.008,.34*beat,1,pitch(p,chord+j*2,-1),43*energy)
        elif song['id']=='r02':
            # Half-time rock: palm-muted power-chord riffs, backbeat on beat 3.
            for k in [0,.5,1.5,2,2.75,3.5]:
                if k>=beats-(1 if rest else 0):continue
                add(b['t']+k*beat,.30*beat,4,root,78*energy)
                if not intro and not bridge:
                    for interval in [0,7,12]:add(b['t']+k*beat,.23*beat,2,root+12+interval,47*energy)
        elif song['id']=='r03':
            # Cello downbeats, pizzicato replies and piano arpeggios in 3/4/5.
            add(b['t'],length*.8,4,root+12,52*energy)
            for k in range(beats):
                if rest and k>=beats-1:continue
                add(b['t']+(k+.5)*beat,.34*beat,2,pitch(p,chord+(k%3)*2,-1),55*energy)
                if pos in (1,5):add(b['t']+k*beat,.42*beat,1,pitch(p,chord+(k%4)*2,-1),47*energy)
        else:
            # Orchestra-rock: alternating piano/bowed theme, guitar power chords.
            for k in range(beats):
                if rest and k>=beats-1:continue
                add(b['t']+k*beat,.65*beat,4,root+(12 if k==3 else 0),72*energy)
                if sec in (1,3) and not bridge:
                    for interval in [0,7]:add(b['t']+(k+.5)*beat,.24*beat,2,root+12+interval,50*energy)
        # Actual acoustic kit. Each song has a different groove and density.
        if not bridge:
            for k in range(beats):
                if rest and k>=beats-1:continue
                at=b['t']+k*beat
                if p['drums']=='fusion':
                    if k in (0,2):add(at,.10,9,36,91*energy)
                    if k in (1,3):add(at,.10,9,38,81*energy)
                    if k==2 and pos%2:add(at+.75*beat,.08,9,36,68*energy)
                    for h in [0,.5]:add(at+h*beat,.045,9,42,43*energy+(7 if h else 0))
                elif p['drums']=='rock':
                    if k in (0,1) or k==3 and pos%2:add(at,.12,9,36,102*energy)
                    if k==2:add(at,.12,9,38,108*energy)
                    for h in [0,.5]:add(at+h*beat,.07,9,51 if sec==3 else 42,(56 if h==0 else 40)*energy)
                elif p['drums']=='chamber':
                    if k==0:add(at,.10,9,36,50*energy)
                    if k==beats-1:add(at,.065,9,37,52*energy)
                    if sec in (1,3):add(at+.5*beat,.035,9,42,32*energy)
                else:
                    if k%2==0:add(at,.12,9,36,104*energy)
                    else:add(at,.10,9,38,94*energy)
                    add(at,.08,9,51,48*energy)
                    if sec==3:add(at+.5*beat,.08,9,36,60*energy)
            if pos==0 and not intro:add(b['t'],.7,9,49,68*energy)
            if pos==6:
                for j in range(4):add(b['t']+(beats-1+j/4)*beat,.10,9,[50,47,45,38][j],(48+j*9)*energy)
        else:
            add(b['t'],.1,9,37,35)
    bi=0
    for index,n in enumerate(data['score']):
        while bi+1<len(bars) and bars[bi+1]['t']<=n['t']+.00001:bi+=1
        b=bars[bi];local=bi%song['section_bars'];pos=local%8;sec=b['section'];beat=60/b['bpm']
        chord=p['progression'][(local//4+sec*2)%8]
        # Motifs reappear as antecedent/consequent phrases, with a harmonic answer.
        original=n['degree'];degree=p['motif'][original%8]+(7 if original>=8 else 0)
        if pos>=4:degree+=2 if sec%2 else -2
        if pos==7:degree=chord+(2 if n['voice']=='reply' else 0)
        layer=n['voice'];ch={'lead':0,'reply':1,'spark':2,'chord':3}[layer]
        if song['id']=='r04' and layer=='lead' and sec in (1,3):ch=5
        if song['id']=='r02' and layer=='lead' and sec==2 and local<8:ch=5
        midi=pitch(p,degree,0)
        if layer=='spark':midi+=12 if song['id']=='r01' else 0
        held=n['d']>=.3
        # Bowed lead remains articulated at each target; holds release at chart time.
        duration=n['d'] if held else min(.22,beat*(.55 if ch==0 else .42))
        velocity={'lead':98,'reply':80,'spark':74,'chord':65}[layer]
        velocity+=5 if n['accent'] else -5
        if sec==2 and local<8:velocity-=10
        add(n['t'],duration,ch,midi,velocity,'score',index)
    return sorted(events,key=lambda e:(e['t'],e['ch'],e['midi']))


class Synth:
    def __init__(self,font,programs):
        self.lib=C.CDLL(ctypes.util.find_library('fluidsynth'))
        signatures={
          'new_fluid_settings':(C.c_void_p,[]),'fluid_settings_setnum':(C.c_int,[C.c_void_p,C.c_char_p,C.c_double]),
          'fluid_settings_setint':(C.c_int,[C.c_void_p,C.c_char_p,C.c_int]),'new_fluid_synth':(C.c_void_p,[C.c_void_p]),
          'fluid_synth_sfload':(C.c_int,[C.c_void_p,C.c_char_p,C.c_int]),'fluid_synth_program_change':(C.c_int,[C.c_void_p,C.c_int,C.c_int]),
          'fluid_synth_cc':(C.c_int,[C.c_void_p,C.c_int,C.c_int,C.c_int]),'fluid_synth_noteon':(C.c_int,[C.c_void_p,C.c_int,C.c_int,C.c_int]),
          'fluid_synth_noteoff':(C.c_int,[C.c_void_p,C.c_int,C.c_int]),
          'fluid_synth_write_float':(C.c_int,[C.c_void_p,C.c_int,C.c_void_p,C.c_int,C.c_int,C.c_void_p,C.c_int,C.c_int]),
          'delete_fluid_synth':(None,[C.c_void_p]),'delete_fluid_settings':(None,[C.c_void_p])}
        for name,(restype,args) in signatures.items():fn=getattr(self.lib,name);fn.restype=restype;fn.argtypes=args
        self.settings=self.lib.new_fluid_settings()
        for key,value in [('synth.sample-rate',RATE),('synth.gain',.65),('synth.reverb.room-size',.38),('synth.reverb.damp',.52),('synth.reverb.level',.16),('synth.chorus.level',.12)]:self.lib.fluid_settings_setnum(self.settings,key.encode(),value)
        self.lib.fluid_settings_setint(self.settings,b'synth.polyphony',256)
        self.synth=self.lib.new_fluid_synth(self.settings)
        if self.lib.fluid_synth_sfload(self.synth,str(font).encode(),1)<0:raise RuntimeError('Cannot load SoundFont')
        for ch,program in enumerate(programs):
            self.lib.fluid_synth_program_change(self.synth,ch,program)
            self.lib.fluid_synth_cc(self.synth,ch,10,[59,77,40,67,64,58][ch])
            self.lib.fluid_synth_cc(self.synth,ch,91,[24,28,15,34,5,24][ch])
    def write(self,frames):
        import numpy as np
        out=np.zeros((frames,2),np.float32);pointer=out.ctypes.data_as(C.c_void_p)
        self.lib.fluid_synth_write_float(self.synth,frames,pointer,0,2,pointer,1,2);return out
    def close(self):self.lib.delete_fluid_synth(self.synth);self.lib.delete_fluid_settings(self.settings)


def render(song,data,path):
    import numpy as np
    font=Path(os.environ.get('RANKER_SOUNDFONT','/usr/share/sounds/sf2/FluidR3_GM.sf2'))
    if not font.is_file():raise RuntimeError('Set RANKER_SOUNDFONT to MIT-licensed FluidR3_GM.sf2; see assets/ranker/README.txt')
    p=PROFILES[song['id']];performance=arrange(song,data);synth=Synth(font,p['programs'])
    frames=math.ceil((data['duration']+data['audio_offset'])*RATE);mix=np.zeros((frames,2),np.float32)
    events=[]
    for token,n in enumerate(performance):
        start=round((n['t']+data['audio_offset'])*RATE);end=min(frames,round((n['t']+data['audio_offset']+n['d'])*RATE))
        events.extend([(start,1,token,n),(end,0,token,n)])
    events.sort(key=lambda e:(e[0],e[1]));cursor=0;active={}
    try:
        for at,on,token,n in events:
            at=max(cursor,min(frames,at))
            if at>cursor:mix[cursor:at]=synth.write(at-cursor);cursor=at
            key=(n['ch'],n['midi'])
            if on:
                if key in active:synth.lib.fluid_synth_noteoff(synth.synth,*key)
                synth.lib.fluid_synth_noteon(synth.synth,*key,n['velocity']);active[key]=token
            elif active.get(key)==token:
                synth.lib.fluid_synth_noteoff(synth.synth,*key);active.pop(key)
        if cursor<frames:mix[cursor:]=synth.write(frames-cursor)
    finally:synth.close()
    mix-=mix.mean(axis=0)
    mix*=np.minimum(1,np.arange(frames,0,-1)/(RATE*.45))[:,None]
    peak=float(np.max(np.abs(mix)));mix*=.89/max(peak,.01)
    with tempfile.TemporaryDirectory() as folder:
        wav=Path(folder)/'mix.wav'
        with wave.open(str(wav),'wb') as out:
            out.setnchannels(2);out.setsampwidth(2);out.setframerate(RATE);out.writeframes(np.rint(mix*32767).astype('<i2').tobytes())
        # Materialize the mastered PCM first. Some FFmpeg loudnorm builds retain
        # padded final packet timestamps when encoding directly to Vorbis; Godot
        # uses that Ogg granule duration even if a decoder discards the padding.
        mastered=Path(folder)/'master.wav'
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(wav),'-af',f'loudnorm=I=-16:TP=-1.5:LRA=9,aresample={RATE},atrim=end_sample={frames}',str(mastered)],check=True)
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(mastered),'-c:a','libvorbis','-q:a','4','-metadata','title='+song['title'],'-metadata','artist=PERFECTO Original Ensemble',str(path)],check=True)
    return dict(events=len(performance),foreground=sum(n['source']=='score' for n in performance),soundfont_sha256=hashlib.sha256(font.read_bytes()).hexdigest())
