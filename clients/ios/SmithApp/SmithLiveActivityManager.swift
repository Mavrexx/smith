import ActivityKit
import Foundation

@MainActor
final class SmithLiveActivityManager {
#if SMITH_LITE
    func start() {}
    func update(state: String, subtitle: String) {}
    func end() {}
#else
    private var activity: Activity<SmithVoiceActivityAttributes>?
    private var lastState: String?
    private var lastSubtitle: String?

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
        lastState = "CONNECTING"
        lastSubtitle = "Starting private voice session"
    }

    func update(state: String, subtitle: String) {
        guard let activity, state != lastState || subtitle != lastSubtitle else { return }
        lastState = state
        lastSubtitle = subtitle
        let content = ActivityContent(
            state: SmithVoiceActivityAttributes.ContentState(state: state, subtitle: subtitle),
            staleDate: Date().addingTimeInterval(90)
        )
        Task { await activity.update(content) }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        lastState = nil
        lastSubtitle = nil
        let final = ActivityContent(
            state: SmithVoiceActivityAttributes.ContentState(
                state: "ENDED",
                subtitle: "Microphone stopped"
            ),
            staleDate: nil
        )
        Task { await activity.end(final, dismissalPolicy: .immediate) }
    }
#endif
}
