import SwiftUI
import WidgetKit

private struct XiLiteWidgetEntry: TimelineEntry {
    let date: Date
    let isPremium: Bool
}

private struct XiLiteWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> XiLiteWidgetEntry {
        XiLiteWidgetEntry(date: .now, isPremium: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (XiLiteWidgetEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<XiLiteWidgetEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> XiLiteWidgetEntry {
        let isPremium = UserDefaults(suiteName: "group.com.xilite.ai")?.bool(forKey: "isPremium") ?? false
        return XiLiteWidgetEntry(date: .now, isPremium: isPremium)
    }
}

private struct XiLiteWidgetView: View {
    let entry: XiLiteWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.cyan.opacity(0.82), Color.purple.opacity(0.9), Color.pink.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 9) {
                Label("Xi Lite", systemImage: "sparkles").font(.headline.bold())
                Spacer(minLength: 0)
                Text(entry.isPremium ? "Your AI, ready." : "Home Screen widget · Pro")
                    .font(family == .systemSmall ? .caption : .subheadline.weight(.semibold))
                    .lineLimit(2)
                Link(destination: URL(string: "xiliteai://")!) {
                    Label(entry.isPremium ? "Open Xi Lite" : "Explore Pro", systemImage: "arrow.up.right")
                        .font(.caption.weight(.bold))
                }
                .tint(.white)
            }
            .foregroundStyle(.white)
            .padding()
        }
        .widgetURL(URL(string: "xiliteai://"))
        .containerBackground(.clear, for: .widget)
    }
}

@main
struct XiLiteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "XiLiteHomeWidget", provider: XiLiteWidgetProvider()) { entry in
            XiLiteWidgetView(entry: entry)
        }
        .configurationDisplayName("Xi Lite")
        .description("Open your Xi Lite AI assistant from the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
