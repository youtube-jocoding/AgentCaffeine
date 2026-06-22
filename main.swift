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
let kDisableSleepCommand = "/usr/bin/pmset -a disablesleep 0"
let kBatteryProtectionCommand =
    "/usr/bin/pmset -a disablesleep 0; " +
    "/usr/bin/pmset -b displaysleep 1 sleep 1 powernap 0 tcpkeepalive 0 ttyskeepawake 0"
private let kPowerModeDefaultsKey = "PowerMode"
private let kAutomaticPollInterval: TimeInterval = 15

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
    let processName: String
    let detail: String
    let quittable: Bool
    let assertionTypes: [String]
    let assertionNames: [String]
}

enum PowerMode: Int, CaseIterable {
    case automatic = 0
    case allowSleep = 1
    case keepAwakeWhileOpen = 2
    case keepAwakeLidClosed = 3

    var title: String {
        switch self {
        case .automatic:
            return "자동: 막는 앱 있을 때만 덮개 유지"
        case .allowSleep:
            return "잠자기 허용"
        case .keepAwakeWhileOpen:
            return "화면 켜짐 동안만 깨어있기"
        case .keepAwakeLidClosed:
            return "덮개 닫아도 깨어있기"
        }
    }

    var helpText: String {
        switch self {
        case .automatic:
            return "막는 앱이 사라지면 자동으로 잠자기를 허용합니다"
        case .allowSleep:
            return "잠잘 수 있을 때 정상적으로 잠듭니다"
        case .keepAwakeWhileOpen:
            return "덮개를 닫으면 정상적으로 잠듭니다"
        case .keepAwakeLidClosed:
            return "덮개를 닫아도 잠들지 않습니다"
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var selectedMode: PowerMode = .allowSleep
    var strongKeepAwakeEnabled = false
    var managedStrongThisSession = false
    var idleAssertionID: IOPMAssertionID = 0
    var automaticTimer: Timer?
    var automaticEnableSuppressed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [kPowerModeDefaultsKey: PowerMode.allowSleep.rawValue])
        selectedMode = storedPowerMode()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.delegate = self          // 메뉴 열 때마다 assertion 목록을 갱신한다
        statusItem.menu = menu

        // 시작 시 자가 치유: 이전 세션이 비정상 종료(재부팅 등)되어 disablesleep가
        // 켜진 채 남아 있으면 사용자에게 알리고 정리한다. watchdog가 살아 있었다면 이미 0이다.
        cleanupStaleReleaseFlag()
        let selfHealStartedManagement = selfHealIfStuck()
        if !selfHealStartedManagement {
            applySelectedMode(fromUserAction: false)
        }
        populate(menu)
    }

    // MARK: - 메뉴 구성

    /// 메뉴를 열기 직전마다 호출 — "잠자기 막는 중" 목록을 실시간으로 다시 그린다.
    func menuWillOpen(_ menu: NSMenu) {
        populate(menu)
    }

    func populate(_ menu: NSMenu) {
        strongKeepAwakeEnabled = currentSleepDisabled()
        menu.removeAllItems()

        let modeHeader = NSMenuItem(title: "전원 제어", action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        menu.addItem(modeHeader)

        let status = NSMenuItem(title: "   상태: \(powerStatusText())", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if let warning = batteryProtectionWarningText() {
            let warningItem = NSMenuItem(title: "   경고: \(warning)", action: nil, keyEquivalent: "")
            warningItem.isEnabled = false
            menu.addItem(warningItem)
        }

        for mode in PowerMode.allCases {
            let item = NSMenuItem(title: "   \(mode.title)", action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = mode.rawValue
            item.state = selectedMode == mode ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let forceSleepItem = NSMenuItem(title: "강제 잠자기", action: #selector(forceSleepNow), keyEquivalent: "")
        forceSleepItem.target = self
        menu.addItem(forceSleepItem)
        let batteryProtectionItem = NSMenuItem(title: "배터리 보호 설정 적용", action: #selector(applyBatteryProtection), keyEquivalent: "")
        batteryProtectionItem.target = self
        menu.addItem(batteryProtectionItem)
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

        let info = NSMenuItem(title: selectedMode.helpText, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        let warnText = strongKeepAwakeEnabled
            ? "가방에 넣기 전에는 잠자기 허용으로 바꾸세요"
            : "발열이 느껴지면 위 목록의 막는 앱을 확인하세요"
        let warn = NSMenuItem(title: warnText, action: nil, keyEquivalent: "")
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

            let running = NSRunningApplication(processIdentifier: pid)
            let fallbackProcessName = processName(for: pid)
            let relevant = assertions.filter { a in
                guard let type = a[kAssertTypeKey] as? String else { return false }
                guard kSleepBlockingTypes.contains(type) else { return false }
                let assertionName = (a[kAssertNameKey] as? String) ?? ""
                return !isIgnorableAssertion(processName: fallbackProcessName, assertionName: assertionName)
            }
            guard !relevant.isEmpty else { continue }

            let onlyDisplay = relevant.allSatisfy {
                (($0[kAssertTypeKey] as? String) ?? "").contains("Display")
            }
            let assertionTypes = relevant.compactMap { $0[kAssertTypeKey] as? String }
            let assertionNames = relevant.compactMap { $0[kAssertNameKey] as? String }
            let name = running?.localizedName
                ?? fallbackProcessName
                ?? (relevant.first?[kAssertNameKey] as? String)
                ?? "PID \(pid)"

            result[pid] = SleepBlocker(
                pid: pid,
                appName: name,
                processName: fallbackProcessName ?? name,
                detail: blockerDetail(assertionNames: assertionNames, onlyDisplay: onlyDisplay),
                quittable: running != nil,
                assertionTypes: assertionTypes,
                assertionNames: assertionNames)
        }

        return result.values.sorted {
            $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
        }
    }

    func isIgnorableAssertion(processName: String?, assertionName: String) -> Bool {
        guard processName == "powerd" else { return false }
        return assertionName == "Powerd - Prevent sleep while display is on"
    }

    func blockerDetail(assertionNames: [String], onlyDisplay: Bool) -> String {
        let joined = assertionNames.joined(separator: " ").lowercased()
        if joined.contains("video") {
            return "비디오 재생"
        }
        if joined.contains("audio") || joined.contains("playing") {
            return "오디오 재생"
        }
        return onlyDisplay ? "화면 켜둠" : "잠자기 막음"
    }

    func automaticKeepAwakeReasons() -> [SleepBlocker] {
        let ignoredProcesses: Set<String> = [
            "AddressBookSourceSync",
            "apsd",
            "bluetoothd",
            "cloudd",
            "coreaudiod",
            "identityservicesd",
            "powerd",
            "sharingd",
            "useractivityd",
        ]
        let ignoredAssertionFragments = [
            "Address Book Source Sync",
            "BTLEAdvertisement",
            "Handoff",
            "IDSPeerIDLookup",
        ]

        return sleepBlockers().filter { blocker in
            if blocker.assertionTypes.allSatisfy({ $0.contains("Display") }) {
                return false
            }
            if ignoredProcesses.contains(blocker.processName) || ignoredProcesses.contains(blocker.appName) {
                return false
            }
            for name in blocker.assertionNames {
                if ignoredAssertionFragments.contains(where: { name.contains($0) }) {
                    return false
                }
            }
            return true
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

    @objc func selectMode(_ sender: NSMenuItem) {
        guard let mode = PowerMode(rawValue: sender.tag) else { return }
        selectedMode = mode
        automaticEnableSuppressed = false
        storePowerMode(mode)
        applySelectedMode(fromUserAction: true)
        if let menu = statusItem.menu {
            populate(menu)
        }
    }

    @objc func forceSleepNow() {
        let alert = NSAlert()
        alert.messageText = "지금 Mac을 잠자기 상태로 전환할까요?"
        alert.informativeText =
            "AgentCaffeine이 잠자기 방지를 해제하고, 배터리 보호 설정을 적용한 뒤 macOS에 잠자기를 요청합니다."
        alert.addButton(withTitle: "잠자기")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        selectedMode = .allowSleep
        storePowerMode(selectedMode)
        applySelectedMode(fromUserAction: true)
        guard applyBatteryProtectionSettings(showErrors: true) else { return }
        _ = runCommand("/usr/bin/pmset", arguments: ["sleepnow"])
    }

    @objc func applyBatteryProtection() {
        let alert = NSAlert()
        alert.messageText = "배터리 보호 설정을 적용할까요?"
        alert.informativeText =
            "배터리 사용 시 화면 잠자기와 시스템 잠자기를 1분으로 돌리고, Power Nap·TCP keepalive·TTY 유지 깨우기를 끕니다. 덮개 닫힘 방지도 해제합니다."
        alert.addButton(withTitle: "적용")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        selectedMode = .allowSleep
        storePowerMode(selectedMode)
        applySelectedMode(fromUserAction: true)
        if applyBatteryProtectionSettings(showErrors: true), let menu = statusItem.menu {
            populate(menu)
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        automaticTimer?.invalidate()
        releaseIdleKeepAwake()
        // 정상 종료: 먼저 watchdog 해제 신호를 남기고, 실제 해제가 확인되지 않으면 직접 복구한다.
        // 비정상 종료는 watchdog가 복구하지만, watchdog 자체가 없어진 경우에는 다음 실행의 자가 치유가 필요하다.
        if strongKeepAwakeEnabled || managedStrongThisSession {
            requestRelease()
            if !waitForSleepDisabled(false, timeout: 3) {
                _ = runPrivileged(kDisableSleepCommand)
            }
        }
    }

    // MARK: - Keep Awake 제어

    func applySelectedMode(fromUserAction: Bool) {
        switch selectedMode {
        case .automatic:
            releaseIdleKeepAwake()
            startAutomaticControl()
        case .allowSleep:
            stopAutomaticControl()
            releaseIdleKeepAwake()
            _ = disableLidClosedKeepAwake(showErrors: fromUserAction)
        case .keepAwakeWhileOpen:
            stopAutomaticControl()
            _ = disableLidClosedKeepAwake(showErrors: fromUserAction)
            enableIdleKeepAwake(showErrors: fromUserAction)
        case .keepAwakeLidClosed:
            stopAutomaticControl()
            releaseIdleKeepAwake()
            _ = enableLidClosedKeepAwake(showErrors: fromUserAction)
        }
        updateUI()
    }

    func startAutomaticControl() {
        stopAutomaticControl()
        automaticTimer = Timer.scheduledTimer(
            timeInterval: kAutomaticPollInterval,
            target: self,
            selector: #selector(reconcileAutomaticControlFromTimer),
            userInfo: nil,
            repeats: true
        )
        reconcileAutomaticControl(fromTimer: false)
    }

    func stopAutomaticControl() {
        automaticTimer?.invalidate()
        automaticTimer = nil
    }

    @objc func reconcileAutomaticControlFromTimer() {
        reconcileAutomaticControl(fromTimer: true)
    }

    func reconcileAutomaticControl(fromTimer: Bool) {
        guard selectedMode == .automatic else { return }
        let reasons = automaticKeepAwakeReasons()
        if reasons.isEmpty {
            automaticEnableSuppressed = false
            if currentSleepDisabled() {
                _ = disableLidClosedKeepAwake(showErrors: false)
            }
        } else if !currentSleepDisabled() && !automaticEnableSuppressed {
            if !enableLidClosedKeepAwake(showErrors: !fromTimer) {
                automaticEnableSuppressed = true
            }
        }
        updateUI()
    }

    func enableIdleKeepAwake(showErrors: Bool) {
        guard idleAssertionID == 0 else { return }
        var newID: IOPMAssertionID = 0
        let reason = "AgentCaffeine: 화면 켜짐 동안 깨어있기" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &newID
        )
        if result == kIOReturnSuccess {
            idleAssertionID = newID
        } else if showErrors {
            showError(
                title: "화면 켜짐 유지 모드를 켜지 못했습니다",
                message: "macOS power assertion 생성에 실패했습니다. 다시 시도해 주세요."
            )
        }
    }

    func releaseIdleKeepAwake() {
        guard idleAssertionID != 0 else { return }
        IOPMAssertionRelease(idleAssertionID)
        idleAssertionID = 0
    }

    @discardableResult
    func enableLidClosedKeepAwake(showErrors: Bool) -> Bool {
        let pid = ProcessInfo.processInfo.processIdentifier
        // 단 한 번의 관리자 권한 요청으로 두 가지를 처리한다.
        //   1) disablesleep 1  — 덮개 닫힘 잠자기까지 막는 macOS의 유일한 방법
        //   2) 루트 watchdog 기동 — 이 앱(PID)이 사라지거나 release 플래그가 생기면
        //      스스로 disablesleep 0 으로 복구한다. 끄기/정상 종료 시에는 앱도 실제 해제 여부를
        //      확인하고, watchdog가 없으면 관리자 권한 fallback으로 직접 복구한다.
        let watchdog =
            "/bin/bash -c 'while /bin/kill -0 \(pid) 2>/dev/null; do " +
            "[ -f \(kReleaseFlagPath) ] && break; /bin/sleep 1; done; " +
            "\(kDisableSleepCommand); /bin/rm -f \(kReleaseFlagPath)'"
        let shell =
            "set -e; /bin/rm -f \(kReleaseFlagPath); " +
            "/usr/bin/nohup \(watchdog) >/dev/null 2>&1 & " +
            "/usr/bin/pmset -a disablesleep 1"
        if runPrivileged(shell), waitForSleepDisabled(true, timeout: 2) {
            strongKeepAwakeEnabled = true
            managedStrongThisSession = true
            return true
        } else {
            strongKeepAwakeEnabled = currentSleepDisabled()
            if showErrors {
                showError(
                    title: "덮개 닫힘 유지 모드를 켜지 못했습니다",
                    message: "시스템 설정을 확인하지 못했습니다. 현재 상태를 다시 확인해 주세요."
                )
            }
            return false
        }
    }

    @discardableResult
    func disableLidClosedKeepAwake(showErrors: Bool) -> Bool {
        guard currentSleepDisabled() else {
            strongKeepAwakeEnabled = false
            cleanupStaleReleaseFlag()
            return true
        }
        // 우선 release 플래그로 watchdog에게 해제를 맡긴다. 확인에 실패하면 관리자 권한 fallback으로 복구한다.
        requestRelease()
        if !waitForSleepDisabled(false, timeout: 3) {
            _ = runPrivileged(kDisableSleepCommand)
        }
        strongKeepAwakeEnabled = currentSleepDisabled()
        if strongKeepAwakeEnabled {
            if showErrors {
                showError(
                    title: "덮개 닫힘 유지 모드를 해제하지 못했습니다",
                    message: "관리자 권한 해제까지 실패했습니다. 터미널에서 sudo pmset -a disablesleep 0 을 실행해 주세요."
                )
            }
            return false
        }
        managedStrongThisSession = false
        cleanupStaleReleaseFlag()
        return true
    }

    @discardableResult
    func applyBatteryProtectionSettings(showErrors: Bool) -> Bool {
        let success = runPrivileged(kBatteryProtectionCommand)
        strongKeepAwakeEnabled = currentSleepDisabled()
        if !success && showErrors {
            showError(
                title: "배터리 보호 설정을 적용하지 못했습니다",
                message: "관리자 권한이 필요합니다. 취소했다면 설정은 변경되지 않습니다."
            )
        }
        if success {
            managedStrongThisSession = false
            cleanupStaleReleaseFlag()
        }
        updateUI()
        return success
    }

    /// watchdog에게 즉시 해제를 지시하는 신호 파일 생성 (사용자 권한, 프롬프트 없음).
    func requestRelease() {
        FileManager.default.createFile(atPath: kReleaseFlagPath, contents: nil)
    }

    func cleanupStaleReleaseFlag() {
        try? FileManager.default.removeItem(atPath: kReleaseFlagPath)
    }

    /// 시작 시 disablesleep가 1로 남아 있으면(=이전 세션의 비정상 종료 잔재) 사용자에게 알리고 정리한다.
    func selfHealIfStuck() -> Bool {
        guard currentSleepDisabled() else { return false }
        let alert = NSAlert()
        alert.messageText = "잠자기 방지가 켜진 채 남아 있었습니다"
        alert.informativeText =
            "이전 세션이 비정상 종료되어 설정이 남은 것 같습니다.\n해제하면 Mac이 다시 정상적으로 잠들 수 있습니다."
        alert.addButton(withTitle: "해제 (권장)")
        alert.addButton(withTitle: "켠 상태로 관리")
        if alert.runModal() == .alertFirstButtonReturn {
            if runPrivileged(kDisableSleepCommand) {
                strongKeepAwakeEnabled = false
            } else {
                strongKeepAwakeEnabled = currentSleepDisabled()
            }
        } else {
            // 계속 켜두되, 이번 세션의 watchdog가 다시 관리하도록 만들어 더 이상 stuck이 아니게 한다.
            selectedMode = .keepAwakeLidClosed
            storePowerMode(selectedMode)
            return enableLidClosedKeepAwake(showErrors: true)
        }
        return false
    }

    // MARK: - 시스템 호출

    @discardableResult
    func runPrivileged(_ shell: String) -> Bool {
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: source) else { return false }
        appleScript.executeAndReturnError(&error)
        return error == nil
    }

    @discardableResult
    func runCommand(_ path: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func commandOutput(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    func waitForSleepDisabled(_ expected: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if currentSleepDisabled() == expected {
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return currentSleepDisabled() == expected
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

    func storedPowerMode() -> PowerMode {
        let raw = UserDefaults.standard.integer(forKey: kPowerModeDefaultsKey)
        return PowerMode(rawValue: raw) ?? .allowSleep
    }

    func storePowerMode(_ mode: PowerMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: kPowerModeDefaultsKey)
    }

    func batteryPowerSettings() -> [String: Int] {
        guard let output = commandOutput("/usr/bin/pmset", arguments: ["-g", "custom"]) else { return [:] }
        var inBatterySection = false
        var settings: [String: Int] = [:]

        for rawLine in output.split(separator: "\n") {
            let line = String(rawLine)
            if line.hasPrefix("Battery Power:") {
                inBatterySection = true
                continue
            }
            if line.hasPrefix("AC Power:") {
                inBatterySection = false
                continue
            }
            guard inBatterySection else { continue }
            let parts = line.split { $0 == " " || $0 == "\t" }
            guard parts.count >= 2, let value = Int(parts.last ?? "") else { continue }
            settings[String(parts[0])] = value
        }
        return settings
    }

    func batteryProtectionWarningText() -> String? {
        let settings = batteryPowerSettings()
        if settings["displaysleep"] == 0 {
            return "배터리에서 화면 잠자기 안 함"
        }
        if settings["sleep"] == 0 {
            return "배터리에서 시스템 잠자기 안 함"
        }
        if settings["powernap"] == 1 || settings["tcpkeepalive"] == 1 {
            return "배터리에서 백그라운드 깨우기 허용"
        }
        return nil
    }

    func powerStatusText() -> String {
        if selectedMode == .automatic {
            let reasons = automaticKeepAwakeReasons()
            if automaticEnableSuppressed && !reasons.isEmpty {
                return "자동 대기 중 (관리자 권한 필요)"
            }
            if strongKeepAwakeEnabled {
                let names = reasons.map(\.appName).prefix(2).joined(separator: ", ")
                return names.isEmpty ? "자동 유지 중" : "자동 유지 중: \(names)"
            }
            return "자동 대기 중"
        }
        if strongKeepAwakeEnabled {
            return "덮개 닫힘 잠자기 차단 중"
        }
        if idleAssertionID != 0 {
            return "화면 켜짐 동안 깨어있음"
        }
        return "잠자기 허용 중"
    }

    func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }

    func updateUI() {
        let keepingAwake = strongKeepAwakeEnabled || idleAssertionID != 0
        let symbol = keepingAwake ? "cup.and.saucer.fill" : "cup.and.saucer"
        let description = keepingAwake ? "잠자기 방지 켜짐" : "잠자기 허용"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description) {
            image.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.title = ""
        } else {
            statusItem.button?.image = nil
            statusItem.button?.title = "☕"
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
