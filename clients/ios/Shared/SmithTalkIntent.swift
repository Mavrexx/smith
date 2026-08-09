import AppIntents
import Foundation

struct TalkToSmithIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Smith"
    static let description = IntentDescription("Starts Smith's explicit voice session.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(SmithRoute.voice.url))
    }
}
