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
        let playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24_000,
            channels: 1,
            interleaved: false
        )
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        observeAudioChanges()
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
    }

    func startCapture(onPCM16: @escaping @Sendable (Data, Float) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetooth, .defaultToSpeaker]
        )
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)

        let input = engine.inputNode
        let sourceFormat = input.outputFormat(forBus: 0)
        guard sourceFormat.sampleRate.isFinite,
              sourceFormat.sampleRate > 0,
              sourceFormat.channelCount > 0 else {
            throw AudioError.invalidInputFormat
        }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let audioConverter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioError.converterUnavailable
        }
        converter = audioConverter
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2_048, format: nil) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }
            let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
            let capacity = max(1, AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1)
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var supplied = false
            var conversionError: NSError?
            converter.convert(to: converted, error: &conversionError) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            guard conversionError == nil,
                  converted.frameLength > 0,
                  let samples = converted.int16ChannelData?.pointee else { return }
            let count = Int(converted.frameLength)
            var energy: Double = 0
            for index in 0..<count {
                let value = Double(samples[index]) / 32_768.0
                energy += value * value
            }
            let level = Float(min(1, sqrt(energy / Double(max(1, count))) * 12))
            onPCM16(Data(bytes: samples, count: count * MemoryLayout<Int16>.size), level)
        }
        do {
            try startEngineIfNeeded()
        } catch {
            input.removeTap(onBus: 0)
            converter = nil
            throw error
        }
    }

    func play(pcm16 data: Data) {
        let frames = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frames > 0,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 24_000,
                channels: 1,
                interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let destination = buffer.floatChannelData?.pointee else { return }

        buffer.frameLength = frames
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for index in 0..<min(Int(frames), samples.count) {
                destination[index] = Float(Int16(littleEndian: samples[index])) / 32_768
            }
        }
        do {
            try startEngineIfNeeded()
            if !player.isPlaying { player.play() }
            player.scheduleBuffer(buffer)
        } catch {
            resetPlayback()
        }
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

    private enum AudioError: LocalizedError {
        case invalidInputFormat
        case converterUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidInputFormat:
                "The microphone audio route is not ready. Disconnect Bluetooth audio and try again."
            case .converterUnavailable:
                "Smith could not prepare the microphone audio converter."
            }
        }
    }
}
