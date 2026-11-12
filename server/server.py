"""Two-player room relay. Deploy behind TLS for public use."""
import asyncio, json, math, secrets, os, time, mimetypes, uuid, logging
from accounts import Store, AccountError, CATALOG
from assets import read_asset, accepts_gzip
from pathlib import Path
from urllib.parse import urlsplit, unquote
from http import HTTPStatus
from websockets.http11 import Response
from websockets.datastructures import Headers
from websockets.asyncio.server import serve
rooms = {}
MAX_MESSAGE_BYTES=524288

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
    original=candidate
    compressed=candidate.with_name(candidate.name+'.gz')
    gzip_enabled=accepts_gzip(request.headers.get('Accept-Encoding','')) and compressed.is_file()
    if gzip_enabled: candidate=compressed
    stat=candidate.stat()
    etag=f'"{stat.st_mtime_ns:x}-{stat.st_size:x}"'
    if request.headers.get('If-None-Match')==etag:
        response=http_response(304,b'')
        response.headers['ETag']=etag
        response.headers['Vary']='Accept-Encoding'
        return response
    body=await read_asset(candidate,stat)
    mime={'.wasm':'application/wasm','.ogg':'audio/ogg'}.get(original.suffix) or mimetypes.guess_type(original.name)[0] or 'application/octet-stream'
    response=http_response(200,body,mime)
    response.headers['ETag']=etag
    response.headers['Vary']='Accept-Encoding'
    if gzip_enabled: response.headers['Content-Encoding']='gzip'
    return response

def validate(notes, lanes=1):
    if not isinstance(notes, list) or not 1 <= len(notes) <= 8: raise ValueError('노트 개수 오류')
    clean=[]; ends=[-0.08]*lanes; budget=0
    for n in notes:
        if not isinstance(n,dict): raise ValueError('잘못된 노트')
        t=float(n['t']); d=float(n['d']); lane=n.get('lane',0)
        if type(lane) is not int or not 0<=lane<lanes: raise ValueError('잘못된 레인')
        if not math.isfinite(t+d) or t<0 or t>30 or d<0 or d>8 or t<ends[lane]+0.075: raise ValueError('잘못된 리듬')
        budget+=max(1, math.ceil(d)) if d>=0.3 else 1
        ends[lane]=t+d; clean.append({'t':t,'d':d if d>=0.3 else 0.0,**({'lane':lane} if lanes==2 else {})})
    if budget!=8: raise ValueError('8개를 모두 사용하세요')
    return sorted(clean,key=lambda n:n['t'])

def pattern_end(notes): return max(n['t']+n['d'] for n in notes)

from scoring import score, analyze
import ranker

store = Store.from_env()
auth_attempts = {}
MODES = {'casual':'일반전','rush':'스피드전','ranked':'랭크전 β','double':'더블 비트'}

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
    r['phase']='record'; r['turn_started']=time.monotonic(); r['deadline']=time.monotonic()+45; r['progress_at']=0; r['activity_at']=0
    await broadcast(r,type='turn',turn=r['turn'],attacker=(r['turn']+r.get('first_attacker',0))%2,scores=r['scores'],speed=turn_speed(r),settings=r['settings'])
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
    room=None; slot=-1; uid=None; name='게스트'; token=''; ranker_run=None; ranker_board_last=0; ranker_begin_last=0
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
                        ranker_run=None
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
                elif typ=='ranker_board':
                    if time.monotonic()-ranker_board_last<.25:raise ValueError('잠시 후 다시 조회하세요')
                    ranker_board_last=time.monotonic()
                    song_id=m.get('id');kind=m.get('kind');difficulty=m.get('difficulty','hard')
                    ranker.chart(song_id,kind,difficulty)
                    board=await asyncio.to_thread(store.ranker_board,song_id,kind,uid,difficulty) if store.enabled else dict(rows=[],own=None)
                    await send(ws,type='ranker_board',id=song_id,kind=kind,difficulty=difficulty,enabled=store.enabled,**board)
                elif typ=='ranker_begin':
                    if not uid:raise AccountError('글로벌 기록은 로그인이 필요합니다. 게스트는 로컬 기록으로 도전할 수 있어요.')
                    if room in rooms:raise ValueError('방에서 나온 후 랭커 모드를 시작하세요')
                    if time.monotonic()-ranker_begin_last<.25:raise ValueError('잠시 후 다시 시작하세요')
                    ranker_begin_last=time.monotonic();ranker_run=ranker.begin(uid,m.get('id'),m.get('kind'),m.get('difficulty','hard'))
                    await send(ws,type='ranker_ready',id=ranker_run['id'],kind=ranker_run['kind'],difficulty=ranker_run['difficulty'],session=ranker_run['token'])
                elif typ=='ranker_result':
                    if not uid or not ranker_run or ranker_run['uid']!=uid:raise AccountError('기록 도전을 다시 시작해 주세요')
                    if 'difficulty' in m and m['difficulty']!=ranker_run['difficulty']:raise ValueError('도전한 난이도와 다릅니다')
                    report=await asyncio.to_thread(ranker.finish,ranker_run,m.get('session'),m.get('hits'))
                    run=ranker_run
                    result=await asyncio.to_thread(store.ranker_submit,uid,run['id'],run['kind'],report,run['difficulty'])
                    ranker_run=None
                    await send(ws,type='ranker_result',id=run['id'],kind=run['kind'],difficulty=run['difficulty'],report=report,**result)
                elif typ in ('buy','equip'):
                    if not uid: raise AccountError('로그인이 필요합니다.')
                    if room in rooms: raise AccountError('방에서 나온 후 스킨을 변경하세요.')
                    profile=await asyncio.to_thread(store.purchase,uid,str(m.get('skin','')),typ=='equip')
                    await send(ws,type='profile',profile=profile,message='스킨을 장착했습니다.')
                elif typ in ('create','join'):
                    ranker_run=None
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
                elif typ=='leave' and room not in rooms:
                    room=None;slot=-1;await send(ws,type='leave_ok')
                elif room in rooms:
                    r=rooms[room]; attacker=(r['turn']+r.get('first_attacker',0))%2
                    if typ=='leave':
                        await abandon(room,slot); room=None; slot=-1; await send(ws,type='leave_ok')
                    elif typ=='configure' and r['phase']=='waiting' and slot==0:
                        config=settings(m.get('settings'))
                        if config['mode']=='ranked' and not all(r['users']): raise AccountError('모두 로그인해야 랭크전을 선택할 수 있습니다.')
                        r['settings']=config; await room_state(r)
                    elif typ=='start' and r['phase']=='waiting' and slot==0:
                        if len(r['players'])!=2: raise ValueError('친구가 참가하면 시작할 수 있습니다')
                        await turn(r)
                    elif typ=='draft' and r['phase']=='record' and slot==attacker:
                        r['draft']=validate(m['notes'],2 if r['settings']['mode']=='double' else 1); r['phase']='review'
                        r['deadline']=min(time.monotonic()+90,r['turn_started']+150)
                        await send(ws,type='draft_ready',remaining=max(0,r['deadline']-time.monotonic()))
                        await send(r['players'][1-slot],type='activity',units=8,review=True)
                    elif typ=='edit' and r['phase'] in ('record','review') and slot==attacker:
                        r['phase']='record'; r.pop('draft',None)
                        r['deadline']=min(time.monotonic()+45,r['turn_started']+150)
                        await send(r['players'][1-slot],type='activity',units=0,review=False)
                    elif typ=='activity' and r['phase']=='record' and slot==attacker:
                        units=m.get('units',0)
                        if type(units) is not int or not 0<=units<=8: raise ValueError('잘못된 진행률')
                        if time.monotonic()-r.get('activity_at',0)>.2:
                            r['activity_at']=time.monotonic()
                            await send(r['players'][1-slot],type='activity',units=units,review=False)
                    elif typ=='confirm' and r['phase']=='review' and slot==attacker:
                        r['notes']=r.pop('draft'); r['phase']='play'; speed=turn_speed(r)
                        r['deadline']=time.monotonic()+4+pattern_end(r['notes'])/speed+5
                        await broadcast(r,type='pattern',notes=r['notes'],speed=speed)
                    elif typ=='progress' and r['phase']=='play' and slot!=attacker:
                        combo=m.get('combo',0); units=m.get('resolved',0)
                        if type(combo) is not int or type(units) is not int or not 0<=combo<=8 or not 0<=units<=8: raise ValueError('잘못된 진행률')
                        if time.monotonic()-r.get('progress_at',0)>.12:
                            r['progress_at']=time.monotonic()
                            await send(r['players'][attacker],type='progress',combo=combo,resolved=units)
                    elif typ=='emote':
                        emote=m.get('emote','')
                        if emote not in ('준비 완료!','좋은 리듬!','한 판 더!','멋진 수비!'): raise ValueError('없는 메시지')
                        if time.monotonic()-r.get('emote_at_'+str(slot),0)>2:
                            r['emote_at_'+str(slot)]=time.monotonic()
                            await broadcast(r,type='emote',slot=slot,text=emote)
                    elif typ=='rematch' and r['phase']=='finished':
                        votes=r.setdefault('rematch',[])
                        if slot not in votes: votes.append(slot)
                        await broadcast(r,type='rematch_state',votes=votes)
                        if len(votes)==2:
                            r.update(id=uuid.uuid4().hex,turn=0,scores=[0,0],awarded=False,rematch=[],first_attacker=1-r.get('first_attacker',0))
                            await turn(r)
                    elif typ=='pattern' and r['phase']=='record' and slot==attacker:
                        r['notes']=validate(m['notes'],2 if r['settings']['mode']=='double' else 1); r['phase']='play'
                        speed=turn_speed(r)
                        r['deadline']=time.monotonic()+4+pattern_end(r['notes'])/speed+5
                        await broadcast(r,type='pattern',notes=r['notes'],speed=speed)
                    elif typ=='result' and r['phase']=='play' and slot!=attacker:
                        if time.monotonic()<r['deadline']-5.3: raise ValueError('아직 연주 중입니다')
                        reported_hits=m['hits']
                        overflow=isinstance(reported_hits,list) and len(reported_hits)>64
                        report=analyze(r['notes'],reported_hits[:64] if overflow else reported_hits)
                        if overflow:
                            report['extra']+=len(reported_hits)-64
                            report['points']=0;report['accuracy']=0.0;report['grade']='D'
                            report['full_combo']=False;report['all_perfect']=False
                            report['warning']='추가 입력이 너무 많아 이번 수비는 0점입니다.'
                        points=report['points']; judgments=report['judgments']; r['scores'][slot]+=points
                        finished=r['turn']==r['settings']['rounds']*2-1
                        r['phase']='finished' if finished else 'result'; r['deadline']=time.monotonic()+120
                        await broadcast(r,type='result',points=points,judgments=judgments,scores=r['scores'],finished=finished,report=report,defender=slot)
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
    async with serve(handle,'0.0.0.0',int(os.getenv('PORT','8765')),max_size=MAX_MESSAGE_BYTES,ping_interval=20,open_timeout=120,process_request=serve_game):
        await cleanup()
if __name__=='__main__': asyncio.run(main())
