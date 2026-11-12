"""Original phrase-based rhythm charts and electronic soundtrack (numpy/ffmpeg)."""
import argparse
import json
from pathlib import Path
from ranker_charts import build_arrangement

ROOT = Path(__file__).resolve().parents[1]
SONGS = [
    dict(id='r01',title='PULSE ENGINE',subtitle='가속하는 심장',bpms=[168,192,168,210],level=11,color='68ffe0',root=45,section_bars=40,voice='anthem'),
    dict(id='r02',title='FRACTURE',subtitle='깨진 박자',bpms=[190,220,190,240],level=14,color='ffbd73',root=43,section_bars=40,voice='glitch'),
    dict(id='r03',title='IRREGULAR ORBIT',subtitle='궤도 이탈',bpms=[180,210,240,210],level=17,color='b89aff',root=47,section_bars=44,voice='orbit'),
    dict(id='r04',title='EVENT HORIZON',subtitle='사건의 지평선',bpms=[210,240,260,280],level=20,color='ff719b',root=42,section_bars=48,voice='finale'),
]


def chart(song):
    # Retain the published musical clock; only the arrangement is versioned.
    bars, time = [], 0
    for index in range(song['section_bars'] * 4):
        section = index // song['section_bars']
        bpm = song['bpms'][section]
        beats = (3 if index % 4 == 2 else 5 if index % 4 == 3 else 4) if song['id'] == 'r03' else 4
        bars.append(dict(t=round(time, 5), bpm=bpm, beats=beats, section=section))
        time += beats * 60 / bpm
    data = dict(section_bars=song['section_bars'], bars=bars, duration=round(time + .65, 5),
                audio_offset=round(4 * 60 / song['bpms'][0], 8))
    data.update(build_arrangement(song, bars, data['duration']))
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--charts-only', action='store_true', help='Rebuild charts without synthesizing audio')
    args = parser.parse_args()
    if not args.charts_only:
        from ranker_soundtrack import render
    folder = ROOT / 'assets/ranker'
    folder.mkdir(exist_ok=True)
    catalog = []
    for song in SONGS:
        data = {**song, **chart(song)}
        data['difficulty_levels'] = {tier: song['level'] + offset for tier, offset in [('hard', 0), ('expert', 3), ('inferno', 6)]}
        if not args.charts_only:
            render(song, data, folder / (song['id'] + '.ogg'))
        catalog.append(data)
        print(song['id'], data['duration'], {tier: {kind: len(notes) for kind, notes in variants.items()}
              for tier, variants in [('hard', data['charts']), *data['extras'].items()]}, flush=True)
    (folder / 'catalog.json').write_text(json.dumps(catalog, separators=(',', ':'), ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
