import Foundation

/// Deliberately separate from the diary/outbox and excluded from device backups.
enum PrivateHealthFile {
    static func url(_ name: String) throws -> URL {
        let folder = ProcessInfo.processInfo.arguments.contains("--demo") ? "PrivateHealthDemo" : "PrivateHealth"
        var directory = URL.applicationSupportDirectory.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try directory.setResourceValues(attributes)
        return directory.appendingPathComponent(name)
    }
    static func read<T: Decodable>(_ name: String, as: T.Type) throws -> T? {
        let file = try url(name)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: file))
    }
    static func write<T: Encodable>(_ value: T, name: String) throws {
        try JSONEncoder().encode(value).write(to: url(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
