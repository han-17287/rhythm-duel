"""Original electronic Ranker soundtrack synthesis (developer regeneration only).

All instruments, motifs and effects are generated here.  Chart timestamps and
bar boundaries remain the single musical clock; no external samples are used.
"""
import math
import subprocess
import tempfile
import wave
from pathlib import Path
import numpy as np

RATE = 22050


def render(song, data, path):
    """Render the shared authored score on its canonical musical clock."""
    preroll = data['audio_offset']
    duration = data['duration'] + preroll
    mix = np.zeros((math.ceil(duration * RATE), 2), dtype=np.float64)
    rng = np.random.default_rng(8172 + int(song['id'][1:]))
    root, voice = song['root'], song['voice']

    def add(at, sound, gain, pan=0):
        start = round((at + preroll) * RATE)
        if start < 0:
            return
        n = min(len(sound), len(mix) - start)
        pan = max(-1, min(1, pan))
        if n > 0:
            mix[start:start+n, 0] += sound[:n] * gain * math.sqrt((1-pan)/2)
            mix[start:start+n, 1] += sound[:n] * gain * math.sqrt((1+pan)/2)

    def pump(sound, beat, depth=.5):
        """Beat-aligned sidechain shape, leaving space for the kick transient."""
        phase = (np.arange(len(sound)) / RATE) % beat
        # Fade into the next duck just before the beat to avoid a gain step.
        duck = np.minimum(1, np.exp(-phase/(beat*.15))+np.exp(-(beat-phase)/.003))
        return sound * (1-depth*duck)

    def tone(midi, length, kind='lead', bright=1):
        t = np.arange(max(1, round(length*RATE))) / RATE
        f = 440 * 2**((midi-69)/12)
        release = np.minimum(np.maximum(length-t, 0)/min(.04, length*.3), 1)
        attack = np.minimum(t/(.055 if kind == 'pad' else .0025), 1)
        phase = 2*np.pi*f*t
        if kind == 'bass':
            # Round sub stays centered; upper FM body is audible on small speakers.
            sub = np.sin(phase)
            body = np.sin(phase*2 + (1.7 if voice == 'glitch' else .9)*np.sin(phase)*np.exp(-t*9))
            bite = .11*np.sin(phase*3)*np.exp(-t*13)
            return (sub + .31*body + bite)*attack*release*np.exp(-t*5.2)
        if kind == 'pad':
            signal = (np.sin(phase*.9985)+np.sin(phase*1.0015)+.2*np.sin(phase*2))/2.2
            return signal*attack*release
        # A pitched hammer transient gives every melody onset a crisp timing cue.
        piano = np.sin(phase)*np.exp(-t*4.8)
        for harmonic in [2, 3, 4, 6]:
            if f*harmonic < RATE*.45:
                piano += .42/harmonic*np.sin(phase*(harmonic+.001*harmonic**2))*np.exp(-t*(5+harmonic*2))
        if kind == 'piano':
            return piano*attack*release
        if kind == 'bell':
            bell = .75*np.sin(phase)*np.exp(-t*7)
            if f*2.003 < RATE*.45:
                bell += .23*np.sin(phase*2.003)*np.exp(-t*12)
            if f*4.01 < RATE*.45:
                bell += .09*np.sin(phase*4.01)*np.exp(-t*20)
            return bell*attack*release
        # A band-limited three-voice unison is brighter than the original sine lead.
        signal = np.zeros(len(t))
        rolloff = 1.27 if voice in ('anthem', 'finale') else 1.42
        for harmonic in range(1, 9):
            if f*harmonic < RATE*.44:
                partial = (np.sin(phase*harmonic*.9978)+np.sin(phase*harmonic)+np.sin(phase*harmonic*1.0022))/3
                signal += partial/harmonic**rolloff*np.exp(-t*(2.5+harmonic*bright*1.1))
        if voice == 'glitch':
            signal = signal*.82 + .16*np.sin(phase + 1.1*np.sin(phase*2)*np.exp(-t*22))
        elif voice == 'orbit':
            signal *= .78
            piano *= 1.18
        return (signal*.78+piano*.32)*attack*release

    def drum(kind):
        length = {'kick':.29, 'snare':.19, 'hat':.04, 'open':.13,
                  'crash':.90, 'tom':.15, 'impact':.75}[kind]
        t = np.arange(round(length*RATE))/RATE
        envelope = np.minimum(t/.0008, 1)
        if kind == 'kick':
            pitch = 45*t + 115*.017*(1-np.exp(-t/.017))
            body = np.sin(2*np.pi*pitch)*np.exp(-t*17)
            click = .13*rng.uniform(-1, 1, len(t))*np.exp(-t*230)
            return (body+click)*envelope
        if kind == 'tom':
            return np.sin(2*np.pi*(91*t+29*.025*(1-np.exp(-t/.025))))*np.exp(-t*24)*envelope
        if kind == 'impact':
            sub = np.sin(2*np.pi*(36*t+35*.08*(1-np.exp(-t/.08))))*np.exp(-t*7)
            return sub*envelope
        noise = rng.uniform(-1, 1, len(t))
        high = np.concatenate(([0], np.diff(noise)))*.5
        if kind == 'snare':
            # Body + staggered clap pulses; stronger midrange without brittle treble.
            clap = np.zeros(len(t))
            for at, strength in [(0, 1), (.011, .58), (.023, .38)]:
                shifted = np.maximum(t-at, 0)
                clap += strength*high*np.exp(-shifted*43)*(t >= at)
            body = .30*np.sin(2*np.pi*184*t)*np.exp(-t*34)
            return (.60*clap+body)*envelope
        decay = 120 if kind == 'hat' else 31 if kind == 'open' else 5
        return high*np.exp(-t*decay)*envelope

    drums = {kind:drum(kind) for kind in ['kick', 'snare', 'hat', 'open', 'crash', 'tom', 'impact']}
    for count in range(4):
        t = np.arange(round(.045*RATE))/RATE
        click = np.sin(2*np.pi*(1320 if count == 0 else 990)*t)*np.exp(-t*75)*np.minimum(t/.002, 1)
        add(-preroll+count*60/song['bpms'][0], click, .18)

    scales = {'anthem':[0, 2, 3, 5, 7, 8, 10, 12],
              'glitch':[0, 1, 3, 5, 7, 8, 10, 12],
              'orbit':[0, 2, 3, 5, 7, 9, 10, 12],
              'finale':[0, 2, 3, 5, 7, 8, 11, 12]}
    scale = scales[voice]
    progression = [0, 5, 2, 6, 0, 3, 5, 6]
    bar_for_note = []
    for i, bar in enumerate(data['bars']):
        local = i % song['section_bars']
        section, beat = bar['section'], 60/bar['bpm']
        bar_length = bar['beats']*beat
        degree = progression[(i//2) % 8] if i < len(data['bars'])-2 else 0
        chord = root+scale[degree]-(12 if degree >= 4 else 0)
        intervals = [scale[(degree+step) % 7]+12*((degree+step)//7)-scale[degree] for step in [0, 2, 4, 6]]
        breakdown, intro = section == 2 and local < 8, section == 0 and local < 4
        energy = [.76, 1.03, .94, 1.15][section]
        if breakdown:
            energy = .32
        elif intro:
            energy = .45+local*.08
        build = section < 3 and local >= song['section_bars']-4
        phrase_rest = local % 8 == 7
        for step in range(bar['beats']):
            if phrase_rest and step == bar['beats'] - 1:
                continue
            at = bar['t']+step*beat
            if not breakdown or step == 0:
                add(at, drums['kick'], .45*energy)
            if step % 2 and not intro:
                add(at, drums['snare'], .29*energy, .06)
            bass = tone(chord-12+(intervals[2] if step == 3 else 0), beat*.72, 'bass')
            add(at, pump(bass, beat, .30), .27*energy)
            if not breakdown:
                add(at+.5*beat, tone(chord-12, beat*.30, 'bass'), .14*energy)
                # Answering bass syncopations make the high-energy profiles groove.
                if section in (1, 3) and step % 2 and voice in ('glitch', 'finale'):
                    add(at+.75*beat, tone(chord-12, beat*.19, 'bass'), .07*energy)
            for half in range(2):
                add(at+half*.5*beat, drums['hat'], .059*energy, -.42 if half else .42)
            if not breakdown and section > 0:
                add(at+.5*beat, drums['open'], .027*energy, .32)
            if section == 3 and step % 2 == 0:
                add(at+.25*beat, drums['hat'], .025*energy, -.35)
                add(at+.75*beat, drums['hat'], .025*energy, .35)
        # Diatonic sevenths, voiced around the melody rather than transposed minor chords.
        for interval in intervals:
            pad = tone(chord+interval, (bar_length-beat if phrase_rest else bar_length*.94), 'pad')
            add(bar['t'], pump(pad, beat, 0 if breakdown else .53), .040*energy, (interval-5)*.085)
        if i % 8 == 0 and not intro:
            add(bar['t'], drums['crash'], .17*energy, -.30)
        if local == 0 and section in (1, 3):
            add(bar['t'], drums['impact'], .24, 0)
            add(bar['t']+.02, drums['crash'], .16, .35)
        if i % 8 == 6 and not breakdown:
            for fill in range(4):
                add(bar['t']+bar_length-(4-fill)*beat*.25, drums['snare'], (.035+fill*.015)*energy, (fill-1.5)*.20)
            if voice in ('glitch', 'finale'):
                for fill in range(3):
                    add(bar['t']+bar_length-(3-fill)*beat/3, drums['tom'], .08*energy, -.3+fill*.3)
        # A four-bar build grows towards the tempo boundary; the downbeat impact resolves it.
        if build and not phrase_rest:
            progress = (local-(song['section_bars']-4))/4
            subdivisions = 4 if progress >= .5 else 2
            for pulse in range(bar['beats']*subdivisions):
                add(bar['t']+pulse*beat/subdivisions, drums['snare'], (.014+.025*progress)*(1+pulse/(bar['beats']*subdivisions)), -.16 if pulse % 2 else .16)
            t = np.arange(round(bar_length*RATE))/RATE
            u = t/bar_length
            sweep = np.sin(2*np.pi*((220+progress*330)*t+400*t*t/bar_length))*.22
            noise = rng.uniform(-1, 1, len(t))
            noise = np.concatenate(([0], np.diff(noise)))*.22
            add(bar['t'], (sweep+noise)*(progress*.55+u*.35)**2*np.minimum((bar_length-t)/.02, 1), .10, .25)
        bar_for_note.append((bar, energy, breakdown, chord))

    # The score is the source of BOTH sound and all playable arrangements.
    # Its foreground hook, answering piano and brief sparkling ornaments have
    # distinct timbres and intentional dynamics, never a quiet union-of-charts.
    bar_index = 0
    score = data['score']
    for i, note in enumerate(score):
        while bar_index + 1 < len(data['bars']) and data['bars'][bar_index + 1]['t'] <= note['t'] + .00001:
            bar_index += 1
        bar, energy, breakdown, chord = bar_for_note[bar_index]
        beat = 60 / bar['bpm']
        layer = note['voice']
        degree = note['degree']
        midi = root + 12 + scale[degree % 7] + 12 * (degree // 7)
        if layer == 'spark':
            midi += 12
        if bar['section'] == 3 and layer == 'lead' and bar_index % 8 >= 4:
            midi += 12
        held = note['d'] >= .3
        length = note['d'] if held else min(.19, beat * .6)
        pan = (-.16 if note['hand'] == 0 else .16) if layer == 'lead' else (-.45 if note['hand'] == 0 else .45)
        accent = 1.12 if note['accent'] else .92
        if layer == 'lead':
            instrument = 'piano' if breakdown or voice == 'orbit' and bar['section'] == 0 else 'lead'
            gain = (.32 if breakdown else .30) * accent
        elif layer == 'reply':
            instrument, gain = ('bell' if voice == 'orbit' else 'piano'), .23 * accent
            length = min(.15, beat * .48)
        elif layer == 'spark':
            instrument, gain = 'bell', .16 * accent
            length = min(.10, beat * .3)
        else:
            instrument, gain = 'piano', .14
            length = min(.21, beat * .7)
        sound = tone(midi, length, instrument, 1.1 if voice == 'glitch' else .8)
        add(note['t'], sound, gain, pan)
        # Short stereo early reflections add space without inventing another
        # rhythm .75 beats after each note, as the old delay did.
        add(note['t'] + .018, sound, gain * .055, -pan)
        if held:
            # A sustained body actually ends at the authored release; the
            # scoring release is therefore audible, not an arbitrary duration.
            add(note['t'], tone(midi, note['d'], 'pad'), .10, -pan)
        if layer == 'lead' and note['accent'] and bar['section'] in (1, 3):
            add(note['t'], tone(midi - 12, min(.13, length), 'piano'), .055, -pan)

    # Gentle bus saturation: more body than the first mix, with codec overshoot headroom.
    mix -= mix.mean(axis=0)
    mix = np.tanh(mix*1.42)
    mix *= np.minimum(1, np.arange(len(mix), 0, -1)/(RATE*.55))[:, None]
    mix *= .80/max(.80, float(np.max(np.abs(mix))))
    pcm = np.rint(mix*32767).astype('<i2')
    with tempfile.TemporaryDirectory() as folder:
        wav = Path(folder)/'song.wav'
        with wave.open(str(wav), 'wb') as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(wav), '-c:a', 'libvorbis', '-q:a', '4', '-metadata', 'title='+song['title'], '-metadata', 'artist=PERFECTO Ranker Original', str(path)], check=True)
