import SwiftUI
import UniformTypeIdentifiers

struct SmithSetupPage: View {
    @ObservedObject var model: SmithModel
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.shield").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(.cyan)
            Text("CONNECT SMITH CORE").font(.system(size: 15, weight: .medium, design: .monospaced)).tracking(2)
            TextField("Private HTTPS address", text: $model.serverAddress)
                .textInputAutocapitalization(.never).keyboardType(.URL).smithInput()
            SecureField("One-time setup access code", text: $model.accessCode).smithInput()
            Button("Register this iPhone") { Task { await model.register() } }
                .buttonStyle(.borderedProminent).tint(.cyan).foregroundStyle(.black)
                .disabled(model.serverAddress.isEmpty || model.accessCode.isEmpty)
            Text(model.status).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
            Spacer()
        }.padding(22)
    }
}

struct SmithFeaturePage: View {
    let page: SmithPage
    @ObservedObject var model: SmithModel
    var body: some View {
        Group {
            switch page {
            case .vision: SmithVisionPage(model: model)
            case .memory: SmithDataListPage(kind: .memory, model: model)
            case .tasks: SmithDataListPage(kind: .tasks, model: model)
            case .devices: SmithDataListPage(kind: .devices, model: model)
            case .files: SmithDataListPage(kind: .files, model: model)
            case .automations: SmithAutomationsPage()
            case .health: SmithHealthPage(model: model)
            case .permissions: SmithPermissionsPage(model: model)
            case .settings: SmithSettingsPage(model: model)
            case .ask: EmptyView()
            }
        }.padding(.bottom, 64)
    }
}

enum SmithListKind { case memory, tasks, devices, files }
struct SmithRowData: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
}
struct MemoryRecord: Decodable { let id: Int; let content: String }
struct TaskRecord: Decodable { let id: String; let title: String; let status: String; let dueAt: String? }
struct DeviceRecord: Decodable {
    let deviceId: String
    let name: String?
    let platform: String?
    let online: Bool?
    let status: String?
}
struct FileRecord: Decodable { let id: String; let name: String; let mediaType: String; let sizeBytes: Int }

struct SmithDataListPage: View {
    let kind: SmithListKind
    @ObservedObject var model: SmithModel
    @State private var rows: [SmithRowData] = []
    @State private var loading = true
    @State private var error: String?
    @State private var entry = ""
    @State private var showFileImporter = false
    @State private var uploadStatus: String?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.title3.weight(.light))
                    Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.42))
                }
                Spacer()
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.bordered).tint(.cyan)
            }
            if kind == .memory || kind == .tasks {
                HStack {
                    TextField(kind == .memory ? "What should Smith remember?" : "New task", text: $entry).smithInput()
                    Button { Task { await add() } } label: { Image(systemName: "plus").frame(width: 34, height: 34) }
                        .buttonStyle(.borderedProminent).tint(.cyan).foregroundStyle(.black)
                        .disabled(entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if kind == .files {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Choose Files for Smith", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.cyan).foregroundStyle(.black)
                Text(uploadStatus ?? "iOS grants access only to files you select. Smith accepts text, JSON, CSV, PDF, JPEG, PNG and WebP up to 5 MB each.")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
            if loading {
                Spacer()
                ProgressView("Loading from Smith Core…").tint(.cyan)
                Spacer()
            } else if let error {
                ContentUnavailableView("Could not load", systemImage: "wifi.exclamationmark", description: Text(error))
            } else if rows.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: emptySymbol, description: Text("Smith Core returned an empty list."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(rows) { row in
                            HStack(spacing: 12) {
                                Image(systemName: row.symbol).foregroundStyle(row.tint).frame(width: 34, height: 34)
                                    .background(row.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                    Text(row.subtitle).font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.42)).lineLimit(2)
                                }
                                Spacer()
                            }
                            .padding(11).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.cyan.opacity(0.09)))
                        }
                    }
                }.refreshable { await load() }
            }
        }
        .padding(15)
        .task { await load() }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.plainText, .json, .commaSeparatedText, .pdf, .jpeg, .png, .webP],
            allowsMultipleSelection: true
        ) { result in
            Task {
                switch result {
                case .success(let urls):
                    var uploaded = 0
                    for url in urls.prefix(20) {
                        do {
                            try await model.api.uploadFile(from: url)
                            uploaded += 1
                        } catch {
                            uploadStatus = "\(url.lastPathComponent): \(error.localizedDescription)"
                            break
                        }
                    }
                    if uploaded > 0 {
                        uploadStatus = "Uploaded \(uploaded) selected file\(uploaded == 1 ? "" : "s") securely to Smith Core."
                        await load()
                    }
                case .failure(let error):
                    uploadStatus = error.localizedDescription
                }
            }
        }
    }

    private var title: String {
        switch kind { case .memory: "Memory"; case .tasks: "Tasks"; case .devices: "My Devices"; case .files: "Files" }
    }
    private var subtitle: String {
        switch kind {
        case .memory: "What matters, connected across conversations."
        case .tasks: "Plan, track and complete what matters."
        case .devices: "Live Smith Core registrations and presence."
        case .files: "Private files stored by Smith Core."
        }
    }
    private var emptySymbol: String {
        switch kind { case .memory: "brain"; case .tasks: "checkmark.circle"; case .devices: "iphone"; case .files: "folder" }
    }

    private func load() async {
        loading = true; error = nil
        do {
            switch kind {
            case .memory:
                let values: [MemoryRecord] = try await model.api.get(path: "/api/smith/memories")
                rows = values.map { SmithRowData(id: String($0.id), title: $0.content, subtitle: "SMITH MEMORY", symbol: "brain", tint: .orange) }
            case .tasks:
                let values: [TaskRecord] = try await model.api.get(path: "/api/smith/tasks")
                rows = values.map { value in
                    SmithRowData(id: value.id, title: value.title, subtitle: value.status.uppercased() + (value.dueAt.map { " • \($0)" } ?? ""), symbol: value.status == "completed" ? "checkmark.circle.fill" : "circle", tint: value.status == "completed" ? .green : .blue)
                }
            case .devices:
                let values: [DeviceRecord] = try await model.api.get(path: "/api/devices")
                rows = values.map { value in
                    let online = value.online ?? false
                    return SmithRowData(id: value.deviceId, title: value.name ?? "Smith device", subtitle: "\(online ? "ONLINE" : (value.status ?? "OFFLINE").uppercased()) • \(value.platform ?? "Unknown platform")", symbol: (value.platform ?? "").lowercased().contains("ios") ? "iphone" : "desktopcomputer", tint: online ? .green : .gray)
                }
            case .files:
                let values: [FileRecord] = try await model.api.get(path: "/api/smith/files")
                let formatter = ByteCountFormatter()
                rows = values.map { SmithRowData(id: $0.id, title: $0.name, subtitle: "\($0.mediaType) • \(formatter.string(fromByteCount: Int64($0.sizeBytes)))", symbol: "doc", tint: .cyan) }
            }
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func add() async {
        let clean = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        do {
            if kind == .memory {
                let _: MemoryRecord = try await model.api.sendJSON(path: "/api/smith/memories", method: "POST", json: ["content": clean])
            } else {
                let _: TaskRecord = try await model.api.sendJSON(path: "/api/smith/tasks", method: "POST", json: ["title": clean])
            }
            entry = ""; await load()
        } catch { self.error = error.localizedDescription }
    }
}

struct SmithAutomationsPage: View {
    @State private var toggles = [true, true, true, false]
    private let items = [
        ("When I connect to Home Wi-Fi", "wifi"),
        ("When I start charging", "bolt.fill"),
        ("At 8:00 AM every day", "alarm"),
        ("When Focus changes", "moon"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Automations").font(.title3.weight(.light))
            Text("Private iPhone triggers. Use the matching Smith Shortcut for execution.")
                .font(.caption).foregroundStyle(.white.opacity(0.44))
            ForEach(items.indices, id: \.self) { index in
                Toggle(isOn: $toggles[index]) {
                    Label(items[index].0, systemImage: items[index].1).font(.system(size: 13))
                }
                .tint(.green).padding(13)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.cyan.opacity(0.09)))
            }
            Spacer()
        }.padding(16)
    }
}

struct SmithPermissionsPage: View {
    @ObservedObject var model: SmithModel
    @StateObject private var manager = SmithPermissionManager()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Permissions").font(.title3.weight(.light))
                Text("Smith can request its own iOS permissions. Apple does not allow one app to grant itself access to every app or silently approve protected data.")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))

                ForEach(manager.items) { item in
                    HStack(spacing: 11) {
                        Image(systemName: item.symbol)
                            .foregroundStyle(item.granted ? .green : .cyan)
                            .frame(width: 28)
                        Text(item.title).font(.system(size: 13))
                        Spacer()
                        Text(item.status.uppercased())
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(item.granted ? .green : .orange)
                    }
                    .padding(12)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(.cyan.opacity(0.08)))
                }

                Button {
                    Task { await manager.requestAllAvailable() }
                } label: {
                    Label(manager.requesting ? "Requesting…" : "Request Available Permissions", systemImage: "checkmark.shield.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.cyan).foregroundStyle(.black)
                .disabled(manager.requesting)

                Button {
                    manager.openSettings()
                } label: {
                    Label("Open Smith in iOS Settings", systemImage: "gearshape.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.cyan)

                Button {
                    model.openWorkspace(.files)
                } label: {
                    Label("Choose Files", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.cyan)

                Text(manager.message)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 4)
            }
            .padding(16)
            .id(manager.revision)
        }
    }
}

extension View {
    func smithInput() -> some View {
        self.padding(.horizontal, 13).padding(.vertical, 11)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.cyan.opacity(0.13)))
    }
}