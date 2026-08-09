import ActivityKit
import Foundation

@MainActor
final class SmithLiveActivityManager {
    private var activity: Activity<SmithVoiceActivityAttributes>?

    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activity == nil else { return }
        let attributes = SmithVoiceActivityAttributes(sessionID: UUID())
        let content = ActivityContent(
            state: SmithVoiceActivityAttributes.ContentState(
                state: "CONNECTING",
                subtitle: "Starting private voice session"
            ),
            staleDate: nil
        )
        activity = try? Activity.request(attributes: attributes, content: content)
    }

    func update(state: String, subtitle: String) {
        guard let activity else { return }
        let content = ActivityContent(
            state: SmithVoiceActivityAttributes.ContentState(state: state, subtitle: subtitle),
            staleDate: Date().addingTimeInterval(90)
        )
        Task { await activity.update(content) }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        let final = ActivityContent(
            state: SmithVoiceActivityAttributes.ContentState(
                state: "ENDED",
                subtitle: "Microphone stopped"
            ),
            staleDate: nil
        )
        Task { await activity.end(final, dismissalPolicy: .immediate) }
    }
}
