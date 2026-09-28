import Foundation

/// Editor input, including incomplete fields. Never added to the server outbox until Save.
public struct LibraryDraft: Codable, Equatable, Sendable, Identifiable {
    public let kind: String
    public let isNew: Bool
    public let baseVersion: Int64
    public let generation: String?
    public let payload: JSONValue
    public let fields: [String: String]
    public var id: String { kind + "." + (payload["id"].string ?? "") }
    public init(kind: String, isNew: Bool, baseVersion: Int64, generation: String?, payload: JSONValue, fields: [String: String] = [:]) {
        self.kind = kind; self.isNew = isNew; self.baseVersion = baseVersion; self.generation = generation; self.payload = payload; self.fields = fields
    }
    private static func file(kind: String, id: String, directory: URL) throws -> URL {
        guard ["programs", "equipment", "calendar"].contains(kind), UUID(uuidString: id) != nil else { throw WorkoutError("Некорректный черновик документа.") }
        return directory.appendingPathComponent("LibraryDrafts").appendingPathComponent(kind + "." + id + ".json")
    }
    public static func read(kind: String, id: String, directory: URL) throws -> LibraryDraft? {
        let url = try file(kind: kind, id: id, directory: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let draft = try JSONDecoder().decode(LibraryDraft?.self, from: Data(contentsOf: url))
        if let draft { guard draft.kind == kind, draft.payload["id"].string == id, draft.baseVersion >= 0 else { throw WorkoutError("Черновик повреждён; файл сохранён.") } }
        return draft
    }
    public func write(directory: URL) throws {
        guard let id = payload["id"].string else { throw WorkoutError("Нет UUID документа.") }
        _ = try Self.read(kind: kind, id: id, directory: directory)
        let url = try Self.file(kind: kind, id: id, directory: directory)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    public static func clear(kind: String, id: String, directory: URL) throws {
        let url = try file(kind: kind, id: id, directory: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        _ = try read(kind: kind, id: id, directory: directory)
        try Data("null".utf8).write(to: url, options: .atomic)
    }
    public static func recover(kind: String, payload: JSONValue, server: JSONValue, generation: String, directory: URL) throws -> LibraryDraft {
        guard !generation.isEmpty else { throw WorkoutError("Нет поколения сервера.") }
        if kind == "equipment" { try WeightProfile.validate(payload) }
        guard let id = payload["id"].string, payload["deletedAt"] == .null,
              try read(kind: kind, id: id, directory: directory) == nil else { throw WorkoutError("Сначала сохраните существующий черновик. Он не будет перезаписан.") }
        let isNew = server == .null
        guard isNew || (server["payload"]["id"].string == id && (server["version"].integer ?? 0) > 0) else { throw WorkoutError("Серверная версия документа не совпадает.") }
        var proposed = payload
        if kind == "programs" { proposed["version"] = .int(max(payload["version"].integer ?? 1, server["payload"]["version"].integer ?? 1)) }
        let fields = kind == "equipment" ? ["step": payload["stepGrams"].integer.map(Workout.formatWeight) ?? "", "weights": payload["availableGrams"].array.compactMap(\.integer).map(Workout.formatWeight).joined(separator: "; ")] : [:]
        let draft = LibraryDraft(kind: kind, isNew: isNew, baseVersion: server["version"].integer ?? 0, generation: generation, payload: proposed, fields: fields)
        let archive: JSONValue = .object(["kind": .string("document"), "path": .string("/\(kind)/\(id)"), "request": .object(["payload": payload]), "server": server, "generation": .string(generation)])
        let folder = directory.appendingPathComponent("Recovery")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(to: folder.appendingPathComponent(UUID().uuidString + ".json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try draft.write(directory: directory)
        return draft
    }
    public static func list(directory: URL) throws -> [LibraryDraft] {
        let folder = directory.appendingPathComponent("LibraryDrafts")
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.compactMap {
            try JSONDecoder().decode(LibraryDraft?.self, from: Data(contentsOf: $0))
        }.sorted { $0.id < $1.id }
    }
}
