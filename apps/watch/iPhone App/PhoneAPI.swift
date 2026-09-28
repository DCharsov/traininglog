import Foundation
import Security
import WorkoutCore

enum PhoneSecrets {
    static func read(_ account: String) throws -> Data? {
        var query = base(account); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw WorkoutError("Не удалось открыть Keychain.") }
        return result as? Data
    }
    static func save(_ data: Data, account: String) throws {
        var query = base(account)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data; query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw WorkoutError("Не удалось сохранить безопасный вход.") }
    }
    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ru.dcharsov.TrainingLogWatch.iphone", kSecAttrAccount as String: account]
    }
}
struct PhoneAPIError: LocalizedError {
    let status: Int
    let body: JSONValue
    var errorDescription: String? {
        if let message = body["message"].string, !message.isEmpty { return message }
        return status == 401 ? "Нужен вход в дневник на iPhone." : "Сервер не принял запрос (\(status)). Локальные записи сохранены."
    }
}
actor PhoneAPI {
    static let endpoint = "https://cleargate.ru/training/api"
    private let session: URLSession
    private var csrf = ""
    private var loggedIn = false
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config, delegate: PhoneNoRedirects(), delegateQueue: nil)
    }
    func login(password: String, force: Bool = false) async throws {
        if loggedIn && !force { return }
        let state = try await request("/auth/state"); csrf = state["token"].string ?? ""
        _ = try await request("/auth/login", method: "POST", body: .object(["password": .string(password)]))
        let signed = try await request("/auth/state"); csrf = signed["token"].string ?? ""
        guard signed["authenticated"].bool else { throw WorkoutError("Вход не подтверждён.") }
        loggedIn = true
    }
    func request(_ path: String, method: String = "GET", body: JSONValue? = nil) async throws -> JSONValue {
        guard path.hasPrefix("/"), !path.contains(".."), let url = URL(string: Self.endpoint + path) else { throw WorkoutError("Неверный адрес API.") }
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if method != "GET" { request.setValue(csrf, forHTTPHeaderField: "X-CSRF-TOKEN") }
        if let body { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; request.httpBody = try encoder.encode(body) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count <= 20_000_000 else { throw WorkoutError("Ответ сервера слишком большой.") }
        let value = data.isEmpty ? JSONValue.null : ((try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null)
        guard (200..<300).contains(http.statusCode) else { if http.statusCode == 401 { loggedIn = false }; throw PhoneAPIError(status: http.statusCode, body: value) }
        return value
    }
}
private final class PhoneNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
