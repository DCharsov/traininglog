import Foundation

public struct PhoneSession: Codable, Equatable, Sendable, Identifiable {
    public var workout: Workout
    public var base: JSONValue?
    public var version: Int64 = 0
    public var control: JSONValue = .object(["state": .string("phone"), "controlEpoch": .int(0)])
    public var selected: SetLocation?
    public var pending: WatchRequest?
    public var conflict: JSONValue?
    public var watchRequested = false
    public var id: String { workout.id }
    public var dirty: Bool { base != workout.json }
    public var editable: Bool { control["state"].string == "phone" && conflict == nil && pending?.method != "POST" }
    public init(workout: Workout, base: JSONValue? = nil) { self.workout = workout; self.base = base; selected = workout.next }
}
public struct PhoneDiaryState: Codable, Sendable {
    public var formatVersion = 1
    public var generation: String?
    public var programs: [JSONValue] = []
    public var archivedPrograms: [JSONValue]?
    public var equipment: [JSONValue] = []
    public var calendar: [JSONValue]?
    public var sessions: [PhoneSession] = []
    public var documentWrites: [WatchRequest]?
    public var documentConflicts: [String: JSONValue]?
    public init() {}
    public var active: PhoneSession? { sessions.first { $0.workout.active && $0.workout.json["deletedAt"] == .null } }
}

/// Native iPhone cache + immutable outbox. The published site and the watch still use the same server leases.
public actor PhoneDiary {
    private let file: URL
    private var state: PhoneDiaryState?
    public init(directory: URL) { file = directory.appendingPathComponent("phone-diary.json") }
    public func load() throws -> PhoneDiaryState {
        if let state { return state }
        if FileManager.default.fileExists(atPath: file.path) {
            let saved = try JSONDecoder().decode(PhoneDiaryState.self, from: Data(contentsOf: file))
            guard saved.formatVersion == 1 else { throw WorkoutError("Неизвестная версия дневника. Данные сохранены.") }
            for row in saved.sessions { try row.workout.validateCompatibility() }
            state = saved
        } else {
            guard !FileManager.default.fileExists(atPath: file.appendingPathExtension("previous").path) else { throw WorkoutError("Основной файл дневника отсутствует. Резервная копия сохранена; требуется восстановление.") }
            state = PhoneDiaryState()
        }
        return state!
    }
    public func recoveryArchives() throws -> [LocalRecoveryArchive] {
        try LocalRecoveryArchive.read(directory: file.deletingLastPathComponent())
    }
    /// Explicit recovery action only. Old-generation requests never migrate into the new outbox.
    public func adoptGeneration(_ generation: String, export: JSONValue) throws -> PhoneDiaryState {
        let old = try load()
        guard !generation.isEmpty, let previousGeneration = old.generation, previousGeneration != generation,
              case .array = export["sessions"], case .array = export["programs"], case .array = export["equipment"] else {
            throw WorkoutError("Нужен полный снимок другого поколения сервера.")
        }
        var next = PhoneDiaryState(); next.generation = generation
        next.programs = export["programs"].array.filter { $0["archivedAt"] == .null && $0["deletedAt"] == .null }
        next.archivedPrograms = export["programs"].array.filter { $0["archivedAt"] != .null && $0["deletedAt"] == .null }
        next.equipment = export["equipment"].array.filter { $0["archivedAt"] == .null && $0["deletedAt"] == .null }
        next.calendar = export["calendar"].array.filter { $0["archivedAt"] == .null && $0["deletedAt"] == .null }
        for payload in export["sessions"].array {
            let workout = try Workout(json: payload)
            guard !next.sessions.contains(where: { $0.id == workout.id }), !(workout.active && next.active != nil) else { throw WorkoutError("Серверный снимок содержит повторяющиеся или конкурирующие тренировки.") }
            var row = PhoneSession(workout: workout, base: payload)
            row.control = .object(["state": .string("unknown"), "controlEpoch": .int(0)])
            row.watchRequested = true
            next.sessions.append(row)
        }
        let previous = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(old))
        let archive: JSONValue = .object(["kind": .string("generation"), "previousGeneration": .string(previousGeneration),
                                          "generation": .string(generation), "diary": previous, "server": export])
        let directory = file.deletingLastPathComponent().appendingPathComponent("Recovery")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(to: directory.appendingPathComponent("generation-\(UUID().uuidString).json"), options: .atomic)
        try persist(next); return next
    }
    public func restoreMissing(_ source: Workout, generation: String) throws -> PhoneDiaryState {
        var next = try load()
        guard next.generation == generation, !generation.isEmpty,
              !source.active || next.sessions.allSatisfy({ !$0.workout.active || $0.id == source.id }) else {
            throw WorkoutError("Сначала сверьте поколение сервера и завершите другую активную тренировку.")
        }
        let previous = next.sessions.first { $0.id == source.id }
        guard previous?.pending == nil || previous?.conflict != nil else { throw WorkoutError("Прежний запрос ещё может быть в пути. Сначала дождитесь его подтверждения.") }
        try source.validateCompatibility()
        let archive: JSONValue = .object(["source": source.json, "local": previous?.workout.json ?? .null,
            "previous": try previous.map { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode($0)) } ?? .null])
        let directory = file.deletingLastPathComponent().appendingPathComponent("Recovery")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(to: directory.appendingPathComponent("restore-\(UUID().uuidString).json"), options: .atomic)
        var row = PhoneSession(workout: source)
        row.control = .object(["state": .string("unknown"), "controlEpoch": .int(0)])
        row.watchRequested = true
        row.pending = WatchRequest(path: "/sessions/\(source.id)", method: "PUT", body: .object([
            "operationId": .string(UUID().uuidString), "contractVersion": .int(2), "generation": .string(generation),
            "baseVersion": .int(0), "payload": source.json
        ]))
        next.sessions.removeAll { $0.id == source.id }; next.sessions.append(row)
        try persist(next); return next
    }
    private func persist(_ next: PhoneDiaryState) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(next)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: file.path) {
            let old = try Data(contentsOf: file)
            let previous = try JSONDecoder().decode(PhoneDiaryState.self, from: old)
            guard previous.formatVersion == 1 else { throw WorkoutError("Неизвестная версия резервной копии.") }
            for row in previous.sessions { try row.workout.validateCompatibility() }
            try old.write(to: file.appendingPathExtension("previous"), options: .atomic)
        }
        try data.write(to: file, options: .atomic); state = next
    }
    public func importServer(_ export: JSONValue, generation: String) throws -> PhoneDiaryState {
        var next = try load()
        guard next.generation == nil || next.generation == generation else { throw WorkoutError("Сервер восстановлен из копии. Локальный дневник сохранён; требуется сверка версий.") }
        next.generation = generation
        next.programs = export["programs"].array.filter { $0["deletedAt"] == .null && $0["archivedAt"] == .null }
        next.archivedPrograms = export["programs"].array.filter { $0["deletedAt"] == .null && $0["archivedAt"] != .null }
        next.equipment = export["equipment"].array.filter { $0["deletedAt"] == .null && $0["archivedAt"] == .null }
        next.calendar = export["calendar"].array.filter { $0["deletedAt"] == .null && $0["archivedAt"] == .null }
        for request in next.documentWrites ?? [] { Self.overlay(request, on: &next) }
        for payload in export["sessions"].array {
            let workout = try Workout(json: payload)
            if !next.sessions.contains(where: { $0.id == workout.id }) {
                if workout.active, next.active != nil { throw WorkoutError("На сервере и iPhone разные активные тренировки. Обе копии сохранены; сначала завершите текущую.") }
                var imported = PhoneSession(workout: workout, base: payload)
                imported.watchRequested = true // Opening the app must not transfer an existing workout unexpectedly.
                next.sessions.append(imported)
            } else if let i = next.sessions.firstIndex(where: { $0.id == workout.id }),
                      !next.sessions[i].workout.active, !next.sessions[i].dirty,
                      next.sessions[i].pending == nil, next.sessions[i].conflict == nil, !workout.active {
                next.sessions[i].workout = workout; next.sessions[i].base = payload
            }
        }
        try persist(next); return next
    }
    public func start(program: JSONValue, day: JSONValue, includeOptional: Bool = false, now: Date = Date()) throws -> PhoneDiaryState {
        var next = try load()
        guard day["archivedAt"] == .null else { throw WorkoutError("Сначала верните день из архива.") }
        guard program["archivedAt"] == .null, program["deletedAt"] == .null else { throw WorkoutError("Сначала верните программу из архива.") }
        guard next.active == nil else { throw WorkoutError("Сначала завершите текущую тренировку.") }
        let workout = try Self.makeWorkout(program: program, day: day, includeOptional: includeOptional, now: now)
        next.sessions.insert(PhoneSession(workout: workout), at: 0)
        try persist(next); return next
    }
    public static func makeWorkout(program: JSONValue, day: JSONValue, includeOptional: Bool = false, now: Date = Date()) throws -> Workout {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        var exercises: [JSONValue] = []
        for var exercise in day["exercises"].array where !exercise["optionalWeekly"].bool || includeOptional {
            guard let sets = exercise["sets"].integer, (1...30).contains(sets) else { throw WorkoutError("Неверное число подходов.") }
            exercise["rest"] = .int(RestRules.seconds(exercise))
            exercise["records"] = .array((0..<Int(sets * (exercise["unilateral"].bool ? 2 : 1))).map { index in
                var r: JSONValue = .object(["id": .string(UUID().uuidString), "status": .string("draft"), "weight": .string(""), "reps": .string(""), "rir": .string(""), "note": .string(""), "kind": .string("working"), "loadGrams": .null, "count": .null, "completedAt": .null])
                if exercise["unilateral"].bool { r["side"] = .string(index % 2 == 0 ? "left" : "right") }
                return r
            })
            exercises.append(exercise)
        }
        guard !exercises.isEmpty else { throw WorkoutError("В тренировке нет упражнений.") }
        return try Workout(json: .object(["id": .string(UUID().uuidString), "programId": program["id"], "programVersion": program["version"], "dayId": day["id"], "name": day["name"], "status": .string("active"), "startedAt": .string(ISO8601DateFormatter().string(from: now)), "completedAt": .null, "localDate": .string(formatter.string(from: now)), "timezone": .string(TimeZone.current.identifier), "revision": .int(1), "restEndsAt": .null, "exercises": .array(exercises)]))
    }
    public func apply(id: String, action: WorkoutAction, now: Date = Date()) throws -> PhoneDiaryState {
        var next = try load()
        guard let i = next.sessions.firstIndex(where: { $0.id == id }), next.sessions[i].editable else { throw WorkoutError("Тренировка сейчас на часах или требует сверки с сервером.") }
        var row = next.sessions[i]; let old = row.workout
        switch action {
        case .field(let l, let f, let value): try row.workout.setField(l, field: f, value: value)
        case .complete(let l): guard try row.workout.complete(l, now: now) else { return next }; row.selected = row.workout.next
        case .skip(let l): try row.workout.skip(l); row.selected = row.workout.next
        case .correct(let l): try row.workout.correct(l); row.selected = l
        case .select(let l):
            guard row.workout.sequence.contains(l), row.workout.record(at: l)["status"].string == "draft" else { throw WorkoutError("Выберите незавершённый подход.") }
            row.selected = l
        case .rest(let seconds): try row.workout.changeRest(seconds: seconds, now: now)
        case .finish: try row.workout.finish(now: now); row.selected = nil
        }
        switch action { case .complete, .skip, .select: if let l = row.selected { try row.workout.autofill(l) }; default: break }
        if row.workout != old { row.workout.incrementRevision() }
        next.sessions[i] = row; try persist(next); return next
    }
    /// Commit the entire editor in one disk write; validation failure leaves the old snapshot intact.
    public func saveSet(id: String, location: SetLocation, values: [String: String], complete: Bool, now: Date = Date()) throws -> PhoneDiaryState {
        var next = try load()
        guard let i = next.sessions.firstIndex(where: { $0.id == id }), next.sessions[i].editable else { throw WorkoutError("Редактирование недоступно.") }
        var row = next.sessions[i]
        if complete, row.workout.record(at: location)["status"].string == "completed" { return next }
        let old = row.workout
        for key in ["weight", "reps", "duration", "rir", "note"] {
            if let value = values[key] { try row.workout.setField(location, field: key, value: value) }
        }
        if complete {
            _ = try row.workout.complete(location, now: now)
            row.selected = row.workout.next
            if let selected = row.selected { try row.workout.autofill(selected) }
        }
        if old != row.workout { row.workout.incrementRevision() }
        next.sessions[i] = row
        try persist(next); return next
    }
    public func correctHistory(id: String, location: SetLocation, values: [String: String], expectedRecord: JSONValue? = nil) throws -> PhoneDiaryState {
        var next = try load()
        guard let i = next.sessions.firstIndex(where: { $0.id == id }), next.sessions[i].editable,
              next.sessions[i].base == nil || next.sessions[i].version > 0 else {
            throw WorkoutError("Сначала загрузите версию истории с сервера и разрешите конфликт, если он есть.")
        }
        let original = next.sessions[i].workout
        if let expectedRecord, original.record(at: location) != expectedRecord {
            throw WorkoutError("Подход изменился после открытия редактора. Черновик сохранён; сверьте новую версию перед исправлением.")
        }
        try next.sessions[i].workout.correctHistory(location, values: values)
        if next.sessions[i].workout != original { next.sessions[i].workout.incrementRevision() }
        try persist(next); return next
    }
    public func changeStructure(id: String, change: WorkoutStructureChange) throws -> PhoneDiaryState {
        var next = try load()
        guard let i = next.sessions.firstIndex(where: { $0.id == id }), next.sessions[i].editable else { throw WorkoutError("Верните управление с часов перед изменением тренировки.") }
        next.sessions[i].workout = try next.sessions[i].workout.changingStructure(change)
        if next.sessions[i].selected == nil { next.sessions[i].selected = next.sessions[i].workout.next }
        try persist(next); return next
    }
    public func setEquipment(id: String, exerciseID: String, equipment: JSONValue) throws -> PhoneDiaryState {
        var next = try load()
        guard let i = next.sessions.firstIndex(where: { $0.id == id }), next.sessions[i].editable else { throw WorkoutError("Редактирование недоступно.") }
        var payload = next.sessions[i].workout.json, all = payload["exercises"].array
        guard let e = all.firstIndex(where: { $0["id"].string == exerciseID }), !all[e]["records"].array.contains(where: { $0["status"].string == "completed" }) else { throw WorkoutError("Оборудование нельзя менять после выполненного подхода.") }
        all[e]["mode"] = equipment["mode"]
        all[e]["stepGrams"] = equipment["stepGrams"]
        all[e]["availableGrams"] = .array(equipment["availableGrams"].array)
        all[e]["equipmentId"] = equipment["id"]; all[e]["equipment"] = equipment["name"]
        payload["exercises"] = .array(all); var workout = try Workout(json: payload); workout.incrementRevision(); next.sessions[i].workout = workout
        try persist(next); return next
    }
    public func acceptSnapshot(_ snapshot: JSONValue) throws -> PhoneDiaryState {
        var next = try load()
        guard snapshot["generation"].string == next.generation, let id = snapshot["sessionId"].string,
              let version = snapshot["version"].integer, ["phone", "offered", "watch"].contains(snapshot["control"]["state"].string ?? "") else { throw WorkoutError("Несовместимое управление тренировкой.") }
        let remote = try Workout(json: snapshot["payload"])
        guard remote.id == id else { throw WorkoutError("ID тренировки не совпадает.") }
        if let i = next.sessions.firstIndex(where: { $0.id == id }) {
            var row = next.sessions[i]
            if remote.json == row.base { row.version = version }
            if row.dirty && remote.json != row.base && remote.json != row.workout.json {
                row.conflict = snapshot // Never discard an offline phone edit when another client won.
            } else if !row.dirty || remote.json == row.workout.json {
                row.workout = remote; row.base = remote.json; row.version = version
                if row.selected == nil || remote.record(at: row.selected!)["status"].string != "draft" { row.selected = remote.next }
            }
            row.control = snapshot["control"]
            if row.pending?.method == "POST", row.control["state"].string != "phone" { row.pending = nil }
            next.sessions[i] = row
        } else { var row = PhoneSession(workout: remote, base: remote.json); row.version = version; row.control = snapshot["control"]; next.sessions.append(row) }
        try persist(next); return next
    }
    public func prepareWrite() throws -> WatchRequest? {
        var next = try load()
        guard let generation = next.generation else { return nil }
        if let pending = next.sessions.filter({ $0.conflict == nil }).compactMap(\.pending).first { return pending }
        if let pending = next.documentWrites?.first(where: { next.documentConflicts?[$0.operationID] == nil }) { return pending }
        guard let i = next.sessions.firstIndex(where: { $0.dirty && $0.editable }) else { return nil }
        let row = next.sessions[i]
        guard row.base == nil || row.version > 0 else { throw WorkoutError("Сначала загрузите серверную версию тренировки.") }
        let request = WatchRequest(path: "/sessions/\(row.id)", method: "PUT", body: .object(["operationId": .string(UUID().uuidString), "contractVersion": .int(2), "generation": .string(generation), "baseVersion": .int(row.version), "payload": row.workout.json]))
        next.sessions[i].pending = request; try persist(next); return request
    }
    public func acknowledge(_ request: WatchRequest, response: JSONValue) throws -> PhoneDiaryState {
        var next = try load()
        if next.documentWrites?.contains(request) == true {
            guard response["generation"].string == next.generation, (response["version"].integer ?? 0) > (request.body["baseVersion"].integer ?? 0) else { throw WorkoutError("Неверное подтверждение документа. Очередь сохранена.") }
            Self.overlay(request, on: &next)
            next.documentWrites?.removeAll { $0 == request }
            next.documentConflicts?[request.operationID] = nil
            try persist(next); return next
        }
        guard let i = next.sessions.firstIndex(where: { $0.pending == request }), response["generation"].string == next.generation,
              let version = response["version"].integer, version > next.sessions[i].version else { throw WorkoutError("Неизвестное подтверждение; очередь сохранена.") }
        if request.method == "PUT" { next.sessions[i].base = request.body["payload"]; next.sessions[i].version = version; next.sessions[i].pending = nil }
        try persist(next); return next
    }
    public func prepareHandoff(id: String, deviceID: String) throws -> WatchRequest {
        var next = try load()
        guard let generation = next.generation, let i = next.sessions.firstIndex(where: { $0.id == id }) else { throw WorkoutError("Сначала синхронизируйте тренировку.") }
        var row = next.sessions[i]
        if let pending = row.pending { return pending }
        guard row.editable, !row.dirty, row.version > 0, row.workout.active else { throw WorkoutError("Сначала сохраните изменения.") }
        let request = WatchRequest(path: "/sessions/\(id)/watch-handoff", method: "POST", body: .object(["operationId": .string(UUID().uuidString), "generation": .string(generation), "baseVersion": .int(row.version), "controlEpoch": row.control["controlEpoch"], "sessionId": .string(id), "deviceId": .string(deviceID)]))
        row.pending = request; row.watchRequested = true; row.control["state"] = .string("preparing"); next.sessions[i] = row; try persist(next); return request
    }
    public func acknowledgeHandoff(_ request: WatchRequest, snapshot: JSONValue) throws -> PhoneDiaryState {
        let current = try load()
        guard current.sessions.contains(where: { $0.pending == request }) else { throw WorkoutError("Неизвестная передача.") }
        var next = try acceptSnapshot(snapshot)
        if let i = next.sessions.firstIndex(where: { $0.id == snapshot["sessionId"].string }) { next.sessions[i].pending = nil }
        try persist(next); return next
    }
    public func markConflict(_ request: WatchRequest, response: JSONValue) throws -> PhoneDiaryState {
        var next = try load()
        if next.documentWrites?.contains(request) == true {
            if next.documentConflicts == nil { next.documentConflicts = [:] }
            next.documentConflicts?[request.operationID] = response
        }
        if let i = next.sessions.firstIndex(where: { $0.pending == request }) { next.sessions[i].conflict = response }
        try persist(next); return next
    }
    public func saveDocument(kind: String, payload: JSONValue, version: Int64) throws -> PhoneDiaryState {
        var next = try load()
        guard ["programs", "equipment", "calendar"].contains(kind), let id = payload["id"].string, UUID(uuidString: id) != nil,
              let generation = next.generation, version >= 0, !(payload["name"].string ?? "").trimmingCharacters(in: .whitespaces).isEmpty else { throw WorkoutError("Заполните название и дождитесь первой синхронизации.") }
        let path = "/\(kind)/\(id)"
        guard !(next.documentWrites ?? []).contains(where: { $0.path == path }) else { throw WorkoutError("Предыдущее изменение этого документа ещё не подтверждено. Копия сохранена на iPhone.") }
        if kind == "programs" {
            try ProgramValidation.validate(payload)
            guard (1...30).contains(payload["days"].array.count) else { throw WorkoutError("Добавьте от 1 до 30 тренировочных дней.") }
            for day in payload["days"].array { _ = try Self.makeWorkout(program: payload, day: day, includeOptional: true) }
        } else if kind == "calendar" {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
            guard let text = payload["date"].string, let date = formatter.date(from: text), formatter.string(from: date) == text,
                  ["planned", "completed"].contains(payload["status"].string ?? "") else { throw WorkoutError("Проверьте дату и статус дня отдыха.") }
        } else {
            guard Workout.modes.contains(payload["mode"].string ?? "") else { throw WorkoutError("Проверьте способ учёта веса.") }
            try WeightProfile.validate(payload)
        }
        let request = WatchRequest(path: path, method: "PUT", body: .object(["operationId": .string(UUID().uuidString), "contractVersion": .int(2), "generation": .string(generation), "baseVersion": .int(version), "payload": payload]))
        if next.documentWrites == nil { next.documentWrites = [] }
        next.documentWrites?.append(request); Self.overlay(request, on: &next)
        try persist(next); return next
    }
    public func resolveDocument(_ request: WatchRequest, snapshot: JSONValue, generation: String, useLocal: Bool) throws -> PhoneDiaryState {
        var next = try load()
        let parts = request.path.split(separator: "/")
        guard parts.count == 2, ["programs", "equipment", "calendar"].contains(String(parts[0])),
              next.documentWrites?.contains(request) == true, next.documentConflicts?[request.operationID] != nil,
              generation == next.generation, request.body["generation"].string == generation,
              let version = snapshot["version"].integer, version > 0,
              snapshot["payload"]["id"].string == String(parts[1]) else {
            throw WorkoutError("Обновите обе версии документа. Исходный запрос сохранён.")
        }
        let archive: JSONValue = .object(["kind": .string("document"), "path": .string(request.path), "request": request.body,
                                          "server": snapshot, "conflict": next.documentConflicts?[request.operationID] ?? .null])
        let directory = file.deletingLastPathComponent().appendingPathComponent("Recovery")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(to: directory.appendingPathComponent(UUID().uuidString + ".json"), options: .atomic)
        next.documentWrites?.removeAll { $0 == request }
        next.documentConflicts?[request.operationID] = nil
        var payload = useLocal ? request.body["payload"] : snapshot["payload"]
        if useLocal, parts[0] == "programs" {
            payload["version"] = .int(max(payload["version"].integer ?? 0, snapshot["payload"]["version"].integer ?? 0) + 1)
        }
        let replacement = WatchRequest(path: request.path, method: "PUT", body: .object([
            "operationId": .string(UUID().uuidString), "contractVersion": .int(2), "generation": .string(generation),
            "baseVersion": .int(version), "payload": payload
        ]))
        if useLocal { next.documentWrites?.append(replacement) }
        Self.overlay(replacement, on: &next)
        try persist(next); return next
    }
    private static func overlay(_ request: WatchRequest, on state: inout PhoneDiaryState) {
        let payload = request.body["payload"], id = payload["id"].string
        let visible = payload["deletedAt"] == .null && payload["archivedAt"] == .null
        if request.path.hasPrefix("/programs/") {
            state.programs.removeAll { $0["id"].string == id }; if visible { state.programs.append(payload) }
            if state.archivedPrograms == nil { state.archivedPrograms = [] }
            state.archivedPrograms?.removeAll { $0["id"].string == id }
            if payload["deletedAt"] == .null && payload["archivedAt"] != .null { state.archivedPrograms?.append(payload) }
        } else if request.path.hasPrefix("/equipment/") {
            state.equipment.removeAll { $0["id"].string == id }; if visible { state.equipment.append(payload) }
        } else if request.path.hasPrefix("/calendar/") {
            if state.calendar == nil { state.calendar = [] }
            state.calendar?.removeAll { $0["id"].string == id }; if visible { state.calendar?.append(payload) }
        }
    }
    public func prepareControl(id: String, force: Bool, snapshot: JSONValue? = nil) throws -> WatchRequest {
        var next = try load()
        guard let i = next.sessions.firstIndex(where: { $0.id == id }), let generation = next.generation else { throw WorkoutError("Нет снимка тренировки.") }
        var row = next.sessions[i]
        if let snapshot {
            guard snapshot["generation"].string == generation, snapshot["sessionId"].string == id,
                  let version = snapshot["version"].integer, version > 0 else { throw WorkoutError("Снимок управления устарел.") }
            row.version = version; row.control = snapshot["control"]
        }
        guard row.pending == nil || row.conflict != nil,
              force ? ["watch", "offered"].contains(row.control["state"].string ?? "") : row.control["state"].string == "offered" else {
            throw WorkoutError("Обновите состояние управления перед возвратом.")
        }
        if row.pending != nil || row.conflict != nil {
            let archive = file.deletingLastPathComponent().appendingPathComponent("Recovery")
            try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
            try JSONEncoder().encode(row).write(to: archive.appendingPathComponent(UUID().uuidString + ".json"), options: .atomic)
        }
        let request = WatchRequest(path: "/sessions/\(id)/\(force ? "watch-force-return" : "watch-handoff/cancel")", method: "POST", body: .object([
            "operationId": .string(UUID().uuidString), "generation": .string(generation), "baseVersion": .int(row.version),
            "sessionId": .string(id), "controlEpoch": row.control["controlEpoch"], "handoffId": row.control["handoffId"]
        ]))
        row.pending = request; row.conflict = nil; row.watchRequested = true; next.sessions[i] = row
        try persist(next); return request
    }
    public func resolve(id: String, snapshot: JSONValue, source: Workout, useLocal: [String: Bool]) throws -> PhoneDiaryState {
        var next = try load()
        guard let i = next.sessions.firstIndex(where: { $0.id == id }), snapshot["sessionId"].string == id,
              snapshot["generation"].string == next.generation, snapshot["control"]["state"].string == "phone",
              let version = snapshot["version"].integer, version > 0 else { throw WorkoutError("Сначала верните управление телефону и обновите версии.") }
        var row = next.sessions[i]
        guard row.pending == nil || row.conflict != nil else { throw WorkoutError("Сначала дождитесь подтверждения очереди.") }
        let server = try Workout(json: snapshot["payload"])
        let base = source == row.workout ? try row.base.map { try Workout(json: $0) } : nil
        let merged = try RecoveryMerge.merge(local: source, server: server, base: base, useLocal: useLocal)
        // Archive before replacing either local snapshot or pending request; kept after acknowledgement too.
        let archive: JSONValue = .object(["local": row.workout.json, "source": source.json, "server": snapshot,
                                          "pending": row.pending.map { .object(["path": .string($0.path), "body": $0.body]) } ?? .null])
        let directory = file.deletingLastPathComponent().appendingPathComponent("Recovery")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(to: directory.appendingPathComponent(UUID().uuidString + ".json"), options: .atomic)
        row.workout = merged; row.base = server.json; row.version = version; row.control = snapshot["control"]
        row.conflict = nil; row.pending = nil; row.selected = merged.next; row.watchRequested = true
        next.sessions[i] = row; try persist(next); return next
    }
}
