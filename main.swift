import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var enabled = false
    var sleepDisabledAtLaunch = false
    var enabledByThisApp = false
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

        // 시스템에 이미 disablesleep이 켜져 있으면 상태만 맞추고 종료 시 임의로 끄지 않는다.
        sleepDisabledAtLaunch = currentSleepDisabled()
        enabled = sleepDisabledAtLaunch
        updateUI()
    }

    @objc func toggle() {
        let target = !enabled
        if setSleepDisabled(target) {
            enabled = target
            enabledByThisApp = target && !sleepDisabledAtLaunch
            updateUI()
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 앱이 이번 실행에서 켠 설정만 종료 시 원복한다.
        if enabledByThisApp {
            _ = setSleepDisabled(false)
        }
    }

    func setSleepDisabled(_ disable: Bool) -> Bool {
        let value = disable ? 1 : 0
        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return false }
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
