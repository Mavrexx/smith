import Combine
import AVFoundation
import Foundation

@MainActor
final class SmithVoiceSession: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var state = "IDLE"
    @Published private(set) var transcript = ""
    @Published private(set) var userTranscript = ""
    @Published private(set) var assistantTranscript = ""
    @Published private(set) var lastError: String?
    @Published private(set) var muted = false

    private let api: SmithAPI
    private let audio = SmithAudioController()
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
        guard !shouldRun else { return }
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
        muted.toggle()
        state = muted ? "MUTED" : (connected ? "LISTENING" : "IDLE")
        liveActivity.update(
            state: state,
            subtitle: muted ? "Microphone transmission stopped" : "Smith is listening"
        )
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
        captureStarted = false
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
            task.resume()
            receive(on: task)
            startHeartbeat()
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
            startCaptureIfNeeded()
        case "audio":
            if let encoded = payload["data"] as? String,
               let chunk = Data(base64Encoded: encoded) {
                state = "SPEAKING"
                liveActivity.update(state: "SPEAKING", subtitle: transcript.isEmpty ? "Smith is responding" : transcript)
                audio.play(pcm16: chunk)
            }
        case "audioReset", "interrupted":
            audio.resetPlayback()
            state = muted ? "MUTED" : "LISTENING"
        case "transcript":
            if let text = payload["text"] as? String {
                transcript = text
                if payload["role"] as? String == "user" {
                    userTranscript = text
                } else {
                    assistantTranscript = text
                }
            }
        case "turnComplete":
            state = muted ? "MUTED" : "LISTENING"
        case "reconnecting":
            audio.resetPlayback()
            state = "RECONNECTING"
            liveActivity.update(state: "RECONNECTING", subtitle: "Restoring the private voice link")
        case "error":
            lastError = payload["message"] as? String ?? "Realtime session error"
        default:
            break
        }
    }

    private func startCaptureIfNeeded() {
        guard !captureStarted else { return }
        do {
            try audio.startCapture { [weak self] data in
                Task { @MainActor in
                    guard let self, self.shouldRun, self.connected, !self.muted else { return }
                    try? await self.send([
                        "type": "audio",
                        "data": data.base64EncodedString(),
                    ])
                }
            }
            captureStarted = true
        } catch {
            lastError = "Audio session could not start: \(error.localizedDescription)"
        }
    }

    private func send(_ object: [String: String]) async throws {
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
        audio.resetPlayback()
        socket?.cancel()
        socket = nil
        heartbeat?.cancel()
        lastError = "Connection interrupted; reconnecting automatically."
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




