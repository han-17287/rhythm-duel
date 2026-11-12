"""Released HARD charts stay immutable while higher tiers add playable challenge."""
import hashlib
import json
import math
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[1]
# Published main 7d9cc6899b41de056ce6b20ef5c55a7d0964c996.
# Fingerprints cover the released HARD notes, tempo/bar grid and duration;
# keeping these stable preserves existing records and first-clear claims.
RELEASED_HARD = {'r01': '557b1ab2739c249bf2477ae2098cd8d607a8f154850dfdbeb52820dd210e9da5', 'r02': 'bfe7b1f0480a0576a4204ac2768a49067a8d163667b8dcb24a03ae38bf10f949', 'r03': 'd555434f46e8fc6909c2d2ade3f79c7cb35d3f3ae9c3543684e998ec435688e8', 'r04': '5bfd228570ef52d6ae9acb1a60c863c4e50d7a803fd913fda656fefdcf96c495'}


def charts(song):
    yield 'hard', song['charts']
    for tier in ('expert', 'inferno'):
        yield tier, song['extras'][tier]


class RankerContent(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.songs = json.loads((ROOT / 'assets/ranker/catalog.json').read_text())

    def test_released_hard_charts_and_timing_are_unchanged(self):
        self.assertEqual({s['id'] for s in self.songs}, set(RELEASED_HARD))
        for song in self.songs:
            released = {key: song[key] for key in ('charts', 'bars', 'duration', 'audio_offset')}
            digest = hashlib.sha256(json.dumps(released, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
            self.assertEqual(digest, RELEASED_HARD[song['id']], song['id'])
            self.assertGreaterEqual(song['duration'] + song['audio_offset'], 180)
            self.assertLessEqual(song['duration'] + song['audio_offset'], 240)

    def test_all_twenty_four_charts_have_playable_lane_geometry(self):
        checked = 0
        for song in self.songs:
            for tier, variants in charts(song):
                for kind, notes in variants.items():
                    checked += 1
                    with self.subTest(song=song['id'], tier=tier, kind=kind):
                        self.assertIn(kind, ('one', 'double'))
                        self.assertGreater(len(notes), 250)
                        self.assertLessEqual(len(notes), 4096)
                        self.assertEqual(notes, sorted(notes, key=lambda n: n['t']))
                        end = [-10.0, -10.0]
                        gap = {'hard': .075, 'expert': .06, 'inferno': .05}[tier]
                        for note in notes:
                            lane = note.get('lane', 0)
                            self.assertIs(type(lane), int)
                            self.assertIn(lane, (0,) if kind == 'one' else (0, 1))
                            self.assertTrue(math.isfinite(note['t']) and math.isfinite(note['d']))
                            self.assertGreaterEqual(note['t'], 0)
                            self.assertGreaterEqual(note['d'], 0)
                            self.assertTrue(note['d'] == 0 or note['d'] >= .3, 'Sub-300ms durations are taps in the game')
                            self.assertLessEqual(note['t'] + note['d'], song['duration'] + .00001)
                            self.assertGreaterEqual(note['t'] - end[lane], gap - .00002)
                            end[lane] = note['t'] + note['d']
                        # Include floating-point timings and hold durations like real replays,
                        # rather than only compact integer authored data.
                        hits = [{**n, 't': n['t'] + .000123456789, 'd': max(n['d'], .014321098765)} for n in notes]
                        packet = json.dumps(dict(type='ranker_result', session='x' * 40, difficulty=tier, hits=hits), separators=(',', ':')).encode()
                        self.assertLessEqual(len(packet), 524288)
        self.assertEqual(checked, 24)

    def test_higher_tiers_add_notes_and_levels_without_changing_song_length(self):
        for song in self.songs:
            levels = song['difficulty_levels']
            self.assertLess(levels['hard'], levels['expert'])
            self.assertLess(levels['expert'], levels['inferno'])
            for kind in ('one', 'double'):
                hard = song['charts'][kind]
                expert = song['extras']['expert'][kind]
                inferno = song['extras']['inferno'][kind]
                self.assertGreater(len(expert), len(hard), (song['id'], kind, 'expert'))
                self.assertGreater(len(inferno), len(expert), (song['id'], kind, 'inferno'))


if __name__ == '__main__':
    unittest.main()
