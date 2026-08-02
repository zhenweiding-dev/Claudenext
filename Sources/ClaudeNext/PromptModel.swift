import AppKit
import SwiftUI

@MainActor
final class PromptModel: ObservableObject {
    @Published var pending: [PendingRequest] = []
    @Published var recent: [RecentDecision] = []
    @Published var optionDown = false
    @Published var serverError: String?
    @Published var paused = false {
        didSet { onQueueChange?() }
    }

    var config = AppConfig()

    /// Wired up by the app delegate.
    var onQueueChange: (() -> Void)?
    var onNewRequest: (() -> Void)?

    var statusLine: String {
        paused
            ? "Requests pass straight through to Claude Code."
            : "127.0.0.1:\(config.port) · \(recent.count) decision\(recent.count == 1 ? "" : "s") this session"
    }

    var rememberScopeLabel: String {
        config.rememberScope == "global" ? "your global rules" : "this project's rules"
    }

    func enqueue(_ request: PendingRequest) {
        lastCwd = request.payload.cwd
        guard !paused else {
            request.answer(PromptDecision(decision: .pass))
            return
        }
        pending.append(request)
        onQueueChange?()
        onNewRequest?()
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
        pending.removeAll { $0.id == id }
        onQueueChange?()
    }

    // MARK: Files

    func openRulesFile() {
        let scope = config.rememberScope
        let url: URL
        if scope == "global" {
            url = AppConfig.supportDirectory.appendingPathComponent("rules.json")
        } else if let cwd = pending.first?.payload.cwd ?? lastCwd {
            url = URL(fileURLWithPath: cwd)
                .appendingPathComponent(".claude")
                .appendingPathComponent("claudenext.json")
        } else {
            url = AppConfig.supportDirectory.appendingPathComponent("rules.json")
        }
        reveal(url, seed: #"{\#n  "allow": [],\#n  "deny": []\#n}\#n"#)
    }

    func openConfigFile() {
        reveal(AppConfig.configURL, seed: """
        {
          "port": \(config.port),
          "sound": \(config.sound),
          "focusOnRequest": \(config.focusOnRequest),
          "rememberScope": "\(config.rememberScope)"
        }

        """)
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
