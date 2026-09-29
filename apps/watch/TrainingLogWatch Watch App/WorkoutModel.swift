import Foundation
import Observation
import UserNotifications
import WatchKit
import WorkoutCore

@MainActor @Observable
final class WorkoutModel {
    var state: WorkoutState?
    var reservation = ReservationState()
    private let reservationStore = ReservationStore(directory: URL.applicationSupportDirectory.appendingPathComponent("Workout"))
    var busy = false
    var ready = false
    var error: String?
    var notificationStatus = ""
    var notificationPermission: UNAuthorizationStatus?
    var connectionStatus = "Не подключено"
    var connected = false
    let companionBridge = CompanionBridge()
    let health = WatchHealth.shared
    private var companionStarted = false
    private var companionUpdating = false
    var syncing = false
    var linking = false
    var linkLabel = ""
    var linkStatus = ""
    var endpoint = "https://cleargate.ru/training/api"
    private let store: WorkoutStore
    private let engine: WatchSyncEngine
    private var credentials: WatchCredentials?
    private var nextAttempt = Date.distantPast
    private var failures = 0
    private var lastCompletion = Date.distantPast
    private var scheduledEnd: Int64?
    private var notificationsInitialized = false

    init() {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("Workout", isDirectory: true)
        let store = WorkoutStore(directory: directory)
        self.store = store
        engine = WatchSyncEngine(store: store)
    }
    func load() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            state = try await store.load(); ready = true
            reservation = try await reservationStore.load()
            do {
                credentials = try WatchKeychain.load(); connected = credentials != nil
                if let credentials { endpoint = credentials.endpoint; connectionStatus = "Подключено" }
            } catch {
                connectionStatus = error.localizedDescription // Local workouts remain usable if Keychain is temporarily locked.
            }
            await updateNotification()
            if !companionStarted {
                companionStarted = true
                health.onControlChange = { [weak self] in self?.publishCompanionState() }
                companionBridge.onReceive = { [weak self] _ in Task { await self?.companionTick() } }
                companionBridge.activate()
            }
            publishCompanionState()
            await health.reconcile(state)
        }
        catch { self.error = error.localizedDescription }
    }
    private func publishCompanionState() {
        var message: JSONValue = .object(["version": .int(1), "kind": .string("watch")])
        if let id = health.activeID { message["measurementSessionID"] = .string(id) }
        message["measurementControl"] = health.pauseSnapshot
        if let credentials { message["deviceId"] = .string(credentials.deviceID) }
        if reservation.snapshot["state"].string == "ready", !reservation.blocked {
            message["readyReservationID"] = reservation.snapshot["reservationId"]
            message["readyReservationEpoch"] = reservation.snapshot["controlEpoch"]
        }
        if let state, !state.isDemo { message["sessionId"] = .string(state.workout.id); message["revision"] = .int(state.localRevision); message["control"] = .string(state.sync?.controlState ?? "") }
        companionBridge.publish(message)
    }
    func companionTick() async {
        guard !companionUpdating, !syncing else { return }
        let message = companionBridge.incoming
        guard message["kind"].string == "phone" else { return }
        companionUpdating = true; defer { companionUpdating = false }
        do {
            if let active = health.activeID, message["finishedSessionIDs"].array.contains(.string(active)) { await health.finish() }
            if message["measurementPauseCommand"] != .null {
                let command = try JSONDecoder().decode(MeasurementPauseCommand.self, from: JSONEncoder().encode(message["measurementPauseCommand"]))
                health.applyPause(command)
            }
            let incoming = message["credentials"]
            if let token = incoming["token"].string, let deviceID = incoming["deviceId"].string,
               let url = incoming["endpoint"].string, let expiresAt = incoming["expiresAt"].integer, deviceID != credentials?.deviceID {
                _ = try WatchHTTPTransport(endpoint: url, token: token)
                guard incoming["protocolVersion"].integer == 1, incoming["contractVersion"].integer == 2 else { throw WorkoutError("Обновите приложение iPhone.") }
                if let state, !state.isDemo, state.sync?.controlState != "phone", state.sync?.recovered != true {
                    throw WorkoutError("Сначала отправьте сохранённую тренировку прежнего подключения. Данные не заменены.")
                }
                let value = WatchCredentials(endpoint: url, deviceID: deviceID, token: token, expiresAt: expiresAt)
                try WatchKeychain.save(value); credentials = value; endpoint = url; connected = true
                connectionStatus = "iPhone настроил связь автоматически"; failures = 0; nextAttempt = .distantPast
            }
            publishCompanionState()
            if message["startReservationID"] == reservation.snapshot["reservationId"],
               message["startReservationEpoch"] == reservation.snapshot["controlEpoch"], message["startReservationID"] != .null {
                await startReserved()
            }
            if let id = message["sessionId"].string, connected,
               state?.workout.id != id || state?.isDemo == true || state?.sync?.controlState == "phone" || state?.sync?.recovered == true {
                await receive()
            }
        } catch { connectionStatus = error.localizedDescription }
    }
    func demo() async {
        guard ready, !busy else { return }
        busy = true
        defer { busy = false }
        do { state = try await store.beginDemo(DemoWorkout.load()) }
        catch { self.error = error.localizedDescription }
    }
    func apply(_ action: WorkoutAction) async -> Bool {
        guard ready, !busy else { return false }
        if case .complete = action, let state, health.pauseBlocksSets(sessionID: state.workout.id) { error = "Сначала продолжите тренировку в разделе «Здоровье»."; return false }
        if case .complete = action {
            guard Date().timeIntervalSince(lastCompletion) > 0.7 else { return false }
            lastCompletion = Date()
        }
        busy = true
        defer { busy = false }
        do {
            state = try await store.apply(action)
            await health.reconcile(state)
            await updateNotification()
            Task { await synchronize() }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func enableNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            notificationStatus = granted ? "Уведомления разрешены" : "Без уведомлений — запись подходов работает"
            await refreshNotificationPermission()
            scheduledEnd = nil
            await updateNotification()
        } catch { notificationStatus = error.localizedDescription }
    }
    func refreshNotificationPermission() async {
        notificationPermission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    var editable: Bool { state?.isDemo == true || (state?.sync?.controlState == "watch" && state?.sync?.returning == false && state?.sync?.conflict == nil) }
    var deliveryStatus: String {
        guard let state, !state.isDemo, let sync = state.sync else { return "Сохранено на часах" }
        if sync.recovered { return "Копия сохранена в архиве сервера" }
        if sync.conflict != nil { return "Конфликт — локальная копия сохранена" }
        if sync.returning { return "Возврат ждёт доставки записей" }
        if sync.controlState == "offered" { return "Подтверждаем приём тренировки" }
        if sync.controlState == "phone" { return "Управление возвращено телефону" }
        return sync.pending == nil && sync.basePayload == state.workout.json ? "Отправлено" : "Сохранено на часах"
    }
    func pair(code: String) async -> Bool {
        guard !syncing else { return false }
        syncing = true
        defer { syncing = false }
        do {
            let transport = try WatchHTTPTransport(endpoint: endpoint, token: nil)
            let response = try await transport.send(WatchRequest(path: "/watch/pairing/redeem", method: "POST", body: .object(["code": .string(code), "name": .string("Apple Watch") ])))
            guard let token = response["token"].string, let deviceID = response["deviceId"].string, let expiresAt = response["expiresAt"].integer,
                  response["protocolVersion"].integer == 1, response["contractVersion"].integer == 2 else { throw WorkoutError("Некорректное подтверждение подключения.") }
            let credentials = WatchCredentials(endpoint: endpoint, deviceID: deviceID, token: token, expiresAt: expiresAt)
            try WatchKeychain.save(credentials)
            self.credentials = credentials; connected = true; failures = 0; nextAttempt = .distantPast
            connectionStatus = "Подключено. Передайте тренировку с телефона."
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func linkWithoutCode() async {
        guard !linking, !syncing else { return }
        linking = true; error = nil; linkLabel = ""
        defer { linking = false }
        do {
            let saved = try WatchKeychain.pendingLink()
            var pending: WatchCredentials
            if let saved, saved.endpoint == endpoint, saved.deviceID != credentials?.deviceID { pending = saved }
            else { pending = try WatchKeychain.newLink(endpoint: endpoint); try WatchKeychain.savePendingLink(pending) }
            let transport = try WatchHTTPTransport(endpoint: pending.endpoint, token: nil)
            var body: JSONValue = .object(["id": .string(pending.deviceID), "token": .string(pending.token), "name": .string("Apple Watch")])
            linkStatus = "Ищем телефон…"
            var response: JSONValue
            do { response = try await transport.send(WatchRequest(path: "/watch/link/request", method: "POST", body: body)) }
            catch let failure as WatchHTTPError where failure.response["error"].string == "request_expired" || failure.status == 401 {
                pending = try WatchKeychain.newLink(endpoint: endpoint); try WatchKeychain.savePendingLink(pending)
                body = .object(["id": .string(pending.deviceID), "token": .string(pending.token), "name": .string("Apple Watch")])
                response = try await transport.send(WatchRequest(path: "/watch/link/request", method: "POST", body: body))
            }
            linkLabel = response["label"].string ?? ""
            linkStatus = "На телефоне нажмите «Это мои часы». Сверьте слова на обоих экранах."
            for _ in 0..<60 {
                try Task.checkCancellation()
                if response["state"].string == "approved" {
                    guard let expires = response["expiresAt"].integer, response["requestId"].string == pending.deviceID,
                          response["protocolVersion"].integer == 1, response["contractVersion"].integer == 2 else { throw WorkoutError("Некорректное подтверждение подключения.") }
                    let credentials = WatchCredentials(endpoint: pending.endpoint, deviceID: pending.deviceID, token: pending.token, expiresAt: expires)
                    try WatchKeychain.save(credentials)
                    self.credentials = credentials; connected = true; failures = 0; nextAttempt = .distantPast
                    linkStatus = "Подключено. Можно передавать тренировку."; connectionStatus = linkStatus
                    return
                }
                try await Task.sleep(for: .seconds(2))
                response = try await transport.send(WatchRequest(path: "/watch/link/status", method: "POST", body: body))
            }
            linkStatus = "Время ожидания истекло. Повторите подключение на телефоне."
        } catch is CancellationError { linkStatus = "Запрос сохранён. Нажмите «Подключить» для продолжения." }
        catch let failure as WatchHTTPError {
            switch failure.status {
            case 409, 410: linkStatus = "На телефоне нажмите «Подключить часы», затем повторите здесь."
            case 404: linkStatus = "Обновите сервер дневника для подключения без кода."
            default: linkStatus = failure.localizedDescription
            }
        } catch { linkStatus = "Нет связи. Повторите подключение; данные тренировки сохранены." }
    }
    func receive() async {
        guard let credentials, !syncing else { return }
        syncing = true
        do {
            let transport = try WatchHTTPTransport(endpoint: credentials.endpoint, token: credentials.token)
            state = try await engine.receive(using: transport, deviceID: credentials.deviceID)
            connectionStatus = state == nil ? "Нет предложенной тренировки" : "Тренировка сохранена на часах"
        } catch { self.error = error.localizedDescription }
        syncing = false
        await synchronize(force: true)
    }
    func synchronize(force: Bool = false) async {
        guard let credentials, !syncing, state?.isDemo != true || companionBridge.incoming["reservationId"] != .null, force || Date() >= nextAttempt else { return }
        syncing = true
        defer { syncing = false }
        do {
            let transport = try WatchHTTPTransport(endpoint: credentials.endpoint, token: credentials.token)
            _ = try await engine.synchronize(using: transport, deviceID: credentials.deviceID)
            state = try await store.load()
            if companionBridge.incoming["reservationId"] != .null || reservation.snapshot != .null {
                try await syncReservation(transport: transport)
            }
            failures = 0; nextAttempt = .distantPast; connectionStatus = "Связь с сервером работает"
            publishCompanionState()
            await updateNotification()
        } catch {
            if let saved = try? await store.load() { state = saved }
            failures += 1
            let delay = (error as? WatchHTTPError)?.retryAfter ?? min(300, pow(2, Double(min(failures, 8))) * 2 + Double.random(in: 0...3))
            nextAttempt = Date().addingTimeInterval(delay)
            connectionStatus = (error as? WatchHTTPError)?.errorDescription ?? "Нет сети — записи сохранены на часах"
        }
        await health.reconcile(state)
    }
    func returnToPhone() async {
        do { state = try await store.requestReturn(); await synchronize(force: true) }
        catch { self.error = error.localizedDescription }
    }
    private func syncReservation(transport: WatchHTTPTransport) async throws {
        if let request = reservation.pending, !reservation.blocked {
            do { reservation = try await reservationStore.acknowledge(request, snapshot: transport.send(request)) }
            catch let error as WatchHTTPError {
                if [400, 409, 426].contains(error.status) { reservation = try await reservationStore.rejectPending() }
                throw error
            }
        }
        let response = try await transport.send(WatchRequest(path: "/watch/v1/reservation/", method: "GET", body: .null))
        guard response["reservation"] != .null else { return }
        reservation = try await reservationStore.accept(response["reservation"])
        let snapshot = reservation.snapshot
        if snapshot["state"].string == "preparing", snapshot["phoneReady"].bool, !snapshot["watchReady"].bool, reservation.pending == nil {
            let request = ReservationStore.command(snapshot, path: "/watch/v1/reservation/ready")
            reservation = try await reservationStore.prepare(request)
            reservation = try await reservationStore.acknowledge(request, snapshot: transport.send(request))
        }
        publishCompanionState()
        // The phone command can arrive before the readiness acknowledgement.
        let command = companionBridge.incoming
        if reservation.snapshot["state"].string == "ready", !reservation.blocked,
           command["startReservationID"] != .null,
           command["startReservationID"] == reservation.snapshot["reservationId"],
           command["startReservationEpoch"] == reservation.snapshot["controlEpoch"],
           state?.workout.id != reservation.snapshot["reservationId"].string {
            await startReserved()
        }
    }
    func startReserved() async {
        guard !busy, let credentials, !reservation.blocked else { return }
        busy = true; defer { busy = false }
        do {
            state = try await store.startReserved(reservation.snapshot, deviceID: credentials.deviceID)
            publishCompanionState(); await health.reconcile(state)
            Task { await self.synchronize(force: true) }
        } catch { self.error = error.localizedDescription }
    }
    func reconcileReservation() async {
        guard !syncing, let credentials else { return }; syncing = true
        do {
            let transport = try WatchHTTPTransport(endpoint: credentials.endpoint, token: credentials.token)
            let response = try await transport.send(WatchRequest(path: "/watch/v1/reservation/", method: "GET", body: .null))
            reservation = try await reservationStore.reconcileRejected(serverSnapshot: response["reservation"])
        } catch { self.error = error.localizedDescription }
        syncing = false; await synchronize(force: true)
    }
    func recover() async {
        guard let credentials, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let transport = try WatchHTTPTransport(endpoint: credentials.endpoint, token: credentials.token)
            try await engine.uploadRecovery(using: transport)
            state = try await store.load()
            connectionStatus = "Копия в архиве сервера. Верните управление на телефоне."
        } catch { self.error = error.localizedDescription }
    }
    private func updateNotification() async {
        let center = UNUserNotificationCenter.current(), identifier = "traininglog.workout.rest"
        let end = state?.workout.restEndsAt
        guard !notificationsInitialized || end != scheduledEnd else { return }
        notificationsInitialized = true
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        scheduledEnd = nil
        guard let end, end > Workout.milliseconds(Date()) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Отдых закончен"
        content.body = "Можно переходить к следующему подходу."
        content.sound = .default
        let interval = max(1, Double(end - Workout.milliseconds(Date())) / 1000)
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))
            scheduledEnd = end
        } catch { notificationStatus = "Не удалось поставить уведомление. Таймер и записи сохранены." }
    }
}

/// The same notification provides foreground haptics and background delivery, not two timers.
final class WorkoutNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run { WKInterfaceDevice.current().play(.notification) }
        return [.banner]
    }
}
