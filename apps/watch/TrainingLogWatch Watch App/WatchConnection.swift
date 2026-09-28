import Foundation
import Security
import WorkoutCore

struct WatchCredentials: Codable, Sendable {
    let endpoint: String
    let deviceID: String
    let token: String
    let expiresAt: Int64
}

enum WatchKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ru.dcharsov.TrainingLogWatch", kSecAttrAccount as String: "watch-api-v1"]
    }
    static func load() throws -> WatchCredentials? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw WorkoutError("Не удалось открыть защищённое подключение (\(status)).") }
        return try JSONDecoder().decode(WatchCredentials.self, from: data)
    }
    static func save(_ credentials: WatchCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var create = query
            create[kSecValueData as String] = data
            create[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(create as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw WorkoutError("Не удалось сохранить подключение (\(status)). Повторите подключение; тренировка сохранена.") }
    }
    static func pendingLink() throws -> WatchCredentials? {
        var lookup = query; lookup[kSecAttrAccount as String] = "watch-pending-link-v1"
        lookup[kSecReturnData as String] = true; lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw WorkoutError("Не удалось открыть запрос подключения.") }
        return try JSONDecoder().decode(WatchCredentials.self, from: data)
    }
    static func savePendingLink(_ credentials: WatchCredentials) throws {
        var key = query; key[kSecAttrAccount as String] = "watch-pending-link-v1"
        let data = try JSONEncoder().encode(credentials)
        var status = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            key[kSecValueData as String] = data
            key[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(key as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw WorkoutError("Не удалось сохранить запрос подключения.") }
    }
    static func newLink(endpoint: String) throws -> WatchCredentials {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw WorkoutError("Не удалось создать безопасное подключение.") }
        return WatchCredentials(endpoint: endpoint, deviceID: UUID().uuidString, token: bytes.map { String(format: "%02X", $0) }.joined(), expiresAt: Workout.milliseconds(Date()) + 120_000)
    }
}

actor WatchHTTPTransport: WatchTransport {
    let endpoint: URL
    let token: String?
    init(endpoint: String, token: String?) throws {
        guard let url = URL(string: endpoint), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw WorkoutError("Нужен адрес API с HTTPS без пароля и параметров.")
        }
        self.endpoint = url; self.token = token
    }
    func send(_ request: WatchRequest) async throws -> JSONValue {
        guard request.path.hasPrefix("/watch/"), !request.path.contains("..") else { throw WorkoutError("Недопустимый маршрут.") }
        let url = endpoint.appendingPathComponent(String(request.path.dropFirst()))
        var outgoing = URLRequest(url: url)
        outgoing.httpMethod = request.method
        outgoing.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { outgoing.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if request.method != "GET" {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            outgoing.httpBody = try encoder.encode(request.body) // Stable across process restarts for receipt hashing.
        }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config, delegate: WatchNoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: outgoing)
        guard data.count <= 2_000_000, let http = response as? HTTPURLResponse else { throw WorkoutError("Некорректный ответ сервера.") }
        let body = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
        guard (200..<300).contains(http.statusCode) else {
            throw WatchHTTPError(status: http.statusCode, response: body, retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
        }
        return body
    }
}

private final class WatchNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
