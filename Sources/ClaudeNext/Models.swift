import Foundation

/// What the hook script POSTs to `/ask`.
struct HookPayload: Decodable {
    var toolName: String
    var toolInput: JSONValue
    var cwd: String
    var sessionId: String?
    var suggestedRule: String?
    var transcriptPath: String?

    enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case cwd
        case sessionId = "session_id"
        case suggestedRule = "suggested_rule"
        case transcriptPath = "transcript_path"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        toolName = (try? c.decode(String.self, forKey: .toolName)) ?? "Unknown"
        toolInput = (try? c.decode(JSONValue.self, forKey: .toolInput)) ?? .object([:])
        cwd = (try? c.decode(String.self, forKey: .cwd)) ?? FileManager.default.currentDirectoryPath
        sessionId = try? c.decode(String.self, forKey: .sessionId)
        suggestedRule = try? c.decode(String.self, forKey: .suggestedRule)
        transcriptPath = try? c.decode(String.self, forKey: .transcriptPath)
    }
}

/// What we send back down the still-open HTTP connection.
struct PromptDecision: Encodable {
    enum Kind: String, Encodable {
        /// Approve the call and skip Claude Code's own permission check.
        case allow
        /// Block the call and hand `message` back to Claude as the reason.
        case deny
        /// Stay out of it — Claude Code falls through to its normal prompt.
        case pass
    }

    var decision: Kind
    /// Persist `suggestedRule` so this never asks again.
    var remember: Bool = false
    var message: String? = nil
}

/// One in-flight request, owned by the main actor.
@MainActor
final class PendingRequest: Identifiable, ObservableObject {
    let id = UUID()
    let payload: HookPayload
    let receivedAt = Date()
    let presentation: Presentation

    private var responder: ((PromptDecision) -> Void)?

    init(payload: HookPayload, responder: @escaping (PromptDecision) -> Void) {
        self.payload = payload
        self.responder = responder
        self.presentation = Presentation.make(payload: payload)
    }

    var isAnswered: Bool { responder == nil }

    func answer(_ decision: PromptDecision) {
        guard let responder else { return }
        self.responder = nil
        responder(decision)
    }

    /// The client hung up (hook timed out, Claude Code was killed, …).
    func abandon() {
        responder = nil
    }
}

struct RecentDecision: Identifiable {
    let id = UUID()
    let toolName: String
    let summary: String
    let kind: PromptDecision.Kind
    let remembered: Bool
    let at = Date()
}
