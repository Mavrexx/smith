import Combine
import Foundation
import UIKit

enum SmithEnvironmentMode: Equatable {
    case idle
    case awake
    case workspace
}

@MainActor
final class SmithModel: ObservableObject {
    @Published var serverAddress = UserDefaults.standard.string(forKey: "smith.serverURL") ?? ""
    @Published var accessCode = ""
    @Published var status = SmithKeychain.get("device-token") == nil ? "SETUP REQUIRED" : "READY"
    @Published private(set) var environment: SmithEnvironmentMode = .idle
    @Published private(set) var workspace: SmithRoute?
    @Published private(set) var isRegistered = SmithKeychain.get("device-token") != nil
    @Published var sharedText = ""
    @Published var pendingAction: String?

    let api = SmithAPI()
    lazy var voice = SmithVoiceSession(api: api)

    private var lastIntentTranscript = ""

    func register() async {
        do {
            guard let url = URL(string: serverAddress) else {
                status = "Enter a valid HTTPS address."
                return
            }
            try await api.configure(serverURL: url)
            try await api.register(accessCode: accessCode)
            accessCode = ""
            isRegistered = true
            status = "ONLINE"
            environment = .idle
            workspace = nil
        } catch {
            status = error.localizedDescription
        }
    }

    func wake() async {
        if !isRegistered {
            openWorkspace(.settings)
            status = "SETUP REQUIRED"
            return
        }

        environment = .awake
        workspace = nil
        if !voice.connected {
            await voice.start()
        }
        status = voice.lastError ?? (voice.connected ? "ONLINE" : voice.state)
    }

    func openWorkspace(_ route: SmithRoute) {
        workspace = route == .conversations ? .voice : route
        environment = .workspace
    }

    func closeWorkspace() {
        let wasConversation = workspace == .voice || workspace == .conversations
        workspace = nil
        environment = wasConversation ? .awake : .idle
    }

    func returnToIdle() {
        workspace = nil
        environment = .idle
    }

    func handleUserTranscript(_ transcript: String) {
        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != lastIntentTranscript else { return }
        lastIntentTranscript = normalized

        guard let intent = SmithEnvironmentIntentParser.parse(normalized) else { return }
        switch intent {
        case .wake:
            environment = .awake
            workspace = nil
        case .open(let route):
            openWorkspace(route)
        case .closeConversation:
            if workspace == .voice || workspace == .conversations {
                workspace = nil
                environment = .awake
            }
        case .returnToIdle:
            returnToIdle()
        }
    }

    func handle(url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let route: SmithRoute
        if url.scheme == "smith" {
            route = SmithRoute(rawValue: url.host ?? "") ?? .voice
        } else if url.scheme == "https" {
            route = SmithRoute(
                rawValue: components?.queryItems?.first(where: { $0.name == "mode" })?.value ?? ""
            ) ?? .voice
        } else {
            return
        }

        sharedText = components?.queryItems?.first(where: { $0.name == "text" })?.value ?? ""
        pendingAction = components?.queryItems?.first(where: { $0.name == "action" })?.value
        if route == .clipboard { sharedText = UIPasteboard.general.string ?? "" }
        if pendingAction == "task" { openWorkspace(.tasks) }
        else if pendingAction == "remember" { openWorkspace(.memory) }
        else { openWorkspace(route) }
    }
}


