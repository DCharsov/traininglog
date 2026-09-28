import Foundation
import WatchConnectivity
import Observation
import WorkoutCore

/// Only Apple's signed companion channel carries credentials. No LAN discovery or untrusted deep links.
@MainActor @Observable final class CompanionBridge: NSObject, WCSessionDelegate {
    var available = false
    var reachable = false
    var status = "Ожидаем системную связь"
    var incoming: JSONValue = .null
    var onReceive: ((JSONValue) -> Void)?
    private var outgoing: JSONValue?
    override init() { super.init() }
    func activate() {
        guard WCSession.isSupported() else { status = "Watch Connectivity недоступен"; return }
        let session = WCSession.default; session.delegate = self; session.activate()
    }
    func publish(_ value: JSONValue) {
        outgoing = value
        guard WCSession.default.activationState == .activated else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(value)
            try WCSession.default.updateApplicationContext(["traininglog": data])
            if WCSession.default.isReachable { WCSession.default.sendMessageData(data, replyHandler: nil, errorHandler: { _ in }) }
        } catch { status = "Данные сохранены; ждём связь с устройством" }
    }
    private func update() {
        let session = WCSession.default
        reachable = session.isReachable
        #if os(iOS)
        available = session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
        status = available ? (reachable ? "Apple Watch рядом" : "Apple Watch · доставка при следующем соединении") : "Установите TrainingLog на ваши Apple Watch"
        #else
        available = session.activationState == .activated && session.isCompanionAppInstalled
        status = available ? "Связь с iPhone настроена системой" : "Откройте TrainingLog на iPhone"
        #endif
        if let outgoing { publish(outgoing) }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext["traininglog"] as? Data
        Task { @MainActor in self.update(); if let data { self.receive(data) } }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in self.update() } }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext["traininglog"] as? Data { Task { @MainActor in self.receive(data) } }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) { Task { @MainActor in self.receive(messageData) } }
    private func receive(_ data: Data) {
        guard data.count <= 64_000, let value = try? JSONDecoder().decode(JSONValue.self, from: data), value["version"].integer == 1 else { return }
        guard incoming != value else { return }
        incoming = value; onReceive?(value)
    }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) { Task { @MainActor in self.available = false; self.incoming = .null } }
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.update() } }
    #endif
}
