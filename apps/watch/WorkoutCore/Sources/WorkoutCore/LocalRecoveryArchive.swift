import Foundation

public struct LocalRecoveryArchive: Identifiable, Sendable {
    public struct Document: Equatable, Sendable {
        public let kind: String
        public let payload: JSONValue
    }
    public let id: String
    public let date: Date
    public let payload: JSONValue?
    public var documents: [Document] {
        guard let payload else { return [] }
        var result: [Document] = []
        func add(_ kind: String, _ value: JSONValue) {
            guard ["programs", "equipment", "calendar"].contains(kind), let id = value["id"].string,
                  UUID(uuidString: id) != nil, value["deletedAt"] == .null else { return }
            let document = Document(kind: kind, payload: value)
            if !result.contains(document) { result.append(document) }
        }
        for kind in ["programs", "equipment", "calendar"] {
            for value in payload["diary"][kind].array { add(kind, value) }
        }
        for value in payload["diary"]["archivedPrograms"].array { add("programs", value) }
        if let path = payload["path"].string, let kind = path.split(separator: "/").first {
            add(String(kind), payload["request"]["payload"])
            add(String(kind), payload["server"]["payload"])
        }
        for request in payload["diary"]["documentWrites"].array {
            if let path = request["path"].string, let kind = path.split(separator: "/").first { add(String(kind), request["body"]["payload"]) }
        }
        return result
    }
    public var workouts: [Workout] {
        guard let payload else { return [] }
        let candidates = [payload["local"], payload["source"], payload["workout"]["json"]]
            + payload["diary"]["sessions"].array.map { $0["workout"]["json"] }
        var result: [Workout] = []
        for candidate in candidates where candidate != .null {
            if let workout = try? Workout(json: candidate), !result.contains(workout) { result.append(workout) }
        }
        return result
    }
    public var title: String {
        if payload == nil { return "Копия недоступна для чтения" }
        if payload?["values"] != .null { return "Незавершённый ввод" }
        if payload?["kind"].string == "document" { return "Версии документа" }
        if payload?["kind"].string == "generation" { return "Дневник до восстановления сервера" }
        return "Копия тренировки"
    }
    /// Reads only regular, bounded files inside the diary's Recovery folder. Never follows links.
    public static func read(directory: URL) throws -> [LocalRecoveryArchive] {
        let folder = directory.appendingPathComponent("Recovery")
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        guard try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw WorkoutError("Архив не может быть ссылкой на другое хранилище.") }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            .filter { $0.pathExtension == "json" }
            .map { file in
                let attributes = try file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                var payload: JSONValue?
                if attributes.isRegularFile == true, attributes.isSymbolicLink != true, (attributes.fileSize ?? Int.max) <= 16 * 1024 * 1024 {
                    payload = try? JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
                }
                return LocalRecoveryArchive(id: file.lastPathComponent, date: attributes.contentModificationDate ?? .distantPast, payload: payload)
            }.sorted { $0.date > $1.date }
    }
}
