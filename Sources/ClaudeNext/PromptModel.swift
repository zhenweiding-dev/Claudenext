import AppKit
import SwiftUI

@MainActor
final class PromptModel: ObservableObject {
    @Published var pending: [PendingRequest] = []
    @Published var recent: [RecentDecision] = []
    @Published var optionDown = false
    @Published var serverError: String?
    /// Which card the keyboard acts on. Every pending request is on screen at
    /// once, so exactly one of them owns ↩ / ⌘A / esc.
    @Published var focusedID: UUID?
    /// How tall the panel may grow, measured from the menu bar to the bottom of
    /// the screen. The list scrolls within this so content is never clipped.
    @Published var maxPanelHeight: CGFloat = 520
    @Published var paused = false {
        didSet { onQueueChange?() }
    }

    @Published var config = AppConfig()
    /// Mutate and persist in one step. Everything except `port` takes effect
    /// immediately — the app reads its own copy, and the hook re-reads the file
    /// on every call.
    func editConfig(_ change: (inout AppConfig) -> Void) {
        var updated = config
        change(&updated)
        guard updated != config else { return }
        config = updated
        updated.save()
        onConfigChange?()
    }

    // MARK: What a project asks about

    /// Per-project `intercept` lists, keyed by cwd. Absent means the project
    /// has no override on disk and inherits the global list.
    @Published private(set) var projectIntercept: [String: [String]] = [:]

    func interceptList(for cwd: String) -> [String] {
        projectIntercept[cwd] ?? config.intercept
    }

    func projectHasOverride(_ cwd: String) -> Bool {
        projectIntercept[cwd] != nil
    }

    /// Writes the project's own file. The first toggle materialises the whole
    /// effective list, so what you see is what lands on disk.
    func toggleProjectIntercept(_ tool: String, cwd: String) {
        var list = interceptList(for: cwd)
        if let index = list.firstIndex(of: tool) {
            list.remove(at: index)
        } else {
            list.append(tool)
        }
        projectIntercept[cwd] = list
        ProjectScope.setIntercept(list, cwd: cwd)
    }

    /// Wired up by the app delegate.
    var onQueueChange: (() -> Void)?
    var onNewRequest: (() -> Void)?
    var onConfigChange: (() -> Void)?

    var statusLine: String {
        paused
            ? "Requests pass straight through to Claude Code."
            : "127.0.0.1:\(config.port) · \(recent.count) decision\(recent.count == 1 ? "" : "s") this session"
    }

    func enqueue(_ request: PendingRequest) {
        lastCwd = request.payload.cwd
        guard !paused else {
            request.answer(PromptDecision(decision: .pass))
            return
        }
        pending.append(request)
        if focusedID == nil { focusedID = request.id }
        let cwd = request.payload.cwd
        if projectIntercept[cwd] == nil,
           let override = ProjectScope.load(cwd: cwd).intercept {
            projectIntercept[cwd] = override
        }
        onQueueChange?()
        onNewRequest?()
    }

    // MARK: Focus

    func focusNext() { moveFocus(by: 1) }
    func focusPrevious() { moveFocus(by: -1) }

    private func moveFocus(by delta: Int) {
        guard pending.count > 1 else { return }
        let current = pending.firstIndex { $0.id == focusedID } ?? 0
        let next = (current + delta + pending.count) % pending.count
        focusedID = pending[next].id
    }

    func resolve(_ request: PendingRequest, with decision: PromptDecision) {
        request.answer(decision)
        if decision.decision != .pass {
            recent.insert(
                RecentDecision(toolName: request.presentation.badge,
                               summary: request.presentation.summary,
                               kind: decision.decision,
                               remembered: decision.remember),
                at: 0
            )
            if recent.count > 30 { recent.removeLast(recent.count - 30) }
        }
        drop(request.id)
    }

    /// The hook gave up or Claude Code exited.
    func abandon(_ id: UUID) {
        pending.first { $0.id == id }?.abandon()
        drop(id)
    }

    private func drop(_ id: UUID) {
        let index = pending.firstIndex { $0.id == id }
        pending.removeAll { $0.id == id }
        if focusedID == id {
            // Keep the focus where the answered card was, not back at the top.
            if let index, !pending.isEmpty {
                focusedID = pending[min(index, pending.count - 1)].id
            } else {
                focusedID = pending.first?.id
            }
        }
        onQueueChange?()
    }

    // MARK: Files

    /// Opens the project's own permission list — the one place rules live.
    func openRulesFile() {
        guard let cwd = pending.first?.payload.cwd ?? lastCwd else { return }
        let url = URL(fileURLWithPath: cwd)
            .appendingPathComponent(".claude")
            .appendingPathComponent("settings.local.json")
        reveal(url, seed: "{\n  \"permissions\": {\n    \"allow\": [],\n    \"deny\": []\n  }\n}\n")
    }

    func openConfigFile() {
        // Make sure the file exists and is complete before handing it over.
        config.save()
        NSWorkspace.shared.open(AppConfig.configURL)
    }

    /// Which project the panel last spoke for, so "Rules…" opens the right file.
    private var lastCwd: String?

    private func reveal(_ url: URL, seed: String) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            try? seed.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }
}
