import concurrent.futures, sys, tempfile, unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parents[1]/'server'))
from accounts import Store, AccountError

class Accounts(unittest.TestCase):
    def setUp(self):
        self.folder=tempfile.TemporaryDirectory()
        self.path=str(Path(self.folder.name)/'accounts.db')
        self.store=Store(path=self.path)
        self.a=self.store.register('플레이어1','rhythm-password-123')
        self.b=self.store.register('플레이어2','rhythm-password-456')
        self.ids=[self.a['profile']['id'],self.b['profile']['id']]
    def tearDown(self): self.folder.cleanup()
    def test_login_sessions_and_restart(self):
        new_store=Store(path=self.path)
        self.assertEqual(new_store.resume(self.a['token'])['name'],'플레이어1')
        with self.assertRaises(AccountError): new_store.login('플레이어1','wrong-password')
        with self.assertRaises(AccountError): new_store.resume('forged-token')
        signed=new_store.login('플레이어1','rhythm-password-123')
        new_store.logout(signed['token'])
        with self.assertRaises(AccountError): new_store.resume(signed['token'])
        with self.store.transaction() as db:
            row=db.execute('SELECT password_hash FROM accounts WHERE id=?',(self.ids[0],)).fetchone()
            self.assertNotIn('rhythm-password',row['password_hash'])
    def test_rewards_idempotency_and_rating(self):
        change=self.store.settle('m1',self.ids,[8000,4000],True)
        self.assertEqual(change[self.ids[0]]['coins'],60)
        self.assertEqual(change[self.ids[0]]['rating'],12)
        self.assertEqual(change[self.ids[1]]['rating'],-12)
        self.assertEqual(self.store.settle('m1',self.ids,[8000,4000],True),{})
        self.assertEqual(self.store.profile(self.ids[0])['coins'],60)
        self.assertEqual(self.store.settle('self',[self.ids[0]]*2,[8000,0],True),{})
        self.store.settle('casual',self.ids,[1,0],False)
        self.assertEqual(self.store.profile(self.ids[0])['rating'],1012)
        self.store.settle('forfeit',self.ids,[0,0],True,0)
        self.assertEqual(self.store.profile(self.ids[1])['coins'],30)
    def test_atomic_purchase(self):
        uid=self.ids[0]
        with self.assertRaises(AccountError): self.store.purchase(uid,'lavender')
        for i in range(2): self.store.settle('fund'+str(i),self.ids,[8,0])
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            results=list(pool.map(lambda _:self.store.purchase(uid,'lavender'),range(2)))
        profile=Store(path=self.path).profile(uid)
        self.assertEqual(profile['coins'],20)
        self.assertEqual(profile['owned'].count('lavender'),1)
        self.assertEqual(profile['skin'],'lavender')
        with self.assertRaises(AccountError): self.store.purchase(uid,'ice',True)
        with self.assertRaises(AccountError): self.store.purchase(uid,'fake_skin')
    def test_disabled_store_and_input_validation(self):
        with self.assertRaises(AccountError): Store().resume('token')
        for name,pw in [('a','password123'),('bad name','password123'),('valid','short')]:
            with self.assertRaises(AccountError): self.store.register(name,pw)
if __name__=='__main__': unittest.main()
