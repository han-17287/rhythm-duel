"""Real WebSocket coverage for the public directory and human matchmaking lifecycle."""
import asyncio
from contextlib import AsyncExitStack
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import AsyncMock, patch

from websockets.asyncio.client import connect
from websockets.asyncio.server import serve
from websockets.protocol import State

sys.path.insert(0,str(Path(__file__).parents[1]/'server'))
import server as s
from accounts import Store


class Peer:
    def __init__(self, ws):
        self.ws=ws
        self.pending=[]

    async def send(self, typ, **data):
        await self.ws.send(json.dumps(dict(type=typ,**data)))

    async def until(self, typ, **fields):
        def wanted(packet):
            return packet.get('type')==typ and all(packet.get(k)==v for k,v in fields.items())
        for index,packet in enumerate(self.pending):
            if wanted(packet):
                return self.pending.pop(index)
        async with asyncio.timeout(3):
            while True:
                packet=json.loads(await self.ws.recv())
                if wanted(packet):
                    return packet
                if packet.get('type')=='error' and typ!='error':
                    raise AssertionError(f'Unexpected server error while waiting for {typ}: {packet}')
                self.pending.append(packet)

    async def no(self, typ, seconds=.08):
        if any(p.get('type')==typ for p in self.pending):
            raise AssertionError(f'Unexpected queued {typ}: {self.pending}')
        try:
            async with asyncio.timeout(seconds):
                while True:
                    packet=json.loads(await self.ws.recv())
                    if packet.get('type')==typ:
                        raise AssertionError(f'Unexpected {typ}: {packet}')
                    self.pending.append(packet)
        except TimeoutError:
            return


class Social(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.stack=AsyncExitStack()
        await self.stack.__aenter__()
        self.folder=tempfile.TemporaryDirectory()
        self.stack.callback(self.folder.cleanup)
        self.store=Store(path=str(Path(self.folder.name)/'accounts.db'))
        self.stack.enter_context(patch.object(s,'store',self.store))
        self.stack.enter_context(patch.object(s,'MATCH_START_DELAY',.15))
        self.stack.enter_context(patch.object(s,'BROWSE_INTERVAL',0))
        self.stack.enter_context(patch.object(s,'MATCH_JOIN_INTERVAL',0))
        self.server=await self.stack.enter_async_context(serve(s.handle,'127.0.0.1',0))
        self.uri=f"ws://127.0.0.1:{self.server.sockets[0].getsockname()[1]}"

    async def asyncTearDown(self):
        await self.stack.aclose()
        await asyncio.sleep(0)
        self.assertFalse(s.rooms,'Disconnected clients must not leave rooms behind')
        self.assertFalse(s.sessions,'Disconnected clients must not leave sessions behind')
        self.assertFalse(s.match_tasks,'Disconnected clients must cancel countdown tasks')
        self.assertTrue(all(not queue for queue in s.match_queues.values()),'Disconnected clients must not leave queue entries behind')

    async def peer(self):
        ws=await self.stack.enter_async_context(connect(self.uri))
        return Peer(ws)

    async def user(self, name, token=None):
        if token is None:
            token=self.store.register(name,'matching-password123')['token']
        peer=await self.peer()
        await peer.send('resume',token=token)
        profile=(await peer.until('profile'))['profile']
        return peer,profile,token

    async def listing(self, peer, mode='all'):
        await peer.send('browse_rooms',mode=mode)
        return await peer.until('room_list')

    async def test_directory_hides_private_full_and_started_rooms(self):
        private,host,browser,guest=await self.peer(),await self.peer(),await self.peer(),await self.peer()
        await private.send('create',title='비공개 초대방')
        private_room=await private.until('joined')
        await host.send('create',public=True,title='  같이 리듬을 쳐요  ',settings={'mode':'double','rounds':1,'speed':1.25})
        public_room=await host.until('joined')
        self.assertTrue(public_room['public'])
        self.assertFalse(public_room.get('auto',False))
        listing=await self.listing(browser)
        self.assertEqual(listing['total'],1)
        row=listing['rooms'][0]
        self.assertEqual(row['code'],public_room['code'])
        self.assertEqual(row['title'],'같이 리듬을 쳐요')
        self.assertEqual((row['count'],row['settings']['mode'],row['settings']['rounds']),(1,'double',1))
        self.assertNotIn(private_room['code'],json.dumps(listing))
        self.assertEqual((await self.listing(browser,'casual'))['rooms'],[])
        self.assertEqual(len((await self.listing(browser,'double'))['rooms']),1)
        await guest.send('join',code=public_room['code'])
        self.assertEqual((await guest.until('joined'))['slot'],1)
        self.assertEqual((await self.listing(browser))['rooms'],[])
        await host.send('start')
        self.assertEqual((await host.until('turn'))['settings']['mode'],'double')
        await guest.until('turn')
        self.assertEqual((await self.listing(browser))['rooms'],[])
        await guest.send('leave')
        await guest.until('leave_ok')
        await host.until('left')
        # Legacy private code invitation still works and does not appear in discovery.
        await guest.send('join',code=private_room['code'])
        self.assertEqual((await guest.until('joined'))['code'],private_room['code'])

    async def test_public_host_departure_and_invalid_metadata(self):
        host,browser=await self.peer(),await self.peer()
        for payload in [dict(public='yes'),dict(public=True,title='x'*33),dict(public=True,title='한 줄\n두 줄')]:
            await host.send('create',**payload)
            await host.until('error',action='create')
        await host.send('create',public=True,title='공개 대기실')
        code=(await host.until('joined'))['code']
        self.assertEqual((await self.listing(browser))['rooms'][0]['code'],code)
        await host.ws.close()
        await asyncio.sleep(.04)
        self.assertEqual((await self.listing(browser))['rooms'],[])

    async def test_expired_public_room_is_hidden_and_cannot_be_joined(self):
        host,browser=await self.peer(),await self.peer()
        await host.send('create',public=True,title='만료 경계 검사')
        code=(await host.until('joined'))['code']
        self.assertEqual((await self.listing(browser))['rooms'][0]['code'],code)
        # Expiry is authoritative even before the periodic room janitor wakes up.
        s.rooms[code]['deadline']=time.monotonic()-1
        self.assertEqual((await self.listing(browser))['rooms'],[])
        await browser.send('join',code=code)
        await browser.until('error',action='join')

    async def test_real_human_mode_queues_autostart_and_hide_auto_rooms(self):
        casual,a,b,browser=await self.peer(),await self.peer(),await self.peer(),await self.peer()
        await casual.send('match_join',mode='casual')
        self.assertEqual((await casual.until('match_status',queued=True))['waiting'],1)
        await a.send('match_join',mode='double')
        self.assertEqual((await a.until('match_status',queued=True))['waiting'],1)
        await casual.no('joined')
        await a.no('joined')
        await b.send('match_join',mode='double',settings={'rounds':9,'speed':2})
        ja,jb=await a.until('joined'),await b.until('joined')
        self.assertEqual(ja['code'],jb['code'])
        self.assertEqual((ja['slot'],jb['slot']),(0,1))
        self.assertTrue(ja['auto']);self.assertFalse(ja['public'])
        self.assertEqual(ja['settings'],{'mode':'double','rounds':3,'speed':1.0})
        ma,mb=await a.until('match_found'),await b.until('match_found')
        self.assertNotEqual(ma['opponent'],mb['opponent'])
        self.assertEqual((await self.listing(browser))['rooms'],[])
        ta,tb=await a.until('turn'),await b.until('turn')
        self.assertEqual(ta['turn'],0);self.assertEqual(tb['attacker'],ta['attacker'])
        await casual.no('joined')
        await casual.send('match_cancel');await casual.until('match_status',queued=False)

    async def test_duplicate_queue_join_cancel_and_prestart_cancel_race(self):
        a,b,c=await self.peer(),await self.peer(),await self.peer()
        for _ in range(4):
            await a.send('match_join',mode='casual')
            status=await a.until('match_status',queued=True)
            self.assertEqual((status['waiting'],status['position']),(1,1))
        await a.send('match_cancel');await a.until('match_status',queued=False)
        await b.send('match_join',mode='casual');await b.until('match_status',queued=True)
        await b.no('joined')
        await a.send('match_join',mode='casual')
        jb,ja=await b.until('joined'),await a.until('joined')
        self.assertEqual(jb['code'],ja['code'])
        self.assertEqual(jb['slot'],0,'FIFO keeps the older human at the front')
        await a.send('match_cancel')
        await a.until('match_status',queued=False)
        await b.until('left')
        await a.no('turn',.2);await b.no('turn',.05)
        await c.send('match_join',mode='casual');await c.until('match_status',queued=True)
        await c.no('joined')
        await a.send('create',public=True,title='취소 후 새 방')
        self.assertTrue((await a.until('joined'))['public'])

    async def test_disconnect_and_room_creation_remove_queue_entries(self):
        a,b,c=await self.peer(),await self.peer(),await self.peer()
        await a.send('match_join',mode='rush');await a.until('match_status',queued=True)
        await a.ws.close();await asyncio.sleep(.04)
        await b.send('match_join',mode='rush');await b.until('match_status',queued=True)
        await b.no('joined')
        await b.send('create',public=True,title='직접 만든 방')
        code=(await b.until('joined'))['code']
        await c.send('match_join',mode='rush');await c.until('match_status',queued=True)
        await c.no('joined')
        await c.send('match_cancel');await c.until('match_status',queued=False)
        await c.send('join',code=code)
        self.assertEqual((await c.until('joined'))['slot'],1)

    async def test_ranked_guards_and_same_account_never_self_matches(self):
        guest=await self.peer()
        await guest.send('match_join',mode='ranked')
        await guest.until('error',action='match_join')
        a,pa,token=await self.user('same_ranker')
        b,pb,_=await self.user('same_ranker',token)
        self.assertEqual(pa['id'],pb['id'])
        await a.send('match_join',mode='ranked');await a.until('match_status',queued=True)
        await b.send('match_join',mode='ranked')
        # Implementations may reject duplicate-account queue entry or leave it unmatched.
        await a.no('joined');await b.no('joined')
        c,pc,_=await self.user('other_ranker')
        await c.send('match_join',mode='ranked')
        ja,jc=await a.until('joined'),await c.until('joined')
        self.assertEqual(ja['code'],jc['code'])
        self.assertEqual(ja['settings'],{'mode':'ranked','rounds':3,'speed':1.0})
        await a.until('turn');await c.until('turn')
        await b.no('joined')

    async def test_ranked_prestart_cancel_is_free_but_active_forfeit_counts(self):
        a,pa,_=await self.user('fair_cancel_a')
        b,pb,_=await self.user('fair_cancel_b')
        await a.send('match_join',mode='ranked');await a.until('match_status',queued=True)
        await b.send('match_join',mode='ranked')
        await a.until('joined');await b.until('joined')
        await a.until('match_found');await b.until('match_found')
        await a.send('match_cancel');await a.until('match_status',queued=False)
        # Canceling a reserved match also acknowledges leaving that room.
        # Consume it here so the next game's leave cannot match this old reply.
        await a.until('leave_ok');await b.until('left')
        for profile in (pa,pb):
            stored=self.store.profile(profile['id'])
            self.assertEqual((stored['rating'],stored['coins'],stored['wins'],stored['losses']),(1000,0,0,0))
        # Once a real round starts, leaving still follows the existing ranked penalty.
        await a.send('match_join',mode='ranked');await a.until('match_status',queued=True)
        await b.send('match_join',mode='ranked')
        await a.until('joined');await b.until('joined')
        await a.until('turn');await b.until('turn')
        await a.send('leave');await a.until('leave_ok');await b.until('left')
        # `left` is intentionally sent before storage work. The reward packets
        # are the protocol's confirmation that the ranked settlement committed.
        loser_reward=await a.until('reward');winner_reward=await b.until('reward')
        self.assertEqual((loser_reward['profile']['losses'],winner_reward['profile']['wins']),(1,1))
        loser=self.store.profile(pa['id']);winner=self.store.profile(pb['id'])
        self.assertEqual((loser['losses'],winner['wins']),(1,1))
        self.assertLess(loser['rating'],1000);self.assertGreater(winner['rating'],1000)
        self.assertEqual((loser['coins'],winner['coins']),(0,0))

    async def test_departure_arrives_before_slow_settlement_and_new_room(self):
        a,b=await self.peer(),await self.peer()
        await a.send('create',settings={'mode':'casual','rounds':1,'speed':1.0})
        old_code=(await a.until('joined'))['code']
        old_id=s.rooms[old_code]['id']
        await b.send('join',code=old_code);await b.until('joined')
        await a.send('start');await a.until('turn');await b.until('turn')
        settling=asyncio.Event();release=asyncio.Event()
        async def slow_award(room, forfeit=None):
            settling.set()
            await release.wait()
        with patch.object(s,'award',slow_award):
            try:
                await a.send('leave')
                await asyncio.wait_for(settling.wait(),1)
                # The survivor must be released while account storage is still blocked.
                left=await b.until('left',code=old_code)
                self.assertEqual(left['room_id'],old_id)
                self.assertFalse(release.is_set())
                await b.send('create',title='새로운 대기실')
                new_code=(await b.until('joined'))['code']
                self.assertNotEqual(new_code,old_code)
                release.set();await a.until('leave_ok')
                await b.no('left',.05)
                self.assertIn(new_code,s.rooms)
                self.assertEqual((s.rooms[new_code]['phase'],len(s.rooms[new_code]['players'])),('waiting',1))
                self.assertTrue(any(state['room']==new_code for state in s.sessions.values()))
            finally:
                release.set()

    async def test_closing_connection_is_ineligible_before_handler_finally(self):
        class FakeSocket:
            def __init__(self, state):
                self.state=state
                self.packets=[]
            async def send(self, raw):
                self.packets.append(json.loads(raw))
        host=FakeSocket(State.OPEN);reader=FakeSocket(State.OPEN);survivor=FakeSocket(State.OPEN)
        fake_sockets=[host,reader,survivor];created=[]
        for index,ws in enumerate(fake_sockets):
            s.sessions[ws]={'room':None,'slot':-1,'uid':str(index),'name':f'fake{index}','token':'','queue_mode':'casual'}
        try:
            # A still-registered connection must stop being eligible at CLOSING,
            # without waiting for its WebSocket handler's finally block to run.
            self.assertTrue(s.queue_valid(host,'casual'))
            host.state=State.CLOSING
            self.assertFalse(s.queue_valid(host,'casual'))
            code,room=s.make_room(s.settings(),'종료 중인 방장',public=True);created.append(code)
            room['players']=[host];room['names']=['closing'];room['users']=['0']
            host.state=State.OPEN;self.assertTrue(s.room_joinable(room))
            host.state=State.CLOSING;self.assertFalse(s.room_joinable(room))
            await s.directory(reader)
            self.assertEqual((reader.packets[-1]['type'],reader.packets[-1]['rooms']),('room_list',[]))
            s.rooms.pop(code)
            auto_code,matched=s.make_room(s.settings(),'자동 매칭',auto=True);created.append(auto_code)
            matched['players']=[survivor,host];matched['names']=['survivor','closing'];matched['users']=['2','0']
            for slot,ws in enumerate(matched['players']):
                s.sessions[ws].update(room=auto_code,slot=slot,queue_mode=None)
            with patch.object(s,'MATCH_START_DELAY',0),patch.object(s,'award',new=AsyncMock()) as award,patch.object(s,'turn',new=AsyncMock()) as turn:
                await s.start_automatic(auto_code,matched['id'])
                award.assert_not_awaited();turn.assert_not_awaited()
            self.assertNotIn(auto_code,s.rooms)
            self.assertEqual((survivor.packets[-1]['type'],survivor.packets[-1]['code']),('left',auto_code))
            self.assertEqual(host.packets,[],'The live survivor, not the closing peer, receives departure')
            self.assertIsNone(s.sessions[survivor]['room'])
            self.assertIsNone(s.sessions[host]['room'])
        finally:
            for code in created:s.rooms.pop(code,None)
            for ws in fake_sockets:s.sessions.pop(ws,None)

    async def test_auth_change_and_ranker_run_cancel_waiting_ticket(self):
        a,profile,_=await self.user('change_identity')
        b=await self.peer()
        await a.send('match_join',mode='casual');await a.until('match_status',queued=True)
        await a.send('logout');self.assertEqual((await a.until('profile'))['profile'],{})
        await b.send('match_join',mode='casual');await b.until('match_status',queued=True)
        await b.no('joined')
        await b.send('match_cancel');await b.until('match_status',queued=False)
        await a.send('login',name='change_identity',password='matching-password123');await a.until('profile')
        await a.send('match_join',mode='casual');await a.until('match_status',queued=True)
        await a.send('ranker_begin',id='r01',kind='one',difficulty='hard',revision=s.ranker.revision('r01'))
        self.assertEqual((await a.until('ranker_ready'))['id'],'r01')
        await b.send('match_join',mode='casual');await b.until('match_status',queued=True)
        await b.no('joined')


if __name__=='__main__':
    unittest.main()
