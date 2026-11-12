"""Canonical Ranker charts and timed challenge sessions; client totals are never trusted."""
import json,secrets,time
from pathlib import Path
from scoring import analyze
path=Path(__file__).with_name('ranker_charts.json')
if not path.exists():path=Path(__file__).parents[1]/'assets/ranker/catalog.json'
SONGS={song['id']:song for song in json.loads(path.read_text())}
WINDOWS=(.022,.05,.1)
MAX_HITS=4096
def begin(uid,song_id,kind):
    if song_id not in SONGS or kind not in ('one','double'):raise ValueError('없는 랭커 종목입니다')
    song=SONGS[song_id]
    return dict(token=secrets.token_urlsafe(24),uid=uid,id=song_id,kind=kind,started=time.monotonic(),duration=song['duration']+song['audio_offset'])
def finish(run,token,hits):
    if not run or not secrets.compare_digest(str(token),run['token']):raise ValueError('기록 도전을 다시 시작해 주세요')
    elapsed=time.monotonic()-run['started']
    if elapsed<run['duration']-.8:raise ValueError('곡이 끝난 뒤 기록을 제출하세요')
    if elapsed>600:raise ValueError('도전 시간이 만료되었습니다')
    if not isinstance(hits,list) or len(hits)>MAX_HITS:raise ValueError('입력 개수 오류')
    for hit in hits:
        if not isinstance(hit,dict):raise ValueError('잘못된 입력')
        lane=hit.get('lane',0)
        if type(lane) is not int or lane not in ((0,) if run['kind']=='one' else (0,1)):raise ValueError('종목과 다른 레인')
        if not -.2<=float(hit.get('t',-100))<=SONGS[run['id']]['duration']+.5:raise ValueError('곡 범위를 벗어난 입력')
    report=analyze(SONGS[run['id']]['charts'][run['kind']],hits,windows=WINDOWS,max_hits=MAX_HITS,chronological=True,max_time=SONGS[run['id']]['duration']+1)
    accuracy=report['accuracy']
    report['grade']=next((g for threshold,g in [(99.5,'EX'),(98,'SS'),(95,'S'),(85,'A'),(75,'B')] if accuracy>=threshold),'F')
    return report
