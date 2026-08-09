import ActivityKit
import Foundation

struct SmithVoiceActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var state: String
        var subtitle: String
    }

    var sessionID: UUID
}
