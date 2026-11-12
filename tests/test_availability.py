"""Account startup failures must not take down the playable site or guest rooms."""
import asyncio
import importlib.util
import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.request
from pathlib import Path
from unittest.mock import patch
from websockets.asyncio.client import connect
from websockets.asyncio.server import serve

sys.path.insert(0,str(Path(__file__).parents[1]/'server'))
from accounts import Store
spec=importlib.util.spec_from_file_location('availability_relay',Path(__file__).parents[1]/'server/server.py')
s=importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)

class Availability(unittest.IsolatedAsyncioTestCase):
    async def test_failed_database_keeps_http_and_guest_rooms_then_recovers(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'index.html').write_text('<title>PERFECTO</title>')
            ready=Store(path=str(root/'accounts.sqlite'))
            allow_recovery=threading.Event()
            def attempt():
                if not allow_recovery.is_set():raise ConnectionError('SECRET_FIXTURE_DATABASE_URL')
                return ready
            with patch.dict(os.environ,{'DATABASE_URL':'configured','ACCOUNT_DB_PATH':''}),patch.object(s,'STATIC_DIR',root),patch.object(s,'store',Store()),patch.object(s,'ACCOUNT_RETRY_SECONDS',.02),patch.object(Store,'from_env',side_effect=attempt),self.assertLogs(level='WARNING') as logs:
                async with serve(s.handle,'127.0.0.1',0,process_request=s.serve_game) as server:
                    port=server.sockets[0].getsockname()[1]
                    task=asyncio.create_task(s.initialize_accounts())
                    try:
                        def fetch(path):
                            with urllib.request.urlopen(f'http://127.0.0.1:{port}{path}',timeout=2) as response:return response.status,response.read()
                        self.assertEqual(await asyncio.to_thread(fetch,'/'),(200,b'<title>PERFECTO</title>'))
                        self.assertEqual(await asyncio.to_thread(fetch,'/health'),(200,b'ok'))
                        async with connect(f'ws://127.0.0.1:{port}') as a,connect(f'ws://127.0.0.1:{port}') as b:
                            async def recv(ws):return json.loads(await asyncio.wait_for(ws.recv(),2))
                            await a.send(json.dumps({'type':'hello'}));self.assertFalse((await recv(a))['accounts_enabled'])
                            await a.send(json.dumps({'type':'create'}));joined=await recv(a);self.assertEqual(joined['type'],'joined');await recv(a)
                            await b.send(json.dumps({'type':'join','code':joined['code']}));self.assertEqual((await recv(b))['type'],'joined');await recv(a);await recv(b)
                            allow_recovery.set();await asyncio.wait_for(task,2)
                            self.assertTrue((await recv(a))['accounts_enabled']);self.assertTrue((await recv(b))['accounts_enabled'])
                            async with connect(f'ws://127.0.0.1:{port}') as account:
                                await account.send(json.dumps({'type':'register','name':'Recovered','password':'fixture-password'}))
                                self.assertEqual((await recv(account))['type'],'profile')
                        self.assertIs(s.store,ready)
                    finally:
                        task.cancel();await asyncio.gather(task,return_exceptions=True)
                self.assertNotIn('SECRET_FIXTURE',str(logs.output))
                self.assertIn('Account database unavailable',str(logs.output))
                self.assertIn('Account database ready',str(logs.output))

    async def test_slow_database_initialization_does_not_block_http(self):
        release=threading.Event();entered=threading.Event()
        def slow():
            entered.set();release.wait(5);return Store()
        with patch.dict(os.environ,{'DATABASE_URL':'configured'}),patch.object(Store,'from_env',side_effect=slow):
            async with serve(s.handle,'127.0.0.1',0,process_request=s.serve_game) as server:
                task=asyncio.create_task(s.initialize_accounts())
                try:
                    self.assertTrue(await asyncio.to_thread(entered.wait,2))
                    port=server.sockets[0].getsockname()[1]
                    def fetch():
                        with urllib.request.urlopen(f'http://127.0.0.1:{port}/health',timeout=1) as r:return r.status
                    self.assertEqual(await asyncio.wait_for(asyncio.to_thread(fetch),2),200)
                finally:
                    release.set();await asyncio.wait_for(task,2)

    async def test_no_database_configuration_stays_explicitly_disabled(self):
        with patch.dict(os.environ,{'DATABASE_URL':'','ACCOUNT_DB_PATH':''}),patch.object(s,'store',Store()),patch.object(Store,'from_env') as factory:
            await s.initialize_accounts();factory.assert_not_called();self.assertFalse(s.store.enabled)

if __name__=='__main__':unittest.main()
