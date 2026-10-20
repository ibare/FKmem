# FKMEM

**어떤 앱이 메모리를 먹고 있는지, 메뉴바에서 한눈에.**

FKMEM은 메모리 사용량을 프로세스가 아니라 **앱 단위로** 묶어서 보여주는 macOS 메뉴바 앱입니다.
기능은 일부러 적게 두었습니다. 메모리가 얼마나 남았는지, 어떤 앱이 얼마나 쓰고 있는지만 보여줍니다.

## 왜 만들었나

요즘 Mac에서 메모리를 쓰는 건 앱 하나가 아니라, 그 앱이 띄운 수많은 자식 프로세스입니다.

- 터미널에서 돌리는 AI 코딩 에이전트는 `node`, `python` 프로세스를 줄줄이 띄웁니다. MCP 서버까지 붙으면 금세 수십 개가 됩니다.
- Electron 앱은 창과 탭마다 `Helper (Renderer)`, `Helper (GPU)` 같은 프로세스를 따로 둡니다.

활성 상태 보기를 열면 이 프로세스들이 제각각 흩어져 나옵니다. 똑같은 이름의 `node`가 열 개 넘게 보여도 어느 앱 소속인지 알 수 없습니다. 앱 하나가 얼마나 쓰는지 알려면 직접 찾아서 더해야 합니다.
이 일을 대신 해 주는 메모리 모니터는 많지만, 대부분 CPU, 네트워크, 디스크, 메모리 정리 기능까지 한꺼번에 담고 있어서 정작 필요한 숫자가 묻힙니다.

FKMEM은 한 가지 질문에만 답합니다. **"지금 어떤 앱이 메모리를 얼마나 쓰고 있나?"**

### 예시

같은 순간을 두 가지 방식으로 본 실제 측정값의 일부입니다.

프로세스 단위로 보면:

```
node                        1.07 GB
Codex (Renderer)             861 MB
Claude Helper (Renderer)     639 MB
Codex (Service)              509 MB
Codex (Renderer)             377 MB
node                         172 MB
node                         148 MB
…  같은 이름의 프로세스가 수십 개 더
```

FKMEM에서 보면:

```
ChatGPT      2.93 GB   ← 이 앱이 띄운 프로세스 23개의 합
Ghostty      1.47 GB   ← 이 터미널과 그 안에서 실행한 node 등 7개의 합
Claude       1.17 GB   ← Claude와 Helper 프로세스 12개의 합
Alacritty    1.15 GB   ← 이 터미널과 그 안에서 실행한 node 등 31개의 합
```

맨 위의 1.07 GB짜리 `node`가 Ghostty에서 실행한 에이전트였다는 것을 따로 찾아볼 필요가 없습니다.

## 화면 구성

**메뉴바** — 아이콘 옆에 지금 쓸 수 있는 메모리(예: `5.2G`)가 표시됩니다. 메모리 압력이 올라가면 숫자 색이 노란색(주의), 빨간색(위험)으로 바뀝니다.

**클릭하면 열리는 창**

- 요약 한 줄: 총 사용량 · 가용 메모리 · 압력(정상 / 주의 / 위험)
- 최근 3분간의 메모리 압력 추이 그래프
- 100 MB 이상 쓰는 앱 목록. 많이 쓰는 순서로 앱 아이콘과 함께 표시
- 마지막 갱신 시각, 새로고침 버튼, 종료 버튼

창을 열어 둔 동안은 3초마다, 닫혀 있을 때는 15초마다 갱신됩니다.
오른쪽 클릭(또는 Control-클릭)하면 종료 메뉴가 나옵니다. Dock에는 나타나지 않습니다.

### 하지 않는 것

CPU, 네트워크, 디스크 정보, 프로세스 강제 종료, "메모리 정리", 설정 화면, 알림. 모두 의도적으로 넣지 않았습니다.
FKMEM은 아무 데이터도 외부로 보내지 않습니다.

## 숫자가 의미하는 것

| 항목 | 출처 |
|---|---|
| 앱별 사용량 | 각 프로세스의 `phys_footprint`(`proc_pid_rusage`). 활성 상태 보기의 "메모리" 열과 같은 기준입니다. |
| 앱 단위 묶기 | macOS가 프로세스마다 기록해 두는 **책임 프로세스(responsible process)**. 터미널에서 실행한 스크립트가 권한을 요청할 때 "터미널이 접근하려고 합니다"라고 뜨는 것과 같은 원리입니다. |
| 앱 이름과 아이콘 | 책임 프로세스가 `.app` 번들 안에 있으면 그 앱의 이름과 아이콘을, 아니면 실행 파일 이름을 씁니다. |
| 총 사용 | 목록에 잡힌 모든 앱(100 MB 미만 포함)의 합계 |
| 가용 | 비어 있는 페이지에 바로 비울 수 있는 페이지(파일 캐시, 해제 가능 영역 등)를 더한 추정치 |
| 압력 | 커널이 판단한 메모리 압력 단계(`kern.memorystatus_vm_pressure_level`) |

압력 그래프의 높이는 커널의 압력 단계에 압축 메모리 비율을 조금 더한 값입니다. 정확한 수치보다는 흐름을 보는 용도입니다.

## 알아둘 점

- **비공개 API를 사용합니다.** 앱 단위 묶기에 쓰는 `responsibility_get_pid_responsible_for_pid`는 Apple이 문서화하지 않은 함수라서 macOS 업데이트로 동작이 바뀔 수 있습니다. 이 함수를 찾지 못하면 묶지 않고 프로세스 단위로 보여줍니다.
- **내 계정의 프로세스만 셉니다.** 시스템이나 다른 사용자 계정으로 실행되는 프로세스(WindowServer, 각종 데몬 등)는 권한상 읽을 수 없어서 목록과 합계에서 빠집니다. 그래서 "총 사용"은 시스템 전체 사용량과 다릅니다.
- 앱이 자식 프로세스의 책임을 넘기도록 실행한 경우, 또는 백그라운드 서비스로 따로 실행된 프로세스는 별도 항목으로 보일 수 있습니다.
- App Sandbox를 쓰지 않고 비공개 API를 쓰기 때문에 Mac App Store로는 배포할 수 없습니다.

## 설치

**요구 사항**: macOS 26.2 이상

릴리즈에서 내려받아도 되고, 소스에서 직접 빌드해도 됩니다.

### 방법 1. 릴리즈에서 내려받기

1. [Releases](https://github.com/ibare/FKmem/releases/latest) 페이지에서 `FKMEM-<버전>.zip`을 내려받습니다.
2. 압축을 풀고 `FKMEM.app`을 응용 프로그램 폴더로 옮깁니다.
3. 실행하면 메뉴바에 아이콘이 나타납니다.

Developer ID로 서명하고 Apple 공증을 받은 빌드입니다. 처음 열 때 인터넷에서 받은 앱을 열지 묻는 확인 창이 한 번 뜨는데, **열기**를 누르면 됩니다.

### 방법 2. 소스에서 직접 빌드하기

Xcode 26.2 이상이 필요합니다.

**Xcode에서**

1. 리포를 clone한 뒤 `FKMEM.xcodeproj`를 엽니다.
2. FKMEM 타깃의 **Signing & Capabilities**에서 Team을 본인 계정으로 바꾸거나, Signing Certificate를 **Sign to Run Locally**로 지정합니다.
3. ⌘R로 실행합니다.

**터미널에서**

```sh
git clone https://github.com/ibare/FKmem.git
cd FKmem
xcodebuild -project FKMEM.xcodeproj -scheme FKMEM -configuration Release \
  -derivedDataPath build DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=- build
cp -R build/Build/Products/Release/FKMEM.app /Applications/
open /Applications/FKMEM.app
```

`DEVELOPMENT_TEAM= CODE_SIGN_IDENTITY=-`는 Apple 개발자 계정 없이 내 Mac에서만 실행할 수 있도록 서명하는 옵션입니다.

### 로그인할 때 자동 실행

앱에 자동 실행 설정은 없습니다. **시스템 설정 → 일반 → 로그인 항목**에 FKMEM을 추가해 주세요.

## 코드 구조

```
FKMEM/
├── App/AppDelegate.swift               메뉴바 아이템, 창, 갱신 주기
├── Core/
│   ├── ProcessSampler.swift            전체 프로세스의 phys_footprint 수집
│   ├── ResponsibilityResolver.swift    책임 프로세스 조회 (비공개 API)
│   ├── AppGrouper.swift                책임 프로세스 기준으로 합산, 앱 이름·아이콘 찾기
│   ├── MemoryPressure.swift            가용 메모리, 압력 단계
│   └── Formatters.swift                용량 표시 형식
├── Models/                             데이터 모델
├── ViewModel/MemoryStore.swift         주기적 측정과 압력 이력
└── Views/PopoverView.swift             클릭하면 열리는 창
scripts/
└── release.sh                          서명·공증된 배포용 zip 만들기 (사용법은 파일 상단 참고)
```

외부 패키지 의존성은 없습니다.

## 라이선스

[MIT](LICENSE)
