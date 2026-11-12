"""Original hard rhythm charts + electronic soundtrack. Regenerate with numpy/ffmpeg."""
import argparse,json
from pathlib import Path
from ranker_charts import build_extras
ROOT=Path(__file__).resolve().parents[1]
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
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--charts-only',action='store_true',help='Rebuild canonical charts without synthesizing the soundtrack')
    args=parser.parse_args()
    if not args.charts_only:
        from ranker_soundtrack import render
    folder=ROOT/'assets/ranker';folder.mkdir(exist_ok=True);catalog=[]
    for song in SONGS:
        data={**song,**chart(song)}
        data['extras']=build_extras(song,data)
        data['difficulty_levels']={tier:song['level']+offset for tier,offset in [('hard',0),('expert',3),('inferno',6)]}
        if not args.charts_only:render(song,data,folder/(song['id']+'.ogg'))
        catalog.append(data)
        print(song['id'],data['duration'],{k:len(v) for k,v in data['charts'].items()},flush=True)
    (folder/'catalog.json').write_text(json.dumps(catalog,separators=(',',':'),ensure_ascii=False)+'\n')
if __name__=='__main__':main()
