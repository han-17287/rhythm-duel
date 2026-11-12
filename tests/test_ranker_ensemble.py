"""Audible foreground contracts for the sampled ensemble arrangements."""
import json
import sys
import unittest
from pathlib import Path
ROOT=Path(__file__).parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from ranker_soundtrack import arrange,PROFILES

class Ensemble(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.songs=json.loads((ROOT/'assets/ranker/catalog.json').read_text())
    def test_all_playable_notes_trigger_a_foreground_instrument(self):
        for song in self.songs:
            performance=arrange(song,song)
            lead=[n for n in performance if n['source']=='score']
            self.assertEqual(sorted(n['score_index'] for n in lead),list(range(len(song['score']))))
            audible={n['t'] for n in lead}
            for variants in [song['charts'],*song['extras'].values()]:
                for notes in variants.values():self.assertLessEqual({n['t'] for n in notes},audible)
            for n in lead:
                source=song['score'][n['score_index']]
                self.assertEqual(n['t'],source['t'])
                if source['d']>=.3:self.assertAlmostEqual(n['d'],source['d'],places=4)
                self.assertGreaterEqual(n['velocity'],55)
                self.assertIn(n['ch'],(0,1,2,3,5))
    def test_four_distinct_instrument_and_groove_identities(self):
        self.assertEqual(len({p['genre'] for p in PROFILES.values()}),4)
        self.assertEqual(len({tuple(p['programs']) for p in PROFILES.values()}),4)
        self.assertEqual(len({tuple(p['motif']) for p in PROFILES.values()}),4)
        self.assertEqual(len({p['drums'] for p in PROFILES.values()}),4)
        for song in self.songs:
            events=arrange(song,song)
            self.assertEqual({n['ch'] for n in events},set(range(len(PROFILES[song['id']]['programs'])))|{9})
            self.assertGreater(sum(n['ch']==9 and n['t']>=0 for n in events),200)
            self.assertEqual(song['genre'],PROFILES[song['id']]['genre'])
            self.assertEqual(song['audio_revision'],3)
            self.assertEqual(song['revision'],2,'Instrument-only remix keeps chart record identity')
    def test_score_bounds_and_countin(self):
        for song in self.songs:
            events=arrange(song,song)
            self.assertEqual(len([n for n in events if n['t']<0]),4)
            for n in events:
                self.assertGreaterEqual(n['t'],-song['audio_offset']-.00001)
                self.assertLessEqual(n['t']+n['d'],song['duration']+.00002)
                self.assertTrue(0<n['velocity']<=120)
                self.assertTrue(21<=n['midi']<=108)
            self.assertEqual(events,arrange(song,song),'Composition is deterministic')

if __name__=='__main__':unittest.main()
