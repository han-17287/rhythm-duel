import json,os,random,shutil,subprocess,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).parents[1]
sys.path.insert(0,str(ROOT/'server'))
from scoring import analyze
class Parity(unittest.TestCase):
    @unittest.skipUnless(shutil.which('godot'),'Godot runtime required for cross-language parity')
    def test_generated_parity(self):
        rng=random.Random(4711);cases=[]
        for _ in range(400):
            notes=[];hits=[];t=0;budget=8
            while budget:
                d=rng.choice([0,0,0,1,2] if budget>=2 else [0,1]);budget-=max(1,d)
                note={'t':round(t,4),'d':d};notes.append(note)
                if rng.random()<.9:
                    error=rng.choice([0,.035,.08,.18,-.035,-.08,-.18,rng.uniform(-.25,.25)])
                    hits.append({'t':note['t']+error,'d':max(0,d+rng.choice([0,0,.1,-.2]))})
                t+=d+rng.choice([.125,.25,.5,.75])
            for _ in range(rng.randrange(4)):hits.append({'t':rng.uniform(-.2,t+.5),'d':0})
            rng.shuffle(hits)
            cases.append({'notes':notes,'hits':hits,'report':analyze(notes,hits)})
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'cases.json';path.write_text(json.dumps(cases))
            env=os.environ.copy();env['SCORING_FIXTURES']=str(path)
            for key,suffix in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:env[key]=str(Path(folder)/suffix)
            try:
                p=subprocess.run(['godot','--headless','--path',str(ROOT),'--script','res://tests/scoring_parity.gd'],env=env,capture_output=True,text=True,timeout=6)
            except subprocess.TimeoutExpired as error:
                self.fail(str(error.stdout)+str(error.stderr))
            self.assertIn('SCORING_PARITY_OK',p.stdout,p.stdout+p.stderr)
            self.assertNotIn('SCRIPT ERROR',p.stderr)
if __name__=='__main__':unittest.main()
