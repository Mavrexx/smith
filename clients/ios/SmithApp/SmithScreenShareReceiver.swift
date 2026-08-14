import Combine
import Foundation
import Network

@MainActor
final class SmithScreenShareReceiver: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var frameCount = 0
    @Published private(set) var lastError: String?

    var onFrame: ((Data) -> Void)?

    private static let port = NWEndpoint.Port(rawValue: 48_173)!
    private static let magic = Data("SMTHSCR1".utf8)
    private static let maximumFrameBytes = 190_000
    private let networkQueue = DispatchQueue(label: "smith.screen.receiver", qos: .utility)
    private var listener: NWListener?
    private var staleTimer: DispatchSourceTimer?
    private var lastFrameAt: Date?

    func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp, on: Self.port)
            listener.newConnectionHandler = { [weak self] connection in self?.receive(connection) }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    Task { @MainActor in self?.lastError = "Screen receiver: \(error.localizedDescription)" }
                }
            }
            self.listener = listener
            listener.start(queue: networkQueue)
            startStaleTimer()
        } catch {
            lastError = "Screen receiver could not start: \(error.localizedDescription)"
        }
    }

    private nonisolated func receive(_ connection: NWConnection) {
        var buffer = Data()
        var receiveNext: (() -> Void)!
        receiveNext = { [weak self, weak connection] in
            guard let self, let connection else { return }
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
                [weak self, weak connection] data, _, complete, error in
                guard let self, let connection else { return }
                if let data { buffer.append(data) }
                if buffer.count >= 12 {
                    guard buffer.prefix(8) == Self.magic else { connection.cancel(); return }
                    let length = buffer[8..<12].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                    if length == 0 {
                        Task { @MainActor in self.markStopped() }
                        connection.cancel()
                        return
                    }
                    guard length <= Self.maximumFrameBytes else { connection.cancel(); return }
                    if buffer.count >= 12 + Int(length) {
                        let frame = Data(buffer[12..<(12 + Int(length))])
                        Task { @MainActor in self.accept(frame) }
                        connection.cancel()
                        return
                    }
                }
                if error != nil || complete || buffer.count > 12 + Self.maximumFrameBytes {
                    connection.cancel()
                } else {
                    receiveNext()
                }
            }
        }
        connection.start(queue: networkQueue)
        receiveNext()
    }

    private func accept(_ frame: Data) {
        active = true
        frameCount += 1
        lastFrameAt = Date()
        lastError = nil
        onFrame?(frame)
    }

    private func markStopped() {
        active = false
        lastFrameAt = nil
    }

    private func startStaleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: networkQueue)
        timer.schedule(deadline: .now() + 3, repeating: 3)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self, let lastFrameAt = self.lastFrameAt else { return }
                if Date().timeIntervalSince(lastFrameAt) > 7 { self.active = false }
            }
        }
        staleTimer = timer
        timer.resume()
    }
}
