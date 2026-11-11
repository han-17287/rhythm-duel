import asyncio,json,sys,time,unittest
from pathlib import Path
from websockets.asyncio.client import connect
from websockets.asyncio.server import serve
sys.path.insert(0,str(Path(__file__).parents[1]/'server'))
import server as s
NOTES=[{'t':i*.5,'d':0} for i in range(8)]
class Protocol(unittest.IsolatedAsyncioTestCase):
    async def test_draft_preview_edit_report_and_rematch(self):
        async with serve(s.handle,'127.0.0.1',0) as server:
            url=f"ws://127.0.0.1:{server.sockets[0].getsockname()[1]}"
            async with connect(url) as a,connect(url) as b:
                async def send(w,**m):await w.send(json.dumps(m))
                async def recv(w,expected):
                    m=json.loads(await asyncio.wait_for(w.recv(),2));self.assertEqual(m['type'],expected,m);return m
                await send(a,type='create',settings={'mode':'casual','rounds':1,'speed':1.25})
                code=(await recv(a,'joined'))['code'];await recv(a,'room')
                await send(b,type='join',code=code);await recv(b,'joined');await recv(a,'room');await recv(b,'room')
                await send(a,type='start');await recv(a,'turn');await recv(b,'turn')
                original_id=s.rooms[code]['id']
                for turn in range(2):
                    attack,defend=(a,b) if turn==0 else (b,a)
                    await send(attack,type='activity',units=4);self.assertEqual((await recv(defend,'activity'))['units'],4)
                    await send(attack,type='draft',notes=NOTES)
                    await recv(attack,'draft_ready');self.assertTrue((await recv(defend,'activity'))['review'])
                    self.assertEqual(s.rooms[code]['phase'],'review')
                    await send(defend,type='confirm');await recv(defend,'error')
                    await send(attack,type='edit');self.assertEqual((await recv(defend,'activity'))['units'],0)
                    await send(attack,type='confirm');await recv(attack,'error')
                    await send(attack,type='draft',notes=NOTES);await recv(attack,'draft_ready');await recv(defend,'activity')
                    await send(attack,type='confirm');await recv(a,'pattern');await recv(b,'pattern')
                    await send(defend,type='progress',combo=4,resolved=4)
                    self.assertEqual((await recv(attack,'progress'))['combo'],4)
                    s.rooms[code]['deadline']=time.monotonic()+5
                    await send(defend,type='result',hits=NOTES)
                    for w in (a,b):
                        result=await recv(w,'result');self.assertEqual(result['report']['max_combo'],8);self.assertTrue(result['report']['all_perfect'])
                    if turn==0:
                        await send(a,type='next');await recv(a,'turn');await recv(b,'turn')
                self.assertTrue(result['finished'])
                await send(a,type='rematch')
                for w in (a,b):self.assertEqual((await recv(w,'rematch_state'))['votes'],[0])
                self.assertEqual(s.rooms[code]['id'],original_id)
                await send(b,type='rematch')
                for w in (a,b):
                    await recv(w,'rematch_state')
                    next_match=await recv(w,'turn')
                    self.assertEqual(next_match['scores'],[0,0]);self.assertEqual(next_match['attacker'],1)
                self.assertNotEqual(s.rooms[code]['id'],original_id)
                await send(a,type='emote',emote='좋은 리듬!')
                for w in (a,b):self.assertEqual((await recv(w,'emote'))['text'],'좋은 리듬!')
                await send(b,type='emote',emote='<script>')
                await recv(b,'error')
            await asyncio.sleep(.02)
            self.assertNotIn(code,s.rooms)
    async def test_excess_taps_finish_round_as_zero(self):
        async with serve(s.handle,'127.0.0.1',0) as server:
            url=f"ws://127.0.0.1:{server.sockets[0].getsockname()[1]}"
            async with connect(url) as a,connect(url) as b:
                async def send(w,**m):await w.send(json.dumps(m))
                async def recv(w):return json.loads(await asyncio.wait_for(w.recv(),2))
                await send(a,type='create');code=(await recv(a))['code'];await recv(a)
                await send(b,type='join',code=code);await recv(b);await recv(a);await recv(b)
                await send(a,type='start');await recv(a);await recv(b)
                await send(a,type='pattern',notes=NOTES);await recv(a);await recv(b)
                s.rooms[code]['deadline']=time.monotonic()+5
                await send(b,type='result',hits=NOTES+[{'t':10+i*.01,'d':0} for i in range(70)])
                for w in (a,b):
                    result=await recv(w)
                    self.assertEqual(result['type'],'result');self.assertEqual(result['points'],0)
                    self.assertIn('warning',result['report'])
                await send(a,type='next')
                self.assertEqual((await recv(a))['type'],'turn')
                await recv(b)
    async def test_leaving_already_closed_room_is_idempotent(self):
        async with serve(s.handle,'127.0.0.1',0) as server:
            url=f"ws://127.0.0.1:{server.sockets[0].getsockname()[1]}"
            async with connect(url) as ws:
                for _ in range(2):
                    await ws.send(json.dumps({'type':'leave'}))
                    response=json.loads(await asyncio.wait_for(ws.recv(),2))
                    self.assertEqual(response['type'],'leave_ok')
if __name__=='__main__':unittest.main()
