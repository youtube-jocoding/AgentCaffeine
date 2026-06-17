import Cocoa

// 루트 watchdog에게 "지금 해제하라"고 알리는 신호 파일.
// 앱(사용자 권한)이 생성하고, watchdog(루트)가 감지 후 삭제한다.
let kReleaseFlagPath = "/tmp/com.jocoding.agentcaffeine.release"

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var enabled = false
    let toggleItem = NSMenuItem(title: "잠자기 방지 켜기", action: #selector(toggle), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem.separator())

        let info = NSMenuItem(title: "Agent가 도는 동안 덮개를 닫아도 잠들지 않습니다", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        let warn = NSMenuItem(title: "가방에 넣기 전에는 꼭 꺼주세요 (발열·배터리)", action: nil, keyEquivalent: "")
        warn.isEnabled = false
        menu.addItem(warn)
        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu

        // 시작 시 자가 치유: 이전 세션이 비정상 종료(재부팅 등)되어 disablesleep가
        // 켜진 채 남아 있으면 사용자에게 알리고 정리한다. watchdog가 살아 있었다면 이미 0이다.
        cleanupStaleReleaseFlag()
        selfHealIfStuck()
        updateUI()
    }

    @objc func toggle() {
        if enabled {
            disableKeepAwake()
        } else {
            enableKeepAwake()
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 정상 종료: 즉시 해제 신호를 남긴다(watchdog가 곧바로 disablesleep 0 복구).
        // 신호를 못 남기는 비정상 종료라도 watchdog의 PID 감시로 동일하게 복구되므로 안전하다.
        if enabled {
            requestRelease()
        }
    }

    // MARK: - Keep Awake 제어

    func enableKeepAwake() {
        let pid = ProcessInfo.processInfo.processIdentifier
        // 단 한 번의 관리자 권한 요청으로 두 가지를 처리한다.
        //   1) disablesleep 1  — 덮개 닫힘 잠자기까지 막는 macOS의 유일한 방법
        //   2) 루트 watchdog 기동 — 이 앱(PID)이 사라지거나 release 플래그가 생기면
        //      스스로 disablesleep 0 으로 복구한다. 따라서 크래시·강제종료에도
        //      설정이 영구히 남는("stuck") 상황이 구조적으로 발생하지 않는다.
        let watchdog =
            "/bin/bash -c 'while /bin/kill -0 \(pid) 2>/dev/null; do " +
            "[ -f \(kReleaseFlagPath) ] && break; /bin/sleep 3; done; " +
            "/usr/bin/pmset -a disablesleep 0; /bin/rm -f \(kReleaseFlagPath)'"
        let shell =
            "/bin/rm -f \(kReleaseFlagPath); " +
            "/usr/bin/pmset -a disablesleep 1; " +
            "/usr/bin/nohup \(watchdog) >/dev/null 2>&1 &"
        if runPrivileged(shell) {
            enabled = true
            updateUI()
        }
    }

    func disableKeepAwake() {
        // 비밀번호 없이 해제: release 플래그만 남기면 루트 watchdog가 disablesleep 0 으로 복구한다.
        requestRelease()
        enabled = false
        updateUI()
    }

    /// watchdog에게 즉시 해제를 지시하는 신호 파일 생성 (사용자 권한, 프롬프트 없음).
    func requestRelease() {
        FileManager.default.createFile(atPath: kReleaseFlagPath, contents: nil)
    }

    func cleanupStaleReleaseFlag() {
        try? FileManager.default.removeItem(atPath: kReleaseFlagPath)
    }

    /// 시작 시 disablesleep가 1로 남아 있으면(=이전 세션의 비정상 종료 잔재) 사용자에게 알리고 정리한다.
    func selfHealIfStuck() {
        guard currentSleepDisabled() else { return }
        let alert = NSAlert()
        alert.messageText = "잠자기 방지가 켜진 채 남아 있었습니다"
        alert.informativeText =
            "이전 세션이 비정상 종료되어 설정이 남은 것 같습니다.\n해제하면 Mac이 다시 정상적으로 잠들 수 있습니다."
        alert.addButton(withTitle: "해제 (권장)")
        alert.addButton(withTitle: "켠 상태로 관리")
        if alert.runModal() == .alertFirstButtonReturn {
            if runPrivileged("/usr/bin/pmset -a disablesleep 0") {
                enabled = false
            } else {
                enabled = currentSleepDisabled()
            }
        } else {
            // 계속 켜두되, 이번 세션의 watchdog가 다시 관리하도록 만들어 더 이상 stuck이 아니게 한다.
            enableKeepAwake()
        }
    }

    // MARK: - 시스템 호출

    @discardableResult
    func runPrivileged(_ shell: String) -> Bool {
        let source = "do shell script \"\(shell)\" with administrator privileges"
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: source) else { return false }
        appleScript.executeAndReturnError(&error)
        return error == nil
    }

    func currentSleepDisabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return false }
        for line in output.split(separator: "\n") {
            let parts = line.split { $0 == " " || $0 == "\t" }
            guard
                let key = parts.first?.lowercased(),
                let value = parts.last,
                key == "sleepdisabled" || key == "disablesleep"
            else {
                continue
            }
            return value == "1"
        }
        return false
    }

    // MARK: - UI

    func updateUI() {
        let symbol = enabled ? "cup.and.saucer.fill" : "cup.and.saucer"
        let description = enabled ? "잠자기 방지 켜짐" : "잠자기 방지 꺼짐"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description) {
            image.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.title = ""
        } else {
            statusItem.button?.image = nil
            statusItem.button?.title = "☕"
        }
        toggleItem.title = enabled ? "잠자기 방지 끄기" : "잠자기 방지 켜기"
        toggleItem.state = enabled ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
