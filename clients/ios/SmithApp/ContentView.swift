import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: SmithModel

    var body: some View {
        ZStack {
            SmithBlueprintBackground()
                .ignoresSafeArea()

            switch model.environment {
            case .idle:
                SmithIdleEnvironment(model: model)
            case .awake:
                SmithCommandCentre(model: model)
            case .workspace:
                SmithWorkspaceEnvironment(model: model)
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(model.voice.$userTranscript) { transcript in
            model.handleUserTranscript(transcript)
        }
    }
}

private struct SmithBlueprintBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.015, green: 0.035, blue: 0.055), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Canvas { context, size in
                var minor = Path()
                let spacing: CGFloat = 32
                for x in stride(from: CGFloat.zero, through: size.width, by: spacing) {
                    minor.move(to: CGPoint(x: x, y: 0))
                    minor.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: CGFloat.zero, through: size.height, by: spacing) {
                    minor.move(to: CGPoint(x: 0, y: y))
                    minor.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(minor, with: .color(.cyan.opacity(0.055)), lineWidth: 0.5)

                var axes = Path()
                axes.move(to: CGPoint(x: size.width / 2, y: 0))
                axes.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                axes.move(to: CGPoint(x: 0, y: size.height / 2))
                axes.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(axes, with: .color(.cyan.opacity(0.09)), lineWidth: 0.75)
            }
        }
    }
}

private struct SmithIdleEnvironment: View {
    @ObservedObject var model: SmithModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 19) {
                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 42, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.9))

                Button {
                    Task { await model.wake() }
                } label: {
                    SmithOrbView(voice: model.voice, diameter: 206)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wake Smith")

                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.caption.monospaced())
                    .textCase(.uppercase)
                    .tracking(2.2)
                    .foregroundStyle(.white.opacity(0.48))

                SmithConnectionPill(model: model, compact: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SmithCommandCentre: View {
    @ObservedObject var model: SmithModel

    private let modules: [(String, String, SmithRoute)] = [
        ("Search", "sparkle.magnifyingglass", .search),
        ("Apps", "square.grid.2x2", .apps),
        ("Devices", "iphone.and.arrow.forward", .devices),
        ("Protocols", "bolt.shield", .protocols),
        ("Memory", "brain.head.profile", .memory),
        ("Conversation", "quote.bubble", .voice),
        ("Settings", "slider.horizontal.3", .settings),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack {
                    HStack {
                        Button {
                            model.returnToIdle()
                        } label: {
                            Image(systemName: "circle.grid.cross")
                                .font(.system(size: 15, weight: .light))
                                .foregroundStyle(.cyan.opacity(0.8))
                                .frame(width: 42, height: 42)
                        }
                        .accessibilityLabel("Return Smith to idle")
                        Spacer()
                        SmithConnectionPill(model: model, compact: false)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                VStack(spacing: 10) {
                    SmithOrbView(voice: model.voice, diameter: min(proxy.size.width * 0.48, 206))
                    Text(model.voice.state)
                        .font(.caption2.monospaced())
                        .tracking(2)
                        .foregroundStyle(.cyan.opacity(0.7))
                }
                .offset(y: -proxy.size.height * 0.12)

                VStack(spacing: 12) {
                    Text("COMMAND CENTRE")
                        .font(.caption2.monospaced())
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.43))

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(modules, id: \.0) { module in
                            Button {
                                model.openWorkspace(module.2)
                            } label: {
                                VStack(spacing: 7) {
                                    Image(systemName: module.1)
                                        .font(.system(size: 18, weight: .light))
                                    Text(module.0)
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.65)
                                }
                                .foregroundStyle(.cyan.opacity(0.88))
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .background(.ultraThinMaterial.opacity(0.56), in: RoundedRectangle(cornerRadius: 15))
                                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.cyan.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14)
                .background(.thinMaterial.opacity(0.72), in: RoundedRectangle(cornerRadius: 25))
                .overlay(RoundedRectangle(cornerRadius: 25).stroke(.cyan.opacity(0.13)))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

private struct SmithWorkspaceEnvironment: View {
    @ObservedObject var model: SmithModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    model.closeWorkspace()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close workspace")

                VStack(alignment: .leading, spacing: 2) {
                    Text(workspaceTitle)
                        .font(.caption.monospaced())
                        .tracking(2)
                    Text(model.voice.state)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.cyan.opacity(0.65))
                }

                Spacer()

                SmithConnectionPill(model: model, compact: true)
                SmithOrbView(voice: model.voice, diameter: 54)
                    .accessibilityLabel("Smith remains active")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial.opacity(0.76))

            workspaceContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var workspaceTitle: String {
        guard let route = model.workspace else { return "WORKSPACE" }
        return route == .voice ? "CONVERSATION" : route.rawValue.uppercased()
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch model.workspace {
        case .some(.voice), .some(.conversations):
            SmithConversationWorkspace(model: model)
        case .some(.memory), .some(.tasks):
            SmithEditorWorkspace(model: model, route: model.workspace ?? .memory)
        case .some(.settings):
            SmithSettingsWorkspace(model: model)
        case .some(.search), .some(.apps), .some(.devices), .some(.protocols),
             .some(.maps), .some(.files), .some(.music),
             .some(.text), .some(.reminders), .some(.clipboard), .some(.share):
            SmithGenericWorkspace(model: model, route: model.workspace ?? .search)
        case .none:
            EmptyView()
        }
    }
}

private struct SmithConversationWorkspace: View {
    @ObservedObject var model: SmithModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Conversation is an optional Smith workspace. Closing it returns to Command Centre.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                transcriptCard(
                    label: "YOU",
                    text: model.voice.userTranscript.isEmpty ? "Listening…" : model.voice.userTranscript,
                    color: .white
                )
                transcriptCard(
                    label: "SMITH",
                    text: model.voice.assistantTranscript.isEmpty ? "Ready." : model.voice.assistantTranscript,
                    color: .cyan
                )
            }
            .padding(18)
        }
    }

    private func transcriptCard(label: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption2.monospaced())
                .tracking(2)
                .foregroundStyle(color.opacity(0.7))
            Text(text)
                .font(.body)
                .foregroundStyle(.white.opacity(0.88))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial.opacity(0.58), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.12)))
    }
}

private struct SmithEditorWorkspace: View {
    @ObservedObject var model: SmithModel
    let route: SmithRoute

    var body: some View {
        VStack(spacing: 14) {
            TextEditor(text: $model.sharedText)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(.thinMaterial.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.cyan.opacity(0.14)))

            Button(route == .memory ? "Save to Smith memory" : "Create Smith task") {
                Task { await save() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan.opacity(0.72))
            .disabled(model.sharedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(18)
    }

    private func save() async {
        do {
            let path = route == .memory ? "/api/smith/memories" : "/api/smith/tasks"
            let key = route == .memory ? "content" : "title"
            try await model.api.post(path: path, json: [key: model.sharedText])
            model.status = "SAVED TO NEON"
            model.sharedText = ""
            model.pendingAction = nil
        } catch {
            model.status = error.localizedDescription
        }
    }
}

private struct SmithSettingsWorkspace: View {
    @ObservedObject var model: SmithModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("PRIVATE SMITH CORE")
                    .font(.caption.monospaced())
                    .tracking(2)
                    .foregroundStyle(.cyan.opacity(0.7))

                TextField("https://device.tailnet.ts.net", text: $model.serverAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .smithField()

                SecureField("One-time setup access code", text: $model.accessCode)
                    .textContentType(.password)
                    .smithField()

                Button(model.isRegistered ? "Re-register this iPhone" : "Register this iPhone") {
                    Task { await model.register() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan.opacity(0.74))
                .disabled(model.serverAddress.isEmpty || model.accessCode.isEmpty)

                Text(model.status)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Text("The access code is used once. Smith stores only this device's protected credential in Keychain and continues to use the existing Core, account, memory and Gemini Live session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
    }
}

private struct SmithGenericWorkspace: View {
    @ObservedObject var model: SmithModel
    let route: SmithRoute

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(.cyan.opacity(0.75))
            Text(route.rawValue.uppercased())
                .font(.title3.monospaced())
                .tracking(4)
            Text(description)
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            if let url = URL(string: model.serverAddress), !model.serverAddress.isEmpty {
                Link("Open secure Smith content", destination: url)
                    .buttonStyle(.bordered)
                    .tint(.cyan)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var symbol: String {
        switch route {
        case .search: "sparkle.magnifyingglass"
        case .apps: "square.grid.2x2"
        case .devices: "iphone.and.arrow.forward"
        case .protocols: "bolt.shield"
        case .maps: "map"
        case .files: "folder"
        case .music: "music.note"
        case .reminders: "bell"
        case .clipboard: "doc.on.clipboard"
        case .share: "square.and.arrow.up"
        default: "circle.hexagongrid"
        }
    }

    private var description: String {
        switch route {
        case .search: "Ask Smith to search. Results remain part of the same Core conversation and memory."
        case .apps: "Smith can surface approved device actions without creating a second assistant."
        case .devices: "Registered devices and their current capabilities are managed by Smith Core."
        case .protocols: "Launch an approved protocol while Smith remains present and interruptible."
        case .maps: "Maps content appears as a temporary workspace around Smith."
        case .files: "Approved files can be surfaced without unrestricted filesystem access."
        case .music: "Media controls use the device bridge while intelligence remains in Smith Core."
        default: "This content is a temporary workspace. Close it to restore the centred Smith environment."
        }
    }
}

private struct SmithConnectionPill: View {
    @ObservedObject var model: SmithModel
    let compact: Bool

    var body: some View {
        Button {
            if model.voice.connected {
                model.voice.toggleMuted()
            } else {
                Task { await model.wake() }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                if !compact {
                    Image(systemName: model.voice.muted ? "mic.slash" : "mic")
                        .font(.system(size: 9))
                }
                Text(statusText)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1)
            }
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial.opacity(0.48), in: Capsule())
            .overlay(Capsule().stroke(statusColor.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.voice.muted ? "Unmute Smith" : "Mute Smith")
    }

    private var statusText: String {
        if !model.isRegistered { return "SETUP" }
        if model.voice.muted { return "MUTED" }
        if model.voice.state == "RECONNECTING" { return "RECONNECTING" }
        if model.voice.connected { return "ONLINE" }
        return "READY"
    }

    private var statusColor: Color {
        if model.voice.muted { return .orange }
        if model.voice.state == "RECONNECTING" { return .yellow }
        if model.isRegistered { return .cyan }
        return .gray
    }
}

private struct SmithOrbView: View {
    @ObservedObject var voice: SmithVoiceSession
    let diameter: CGFloat
    @State private var breathing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.cyan.opacity(0.10), lineWidth: 1)
                .frame(width: diameter * 1.19, height: diameter * 1.19)
                .scaleEffect(breathing ? 1.025 : 0.97)

            Circle()
                .stroke(
                    AngularGradient(
                        colors: [.clear, .cyan.opacity(0.72), .white.opacity(0.55), .clear],
                        center: .center
                    ),
                    lineWidth: max(1, diameter * 0.012)
                )
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(breathing ? 360 : 0))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(voice.state == "SPEAKING" ? 0.54 : 0.30),
                            .cyan.opacity(voice.connected ? 0.23 : 0.11),
                            Color(red: 0.01, green: 0.08, blue: 0.12).opacity(0.35),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: diameter * 0.5
                    )
                )
                .frame(width: diameter * 0.91, height: diameter * 0.91)
                .shadow(color: .cyan.opacity(voice.connected ? 0.34 : 0.14), radius: diameter * 0.12)

            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 0.6)
                .frame(width: diameter * 0.57, height: diameter * 0.57)
        }
        .frame(width: diameter * 1.2, height: diameter * 1.2)
        .contentShape(Circle())
        .onAppear {
            withAnimation(.linear(duration: voice.state == "SPEAKING" ? 2.2 : 7).repeatForever(autoreverses: false)) {
                breathing = true
            }
        }
    }
}

private extension View {
    func smithField() -> some View {
        self
            .padding(13)
            .background(.thinMaterial.opacity(0.56), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.cyan.opacity(0.14)))
    }
}


