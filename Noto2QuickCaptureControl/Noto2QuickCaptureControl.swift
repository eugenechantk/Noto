import SwiftUI
import WidgetKit

@main
struct Noto2QuickCaptureWidgetBundle: WidgetBundle {
    var body: some Widget {
        Noto2QuickCaptureWidget()
    }
}

struct Noto2QuickCaptureWidget: Widget {
    static let kind = "com.eugenechan.Noto2.quickCaptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: Noto2QuickCaptureProvider()) { entry in
            Noto2QuickCaptureWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("Quick Capture")
        .description("Open Noto directly to capture a thought.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

private struct Noto2QuickCaptureEntry: TimelineEntry {
    let date: Date
}

private struct Noto2QuickCaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> Noto2QuickCaptureEntry {
        Noto2QuickCaptureEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (Noto2QuickCaptureEntry) -> Void) {
        completion(Noto2QuickCaptureEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Noto2QuickCaptureEntry>) -> Void) {
        completion(Timeline(entries: [Noto2QuickCaptureEntry(date: .now)], policy: .never))
    }
}

private struct Noto2QuickCaptureWidgetView: View {
    let entry: Noto2QuickCaptureEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                rectangularContent
            default:
                circularContent
            }
        }
        .widgetURL(Noto2LaunchRoute.quickCaptureURL)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quick Capture")
        .accessibilityHint("Opens Noto to capture a thought")
        .accessibilityIdentifier("quick_capture_lock_screen_widget")
    }

    private var circularContent: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "square.and.pencil")
                .font(.title2.weight(.semibold))
                .widgetAccentable()
        }
    }

    private var rectangularContent: some View {
        HStack(spacing: 7) {
            Image(systemName: "square.and.pencil")
                .font(.title3.weight(.semibold))
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 1) {
                Text("Quick Capture")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("New note")
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
    }
}

#Preview(as: .accessoryCircular) {
    Noto2QuickCaptureWidget()
} timeline: {
    Noto2QuickCaptureEntry(date: .now)
}

#Preview(as: .accessoryRectangular) {
    Noto2QuickCaptureWidget()
} timeline: {
    Noto2QuickCaptureEntry(date: .now)
}
