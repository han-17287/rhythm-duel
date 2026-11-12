"""Two-player room relay. Deploy behind TLS for public use."""
import asyncio, json, math, secrets, os, time, mimetypes, uuid, logging
from accounts import Store, AccountError, CATALOG
from assets import read_asset, accepts_gzip
from pathlib import Path
from urllib.parse import urlsplit, unquote
from http import HTTPStatus
from websockets.http11 import Response
from websockets.datastructures import Headers
from websockets.protocol import State
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
    await broadcast(r,type='room',settings=r['settings'],players=r['names'],count=len(r['players']),**room_metadata(r))
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
    task=match_tasks.pop(code,None)
    if task and task is not asyncio.current_task():task.cancel()
    for w in r['players']:
        state=sessions.get(w)
        if state and state.get('room')==code:state['room']=None;state['slot']=-1
    # Notify departure before slow account settlement, so an old room's event
    # cannot arrive after the survivor has already joined a new room.
    for i,w in enumerate(r['players']):
        if i!=leaver:
            try: await send(w,type='left',code=code,room_id=r['id'])
            except Exception: pass
    if r['phase'] not in ('waiting','matched','finished') and len(r['players'])==2:
        await award(r,leaver)

# Queue and connection membership are shared so a matched player's idle handler
# can observe a room assigned by the other player's request.
sessions = {}
match_queues = {mode: [] for mode in MODES}
match_tasks = {}
MATCH_START_DELAY = 3.0
BROWSE_INTERVAL = .25
MATCH_JOIN_INTERVAL = .25


def is_open(ws):
    return getattr(ws,'state',State.OPEN)==State.OPEN


def room_joinable(r):
    return bool(r and len(r['players'])<2 and r['phase']=='waiting'
                and r['deadline']>time.monotonic() and all(is_open(w) for w in r['players']))


def room_metadata(r):
    return {'public': bool(r.get('public', False)), 'title': r.get('title', '친구 대전'), 'auto': bool(r.get('auto', False))}


def make_room(config, title, public=False, auto=False):
    code=''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(6))
    while code in rooms: code=''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(6))
    r={'id':uuid.uuid4().hex,'players':[],'users':[],'names':[],'turn':0,'scores':[0,0],
       'phase':'matched' if auto else 'waiting','settings':config,'deadline':time.monotonic()+600,
       'public':public,'title':title,'auto':auto,'created_at':time.monotonic()}
    rooms[code]=r
    return code,r


def public_title(value, name):
    if value is None or value=='': return (name+'의 방')[:32]
    if not isinstance(value,str):raise ValueError('잘못된 방 제목')
    value=value.strip()
    if not value:return (name+'의 방')[:32]
    if len(value)>32 or not value.isprintable():raise ValueError('방 제목은 32자 이내로 입력하세요')
    return value


async def directory(ws, mode='all'):
    if mode!='all' and mode not in MODES:raise ValueError('없는 대전 모드')
    state=sessions[ws];now=time.monotonic()
    if now-state.get('browse_at',-10)<BROWSE_INTERVAL:raise ValueError('잠시 후 다시 조회하세요')
    state['browse_at']=now
    eligible=[(code,r) for code,r in rooms.items() if r.get('public') and not r.get('auto')
              and room_joinable(r) and len(r['players'])==1
              and (mode=='all' or r['settings']['mode']==mode)]
    eligible.sort(key=lambda item:item[1].get('created_at',0))
    rows=[{'code':code,'title':r['title'],'host':r['names'][0],'count':len(r['players']),
           'settings':r['settings'],'requires_login':r['settings']['mode']=='ranked'} for code,r in eligible[:50]]
    await send(ws,type='room_list',mode=mode,rooms=rows,total=len(eligible),online=len(sessions))


def queue_valid(ws, mode):
    state=sessions.get(ws)
    return bool(state and is_open(ws) and state.get('queue_mode')==mode and state.get('room') not in rooms)


async def queue_status(ws, queued, mode=None):
    state=sessions.get(ws)
    if state is None:return
    mode=mode or state.get('queue_mode') or ''
    queue=match_queues.get(mode,[])
    eligible=[w for w in queue if queue_valid(w,mode)]
    await send(ws,type='match_status',queued=queued,mode=mode,
               position=eligible.index(ws)+1 if queued and ws in eligible else 0,
               waiting=len(eligible),elapsed=max(0,int(time.monotonic()-state.get('queued_at',time.monotonic()))) if queued else 0)


async def notify_queue(mode):
    queue=match_queues.get(mode,[])
    queue[:]=[w for w in queue if queue_valid(w,mode)]
    for w in list(queue):
        try:await queue_status(w,True,mode)
        except Exception:
            if w in queue:queue.remove(w)
            if w in sessions:sessions[w]['queue_mode']=None


async def cancel_queue(ws, notify=True):
    state=sessions.get(ws)
    if state is None:return
    previous=state.get('queue_mode')
    # Clear membership before yielding to a websocket send.
    state['queue_mode']=None
    for mode,queue in match_queues.items():
        if ws in queue:queue.remove(ws)
    if notify:
        try:await queue_status(ws,False,previous)
        except Exception:pass
    if previous:await notify_queue(previous)


async def start_automatic(code, identity):
    try:
        await asyncio.sleep(MATCH_START_DELAY)
        r=rooms.get(code)
        if not r or r['id']!=identity or r['phase']!='matched':return
        unavailable=next((i for i,w in enumerate(r['players']) if not is_open(w) or sessions.get(w,{}).get('room')!=code),None)
        if len(r['players'])!=2 or unavailable is not None:
            await abandon(code,unavailable if unavailable is not None else 0);return
        await turn(r)
    finally:
        if match_tasks.get(code) is asyncio.current_task():match_tasks.pop(code,None)


async def match_waiting(mode):
    queue=match_queues[mode]
    while True:
        queue[:]=[w for w in queue if queue_valid(w,mode)]
        pair=None
        for i,a in enumerate(queue):
            for b in queue[i+1:]:
                uid=sessions[a]['uid']
                if uid and uid==sessions[b]['uid']:continue
                pair=(a,b);break
            if pair:break
        if not pair:break
        a,b=pair
        for w in pair:queue.remove(w);sessions[w]['queue_mode']=None
        code,r=make_room(settings({'mode':mode,'rounds':3,'speed':1.0}),'자동 매칭 · '+MODES[mode],auto=True)
        for slot,w in enumerate(pair):
            state=sessions[w]
            r['players'].append(w);r['users'].append(state['uid']);r['names'].append(state['name'])
            state['room']=code;state['slot']=slot
        # Both slots are reserved atomically before the first network await.
        outcomes=await asyncio.gather(*(send(w,type='joined',code=code,slot=i,settings=r['settings'],**room_metadata(r)) for i,w in enumerate(pair)),return_exceptions=True)
        failed=next((i for i,result in enumerate(outcomes) if isinstance(result,BaseException)),None)
        if failed is not None:
            await abandon(code,failed);continue
        if rooms.get(code) is not r:continue
        await room_state(r)
        if rooms.get(code) is not r:continue
        outcomes=await asyncio.gather(*(send(w,type='match_found',mode=mode,opponent=r['names'][1-i],starts_in=MATCH_START_DELAY) for i,w in enumerate(pair)),return_exceptions=True)
        failed=next((i for i,result in enumerate(outcomes) if isinstance(result,BaseException)),None)
        if failed is not None:
            await abandon(code,failed);continue
        if rooms.get(code) is r:
            r['deadline']=time.monotonic()+MATCH_START_DELAY+30
            match_tasks[code]=asyncio.create_task(start_automatic(code,r['id']))
    await notify_queue(mode)


async def enqueue_match(ws, mode='casual'):
    if mode not in MODES:raise ValueError('없는 대전 모드')
    state=sessions[ws]
    if state['room'] in rooms:raise ValueError('이미 방에 있습니다')
    if mode=='ranked' and not state['uid']:raise AccountError('랭크전 자동 매칭은 로그인이 필요합니다.')
    if state.get('queue_mode')==mode:
        await queue_status(ws,True,mode);return
    now=time.monotonic()
    if now-state.get('match_at',-10)<MATCH_JOIN_INTERVAL:raise ValueError('잠시 후 다시 검색하세요')
    await cancel_queue(ws,notify=False)
    state['queue_mode']=mode;state['queued_at']=now;state['match_at']=now
    match_queues[mode].append(ws)
    await queue_status(ws,True,mode)
    await match_waiting(mode)

def auth_limit(ws,name):
    key=(str(ws.remote_address[0]) if ws.remote_address else 'unknown',str(name).casefold())
    timestamps=auth_attempts.setdefault(key,[]); now=time.monotonic()
    timestamps[:]=[t for t in timestamps if t>now-60]
    if len(timestamps)>=6: raise AccountError('로그인 요청이 많습니다. 1분 뒤 다시 시도하세요.')
    timestamps.append(now)

async def handle(ws):
    name='게스트-'+secrets.token_hex(2).upper()
    state={'room':None,'slot':-1,'uid':None,'name':name,'token':'','queue_mode':None}
    sessions[ws]=state
    room=None;slot=-1;uid=None;token='';ranker_run=None;ranker_board_last=0;ranker_begin_last=0
    try:
        async for raw in ws:
            room=state['room'];slot=state['slot'];uid=state['uid'];name=state['name'];token=state['token']
            typ=''
            try:
                m=json.loads(raw)
                if not isinstance(m,dict): raise ValueError('잘못된 요청')
                typ=m.get('type')
                if typ=='hello':
                    await send(ws,type='hello',accounts_enabled=store.enabled,catalog=CATALOG,online=len(sessions))
                elif typ=='browse_rooms':
                    await directory(ws,m.get('mode','all'))
                elif typ=='match_join':
                    ranker_run=None
                    await enqueue_match(ws,m.get('mode','casual'))
                elif typ=='match_cancel':
                    await cancel_queue(ws)
                    current=state['room']
                    if current in rooms and rooms[current].get('auto') and rooms[current]['phase']=='matched':
                        await abandon(current,state['slot']);await send(ws,type='leave_ok')
                elif typ in ('register','login','resume','logout'):
                    if room in rooms: raise AccountError('방에서 나온 후 계정을 변경하세요.')
                    await cancel_queue(ws,notify=bool(state.get('queue_mode')))
                    if typ=='logout':
                        ranker_run=None
                        if token: await asyncio.to_thread(store.logout,token)
                        uid=None;token='';name='게스트-'+secrets.token_hex(2).upper()
                        state.update(uid=uid,name=name,token=token)
                        await send(ws,type='profile',profile={},token='')
                    elif typ=='resume':
                        token=str(m.get('token','')); profile=await asyncio.to_thread(store.resume,token)
                        uid=profile['id'];name=profile['name'];state.update(uid=uid,name=name,token=token)
                        await send(ws,type='profile',profile=profile,token=token)
                    else:
                        auth_limit(ws,m.get('name',''))
                        result=await asyncio.to_thread(getattr(store,typ),m.get('name',''),m.get('password',''))
                        uid=result['profile']['id'];name=result['profile']['name'];token=result['token']
                        state.update(uid=uid,name=name,token=token)
                        await send(ws,type='profile',**result)
                elif typ=='ranker_board':
                    if time.monotonic()-ranker_board_last<.25:raise ValueError('잠시 후 다시 조회하세요')
                    ranker_board_last=time.monotonic()
                    song_id=m.get('id');kind=m.get('kind');difficulty=m.get('difficulty','hard')
                    ranker.chart(song_id,kind,difficulty)
                    board=await asyncio.to_thread(store.ranker_board,song_id,kind,uid,difficulty) if store.enabled else dict(rows=[],own=None)
                    await send(ws,type='ranker_board',id=song_id,kind=kind,difficulty=difficulty,enabled=store.enabled,**board)
                elif typ=='ranker_begin':
                    await cancel_queue(ws,notify=bool(state.get('queue_mode')))
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
                    await cancel_queue(ws,notify=bool(state.get('queue_mode')))
                    if not uid: raise AccountError('로그인이 필요합니다.')
                    if room in rooms: raise AccountError('방에서 나온 후 스킨을 변경하세요.')
                    profile=await asyncio.to_thread(store.purchase,uid,str(m.get('skin','')),typ=='equip')
                    await send(ws,type='profile',profile=profile,message='스킨을 장착했습니다.')
                elif typ in ('create','join'):
                    ranker_run=None
                    if room in rooms: raise ValueError('이미 방에 있습니다')
                    await cancel_queue(ws,notify=bool(state.get('queue_mode')))
                    if typ=='create':
                        config=settings(m.get('settings'))
                        if config['mode']=='ranked' and not uid: raise AccountError('랭크전은 로그인이 필요합니다.')
                        public=m.get('public',False)
                        if type(public) is not bool:raise ValueError('잘못된 공개 설정')
                        title=public_title(m.get('title'),name)
                        code,r=make_room(config,title,public=public)
                    else: code=str(m.get('code','')).strip().upper()
                    r=rooms.get(code)
                    if not room_joinable(r): raise ValueError('방이 없거나 가득 찼습니다')
                    if r['settings']['mode']=='ranked' and not uid: raise AccountError('랭크전은 로그인이 필요합니다.')
                    if uid and uid in r['users']: raise AccountError('같은 계정으로 대전할 수 없습니다.')
                    room=code;slot=len(r['players']);state.update(room=room,slot=slot)
                    r['players'].append(ws);r['users'].append(uid);r['names'].append(name)
                    await send(ws,type='joined',code=code,slot=slot,settings=r['settings'],**room_metadata(r))
                    await room_state(r)
                elif typ=='leave' and room not in rooms:
                    await cancel_queue(ws,notify=bool(state.get('queue_mode')))
                    room=None;slot=-1;state.update(room=room,slot=slot);await send(ws,type='leave_ok')
                elif room in rooms:
                    r=rooms[room]; attacker=(r['turn']+r.get('first_attacker',0))%2
                    if typ=='leave':
                        await abandon(room,slot);room=None;slot=-1;state.update(room=room,slot=slot);await send(ws,type='leave_ok')
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
        await cancel_queue(ws,notify=False)
        current=state.get('room')
        if current in rooms:await abandon(current,state['slot'])
        sessions.pop(ws,None)
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
