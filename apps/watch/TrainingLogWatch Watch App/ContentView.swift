import SwiftUI
import WatchKit

struct InstallationProbeView: View {
    @State private var probe = InstallationProbe()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Проверка установки").font(.headline)
                Text("\(probe.count)").font(.largeTitle.monospacedDigit())
                    .accessibilityIdentifier("savedCounter")
                Button("Сохранить +1") { probe.increment() }
                    .disabled(!probe.storageReady)
                Text(probe.storageStatus).font(.footnote)
                Divider()
                Button("Проверить HTTPS") { Task { await probe.checkHealth() } }
                    .disabled(probe.checkingHealth)
                Text(probe.healthStatus).font(.footnote)
                Button("Уведомление через 60 с") { Task { await probe.scheduleNotification() } }
                    .disabled(probe.schedulingNotification)
                Text(probe.notificationStatus).font(.footnote)
                Text("\(WKInterfaceDevice.current().model) · watchOS \(WKInterfaceDevice.current().systemVersion)")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("Этап 0 · не дневник тренировок")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
    }
}
