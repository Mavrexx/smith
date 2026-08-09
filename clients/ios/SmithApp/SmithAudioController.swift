import AVFoundation
import Foundation

final class SmithAudioController {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var converter: AVAudioConverter?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?

    init() {
        engine.attach(player)
        let output = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24_000,
            channels: 1,
            interleaved: false
        )!
        engine.connect(player, to: engine.mainMixerNode, format: output)
        observeAudioChanges()
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
    }

    func startCapture(onPCM16: @escaping @Sendable (Data) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)

        let input = engine.inputNode
        let sourceFormat = input.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2_048, format: sourceFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }
            let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil,
                  converted.frameLength > 0,
                  let samples = converted.int16ChannelData?.pointee else { return }
            onPCM16(Data(bytes: samples, count: Int(converted.frameLength) * MemoryLayout<Int16>.size))
        }
        try startEngineIfNeeded()
    }

    func play(pcm16 data: Data) {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24_000,
            channels: 1,
            interleaved: false
        )!
        let frames = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let destination = buffer.int16ChannelData?.pointee else { return }
        buffer.frameLength = frames
        data.withUnsafeBytes { source in
            if let baseAddress = source.baseAddress {
                memcpy(destination, baseAddress, data.count)
            }
        }
        try? startEngineIfNeeded()
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer)
    }

    func resetPlayback() {
        player.stop()
        player.reset()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        resetPlayback()
        engine.stop()
        converter = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    private func observeAudioChanges() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                self.resetPlayback()
            } else {
                try? AVAudioSession.sharedInstance().setActive(true)
                try? self.startEngineIfNeeded()
            }
        }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            try? self?.startEngineIfNeeded()
        }
    }
}
