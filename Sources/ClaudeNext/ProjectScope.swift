import Foundation

/// `<project>/.claude/claudenext.json` — which tools this project routes
/// through the panel at all.
///
/// Deliberately *not* a rule store. Remembered rules live in the project's own
/// `.claude/settings.local.json` permissions, so there is one permission list
/// and Claude Code honours it too. This file only holds scope.
struct ProjectScope {
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

    static func load(cwd: String) -> ProjectScope {
        var scope = ProjectScope()
        guard let data = try? Data(contentsOf: url(for: cwd)),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return scope }
        scope.intercept = object["intercept"] as? [String]
        scope.ignore = object["ignore"] as? [String]
        return scope
    }

    /// Write `intercept`, leaving every other key exactly as found.
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
