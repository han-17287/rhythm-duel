"""Two-player room relay. Deploy behind TLS for public use."""
import asyncio, json, math, secrets, os, time
from websockets.asyncio.server import serve
rooms = {}

def validate(notes):
    if not isinstance(notes, list) or not 1 <= len(notes) <= 8: raise ValueError('노트 개수 오류')
    clean=[]; end=-0.08; budget=0
    for n in notes:
        t=float(n['t']); d=float(n['d'])
        if not math.isfinite(t+d) or t<0 or t>30 or d<0 or d>8 or t<end+0.075: raise ValueError('잘못된 리듬')
        budget+=max(1, math.ceil(d)) if d>=0.3 else 1
        end=t+d; clean.append({'t':t,'d':d if d>=0.3 else 0.0})
    if budget!=8: raise ValueError('8개를 모두 사용하세요')
    return clean

def score(notes, hits):
    if not isinstance(hits,list) or len(hits)>64: raise ValueError('입력 개수 오류')
    used=set(); total=0; judgments=[]
    for n in notes:
        candidates=[(abs(float(h['t'])-n['t']),i,h) for i,h in enumerate(hits) if i not in used and isinstance(h,dict) and math.isfinite(float(h['t'])) and math.isfinite(float(h['d'])) and float(h['d'])>=0]
        best=min(candidates, default=None, key=lambda v:v[0]); error=999.0
        if best and best[0]<=0.18:
            _,i,h=best; used.add(i)
            error=max(best[0],abs((float(h['t'])+float(h['d']))-(n['t']+n['d']))) if n['d']>=0.3 else best[0]
        j=0 if error<=0.035 else 1 if error<=0.08 else 2 if error<=0.18 else 3
        total += [1000,700,400,0][j]*max(1,math.ceil(n['d']))
        judgments.append(j)
    total=max(0,total-200*(len(hits)-len(used)))
    return total,judgments

async def send(ws, **data): await ws.send(json.dumps(data,ensure_ascii=False))
async def broadcast(r, **data):
    await asyncio.gather(*(send(w,**data) for w in r['players']),return_exceptions=True)
async def turn(r):
    r['phase']='record'; r['deadline']=time.monotonic()+45
    await broadcast(r,type='turn',turn=r['turn'],attacker=r['turn']%2,scores=r['scores'],speed=1+0.15*(r['turn']//2))
async def handle(ws):
    room=None; slot=-1
    try:
        async for raw in ws:
            try:
                m=json.loads(raw); typ=m.get('type')
                if typ in ('create','join'):
                    if room: raise ValueError('이미 방에 있습니다')
                    if typ=='create':
                        code=''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(6))
                        while code in rooms: code=secrets.token_hex(3).upper()
                        rooms[code]={'players':[],'turn':0,'scores':[0,0],'phase':'waiting','deadline':time.monotonic()+600}
                    else: code=str(m.get('code','')).strip().upper()
                    r=rooms.get(code)
                    if not r or len(r['players'])>=2: raise ValueError('방이 없거나 가득 찼습니다')
                    room=code; slot=len(r['players']); r['players'].append(ws)
                    await send(ws,type='joined',code=code,slot=slot)
                    if len(r['players'])==2: await turn(r)
                elif room and room in rooms:
                    r=rooms[room]; attacker=r['turn']%2
                    if typ=='pattern' and r['phase']=='record' and slot==attacker:
                        r['notes']=validate(m['notes']); r['phase']='play'
                        speed=1+0.15*(r['turn']//2)
                        r['deadline']=time.monotonic()+4+(r['notes'][-1]['t']+r['notes'][-1]['d'])/speed+5
                        await broadcast(r,type='pattern',notes=r['notes'],speed=speed)
                    elif typ=='result' and r['phase']=='play' and slot!=attacker:
                        # Client reports local replay timestamps. Score is calculated here.
                        if time.monotonic()<r['deadline']-5.3: raise ValueError('아직 연주 중입니다')
                        points,judgments=score(r['notes'],m['hits']); r['scores'][slot]+=points
                        r['phase']='result'; r['deadline']=time.monotonic()+30
                        await broadcast(r,type='result',points=points,judgments=judgments,scores=r['scores'],finished=r['turn']==5)
                    elif typ=='next' and r['phase']=='result' and slot==0 and r['turn']<5:
                        r['turn']+=1; await turn(r)
                    else: raise ValueError('현재 단계에서 사용할 수 없는 요청')
            except (ValueError,KeyError,TypeError,OverflowError):
                await send(ws,type='error',message='요청 오류: 방 코드, 노트 수 또는 현재 단계를 확인하세요')
    finally:
        if room in rooms:
            r=rooms.pop(room)
            for other in r['players']:
                if other!=ws:
                    try: await send(other,type='left'); await other.close()
                    except Exception: pass
async def cleanup():
    while True:
        await asyncio.sleep(5)
        for code,r in list(rooms.items()):
            if time.monotonic()>r['deadline']:
                await broadcast(r,type='error',message='제한 시간이 지나 방을 닫습니다')
                for w in r['players']: await w.close()
async def main():
    async with serve(handle,'0.0.0.0',int(os.getenv('PORT','8765')),max_size=16384,ping_interval=20):
        await cleanup()
if __name__=='__main__': asyncio.run(main())
