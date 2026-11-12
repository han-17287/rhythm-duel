"""Generate the original 120 BPM timing calibration click track."""
from pathlib import Path
import subprocess,tempfile,wave
import numpy as np
RATE=22050


def main():
    pcm=np.zeros(round(10.35*RATE),dtype=np.float64)
    for beat in range(20):
        start=round(beat*.5*RATE);t=np.arange(round(.065*RATE))/RATE
        sound=np.sin(2*np.pi*(1320 if beat%4==0 else 990)*t)*np.exp(-t*60)*np.minimum(t/.002,1)
        pcm[start:start+len(sound)]+=sound*.6
    with tempfile.TemporaryDirectory() as folder:
        wav=Path(folder)/'click.wav'
        with wave.open(str(wav),'wb') as w:w.setnchannels(1);w.setsampwidth(2);w.setframerate(RATE);w.writeframes(np.rint(pcm*32767).astype('<i2').tobytes())
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(wav),'-c:a','libvorbis','-q:a','3',str(Path(__file__).resolve().parents[1]/'assets/music/calibration.ogg')],check=True)


if __name__ == '__main__':
    main()
