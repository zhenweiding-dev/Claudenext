import Foundation

/// `~/.claudenext/config.json`, shared with the hook script.
///
/// The app owns `port`, `sound`, `focusOnRequest` and the icon behaviour; the
/// hook owns `intercept`, `ignore` and `timeout`. Both are modelled here so the
/// settings can edit either without the two ends clobbering each other.
struct AppConfig: Equatable {
    var port: UInt16 = 4471
    var sound: Bool = true
    /// Bring the popover to the keyboard when a request arrives.
    var focusOnRequest: Bool = true
    /// Tool names (fnmatch patterns) routed through the panel.
    var intercept: [String] = ["Bash", "Write", "Edit", "MultiEdit",
                               "NotebookEdit", "WebFetch", "mcp__*"]
    var ignore: [String] = []
    /// Seconds the hook waits for an answer.
    var timeout: Double = 280
    /// Optionally keep out of the menu bar until there is something to ask.
    var hideWhenIdle: Bool = false
    /// Honour permissions.allow / deny / ask already set in .claude/settings.json.
    var respectClaudeCodePermissions: Bool = true

    /// Every tool the settings pane offers, in the order it shows them.
    static let knownTools = ["Bash", "Edit", "MultiEdit", "Write", "NotebookEdit",
                             "Read", "WebFetch", "WebSearch", "mcp__*"]

    /// `CLAUDENEXT_HOME` relocates the whole support directory. The hook honours
    /// the same variable, so both ends stay pointed at the same files — and it
    /// is the only safe way to test this, since `NSHomeDirectory()` ignores
    /// `$HOME` and would otherwise write to the real one.
    static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDENEXT_HOME"],
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claudenext")
    }

    static var configURL: URL {
        supportDirectory.appendingPathComponent("config.json")
    }

    static func load() -> AppConfig {
        var config = AppConfig()
        guard let data = try? Data(contentsOf: configURL),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return config }

        if let v = object["port"] as? NSNumber { config.port = v.uint16Value }
        if let v = object["sound"] as? Bool { config.sound = v }
        if let v = object["focusOnRequest"] as? Bool { config.focusOnRequest = v }
        if let v = object["intercept"] as? [String] { config.intercept = v }
        if let v = object["ignore"] as? [String] { config.ignore = v }
        if let v = object["timeout"] as? NSNumber { config.timeout = v.doubleValue }
        if let v = object["hideWhenIdle"] as? Bool { config.hideWhenIdle = v }
        if let v = object["respectClaudeCodePermissions"] as? Bool {
            config.respectClaudeCodePermissions = v
        }
        return config
    }

    /// Read-modify-write, so keys added by hand survive a change made in the UI.
    func save() {
        var object: [String: Any] = [:]
        if let data = try? Data(contentsOf: Self.configURL),
           let existing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            object = existing
        }
        object["port"] = Int(port)
        object["sound"] = sound
        object["focusOnRequest"] = focusOnRequest
        object["intercept"] = intercept
        object["ignore"] = ignore
        object["timeout"] = timeout
        object["hideWhenIdle"] = hideWhenIdle
        object["respectClaudeCodePermissions"] = respectClaudeCodePermissions

        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
        ) else { return }

        try? FileManager.default.createDirectory(at: Self.supportDirectory,
                                                 withIntermediateDirectories: true)
        let temporary = Self.configURL.appendingPathExtension("tmp")
        do {
            try (data + Data("\n".utf8)).write(to: temporary, options: .atomic)
            _ = try? FileManager.default.removeItem(at: Self.configURL)
            try FileManager.default.moveItem(at: temporary, to: Self.configURL)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
        }
    }

    func intercepts(_ tool: String) -> Bool {
        intercept.contains(tool)
    }
}
