// Compiled against Sources/ClaudeNext/AppConfig.swift by run-tests.sh.
//
// config.json is written by the settings pane and read by the hook on every
// tool call, so a clobbering bug here would silently drop someone's intercept
// list. These checks pin that down.

import Foundation

@main
enum ConfigRoundtrip {
    static var failures: [String] = []

    static func check(_ description: String, _ condition: Bool) {
        if !condition { failures.append(description) }
    }

    static func main() {
        let configURL = AppConfig.configURL
        // NSHomeDirectory() ignores $HOME, so only CLAUDENEXT_HOME can keep this
        // test off the real support directory. Refuse to run without it.
        precondition(ProcessInfo.processInfo.environment["CLAUDENEXT_HOME"] != nil,
                     "set CLAUDENEXT_HOME; this test writes files")
        precondition(!configURL.path.hasPrefix(NSHomeDirectory() + "/.claudenext"),
                     "refusing to run against the real ~/.claudenext")

        try? FileManager.default.createDirectory(at: AppConfig.supportDirectory,
                                                 withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: configURL)

        // 1. No file at all -> defaults.
        let defaults = AppConfig.load()
        check("defaults: port", defaults.port == 4471)
        check("defaults: sound on", defaults.sound)
        check("defaults: intercepts Bash", defaults.intercepts("Bash"))
        check("defaults: does not intercept Read", !defaults.intercepts("Read"))
        check("defaults: icon stays visible", !defaults.hideWhenIdle)
        check("defaults: does not open itself", !defaults.autoOpenOnRequest)

        // 2. Everything the app owns survives a save/load cycle.
        var edited = defaults
        edited.sound = false
        edited.focusOnRequest = false
        edited.autoOpenOnRequest = true
        edited.port = 4999
        edited.intercept = ["Bash", "Read", "mcp__*"]
        edited.ignore = ["Bash(echo:*)"]
        edited.timeout = 120
        edited.hideWhenIdle = true
        edited.save()

        let reloaded = AppConfig.load()
        check("roundtrip: sound", reloaded.sound == false)
        check("roundtrip: focusOnRequest", reloaded.focusOnRequest == false)
        check("roundtrip: autoOpenOnRequest", reloaded.autoOpenOnRequest)
        check("roundtrip: port", reloaded.port == 4999)
        check("roundtrip: intercept", reloaded.intercept == ["Bash", "Read", "mcp__*"])
        check("roundtrip: ignore", reloaded.ignore == ["Bash(echo:*)"])
        check("roundtrip: timeout", reloaded.timeout == 120)
        check("roundtrip: hideWhenIdle", reloaded.hideWhenIdle)
        check("roundtrip: whole value is equal", reloaded == edited)

        // 3. Keys the app knows nothing about must survive a write from the UI.
        var raw = (try! JSONSerialization.jsonObject(
            with: Data(contentsOf: configURL))) as! [String: Any]
        raw["experimentalThing"] = ["nested": true]
        raw["someFutureKey"] = "keep me"
        try! JSONSerialization
            .data(withJSONObject: raw, options: .prettyPrinted)
            .write(to: configURL)

        var afterUIEdit = AppConfig.load()
        afterUIEdit.sound = true
        afterUIEdit.save()

        let finalRaw = (try! JSONSerialization.jsonObject(
            with: Data(contentsOf: configURL))) as! [String: Any]
        check("preserves unknown scalar key",
              finalRaw["someFutureKey"] as? String == "keep me")
        check("preserves unknown nested key",
              (finalRaw["experimentalThing"] as? [String: Any])?["nested"] as? Bool == true)
        check("applied the edit", finalRaw["sound"] as? Bool == true)
        check("kept the hook's timeout",
              (finalRaw["timeout"] as? NSNumber)?.doubleValue == 120)
        check("kept the hook's intercept",
              (finalRaw["intercept"] as? [String]) == ["Bash", "Read", "mcp__*"])

        // 4. A corrupt file must not throw away the defaults.
        try! Data("{ not json".utf8).write(to: configURL)
        let recovered = AppConfig.load()
        check("corrupt file falls back to defaults", recovered.port == 4471 && recovered.sound)

        if failures.isEmpty {
            print("config_roundtrip: all pass")
        } else {
            for failure in failures { print("FAIL  " + failure) }
            exit(1)
        }
    }
}
