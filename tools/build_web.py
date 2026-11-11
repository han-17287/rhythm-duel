"""Build a playable Godot Web export; downloads only Web templates via HTTP ranges."""
import gzip, io, os, platform, shutil, subprocess, urllib.request, zipfile
from pathlib import Path
from web_gl import patch as patch_web_gl
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
    env=os.environ.copy()
    env['XDG_DATA_HOME']=str(CACHE/'data')
    env['XDG_CONFIG_HOME']=str(CACHE/'config')
    env['XDG_CACHE_HOME']=str(CACHE/'cache')
    for key in ['XDG_DATA_HOME','XDG_CONFIG_HOME','XDG_CACHE_HOME']:
        Path(env[key]).mkdir(parents=True,exist_ok=True)
    actual=subprocess.check_output([godot,'--version'],text=True,env=env).strip()
    if not actual.startswith(VERSION+'.stable'): raise RuntimeError(f'Expected Godot {VERSION}; found {actual}')
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
    (ROOT/'build/.gdignore').touch()
    subprocess.run([godot,'--headless','--path',str(ROOT),'--editor','--import','--quit'],env=env,check=True)
    subprocess.run([godot,'--headless','--path',str(ROOT),'--export-release','Web',str(output/'index.html')],env=env,check=True)
    patch_web_gl(output/'index.js')
    shutil.copyfile(assets/'OFL.txt',output/'OFL.txt')
    if (assets/'ui/Oxanium-OFL.txt').exists(): shutil.copyfile(assets/'ui/Oxanium-OFL.txt',output/'Oxanium-OFL.txt')
    html=output/'index.html'
    shell=html.read_text()
    shell=shell.replace('<html lang="en">','<html lang="ko">')
    shell=shell.replace('<canvas id="canvas">','<canvas id="canvas" aria-label="PERFECTO 리듬 대전 게임">')
    shell=shell.replace('</head>', '''<meta name="description" content="내가 만든 여덟 개의 비트로 친구와 겨루는 온라인 리듬 대전, PERFECTO.">
<meta name="theme-color" content="#121122">
<style>
body,#status{background:#121122}
#status-splash{max-width:min(640px,92vw);max-height:70vh}
#status-progress{position:absolute;bottom:14%;width:min(360px,70vw);height:6px;border:0;border-radius:8px;overflow:hidden;background:#342b48;accent-color:#6fffe0}
#status-progress::-webkit-progress-bar{background:#342b48;border-radius:8px}
#status-progress::-webkit-progress-value{background:linear-gradient(90deg,#a78bfa,#6fffe0);border-radius:8px}
#status-progress::-moz-progress-bar{background:#6fffe0}
#loading-caption{position:absolute;bottom:19%;color:#c4b9da;text-align:center;font:14px sans-serif;line-height:1.8}
#loading-caption small{color:#8d829f;font-size:12px}
#portrait-hint{display:none}
@media(max-width:700px) and (orientation:portrait){#portrait-hint{display:block;position:fixed;left:16px;right:16px;top:16px;padding:14px;border-radius:16px;background:#29213e;color:#dffef6;border:1px solid #695389;font:15px sans-serif;text-align:center;z-index:999;pointer-events:none}}
</style></head>''')
    shell=shell.replace('<progress id="status-progress">','<div id="loading-caption">비트를 준비하는 중…<br><small>첫 접속은 파일을 내려받는 데 시간이 걸릴 수 있어요.</small></div><progress id="status-progress">')
    shell=shell.replace("statusNotice.style.display = mode === 'notice' ? 'block' : 'none';", "statusNotice.style.display = mode === 'notice' ? 'block' : 'none';\n        document.getElementById('loading-caption').style.display = mode === 'notice' ? 'none' : 'block';")
    shell=shell.replace('</body>','<div id="portrait-hint">가로로 돌리면 더 편하게 플레이할 수 있어요.</div></body>')
    html.write_text(shell)
    if not (output/'index.wasm').is_file(): raise RuntimeError('Web export did not produce WebAssembly')
    for asset in output.iterdir():
        if asset.suffix in ('.wasm','.pck','.js'):
            asset.with_name(asset.name+'.gz').write_bytes(gzip.compress(asset.read_bytes(),compresslevel=6,mtime=0))
    output.chmod(0o755)
    for asset in output.iterdir():
        if asset.is_file(): asset.chmod(0o644)
    with zipfile.ZipFile(ROOT/'build/rhythm-duel-web.zip','w',zipfile.ZIP_DEFLATED) as z:
        for f in output.iterdir():
            if f.is_file() and f.suffix!='.gz': z.write(f,f.name)
    print('READY: build/web/index.html and build/rhythm-duel-web.zip',flush=True)
if __name__=='__main__': main()
