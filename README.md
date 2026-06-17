# AgentCaffeine ☕

AI Agent가 도는 동안 Mac이 잠들지 않게 해주는 메뉴바 앱.
**덮개를 닫아도 잠들지 않습니다.**

메뉴바의 ☕ 아이콘 → "잠자기 방지 켜기" → 관리자 비밀번호 입력(켤 때 한 번만). 끄기·종료는 비밀번호 없이 즉시 해제되고, **앱이 크래시·강제종료되어도 watchdog가 몇 초 안에 설정을 자동 복구**합니다.

또한 메뉴에서 **지금 Mac의 잠자기를 막고 있는 앱·프로세스를 실시간으로 보여주고**, 그게 일반 앱이면 바로 종료해 잠자기 방지를 풀 수 있습니다 (Codex·Chrome 등). 시스템 프로세스(powerd 등)는 종료 불가로 구분 표시됩니다.

> ⚠️ 켜진 상태로 가방에 넣지 마세요 (발열·배터리 소모). 재부팅 등으로 설정이 남는 드문 경우, 앱을 다시 켜면 자동 감지해 해제 안내가 뜹니다. 수동으로 풀려면 `sudo pmset -a disablesleep 0`.

## 빌드 (로컬 실행)

```bash
./build.sh
open AgentCaffeine.app
```

Xcode Command Line Tools만 있으면 됩니다. 기본 빌드는 Apple Silicon/Intel universal 앱으로 생성됩니다.
Developer ID 인증서가 없으면 ad-hoc 서명되어 이 Mac에서만 실행됩니다.

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
./notarize.sh   # 앱/DMG 공증 → 스테이플 → AgentCaffeine-1.0.dmg 생성
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
