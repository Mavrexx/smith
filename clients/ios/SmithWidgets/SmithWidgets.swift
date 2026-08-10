import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct SmithLauncherEntry: TimelineEntry {
    let date: Date
}

struct SmithLauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> SmithLauncherEntry { .init(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (SmithLauncherEntry) -> Void) {
        completion(.init(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SmithLauncherEntry>) -> Void) {
        completion(Timeline(entries: [.init(date: .now)], policy: .never))
    }
}

struct SmithLauncherWidget: Widget {
    let kind = "SmithLauncher"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SmithLauncherProvider()) { _ in
            Link(destination: SmithRoute.voiceURL()) {
                VStack(spacing: 4) {
                    Image(systemName: "waveform.circle.fill")
                    Text("Smith").font(.caption2.monospaced())
                }
                .containerBackground(.black, for: .widget)
                .foregroundStyle(.cyan)
            }
        }
        .configurationDisplayName("Talk to Smith")
        .description("Open an explicit Smith voice session.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct SmithLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SmithVoiceActivityAttributes.self) { context in
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(.cyan.opacity(0.16)).frame(width: 42, height: 42)
                    Image(systemName: "waveform").foregroundStyle(.cyan)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("S M I T H").font(.headline).tracking(2).foregroundStyle(.white)
                    Text(context.state.subtitle).font(.caption).foregroundStyle(.cyan.opacity(0.86)).lineLimit(1)
                }
                Spacer()
                Link("Open", destination: SmithRoute.voiceURL()).foregroundStyle(.cyan)
            }
            .padding()
            .activityBackgroundTint(Color(red: 0.01, green: 0.03, blue: 0.06))
            .activitySystemActionForegroundColor(.cyan)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "waveform.circle.fill").font(.title2).foregroundStyle(.cyan)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("S M I T H").font(.caption2.bold()).tracking(2).foregroundStyle(.cyan)
                        Text(context.state.subtitle).font(.caption2).foregroundStyle(.white).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.state).font(.caption2.bold()).foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Link(destination: SmithRoute.voiceURL()) {
                        Label("Return to Smith", systemImage: "mic.circle.fill")
                            .font(.caption.bold()).foregroundStyle(.cyan)
                    }
                }
            } compactLeading: {
                HStack(spacing: 2) {
                    Text("S").font(.caption.bold())
                    Image(systemName: "waveform").font(.caption2.bold())
                }
                .foregroundStyle(.cyan)
                .accessibilityLabel("Smith active")
            } compactTrailing: {
                Text("LIVE")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(.green)
                    .accessibilityLabel(context.state.state)
            } minimal: {
                Text("S").font(.caption.bold()).foregroundStyle(.cyan)
                    .accessibilityLabel("Smith")
            }
            .widgetURL(SmithRoute.voiceURL())
        }
    }
}

@available(iOSApplicationExtension 18.0, *)
struct SmithControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Smith"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(SmithRoute.voiceURL()))
    }
}

@available(iOSApplicationExtension 18.0, *)
struct SmithControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SmithVoiceControl") {
            ControlWidgetButton(action: SmithControlIntent()) {
                Label("Start Smith", systemImage: "mic.circle.fill")
            }
        }
        .displayName("Talk to Smith")
        .description("Open Smith voice mode from Control Centre.")
    }
}

@main
struct SmithWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        SmithLauncherWidget()
        SmithLiveActivityWidget()
        if #available(iOSApplicationExtension 18.0, *) {
            SmithControlWidget()
        }
    }
}
