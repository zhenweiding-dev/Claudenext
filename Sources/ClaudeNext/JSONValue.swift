import Foundation

/// Minimal JSON tree so we can render arbitrary `tool_input` payloads without
/// knowing every tool's schema up front.
enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Double.self) {
            self = .number(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([JSONValue].self) {
            self = .array(v)
        } else if let v = try? c.decode([String: JSONValue].self) {
            self = .object(v)
        } else {
            self = .null
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    /// Compact one-line rendering, used for unknown tool inputs.
    var inlineDescription: String {
        switch self {
        case .string(let s): return s
        case .number(let d): return d == d.rounded() ? String(Int(d)) : String(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let a): return "[" + a.map(\.inlineDescription).joined(separator: ", ") + "]"
        case .object(let o):
            let body = o.sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.inlineDescription)" }
                .joined(separator: ", ")
            return "{" + body + "}"
        }
    }
}
