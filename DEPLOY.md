# 친구에게 링크로 공유하기

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

빌드 도구는 Godot 4.6.3, 같은 버전의 Web 전용 내보내기 템플릿, SIL OFL 라이선스의 Noto Sans KR 글꼴을 내려받습니다. Godot가 설치되어 있다면 버전이 일치해야 하며 `GODOT_BIN` 환경변수로 실행 파일을 지정할 수도 있습니다. Linux 서버에서 필요한 시스템 라이브러리는 `server/Dockerfile`을 참고하세요.

출력은 `build/web/`이며, 별도 호스팅에 올릴 ZIP은 `build/rhythm-duel-web.zip`입니다. ZIP 최상위에 index.html과 모든 내보내기 파일이 포함됩니다. 별도 호스팅을 사용할 경우 게임의 서버 설정에서 `wss://rhythm-duel.onrender.com`을 입력하세요. HTTPS 페이지에서는 wss:// 주소가 필요합니다.

## 검증

서버 테스트는 같은 포트의 HTTP 게임 파일 제공과 WebSocket 방 연결, 올바른 WebAssembly MIME 타입, 경로 접근 제한 및 6회 공수·점수 계산을 검사합니다. 로컬 Chromium에서 Web 빌드 실행과 한글 표시, 두 브라우저의 방 코드 참가·리듬 제작·수비 화면도 확인했습니다. 실제 Render 배포 완료 상태는 Render 대시보드에서 확인해야 합니다.
