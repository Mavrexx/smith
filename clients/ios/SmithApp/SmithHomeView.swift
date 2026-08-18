import SafariServices
import SwiftUI

enum SmithPage: String, CaseIterable, Identifiable {
    case ask = "Ask Smith", vision = "Vision", memory = "Memory", tasks = "Tasks"
    case devices = "Devices", files = "Files", automations = "Automations", health = "Health"
    case permissions = "Permissions", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .ask: "bubble.left.and.waveform"
        case .vision: "camera.viewfinder"
        case .memory: "brain.head.profile"
        case .tasks: "checklist"
        case .devices: "desktopcomputer.and.iphone"
        case .files: "folder"
        case .automations: "bolt"
        case .health: "heart"
        case .permissions: "hand.raised.fill"
        case .settings: "gearshape"
        }
    }
}

struct SmithHomeView: View {
    @ObservedObject var model: SmithModel
    @State private var page: SmithPage = .ask
    @State private var dockOpen = false
    @State private var command = ""
    @State private var displayedMuted = false
    @State private var safariDestination: SmithSafariDestination?
    @FocusState private var commandFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    header
                    if !model.isRegistered {
                        SmithSetupPage(model: model)
                    } else if page == .ask {
                        askPage(height: proxy.size.height)
                    } else {
                        SmithFeaturePage(page: page, model: model)
                    }
                }
                if model.isRegistered {
                    VStack(spacing: 10) {
                        if dockOpen { dock.transition(.move(edge: .bottom).combined(with: .opacity)) }
                        dockHandle
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: dockOpen)
        .onReceive(model.$requestedRoute) { route in
            guard let route else { return }
            page = pageForRoute(route)
            dockOpen = false
        }
        .onReceive(model.voice.$muted) { displayedMuted = $0 }
        .onReceive(model.voice.$requestedPage) { requested in
            guard let requested,
                  let destination = SmithPage.allCases.first(where: {
                      $0.rawValue.lowercased() == requested.lowercased()
                  }) else { return }
            page = destination
            dockOpen = false
            model.voice.requestedPage = nil
        }
        .onReceive(model.voice.$safariDestination) { safariDestination = $0 }
        .sheet(item: $safariDestination, onDismiss: {
            model.voice.safariDestination = nil
        }) { destination in
            SmithSafariView(url: destination.url).ignoresSafeArea()
        }
        .task {
            guard model.isRegistered else { return }
            await model.wake()
        }
    }

    private func pageForRoute(_ route: SmithRoute) -> SmithPage {
        switch route {
        case .voice, .text, .conversations, .share, .clipboard: return .ask
        case .memory: return .memory
        case .tasks, .reminders: return .tasks
        case .devices: return .devices
        case .files: return .files
        case .permissions: return .permissions
        case .settings: return .settings
        default: return .ask
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("S M I T H").font(.system(size: 17, weight: .light, design: .rounded)).tracking(3)
                Text(page.rawValue.uppercased())
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.8).foregroundStyle(.cyan)
            }
            Spacer()
            Circle().fill(connectionColor).frame(width: 6, height: 6).shadow(color: connectionColor, radius: 4)
            Text(connectionText).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
            Button(action: toggleMicrophone) {
                Image(systemName: displayedMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 12)).foregroundStyle(displayedMuted ? .orange : .cyan)
                    .frame(width: 44, height: 44).background(.white.opacity(0.055), in: Circle())
                    .overlay(Circle().stroke(.cyan.opacity(0.15)))
            }
            .buttonStyle(.plain).contentShape(Circle())
            .accessibilityLabel(displayedMuted ? "Unmute Smith" : "Mute Smith")
            .accessibilityHint("Stops or resumes microphone transmission immediately")
        }
        .padding(.horizontal, 17).padding(.top, 8).padding(.bottom, 10).background(.black.opacity(0.22))
    }

    private var connectionText: String {
        if !model.isRegistered { return "SETUP" }
        if displayedMuted { return "MUTED" }
        if model.voice.connected && model.voice.audioPacketsSent > 0 { return "LIVE" }
        if model.voice.commandChannelConnected && !model.voice.connected { return "REMOTE" }
        return model.voice.state
    }

    private var connectionColor: Color {
        if model.voice.lastError != nil && !model.voice.commandChannelConnected { return .red }
        if displayedMuted { return .orange }
        if model.voice.connected { return .green }
        if model.voice.commandChannelConnected { return .cyan }
        return .cyan
    }

    private func askPage(height: CGFloat) -> some View {
        VStack(spacing: 9) {
            Spacer(minLength: 2)
            Text(greeting).font(.system(size: 13, weight: .light)).foregroundStyle(.white.opacity(0.64))
            Button {
                Task {
                    if model.voice.connected { model.voice.toggleMuted() }
                    else { await model.wake() }
                }
            } label: {
                SmithCoreOrb(voice: model.voice, diameter: min(214, height * 0.285))
            }
            .buttonStyle(.plain)
            Text(model.voice.state)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(2.4).foregroundStyle(stateColor)
            if model.voice.connected {
                Text(model.voice.audioPacketsSent > 0 ? "Microphone streaming to Smith Core" : "Preparing microphone stream…")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.42))
            }
            if !model.voice.userTranscript.isEmpty || !model.voice.assistantTranscript.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if !model.voice.userTranscript.isEmpty { transcriptRow("YOU", model.voice.userTranscript, .white) }
                        if !model.voice.assistantTranscript.isEmpty { transcriptRow("SMITH", model.voice.assistantTranscript, .cyan) }
                    }.padding(.horizontal, 15)
                }
                .frame(maxHeight: max(90, height * 0.18))
            } else {
                Text("Tap the orb and speak, or type below.").font(.caption).foregroundStyle(.white.opacity(0.42)).padding(.vertical, 7)
            }
            if let error = model.voice.lastError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.72))
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.18))).padding(.horizontal, 14)
            }
            composer.padding(.bottom, dockOpen ? 226 : 62)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        return hour < 12 ? "Good morning." : hour < 18 ? "Good afternoon." : "Good evening."
    }

    private var stateColor: Color {
        switch model.voice.state {
        case "LISTENING": .cyan
        case "SPEAKING": .green
        case "THINKING": .blue
        case "MUTED": .orange
        case "RECONNECTING": .yellow
        default: .white.opacity(0.62)
        }
    }

    private func transcriptRow(_ role: String, _ text: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(role).font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(color.opacity(0.75))
            Text(text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.86)).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(11)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(color.opacity(0.1)))
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message Smith…", text: $command, axis: .vertical)
                .focused($commandFocused).lineLimit(1...4).submitLabel(.send).onSubmit(sendCommand)
                .padding(.horizontal, 13).padding(.vertical, 11)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.cyan.opacity(commandFocused ? 0.38 : 0.13)))
            Button(action: sendCommand) {
                Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 39, height: 39).background(.cyan, in: Circle()).shadow(color: .cyan.opacity(0.35), radius: 8)
            }
            .buttonStyle(.plain).disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(.horizontal, 14)
    }

    private func sendCommand() {
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        command = ""; commandFocused = false
        Task { await model.voice.sendText(text) }
    }

    private func toggleMicrophone() {
        Task {
            if model.voice.state == "IDLE" || model.voice.state == "PERMISSION REQUIRED" {
                await model.wake()
            } else {
                model.voice.toggleMuted()
            }
        }
    }

    private var dockHandle: some View {
        HStack {
            Button(action: toggleMicrophone) {
                VStack(spacing: 2) {
                    Image(systemName: displayedMuted ? "mic.slash.fill" : "mic.fill")
                    Text(displayedMuted ? "UNMUTE" : "MUTE")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(displayedMuted ? .orange : .cyan)
                .frame(width: 52, height: 44)
                .background((displayedMuted ? Color.orange : Color.cyan).opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(displayedMuted ? "Unmute Smith" : "Mute Smith")
            .accessibilityHint("Stops or resumes microphone transmission immediately")

            Spacer()

            Button {
                page = .ask
                commandFocused = false
                dockOpen = false
            } label: {
                Image(systemName: "house.fill").foregroundStyle(.cyan)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Smith Home")

            Spacer()

            Button {
                commandFocused = false
                dockOpen.toggle()
            } label: {
                ZStack {
                    Circle().fill(.cyan.opacity(0.1)).frame(width: 44, height: 44)
                    Image(systemName: dockOpen ? "chevron.down" : "circle.grid.3x3.fill").foregroundStyle(.cyan)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(dockOpen ? "Close app dock" : "Open app dock")

            Spacer()

            Button {
                dockOpen = false
                Task { await model.voice.stop() }
            } label: {
                Image(systemName: "xmark").foregroundStyle(.white.opacity(0.62))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop Smith voice")
        }
        .font(.system(size: 13)).padding(.horizontal, 8).frame(height: 54)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.cyan.opacity(0.19)))
    }

    private var dock: some View {
        VStack(spacing: 10) {
            HStack {
                Text("APP DOCK").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(.cyan)
                Spacer()
                Text("ONE TAP AWAY").font(.system(size: 8, design: .monospaced)).foregroundStyle(.white.opacity(0.38))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(SmithPage.allCases) { item in
                    Button {
                        page = item; dockOpen = false
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.symbol).font(.system(size: 17, weight: .light)).foregroundStyle(item == page ? .white : .cyan)
                            Text(item.rawValue).font(.system(size: 8, weight: .medium)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 49)
                        .background(item == page ? .cyan.opacity(0.18) : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.cyan.opacity(item == page ? 0.35 : 0.10)))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23))
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(.cyan.opacity(0.17)))
    }
}

struct SmithSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = .cyan
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

struct SmithCoreOrb: View {
    @ObservedObject var voice: SmithVoiceSession
    let diameter: CGFloat
    @State private var orbit = false
    @State private var pulse = false
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle().stroke(.cyan.opacity(0.08 - Double(index) * 0.015), lineWidth: 1)
                    .frame(width: diameter * (1.05 + CGFloat(index) * 0.10)).scaleEffect(pulse ? 1.025 : 0.975)
            }
            Circle()
                .stroke(AngularGradient(colors: [.clear, .cyan, .white.opacity(0.8), .blue, .clear], center: .center), lineWidth: max(2, diameter * 0.017))
                .frame(width: diameter, height: diameter).rotationEffect(.degrees(orbit ? 360 : 0)).shadow(color: .cyan.opacity(0.75), radius: 12)
            Circle()
                .fill(RadialGradient(colors: [.cyan.opacity(0.27 + Double(voice.microphoneLevel) * 0.32), .blue.opacity(0.12), .black.opacity(0.36)], center: .center, startRadius: 0, endRadius: diameter * 0.49))
                .frame(width: diameter * 0.92, height: diameter * 0.92)
            SmithWaveform(level: voice.microphoneLevel, active: voice.connected && !voice.muted)
                .frame(width: diameter * 0.62, height: diameter * 0.27)
            Text("SMITH").font(.system(size: diameter * 0.105, weight: .ultraLight, design: .rounded))
                .tracking(diameter * 0.025).foregroundStyle(.white.opacity(0.75)).offset(y: diameter * 0.22)
        }
        .frame(width: diameter * 1.28, height: diameter * 1.28)
        .onAppear {
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) { orbit = true }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

struct SmithWaveform: View {
    let level: Float
    let active: Bool
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<17, id: \.self) { index in
                let distance = abs(index - 8)
                let base = max(3, 18 - CGFloat(distance) * 1.7)
                Capsule().fill(active ? Color.cyan : Color.white.opacity(0.18)).frame(width: 2.2, height: base + CGFloat(level) * CGFloat(42 - distance * 2))
            }
        }.animation(.linear(duration: 0.08), value: level)
    }
}