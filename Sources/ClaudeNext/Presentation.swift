import Foundation

/// Tool-specific rendering. Mirrors the phrasing Claude Code uses in the
/// terminal ("Claude wants to run a command", …).
struct Presentation {
    enum Block: Identifiable {
        case code(String)
        case note(String)
        case diff(removed: [String], added: [String])
        case field(label: String, value: String)

        var id: String {
            switch self {
            case .code(let s): return "c\(s.hashValue)"
            case .note(let s): return "n\(s.hashValue)"
            case .diff(let r, let a): return "d\(r.hashValue)\(a.hashValue)"
            case .field(let l, let v): return "f\(l)\(v.hashValue)"
            }
        }
    }

    /// The session's project, so parallel sessions are told apart at a glance.
    var project: String = ""
    /// Full working directory, shown on hover.
    var projectPath: String = ""
    var title: String
    var badge: String
    var subtitle: String?
    var blocks: [Block]
    /// One-line version used for the recent-activity list.
    var summary: String

    private static let maxLines = 14

    static func make(payload: HookPayload) -> Presentation {
        var result = build(payload: payload)
        result.project = projectName(for: payload.cwd)
        result.projectPath = abbreviateHome(payload.cwd)
        return result
    }

    /// The directory name is what people actually call the project.
    private static func projectName(for cwd: String) -> String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || name == "/" ? abbreviateHome(cwd) : name
    }

    private static func build(payload: HookPayload) -> Presentation {
        let input = payload.toolInput
        let cwd = payload.cwd
        let tool = payload.toolName

        func str(_ key: String) -> String? {
            guard let v = input[key]?.stringValue, !v.isEmpty else { return nil }
            return v
        }

        switch tool {
        case "Bash":
            let command = str("command") ?? ""
            var blocks: [Block] = [.code(command)]
            if let d = str("description") { blocks.append(.note(d)) }
            return Presentation(
                title: "Claude wants to run a command",
                badge: "Bash",
                subtitle: nil,
                blocks: blocks,
                summary: firstLine(command)
            )

        case "Write":
            let path = str("file_path") ?? ""
            let content = str("content") ?? ""
            let exists = FileManager.default.fileExists(atPath: path)
            return Presentation(
                title: exists ? "Claude wants to overwrite a file" : "Claude wants to create a file",
                badge: "Write",
                subtitle: shortPath(path, cwd: cwd),
                blocks: [.code(clamp(content))],
                summary: shortPath(path, cwd: cwd)
            )

        case "Edit", "MultiEdit":
            let path = str("file_path") ?? ""
            var blocks: [Block] = []
            if let old = str("old_string"), let new = str("new_string") {
                blocks.append(.diff(removed: clampLines(old), added: clampLines(new)))
            } else if let edits = input["edits"], case .array(let items) = edits {
                for item in items.prefix(3) {
                    let old = item["old_string"]?.stringValue ?? ""
                    let new = item["new_string"]?.stringValue ?? ""
                    blocks.append(.diff(removed: clampLines(old, 6), added: clampLines(new, 6)))
                }
                if items.count > 3 {
                    blocks.append(.note("+ \(items.count - 3) more edits"))
                }
            }
            return Presentation(
                title: "Claude wants to edit a file",
                badge: tool,
                subtitle: shortPath(path, cwd: cwd),
                blocks: blocks,
                summary: shortPath(path, cwd: cwd)
            )

        case "NotebookEdit":
            let path = str("notebook_path") ?? ""
            return Presentation(
                title: "Claude wants to edit a notebook",
                badge: "NotebookEdit",
                subtitle: shortPath(path, cwd: cwd),
                blocks: [.code(clamp(str("new_source") ?? ""))],
                summary: shortPath(path, cwd: cwd)
            )

        case "Read":
            let path = str("file_path") ?? ""
            return Presentation(
                title: "Claude wants to read a file",
                badge: "Read",
                subtitle: shortPath(path, cwd: cwd),
                blocks: [],
                summary: shortPath(path, cwd: cwd)
            )

        case "WebFetch":
            let url = str("url") ?? ""
            var blocks: [Block] = [.code(url)]
            if let p = str("prompt") { blocks.append(.note(p)) }
            return Presentation(
                title: "Claude wants to fetch a web page",
                badge: "WebFetch",
                subtitle: host(of: url),
                blocks: blocks,
                summary: host(of: url) ?? url
            )

        case "WebSearch":
            let q = str("query") ?? ""
            return Presentation(
                title: "Claude wants to search the web",
                badge: "WebSearch",
                subtitle: nil,
                blocks: [.code(q)],
                summary: q
            )

        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.split(separator: "_", omittingEmptySubsequences: true).map(String.init)
                let server = parts.count > 1 ? parts[1] : "mcp"
                let name = parts.count > 2 ? parts.dropFirst(2).joined(separator: "_") : tool
                return Presentation(
                    title: "Claude wants to use \(name)",
                    badge: server,
                    subtitle: tool,
                    blocks: fields(from: input),
                    summary: tool
                )
            }
            return Presentation(
                title: "Claude wants to use \(tool)",
                badge: tool,
                subtitle: nil,
                blocks: fields(from: input),
                summary: input.inlineDescription
            )
        }
    }

    // MARK: - Helpers

    private static func fields(from input: JSONValue) -> [Block] {
        guard let obj = input.objectValue, !obj.isEmpty else { return [] }
        return obj.sorted { $0.key < $1.key }.prefix(8).map { key, value in
            .field(label: key, value: clamp(value.inlineDescription, 6))
        }
    }

    private static func clampLines(_ s: String, _ limit: Int = maxLines) -> [String] {
        let lines = s.components(separatedBy: "\n")
        if lines.count <= limit { return lines }
        return Array(lines.prefix(limit)) + ["… \(lines.count - limit) more lines"]
    }

    private static func clamp(_ s: String, _ limit: Int = maxLines) -> String {
        clampLines(s, limit).joined(separator: "\n")
    }

    private static func firstLine(_ s: String) -> String {
        s.components(separatedBy: "\n").first ?? s
    }

    private static func host(of url: String) -> String? {
        URL(string: url)?.host
    }

    /// `/Users/me/proj/src/a.ts` → `src/a.ts` inside the project, `~/…` outside.
    static func shortPath(_ path: String, cwd: String) -> String {
        guard !path.isEmpty else { return "" }
        if path == cwd {
            return abbreviateHome(path)
        }
        if path.hasPrefix(cwd + "/") {
            return String(path.dropFirst(cwd.count + 1))
        }
        return abbreviateHome(path)
    }

    private static func abbreviateHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~/" + path.dropFirst(home.count + 1) }
        return path
    }
}
