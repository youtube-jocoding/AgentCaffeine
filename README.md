# AgentCaffeine ☕

> AI 에이전트가 오래 도는 동안 Mac이 잠들지 않게 해주는 메뉴바 앱 — **덮개를 닫아도 안 잡니다.**

Claude Code·Codex 같은 AI 에이전트나 긴 빌드·렌더링·다운로드를 걸어두고 자리를 비울 때,
노트북 덮개를 닫으면 macOS가 잠들어 작업이 멈춰버립니다. AgentCaffeine은 메뉴바 토글 하나로
**덮개를 닫아도** Mac을 깨어 있게 하고, 작업이 끝나거나 앱이 꺼지면(크래시·강제종료 포함)
**안전하게 원상 복구**합니다.

## ✨ 기능

- ☕ **덮개 닫힘(클램셸) 잠자기까지 차단** — macOS에서 이게 가능한 유일한 방법(`pmset disablesleep`) 사용
- 🛡️ **크래시에도 안전** — 앱이 강제종료·크래시돼도 watchdog가 몇 초 안에 자동 복구 (가방 속 발열 사고 방지)
- 🔌 **비밀번호는 켤 때 한 번만** — 끄기·종료는 무프롬프트
- 🔎 **잠자기 막는 앱 진단** — 지금 어떤 앱이 Mac을 깨워두는지 보여주고, 일반 앱은 메뉴에서 바로 종료
- 🪶 **가볍습니다** — 외부 의존성 없는 단일 Swift 파일, 메뉴바에만 상주

## 메뉴 미리보기

```
☕ AgentCaffeine
──────────────────────────────
  잠자기 방지 켜기
──────────────────────────────
  지금 잠자기를 막는 중
    Codex          —  잠자기 막음        ← 클릭하면 종료
    Google Chrome  —  화면 켜둠          ← 클릭하면 종료
    powerd         —  잠자기 막음 · 종료 불가
──────────────────────────────
  Agent가 도는 동안 덮개를 닫아도 잠들지 않습니다
  가방에 넣기 전에는 꼭 꺼주세요 (발열·배터리)
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

1. 메뉴바 ☕ 아이콘 → **잠자기 방지 켜기** → 관리자 비밀번호 입력(켤 때 한 번만)
2. 이제 덮개를 닫거나 자리를 비워도 Mac이 잠들지 않습니다
3. 끝나면 **잠자기 방지 끄기** 또는 앱 종료 → 자동 복구 (비밀번호 불필요)

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
- **Homebrew**: `Casks/agentcaffeine.rb` 의 PLACEHOLDER(GitHub 계정, SHA256)를 채우고
  본인의 tap 저장소(`github.com/<계정>/homebrew-tap`)에 올리면:
  ```bash
  brew install --cask <계정>/tap/agentcaffeine
  ```

### 버전 올리기

`Info.plist`의 `CFBundleShortVersionString`과 `CFBundleVersion`을 수정 후 4번부터 반복.

## 파일 구성

| 파일 | 역할 |
|---|---|
| `main.swift` | 앱 전체 코드 (메뉴바 토글, pmset 제어, watchdog, 잠자기 막는 앱 표시·종료) |
| `Info.plist` | 앱 메타데이터 |
| `entitlements.plist` | Hardened Runtime 권한 (공증에 필요) |
| `build.sh` | 빌드 + 서명 (인증서 자동 감지) |
| `notarize.sh` | 공증 + DMG 패키징 |
| `gen_icon.swift` | 앱 아이콘 생성 (`swift gen_icon.swift`) |
| `Casks/agentcaffeine.rb` | Homebrew cask 템플릿 |

## 동작 원리

macOS에서 덮개 닫힘 잠자기까지 막는 유일한 공식 방법은 `pmset -a disablesleep` 입니다
(`caffeinate`·`IOPMAssertion`은 idle 잠자기만 막고 덮개 닫힘은 못 막습니다).

문제는 `disablesleep`이 **프로세스가 아니라 시스템에 영구히 박히는 설정**이라, 앱이 크래시되면
잠자기 방지가 영원히 남아 덮개를 닫아도 발열이 계속되는 사고가 납니다. 이를 막기 위해:

1. **켜기** — 관리자 권한 1회로 `disablesleep 1` 설정 + 루트 **watchdog** 프로세스를 띄웁니다.
2. **watchdog** — `kill -0`로 앱 PID를 3초마다 감시하다가, 앱이 사라지거나(크래시·강제종료·정상종료)
   해제 신호 파일이 생기면 스스로 `disablesleep 0`으로 되돌립니다. → **영구 stuck 구조적 불가**.
3. **끄기·종료** — 비밀번호 없이 신호 파일만 남기면 watchdog가 복구합니다.
4. **자가 치유** — 재부팅 등으로 설정이 남은 채 시작되면 감지해 해제 안내를 띄웁니다.

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
