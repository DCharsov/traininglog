import Foundation
import WorkoutCore

struct EditorDraft: Codable, Equatable {
    let sessionID: String
    let location: SetLocation
    let values: [String: String]
    var originalRecord: JSONValue? = nil
    static var file: URL { URL.applicationSupportDirectory.appendingPathComponent(ProcessInfo.processInfo.arguments.contains("--demo") ? "PhoneDemo" : "PhoneDiary").appendingPathComponent("editor-draft.json") }
    static func read(from file: URL = file) throws -> EditorDraft? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(EditorDraft?.self, from: Data(contentsOf: file))
    }
    static func write(_ draft: EditorDraft?, to file: URL = file) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func archive(_ draft: EditorDraft) throws {
        let directory = file.deletingLastPathComponent().appendingPathComponent("Recovery")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: directory.appendingPathComponent("editor-\(UUID().uuidString).json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try write(nil)
    }
}
