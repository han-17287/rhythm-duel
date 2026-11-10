import asyncio, importlib.util, json, sys, tempfile, time, unittest
from pathlib import Path
from unittest.mock import patch
from websockets.asyncio.client import connect
from websockets.asyncio.server import serve
sys.path.insert(0,str(Path(__file__).parents[1]/'server'))
import server as s
from accounts import Store
NOTES=[{'t':i*.5,'d':0} for i in range(8)]
class Modes(unittest.IsolatedAsyncioTestCase):
    async def test_authenticated_custom_match_and_rewards(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(s,'store',Store(path=str(Path(folder)/'test.db'))):
            async with serve(s.handle,'127.0.0.1',0) as server:
                port=server.sockets[0].getsockname()[1]
                async with connect(f'ws://127.0.0.1:{port}') as a,connect(f'ws://127.0.0.1:{port}') as b:
                    async def send(w,**m): await w.send(json.dumps(m))
                    async def recv(w): return json.loads(await asyncio.wait_for(w.recv(),3))
                    for i,w in enumerate((a,b)):
                        await send(w,type='register',name='mode_player'+str(i),password='good_password123')
                        self.assertEqual((await recv(w))['type'],'profile')
                    await send(a,type='create',settings={'mode':'rush','rounds':1,'speed':1.5})
                    room=(await recv(a))['code']; await recv(a)
                    await send(b,type='join',code=room); await recv(b); await recv(a); await recv(b)
                    await send(b,type='configure',settings={'mode':'casual','rounds':9,'speed':2})
                    self.assertEqual((await recv(b))['type'],'error')
                    await send(a,type='start')
                    for turn in range(2):
                        for w in (a,b):
                            packet=await recv(w)
                            self.assertEqual(packet['speed'],1.5)
                            self.assertEqual(packet['settings']['rounds'],1)
                        attack,defend=(a,b) if turn==0 else (b,a)
                        await send(attack,type='pattern',notes=NOTES)
                        await recv(a); await recv(b)
                        s.rooms[room]['deadline']=time.monotonic()+5
                        await send(defend,type='result',hits=NOTES if turn==0 else [])
                        for w in (a,b):
                            packet=await recv(w); self.assertEqual(packet['finished'],turn==1)
                        if turn==0: await send(a,type='next')
                    ra=await recv(a); rb=await recv(b)
                    self.assertEqual(ra['type'],'reward');self.assertEqual(rb['type'],'reward')
                    self.assertEqual(ra['coins'],15);self.assertEqual(rb['coins'],60)
                    self.assertEqual(ra['rating'],0);self.assertEqual(rb['profile']['wins'],1)
                    await send(b,type='result',hits=NOTES)
                    self.assertEqual((await recv(b))['type'],'error')
                    self.assertEqual(s.store.profile(rb['profile']['id'])['coins'],60)
    def test_setting_validation_and_ranked_lock(self):
        self.assertEqual(s.settings({'mode':'ranked','rounds':9,'speed':2}),{'mode':'ranked','rounds':3,'speed':1.0})
        for data in [{'rounds':0},{'rounds':100},{'rounds':1.5},{'rounds':True},{'speed':float('nan')},{'speed':4},{'speed':1.1},{'mode':'fake'}]:
            with self.assertRaises(ValueError): s.settings(data)
        r={'settings':{'mode':'rush','rounds':9,'speed':2},'turn':16}
        self.assertEqual(s.turn_speed(r),3)
if __name__=='__main__': unittest.main()
