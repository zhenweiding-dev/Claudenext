import Foundation
import Network

/// A deliberately tiny HTTP/1.1 server bound to 127.0.0.1.
///
/// `POST /ask` holds the connection open until the user answers in the UI —
/// the hook script is blocked on that response, which is what makes this a
/// drop-in replacement for the terminal prompt.
final class PromptServer {
    typealias Handler = (HookPayload, _ reply: @escaping (PromptDecision) -> Void, _ onAbandon: @escaping (@escaping () -> Void) -> Void) -> Void

    /// Answers `GET /status` with a JSON string.
    typealias StatusProvider = (_ done: @escaping (String) -> Void) -> Void

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.claudenext.server")
    private var handler: Handler?

    private(set) var port: UInt16 = 0
    var onStateChange: ((String?) -> Void)?
    var statusProvider: StatusProvider?

    func start(port: UInt16, handler: @escaping Handler) throws {
        self.handler = handler
        self.port = port

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback),
                                                 port: NWEndpoint.Port(rawValue: port)!)

        let listener = try NWListener(using: params)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                self?.onStateChange?("Port \(port) unavailable — \(error.localizedDescription)")
            case .ready:
                self?.onStateChange?(nil)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            Connection(conn: conn,
                       queue: self.queue,
                       handler: self.handler,
                       statusProvider: self.statusProvider).begin()
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}

// MARK: - One connection

private final class Connection {
    private let conn: NWConnection
    private let queue: DispatchQueue
    private let handler: PromptServer.Handler?
    private let statusProvider: PromptServer.StatusProvider?

    private var buffer = Data()
    private var didRoute = false
    private var abandonCallback: (() -> Void)?
    /// Retain ourselves for the (possibly minutes-long) lifetime of the request.
    private var selfRef: Connection?

    init(conn: NWConnection,
         queue: DispatchQueue,
         handler: PromptServer.Handler?,
         statusProvider: PromptServer.StatusProvider?) {
        self.conn = conn
        self.queue = queue
        self.handler = handler
        self.statusProvider = statusProvider
    }

    func begin() {
        selfRef = self
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.clientWentAway()
            default:
                break
            }
        }
        conn.start(queue: queue)
        receive()
    }

    private func receive() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { self.buffer.append(data) }

            if !self.didRoute, let request = self.parse() {
                self.didRoute = true
                self.route(request)
                // Keep reading so we notice the client hanging up while we wait.
                self.drain()
                return
            }
            if isComplete || error != nil {
                self.clientWentAway()
                self.conn.cancel()
                return
            }
            self.receive()
        }
    }

    /// Post-routing reads: we only care about EOF.
    private func drain() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 14) { [weak self] _, _, isComplete, error in
            guard let self else { return }
            if isComplete || error != nil {
                self.clientWentAway()
                return
            }
            self.drain()
        }
    }

    private func clientWentAway() {
        guard let cb = abandonCallback else { return }
        abandonCallback = nil
        cb()
        selfRef = nil
    }

    // MARK: Parsing

    private struct Request {
        var method: String
        var path: String
        var body: Data
    }

    private func parse() -> Request? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst().split(separator: " ").map(String.init)
        guard requestLine.count >= 2 else { return nil }

        var contentLength = 0
        var expectsContinue = false
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name == "content-length" { contentLength = Int(value) ?? 0 }
            if name == "expect", value.lowercased() == "100-continue" { expectsContinue = true }
        }

        let bodyStart = headerEnd.upperBound
        let available = buffer.distance(from: bodyStart, to: buffer.endIndex)

        if expectsContinue && available < contentLength {
            conn.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8),
                      completion: .contentProcessed { _ in })
        }
        guard available >= contentLength else { return nil }

        let body = buffer[bodyStart..<buffer.index(bodyStart, offsetBy: contentLength)]
        return Request(method: requestLine[0].uppercased(), path: requestLine[1], body: Data(body))
    }

    // MARK: Routing

    private func route(_ request: Request) {
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path

        switch (request.method, path) {
        case ("GET", "/health"):
            respond(json: #"{"ok":true,"app":"ClaudeNext"}"#)

        case ("GET", "/status"):
            guard let statusProvider else {
                respond(json: #"{"pending":0}"#)
                return
            }
            statusProvider { [weak self] json in
                self?.queue.async { self?.respond(json: json) }
            }

        case ("POST", "/ask"):
            guard let payload = try? JSONDecoder().decode(HookPayload.self, from: request.body) else {
                respond(json: #"{"decision":"pass","error":"bad payload"}"#, status: "400 Bad Request")
                return
            }
            guard let handler else {
                respond(json: #"{"decision":"pass"}"#)
                return
            }
            var replied = false
            let lock = NSLock()
            handler(
                payload,
                { [weak self] decision in
                    lock.lock(); defer { lock.unlock() }
                    guard !replied else { return }
                    replied = true
                    let data = (try? JSONEncoder().encode(decision)) ?? Data(#"{"decision":"pass"}"#.utf8)
                    self?.queue.async {
                        self?.respond(json: String(data: data, encoding: .utf8) ?? #"{"decision":"pass"}"#)
                    }
                },
                { [weak self] onAbandon in
                    self?.queue.async { self?.abandonCallback = onAbandon }
                }
            )

        default:
            respond(json: #"{"error":"not found"}"#, status: "404 Not Found")
        }
    }

    private func respond(json: String, status: String = "200 OK") {
        abandonCallback = nil
        let body = Data(json.utf8)
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { [weak self] _ in
            self?.conn.cancel()
            self?.selfRef = nil
        })
    }
}
