# 인터넷 배포: Render 서버 + itch.io 브라우저 게임

서버와 게임을 각각 배포합니다. 방 코드는 같은 서버에 접속한 사람끼리 공유합니다.

## 1. 방 코드 서버 배포

1. https://dashboard.render.com/ 에 가입하고 GitHub를 연결합니다.
2. **New → Blueprint**에서 `han-17287/rhythm-duel` 저장소를 선택합니다.
3. 저장소 루트의 `render.yaml`을 사용해 서비스를 생성합니다. 비용과 무료 플랜 제공 여부는 Render 확인 화면에서 확인하세요. 설정은 `plan: free`입니다.
4. 배포가 완료되면 Render의 서비스 주소를 복사합니다. 예: `https://rhythm-duel-relay-xxxx.onrender.com`.
5. 게임에 사용할 주소는 `https://`를 `wss://`로 바꾼 `wss://rhythm-duel-relay-xxxx.onrender.com`입니다. Render가 TLS를 처리하고 컨테이너는 `PORT` 환경변수를 읽습니다.

Blueprint를 사용하지 않으면 **New → Web Service**, 해당 저장소, Root Directory `server`, Runtime `Docker`로 생성해도 됩니다. 서버는 WebSocket 전용이라 주소를 브라우저에서 여는 것만으로 정상 작동을 확인할 수 없습니다. 게임의 방 만들기로 확인하세요.

무료 서비스는 유휴 상태에서 중지되어 첫 연결이 지연되거나 기존 연결이 종료될 수 있습니다. 현재 클라이언트는 최대 90초 동안 연결을 기다립니다. 그래도 접속이 실패하면 잠시 뒤 재시도하세요. 실제 대전 안정성이 필요하면 항상 실행되는 요금제를 검토하세요. 서비스 재시작 시 메모리에 있는 방과 점수는 초기화됩니다. 여러 서버 인스턴스 사이의 방 공유는 지원하지 않습니다.

## 2. 게임 기본 서버 주소 지정

고돗을 닫고 `project.godot`의 다음 설정을 실제 서버 주소로 바꾸세요. 고돗 Project Settings에서 Advanced Settings를 켜고 `application/config/server_url`을 변경해도 됩니다.

```ini
[application]
config/server_url="wss://실제서버주소.onrender.com"
```

이 값을 설정하면 플레이어가 서버 주소를 직접 입력할 필요가 없습니다. 웹 게임이 HTTPS로 배포되면 서버도 `wss://`여야 합니다. `127.0.0.1`은 접속한 플레이어 자신의 컴퓨터이므로 인터넷 배포용 주소가 아닙니다.

## 3. 브라우저 게임 내보내기

1. 고돗 **Editor → Manage Export Templates**에서 사용 중인 고돗 버전과 정확히 일치하는 Export Templates를 설치합니다.
2. **Project → Export → Web** 프리셋을 선택합니다. 저장소에 Web 프리셋을 포함했습니다.
3. `Thread Support`는 끕니다. 이 프로젝트는 Compatibility 렌더러와 단일 스레드 Web 내보내기를 사용합니다.
4. 프로젝트 안에 `build/web` 폴더를 만들고 **Export Project**로 `build/web/index.html`을 내보냅니다.
5. 생성된 `.html`, `.js`, `.wasm`, `.pck` 등 **모든 파일**을 함께 ZIP으로 묶습니다. ZIP 최상위에 `index.html`이 있어야 합니다. `web/index.html`처럼 상위 폴더를 포함하지 마세요.

고돗 프로젝트 소스 ZIP을 그대로 웹 호스팅에 올리면 게임이 실행되지 않습니다. 반드시 Web 내보내기를 먼저 해야 합니다. 본 작업 환경에서는 Web Export Templates 설치와 실제 브라우저 배포를 수행하지 않았습니다.

## 4. itch.io에 공개

1. https://itch.io/game/new 에서 게임 페이지를 만듭니다.
2. Kind of project를 **HTML**로 선택합니다.
3. 내보낸 Web 파일들의 ZIP을 업로드하고 **This file will be played in the browser**를 체크합니다.
4. 화면 크기는 1152 × 720으로 지정하거나 전체 화면 버튼을 켭니다. 플레이 중에는 게임 화면을 클릭해 키보드 포커스를 맞춥니다.
5. 페이지를 저장하고 공개합니다. 공개 전 미리보기에서 먼저 검증해도 됩니다.
6. 두 사람이 게임 링크를 열어 같은 서버에 접속하고, 한 명이 방을 만든 뒤 표시된 6자리 코드를 공유합니다.

데스크톱 게임으로 배포하려면 Windows/Linux/macOS용으로 내보내고 같은 itch.io 페이지에 다운로드 파일로 올려도 됩니다. 이 경우에도 방 코드 서버는 계속 실행되어야 합니다.

## 공개 후 확인

서로 다른 PC나 네트워크에서 방 만들기 → 코드 참가 → 일반/롱 노트 수비 → 6회 공수 → 최종 점수까지 확인하세요. 이 프로젝트는 클라이언트 보고 입력 시간을 신뢰하는 친구 대전용 프로토타입이며 계정·랭킹·강력한 부정행위 방지는 아직 없습니다.
