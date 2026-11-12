"""Revision 2: a musical score, then playable arrangements of that score.

Every attack is authored in an eight-bar call/response phrase. HARD follows the
foreground hook; the other tiers add its answering voice and short ornaments.
No tier manufactures a continuous subdivision stream independently of the music.
"""

TIERS = ('hard', 'expert', 'inferno')
GAPS = (.075, .060, .050)

# Four recognisable rhythmic cells, each with a question and an answer. Values
# are beats, not seconds, so the same hook survives tempo/section changes.
CELLS = (
    ([0, .5, 1.5, 2, 3, 3.5], [0, .75, 1.5, 2, 2.75, 3.5]),
    ([0, .75, 1.25, 2, 2.5, 3.25], [0, .5, 1.25, 1.75, 2.75, 3.5]),
    ([0, .5, 1, 2, 2.75, 3.5], [0, .75, 1.5, 2.5, 3, 3.5]),
    ([0, .5, 1.25, 2, 2.75, 3.25], [0, .75, 1.25, 2.25, 3, 3.5]),
)
MELODIES = (
    (0, 2, 4, 5, 4, 2, 1, 0),
    (0, 1, 4, 2, 5, 4, 2, 1),
    (0, 2, 5, 4, 2, 6, 4, 2),
    (0, 4, 3, 2, 6, 5, 4, 1),
)
PHRASE_NAMES = ('OFFBEAT SIGNAL', 'TRIPLET TURN', 'HOLD THE LINE', 'CROSS CURRENT')
TECHNIQUES = ('엇박 · 반복과 대답 · 쉼표', '셋잇단 · 짧은 연타 · 쉼표',
              '홀드와 떼기 · 엇박 대답', '교대 · 엇박 · 짧은 연타')


def _fits(note, accepted, gap):
    """Check both neighbours: ornaments cannot displace a future hook."""
    lane = note.get('lane', 0)
    start, end = note['t'], note['t'] + note['d']
    for other in accepted:
        if other.get('lane', 0) != lane:
            continue
        if start < other['t']:
            if other['t'] - end < gap - .00002:
                return False
        elif start - (other['t'] + other['d']) < gap - .00002:
            return False
    return True


def _bar_events(song, bar, index):
    beat, beats = 60 / bar['bpm'], bar['beats']
    local, section = index % song['section_bars'], bar['section']
    pos, phrase = local % 8, local // 8
    cell_index = (int(song['id'][1:]) - 1 + phrase + section) % 4
    cell = CELLS[cell_index][int(pos in (1, 3, 5, 7))]
    melody = MELODIES[(cell_index + int(song['id'][1:]) - 1) % 4]
    calm = section == 2 and local < 8
    intro = section == 0 and local < 4
    offsets = [v for v in cell if v < beats - .1]
    if beats == 5:
        offsets += [4, 4.5]
    # Bars 1/3 and 2/4 restate the theme; the next four bars answer it.
    if pos in (2, 6) and not intro and not calm:
        unit = 1 / 3 if beat / 3 >= GAPS[0] else .4
        offsets = [0, unit, 2 * unit, 1.5, 2, 2 + unit, 2 + 2 * unit, 3.5]
        offsets = [v for v in offsets if v < beats - .1]
        if beats == 5:
            offsets += [4, 4.5]
    hold_at, hold_beats = None, 0
    if pos == 3 or calm and pos % 2 == 0:
        hold_at = max(1.0, beats - 2.0)
        offsets = [v for v in offsets if v < hold_at - .25] + [hold_at]
        hold_beats = 1.5
    if intro:
        offsets = [0, 1.5, 2.5] if beats >= 4 else [0, 1.5]
        hold_at = None
    if calm:
        offsets = [0, 1.5] if hold_at is None else [0, hold_at]
    # A phrase ends with a real breath in EVERY tier, including INFERNO.
    if pos == 7:
        offsets = [v for v in offsets if v < beats - 1.0]
        hold_at = None
    events = []
    owner = (phrase + section) % 2

    def event(at, tier, voice, degree, duration=0, hand=None, accent=False):
        if not 0 <= at < beats - .00001:
            return
        if pos == 7 and at >= beats - 1.0:
            return
        events.append(dict(t=round(bar['t'] + at * beat, 5),
                           d=round(duration * beat, 5), tier=tier, voice=voice,
                           degree=degree, hand=owner if hand is None else hand,
                           accent=accent))

    for j, at in enumerate(offsets):
        duration = hold_beats if at == hold_at else 0
        # Repeated two-note hand groups, alternation and anchored holds are
        # deliberate Double patterns, not arbitrary lane noise.
        hand = owner if duration else (owner + (j // 2 if cell_index in (1, 3) else j)) % 2
        degree = melody[j % len(melody)]
        if pos >= 4 and pos != 7:
            degree = melody[(j + 2) % len(melody)]
        event(at, 0, 'lead', degree, duration, hand, j == 0 or at == 2)

    if intro or calm:
        if calm and hold_at is not None:
            for j, at in enumerate([hold_at + .5, hold_at + 1]):
                event(at, 1, 'reply', melody[(j + 3) % 8], hand=1-owner)
        return events

    # A short, audible second melodic line. Silence is retained around it
    # instead of filling every empty point of a 16th-note grid.
    reply = {
        0: [.75, 2.5], 1: [1.0, 2.25, 3.75],
        2: [1, 3], 3: [hold_at + .5, hold_at + 1] if hold_at is not None else [1, 2.5],
        4: [.75, 2.5, 3.75], 5: [1, 2.25, 3.75],
        6: [1, 3], 7: [.75, 1.75],
    }[pos]
    for j, at in enumerate(reply):
        event(at, 1, 'reply', melody[(j + 4) % 8], hand=1-owner,
              accent=j == 0 and pos in (1, 5))

    # Compact pickup/turn figures: at most three attacks, then a longer gap.
    ornaments = {
        0: [.25, 1.75], 1: [2.75, 3], 2: [1.25, 3.25],
        3: [hold_at + .75, hold_at + 1.25] if hold_at is not None else [2.75],
        4: [.25, 1.75, 2.75], 5: [.25, 2.75, 3],
        6: [1.25, 3.25, 3.75], 7: [.25, 1.25],
    }[pos]
    for j, at in enumerate(ornaments):
        event(at, 2, 'spark', melody[(j + 6) % 8], hand=(owner + j + 1) % 2)

    # Double downbeat chords are a second pitched voice, not silent duplicates.
    if pos in (0, 4):
        event(0, 0, 'chord', melody[0] + 2, hand=1-events[0]['hand'], accent=True)
    return events


def build_arrangement(song, bars, duration):
    score, phrases = [], []
    for index, bar in enumerate(bars):
        score.extend(_bar_events(song, bar, index))
        local = index % song['section_bars']
        if local % 8 == 0:
            remaining = song['section_bars'] - local
            end_index = min(len(bars), index + min(8, remaining))
            cell = (int(song['id'][1:]) - 1 + local // 8 + bar['section']) % 4
            label, technique = PHRASE_NAMES[cell], TECHNIQUES[cell]
            if cell == 1 and 60 / bar['bpm'] / 3 < GAPS[0]:
                label, technique = 'QUINTUPLET TURN', '5연음 · 짧은 연타 · 쉼표'
            if bar['section'] == 0 and local == 0:
                label, technique = 'FIND THE PULSE', '기본 리듬을 듣고 익히기'
            elif bar['section'] == 2 and local == 0:
                label, technique = 'BREATHE / REBUILD', '쉬는 박자 · 홀드 · 다시 가속'
            elif bar['section'] == 3 and local == 0:
                label = 'FINAL / ' + label
            phrases.append(dict(t=bar['t'], end=bars[end_index]['t'] if end_index < len(bars) else duration,
                                label=label, technique=technique, section=bar['section']))

    # Higher layers fit around the complete hook, preserving recurring motifs.
    all_charts = {}
    score_by_time = sorted(score, key=lambda e: (e['t'], e['tier'], e['voice']))
    for tier, gap in enumerate(GAPS):
        variants = {}
        for kind in ('one', 'double'):
            accepted = []
            for layer in range(tier + 1):
                for source in score_by_time:
                    if source['tier'] != layer or kind == 'one' and source['voice'] == 'chord':
                        continue
                    note = {'t': source['t'], 'd': source['d']}
                    if kind == 'double':
                        note['lane'] = source['hand']
                    if _fits(note, accepted, gap):
                        accepted.append(note)
            accepted.sort(key=lambda n: (n['t'], n.get('lane', 0)))
            if not 250 < len(accepted) <= 3900:
                raise ValueError(f'Invalid chart size: {song["id"]} {TIERS[tier]} {kind} {len(accepted)}')
            variants[kind] = accepted
        all_charts[TIERS[tier]] = variants
    # The sound score excludes ornament attacks that no arrangement can play.
    used = {(n['t'], n['d']) for variants in all_charts.values() for notes in variants.values() for n in notes}
    score = [e for e in score_by_time if (e['t'], e['d']) in used]
    return dict(revision=2, score=score, phrases=phrases, charts=all_charts['hard'],
                extras={tier: all_charts[tier] for tier in ('expert', 'inferno')})


def build_extras(song, base):
    """Compatibility entry point for scripts importing the previous API."""
    return build_arrangement(song, base['bars'], base['duration'])['extras']
