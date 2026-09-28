import Foundation
import Observation
import UserNotifications

/// Stage 0 only: no credentials, workout data or server writes.
@MainActor @Observable
final class InstallationProbe {
    private(set) var count = 0
    private(set) var storageReady = false
    private(set) var storageStatus = "Загрузка…"
    private(set) var healthStatus = "Проверка ещё не выполнялась"
    private(set) var notificationStatus = "Проверка ещё не выполнялась"
    private(set) var checkingHealth = false
    private(set) var schedulingNotification = false
    private var fileURL: URL?

    private struct SavedCounter: Codable {
        var formatVersion: Int
        var count: Int
    }

    init() {
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            let url = directory.appendingPathComponent("installation-probe.json")
            fileURL = url
            if FileManager.default.fileExists(atPath: url.path) {
                let saved = try JSONDecoder().decode(SavedCounter.self, from: Data(contentsOf: url))
                guard saved.formatVersion == 1, saved.count >= 0 else {
                    storageStatus = "Формат счётчика не поддерживается. Файл сохранён."
                    return
                }
                count = saved.count
                storageStatus = "Восстановлено с диска"
            } else {
                storageStatus = "Новая установка — нажмите +1"
            }
            storageReady = true
        } catch {
            storageStatus = "Не удалось прочитать счётчик: \(error.localizedDescription)"
        }
    }

    func increment() {
        guard storageReady, let fileURL, count < Int.max else { return }
        do {
            let next = count + 1
            let data = try JSONEncoder().encode(SavedCounter(formatVersion: 1, count: next))
            try data.write(to: fileURL, options: .atomic)
            count = next
            storageStatus = "Сохранено на часах"
        } catch {
            storageStatus = "Ошибка сохранения: \(error.localizedDescription). Повторите."
        }
    }

    func checkHealth() async {
        guard !checkingHealth else { return }
        checkingHealth = true
        healthStatus = "Подключение…"
        defer { checkingHealth = false }
        // Only a public read-only health check reaches production.
        let url = URL(string: "https://cleargate.ru/training/api/health")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                healthStatus = "Ошибка HTTP: \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                return
            }
            struct Health: Decodable { let status: String; let contractVersion: Int }
            let health = try JSONDecoder().decode(Health.self, from: data)
            guard health.status == "ok", health.contractVersion == 2 else {
                healthStatus = "Ответ API несовместим"
                return
            }
            healthStatus = "HTTPS работает · API v2"
        } catch {
            healthStatus = "HTTPS: \(error.localizedDescription)"
        }
    }

    func scheduleNotification() async {
        guard !schedulingNotification else { return }
        schedulingNotification = true
        defer { schedulingNotification = false }
        let center = UNUserNotificationCenter.current()
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                notificationStatus = "Уведомления запрещены. Счётчик работает."
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "TrainingLog"
            content.body = "Проверка: прошла одна минута"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "traininglog.installation-probe",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
            )
            try await center.add(request)
            notificationStatus = "Запланировано. Откройте циферблат и подождите минуту."
        } catch {
            notificationStatus = "Уведомление: \(error.localizedDescription)"
        }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
