import SwiftUI
import WidgetKit

struct AmudWidgetEntry: TimelineEntry {
    let date: Date
    let value: AmudEntry
    let location: String
}
struct AmudProvider: TimelineProvider {
    func placeholder(in context: Context) -> AmudWidgetEntry { AmudWidgetEntry(date: Date(), value: .stale, location: "") }
    func getSnapshot(in context: Context, completion: @escaping (AmudWidgetEntry) -> Void) {
        let timeline = AmudTimeline.load()
        completion(AmudWidgetEntry(date: Date(), value: timeline?.active() ?? .stale, location: timeline?.location ?? ""))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AmudWidgetEntry>) -> Void) {
        guard let data = AmudTimeline.load(), data.validUntil > Date().timeIntervalSince1970 * 1000 else {
            completion(Timeline(entries: [placeholder(in: context)], policy: .after(Date().addingTimeInterval(3600))))
            return
        }
        var entries = [AmudWidgetEntry(date: Date(), value: data.active() ?? .stale, location: data.location)]
        for entry in data.entries where entry.at > Date().timeIntervalSince1970 * 1000 {
            entries.append(AmudWidgetEntry(date: Date(timeIntervalSince1970: entry.at / 1000), value: entry, location: data.location))
        }
        entries.append(AmudWidgetEntry(date: Date(timeIntervalSince1970: data.validUntil / 1000), value: .stale, location: data.location))
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
struct AmudWidgetView: View {
    let entry: AmudWidgetEntry
    @Environment(\.widgetFamily) var family
    private var content: some View {
        Group {
            #if os(watchOS)
            if family == .accessoryCircular {
                VStack { Text(entry.value.nextZmanTime.isEmpty ? "Amud" : entry.value.nextZmanTime).font(.caption).minimumScaleFactor(0.5)
                    if entry.value.omer > 0 { Text("Omer \(entry.value.omer)").font(.caption2) } }
            } else if family == .accessoryInline {
                Text("\(entry.value.nextZman) \(entry.value.nextZmanTime)\(entry.value.omer > 0 ? " · Omer \(entry.value.omer)" : "")")
            } else {
                VStack(alignment: .leading) {
                    Text(entry.value.nextZman).font(.caption)
                    Text(entry.value.nextZmanTime).font(.headline)
                    if entry.value.omer > 0 { Text("Omer · \(entry.value.omer)") }
                }
            }
            #else
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.value.hebrewDate).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                Text(entry.value.parsha).font(.caption).lineLimit(1)
                Text("\(entry.value.nextZman) \(entry.value.nextZmanTime)").font(.subheadline).lineLimit(2)
                if entry.value.omer > 0 { Text("Omer · \(entry.value.omer)").font(.caption) }
                if !entry.value.candleLighting.isEmpty { Text("🕯 \(entry.value.candleLighting)").font(.caption) }
                Text(entry.location).font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }
            #endif
        }.widgetURL(URL(string: "amud://zmanim"))
    }
    var body: some View {
        if #available(iOSApplicationExtension 17.0, macOSApplicationExtension 14.0, watchOSApplicationExtension 10.0, *) {
            content.containerBackground(for: .widget) { Color.clear }
        } else { content.padding(8) }
    }
}
struct AmudWidget: Widget {
    let kind = "AmudWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AmudProvider()) { entry in AmudWidgetView(entry: entry) }
            .configurationDisplayName("Amud · Next zman & Omer")
            .description("Hebrew date, parsha, next zman, Omer and candle lighting.")
            #if os(watchOS)
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
            #else
            .supportedFamilies([.systemSmall, .systemMedium])
            #endif
    }
}
@main
struct AmudWidgetBundle: WidgetBundle {
    var body: some Widget { AmudWidget() }
}
