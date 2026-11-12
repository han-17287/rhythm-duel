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

def tier_fixture():
    charts={}
    for difficulty,count in [('hard',1),('expert',2),('inferno',3)]:
        one=[{'t':180+i*.2,'d':0} for i in range(count)]
        charts[difficulty]=dict(one=one,double=[{**n,'lane':i%2} for i,n in enumerate(one)])
    return dict(id='fixture',duration=190,audio_offset=1,charts=charts['hard'],extras={key:charts[key] for key in ['expert','inferno']})

class RankerScoring(unittest.TestCase):
    def test_revision_keys_keep_legacy_records_and_first_clear_separate(self):
        fixture=dict(tier_fixture(),revision=2)
        with tempfile.TemporaryDirectory() as folder,patch.dict(ranker.SONGS,{'fixture':fixture}):
            store=Store(path=str(Path(folder)/'revision.db'))
            uid=store.register('revision_records','password123')['profile']['id']
            report=dict(points=1000,accuracy=100,max_combo=1,grade='EX')
            self.assertEqual(ranker.storage_id('fixture'),'fixture:v2')
            for difficulty in ranker.DIFFICULTY_WINDOWS:
                # Existing scores and rewards survive; the new arrangement has
                # its own board and one first-clear reward, not a copied score.
                self.assertEqual(store.ranker_submit(uid,'fixture','one',report,difficulty)['coins'],40)
                self.assertIsNone(store.ranker_board(ranker.storage_id('fixture'),'one',uid,difficulty)['own'])
                current={**report,'points':2000}
                self.assertEqual(store.ranker_submit(uid,ranker.storage_id('fixture'),'one',current,difficulty)['coins'],40)
                self.assertEqual(store.ranker_submit(uid,ranker.storage_id('fixture'),'one',current,difficulty)['coins'],0)
                self.assertEqual(store.ranker_board('fixture','one',uid,difficulty)['own']['points'],1000)
                self.assertEqual(store.ranker_board(ranker.storage_id('fixture'),'one',uid,difficulty)['own']['points'],2000)
            self.assertEqual(store.profile(uid)['coins'],240)

    def test_revision_mismatch_cannot_start_or_finish_rewritten_chart(self):
        fixture=dict(tier_fixture(),revision=2)
        with patch.dict(ranker.SONGS,{'fixture':fixture}):
            self.assertEqual(ranker.require_revision('fixture',2),2)
            for wrong in [None,1,3,'2',True,2.0]:
                with self.subTest(revision=wrong),self.assertRaisesRegex(ValueError,'새로고침'):
                    ranker.require_revision('fixture',wrong)
            run=ranker.begin('uid','fixture','one');run['started']-=run['duration']+1
            self.assertEqual(run['revision'],2)
            self.assertEqual(ranker.finish(run,run['token'],fixture['charts']['one'])['accuracy'],100)
            fixture['revision']=3
            with self.assertRaisesRegex(ValueError,'새로고침'):
                ranker.finish(run,run['token'],fixture['charts']['one'])

    def test_rests_reward_precision_and_penalize_mashing(self):
        notes=[{'t':t,'d':0} for t in [0,.375,.75,1.5,1.875,2.625,3,3.5]]
        fixture=dict(tier_fixture(),revision=2,charts={'one':notes,'double':notes})
        with patch.dict(ranker.SONGS,{'fixture':fixture}):
            run=ranker.begin('uid','fixture','one');run['started']-=run['duration']+1
            exact=ranker.finish(run,run['token'],notes)
            mash=[{'t':i*.125,'d':.012} for i in range(29)]
            bad=ranker.finish(run,run['token'],mash)
            self.assertEqual((exact['accuracy'],exact['full_combo']),(100,True))
            self.assertEqual((bad['accuracy'],bad['grade'],bad['full_combo']),(0,'F',False))
            self.assertGreater(bad['extra'],0)
            # Even perfectly matched targets lose credit when a rest is hit.
            extra=notes+[{'t':1.125,'d':.012}]
            current=ranker.finish(run,run['token'],extra)
            self.assertEqual((current['points'],current['extra_penalty'],current['penalty_points']),(7400,600,600))
            legacy=analyze(notes,extra)
            self.assertEqual((legacy['points'],legacy['extra_penalty']),(7800,200))

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

    def test_all_difficulty_charts_are_scored_authoritatively(self):
        for song in ranker.SONGS.values():
            for difficulty in ranker.DIFFICULTY_WINDOWS:
                for kind in ['one','double']:
                    with self.subTest(song=song['id'],difficulty=difficulty,kind=kind):
                        notes=ranker.chart(song['id'],kind,difficulty)
                        self.assertLessEqual(len(notes),ranker.MAX_HITS)
                        run=ranker.begin('uid',song['id'],kind,difficulty);run['started']-=run['duration']+1
                        report=ranker.finish(run,run['token'],notes)
                        self.assertEqual((report['accuracy'],report['grade'],report['max_combo']),(100,'EX',len(notes)))
                        self.assertLessEqual(len(json.dumps(dict(type='ranker_result',session='x'*40,difficulty=difficulty,hits=notes)).encode()),s.MAX_MESSAGE_BYTES)

    def test_dense_inputs_match_live_press_order(self):
        notes=[{'t':0,'d':0},{'t':.076,'d':0}]
        hits=[{'t':-.06,'d':.01},{'t':.01,'d':.01}]
        report=analyze(notes,hits,windows=ranker.WINDOWS,chronological=True)
        self.assertEqual(report['counts'],[0,0,2,0])
        self.assertEqual((report['extra'],report['max_combo']),(0,2))

    def test_difficulty_windows_and_canonical_chart_are_bound_to_run(self):
        fixture=tier_fixture()
        with patch.dict(ranker.SONGS,{'fixture':fixture}):
            for difficulty,expected in [('hard',1000),('expert',700),('inferno',700)]:
                run=ranker.begin('uid','fixture','one',difficulty);run['started']-=run['duration']+1
                # Only the first note is pressed: 21ms is PERFECT on HARD but GREAT on tighter tiers.
                report=ranker.finish(run,run['token'],[{'t':180.021,'d':0}])
                self.assertEqual(report['points'],expected)
                self.assertEqual(run['difficulty'],difficulty)
            expert=ranker.begin('uid','fixture','one','expert');expert['started']-=expert['duration']+1
            self.assertEqual(ranker.finish(expert,expert['token'],fixture['charts']['one'])['accuracy'],50)
            self.assertEqual(ranker.finish(expert,expert['token'],fixture['extras']['expert']['one'])['accuracy'],100)
            for invalid in ['easy','EXPERT','',None]:
                with self.assertRaises((ValueError,TypeError)):ranker.begin('uid','fixture','one',invalid)
            # Missing extras must fail instead of silently submitting a HARD score for another tier.
            with patch.dict(ranker.SONGS,{'legacy':dict(fixture,charts=fixture['charts'],extras={})}):
                with self.assertRaises(ValueError):ranker.begin('uid','legacy','one','expert')

    def test_difficulty_bests_boards_and_rewards_preserve_legacy_hard(self):
        with tempfile.TemporaryDirectory() as folder:
            path=str(Path(folder)/'tiers.db');store=Store(path=path)
            uid=store.register('tier_records','password123')['profile']['id']
            for difficulty,points in [('hard',1000),('expert',2000),('inferno',3000)]:
                report=dict(points=points,accuracy=100,max_combo=points//1000,grade='EX')
                self.assertEqual(store.ranker_submit(uid,'r01','one',report,difficulty)['coins'],40)
                self.assertEqual(store.ranker_submit(uid,'r01','one',report,difficulty)['coins'],0)
                self.assertEqual(store.ranker_board('r01','one',uid,difficulty)['own']['points'],points)
            # Old callers still select exactly the original HARD record and reward flag.
            self.assertEqual(store.ranker_board('r01','one',uid)['own']['points'],1000)
            self.assertEqual(store.profile(uid)['coins'],120)
            reopened=Store(path=path)
            self.assertEqual(reopened.ranker_board('r01','one',uid,'inferno')['own']['points'],3000)
            with store.transaction() as db:
                keys=[row['song'] for row in db.execute('SELECT song FROM ranker_bests ORDER BY song').fetchall()]
            self.assertEqual(keys,['r01','r01:expert','r01:inferno'])
            with self.assertRaises(ValueError):store.ranker_board('r01','one',uid,'wrong')

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
    async def test_tiers_nonce_binding_and_separate_global_boards(self):
        fixture=tier_fixture()
        with tempfile.TemporaryDirectory() as folder,patch.object(s,'store',Store(path=str(Path(folder)/'tiers.db'))),patch.dict(ranker.SONGS,{'fixture':fixture}):
            async with serve(s.handle,'127.0.0.1',0,max_size=s.MAX_MESSAGE_BYTES) as server:
                async with connect(f'ws://127.0.0.1:{server.sockets[0].getsockname()[1]}') as ws:
                    async def send(**data):await ws.send(json.dumps(data))
                    async def recv():return json.loads(await asyncio.wait_for(ws.recv(),5))
                    await send(type='register',name='tier_protocol',password='password123');await recv()
                    original_finish=ranker.finish
                    def mature_finish(run,token,hits):
                        return original_finish(dict(run,started=run['started']-run['duration']-1),token,hits)
                    for difficulty,count in [('hard',1),('expert',2),('inferno',3)]:
                        await asyncio.sleep(.26)
                        # The first run deliberately uses the legacy request shape without a tier.
                        await send(type='ranker_begin',id='fixture',kind='one',**({} if difficulty=='hard' else {'difficulty':difficulty}))
                        ready=await recv();self.assertEqual((ready['type'],ready['difficulty']),('ranker_ready',difficulty))
                        notes=ranker.chart('fixture','one',difficulty)
                        await send(type='ranker_result',session=ready['session'],difficulty='wrong',hits=notes)
                        self.assertEqual((await recv())['type'],'error')
                        with patch.object(ranker,'finish',side_effect=mature_finish):
                            # An omitted result tier still uses the nonce-bound run, never the default HARD chart.
                            await send(type='ranker_result',session=ready['session'],hits=notes)
                            result=await recv()
                        self.assertEqual((result['type'],result['difficulty'],result['report']['points'],result['coins']),('ranker_result',difficulty,count*1000,40))
                        await send(type='ranker_result',session=ready['session'],difficulty=difficulty,hits=notes)
                        self.assertEqual((await recv())['type'],'error')
                        await send(type='ranker_board',id='fixture',kind='one',**({} if difficulty=='hard' else {'difficulty':difficulty}))
                        board=await recv()
                        self.assertEqual((board['difficulty'],board['own']['points']), (difficulty,count*1000))
                    self.assertEqual(result['profile']['coins'],120)

    async def test_authenticated_global_replay_and_board(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(s,'store',Store(path=str(Path(folder)/'test.db'))):
            async with serve(s.handle,'127.0.0.1',0,max_size=262144) as server:
                async with connect(f'ws://127.0.0.1:{server.sockets[0].getsockname()[1]}') as ws:
                    async def send(**data):await ws.send(json.dumps(data))
                    async def recv():return json.loads(await asyncio.wait_for(ws.recv(),5))
                    await send(type='register',name='global_ranker',password='password123');await recv()
                    await send(type='ranker_begin',id='r01',kind='double',revision=ranker.revision('r01'));run=await recv();self.assertEqual(run['type'],'ranker_ready')
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
                    await send(type='ranker_board',id='r01',kind='double',revision=ranker.revision('r01'));board=await recv()
                    self.assertTrue(board['enabled']);self.assertEqual(board['rows'][0]['name'],'global_ranker')
    async def test_unconfigured_board_is_honest_and_guest_cannot_publish(self):
        with patch.object(s,'store',Store()):
            async with serve(s.handle,'127.0.0.1',0,max_size=262144) as server:
                async with connect(f'ws://127.0.0.1:{server.sockets[0].getsockname()[1]}') as ws:
                    await ws.send(json.dumps(dict(type='ranker_board',id='r01',kind='one',revision=ranker.revision('r01'))));board=json.loads(await ws.recv())
                    self.assertEqual((board['enabled'],board['rows']),(False,[]))
                    await ws.send(json.dumps(dict(type='ranker_begin',id='r01',kind='one')))
                    self.assertEqual(json.loads(await ws.recv())['type'],'error')

    async def test_v2_protocol_rejects_cached_client_and_uses_current_board(self):
        fixture=dict(tier_fixture(),revision=2)
        with tempfile.TemporaryDirectory() as folder,patch.object(s,'store',Store(path=str(Path(folder)/'v2.db'))),patch.dict(ranker.SONGS,{'fixture':fixture}):
            async with serve(s.handle,'127.0.0.1',0,max_size=s.MAX_MESSAGE_BYTES) as server:
                async with connect(f'ws://127.0.0.1:{server.sockets[0].getsockname()[1]}') as ws:
                    async def send(**data):await ws.send(json.dumps(data))
                    async def recv():return json.loads(await asyncio.wait_for(ws.recv(),5))
                    await send(type='register',name='version_protocol',password='password123')
                    account=await recv();uid=account['profile']['id']
                    legacy=dict(points=999000,accuracy=100,max_combo=999,grade='EX')
                    s.store.ranker_submit(uid,'fixture','one',legacy)
                    for wrong in [None,1]:
                        await send(type='ranker_begin',id='fixture',kind='one',revision=wrong)
                        error=await recv();self.assertEqual(error['type'],'error');self.assertIn('새로고침',error['message'])
                    await send(type='ranker_board',id='fixture',kind='one')
                    error=await recv();self.assertEqual(error['type'],'error');self.assertIn('새로고침',error['message'])
                    await asyncio.sleep(.26)
                    await send(type='ranker_board',id='fixture',kind='one',revision=2)
                    board=await recv();self.assertEqual((board['revision'],board['rows'],board['own']),(2,[],None))
                    await send(type='ranker_begin',id='fixture',kind='one',revision=2)
                    ready=await recv();self.assertEqual((ready['type'],ready['revision']),('ranker_ready',2))
                    await send(type='ranker_result',session=ready['session'],revision=1,hits=fixture['charts']['one'])
                    self.assertEqual((await recv())['type'],'error')
                    original_finish=ranker.finish
                    def mature(run,token,hits):
                        return original_finish(dict(run,started=run['started']-run['duration']-1),token,hits)
                    with patch.object(ranker,'finish',side_effect=mature):
                        await send(type='ranker_result',session=ready['session'],revision=2,hits=fixture['charts']['one'])
                        result=await recv()
                    self.assertEqual((result['type'],result['revision'],result['report']['points'],result['coins']),('ranker_result',2,1000,40))
                    self.assertEqual(s.store.ranker_board('fixture','one',uid)['own']['points'],999000)
                    self.assertEqual(s.store.ranker_board('fixture:v2','one',uid)['own']['points'],1000)
