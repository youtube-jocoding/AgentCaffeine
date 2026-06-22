# AgentCaffeine ☕

> AI 에이전트가 오래 도는 동안 Mac이 잠들지 않게 해주는 메뉴바 앱 — 필요할 때만 깨우고, 잠잘 수 있을 때는 다시 재웁니다.

Claude Code·Codex 같은 AI 에이전트나 긴 빌드·렌더링·다운로드를 걸어두고 자리를 비울 때,
노트북 덮개를 닫으면 macOS가 잠들어 작업이 멈춰버립니다. 반대로 작업이 끝났는데도 잠자기 방지가
남아 있으면 발열과 배터리 소모가 생깁니다. AgentCaffeine은 메뉴바에서 전원 정책을 고르게 해서
**깨어 있어야 할 때는 깨어 있고**, **잠잘 수 있을 때는 정상적으로 잠들게** 합니다.

## ✨ 기능

- 🧭 **전원 정책 선택** — 자동, 잠자기 허용, 화면 켜짐 동안만 유지, 덮개 닫아도 유지
- 🤖 **자동 모드** — 다른 앱이 실제로 잠자기를 막고 있을 때만 덮개 닫힘 방지까지 올리고, 사라지면 해제
- 💤 **강제 잠자기** — 잠자기 방지 해제, 배터리 보호 설정 적용, `pmset sleepnow`를 한 번에 실행
- 🔋 **배터리 보호 설정** — 배터리에서 화면/시스템 잠자기를 1분으로 복구하고 백그라운드 깨우기를 끔
- ☕ **덮개 닫힘(클램셸) 잠자기까지 차단** — macOS에서 이게 가능한 유일한 방법(`pmset disablesleep`) 사용
- 🛡️ **복구 안전장치** — watchdog가 자동 복구하고, 끄기·종료 시 실제 해제 여부를 확인
- 🔌 **비밀번호 요청 최소화** — 덮개 닫힘 방지가 필요할 때만 관리자 권한을 요청
- 🔎 **잠자기 막는 앱 진단** — 지금 어떤 앱이 Mac을 깨워두는지 보여주고, 일반 앱은 메뉴에서 바로 종료
- 🪶 **가볍습니다** — 외부 의존성 없는 단일 Swift 파일, 메뉴바에만 상주

## 메뉴 미리보기

```
☕ AgentCaffeine
──────────────────────────────
  전원 제어
    상태: 자동 유지 중: Codex
    자동: 막는 앱 있을 때만 덮개 유지
    잠자기 허용
    화면 켜짐 동안만 깨어있기
    덮개 닫아도 깨어있기
──────────────────────────────
  강제 잠자기
  배터리 보호 설정 적용
──────────────────────────────
  지금 잠자기를 막는 중
    Codex          —  잠자기 막음        ← 클릭하면 종료
    Google Chrome  —  오디오 재생        ← 클릭하면 종료
──────────────────────────────
  막는 앱이 사라지면 자동으로 잠자기를 허용합니다
  가방에 넣기 전에는 잠자기 허용으로 바꾸세요
──────────────────────────────
  종료
```

## 요구 사항

- macOS 12 (Monterey) 이상 · Apple Silicon / Intel
- (빌드 시) Xcode Command Line Tools — 없으면 `xcode-select --install`

## 설치 / 실행

현재는 소스에서 직접 빌드합니다 (서명된 DMG 배포는 준비 중):

```bash
git clone https://github.com/youtube-jocoding/AgentCaffeine.git
cd AgentCaffeine
./build.sh
open AgentCaffeine.app
```

빌드되면 메뉴바에 ☕ 아이콘이 생깁니다. 처음 실행 시 "확인되지 않은 개발자" 경고가 뜨면
앱을 **오른쪽 클릭 → 열기**로 한 번만 허용하면 됩니다.

> Developer ID 인증서가 키체인에 있으면 `build.sh`가 자동으로 정식 서명합니다. 없으면 ad-hoc 서명되어
> 이 Mac에서만 실행됩니다. 빌드는 Apple Silicon/Intel universal 바이너리로 생성됩니다.

## 사용법

1. 메뉴바 ☕ 아이콘 → 원하는 **전원 제어** 모드를 선택합니다.
2. 평소에는 **자동: 막는 앱 있을 때만 덮개 유지** 또는 **잠자기 허용**을 권장합니다.
3. 장시간 에이전트를 돌리고 덮개를 닫아야 하면 **덮개 닫아도 깨어있기**를 선택합니다.
4. 끝나면 **잠자기 허용** 또는 **강제 잠자기**를 누르면 watchdog와 확인 절차로 설정을 되돌립니다.

모드별 의미:

- **자동**: Codex, Claude Code, 빌드 도구처럼 실제로 잠자기를 막는 앱이 감지되면 덮개 닫힘 방지까지 켭니다. 막는 앱이 사라지면 다시 잠자기를 허용합니다.
- **잠자기 허용**: AgentCaffeine이 가진 잠자기 방지를 모두 풉니다. Mac은 다른 앱이 막지 않는 한 정상적으로 잠듭니다.
- **화면 켜짐 동안만 깨어있기**: 앱이 idle sleep만 막습니다. 덮개를 닫으면 정상적으로 잠듭니다.
- **덮개 닫아도 깨어있기**: `pmset disablesleep`을 사용해 클램셸 잠자기까지 막습니다.
- **강제 잠자기**: AgentCaffeine의 잠자기 방지를 풀고, 배터리 보호 설정을 적용한 뒤 `pmset sleepnow`를 실행합니다.
- **배터리 보호 설정 적용**: 전원 연결 시 `displaysleep 5`, 배터리 사용 시 `displaysleep 1`, `sleep 1`, `powernap 0`, `tcpkeepalive 0`, `ttyskeepawake 0`을 적용하고 `disablesleep`을 해제합니다.

메뉴의 **"지금 잠자기를 막는 중"** 목록에서 다른 앱이 Mac을 깨워두는 것도 확인하고, 일반 앱이면 클릭해서 바로 종료할 수 있습니다.

> ⚠️ **켜진 상태로 가방에 넣지 마세요** (발열·배터리 소모). 혹시 비정상 종료로 설정이 남아도
> 앱을 다시 켜면 자동 감지해 해제 안내가 뜹니다. 수동 해제는 `sudo pmset -a disablesleep 0`.

## 배포 (Developer ID + 공증)

App Store 밖에서 정식 배포하는 절차입니다. 이 앱은 관리자 권한(`pmset disablesleep`)이 필요해서 App Store 샌드박스 정책상 입점이 불가능하므로, 이 방식이 정식 배포 경로입니다.

### 1. Apple Developer Program 가입 (최초 1회, 연 $99)

[developer.apple.com/programs](https://developer.apple.com/programs/) 에서 가입.

### 2. Developer ID Application 인증서 발급 (최초 1회)

가장 쉬운 방법은 Xcode 사용:

1. Xcode → Settings → Accounts → Apple ID 로그인
2. 팀 선택 → **Manage Certificates** → `+` → **Developer ID Application**

발급되면 키체인에 들어가고, `build.sh`가 자동으로 감지해서 정식 서명합니다.

### 3. 공증 자격 증명 저장 (최초 1회)

```bash
xcrun notarytool store-credentials agentcaffeine \
  --apple-id "본인 Apple ID 이메일" \
  --team-id "팀 ID(10자리, developer.apple.com → Membership에서 확인)" \
  --password "앱 암호"
```

앱 암호는 [appleid.apple.com](https://appleid.apple.com) → 로그인 및 보안 → 앱 암호에서 생성합니다 (Apple ID 비밀번호 아님).

### 4. 빌드 + 공증 + DMG 생성

```bash
./build.sh      # Developer ID 서명 빌드
./notarize.sh   # 앱/DMG 공증 → 스테이플 → AgentCaffeine-<버전>.dmg 생성
```

완료되면 어느 Mac에서나 경고 없이 실행되는 DMG가 나옵니다.

### 5. 배포

- **GitHub Releases**: 저장소를 만들고 DMG를 릴리스에 업로드
- **Homebrew**: `Casks/agentcaffeine.rb` 를 본인의 tap 저장소(`github.com/<계정>/homebrew-tap`)에 올리면:
  ```bash
  brew install --cask <계정>/tap/agentcaffeine
  ```

### 버전 올리기

`Info.plist`의 `CFBundleShortVersionString`과 `CFBundleVersion`을 수정 후 4번부터 반복.

## 파일 구성

| 파일 | 역할 |
|---|---|
| `main.swift` | 앱 전체 코드 (전원 정책, pmset/IOPMAssertion 제어, watchdog, 잠자기 막는 앱 표시·종료) |
| `Info.plist` | 앱 메타데이터 |
| `entitlements.plist` | Hardened Runtime 권한 (공증에 필요) |
| `build.sh` | 빌드 + 서명 (인증서 자동 감지) |
| `notarize.sh` | 공증 + DMG 패키징 |
| `gen_icon.swift` | 앱 아이콘 생성 (`swift gen_icon.swift`) |
| `Casks/agentcaffeine.rb` | Homebrew cask |

## 동작 원리

macOS에서 덮개 닫힘 잠자기까지 막는 유일한 공식 방법은 `pmset -a disablesleep` 입니다.
`caffeinate`·`IOPMAssertion`은 idle 잠자기만 막고 덮개 닫힘은 못 막습니다.

문제는 `disablesleep`이 **프로세스가 아니라 시스템에 영구히 박히는 설정**이라, 앱이 크래시되면
잠자기 방지가 영원히 남아 덮개를 닫아도 발열이 계속되는 사고가 납니다. 이를 막기 위해:

1. **덮개 닫아도 깨어있기** — 관리자 권한 1회로 `disablesleep 1` 설정 + 루트 **watchdog** 프로세스를 띄웁니다.
2. **watchdog** — `kill -0`로 앱 PID를 1초마다 감시하다가, 앱이 사라지거나(크래시·강제종료·정상종료)
   해제 신호 파일이 생기면 스스로 `disablesleep 0`으로 되돌립니다.
3. **잠자기 허용·종료** — 신호 파일을 남긴 뒤 실제 `SleepDisabled=0`을 확인합니다. 확인에 실패하면 관리자 권한으로 직접 복구합니다.
4. **자가 치유** — 재부팅 등으로 설정이 남은 채 시작되면 감지해 해제 안내를 띄웁니다.
5. **화면 켜짐 동안만 깨어있기** — 앱 프로세스가 소유한 `IOPMAssertion`만 만들기 때문에 앱 종료 시 macOS가 자동 회수합니다.
6. **자동 모드** — 주기적으로 power assertion을 확인해, 실질적인 작업 앱이 있을 때만 덮개 닫힘 방지를 켜고 없으면 끕니다.
7. **강제 잠자기/배터리 보호** — `disablesleep`을 끄고 배터리 전원 프로필을 안전값으로 되돌린 뒤 즉시 잠자기를 요청합니다.

### 잠자기 막는 앱 표시·종료

IOKit `IOPMCopyAssertionsByProcess()`로 현재 잠자기를 막는 power assertion을 읽어 메뉴에
앱 이름과 함께 보여줍니다. macOS는 다른 프로세스의 assertion을 직접 해제하는 것을 허용하지
않으므로(만든 프로세스만 해제 가능), 대신 **해당 앱을 종료**해 OS가 assertion을 회수하게 합니다.
일반 GUI 앱만 종료 버튼이 활성화되고, 시스템 프로세스·커널 assertion은 종료 불가로 표시됩니다.

## 기여

버그 제보·기능 제안은 [Issues](https://github.com/youtube-jocoding/AgentCaffeine/issues),
코드 기여는 Pull Request 환영합니다.

## 라이선스

[Apache License 2.0](LICENSE) © 2026 jocoding — 자유롭게 쓰고·고치고·배포할 수 있으며, 특허·상표 보호 조항이 포함됩니다.
