"""Keep server account tables out of anonymous PostgreSQL auto-generated APIs."""
import sqlite3
import sys
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).parents[1]/'server'))
from accounts import Store

PRIVATE_TABLES={'accounts','inventory','sessions','settlements','ranker_bests'}


class AccountVisibility(unittest.TestCase):
    def test_postgres_initialization_enables_default_deny_for_all_server_tables(self):
        statements=[]
        class RecordingDB:
            def execute(self,sql,args=()):statements.append(sql)
        @contextmanager
        def transaction():yield RecordingDB()
        store=Store.__new__(Store)
        store.url='postgresql://unit-fixture';store.path=None;store.enabled=True
        with patch.object(store,'transaction',transaction):store.initialize()
        create=[sql for sql in statements if sql.startswith('CREATE TABLE')]
        rls=[sql for sql in statements if 'ROW LEVEL SECURITY' in sql]
        self.assertEqual(len(create),5)
        self.assertEqual(set(rls),{f'ALTER TABLE {table} ENABLE ROW LEVEL SECURITY' for table in PRIVATE_TABLES})
        self.assertTrue(all(statements.index(sql)>statements.index(create[-1]) for sql in rls))
        self.assertFalse(any('CREATE POLICY' in sql for sql in statements),'No browser/anonymous access policy is installed')
        self.assertFalse(any('FORCE ROW LEVEL SECURITY' in sql for sql in statements),'The server table owner must retain normal backend access')

    def test_sqlite_uses_no_postgres_rls_and_keeps_real_account_persistence(self):
        statements=[];connect=sqlite3.connect
        def trace_connect(*args,**kwargs):
            db=connect(*args,**kwargs);db.set_trace_callback(statements.append);return db
        with tempfile.TemporaryDirectory() as folder,patch('accounts.sqlite3.connect',side_effect=trace_connect):
            path=str(Path(folder)/'visibility.db')
            store=Store(path=path)
            created=store.register('visibility_user','local-fixture-password')
            restored=Store(path=path).login('visibility_user','local-fixture-password')
            self.assertEqual(created['profile']['id'],restored['profile']['id'])
        self.assertFalse(any('ROW LEVEL SECURITY' in sql for sql in statements))


if __name__=='__main__':unittest.main()
