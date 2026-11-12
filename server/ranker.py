"""Canonical Ranker charts and timed challenge sessions; client totals are never trusted."""
import json,secrets,time
from pathlib import Path
from scoring import analyze
path=Path(__file__).with_name('ranker_charts.json')
if not path.exists():path=Path(__file__).parents[1]/'assets/ranker/catalog.json'
SONGS={song['id']:song for song in json.loads(path.read_text())}
WINDOWS=(.022,.05,.1)
DIFFICULTY_WINDOWS={
    'hard':WINDOWS,
    'expert':(.020,.045,.090),
    'inferno':(.018,.040,.080),
}
MAX_HITS=4096
EXTRA_PENALTY=600
REFRESH_MESSAGE='채보가 업데이트되었어요. 게임을 새로고침한 뒤 다시 도전해 주세요.'
class RevisionError(ValueError):
    """A safe, actionable message for cached clients, not raw internal errors."""

def revision(song_id):
    if song_id not in SONGS:raise ValueError('없는 랭커 종목입니다')
    return int(SONGS[song_id].get('revision',1))

def require_revision(song_id,client_revision):
    expected=revision(song_id)
    # Legacy revisions may omit this field; a cached v1 browser must never
    # unknowingly submit its old chart to a rewritten v2 leaderboard.
    if client_revision is None and expected==1:return expected
    if type(client_revision) is not int or client_revision!=expected:raise RevisionError(REFRESH_MESSAGE)
    return expected

def storage_id(song_id,chart_revision=None):
    version=revision(song_id) if chart_revision is None else chart_revision
    return song_id+(f':v{version}' if version>1 else '')

def chart(song_id,kind,difficulty='hard'):
    if song_id not in SONGS or kind not in ('one','double') or difficulty not in DIFFICULTY_WINDOWS:
        raise ValueError('없는 랭커 종목입니다')
    song=SONGS[song_id]
    charts=song['charts'] if difficulty=='hard' else song.get('extras',{}).get(difficulty,{})
    if kind not in charts:raise ValueError('없는 랭커 난이도입니다')
    return charts[kind]

def begin(uid,song_id,kind,difficulty='hard'):
    chart(song_id,kind,difficulty)
    song=SONGS[song_id]
    return dict(token=secrets.token_urlsafe(24),uid=uid,id=song_id,kind=kind,difficulty=difficulty,revision=revision(song_id),started=time.monotonic(),duration=song['duration']+song['audio_offset'])
def finish(run,token,hits):
    if not run or not secrets.compare_digest(str(token),run['token']):raise ValueError('기록 도전을 다시 시작해 주세요')
    if run.get('revision',1)!=revision(run['id']):raise RevisionError(REFRESH_MESSAGE)
    elapsed=time.monotonic()-run['started']
    if elapsed<run['duration']-.8:raise ValueError('곡이 끝난 뒤 기록을 제출하세요')
    if elapsed>600:raise ValueError('도전 시간이 만료되었습니다')
    if not isinstance(hits,list) or len(hits)>MAX_HITS:raise ValueError('입력 개수 오류')
    for hit in hits:
        if not isinstance(hit,dict):raise ValueError('잘못된 입력')
        lane=hit.get('lane',0)
        if type(lane) is not int or lane not in ((0,) if run['kind']=='one' else (0,1)):raise ValueError('종목과 다른 레인')
        if not -.2<=float(hit.get('t',-100))<=SONGS[run['id']]['duration']+.5:raise ValueError('곡 범위를 벗어난 입력')
    difficulty=run.get('difficulty','hard')
    report=analyze(chart(run['id'],run['kind'],difficulty),hits,windows=DIFFICULTY_WINDOWS[difficulty],max_hits=MAX_HITS,chronological=True,max_time=SONGS[run['id']]['duration']+1,extra_penalty=EXTRA_PENALTY)
    accuracy=report['accuracy']
    report['grade']=next((g for threshold,g in [(99.5,'EX'),(98,'SS'),(95,'S'),(85,'A'),(75,'B')] if accuracy>=threshold),'F')
    return report
