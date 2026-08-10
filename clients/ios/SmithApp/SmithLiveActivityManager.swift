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

    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if activity == nil {
            activity = Activity<SmithVoiceActivityAttributes>.activities.first
        }
        guard activity == nil else {
            update(state: "CONNECTING", subtitle: "Starting private voice session")
            return
        }
        let attributes = SmithVoiceActivityAttributes(sessionID: UUID())
        let content = ActivityContent(
            state: SmithVoiceActivityAttributes.ContentState(
                state: "CONNECTING",
                subtitle: "Starting private voice session"
            ),
            staleDate: nil
        )
        do {
            activity = try Activity.request(attributes: attributes, content: content)
        } catch {
            print("Smith Live Activity could not start: \(error.localizedDescription)")
        }
    }

    func update(state: String, subtitle: String) {
        if activity == nil { activity = Activity<SmithVoiceActivityAttributes>.activities.first }
        guard let activity else {
            start()
            return
        }
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
#endif
}
