import Foundation

struct AmudEntry: Codable {
    let at: Double
    let prayerDay: Int
    let hebrewDate: String
    let dateLabel: String
    let parsha: String
    let omer: Int
    let nextZman: String
    let nextZmanAt: Double?
    let nextZmanTime: String
    let candleLighting: String
    static let stale = AmudEntry(at: 0, prayerDay: 0, hebrewDate: "Amud", dateLabel: "", parsha: "Open Amud to refresh", omer: 0,
                                  nextZman: "", nextZmanAt: nil, nextZmanTime: "", candleLighting: "")
}
struct WatchPrayer: Codable, Identifiable {
    let key: String
    let title: String
    let hebrewTitle: String
    let text: String
    var id: String { key }
}
struct WatchPrayerDay: Codable {
    let day: Int
    let prayers: [WatchPrayer]
}
struct AmudTimeline: Codable {
    let version: Int
    let validUntil: Double
    let location: String
    let entries: [AmudEntry]
    let prayerDays: [WatchPrayerDay]?
    static let defaults = UserDefaults(suiteName: "group.page.amud")!
    static func load() -> AmudTimeline? {
        guard let json = defaults.string(forKey: "amudTimeline"), let data = json.data(using: .utf8),
              let timeline = try? JSONDecoder().decode(AmudTimeline.self, from: data), timeline.version == 1 else { return nil }
        return timeline
    }
    func prayers(at date: Date = Date()) -> [WatchPrayer] {
        guard let entry = active(at: date) else { return [] }
        return prayerDays?.first(where: { $0.day == entry.prayerDay })?.prayers ?? []
    }
    func active(at date: Date = Date()) -> AmudEntry? {
        let stamp = date.timeIntervalSince1970 * 1000
        guard validUntil > stamp else { return nil }
        return entries.last(where: { $0.at <= stamp })
    }
}
