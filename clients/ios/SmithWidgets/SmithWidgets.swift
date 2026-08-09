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
            Link(destination: SmithRoute.voice.url) {
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
            HStack {
                Image(systemName: "waveform")
                VStack(alignment: .leading) {
                    Text("Smith").font(.headline)
                    Text(context.state.subtitle).font(.caption)
                }
                Spacer()
                Link("Open", destination: SmithRoute.voice.url)
            }
            .padding()
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.cyan)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "waveform") }
                DynamicIslandExpandedRegion(.center) { Text(context.state.subtitle) }
                DynamicIslandExpandedRegion(.trailing) { Text(context.state.state) }
            } compactLeading: {
                Image(systemName: "waveform")
            } compactTrailing: {
                Text("S")
            } minimal: {
                Image(systemName: "waveform")
            }
            .widgetURL(SmithRoute.voice.url)
        }
    }
}

@available(iOSApplicationExtension 18.0, *)
struct SmithControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SmithVoiceControl") {
            ControlWidgetButton(action: TalkToSmithIntent()) {
                Label("Smith", systemImage: "waveform.circle")
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
