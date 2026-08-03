import Foundation

/// `<project>/.claude/claudenext.json`.
///
/// Both ends write this file: the hook when you remember a rule, the panel when
/// you change what a project asks about. Writes take an exclusive lock on a
/// sibling lockfile and land via atomic rename, so neither side can read a
/// half-written file or silently drop the other's change.
struct ProjectRules {
    var allow: [String] = []
    var deny: [String] = []
    /// `nil` means the project has no opinion and inherits the global list.
    var intercept: [String]?
    var ignore: [String]?

    static func directory(for cwd: String) -> URL {
        URL(fileURLWithPath: cwd).appendingPathComponent(".claude")
    }

    static func url(for cwd: String) -> URL {
        directory(for: cwd).appendingPathComponent("claudenext.json")
    }

    static func lockURL(for cwd: String) -> URL {
        directory(for: cwd).appendingPathComponent(".claudenext.lock")
    }

    static func load(cwd: String) -> ProjectRules {
        var rules = ProjectRules()
        guard let data = try? Data(contentsOf: url(for: cwd)),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return rules }
        rules.allow = (object["allow"] as? [String]) ?? []
        rules.deny = (object["deny"] as? [String]) ?? []
        rules.intercept = object["intercept"] as? [String]
        rules.ignore = object["ignore"] as? [String]
        return rules
    }

    /// Write `intercept`, leaving every other key — including rules the hook
    /// saved a moment ago — exactly as found.
    static func setIntercept(_ tools: [String], cwd: String) {
        mutate(cwd: cwd) { object in
            object["intercept"] = tools
        }
    }

    private static func mutate(cwd: String, _ change: (inout [String: Any]) -> Void) {
        let directory = directory(for: cwd)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let lock = FileLock(url: lockURL(for: cwd))
        lock.acquire()
        defer { lock.release() }

        let target = url(for: cwd)
        var object: [String: Any] = [:]
        if let data = try? Data(contentsOf: target),
           let existing = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            object = existing
        }
        change(&object)
        object["allow"] = object["allow"] ?? []
        object["deny"] = object["deny"] ?? []

        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
        ) else { return }

        atomicWrite(data + Data("\n".utf8), to: target)
    }
}

/// Replace a file's contents without ever leaving it missing.
///
/// `removeItem` followed by `moveItem` has a window where a reader — the hook
/// runs on every tool call — sees no file at all and falls back to defaults.
func atomicWrite(_ data: Data, to target: URL) {
    let temporary = target
        .deletingLastPathComponent()
        .appendingPathComponent(".\(target.lastPathComponent).\(getpid()).tmp")
    do {
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: target)
        }
    } catch {
        try? FileManager.default.removeItem(at: temporary)
    }
}

/// `flock` on a sibling file, so the Python hook can take the same lock.
final class FileLock {
    private var descriptor: Int32 = -1
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    func acquire() {
        descriptor = open(url.path, O_RDWR | O_CREAT, 0o644)
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_EX)
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
}
