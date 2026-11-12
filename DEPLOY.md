# 친구에게 링크로 공유하기

로그인·레이팅·코인·스킨을 활성화하려면 [계정 저장소 연결 안내](ACCOUNTS.md)에 따라 PostgreSQL `DATABASE_URL`을 Render 환경변수로 설정하세요. 설정 전에는 게스트 대전을 유지합니다.

## 기존 Render 서비스가 있는 경우

게임과 대전 서버를 같은 서비스에서 제공합니다. 저장소 업데이트 후 Render가 새 버전으로 배포되면 **https://rhythm-duel.onrender.com** 을 브라우저에서 열어 플레이할 수 있습니다. 친구에게 이 링크를 보내면 됩니다. 고돗 설치가 필요 없습니다.

1. Render의 기존 `rhythm-duel` 서비스에서 배포 상태를 확인합니다.
2. 자동 배포가 꺼져 있으면 **Manual Deploy → Deploy latest commit**을 누릅니다.
3. 새 빌드에는 Godot와 Web 템플릿 다운로드 및 내보내기가 포함되어 기존보다 시간이 더 걸립니다.
4. **Live**가 되면 서비스 주소를 엽니다. 화면이 이전 버전이면 Ctrl+Shift+R로 새로고침합니다.
5. 두 사람이 온라인 대전에 들어가 한 명이 방을 만들고 다른 사람이 6자리 코드로 참가합니다. 브라우저 게임은 현재 페이지와 같은 서버에 자동 연결합니다.

Render 설정은 기존과 같습니다: **Root Directory `server` / Runtime `Docker` / Branch `main`**. Docker 빌드 단계가 이 공개 GitHub 저장소의 main 브랜치에서 게임 소스를 가져와 내보내고, 런타임에는 내보낸 게임과 WebSocket 서버만 포함합니다. 코드가 바뀌면 최신 커밋으로 다시 배포하세요.

이 서비스는 서버 방과 점수를 메모리에 보관하므로 재배포나 재시작 시 진행 중인 경기가 초기화됩니다. 무료 서비스는 유휴 상태에서 중지될 수 있어 첫 접속이 늦을 수 있습니다. 페이지가 뜨지 않으면 잠시 기다린 뒤 다시 시도하세요. 상시 실행이 필요하면 Render의 요금제와 비용을 확인하세요.

## 새 Render 서비스로 처음 배포

Render → New Web Service → GitHub `han-17287/rhythm-duel` 선택:

| 항목 | 값 |
|---|---|
| Branch | main |
| Root Directory | server |
| Runtime | Docker |
| Instance Type | Free (제공 여부·조건은 Render에서 확인) |

Deploy 후 Live 상태가 되면 Render가 보여주는 서비스 주소를 공유합니다. 이 브라우저 게임은 같은 주소의 WebSocket 서버를 자동으로 사용하므로 별도 서버 URL 설정이 필요 없습니다.

## 로컬 Web 빌드

Linux x86_64와 Python 3.11 이상에서:

```sh
python3 tools/build_web.py
STATIC_DIR="$PWD/build/web" python3 server/server.py
```

먼저 `python3 -m pip install -r server/requirements.txt`로 서버 의존성을 설치하세요. 이후 http://localhost:8765 에서 플레이할 수 있습니다.

빌드 도구는 Godot 4.7.2와 같은 버전의 Web 전용 내보내기 템플릿을 내려받습니다. 한국어 UI용 PERFECTO UI 글꼴은 저장소에 포함되어 있으며 Noto Sans KR에서 파생한 SIL OFL 글꼴입니다(`assets/FONTLOG.txt`, `assets/OFL.txt`). Godot가 설치되어 있다면 버전이 일치해야 하며 `GODOT_BIN` 환경변수로 실행 파일을 지정할 수도 있습니다. Linux 서버에서 필요한 시스템 라이브러리는 `server/Dockerfile`을 참고하세요.

출력은 `build/web/`이며, 별도 호스팅에 올릴 ZIP은 `build/rhythm-duel-web.zip`입니다. ZIP에 index.html과 모든 내보내기 파일, 음악용 `audio/` 하위 폴더가 포함됩니다. 웹에서는 이 빌드 도구가 음악 재생과 실제 입력 시각을 동기화하는 브라우저 코드를 함께 넣으므로 `build/web/` 폴더 전체를 배포하세요. 별도 호스팅을 사용할 경우 게임의 서버 설정에서 `wss://rhythm-duel.onrender.com`을 입력하세요. HTTPS 페이지에서는 wss:// 주소가 필요합니다.

## 검증

### HTTP 503 또는 계정 연결 실패

`Live`는 배포 상태이며, 접속 오류가 계속되면 해당 배포의 실행 로그를 확인하세요. `/health`는 웹 서버가 요청을 처리할 때 `200 ok`를 반환합니다. Render의 Health Check Path를 설정한다면 `/health`를 사용합니다.

웹 서버는 계정 DB 초기화보다 먼저 시작합니다. DB 연결·초기화 실패 시 게임 파일과 게스트 방은 계속 제공하고 30초마다 다시 연결합니다. 이때 로그인·계정 보상·글로벌 기록은 활성화하지 않으며, 임시 로컬 DB에 계정을 대신 저장하지 않습니다. 연결이 복구되면 접속 중인 게임에도 계정 기능 활성화를 알립니다.

로그의 `Account database unavailable`은 `DATABASE_URL`의 호스트·포트·DB 비밀번호·접근 권한을 확인하라는 뜻입니다. `Account database ready`가 나오면 초기화가 완료된 것입니다. 이 두 메시지에는 연결 문자열이나 비밀번호를 출력하지 않습니다. 이 동작은 DB 초기화 실패에 의한 서버 중단을 막는 것으로, 모든 Render 503 원인을 해결한다는 뜻은 아닙니다.

서버 테스트는 같은 포트의 HTTP 게임 파일 제공과 WebSocket 방 연결, 올바른 WebAssembly MIME 타입, 경로 접근 제한 및 6회 공수·점수 계산을 검사합니다. 로컬 Chromium에서 Web 빌드 실행과 한글 표시, 두 브라우저의 방 코드 참가·리듬 제작·수비 화면도 확인했습니다. 실제 Render 배포 완료 상태는 Render 대시보드에서 확인해야 합니다.


랭커 글로벌 기록판과 첫 클리어 보상은 기존 계정 저장소(`DATABASE_URL`)를 사용합니다. 별도 테이블은 서버 시작 시 자동 생성됩니다. 저장소가 없을 때도 원비트·더블과 모든 구간 연습, 기기 최고 기록은 사용할 수 있습니다.
