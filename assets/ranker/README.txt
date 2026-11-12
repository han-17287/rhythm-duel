PERFECTO / ORIGINAL ENSEMBLE

Four original compositions arranged for sampled piano, acoustic drums, electric
and clean guitar, violin, strings, pizzicato and bass. No melodies or recordings
from other games are used.

r01 PULSE ENGINE — piano fusion, syncopated clean guitar and acoustic kit
r02 FRACTURE — guitar rock, palm-muted power chords and half-time backbeat
r03 IRREGULAR ORBIT — violin, piano, pizzicato and cello in changing meters
r04 EVENT HORIZON — symphonic rock, alternating piano/violin and guitar/drums

Instrument samples: FluidR3 GM, copyright 2000–2002, 2008 Frank Wen and
2008 Toby Smithe. MIT license; complete notice in FluidR3-LICENSE.txt.
Source package: https://deb.debian.org/debian/pool/main/f/fluid-soundfont/
fluid-soundfont-gm_3.1-6_all.deb; extract usr/share/sounds/sf2/FluidR3_GM.sf2.
The original SoundFont is not bundled; only rendered music is served.

Regenerate with libfluidsynth, numpy and ffmpeg installed:
RANKER_SOUNDFONT=/path/to/FluidR3_GM.sf2 python tools/compose_ranker.py

The renderer plays every score attack on an assigned instrument at its exact
chart time; held score notes send note-off at the target release. Backing parts
are separately arranged for each genre. Mixes are stereo 44.1 kHz, mastered to
-16 LUFS / -1.5 dBTP before Vorbis encoding. Song clocks and all 24 playable
charts are unchanged from chart revision 2; audio_revision 3 invalidates the
music cache without resetting earned scores. The existing music preview plays
the new arrangement, and the UI identifies each song's instrument combination.
