import Foundation

enum SmithRoute: String, CaseIterable {
    case voice
    case text
    case memory
    case tasks
    case reminders
    case conversations
    case clipboard
    case share
    case search
    case apps
    case devices
    case protocols
    case settings
    case maps
    case files
    case music
    var url: URL {
        URL(string: "smith://\(rawValue)")!
    }

    static func shareURL(text: String, action: String? = nil) -> URL {
        var components = URLComponents(string: "smith://share")!
        var items = [URLQueryItem(name: "text", value: text)]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        components.queryItems = items
        return components.url!
    }
}

