import asyncio,json,sys,time,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parents[1]/'server'))
import server as s
from scoring import analyze
from websockets.asyncio.client import connect
from websockets.asyncio.server import serve
NOTES=[{'t':i//2*.5,'d':0,'lane':i%2} for i in range(8)]
class DoubleBeat(unittest.IsolatedAsyncioTestCase):
    def test_lane_scoring_and_validation(self):
        self.assertEqual(s.validate(NOTES,2),NOTES)
        with self.assertRaises(ValueError):s.validate(NOTES)
        with self.assertRaises(ValueError):s.validate([{**n,'lane':True} for n in NOTES],2)
        self.assertEqual(analyze(NOTES,NOTES)['points'],8000)
        self.assertEqual(analyze(NOTES,[n for n in NOTES if n['lane']==0])['points'],4000)
        # Swapping simultaneous chord lanes is equivalent; isolated wrong lanes miss.
        note=[{'t':0,'d':0,'lane':0}]
        self.assertEqual(analyze(note,[{'t':0,'d':0,'lane':1}])['points'],0)
        holds=[{'t':0,'d':7,'lane':0},{'t':0,'d':0,'lane':1}]
        self.assertEqual(s.pattern_end(s.validate(holds,2)),7)
    async def test_two_player_double_match(self):
        async with serve(s.handle,'127.0.0.1',0) as server:
            port=server.sockets[0].getsockname()[1]
            async with connect(f'ws://127.0.0.1:{port}') as a,connect(f'ws://127.0.0.1:{port}') as b:
                async def send(w,**m):await w.send(json.dumps(m))
                async def recv(w):return json.loads(await asyncio.wait_for(w.recv(),3))
                await send(a,type='create',settings={'mode':'double','rounds':1,'speed':1})
                joined=await recv(a);code=joined['code'];await recv(a)
                await send(b,type='join',code=code);await recv(b);await recv(a);await recv(b)
                await send(a,type='start')
                for turn in range(2):
                    for w in (a,b):self.assertEqual((await recv(w))['settings']['mode'],'double')
                    attack,defend=(a,b) if turn==0 else (b,a)
                    await send(attack,type='draft',notes=NOTES);self.assertEqual((await recv(attack))['type'],'draft_ready')
                    self.assertEqual((await recv(defend))['type'],'activity')
                    await send(attack,type='confirm')
                    for w in (a,b):self.assertEqual((await recv(w))['notes'],NOTES)
                    s.rooms[code]['turn_started']=time.monotonic()-10
                    s.rooms[code]['deadline']=time.monotonic()-1
                    await send(defend,type='result',hits=NOTES)
                    for w in (a,b):
                        report=await recv(w);self.assertEqual(report['report']['points'],8000)
                    if turn==0:await send(a,type='next')
                await send(a,type='leave')
