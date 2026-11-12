"""Difficulty-specific rhythm arrangements built from the released HARD bar grid.

HARD is left untouched. Higher tiers use authored phrase templates, lane runs,
chords and hold-countervoice gates. Every lane remains physically releasable.
"""
from bisect import bisect_left


def _clean(notes, gap):
    result=[];ends=[-10.0,-10.0]
    for note in sorted(notes,key=lambda n:(n['t'],n.get('lane',0))):
        lane=note.get('lane',0)
        if note['t']-ends[lane]<gap-.00001:continue
        n={**note,'t':round(note['t'],5),'d':round(note['d'],5)}
        result.append(n);ends[lane]=n['t']+n['d']
    return result


def build_extras(song, base):
    variants={}
    bars=base['bars'];section_bars=song['section_bars']
    for tier in ['expert','inferno']:
        gap=.06 if tier=='expert' else .05
        charts={}
        for kind in ['one','double']:
            double=kind=='double';source=base['charts'][kind]
            times=[n['t'] for n in source];out=[]
            for bi,bar in enumerate(bars):
                beat=60/bar['bpm'];beats=bar['beats'];start=bar['t']
                end=bars[bi+1]['t'] if bi+1<len(bars) else base['duration']-.65
                local=bi%section_bars;section=bar['section']
                existing=[dict(n) for n in source[bisect_left(times,start-.00001):bisect_left(times,end-.00001)]]
                calm=(section==0 and local<4) or (section==2 and local<8)
                held=any(n['d']>=.3 for n in existing)
                rewrite=not calm and not held and ((bi%4 in (1,3) or section==3 and local>=section_bars-8) if tier=='expert' else (bi%4!=0 or section==3))
                if rewrite:
                    if double:division=6 if tier=='inferno' and bi%8==7 else 4
                    elif tier=='expert':division=4 if bi%8==7 and beat/4>=gap else 3
                    else:division=min(6,int(beat/gap+.00001)) if bi%8==7 else 4
                    notes=[]
                    for tick in range(beats*division):
                        # A short answering breath closes each eighth bar.
                        if bi%8==7 and tick>=beats*division-2:continue
                        value=tick/division
                        lane=((tick//2+bi)%2 if bi%8==3 else (tick+bi//2)%2) if double else 0
                        note={'t':round(start+value*beat,5),'d':0}
                        if double:note['lane']=lane
                        notes.append(note)
                        # Chord accents on the downbeat and half-bar; no constant chord spam.
                        chord=(tick==0 or tier=='inferno' and tick==2*division)
                        if double and chord:notes.append({**note,'lane':1-lane})
                    # A held lane against a fast countervoice creates a different hand problem.
                    if double and bi%16==7 and beat*1.5>=.3:
                        owner=bi%2;hold_end=start+beat*1.5
                        notes=[n for n in notes if n['lane']!=owner or n['t']>=hold_end+gap-.00001]
                        notes.append({'t':start,'d':round(1.5*beat,5),'lane':owner})
                else:
                    notes=existing
                    if double and held and not calm:
                        owner=next(n['lane'] for n in existing if n['d']>=.3)
                        hold=next(n for n in existing if n['d']>=.3)
                        division=3 if tier=='expert' else 4
                        step=beat/division
                        for tick in range(1,int(hold['d']/step)):
                            notes.append({'t':round(hold['t']+tick*step,5),'d':0,'lane':1-owner})
                out.extend(_clean(notes,gap))
            result=_clean(out,gap)
            if not 1<=len(result)<=3900:raise ValueError(f'Invalid chart size {song["id"]} {tier} {kind}: {len(result)}')
            charts[kind]=result
        variants[tier]=charts
    return variants
