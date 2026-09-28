import Foundation
import Observation
import UserNotifications
import WatchKit
import WorkoutCore

@MainActor @Observable
final class WorkoutModel {
    var state: WorkoutState?
    var busy = false
    var ready = false
    var error: String?
    var notificationStatus = ""
    var connectionStatus = "Не подключено"
    var connected = false
    var syncing = false
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
            do {
                credentials = try WatchKeychain.load(); connected = credentials != nil
                if let credentials { endpoint = credentials.endpoint; connectionStatus = "Подключено" }
            } catch {
                connectionStatus = error.localizedDescription // Local workouts remain usable if Keychain is temporarily locked.
            }
            await updateNotification()
        }
        catch { self.error = error.localizedDescription }
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
        if case .complete = action {
            guard Date().timeIntervalSince(lastCompletion) > 0.7 else { return false }
            lastCompletion = Date()
        }
        busy = true
        defer { busy = false }
        do {
            state = try await store.apply(action)
            await updateNotification()
            Task { await synchronize() }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func enableNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            notificationStatus = granted ? "Уведомления разрешены" : "Без уведомлений — запись подходов работает"
            scheduledEnd = nil
            await updateNotification()
        } catch { notificationStatus = error.localizedDescription }
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
        guard let credentials, !syncing, state?.isDemo == false, force || Date() >= nextAttempt else { return }
        syncing = true
        defer { syncing = false }
        do {
            let transport = try WatchHTTPTransport(endpoint: credentials.endpoint, token: credentials.token)
            _ = try await engine.synchronize(using: transport, deviceID: credentials.deviceID)
            state = try await store.load()
            failures = 0; nextAttempt = .distantPast; connectionStatus = "Связь с сервером работает"
            await updateNotification()
        } catch {
            if let saved = try? await store.load() { state = saved }
            failures += 1
            let delay = (error as? WatchHTTPError)?.retryAfter ?? min(300, pow(2, Double(min(failures, 8))) * 2 + Double.random(in: 0...3))
            nextAttempt = Date().addingTimeInterval(delay)
            connectionStatus = (error as? WatchHTTPError)?.errorDescription ?? "Нет сети — записи сохранены на часах"
        }
    }
    func returnToPhone() async {
        do { state = try await store.requestReturn(); await synchronize(force: true) }
        catch { self.error = error.localizedDescription }
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
