import asyncio,json,sys,tempfile,time,unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).parents[1]/'server'))
import ranker,server as s
from accounts import Store
from scoring import analyze
from websockets.asyncio.client import connect
from websockets.asyncio.server import serve
class RankerScoring(unittest.TestCase):
    def test_eight_canonical_charts_and_strict_windows(self):
        for song in ranker.SONGS.values():
            self.assertGreaterEqual(song['duration']+song['audio_offset'],180)
            self.assertLessEqual(song['duration']+song['audio_offset'],240)
            self.assertEqual(len(song['bars']),song['section_bars']*4)
            for section in range(4):
                self.assertEqual(song['bars'][section*song['section_bars']]['section'],section)
            for kind,notes in song['charts'].items():
                self.assertGreater(len(notes),250)
                self.assertGreater(notes[-1]['t'],120)
                self.assertLessEqual(len(json.dumps(dict(type='ranker_result',session='x'*40,hits=notes)).encode()),262144)
                ends=[-10,-10]
                for n in notes:
                    lane=n.get('lane',0);self.assertGreaterEqual(n['t']-ends[lane],.07499);ends[lane]=n['t']+n['d']
                run=ranker.begin('uid',song['id'],kind);run['started']-=run['duration']+1
                report=ranker.finish(run,run['token'],notes)
                self.assertEqual((report['accuracy'],report['grade'],report['max_combo']),(100,'EX',len(notes)))
                shifted=[{**n,'t':n['t']+.04} for n in notes]
                self.assertEqual(ranker.finish(run,run['token'],shifted)['grade'],'F')
    def test_long_song_time_limit_does_not_relax_legacy_duels(self):
        note=[{'t':180,'d':0}]
        with self.assertRaises(ValueError):analyze(note,note)
        self.assertEqual(analyze(note,note,max_time=241)['accuracy'],100)
        with self.assertRaises(ValueError):analyze([{'t':242,'d':0}],[{'t':242,'d':0}],max_time=241)

    def test_dense_inputs_match_live_press_order(self):
        notes=[{'t':0,'d':0},{'t':.076,'d':0}]
        hits=[{'t':-.06,'d':.01},{'t':.01,'d':.01}]
        report=analyze(notes,hits,windows=ranker.WINDOWS,chronological=True)
        self.assertEqual(report['counts'],[0,0,2,0])
        self.assertEqual((report['extra'],report['max_combo']),(0,2))

    def test_session_timing_lane_and_token_validation(self):
        run=ranker.begin('uid','r01','one');notes=ranker.SONGS['r01']['charts']['one']
        with self.assertRaises(ValueError):ranker.finish(run,run['token'],notes)
        run['started']-=run['duration']+1
        with self.assertRaises(ValueError):ranker.finish(run,'wrong',notes)
        with self.assertRaises(ValueError):ranker.finish(run,run['token'],[{**n,'lane':1} for n in notes])
        with self.assertRaises(ValueError):ranker.finish(run,run['token'],notes*10)
    def test_best_record_and_first_clear_reward_once(self):
        with tempfile.TemporaryDirectory() as folder:
            store=Store(path=str(Path(folder)/'accounts.db'));profile=store.register('ranker_test','password123')['profile'];uid=profile['id']
            report=dict(points=100000,accuracy=98.1,max_combo=100,grade='SS')
            a=store.ranker_submit(uid,'r01','one',report);b=store.ranker_submit(uid,'r01','one',report)
            self.assertEqual((a['coins'],b['coins'],b['profile']['coins']),(40,0,40))
            store.ranker_submit(uid,'r01','double',{**report,'points':150000})
            board=store.ranker_board('r01','one',uid)
            self.assertEqual(len(board['rows']),1);self.assertEqual(board['own']['points'],100000)
            self.assertEqual(store.profile(uid)['coins'],80)
            # Reopening the database preserves records and the claimed clear reward.
            self.assertEqual(Store(path=store.path).ranker_submit(uid,'r01','one',report)['coins'],0)
    def test_parallel_first_clear_is_not_paid_twice(self):
        with tempfile.TemporaryDirectory() as folder:
            store=Store(path=str(Path(folder)/'parallel.db'));uid=store.register('parallel_ranker','password123')['profile']['id']
            report=dict(points=100000,accuracy=99,max_combo=100,grade='SS')
            with ThreadPoolExecutor(max_workers=4) as pool:
                rewards=list(pool.map(lambda _:store.ranker_submit(uid,'r04','double',report)['coins'],range(8)))
            self.assertEqual(sum(rewards),40)
            self.assertEqual(store.profile(uid)['coins'],40)

class RankerProtocol(unittest.IsolatedAsyncioTestCase):
    async def test_authenticated_global_replay_and_board(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(s,'store',Store(path=str(Path(folder)/'test.db'))):
            async with serve(s.handle,'127.0.0.1',0,max_size=262144) as server:
                async with connect(f'ws://127.0.0.1:{server.sockets[0].getsockname()[1]}') as ws:
                    async def send(**data):await ws.send(json.dumps(data))
                    async def recv():return json.loads(await asyncio.wait_for(ws.recv(),5))
                    await send(type='register',name='global_ranker',password='password123');await recv()
                    await send(type='ranker_begin',id='r01',kind='double');run=await recv();self.assertEqual(run['type'],'ranker_ready')
                    notes=ranker.SONGS['r01']['charts']['double']
                    await send(type='ranker_result',session=run['session'],hits=notes);self.assertEqual((await recv())['type'],'error')
                    # Move only this challenge's monotonic clock for a deterministic full replay.
                    original_finish=ranker.finish
                    def mature_finish(run,token,hits):
                        run=dict(run,started=run['started']-run['duration']-1)
                        return original_finish(run,token,hits)
                    with patch.object(ranker,'finish',side_effect=mature_finish):
                        await send(type='ranker_result',session=run['session'],hits=notes);result=await recv()
                    self.assertEqual((result['type'],result['report']['accuracy'],result['coins']),('ranker_result',100,40))
                    await send(type='ranker_result',session=run['session'],hits=notes);self.assertEqual((await recv())['type'],'error')
                    await asyncio.sleep(.26)
                    await send(type='ranker_board',id='r01',kind='double');board=await recv()
                    self.assertTrue(board['enabled']);self.assertEqual(board['rows'][0]['name'],'global_ranker')
    async def test_unconfigured_board_is_honest_and_guest_cannot_publish(self):
        with patch.object(s,'store',Store()):
            async with serve(s.handle,'127.0.0.1',0,max_size=262144) as server:
                async with connect(f'ws://127.0.0.1:{server.sockets[0].getsockname()[1]}') as ws:
                    await ws.send(json.dumps(dict(type='ranker_board',id='r01',kind='one')));board=json.loads(await ws.recv())
                    self.assertEqual((board['enabled'],board['rows']),(False,[]))
                    await ws.send(json.dumps(dict(type='ranker_begin',id='r01',kind='one')))
                    self.assertEqual(json.loads(await ws.recv())['type'],'error')
