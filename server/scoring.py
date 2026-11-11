"""Canonical rhythm scoring and the detailed report sent to both players."""
import math
WINDOWS=(.035,.08,.18)
POINTS=(1000,700,400,0)
def analyze(notes,hits):
    if not isinstance(hits,list) or len(hits)>64: raise ValueError('입력 개수 오류')
    clean=[]
    for h in hits:
        if not isinstance(h,dict): raise ValueError('잘못된 입력')
        t=float(h['t']);d=float(h['d'])
        if not math.isfinite(t+d) or d<0 or d>120 or abs(t)>120: raise ValueError('잘못된 입력 시간')
        clean.append({'t':t,'d':d})
    used=set(); events=[]; total=maximum=combo=best_combo=0; judgments=[]; offsets=[];counts=[0,0,0,0]
    for note in notes:
        candidates=[(abs(h['t']-note['t']),i,h) for i,h in enumerate(clean) if i not in used]
        best=min(candidates,default=None,key=lambda x:x[0]);error=math.inf;offset=None
        if best and best[0]<=.180001:
            _,i,h=best;used.add(i);offset=h['t']-note['t'];error=best[0]
            if note['d']>=.3:
                release_offset=h['t']+h['d']-note['t']-note['d']
                if abs(release_offset)>abs(offset):offset=release_offset
                error=max(error,abs(release_offset))
        j=next((i for i,w in enumerate(WINDOWS) if error<=w+.000001),3)
        weight=max(1,math.ceil(note['d'])); total+=POINTS[j]*weight;maximum+=1000*weight
        events.append((float(note['t']),j))
        counts[j]+=1;judgments.append(j);offsets.append(None if offset is None else round(offset*1000,1))
        combo=0 if j==3 else combo+1;best_combo=max(best_combo,combo)
    for i,h in enumerate(clean):
        if i not in used: events.append((h['t'],3))
    combo=best_combo=0
    combo_events=[]
    for _,j in sorted(events,key=lambda event:event[0]):
        combo=0 if j==3 else combo+1;best_combo=max(best_combo,combo);combo_events.append(j)
    extra=len(clean)-len(used);total=max(0,total-200*extra)
    accuracy=100*total/max(1,maximum)
    grade=next((g for threshold,g in [(95,'S'),(85,'A'),(70,'B'),(50,'C')] if accuracy>=threshold),'D')
    return dict(points=total,maximum=maximum,accuracy=math.floor(accuracy*10+.5)/10,grade=grade,counts=counts,judgments=judgments,offsets=offsets,max_combo=best_combo,combo_events=combo_events,extra=extra,full_combo=counts[3]==0 and extra==0 and bool(notes),all_perfect=counts[0]==len(notes) and extra==0 and bool(notes))

def score(notes,hits):
    report=analyze(notes,hits)
    return report['points'],report['judgments']
