import Foundation

enum SmithEnvironmentIntent: Equatable {
    case wake
    case open(SmithRoute)
    case closeConversation
    case returnToIdle
}

enum SmithEnvironmentIntentParser {
    static func parse(_ transcript: String) -> SmithEnvironmentIntent? {
        let text = transcript
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9']+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return nil }

        if containsAny(text, ["close conversation", "close chat", "hide conversation", "dismiss chat"]) {
            return .closeConversation
        }
        if containsAny(text, ["return to idle", "go idle", "stand down", "close workspace", "centre smith", "center smith"]) {
            return .returnToIdle
        }

        let opening = containsAny(text, ["open", "show", "pull up", "bring up", "launch"])
        if opening {
            if containsAny(text, ["conversation", "chat"]) { return .open(.voice) }
            if text.contains("search") { return .open(.search) }
            if containsAny(text, ["app", "applications"]) { return .open(.apps) }
            if containsAny(text, ["device", "tablet", "phone"]) { return .open(.devices) }
            if text.contains("protocol") { return .open(.protocols) }
            if text.contains("memory") { return .open(.memory) }
            if containsAny(text, ["setting", "preferences"]) { return .open(.settings) }
            if containsAny(text, ["map", "navigation"]) { return .open(.maps) }
            if containsAny(text, ["file", "document"]) { return .open(.files) }
            if containsAny(text, ["music", "spotify", "audio"]) { return .open(.music) }
            if text.contains("task") { return .open(.tasks) }
            if text.contains("reminder") { return .open(.reminders) }
        }

        if text == "smith" || containsAny(text, ["wake up smith", "smith wake up", "smith online"]) {
            return .wake
        }
        return nil
    }

    private static func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains(where: text.contains)
    }
}

