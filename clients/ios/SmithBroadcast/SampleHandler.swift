import CoreImage
import Foundation
import ImageIO
import Network
import ReplayKit
import UniformTypeIdentifiers

final class SampleHandler: RPBroadcastSampleHandler {
    private static let port = NWEndpoint.Port(rawValue: 48_173)!
    private static let magic = Data("SMTHSCR1".utf8)
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let networkQueue = DispatchQueue(label: "smith.screen.sender", qos: .utility)
    private let stateQueue = DispatchQueue(label: "smith.screen.sender.state")
    private var lastFrameTime: TimeInterval = 0
    private var frameInFlight = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) { lastFrameTime = 0 }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrameTime >= 2, claimFrameSlot() else { return }
        lastFrameTime = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let data = jpegData(from: pixelBuffer) else {
            releaseFrameSlot()
            return
        }
        send(data, finished: { [weak self] in self?.releaseFrameSlot() })
    }

    override func broadcastFinished() { send(Data(), finished: {}) }

    private func jpegData(from pixelBuffer: CVPixelBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let scale = min(1, 720 / max(extent.width, extent.height))
        let resized = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        for quality in [0.42, 0.28] {
            if let value = encodedJPEG(resized, quality: quality), value.count <= 190_000 {
                return value
            }
        }
        return nil
    }

    private func encodedJPEG(_ image: CIImage, quality: Double) -> Data? {
        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private func send(_ frame: Data, finished: @escaping () -> Void) {
        var length = UInt32(frame.count).bigEndian
        var packet = Self.magic
        withUnsafeBytes(of: &length) { packet.append(contentsOf: $0) }
        packet.append(frame)
        let connection = NWConnection(host: "127.0.0.1", port: Self.port, using: .tcp)
        var completed = false
        let finishOnce = {
            self.stateQueue.sync {
                guard !completed else { return }
                completed = true
                finished()
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: packet, completion: .contentProcessed { _ in
                    connection.cancel()
                    finishOnce()
                })
            case .failed, .cancelled:
                finishOnce()
            default:
                break
            }
        }
        connection.start(queue: networkQueue)
        networkQueue.asyncAfter(deadline: .now() + 1.5) {
            connection.cancel()
            finishOnce()
        }
    }

    private func claimFrameSlot() -> Bool {
        stateQueue.sync {
            guard !frameInFlight else { return false }
            frameInFlight = true
            return true
        }
    }

    private func releaseFrameSlot() { stateQueue.async { self.frameInFlight = false } }
}
