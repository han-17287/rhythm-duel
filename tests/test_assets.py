import asyncio,gzip,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).parents[1]/'server'))
import assets,server
from websockets.http11 import Request
from websockets.datastructures import Headers
class Assets(unittest.IsolatedAsyncioTestCase):
    async def test_revalidation_and_cache_invalidation(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(server,'STATIC_DIR',Path(folder)):
            path=Path(folder)/'index.wasm';path.write_bytes(b'\0asmfirst')
            request=Request('/index.wasm',Headers())
            initial=await server.serve_game(None,request)
            self.assertEqual(initial.status_code,200)
            self.assertEqual(initial.headers['Content-Type'],'application/wasm')
            again=await server.serve_game(None,request)
            self.assertIs(initial.body,again.body)
            cached=await server.serve_game(None,Request('/index.wasm',Headers({'If-None-Match':initial.headers['ETag']})))
            self.assertEqual(cached.status_code,304);self.assertEqual(cached.body,b'')
            path.write_bytes(b'\0asmchanged')
            updated=await server.serve_game(None,Request('/index.wasm',Headers({'If-None-Match':initial.headers['ETag']})))
            self.assertEqual(updated.status_code,200)
            self.assertNotEqual(updated.headers['ETag'],initial.headers['ETag'])
            self.assertEqual(updated.body,b'\0asmchanged')
    async def test_gzip_variant_uses_original_mime(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(server,'STATIC_DIR',Path(folder)):
            path=Path(folder)/'index.wasm';path.write_bytes(b'\0asm'+b'a'*1000)
            path.with_name('index.wasm.gz').write_bytes(gzip.compress(path.read_bytes()))
            plain=await server.serve_game(None,Request('/index.wasm',Headers()))
            compressed=await server.serve_game(None,Request('/index.wasm',Headers({'Accept-Encoding':'gzip, deflate'})))
            self.assertEqual(compressed.headers['Content-Encoding'],'gzip')
            self.assertEqual(compressed.headers['Content-Type'],'application/wasm')
            self.assertEqual(compressed.headers['Vary'],'Accept-Encoding')
            self.assertEqual(gzip.decompress(compressed.body),plain.body)
            self.assertNotEqual(compressed.headers['ETag'],plain.headers['ETag'])
            refused=await server.serve_game(None,Request('/index.wasm',Headers({'Accept-Encoding':'gzip;q=0, *;q=1'})))
            self.assertNotIn('Content-Encoding',refused.headers)
            self.assertFalse(assets.accepts_gzip('gzip;q=bad'))
    async def test_concurrent_reads_and_limit(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'small.bin';path.write_bytes(b'a'*100)
            with patch.object(assets,'cache_limit',200):
                results=await asyncio.gather(*(assets.read_asset(path,path.stat()) for _ in range(20)))
                self.assertTrue(all(x is results[0] for x in results))
                for i in range(3):
                    other=Path(folder)/str(i);other.write_bytes(b'b'*100)
                    await assets.read_asset(other,other.stat())
                self.assertLessEqual(assets.cache_bytes,200)
if __name__=='__main__':unittest.main()
