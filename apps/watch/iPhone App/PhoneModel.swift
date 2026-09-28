import Foundation
import Observation
import WorkoutCore

@MainActor @Observable final class PhoneModel {
    var diary = PhoneDiaryState()
    var reservation = ReservationState()
    var reservationsEnabled = false
    private let reservationStore = ReservationStore(directory: URL.applicationSupportDirectory.appendingPathComponent(ProcessInfo.processInfo.arguments.contains("--demo") ? "PhoneDemo" : "PhoneDiary"))
    var hasReservation: Bool { reservation.pending != nil || ["preparing", "ready", "started"].contains(reservation.snapshot["state"].string ?? "") }
    var reservationReady: Bool {
        reservation.snapshot["state"].string == "ready" && !reservation.blocked && reservation.confirmedWatchEpoch == reservation.snapshot["controlEpoch"].integer
    }
    var busy = false
    var syncing = false
    var loaded = false
    var error: String?
    var status = "Дневник на iPhone"
    var signedIn = false
    var useWatch = UserDefaults.standard.object(forKey: "autoContinueOnWatch") as? Bool ?? true {
        didSet { UserDefaults.standard.set(useWatch, forKey: "autoContinueOnWatch") }
    }
    var editingSet = false
    var editorDraft: EditorDraft?
    var libraryDrafts: [LibraryDraft] = []
    private var draftDirectory: URL { EditorDraft.file.deletingLastPathComponent() }
    func loadLibraryDrafts() {
        do { libraryDrafts = try LibraryDraft.list(directory: draftDirectory) }
        catch { self.error = "Не удалось прочитать черновики документов. Файлы не изменены." }
    }
    func libraryDraft(kind: String, id: String) throws -> LibraryDraft? {
        let draft = try LibraryDraft.read(kind: kind, id: id, directory: draftDirectory)
        guard draft?.generation == nil || draft?.generation == diary.generation else { throw WorkoutError("Поколение сервера изменилось. Черновик сохранён; требуется восстановление.") }
        return draft
    }
    func stageLibraryDraft(_ draft: LibraryDraft) throws {
        try draft.write(directory: draftDirectory)
        loadLibraryDrafts()
    }
    var recoveryCopies: [JSONValue] = []
    var changedServerGeneration: String?
    var localRecoveryCopies: [LocalRecoveryArchive] = []
    var recoverySnapshot: JSONValue?
    var recoverySource: Workout?
    var recoveryMissingSource: Workout?
    var recoveryDifferences: [RecoveryDifference] = []
    let bridge = CompanionBridge()
    let health = PhoneHealth()
    var measurementPauseCommand: MeasurementPauseCommand?
    private var pauseCommandReadable = true
    private func pauseBlocksCompletion(_ id: String) -> Bool {
        (measurementControl["sessionID"].string == id && measurementControl["paused"].bool)
        || (measurementPauseCommand?.sessionID == id && measurementPauseCommand?.paused == true && (measurementPauseCommand?.expiresAt ?? .distantPast) >= Date())
    }
    var measurementControl: JSONValue { bridge.incoming["measurementControl"] }
    func requestMeasurementPause(_ paused: Bool) {
        guard pauseCommandReadable else { error = "Журнал команды паузы повреждён. Используйте управление на часах; дневник доступен."; return }
        guard !isDemo, bridge.reachable, let id = diary.active?.id,
              measurementControl["sessionID"].string == id, measurementControl["canPause"].bool,
              let revision = measurementControl["revision"].integer else { error = "Откройте TrainingLog на часах и дождитесь связи."; return }
        do {
            let command = MeasurementPauseCommand(sessionID: id, expectedRevision: revision, paused: paused, now: Date())
            try PrivateHealthFile.write(command, name: "phone-pause-command.json")
            measurementPauseCommand = command; publishCompanion()
        } catch { self.error = "Не удалось сохранить команду паузы. Она не отправлена." }
    }
    private func receiveMeasurementControl() {
        guard let command = measurementPauseCommand else { return }
        let snapshot = measurementControl
        let acknowledged = snapshot["commandID"].string == command.id.uuidString && snapshot["paused"].bool == command.paused
        let superseded = snapshot["sessionID"].string == command.sessionID && (snapshot["revision"].integer ?? -1) > command.expectedRevision && snapshot["commandID"].string != command.id.uuidString
        guard acknowledged || superseded || Date() > command.expiresAt else { return }
        do {
            try PrivateHealthFile.write(Optional<MeasurementPauseCommand>.none, name: "phone-pause-command.json")
            measurementPauseCommand = nil
            if !acknowledged { error = "Пауза не подтверждена: команда устарела или состояние изменено на часах. Проверьте экран часов." }
            publishCompanion()
        } catch { self.error = "Не удалось сохранить подтверждение паузы. Повторная доставка не переключит состояние." }
    }
    let isDemo = ProcessInfo.processInfo.arguments.contains("--demo")
    private let store: PhoneDiary
    private let api = PhoneAPI()
    private var password: String?
    private var exportedAt = Date.distantPast
    private var lastAttempt = Date.distantPast
    private var companionID: String?
    private var provisioned: JSONValue?
    private var lastComplete = Date.distantPast
    init() {
        store = PhoneDiary(directory: URL.applicationSupportDirectory.appendingPathComponent(ProcessInfo.processInfo.arguments.contains("--demo") ? "PhoneDemo" : "PhoneDiary"))
    }
    func load() async {
        guard !loaded else { return }
        do {
            diary = try await store.load()
            loadLibraryDrafts()
            reservation = try await reservationStore.load()
            editorDraft = try EditorDraft.read()
            editingSet = editorDraft != nil
            if isDemo {
                let demo = try DemoWorkout.load()
                let program: JSONValue = .object(["id": demo.json["programId"], "version": .int(1), "name": .string("Демо · силовая тренировка"), "days": .array([.object(["id": demo.json["dayId"], "name": .string("Всё тело"), "exercises": demo.json["exercises"]])])])
                diary = try await store.importServer(.object(["programs": .array([program]), "sessions": .array([]), "equipment": .array([])]), generation: "demo")
                loaded = true; status = "Демо · без отправки в историю"; return
            }
            // Optional one-time private provisioning during USB install; never part of the app bundle or Git.
            let importFile = URL.documentsDirectory.appendingPathComponent("owner-password-import.txt")
            if FileManager.default.fileExists(atPath: importFile.path) {
                let data = try Data(contentsOf: importFile)
                guard data.count <= 1024 else { throw WorkoutError("Некорректный файл входа.") }
                if try PhoneSecrets.read("owner-password") == nil { try PhoneSecrets.save(data, account: "owner-password") }
                try FileManager.default.removeItem(at: importFile)
            }
            if let data = try PhoneSecrets.read("owner-password") { password = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let data = try PhoneSecrets.read("watch-companion") { provisioned = try JSONDecoder().decode(JSONValue.self, from: data) }
            do { measurementPauseCommand = try PrivateHealthFile.read("phone-pause-command.json", as: MeasurementPauseCommand.self) }
            catch { pauseCommandReadable = false; self.error = "Не удалось прочитать команду паузы. Дневник доступен; управляйте измерением на часах." }
            bridge.onReceive = { [weak self] _ in
                self?.receiveMeasurementControl()
                Task { await self?.receiveReservationReceipt(); await self?.synchronize(force: true) }
            }
            bridge.activate(); publishCompanion()
            loaded = true
            await synchronize(force: true)
        } catch { self.error = error.localizedDescription }
    }
    func login(_ value: String) async {
        do {
            try await api.login(password: value, force: true)
            try PhoneSecrets.save(Data(value.utf8), account: "owner-password")
            password = value; exportedAt = .distantPast; await synchronize(force: true)
        } catch { self.error = error.localizedDescription }
    }
    func start(program: JSONValue, day: JSONValue, includeOptional: Bool = false) async {
        guard !hasReservation else { error = "Сначала начните подготовленную тренировку на часах или отмените резерв."; return }
        guard !busy else { return }; busy = true
        defer { busy = false }
        do { diary = try await store.start(program: program, day: day, includeOptional: includeOptional); Task { await self.synchronize(force: true) } }
        catch { self.error = error.localizedDescription }
    }
    func apply(_ action: WorkoutAction) async {
        guard !busy, let row = diary.active else { return }
        if case .complete = action, pauseBlocksCompletion(row.id) { error = "Сначала продолжите тренировку на часах."; return }
        if case .complete = action { guard Date().timeIntervalSince(lastComplete) > 0.7 else { return }; lastComplete = .now }
        busy = true; defer { busy = false }
        do { diary = try await store.apply(id: row.id, action: action); publishCompanion(); Task { await self.synchronize(force: true) } }
        catch { self.error = error.localizedDescription }
    }
    func saveSet(_ location: SetLocation, values: [String: String], complete: Bool) async -> Bool {
        guard !busy, let row = diary.active else { return false }
        if complete, pauseBlocksCompletion(row.id) { error = "Сначала продолжите тренировку на часах."; return false }
        if let draft = editorDraft, draft.sessionID != row.id || draft.location != location {
            error = "Сохранён ввод другого подхода. Откройте «Восстановление записей», прежде чем продолжать."; return false
        }
        busy = true; defer { busy = false }
        do {
            diary = try await store.saveSet(id: row.id, location: location, values: values, complete: complete)
            try EditorDraft.write(nil); editorDraft = nil
            editingSet = false
            Task { await self.synchronize(force: true) }; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func loadHistoryVersion(_ id: String) async {
        guard !isDemo, !busy else { return }
        do { diary = try await store.acceptSnapshot(api.request("/sessions/\(id)/watch-control")) }
        catch { self.error = error.localizedDescription }
    }
    func correctHistory(id: String, location: SetLocation, values: [String: String], expectedRecord: JSONValue) async -> Bool {
        guard !busy else { return false }; busy = true; defer { busy = false }
        do {
            diary = try await store.correctHistory(id: id, location: location, values: values, expectedRecord: expectedRecord)
            Task { await self.synchronize(force: true) }; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func changeStructure(_ change: WorkoutStructureChange) async {
        guard !busy, !editingSet, let row = diary.active else { return }
        busy = true; defer { busy = false }
        do {
            diary = try await store.changeStructure(id: row.id, change: change)
            Task { await self.synchronize(force: true) }
        } catch { self.error = error.localizedDescription }
    }
    func equipment(exerciseID: String, equipment: JSONValue) async {
        guard let row = diary.active else { return }
        do { diary = try await store.setEquipment(id: row.id, exerciseID: exerciseID, equipment: equipment); Task { await self.synchronize(force: true) } }
        catch { self.error = error.localizedDescription }
    }
    func stageEditor(sessionID: String, location: SetLocation, values: [String: String]) {
        if let previous = editorDraft, previous.sessionID != sessionID || previous.location != location {
            error = "Другой незавершённый ввод сохранён. Сначала откройте «Восстановление записей»."; return
        }
        let draft = EditorDraft(sessionID: sessionID, location: location, values: values)
        do { try EditorDraft.write(draft); editorDraft = draft; editingSet = true }
        catch { self.error = "Не удалось сохранить ввод на iPhone. Не закрывайте редактор и повторите сохранение." }
    }
    func archiveEditorDraft() {
        guard !busy, let draft = editorDraft else { return }
        do { try EditorDraft.archive(draft); editorDraft = nil; editingSet = false; Task { await loadLocalRecoveries() } }
        catch { self.error = "Архивировать ввод не удалось. Исходный черновик сохранён; редактирование не разблокировано." }
    }
    func reopenEditorDraft() async {
        guard !busy, let draft = editorDraft, diary.active?.id == draft.sessionID else { return }
        await apply(.select(draft.location))
    }
    func returnControl(force: Bool) async {
        guard !syncing, !busy, let row = diary.active else { return }
        busy = true
        do {
            let snapshot = try await api.request("/sessions/\(row.id)/watch-control")
            diary = try await store.acceptSnapshot(snapshot)
            _ = try await store.prepareControl(id: row.id, force: force, snapshot: snapshot)
            diary = try await store.load()
        } catch { self.error = error.localizedDescription }
        busy = false
        await synchronize(force: true)
    }
    func listRecoveries() async {
        await loadLocalRecoveries()
        guard !isDemo else { return }
        do { recoveryCopies = try await api.request("/watch/recovery").array }
        catch { self.error = error.localizedDescription }
    }
    func loadLocalRecoveries() async {
        do { localRecoveryCopies = try await store.recoveryArchives() }
        catch { self.error = "Не удалось прочитать локальный архив. Файлы не изменены." }
    }
    func adoptServerGeneration() async {
        guard !busy, !syncing, !isDemo else { return }
        busy = true; defer { busy = false }
        do {
            let before = try await api.request("/bootstrap")["generation"].string
            guard let before, before != diary.generation else { throw WorkoutError("Поколение сервера не изменилось.") }
            let serverReservation = try await api.request("/watch/reservation")["reservation"]
            guard !["preparing", "ready"].contains(serverReservation["state"].string ?? "") else {
                throw WorkoutError("На восстановленном сервере остался резерв. Сначала нужна его явная отмена или завершение; локальный дневник не заменён.")
            }
            let export = try await api.request("/export")
            if serverReservation["state"].string == "started", !export["sessions"].array.contains(where: { $0["id"] == serverReservation["reservationId"] }) {
                throw WorkoutError("Начатый резерв не имеет серверной тренировки. Данные сохранены; требуется сверка базы.")
            }
            let after = try await api.request("/bootstrap")["generation"].string
            guard before == after else { throw WorkoutError("Сервер снова изменился. Повторите сверку.") }
            if let draft = editorDraft { try EditorDraft.archive(draft); editorDraft = nil; editingSet = false }
            // Preserve reservation requests separately before leaving the old generation.
            reservation = try await reservationStore.rejectPending()
            reservation = try await reservationStore.reconcileRejected(serverSnapshot: serverReservation)
            diary = try await store.adoptGeneration(before, export: export)
            changedServerGeneration = nil; exportedAt = .now
            await loadLocalRecoveries()
            Task { await self.synchronize(force: true) }
        } catch { self.error = error.localizedDescription }
    }
    func cancelRestoredReservation() async {
        guard !busy, !syncing, !isDemo else { return }
        busy = true; defer { busy = false }
        do {
            let boot = try await api.request("/bootstrap")
            guard let generation = boot["generation"].string, generation != diary.generation else { throw WorkoutError("Используйте обычную отмену резерва текущего поколения.") }
            let snapshot = try await api.request("/watch/reservation")["reservation"]
            reservation = try await reservationStore.prepareGenerationCancellation(snapshot: snapshot, generation: generation)
            guard let request = reservation.pending else { throw WorkoutError("Нет сохранённой команды отмены.") }
            let reply = try await api.request(request.path, method: request.method, body: request.body)
            reservation = try await reservationStore.acknowledgeGenerationCancellation(request, snapshot: reply)
            status = "Старый резерв отменён. Можно принять восстановленную версию сервера."
            await loadLocalRecoveries()
        } catch { self.error = error.localizedDescription }
    }
    func restoreEditorArchive(_ payload: JSONValue) {
        guard editorDraft == nil, !busy else { error = "Сначала сохраните или архивируйте текущий ввод."; return }
        do {
            let draft = try JSONDecoder().decode(EditorDraft.self, from: JSONEncoder().encode(payload))
            guard UUID(uuidString: draft.sessionID) != nil, UUID(uuidString: draft.location.exerciseID) != nil,
                  UUID(uuidString: draft.location.setID) != nil else { throw WorkoutError("Неверный UUID черновика.") }
            try EditorDraft.write(draft); editorDraft = draft; editingSet = true
        } catch { self.error = "Не удалось восстановить черновик. Архив не изменён." }
    }
    func documentSnapshot(kind: String, id: String) async throws -> JSONValue {
        if isDemo { return .object(["version": .int(0)]) }
        return try await api.request("/\(kind)/\(id)")
    }
    func prepareArchivedDocument(_ document: LocalRecoveryArchive.Document) async throws -> LibraryDraft {
        guard !busy, !syncing, let id = document.payload["id"].string,
              !(diary.documentWrites ?? []).contains(where: { $0.path == "/\(document.kind)/\(id)" }) else { throw WorkoutError("Дождитесь отправки документа или разрешите его конфликт.") }
        busy = true; defer { busy = false }
        let generation: String
        var server: JSONValue = .null
        if isDemo { generation = "demo" }
        else {
            let boot = try await api.request("/bootstrap")
            guard let current = boot["generation"].string, current == diary.generation else { throw WorkoutError("Сначала примите поколение сервера в восстановлении.") }
            generation = current
            do { server = try await api.request("/\(document.kind)/\(id)") }
            catch let failure as PhoneAPIError where failure.status == 404 { }
            guard try await api.request("/bootstrap")["generation"].string == current else { throw WorkoutError("Поколение сервера изменилось во время чтения.") }
        }
        let draft = try LibraryDraft.recover(kind: document.kind, payload: document.payload, server: server, generation: generation, directory: draftDirectory)
        loadLibraryDrafts(); await loadLocalRecoveries()
        return draft
    }
    func resolveDocument(_ request: WatchRequest, snapshot: JSONValue, generation: String, useLocal: Bool) async -> Bool {
        guard !busy, !syncing else { return false }
        do {
            diary = try await store.resolveDocument(request, snapshot: snapshot, generation: generation, useLocal: useLocal)
            Task { await self.synchronize(force: true) }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func inspectDocumentConflict(_ request: WatchRequest) async throws -> (JSONValue, String) {
        let bootstrap = try await api.request("/bootstrap")
        guard let generation = bootstrap["generation"].string, generation == diary.generation else { throw WorkoutError("Поколение сервера изменилось. Исходные данные сохранены.") }
        return (try await api.request(request.path), generation)
    }
    func saveDocument(kind: String, payload: JSONValue, version: Int64) async -> Bool {
        do {
            diary = try await store.saveDocument(kind: kind, payload: payload, version: version)
            do { if ["programs", "equipment", "calendar"].contains(kind) { try LibraryDraft.clear(kind: kind, id: payload["id"].string ?? "", directory: draftDirectory); loadLibraryDrafts() } }
            catch { self.error = "Документ сохранён в очередь, но черновик не удалось очистить. Не создавайте повторную копию." }
            Task { await self.synchronize(force: true) }; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func inspectRecovery(sessionID: String, archiveID: String? = nil, localSource: Workout? = nil) async {
        guard !syncing, !busy else { return }
        busy = true; defer { busy = false }
        recoverySnapshot = nil; recoverySource = nil; recoveryMissingSource = nil; recoveryDifferences = []
        do {
            let source: Workout
            if let localSource { source = localSource }
            else if let archiveID { source = try Workout(json: await api.request("/watch/recovery/\(archiveID)")["payload"]) }
            else if let row = diary.sessions.first(where: { $0.id == sessionID }) { source = row.workout }
            else { throw WorkoutError("Локальная копия не найдена.") }
            let snapshot: JSONValue
            do { snapshot = try await api.request("/sessions/\(sessionID)/watch-control") }
            catch let failure as PhoneAPIError where failure.status == 404 { recoveryMissingSource = source; return }
            let row = diary.sessions.first { $0.id == sessionID }
            let base = archiveID == nil && localSource == nil ? try row?.base.map { try Workout(json: $0) } : nil
            let differences = try RecoveryMerge.differences(local: source, server: Workout(json: snapshot["payload"]), base: base)
            recoverySource = source; recoveryDifferences = differences; recoverySnapshot = snapshot
        } catch { self.error = error.localizedDescription }
    }
    func restoreMissingRecovery() async {
        guard !busy, !syncing, let source = recoveryMissingSource else { return }
        busy = true
        do {
            let boot = try await api.request("/bootstrap")
            guard let generation = boot["generation"].string, generation == diary.generation else { throw WorkoutError("Сначала примите новое поколение сервера.") }
            do {
                _ = try await api.request("/sessions/\(source.id)/watch-control")
                throw WorkoutError("Запись уже существует. Обновите сравнение версий.")
            } catch let failure as PhoneAPIError where failure.status == 404 { }
            diary = try await store.restoreMissing(source, generation: generation)
            recoveryMissingSource = nil
        } catch { self.error = error.localizedDescription }
        busy = false; await synchronize(force: true)
    }
    func resolveRecovery(choices: [String: Bool]) async {
        guard !syncing, !busy, let source = recoverySource, let snapshot = recoverySnapshot else { return }
        busy = true
        do {
            diary = try await store.resolve(id: source.id, snapshot: snapshot, source: source, useLocal: choices)
            recoverySnapshot = nil; recoverySource = nil; recoveryDifferences = []
        } catch { self.error = error.localizedDescription }
        busy = false; await synchronize(force: true)
    }
    private func publishCompanion() {
        var message: JSONValue = .object(["version": .int(1), "kind": .string("phone"), "endpoint": .string(PhoneAPI.endpoint)])
        message["finishedSessionIDs"] = .array(diary.sessions.filter { !$0.workout.active }.sorted { ($0.workout.json["startedAt"].string ?? "") > ($1.workout.json["startedAt"].string ?? "") }.prefix(32).map { .string($0.id) })
        if let provisioned { message["credentials"] = provisioned }
        if let command = measurementPauseCommand, command.expiresAt >= Date(),
           let data = try? JSONEncoder().encode(command), let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
            message["measurementPauseCommand"] = value
        }
        if hasReservation {
            message["reservationId"] = reservation.snapshot["reservationId"]
            if reservation.startRequested {
                message["startReservationID"] = reservation.snapshot["reservationId"]
                message["startReservationEpoch"] = reservation.snapshot["controlEpoch"]
            }
        }
        if let row = diary.active, ["offered", "watch"].contains(row.control["state"].string ?? "") { message["sessionId"] = .string(row.id) }
        bridge.publish(message)
    }
    private func prepareCompanion() async throws {
        guard bridge.available, bridge.incoming["kind"].string == "watch" else { return }
        let devices = try await api.request("/watch/devices")["devices"].array
        let reported = bridge.incoming["deviceId"].string
        if let reported, devices.contains(where: { $0["id"].string == reported && $0["revokedAt"] == .null && ($0["expiresAt"].integer ?? 0) > Workout.milliseconds(Date()) }) {
            companionID = reported
            if provisioned?["deviceId"].string != reported { provisioned = nil }
            return
        }
        if let provisioned, devices.contains(where: { $0["id"].string == provisioned["deviceId"].string && $0["revokedAt"] == .null && ($0["expiresAt"].integer ?? 0) > Workout.milliseconds(Date()) }) {
            publishCompanion(); return // Wait for the physical watch to acknowledge durable Keychain storage.
        }
        // No UI code: iPhone owner authorizes its already system-paired, signed companion.
        let code = try await api.request("/watch/pairing", method: "POST", body: .object([:]))
        var paired = try await api.request("/watch/pairing/redeem", method: "POST", body: .object(["code": code["code"], "name": .string("Apple Watch · iPhone")]))
        paired["endpoint"] = .string(PhoneAPI.endpoint)
        guard paired["token"].string != nil, paired["deviceId"].string != nil else { throw WorkoutError("Не удалось настроить часы автоматически.") }
        try PhoneSecrets.save(try JSONEncoder().encode(paired), account: "watch-companion")
        provisioned = paired; publishCompanion()
    }
    func synchronize(force: Bool = false) async {
        guard !isDemo, !syncing, let password, force || Date().timeIntervalSince(lastAttempt) >= 5 else { return }
        syncing = true; lastAttempt = .now; defer { syncing = false }
        do {
            try await api.login(password: password); signedIn = true
            let boot = try await api.request("/bootstrap")
            guard let generation = boot["generation"].string else { throw WorkoutError("Нет поколения сервера.") }
            if let local = diary.generation, local != generation {
                changedServerGeneration = generation
                throw WorkoutError("Сервер восстановлен из копии. Отправка остановлена; откройте «Восстановление записей».")
            }
            if Date().timeIntervalSince(exportedAt) > 30 {
                let export = try await api.request("/export")
                diary = try await store.importServer(export, generation: generation); exportedAt = .now
            }
            // Resolve current ownership before any writes. The server remains the final arbiter.
            if let row = diary.active, row.base != nil, row.pending == nil {
                diary = try await store.acceptSnapshot(api.request("/sessions/\(row.id)/watch-control"))
            }
            for _ in 0..<8 {
                guard let request = try await store.prepareWrite() else { break }
                do {
                    let response = try await api.request(request.path, method: request.method, body: request.body)
                    if request.method == "POST", let id = request.body["sessionId"].string {
                        let current = try await api.request("/sessions/\(id)/watch-control")
                        diary = try await store.acknowledgeHandoff(request, snapshot: current)
                    } else { diary = try await store.acknowledge(request, response: response) }
                } catch let failure as PhoneAPIError {
                    if [400, 409, 423, 426].contains(failure.status) { diary = try await store.markConflict(request, response: failure.body) }
                    throw failure
                }
            }
            if useWatch {
                try await prepareCompanion()
                if let row = diary.active, let companionID, row.editable, !row.dirty, !row.watchRequested, !editingSet, !busy,
                   !row.workout.exercises.contains(where: { $0["requiresEquipment"].bool && $0["mode"].string == "Unspecified" }) {
                    let request = try await store.prepareHandoff(id: row.id, deviceID: companionID)
                    diary = try await store.load()
                    _ = try await api.request(request.path, method: request.method, body: request.body)
                    let current = try await api.request("/sessions/\(row.id)/watch-control")
                    diary = try await store.acknowledgeHandoff(request, snapshot: current)
                }
            }
            if boot["watchReservationsVersion"].integer == 1 {
                try await synchronizeReservation()
            }
            publishCompanion(); status = "Синхронизировано"
        } catch {
            if let saved = try? await store.load() { diary = saved }
            status = error.localizedDescription
        }
    }
    private func synchronizeReservation() async throws {
        if let request = reservation.pending, !reservation.blocked {
            do { reservation = try await reservationStore.acknowledge(request, snapshot: api.request(request.path, method: request.method, body: request.body)) }
            catch let error as PhoneAPIError {
                if [400, 409, 423, 426].contains(error.status) { reservation = try await reservationStore.rejectPending() }
                throw error
            }
        }
        let response = try await api.request("/watch/reservation")
        reservationsEnabled = response["enabled"].bool
        if response["reservation"] != .null {
            let snapshot = response["reservation"]
            if reservation.snapshot != .null, reservation.snapshot["generation"] != snapshot["generation"], let generation = diary.generation {
                reservation = try await reservationStore.reconcileStartedGeneration(snapshot: snapshot, generation: generation)
            } else { reservation = try await reservationStore.accept(snapshot) }
        }
        if reservation.pending == nil, reservation.snapshot["state"].string == "preparing", !reservation.snapshot["phoneReady"].bool {
            let request = ReservationStore.command(reservation.snapshot, path: "/watch/reservation/phone-ready")
            reservation = try await reservationStore.prepare(request)
            reservation = try await reservationStore.acknowledge(request, snapshot: api.request(request.path, method: request.method, body: request.body))
        }
        await receiveReservationReceipt()
    }
    private func receiveReservationReceipt() async {
        guard let id = bridge.incoming["readyReservationID"].string, let epoch = bridge.incoming["readyReservationEpoch"].integer else { return }
        do { reservation = try await reservationStore.confirmWatch(id: id, epoch: epoch) }
        catch { self.error = error.localizedDescription }
    }
    func prepareOffline(program: JSONValue, day: JSONValue, includeOptional: Bool = false) async {
        guard program["archivedAt"] == .null, program["deletedAt"] == .null else { error = "Сначала верните программу из архива."; return }
        guard day["archivedAt"] == .null else { error = "Сначала верните день из архива."; return }
        guard !busy, !syncing, !hasReservation, diary.active == nil, reservationsEnabled else { return }
        guard let companionID, let generation = diary.generation else { error = "Откройте TrainingLog на часах для подтверждения системной связи."; return }
        busy = true
        do {
            let workout = try PhoneDiary.makeWorkout(program: program, day: day, includeOptional: includeOptional)
            let request = WatchRequest(path: "/watch/reservation", method: "POST", body: .object(["operationId": .string(UUID().uuidString), "generation": .string(generation), "deviceId": .string(companionID), "payload": workout.json]))
            reservation = try await reservationStore.prepare(request)
        } catch { self.error = error.localizedDescription }
        busy = false; await synchronize(force: true)
    }
    func startOfflineOnWatch() async {
        guard reservationReady else { error = "Дождитесь подтверждения сохранения на часах."; return }
        do { reservation = try await reservationStore.requestStart(); publishCompanion() }
        catch { self.error = error.localizedDescription }
    }
    func cancelReservation() async {
        guard !busy, !syncing else { return }; busy = true
        do {
            let current = try await api.request("/watch/reservation")["reservation"]
            reservation = try await reservationStore.accept(current)
            reservation = try await reservationStore.prepare(ReservationStore.command(current, path: "/watch/reservation/force-cancel"))
        } catch { self.error = error.localizedDescription }
        busy = false; await synchronize(force: true)
    }
    func reconcileReservation() async {
        guard !busy, !syncing else { return }; busy = true
        do {
            let response = try await api.request("/watch/reservation")
            reservation = try await reservationStore.reconcileRejected(serverSnapshot: response["reservation"])
        } catch { self.error = error.localizedDescription }
        busy = false; await synchronize(force: true)
    }
}
