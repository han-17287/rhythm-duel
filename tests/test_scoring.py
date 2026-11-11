import math,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parents[1]/'server'))
from scoring import analyze
NOTES=[{'t':i*.5,'d':0} for i in range(8)]
class Analysis(unittest.TestCase):
    def test_report_and_boundaries(self):
        r=analyze(NOTES,NOTES)
        self.assertEqual(r['points'],8000);self.assertEqual(r['max_combo'],8)
        self.assertTrue(r['all_perfect']);self.assertEqual(r['grade'],'S')
        self.assertEqual(r['counts'],[8,0,0,0])
        for error,j in [(0.035,0),(0.08,1),(0.18,2),(0.181,3)]:
            self.assertEqual(analyze([NOTES[0]],[{'t':error,'d':0}])['judgments'],[j])
    def test_extra_input_breaks_combo(self):
        hits=NOTES+[{'t':1.75,'d':0}]
        r=analyze(NOTES,hits)
        self.assertEqual(r['extra'],1);self.assertEqual(r['points'],7800)
        self.assertFalse(r['full_combo']);self.assertEqual(r['max_combo'],4)
    def test_early_press_and_hold_release(self):
        self.assertEqual(analyze([{'t':0,'d':0}],[{'t':-.03,'d':.06}])['points'],1000)
        r=analyze([{'t':0,'d':2}],[{'t':-.03,'d':2.03}])
        self.assertEqual(r['points'],2000);self.assertEqual(r['offsets'],[-30.0])
        self.assertEqual(analyze([{'t':0,'d':2}],[{'t':0,'d':.5}])['points'],0)
        self.assertEqual(analyze([{'t':0,'d':2}],[{'t':0,'d':.5}])['offsets'],[-1500.0])
    def test_malformed_hits(self):
        for hit in [{'t':float('nan'),'d':0},{'t':0,'d':float('inf')},{'t':0,'d':-1},{'t':99999,'d':0},None]:
            with self.assertRaises((ValueError,TypeError)):analyze(NOTES,[hit])
    def test_empty_is_not_full_combo(self):
        r=analyze([],[])
        self.assertEqual(r['accuracy'],0);self.assertFalse(r['full_combo']);self.assertEqual(r['max_combo'],0)
if __name__=='__main__':unittest.main()
