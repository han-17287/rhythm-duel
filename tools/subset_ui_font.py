"""Build the bundled Korean UI font from the OFL Noto Sans KR source.

Developer tool only: pip install fonttools brotli; pass the original variable TTF.
Keeps every modern Hangul syllable and common UI symbols, rather than only
characters currently appearing in the game, so player nicknames remain legible.
"""
import argparse
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    destination = Path(__file__).resolve().parents[1] / 'assets' / 'PerfectoUI.woff2'
    font = TTFont(args.source, recalcTimestamp=False)
    options = subset.Options()
    options.name_IDs = ['*']
    options.name_legacy = True
    options.name_languages = ['*']
    options.notdef_glyph = True
    options.recommended_glyphs = True
    subsetter = subset.Subsetter(options=options)
    ranges = [(0x20, 0x024F), (0x1100, 0x11FF), (0x2000, 0x2BFF),
              (0x3000, 0x303F), (0x3130, 0x318F), (0xA960, 0xA97F),
              (0xAC00, 0xD7AF), (0xD7B0, 0xD7FF), (0xFF00, 0xFFEF)]
    subsetter.populate(unicodes={code for start, end in ranges for code in range(start, end + 1)})
    subsetter.subset(font)
    # Modified fonts use a distinct family name under the OFL reserved-name rule.
    replacements = {1: 'PERFECTO UI', 3: 'PERFECTO UI 1.0', 4: 'PERFECTO UI',
                    6: 'PerfectoUI', 16: 'PERFECTO UI', 21: 'PERFECTO UI',
                    25: 'PerfectoUI'}
    for record in font['name'].names:
        if record.nameID in replacements:
            record.string = replacements[record.nameID].encode(record.getEncoding())
    font.flavor = "woff2"
    font.save(destination)
    print(f'{destination.name}: {destination.stat().st_size:,} bytes')


if __name__ == '__main__':
    main()
