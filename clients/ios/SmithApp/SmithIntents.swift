import AppIntents
import Foundation

struct OpenSmithMemoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Smith Memory"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(SmithRoute.memory.url))
    }
}

struct CreateSmithTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Create a Smith Task"
    static let openAppWhenRun = true

    @Parameter(title: "Task")
    var task: String

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(SmithRoute.shareURL(text: task, action: "task")))
    }
}

struct RememberWithSmithIntent: AppIntent {
    static let title: LocalizedStringResource = "Remember with Smith"
    static let openAppWhenRun = true

    @Parameter(title: "Information")
    var information: String

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(SmithRoute.shareURL(text: information, action: "remember")))
    }
}

struct SmithShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TalkToSmithIntent(),
            phrases: ["Talk to \(.applicationName)", "Open \(.applicationName)"],
            shortTitle: "Talk to Smith",
            systemImageName: "waveform.circle"
        )
        AppShortcut(
            intent: OpenSmithMemoryIntent(),
            phrases: ["Open \(.applicationName) memory"],
            shortTitle: "Smith Memory",
            systemImageName: "brain"
        )
        AppShortcut(
            intent: CreateSmithTaskIntent(),
            phrases: ["Create a \(.applicationName) task"],
            shortTitle: "Smith Task",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: RememberWithSmithIntent(),
            phrases: ["Remember with \(.applicationName)"],
            shortTitle: "Smith Memory",
            systemImageName: "bookmark"
        )
    }
}
