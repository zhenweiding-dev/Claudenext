import Foundation

struct AppConfig: Decodable {
    var port: UInt16 = 4471
    var sound: Bool = true
    /// Bring the popover to the keyboard when a request arrives.
    var focusOnRequest: Bool = true
    /// Where "Always allow" writes its rule: "project" or "global".
    var rememberScope: String = "project"

    static var configURL: URL {
        supportDirectory.appendingPathComponent("config.json")
    }

    static var supportDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claudenext")
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return cfg
    }
}

extension AppConfig {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        if let v = try? c.decode(UInt16.self, forKey: .port) { port = v }
        if let v = try? c.decode(Bool.self, forKey: .sound) { sound = v }
        if let v = try? c.decode(Bool.self, forKey: .focusOnRequest) { focusOnRequest = v }
        if let v = try? c.decode(String.self, forKey: .rememberScope) { rememberScope = v }
    }

    enum CodingKeys: String, CodingKey {
        case port, sound, focusOnRequest, rememberScope
    }
}
