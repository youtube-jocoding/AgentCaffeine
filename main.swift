// Copyright 2026 jocoding
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Cocoa
import IOKit.pwr_mgt
import Darwin

// 루트 watchdog에게 "지금 해제하라"고 알리는 신호 파일.
// 앱(사용자 권한)이 생성하고, watchdog(루트)가 감지 후 삭제한다.
let kReleaseFlagPath = "/tmp/com.jocoding.agentcaffeine.release"

// IOPMCopyAssertionsByProcess가 돌려주는 per-assertion 딕셔너리의 키/값.
// (CFSTR 매크로는 Swift로 임포트되지 않으므로 원시 문자열을 직접 쓴다.)
private let kAssertTypeKey = "AssertType"
private let kAssertNameKey = "AssertName"
private let kSleepBlockingTypes: Set<String> = [
    "PreventUserIdleSystemSleep",   // idle 시스템 잠자기 차단 (caffeinate -i 등)
    "NoIdleSleepAssertion",         // 동일 계열 (Electron 앱 다수)
    "PreventSystemSleep",           // 시스템 잠자기 차단 (caffeinate -s)
    "PreventUserIdleDisplaySleep",  // 화면 잠자기 차단 → 화면 켜진 동안 잠 못 듦
]

/// 잠자기를 막고 있는 프로세스 한 건.
struct SleepBlocker {
    let pid: pid_t
    let appName: String
    let detail: String
    let quittable: Bool
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var enabled = false
    let toggleItem = NSMenuItem(title: "잠자기 방지 켜기", action: #selector(toggle), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.delegate = self          // 메뉴 열 때마다 assertion 목록을 갱신한다
        statusItem.menu = menu

        // 시작 시 자가 치유: 이전 세션이 비정상 종료(재부팅 등)되어 disablesleep가
        // 켜진 채 남아 있으면 사용자에게 알리고 정리한다. watchdog가 살아 있었다면 이미 0이다.
        cleanupStaleReleaseFlag()
        selfHealIfStuck()
        populate(menu)
    }

    // MARK: - 메뉴 구성

    /// 메뉴를 열기 직전마다 호출 — "잠자기 막는 중" 목록을 실시간으로 다시 그린다.
    func menuWillOpen(_ menu: NSMenu) {
        populate(menu)
    }

    func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem.separator())

        // --- 지금 잠자기를 막는 중 ---
        let header = NSMenuItem(title: "지금 잠자기를 막는 중", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let blockers = sleepBlockers()
        if blockers.isEmpty {
            let none = NSMenuItem(title: "   (없음 — 정상적으로 잠들 수 있음)", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for b in blockers {
                if b.quittable {
                    let item = NSMenuItem(
                        title: "   \(b.appName)  —  \(b.detail)",
                        action: #selector(quitBlocker(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = Int(b.pid)
                    item.toolTip = "클릭하면 이 앱을 종료해 잠자기 방지를 해제합니다"
                    menu.addItem(item)
                } else {
                    let item = NSMenuItem(
                        title: "   \(b.appName)  —  \(b.detail) · 종료 불가",
                        action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    menu.addItem(item)
                }
            }
        }
        menu.addItem(NSMenuItem.separator())

        let info = NSMenuItem(title: "Agent가 도는 동안 덮개를 닫아도 잠들지 않습니다", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        let warn = NSMenuItem(title: "가방에 넣기 전에는 꼭 꺼주세요 (발열·배터리)", action: nil, keyEquivalent: "")
        warn.isEnabled = false
        menu.addItem(warn)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        updateUI()
    }

    // MARK: - 잠자기 막는 프로세스 조회/종료

    /// 현재 잠자기를 막고 있는 프로세스 목록을 PID 기준으로 묶어 돌려준다.
    func sleepBlockers() -> [SleepBlocker] {
        var cf: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&cf) == kIOReturnSuccess,
              let cfDict = cf?.takeRetainedValue() else { return [] }
        let byPid = cfDict as NSDictionary

        let myPid = ProcessInfo.processInfo.processIdentifier
        var result: [pid_t: SleepBlocker] = [:]

        for (key, value) in byPid {
            guard let pidNum = key as? NSNumber,
                  let assertions = value as? [[String: Any]] else { continue }
            let pid = pidNum.int32Value
            if pid == myPid { continue }

            let relevant = assertions.filter { a in
                guard let type = a[kAssertTypeKey] as? String else { return false }
                return kSleepBlockingTypes.contains(type)
            }
            guard !relevant.isEmpty else { continue }

            let onlyDisplay = relevant.allSatisfy {
                (($0[kAssertTypeKey] as? String) ?? "").contains("Display")
            }
            let running = NSRunningApplication(processIdentifier: pid)
            let name = running?.localizedName
                ?? processName(for: pid)
                ?? (relevant.first?[kAssertNameKey] as? String)
                ?? "PID \(pid)"

            result[pid] = SleepBlocker(
                pid: pid,
                appName: name,
                detail: onlyDisplay ? "화면 켜둠" : "잠자기 막음",
                quittable: running != nil)
        }

        return result.values.sorted {
            $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
        }
    }

    /// GUI 앱이 아닌(데몬·CLI) 프로세스의 실행 파일 이름을 얻는 폴백.
    func processName(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_MAXSIZE
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        return path.isEmpty ? nil : (path as NSString).lastPathComponent
    }

    @objc func quitBlocker(_ sender: NSMenuItem) {
        let pid = pid_t(sender.tag)
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        let name = app.localizedName ?? "이 앱"
        let alert = NSAlert()
        alert.messageText = "\(name)을(를) 종료할까요?"
        alert.informativeText = "이 앱이 Mac의 잠자기를 막고 있습니다. 종료하면 잠자기 방지가 풀립니다."
        alert.addButton(withTitle: "종료")
        alert.addButton(withTitle: "취소")
        if alert.runModal() == .alertFirstButtonReturn {
            if !app.terminate() {
                app.forceTerminate()
            }
        }
    }

    // MARK: - 액션

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
