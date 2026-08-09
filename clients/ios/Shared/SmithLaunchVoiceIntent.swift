import AppIntents
import Foundation

extension Notification.Name {
    static let smithLaunchVoice = Notification.Name("com.farhan.smith.launchVoice")
}

struct SmithLaunchVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Smith"
    static let description = IntentDescription("Opens Smith and starts the private voice session.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .smithLaunchVoice, object: nil)
        return .result()
    }
}