"""Build a playable Godot Web export; downloads only Web templates via HTTP ranges."""
import io, os, platform, shutil, subprocess, urllib.request, zipfile
from pathlib import Path
VERSION='4.6.3'
ROOT=Path(__file__).resolve().parents[1]
CACHE=ROOT/'.web-build-cache'
BASE=f'https://github.com/godotengine/godot/releases/download/{VERSION}-stable/'
class RemoteZip(io.RawIOBase):
    def __init__(self,url):
        with urllib.request.urlopen(urllib.request.Request(url,method='HEAD'),timeout=90) as r:
            self.url=r.url; self.length=int(r.headers['Content-Length'])
        self.pos=0
    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.pos
    def seek(self,offset,whence=0):
        self.pos=offset if whence==0 else self.pos+offset if whence==1 else self.length+offset
        return self.pos
    def read(self,size=-1):
        if self.pos>=self.length: return b''
        end=self.length-1 if size<0 else min(self.length-1,self.pos+size-1)
        req=urllib.request.Request(self.url,headers={'Range':f'bytes={self.pos}-{end}'})
        with urllib.request.urlopen(req,timeout=120) as r:
            if r.status!=206: raise RuntimeError('Download server did not support partial ZIP downloads')
            data=r.read()
        self.pos+=len(data)
        return data

def main():
    CACHE.mkdir(exist_ok=True)
    (CACHE/'.gdignore').touch()
    assets=ROOT/'assets'; assets.mkdir(exist_ok=True)
    font=assets/'NotoSansKR.ttf'
    if not font.exists():
        print('Downloading Korean font...',flush=True)
        with urllib.request.urlopen('https://raw.githubusercontent.com/google/fonts/main/ofl/notosanskr/NotoSansKR%5Bwght%5D.ttf',timeout=90) as r:
            font.write_bytes(r.read())
        with urllib.request.urlopen('https://raw.githubusercontent.com/google/fonts/main/ofl/notosanskr/OFL.txt',timeout=30) as r:
            (assets/'OFL.txt').write_bytes(r.read())
    godot=os.environ.get('GODOT_BIN') or shutil.which('godot')
    if not godot:
        if platform.machine() not in ('x86_64','AMD64'): raise RuntimeError('Set GODOT_BIN to a Godot 4.6.3 executable')
        binary=CACHE/f'Godot_v{VERSION}-stable_linux.x86_64'
        if not binary.exists():
            print('Downloading Godot editor...',flush=True)
            with urllib.request.urlopen(BASE+binary.name+'.zip',timeout=120) as r:
                with zipfile.ZipFile(io.BytesIO(r.read())) as z: z.extractall(CACHE)
            binary.chmod(0o755)
        godot=str(binary)
    actual=subprocess.check_output([godot,'--version'],text=True).strip()
    if not actual.startswith(VERSION+'.stable'): raise RuntimeError(f'Expected Godot {VERSION}; found {actual}')
    env=os.environ.copy()
    env['XDG_DATA_HOME']=str(CACHE/'data')
    env['XDG_CONFIG_HOME']=str(CACHE/'config')
    env['XDG_CACHE_HOME']=str(CACHE/'cache')
    templates=Path(env['XDG_DATA_HOME'])/'godot/export_templates'/f'{VERSION}.stable'
    templates.mkdir(parents=True,exist_ok=True)
    required=['web_nothreads_release.zip','web_nothreads_debug.zip','version.txt']
    missing=[n for n in required if not (templates/n).exists()]
    if missing:
        print('Downloading Web-only export templates...',flush=True)
        with zipfile.ZipFile(RemoteZip(BASE+f'Godot_v{VERSION}-stable_export_templates.tpz')) as z:
            for name in missing:
                (templates/name).write_bytes(z.read('templates/'+name))
                print('Installed',name,flush=True)
    output=ROOT/'build/web'; output.mkdir(parents=True,exist_ok=True)
    subprocess.run([godot,'--headless','--path',str(ROOT),'--editor','--import','--quit'],env=env,check=True)
    subprocess.run([godot,'--headless','--path',str(ROOT),'--export-release','Web',str(output/'index.html')],env=env,check=True)
    shutil.copyfile(assets/'OFL.txt',output/'OFL.txt')
    if not (output/'index.wasm').is_file(): raise RuntimeError('Web export did not produce WebAssembly')
    with zipfile.ZipFile(ROOT/'build/rhythm-duel-web.zip','w',zipfile.ZIP_DEFLATED) as z:
        for f in output.iterdir():
            if f.is_file(): z.write(f,f.name)
    print('READY: build/web/index.html and build/rhythm-duel-web.zip',flush=True)
if __name__=='__main__': main()
