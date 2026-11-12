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
        self.assert_reports_match(cases)

    @unittest.skipUnless(shutil.which('godot'),'Godot runtime required for cross-language parity')
    def test_ranker_tier_boundaries_holds_and_dense_matching(self):
        rng=random.Random(1802045);cases=[]
        for windows in [(.022,.05,.1),(.020,.045,.09),(.018,.04,.08)]:
            def append(notes,hits):
                cases.append(dict(notes=notes,hits=hits,windows=windows,chronological=True,extra_penalty=600,report=analyze(notes,hits,windows=windows,chronological=True,extra_penalty=600)))
            # The existing one-microsecond tolerance is part of the scoring contract.
            # Check either side of every threshold with both early and late input.
            for threshold in windows:
                for delta in [-.000002,-.000001,0,.000001,.000002]:
                    for sign in (-1,1):
                        error=sign*(threshold+delta)
                        append([{'t':0,'d':0}],[{'t':error,'d':.012}])
                        append([{'t':0,'d':.5}],[{'t':0,'d':.5+error}])
            # These are deliberately dense enough for chronological assignment to
            # differ from the legacy nearest-unused-note rule, including lane ties.
            append([{'t':0,'d':0},{'t':.05,'d':0}],[{'t':-.03,'d':.012},{'t':.02,'d':.012}])
            append([{'t':0,'d':0,'lane':0},{'t':0,'d':0,'lane':1},{'t':.05,'d':0,'lane':0}],
                   [{'t':0,'d':.012,'lane':1},{'t':-.01,'d':.012,'lane':0},{'t':.04,'d':.012,'lane':0}])
            append([{'t':0,'d':.4,'lane':0},{'t':.05,'d':0,'lane':1},{'t':.1,'d':0,'lane':1}],
                   [{'t':.001,'d':.399,'lane':0},{'t':.05,'d':.012,'lane':1},{'t':.1,'d':.012,'lane':1}])
            for _ in range(40):
                notes=[];hits=[];time=0
                for index in range(rng.randrange(5,16)):
                    lane=index%2;duration=rng.choice([0,0,0,.4])
                    notes.append(dict(t=time,d=duration,lane=lane))
                    if rng.random()<.9:
                        error=rng.choice([0,*windows,*[-w for w in windows],rng.uniform(-.11,.11)])
                        hits.append(dict(t=time+error,d=max(.012,duration+rng.choice([0,0,.025,-.025])),lane=lane if rng.random()<.9 else 1-lane))
                    time+=duration+rng.choice([.05,.075,.125,1/6])
                for _ in range(rng.randrange(3)):
                    hits.append(dict(t=rng.uniform(-.05,time),d=.012,lane=rng.randrange(2)))
                rng.shuffle(hits);append(notes,hits)
        self.assertEqual(len(cases),309)
        self.assert_reports_match(cases)

    def assert_reports_match(self,cases):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'cases.json';path.write_text(json.dumps(cases))
            env=os.environ.copy();env['SCORING_FIXTURES']=str(path)
            for key,suffix in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:env[key]=str(Path(folder)/suffix)
            try:
                p=subprocess.run(['godot','--headless','--path',str(ROOT),'--script','res://tests/scoring_parity.gd'],env=env,capture_output=True,text=True,timeout=10)
            except subprocess.TimeoutExpired as error:
                self.fail(str(error.stdout)+str(error.stderr))
            self.assertIn('SCORING_PARITY_OK',p.stdout,p.stdout+p.stderr)
            self.assertNotIn('SCRIPT ERROR',p.stderr)
if __name__=='__main__':unittest.main()
