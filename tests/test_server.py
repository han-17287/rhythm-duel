import asyncio, importlib.util, json, unittest, tempfile
import urllib.request, urllib.error
from unittest.mock import patch
from pathlib import Path
from websockets.asyncio.client import connect
from websockets.asyncio.server import serve
spec=importlib.util.spec_from_file_location('relay',Path(__file__).parents[1]/'server/server.py')
s=importlib.util.module_from_spec(spec); spec.loader.exec_module(s)
NOTES=[{'t':i*.5,'d':0.0} for i in range(8)]
class Rules(unittest.TestCase):
    def test_judgments(self):
        for error,expected in [(0,8000),(.03,8000),(.06,5600),(.15,3200),(.3,0)]:
            hits=[{'t':n['t']+error,'d':0} for n in NOTES]
            self.assertEqual(s.score(NOTES,hits)[0],expected)
    def test_hold_release_and_spam(self):
        notes=[{'t':0.,'d':8.}]
        self.assertEqual(s.validate(notes),notes)
        self.assertEqual(s.score(notes,[{'t':0.,'d':8.}])[0],8000)
        self.assertEqual(s.score(notes,[{'t':0.,'d':1.}])[0],0)
        self.assertEqual(s.score(NOTES,[{'t':n['t'],'d':0} for n in NOTES]+[{'t':10,'d':0}])[0],7800)
    def test_invalid(self):
        for notes in [[],NOTES[:7],[{'t':0,'d':float('nan')}],[{'t':0,'d':9}], [{'t':0,'d':4},{'t':1,'d':4}]]:
            with self.assertRaises(ValueError): s.validate(notes)
class Network(unittest.IsolatedAsyncioTestCase):
    async def test_http_and_websocket_same_port(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(s,'STATIC_DIR',Path(folder)):
            Path(folder,'index.html').write_text('<title>PERFECTO</title>')
            Path(folder,'index.wasm').write_bytes(b'\x00asm')
            async with serve(s.handle,'127.0.0.1',0,process_request=s.serve_game) as server:
                port=server.sockets[0].getsockname()[1]
                def fetch(path):
                    with urllib.request.urlopen(f'http://127.0.0.1:{port}{path}') as r:
                        return r.status,r.headers['Content-Type'],r.read()
                status,mime,body=await asyncio.to_thread(fetch,'/')
                self.assertEqual(status,200); self.assertIn(b'PERFECTO',body)
                self.assertEqual((await asyncio.to_thread(fetch,'/index.wasm'))[1],'application/wasm')
                self.assertEqual((await asyncio.to_thread(fetch,'/health'))[2],b'ok')
                with self.assertRaises(urllib.error.HTTPError) as err:
                    await asyncio.to_thread(fetch,'/%2e%2e/server.py')
                self.assertEqual(err.exception.code,404)
                async with connect(f'ws://127.0.0.1:{port}') as ws:
                    await ws.send(json.dumps({'type':'create'}))
                    self.assertEqual(json.loads(await ws.recv())['type'],'joined')
    async def test_full_match(self):
        async with serve(s.handle,'127.0.0.1',0) as server:
            port=server.sockets[0].getsockname()[1]
            async with connect(f'ws://127.0.0.1:{port}') as a, connect(f'ws://127.0.0.1:{port}') as b:
                async def send(w,**m): await w.send(json.dumps(m))
                async def recv(w): return json.loads(await asyncio.wait_for(w.recv(),2))
                await send(a,type='create'); joined=await recv(a); code=joined['code']
                await send(b,type='join',code=code); self.assertEqual((await recv(b))['slot'],1)
                for turn in range(6):
                    for w in (a,b): self.assertEqual((await recv(w))['turn'],turn)
                    attack,defend=(a,b) if turn%2==0 else (b,a)
                    await send(defend,type='pattern',notes=NOTES)
                    self.assertEqual((await recv(defend))['type'],'error')
                    await send(attack,type='pattern',notes=NOTES)
                    for w in (a,b): self.assertEqual((await recv(w))['type'],'pattern')
                    await send(defend,type='result',hits=NOTES)
                    self.assertEqual((await recv(defend))['type'],'error')
                    s.rooms[code]['deadline']=__import__('time').monotonic()+5
                    await send(defend,type='result',hits=NOTES)
                    for w in (a,b):
                        result=await recv(w)
                        self.assertEqual(result['points'],8000)
                        self.assertEqual(result['finished'],turn==5)
                    if turn<5: await send(a,type='next')
                self.assertEqual(result['scores'],[24000,24000])
            await asyncio.sleep(.05)
            self.assertNotIn(code,s.rooms)
if __name__=='__main__': unittest.main()
