"""Two-player room relay. Deploy behind TLS for public use."""
import asyncio, json, math, secrets, os, time, mimetypes, uuid, logging
from accounts import Store, AccountError, CATALOG
from pathlib import Path
from urllib.parse import urlsplit, unquote
from http import HTTPStatus
from websockets.http11 import Response
from websockets.datastructures import Headers
from websockets.asyncio.server import serve
rooms = {}

STATIC_DIR = Path(os.getenv('STATIC_DIR', str(Path(__file__).parent/'static'))).resolve()

def http_response(status, body, content_type='text/plain; charset=utf-8'):
    return Response(status, HTTPStatus(status).phrase, Headers({
        'Content-Type': content_type, 'Content-Length': str(len(body)),
        'Cache-Control': 'no-cache', 'X-Content-Type-Options': 'nosniff'
    }), body)

async def serve_game(connection, request):
    if request.headers.get('Upgrade','').lower() == 'websocket': return None
    path=unquote(urlsplit(request.path).path)
    if path=='/health': return http_response(200,b'ok')
    candidate=(STATIC_DIR/('index.html' if path=='/' else path.lstrip('/'))).resolve()
    if not candidate.is_relative_to(STATIC_DIR) or not candidate.is_file():
        return http_response(404,b'Not found')
    body=await asyncio.to_thread(candidate.read_bytes)
    mime='application/wasm' if candidate.suffix=='.wasm' else mimetypes.guess_type(candidate.name)[0] or 'application/octet-stream'
    return http_response(200,body,mime)

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

store = Store.from_env()
auth_attempts = {}
MODES = {'casual':'일반전','rush':'스피드전','ranked':'랭크전 β'}

def settings(data=None):
    data=data or {}
    if not isinstance(data,dict): raise ValueError('잘못된 방 설정')
    mode=data.get('mode','casual'); rounds=data.get('rounds',3); speed=data.get('speed',1.0)
    if mode not in MODES or type(rounds) is not int or not 1<=rounds<=9 or type(speed) not in (int,float) or not math.isfinite(speed) or not .5<=speed<=2 or abs(speed*4-round(speed*4))>.001: raise ValueError('방 설정 범위를 확인하세요')
    return {'mode':mode,'rounds':3 if mode=='ranked' else rounds,'speed':1.0 if mode=='ranked' else float(speed)}

def turn_speed(r): return min(3.0,r['settings']['speed']+(.3 if r['settings']['mode']=='rush' else .15)*(r['turn']//2))

async def send(ws, **data): await ws.send(json.dumps(data,ensure_ascii=False))
async def broadcast(r, **data):
    await asyncio.gather(*(send(w,**data) for w in r['players']),return_exceptions=True)
async def room_state(r):
    await broadcast(r,type='room',settings=r['settings'],players=r['names'],count=len(r['players']))
async def turn(r):
    r['phase']='record'; r['deadline']=time.monotonic()+45
    await broadcast(r,type='turn',turn=r['turn'],attacker=r['turn']%2,scores=r['scores'],speed=turn_speed(r),settings=r['settings'])
async def award(r,forfeit=None):
    if r.get('awarded'): return
    changes=await asyncio.to_thread(store.settle,r['id'],r['users'],r['scores'],r['settings']['mode']=='ranked',forfeit)
    r['awarded']=True
    for w,uid in zip(r['players'],r['users']):
        if uid in changes:
            try: await send(w,type='reward',**changes[uid])
            except Exception: pass
async def abandon(code,leaver):
    r=rooms.pop(code,None)
    if not r: return
    if r['phase'] not in ('waiting','finished') and len(r['players'])==2:
        await award(r,leaver)
    for i,w in enumerate(r['players']):
        if i!=leaver:
            try: await send(w,type='left')
            except Exception: pass

def auth_limit(ws,name):
    key=(str(ws.remote_address[0]) if ws.remote_address else 'unknown',str(name).casefold())
    timestamps=auth_attempts.setdefault(key,[]); now=time.monotonic()
    timestamps[:]=[t for t in timestamps if t>now-60]
    if len(timestamps)>=6: raise AccountError('로그인 요청이 많습니다. 1분 뒤 다시 시도하세요.')
    timestamps.append(now)

async def handle(ws):
    room=None; slot=-1; uid=None; name='게스트'; token=''
    try:
        async for raw in ws:
            typ=''
            try:
                m=json.loads(raw)
                if not isinstance(m,dict): raise ValueError('잘못된 요청')
                typ=m.get('type')
                if typ=='hello':
                    await send(ws,type='hello',accounts_enabled=store.enabled,catalog=CATALOG)
                elif typ in ('register','login','resume','logout'):
                    if room in rooms: raise AccountError('방에서 나온 후 계정을 변경하세요.')
                    if typ=='logout':
                        if token: await asyncio.to_thread(store.logout,token)
                        uid=None; token=''; name='게스트'; await send(ws,type='profile',profile={},token='')
                    elif typ=='resume':
                        token=str(m.get('token','')); profile=await asyncio.to_thread(store.resume,token)
                        uid=profile['id']; name=profile['name']; await send(ws,type='profile',profile=profile,token=token)
                    else:
                        auth_limit(ws,m.get('name',''))
                        result=await asyncio.to_thread(getattr(store,typ),m.get('name',''),m.get('password',''))
                        uid=result['profile']['id']; name=result['profile']['name']; token=result['token']
                        await send(ws,type='profile',**result)
                elif typ in ('buy','equip'):
                    if not uid: raise AccountError('로그인이 필요합니다.')
                    if room in rooms: raise AccountError('방에서 나온 후 스킨을 변경하세요.')
                    profile=await asyncio.to_thread(store.purchase,uid,str(m.get('skin','')),typ=='equip')
                    await send(ws,type='profile',profile=profile,message='스킨을 장착했습니다.')
                elif typ in ('create','join'):
                    if room in rooms: raise ValueError('이미 방에 있습니다')
                    if typ=='create':
                        config=settings(m.get('settings'))
                        if config['mode']=='ranked' and not uid: raise AccountError('랭크전은 로그인이 필요합니다.')
                        code=''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(6))
                        while code in rooms: code=secrets.token_hex(3).upper()
                        rooms[code]={'id':uuid.uuid4().hex,'players':[],'users':[],'names':[],'turn':0,'scores':[0,0],'phase':'waiting','settings':config,'deadline':time.monotonic()+600}
                    else: code=str(m.get('code','')).strip().upper()
                    r=rooms.get(code)
                    if not r or len(r['players'])>=2: raise ValueError('방이 없거나 가득 찼습니다')
                    if r['settings']['mode']=='ranked' and not uid: raise AccountError('랭크전은 로그인이 필요합니다.')
                    if uid and uid in r['users']: raise AccountError('같은 계정으로 대전할 수 없습니다.')
                    room=code; slot=len(r['players']); r['players'].append(ws); r['users'].append(uid); r['names'].append(name)
                    await send(ws,type='joined',code=code,slot=slot,settings=r['settings'])
                    await room_state(r)
                elif room in rooms:
                    r=rooms[room]; attacker=r['turn']%2
                    if typ=='leave':
                        await abandon(room,slot); room=None; slot=-1; await send(ws,type='leave_ok')
                    elif typ=='configure' and r['phase']=='waiting' and slot==0:
                        config=settings(m.get('settings'))
                        if config['mode']=='ranked' and not all(r['users']): raise AccountError('모두 로그인해야 랭크전을 선택할 수 있습니다.')
                        r['settings']=config; await room_state(r)
                    elif typ=='start' and r['phase']=='waiting' and slot==0:
                        if len(r['players'])!=2: raise ValueError('친구가 참가하면 시작할 수 있습니다')
                        await turn(r)
                    elif typ=='pattern' and r['phase']=='record' and slot==attacker:
                        r['notes']=validate(m['notes']); r['phase']='play'
                        speed=turn_speed(r)
                        r['deadline']=time.monotonic()+4+(r['notes'][-1]['t']+r['notes'][-1]['d'])/speed+5
                        await broadcast(r,type='pattern',notes=r['notes'],speed=speed)
                    elif typ=='result' and r['phase']=='play' and slot!=attacker:
                        if time.monotonic()<r['deadline']-5.3: raise ValueError('아직 연주 중입니다')
                        points,judgments=score(r['notes'],m['hits']); r['scores'][slot]+=points
                        finished=r['turn']==r['settings']['rounds']*2-1
                        r['phase']='finished' if finished else 'result'; r['deadline']=time.monotonic()+120
                        await broadcast(r,type='result',points=points,judgments=judgments,scores=r['scores'],finished=finished)
                        if finished: await award(r)
                    elif typ=='next' and r['phase']=='result' and slot==0:
                        r['turn']+=1; await turn(r)
                    else: raise ValueError('현재 단계에서 사용할 수 없는 요청')
                else: raise ValueError('먼저 방을 만들거나 참가하세요')
            except AccountError as e:
                if typ=='configure' and room in rooms: await room_state(rooms[room])
                await send(ws,type='error',action=typ,message=str(e))
            except (ValueError,KeyError,TypeError,OverflowError,AttributeError):
                await send(ws,type='error',action=typ,message='방 코드, 입력 값 또는 현재 단계를 확인하세요.')
            except Exception:
                logging.exception('Request failed (%s)',typ)
                await send(ws,type='error',action=typ,message='저장 서버 처리에 실패했습니다. 잠시 후 다시 시도하세요.')
    finally:
        if room in rooms: await abandon(room,slot)
async def cleanup():
    while True:
        await asyncio.sleep(5)
        for key,items in list(auth_attempts.items()):
            if not items or items[-1]<time.monotonic()-60: auth_attempts.pop(key,None)
        for code,r in list(rooms.items()):
            if time.monotonic()>r['deadline']:
                await broadcast(r,type='error',message='제한 시간이 지나 방을 닫습니다')
                for w in r['players']: await w.close()
async def main():
    async with serve(handle,'0.0.0.0',int(os.getenv('PORT','8765')),max_size=16384,ping_interval=20,process_request=serve_game):
        await cleanup()
if __name__=='__main__': asyncio.run(main())
