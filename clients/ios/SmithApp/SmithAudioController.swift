import AVFoundation
import Foundation

final class SmithAudioController {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var converter: AVAudioConverter?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var captureHandler: (@Sendable (Data, Float) -> Void)?
    private var reconfiguring = false
    private(set) var outputGain: Float = 1.65

    init() {
        engine.attach(player)
        let playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24_000,
            channels: 1,
            interleaved: false
        )
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        player.volume = 1
        engine.mainMixerNode.outputVolume = 1
        observeAudioChanges()
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
    }

    func startCapture(onPCM16: @escaping @Sendable (Data, Float) -> Void) throws {
        captureHandler = onPCM16
        try configureCapture(onPCM16: onPCM16)
    }

    func restartCapture() throws {
        guard let captureHandler else { throw AudioError.captureUnavailable }
        try configureCapture(onPCM16: captureHandler)
    }

    func setOutputGain(_ gain: Float) -> Int {
        outputGain = min(2.5, max(0.35, gain))
        return Int((outputGain / 2.5 * 100).rounded())
    }

    func adjustOutputGain(by delta: Float) -> Int {
        setOutputGain(outputGain + delta)
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
        let gain = outputGain
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for index in 0..<min(Int(frames), samples.count) {
                let value = Float(Int16(littleEndian: samples[index])) / 32_768
                destination[index] = tanh(value * gain)
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
        captureHandler = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func configureCapture(onPCM16: @escaping @Sendable (Data, Float) -> Void) throws {
        guard !reconfiguring else { return }
        reconfiguring = true
        defer { reconfiguring = false }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP, .defaultToSpeaker]
        )
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.01)
        try session.setActive(true)
        if session.currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) {
            try? session.overrideOutputAudioPort(.speaker)
        }

        let input = engine.inputNode
        input.removeTap(onBus: 0)
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

        // 20 ms capture packets keep voice responsive without exceeding the
        // server's 120-packet/second protection.
        let tapFrames = AVAudioFrameCount(max(320, sourceFormat.sampleRate * 0.02))
        input.installTap(onBus: 0, bufferSize: tapFrames, format: nil) { [weak self] buffer, _ in
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
                let value = Double(samples[index]) / 32_768
                energy += value * value
            }
            let level = Float(min(1, sqrt(energy / Double(max(1, count))) * 14))
            onPCM16(Data(bytes: samples, count: count * MemoryLayout<Int16>.size), level)
        }
        try startEngineIfNeeded()
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    private func restoreCaptureAfterAudioChange() {
        guard let handler = captureHandler else { return }
        resetPlayback()
        engine.stop()
        converter = nil
        do {
            try configureCapture(onPCM16: handler)
        } catch {
            // The next explicit microphone retry will surface a user-facing error.
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
                self.restoreCaptureAfterAudioChange()
            }
        }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restoreCaptureAfterAudioChange()
        }
    }

    private enum AudioError: LocalizedError {
        case invalidInputFormat
        case converterUnavailable
        case captureUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidInputFormat:
                "The microphone audio route is not ready. Disconnect Bluetooth audio and try again."
            case .converterUnavailable:
                "Smith could not prepare the microphone audio converter."
            case .captureUnavailable:
                "Start Smith once before retrying the microphone."
            }
        }
    }
}