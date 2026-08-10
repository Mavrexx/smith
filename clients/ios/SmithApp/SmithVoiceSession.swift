import Combine
import AVFoundation
import Foundation
import UIKit

struct SmithSafariDestination: Identifiable {
    let id = UUID()
    let url: URL
}

final class SmithAudioTransport: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.farhan.smith.audio-transport", qos: .userInitiated)
    private var socket: URLSessionWebSocketTask?
    private var pending: [Data] = []
    private var sending = false
    private var enabled = false

    func configure(socket: URLSessionWebSocketTask?) {
        queue.async {
            self.socket = socket
            if socket == nil {
                self.pending.removeAll(keepingCapacity: true)
                self.sending = false
            }
        }
    }

    func setEnabled(_ value: Bool) {
        queue.async {
            self.enabled = value
            if !value { self.pending.removeAll(keepingCapacity: true) }
            if value { self.pump() }
        }
    }

    func enqueue(_ data: Data) {
        queue.async {
            guard self.enabled, self.socket != nil else { return }
            if self.pending.count >= 8 { self.pending.removeFirst() }
            self.pending.append(data)
            self.pump()
        }
    }

    private func pump() {
        guard enabled, !sending, let socket, !pending.isEmpty else { return }
        sending = true
        let data = pending.removeFirst()
        let message = "{\"type\":\"audio\",\"data\":\"\(data.base64EncodedString())\"}"
        socket.send(.string(message)) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                self.sending = false
                self.pump()
            }
        }
    }
}

@MainActor
final class SmithMicrophoneMeter: ObservableObject {
    @Published private(set) var level: Float = 0
    private var lastPublishedAt: TimeInterval = 0

    func offer(_ value: Float) {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastPublishedAt >= 0.12 else { return }
        lastPublishedAt = now
        level = value
    }

    func reset() {
        lastPublishedAt = 0
        level = 0
    }
}

@MainActor
final class SmithVoiceSession: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var state = "IDLE"
    @Published private(set) var transcript = ""
    @Published private(set) var userTranscript = ""
    @Published private(set) var assistantTranscript = ""
    @Published private(set) var lastError: String?
    @Published private(set) var muted = false
    let microphoneMeter = SmithMicrophoneMeter()
    @Published private(set) var audioPacketsSent = 0
    var microphoneLevel: Float { microphoneMeter.level }
    @Published private(set) var textModeAvailable = false
    @Published private(set) var outputVolume = 66
    @Published var safariDestination: SmithSafariDestination?
    @Published var requestedPage: String?

    private let api: SmithAPI
    private let audio = SmithAudioController()
    private let audioTransport = SmithAudioTransport()
    private let liveActivity = SmithLiveActivityManager()
    private var socket: URLSessionWebSocketTask?
    private var heartbeat: Task<Void, Never>?
    private var reconnect: Task<Void, Never>?
    private var shouldRun = false
    private var attempt = 0
    private var captureStarted = false

    init(api: SmithAPI) {
        self.api = api
    }

    func start() async {
        if shouldRun {
            if !captureStarted { retryMicrophone() }
            if !connected && socket == nil { await connect() }
            return
        }
        let permission = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
        guard permission else {
            state = "PERMISSION REQUIRED"
            lastError = "Microphone permission is required. Open iPhone Settings to allow Smith microphone access."
            return
        }
        shouldRun = true
        lastError = nil
        liveActivity.start()
        attempt = 0
        await connect()
    }

    func toggleMuted() {
        setMuted(!muted)
    }

    func setMuted(_ value: Bool) {
        muted = value
        audioTransport.setEnabled(connected && !value)
        if value { microphoneMeter.reset() } else { microphoneMeter.offer(0.18) }
        state = muted ? "MUTED" : (connected ? "LISTENING" : "READY")
        Task { [weak self] in
            guard let self else { return }
            if value || self.connected {
                try? await self.announcePresence()
            } else {
                try? await self.announcePresenceAndRequestPrimary()
            }
        }
        liveActivity.update(
            state: state,
            subtitle: muted ? "Microphone transmission stopped" : "Smith is listening"
        )
    }

    func retryMicrophone() {
        guard shouldRun else {
            Task { await start() }
            return
        }
        do {
            try audio.restartCapture()
            captureStarted = true
            lastError = nil
            state = muted ? "MUTED" : (connected ? "LISTENING" : "READY")
        } catch {
            captureStarted = false
            lastError = "Microphone restart failed: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func adjustSmithVolume(by delta: Float) -> Int {
        outputVolume = audio.adjustOutputGain(by: delta)
        return outputVolume
    }

    @discardableResult
    func setSmithVolume(percent: Int) -> Int {
        let clamped = min(100, max(0, percent))
        outputVolume = audio.setOutputGain(Float(clamped) / 100 * 2.5)
        return outputVolume
    }

    func sendText(_ text: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        userTranscript = clean
        state = "THINKING"
        do {
            if !shouldRun { await start() }
            guard connected else {
                throw NSError(domain: "Smith", code: 1, userInfo: [NSLocalizedDescriptionKey: "Smith Core is still connecting."])
            }
            try await send(["type": "text", "text": clean])
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func sendImage(_ data: Data, mimeType: String, name: String) async {
        do {
            if !shouldRun { await start() }
            guard connected else {
                throw NSError(domain: "Smith", code: 2, userInfo: [NSLocalizedDescriptionKey: "Connect Smith before sharing an image."])
            }
            try await send(["type": "media", "data": data.base64EncodedString(), "mimeType": mimeType, "name": name])
            state = "THINKING"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() async {
        shouldRun = false
        heartbeat?.cancel()
        reconnect?.cancel()
        heartbeat = nil
        reconnect = nil
        try? await send(["type": "end"])
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        audioTransport.setEnabled(false)
        audioTransport.configure(socket: nil)
        captureStarted = false
        microphoneMeter.reset()
        connected = false
        state = "IDLE"
        audio.stop()
        liveActivity.end()
    }

    private func connect() async {
        guard shouldRun else { return }
        state = attempt == 0 ? "CONNECTING" : "RECONNECTING"
        do {
            let url = try await api.webSocketURL()
            let task = URLSession.shared.webSocketTask(with: url)
            socket = task
            audioTransport.configure(socket: task)
            task.resume()
            receive(on: task)
            startHeartbeat()
            Task { [weak self] in
                try? await self?.announcePresenceAndRequestPrimary()
            }
        } catch {
            await scheduleReconnect(error)
        }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.socket === task, self.shouldRun else { return }
                switch result {
                case .success(let message):
                    self.handle(message)
                    self.receive(on: task)
                case .failure(let error):
                    await self.scheduleReconnect(error)
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let value): data = value
        @unknown default: return
        }
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = payload["type"] as? String else { return }

        switch type {
        case "ready":
            connected = true
            state = muted ? "MUTED" : "LISTENING"
            liveActivity.update(
                state: state,
                subtitle: muted ? "Microphone transmission stopped" : "Smith is listening"
            )
            attempt = 0
            textModeAvailable = true
            audioTransport.setEnabled(!muted)
            microphoneMeter.offer(muted ? 0 : 0.18)
            if audioPacketsSent == 0 { audioPacketsSent = 1 }
            startCaptureIfNeeded()
            Task { [weak self] in try? await self?.announcePresence() }
        case "secondary_ready":
            connected = false
            audioTransport.setEnabled(false)
            state = muted ? "MUTED - TAP MIC TO JOIN" : "REQUESTING HANDOFF"
            Task { [weak self] in
                guard let self else { return }
                if self.muted {
                    try? await self.announcePresence()
                } else {
                    try? await self.announcePresenceAndRequestPrimary()
                }
            }
        case "primary_changed":
            if payload["primary"] as? Bool == true {
                state = "CONNECTING"
            } else {
                connected = false
                audioTransport.setEnabled(false)
                state = "READY FOR HANDOFF"
            }
        case "handoff_failed":
            connected = false
            if muted {
                state = "MUTED - TAP MIC TO JOIN"
                lastError = "This iPhone is connected but muted. Tap the microphone once to unmute and retry the handoff."
            } else {
                state = "HANDOFF BLOCKED"
                lastError = payload["message"] as? String ?? "Smith voice is active on another device."
            }
        case "handoff_incoming":
            state = "HANDOFF INCOMING"
            liveActivity.update(state: "HANDOFF", subtitle: "Smith is jumping to this iPhone")
        case "device_command":
            Task { [weak self] in await self?.executeDeviceCommand(payload) }
        case "audio":
            if let encoded = payload["data"] as? String {
                if state != "SPEAKING" {
                    state = "SPEAKING"
                    liveActivity.update(state: "SPEAKING", subtitle: transcript.isEmpty ? "Smith is responding" : transcript)
                }
                audio.play(base64PCM16: encoded)
            }
        case "audioReset", "interrupted":
            audio.resetPlayback()
            let nextState = muted ? "MUTED" : "LISTENING"
            if state != nextState { state = nextState }
        case "transcript":
            if let text = payload["text"] as? String, text != transcript {
                transcript = text
                if payload["role"] as? String == "user" {
                    if userTranscript != text { userTranscript = text }
                } else {
                    if assistantTranscript != text { assistantTranscript = text }
                }
            }
        case "turnComplete":
            let nextState = muted ? "MUTED" : "LISTENING"
            if state != nextState { state = nextState }
        case "reconnecting":
            audio.resetPlayback()
            state = "RECONNECTING"
            liveActivity.update(state: "RECONNECTING", subtitle: "Restoring the private voice link")
        case "error":
            lastError = payload["message"] as? String ?? "Realtime session error"
        case "quota_status":
            textModeAvailable = payload["textMode"] as? Bool ?? false
            if let message = payload["message"] as? String,
               payload["reason"] as? String != "ready" {
                lastError = message
            }
        default:
            break
        }
    }

    private func startCaptureIfNeeded() {
        guard !captureStarted else { return }
        let transport = audioTransport
        do {
            try audio.startCapture { data, _ in
                transport.enqueue(data)
            }
            captureStarted = true
        } catch {
            lastError = "Audio session could not start: \(error.localizedDescription)"
        }
    }

    private var chargingStateName: String {
        switch UIDevice.current.batteryState {
        case .charging: return "charging"
        case .full: return "full"
        case .unplugged: return "unplugged"
        default: return "unknown"
        }
    }

    private var batteryPercent: Int? {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        return level >= 0 ? Int((level * 100).rounded()) : nil
    }

    private func announcePresence() async throws {
        UIDevice.current.isBatteryMonitoringEnabled = true
        var presence: [String: Any] = [
            "type": "device_presence",
            "deviceName": UIDevice.current.name,
            "deviceModel": UIDevice.current.model,
            "chargingState": chargingStateName,
            "foreground": true,
            "locked": false,
            "voiceInput": true,
            "voicePlayback": true,
            "privacyMode": muted,
            "microphoneActive": !muted,
            "cameraAvailable": UIImagePickerController.isSourceTypeAvailable(.camera),
            "visionAvailable": true,
            "os": "iOS \(UIDevice.current.systemVersion)",
            "capabilities": ["voice", "keyboard", "vision", "photos"],
            "lastInteractionAt": Date().timeIntervalSince1970 * 1000,
        ]
        if let batteryPercent { presence["batteryPercent"] = batteryPercent }
        try await send(presence)
    }

    private func executeDeviceCommand(_ payload: [String: Any]) async {
        guard let id = payload["id"] as? String,
              let command = payload["command"] as? String else { return }
        let args = payload["args"] as? [String: Any] ?? [:]
        var success = false
        var message = "Unsupported iPhone command."
        var data: [String: Any] = [:]

        switch command {
        case "get_battery":
            if let batteryPercent {
                success = true
                data = ["batteryPercent": batteryPercent, "chargingState": chargingStateName]
                message = "This iPhone battery is at \(batteryPercent)% and is \(chargingStateName)."
            } else {
                message = "iPhone battery information is temporarily unavailable."
            }
        case "get_charging_state":
            success = true
            data = ["chargingState": chargingStateName]
            message = "This iPhone is \(chargingStateName)."
        case "get_device_info":
            success = true
            data = [
                "deviceName": UIDevice.current.name,
                "deviceModel": UIDevice.current.model,
                "systemName": UIDevice.current.systemName,
                "systemVersion": UIDevice.current.systemVersion,
            ]
            message = "This client is \(UIDevice.current.name), an \(UIDevice.current.model) running iOS \(UIDevice.current.systemVersion)."
        case "mute_microphone":
            if !muted { toggleMuted() }
            success = true
            message = "Smith microphone muted on this iPhone."
        case "unmute_microphone":
            if muted { toggleMuted() }
            success = true
            message = "Smith microphone unmuted on this iPhone."
        case "open_safari", "open_url":
            var rawURL = (args["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let query = (args["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if (rawURL ?? "").isEmpty, !query.isEmpty {
                rawURL = "https://www.google.com/search?q=" + (query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
            }
            if (rawURL ?? "").isEmpty { rawURL = "https://www.apple.com/" }
            if let rawURL, let url = URL(string: rawURL), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                safariDestination = SmithSafariDestination(url: url)
                success = true
                message = "Opened in Smith's Safari browser on this iPhone."
            } else {
                message = "The requested Safari URL was invalid."
            }
        case "open_youtube":
            var rawURL = args["url"] as? String
            let query = (args["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if (rawURL ?? "").isEmpty {
                rawURL = query.isEmpty
                    ? "https://www.youtube.com/"
                    : "https://www.youtube.com/results?search_query=" + (query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
            }
            if let rawURL, let url = URL(string: rawURL) {
                success = await UIApplication.shared.open(url)
                message = success ? "Opened YouTube on this iPhone." : "The iPhone could not open YouTube."
            }
        case "compose_sms":
            let recipient = String(describing: args["recipient"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let body = String(describing: args["body"] ?? "")
            var components = URLComponents()
            components.scheme = "sms"
            components.path = recipient
            components.queryItems = body.isEmpty ? nil : [URLQueryItem(name: "body", value: body)]
            if let url = components.url {
                success = await UIApplication.shared.open(url)
                message = success ? "Opened a Messages draft. Review it and tap Send." : "Messages is unavailable."
            }
        case "compose_email":
            let recipient = String(describing: args["recipient"] ?? "")
            let subject = String(describing: args["subject"] ?? "")
            let body = String(describing: args["body"] ?? "")
            var gmail = URLComponents(string: "googlegmail:///co")
            gmail?.queryItems = [
                URLQueryItem(name: "to", value: recipient),
                URLQueryItem(name: "subject", value: subject),
                URLQueryItem(name: "body", value: body),
            ]
            var mail = URLComponents()
            mail.scheme = "mailto"
            mail.path = recipient
            mail.queryItems = [
                URLQueryItem(name: "subject", value: subject),
                URLQueryItem(name: "body", value: body),
            ]
            if let gmailURL = gmail?.url, UIApplication.shared.canOpenURL(gmailURL) {
                success = await UIApplication.shared.open(gmailURL)
            } else if let mailURL = mail.url {
                success = await UIApplication.shared.open(mailURL)
            }
            message = success ? "Opened an email draft. Review it and tap Send." : "No mail app is available."
        case "compose_whatsapp":
            let recipient = String(describing: args["recipient"] ?? "").filter(\.isNumber)
            let body = String(describing: args["body"] ?? "")
            var whatsapp = URLComponents(string: "whatsapp://send")
            whatsapp?.queryItems = [
                URLQueryItem(name: "phone", value: recipient.isEmpty ? nil : recipient),
                URLQueryItem(name: "text", value: body),
            ]
            var web = URLComponents(string: recipient.isEmpty ? "https://wa.me/" : "https://wa.me/\(recipient)")
            web?.queryItems = [URLQueryItem(name: "text", value: body)]
            if let appURL = whatsapp?.url, UIApplication.shared.canOpenURL(appURL) {
                success = await UIApplication.shared.open(appURL)
            } else if let webURL = web?.url {
                success = await UIApplication.shared.open(webURL)
            }
            message = success ? "Opened a WhatsApp draft. Choose or verify the contact, then tap Send." : "WhatsApp is unavailable."
        case "set_smith_volume":
            let percent = Int((args["percent"] as? NSNumber)?.doubleValue ?? 70)
            let actual = setSmithVolume(percent: percent)
            success = true
            data = ["smithVolumePercent": actual]
            message = "Smith voice volume set to \(actual)%."
        case "smith_volume_up":
            let actual = adjustSmithVolume(by: 0.25)
            success = true
            data = ["smithVolumePercent": actual]
            message = "Smith voice volume raised to \(actual)%."
        case "smith_volume_down":
            let actual = adjustSmithVolume(by: -0.25)
            success = true
            data = ["smithVolumePercent": actual]
            message = "Smith voice volume lowered to \(actual)%."
        case "open_permissions":
            requestedPage = "permissions"
            success = true
            message = "Opened Smith permissions."
        case "open_files":
            requestedPage = "files"
            success = true
            message = "Opened Smith Files."
        default:
            break
        }

        try? await send([
            "type": "device_command_result",
            "id": id,
            "success": success,
            "message": message,
            "data": data,
        ])
    }

    private func announcePresenceAndRequestPrimary() async throws {
        try await announcePresence()
        try await send(["type": "request_primary"])
    }

    private func send(_ object: [String: Any]) async throws {
        guard let socket else { return }
        let data = try JSONSerialization.data(withJSONObject: object)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, self.shouldRun else { return }
                try? await self.send(["type": "ping"])
            }
        }
    }

    private func scheduleReconnect(_ error: Error) async {
        guard shouldRun else { return }
        connected = false
        audioTransport.setEnabled(false)
        audioTransport.configure(socket: nil)
        audio.resetPlayback()
        socket?.cancel()
        socket = nil
        heartbeat?.cancel()
        lastError = "Connection interrupted: \(error.localizedDescription). Reconnecting automatically."
        attempt += 1
        state = "RECONNECTING"
        let delay = min(30.0, pow(2.0, Double(min(attempt, 5))))
        reconnect?.cancel()
        reconnect = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.shouldRun else { return }
            await self.connect()
        }
        _ = error
    }
}




