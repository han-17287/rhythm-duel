"""Musical score/arrangement contracts, physical playability and revised records."""
import hashlib
import json
import math
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[1]
# Revision 2 changes the arrangements, but keeps the published musical clock.
RELEASED_CLOCK = {
    'r01': '1b58b65de8dc7b963f3cecba51ee58c71f84a24893c15a42edf00c1028a25fe0',
    'r02': '9f49f63f324571c468a3dc336953ad5bd1fc0a9858affecde8e48a10f275fc79',
    'r03': '3871373d8954c060abce496f50372a7a9304069e71685ad9c33e234ee1f75cfe',
    'r04': 'be0f0dfb18731434319d12c02e678f5e8fc07b53a5048d3873ef1418f779d2e6',
}


def charts(song):
    yield 'hard', song['charts']
    for tier in ('expert', 'inferno'):
        yield tier, song['extras'][tier]


def uniform_run(notes):
    times = sorted(set(n['t'] for n in notes))
    best = run = 0
    previous = -1
    for a, b in zip(times, times[1:]):
        gap = b - a
        run = run + 1 if abs(gap - previous) < .002 else 1
        best = max(best, run)
        previous = gap
    return best + 1


class RankerContent(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.songs = json.loads((ROOT / 'assets/ranker/catalog.json').read_text())

    def test_revision_changes_arrangement_without_drifting_song_clock(self):
        self.assertEqual({s['id'] for s in self.songs}, set(RELEASED_CLOCK))
        for song in self.songs:
            self.assertEqual(song['revision'], 2)
            released = {key: song[key] for key in ('bars', 'duration', 'audio_offset')}
            digest = hashlib.sha256(json.dumps(released, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
            self.assertEqual(digest, RELEASED_CLOCK[song['id']], song['id'])
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
                        self.assertLessEqual(len(notes), 3900)
                        self.assertEqual(notes, sorted(notes, key=lambda n: n['t']))
                        end = [-10.0, -10.0]
                        gap = {'hard': .075, 'expert': .06, 'inferno': .05}[tier]
                        for note in notes:
                            lane = note.get('lane', 0)
                            self.assertIs(type(lane), int)
                            self.assertIn(lane, (0,) if kind == 'one' else (0, 1))
                            self.assertTrue(math.isfinite(note['t']) and math.isfinite(note['d']))
                            self.assertGreaterEqual(note['t'], 0)
                            self.assertTrue(note['d'] == 0 or note['d'] >= .3, 'Short durations are taps, not holds')
                            self.assertLessEqual(note['t'] + note['d'], song['duration'] + .00001)
                            self.assertGreaterEqual(note['t'] - end[lane], gap - .00002)
                            end[lane] = note['t'] + note['d']
                        hits = [{**n, 't': n['t'] + .000123456789, 'd': max(n['d'], .014321098765)} for n in notes]
                        packet = json.dumps(dict(type='ranker_result', session='x' * 40, difficulty=tier, revision=2, hits=hits), separators=(',', ':')).encode()
                        self.assertLessEqual(len(packet), 524288)
        self.assertEqual(checked, 24)

    def test_each_playable_attack_and_release_exists_in_the_audible_score(self):
        for song in self.songs:
            score = {(n['t'], n['d']) for n in song['score']}
            audible = set()
            for _, variants in charts(song):
                for notes in variants.values():
                    chart = {(n['t'], n['d']) for n in notes}
                    self.assertLessEqual(chart, score, song['id'])
                    audible.update(chart)
            self.assertEqual(score, audible, 'No impossible ornamental union in the music')
            self.assertEqual({n['voice'] for n in song['score']}, {'lead', 'reply', 'spark', 'chord'})

    def test_higher_tiers_keep_the_hook_and_add_distinct_answering_parts(self):
        for song in self.songs:
            levels = song['difficulty_levels']
            self.assertLess(levels['hard'], levels['expert'])
            self.assertLess(levels['expert'], levels['inferno'])
            for kind in ('one', 'double'):
                previous = None
                for _, variants in charts(song):
                    notes = {(n['t'], n['d'], n.get('lane', 0)) for n in variants[kind]}
                    if previous is not None:
                        self.assertLessEqual(previous, notes, 'The recurring hook must not disappear at a higher tier')
                        self.assertGreater(len(notes - previous), 100)
                    previous = notes

    def test_phrases_cover_the_song_and_leave_an_audible_breath(self):
        for song in self.songs:
            phrases = song['phrases']
            self.assertEqual(phrases[0]['t'], 0)
            self.assertEqual(phrases[-1]['end'], song['duration'])
            for a, b in zip(phrases, phrases[1:]):
                self.assertEqual(a['end'], b['t'])
            for phrase in phrases:
                self.assertTrue(phrase['label'] and phrase['technique'])
                self.assertGreater(phrase['end'], phrase['t'])
                self.assertIn(phrase['section'], range(4))
            # The final beat of every complete eight-bar phrase is an authored
            # rest in all tiers, and the renderer also drops its drum attacks.
            for index, bar in enumerate(song['bars']):
                if index % song['section_bars'] % 8 != 7:
                    continue
                rest = bar['t'] + (bar['beats'] - 1) * 60 / bar['bpm']
                end = bar['t'] + bar['beats'] * 60 / bar['bpm']
                self.assertFalse(any(rest - .00002 <= n['t'] < end - .00002 for n in song['score']))

    def test_challenge_is_bounded_rhythmic_figures_not_continuous_mashing(self):
        for song in self.songs:
            for tier, variants in charts(song):
                for kind, notes in variants.items():
                    with self.subTest(song=song['id'], tier=tier, kind=kind):
                        self.assertLessEqual(uniform_run(notes), 12)
                        self.assertGreaterEqual(sum(n['d'] >= .3 for n in notes), 20)
                        times = sorted(set(n['t'] for n in notes))
                        intervals = {round(b - a, 3) for a, b in zip(times, times[1:])}
                        self.assertGreaterEqual(len(intervals), 10)

    def test_blind_constant_subdivision_cannot_clear_the_real_phrases(self):
        import sys
        sys.path.insert(0, str(ROOT / 'server'))
        from scoring import analyze
        for song in self.songs:
            start = song['bars'][8]['t']
            end = song['bars'][16]['t']
            step = 60 / song['bars'][8]['bpm'] / 4
            hits = [{'t': start + i * step, 'd': .012} for i in range(round((end-start)/step))]
            for tier, variants in charts(song):
                notes = [n for n in variants['one'] if start <= n['t'] < end]
                report = analyze(notes, hits, windows=(.022, .05, .1), max_hits=4096,
                                 chronological=True, max_time=241, extra_penalty=600)
                self.assertLess(report['accuracy'], 75, (song['id'], tier))
                self.assertFalse(report['full_combo'])


if __name__ == '__main__':
    unittest.main()
