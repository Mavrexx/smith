import AVFoundation
import MediaPlayer
import PhotosUI
import SwiftUI
import UIKit

struct SmithVisionPage: View {
    @ObservedObject var model: SmithModel
    @State private var photo: PhotosPickerItem?
    @State private var cameraOpen = false
    @State private var message = "Choose Camera or Photos. Smith analyses only the image you explicitly share."

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().stroke(.cyan.opacity(0.28), lineWidth: 1).frame(width: 190, height: 190)
                Circle().fill(.cyan.opacity(0.06)).frame(width: 154, height: 154)
                Image(systemName: "camera.aperture").font(.system(size: 78, weight: .ultraLight))
                    .foregroundStyle(.cyan).shadow(color: .cyan.opacity(0.5), radius: 14)
            }
            Text("WHAT DO YOU WANT TO SEE?").font(.system(size: 12, weight: .medium, design: .monospaced)).tracking(1.5)
            Text(message).font(.caption).foregroundStyle(.white.opacity(0.52)).multilineTextAlignment(.center).padding(.horizontal, 25)
            HStack(spacing: 10) {
                Button { cameraOpen = true } label: {
                    Label("Camera", systemImage: "camera").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.cyan).foregroundStyle(.black)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Photos", systemImage: "photo").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.cyan)
            }.padding(.horizontal, 18)
            Spacer()
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let prepared = preparedJPEG(data) else {
                        message = "That image could not be reduced under Smith's secure 192 KB limit."
                        return
                    }
                    await model.voice.sendImage(prepared, mimeType: "image/jpeg", name: "iPhone photo.jpg")
                    message = model.voice.lastError ?? "Image sent securely to the active Smith conversation."
                } catch { message = error.localizedDescription }
            }
        }
        .fullScreenCover(isPresented: $cameraOpen) {
            SmithCameraPicker { image in
                cameraOpen = false
                guard let input = image.jpegData(compressionQuality: 0.8), let prepared = preparedJPEG(input) else {
                    message = "Camera image could not be prepared."
                    return
                }
                Task {
                    await model.voice.sendImage(prepared, mimeType: "image/jpeg", name: "iPhone camera.jpg")
                    message = model.voice.lastError ?? "Camera image sent securely to Smith."
                }
            }.ignoresSafeArea()
        }
    }

    private func preparedJPEG(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maximum: CGFloat = 900
        let scale = min(1, maximum / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        for quality in [0.68, 0.52, 0.38, 0.25] {
            if let value = resized.jpegData(compressionQuality: quality), value.count < 185_000 { return value }
        }
        return nil
    }
}

struct SmithCameraPicker: UIViewControllerRepresentable {
    let completion: (UIImage) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage) -> Void
        init(completion: @escaping (UIImage) -> Void) { self.completion = completion }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { completion(image) }
            else { picker.dismiss(animated: true) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
    }
}

struct SmithHealthPage: View {
    @ObservedObject var model: SmithModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("System & Privacy").font(.title3.weight(.light))
                status("Microphone permission", microphonePermission, "mic", microphonePermission == "Allowed" ? .green : .orange)
                status("Realtime socket", model.voice.connected ? "Connected" : model.voice.state.capitalized, "network", model.voice.connected ? .green : .orange)
                status("Audio packets sent", String(model.voice.audioPacketsSent), "waveform", model.voice.audioPacketsSent > 0 ? .green : .orange)
                status("Live input level", String(format: "%.0f%%", model.voice.microphoneLevel * 100), "gauge.with.dots.needle.67percent", model.voice.microphoneLevel > 0.01 ? .green : .cyan)
                status("Keyboard input", model.voice.connected ? "Available" : "Waiting for Core", "keyboard", model.voice.connected ? .green : .orange)
                VStack(alignment: .leading, spacing: 8) {
                    Label("PRIVACY, ALWAYS", systemImage: "lock.shield.fill").font(.caption.monospaced()).foregroundStyle(.cyan)
                    Text("Encrypted HTTPS/WSS • device credential in Keychain • explicit image sharing • no hidden capture • Smith Core keeps memory and history.")
                        .font(.caption).foregroundStyle(.white.opacity(0.55))
                }
                .padding(14).background(.cyan.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.cyan.opacity(0.14)))
                if let error = model.voice.lastError {
                    Text(error).font(.caption.monospaced()).foregroundStyle(.orange).padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
                }
            }.padding(16)
        }
    }

    private var microphonePermission: String {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: "Allowed"
        case .denied: "Denied"
        case .undetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }
    private func status(_ name: String, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 28)
            Text(name).font(.system(size: 13))
            Spacer()
            Text(value).font(.system(size: 10, design: .monospaced)).foregroundStyle(tint)
        }.padding(13).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
    }
}

struct SmithSystemVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = true
        view.showsVolumeSlider = true
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {}
}

struct SmithSettingsPage: View {
    @ObservedObject var model: SmithModel
    @ObservedObject private var voice: SmithVoiceSession

    init(model: SmithModel) {
        self.model = model
        _voice = ObservedObject(wrappedValue: model.voice)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("Smith Core").font(.title3.weight(.light))
                TextField("Private HTTPS address", text: $model.serverAddress)
                    .textInputAutocapitalization(.never).keyboardType(.URL).smithInput()
                SecureField("New one-time setup code", text: $model.accessCode).smithInput()
                Button("Re-register this iPhone") { Task { await model.register() } }
                    .buttonStyle(.borderedProminent).tint(.cyan).foregroundStyle(.black)
                    .disabled(model.accessCode.isEmpty || model.serverAddress.isEmpty)
                Text(model.status).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.55))
                Divider().overlay(.cyan.opacity(0.15))
                Text("Voice controls").font(.headline)
                Button(voice.muted ? "Unmute Smith" : "Mute Smith") {
                    if voice.state == "IDLE" {
                        Task { await model.wake() }
                    } else {
                        voice.toggleMuted()
                    }
                }
                .buttonStyle(.bordered).tint(.cyan)

                Button("Retry microphone") { voice.retryMicrophone() }
                    .buttonStyle(.bordered).tint(.cyan)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Smith voice boost")
                        Spacer()
                        Text("\(voice.outputVolume)%").font(.caption.monospaced()).foregroundStyle(.cyan)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(voice.outputVolume) },
                            set: { _ = voice.setSmithVolume(percent: Int($0)) }
                        ),
                        in: 0...100,
                        step: 5
                    ).tint(.cyan)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("iPhone system volume").font(.subheadline)
                    SmithSystemVolumeView()
                        .frame(height: 34)
                    Text("Apple requires system volume to be changed through this visible control.")
                        .font(.caption2).foregroundStyle(.white.opacity(0.45))
                }

                Button("Reconnect realtime voice") {
                    Task { await voice.stop(); await model.wake() }
                }.buttonStyle(.bordered).tint(.cyan)

                Button("Open Permissions") { model.openWorkspace(.permissions) }
                    .buttonStyle(.bordered).tint(.cyan)

                Text("Server: \(model.serverAddress)")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.38)).textSelection(.enabled)
            }.padding(16)
        }
    }
}