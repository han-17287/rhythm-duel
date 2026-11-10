"""Account storage. PostgreSQL in production; explicitly configured SQLite for development."""
import hashlib, hmac, json, math, os, re, secrets, sqlite3, time, uuid
from contextlib import contextmanager
from pathlib import Path

CATALOG=[
    {'id':'mint','name':'민트 펄스','price':0,'color':'54f4d4'},
    {'id':'lavender','name':'라벤더 웨이브','price':100,'color':'b49bff'},
    {'id':'sunset','name':'선셋 글로우','price':250,'color':'ff997d'},
    {'id':'ice','name':'아이스 블루','price':400,'color':'8cdaff'},
]
class AccountError(ValueError): pass
class DB:
    def __init__(self,connection,postgres): self.connection=connection; self.postgres=postgres
    def execute(self,sql,args=()): return self.connection.execute(sql.replace('?','%s') if self.postgres else sql,args)
class Store:
    def __init__(self,url=None,path=None):
        self.url=url; self.path=path; self.enabled=bool(url or path)
        if self.enabled: self.initialize()
    @classmethod
    def from_env(cls): return cls(os.getenv('DATABASE_URL'),os.getenv('ACCOUNT_DB_PATH'))
    @contextmanager
    def transaction(self):
        if not self.enabled: raise AccountError('계정 저장소 연결이 필요합니다. 지금은 게스트 대전을 이용하세요.')
        if self.url:
            import psycopg
            from psycopg.rows import dict_row
            c=psycopg.connect(self.url,row_factory=dict_row,connect_timeout=10)
        else:
            Path(self.path).parent.mkdir(parents=True,exist_ok=True)
            c=sqlite3.connect(self.path,timeout=10,isolation_level=None)
            c.row_factory=sqlite3.Row; c.execute('PRAGMA foreign_keys=ON'); c.execute('BEGIN IMMEDIATE')
        try:
            yield DB(c,bool(self.url)); c.commit()
        except Exception:
            c.rollback(); raise
        finally: c.close()
    def initialize(self):
        statements=[
            'CREATE TABLE IF NOT EXISTS accounts (id TEXT PRIMARY KEY, username TEXT UNIQUE NOT NULL, name TEXT NOT NULL, salt TEXT NOT NULL, password_hash TEXT NOT NULL, rating INTEGER NOT NULL DEFAULT 1000, coins INTEGER NOT NULL DEFAULT 0 CHECK(coins>=0), wins INTEGER NOT NULL DEFAULT 0, losses INTEGER NOT NULL DEFAULT 0, draws INTEGER NOT NULL DEFAULT 0, skin TEXT NOT NULL DEFAULT \'mint\')',
            'CREATE TABLE IF NOT EXISTS inventory (account_id TEXT NOT NULL REFERENCES accounts(id), skin TEXT NOT NULL, PRIMARY KEY(account_id,skin))',
            'CREATE TABLE IF NOT EXISTS sessions (token_hash TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id), expires BIGINT NOT NULL)',
            'CREATE TABLE IF NOT EXISTS settlements (match_id TEXT PRIMARY KEY, details TEXT NOT NULL)',
        ]
        with self.transaction() as db:
            for sql in statements: db.execute(sql)
    @staticmethod
    def password_hash(password,salt): return hashlib.pbkdf2_hmac('sha256',password.encode(),bytes.fromhex(salt),600000).hex()
    @staticmethod
    def validate_name(name):
        if not isinstance(name,str) or not re.fullmatch(r'[A-Za-z0-9_가-힣]{2,16}',name): raise AccountError('닉네임은 한글·영문·숫자·밑줄 2~16자로 입력하세요.')
        return name.casefold()
    @staticmethod
    def validate_password(password):
        if not isinstance(password,str) or not 8<=len(password)<=128: raise AccountError('비밀번호는 8~128자로 입력하세요.')
    def profile(self,user_id,db=None):
        if db is None:
            with self.transaction() as db: return self.profile(user_id,db)
        row=db.execute('SELECT id,name,rating,coins,wins,losses,draws,skin FROM accounts WHERE id=?',(user_id,)).fetchone()
        if row is None: raise AccountError('계정을 찾을 수 없습니다.')
        data=dict(row); data['owned']=[r['skin'] for r in db.execute('SELECT skin FROM inventory WHERE account_id=?',(user_id,)).fetchall()]
        return data
    def register(self,name,password):
        username=self.validate_name(name); self.validate_password(password)
        salt=secrets.token_hex(16); hashed=self.password_hash(password,salt); uid=uuid.uuid4().hex
        with self.transaction() as db:
            if db.execute('SELECT id FROM accounts WHERE username=?',(username,)).fetchone(): raise AccountError('이미 사용 중인 닉네임입니다.')
            try: db.execute('INSERT INTO accounts(id,username,name,salt,password_hash) VALUES(?,?,?,?,?)',(uid,username,name,salt,hashed))
            except Exception as e:
                # A simultaneous registration can win the unique constraint.
                raise AccountError('닉네임을 사용할 수 없습니다.') from e
            db.execute('INSERT INTO inventory(account_id,skin) VALUES(?,?)',(uid,'mint'))
        return self.new_session(uid)
    def login(self,name,password):
        username=self.validate_name(name); self.validate_password(password)
        with self.transaction() as db: row=db.execute('SELECT id,salt,password_hash FROM accounts WHERE username=?',(username,)).fetchone()
        salt=row['salt'] if row else '00'*16
        hashed=self.password_hash(password,salt)
        if row is None or not hmac.compare_digest(hashed,row['password_hash']): raise AccountError('닉네임 또는 비밀번호를 확인하세요.')
        return self.new_session(row['id'])
    def new_session(self,uid):
        token=secrets.token_urlsafe(32)
        with self.transaction() as db:
            db.execute('DELETE FROM sessions WHERE expires<?',(int(time.time()),))
            db.execute('INSERT INTO sessions(token_hash,account_id,expires) VALUES(?,?,?)',(hashlib.sha256(token.encode()).hexdigest(),uid,int(time.time())+7*86400))
            return {'token':token,'profile':self.profile(uid,db)}
    def resume(self,token):
        if not isinstance(token,str) or len(token)>128: raise AccountError('다시 로그인하세요.')
        with self.transaction() as db:
            row=db.execute('SELECT account_id FROM sessions WHERE token_hash=? AND expires>?',(hashlib.sha256(token.encode()).hexdigest(),int(time.time()))).fetchone()
            if row is None: raise AccountError('로그인이 만료되었습니다. 다시 로그인하세요.')
            return self.profile(row['account_id'],db)
    def logout(self,token):
        with self.transaction() as db: db.execute('DELETE FROM sessions WHERE token_hash=?',(hashlib.sha256(token.encode()).hexdigest(),))
    def purchase(self,uid,skin,equip_only=False):
        item=next((x for x in CATALOG if x['id']==skin),None)
        if item is None: raise AccountError('없는 스킨입니다.')
        with self.transaction() as db:
            suffix=' FOR UPDATE' if self.url else ''
            row=db.execute('SELECT coins FROM accounts WHERE id=?'+suffix,(uid,)).fetchone()
            owned=db.execute('SELECT skin FROM inventory WHERE account_id=? AND skin=?',(uid,skin)).fetchone()
            if equip_only and not owned: raise AccountError('먼저 스킨을 구매하세요.')
            if not owned:
                if row['coins']<item['price']: raise AccountError('코인이 부족합니다. 대전에서 보상을 모아보세요.')
                db.execute('UPDATE accounts SET coins=coins-? WHERE id=?',(item['price'],uid))
                db.execute('INSERT INTO inventory(account_id,skin) VALUES(?,?)',(uid,skin))
            db.execute('UPDATE accounts SET skin=? WHERE id=?',(skin,uid))
            return self.profile(uid,db)
    def settle(self,match_id,players,scores,ranked=False,forfeit=None):
        if not self.enabled or len(players)!=2 or not all(players) or players[0]==players[1]: return {}
        with self.transaction() as db:
            # Claim the match before balances are touched. Conflict means already paid.
            claim=db.execute('INSERT INTO settlements(match_id,details) VALUES(?,?) ON CONFLICT(match_id) DO NOTHING',(match_id,'{}'))
            if claim.rowcount==0: return {}
            suffix=' FOR UPDATE' if self.url else ''
            rows=db.execute('SELECT id,rating FROM accounts WHERE id IN (?,?) ORDER BY id'+suffix,tuple(players)).fetchall()
            ratings={r['id']:r['rating'] for r in rows}
            winner=(1-forfeit) if forfeit is not None else (None if scores[0]==scores[1] else (0 if scores[0]>scores[1] else 1))
            expected=1/(1+10**((ratings[players[1]]-ratings[players[0]])/400))
            delta=round(24*((0.5 if winner is None else 1 if winner==0 else 0)-expected)) if ranked else 0
            changes={}
            for i,uid in enumerate(players):
                coins=0 if forfeit is not None else 25 if winner is None else 60 if winner==i else 15
                rating_delta=delta if i==0 else -delta
                rating_delta=max(-ratings[uid],rating_delta)
                db.execute('UPDATE accounts SET rating=rating+?,coins=coins+?,wins=wins+?,losses=losses+?,draws=draws+? WHERE id=?',(rating_delta,coins,int(winner==i),int(winner is not None and winner!=i),int(winner is None),uid))
                changes[uid]={'coins':coins,'rating':rating_delta,'profile':self.profile(uid,db)}
            db.execute('UPDATE settlements SET details=? WHERE match_id=?',(json.dumps(changes),match_id))
            return changes
