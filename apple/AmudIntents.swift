import Foundation
import AppIntents

@available(iOS 16.0, macOS 13.0, *)
enum AmudPrayer: String, AppEnum {
    case shacharit, mincha, maariv, birkat, derech
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Prayer"
    static var caseDisplayRepresentations: [AmudPrayer: DisplayRepresentation] = [
        .shacharit: "Shacharis", .mincha: "Mincha", .maariv: "Maariv", .birkat: "Birkat HaMazon", .derech: "Tefillat HaDerech"
    ]
}
@available(iOS 16.0, macOS 13.0, *)
struct OpenPrayerIntent: AppIntent {
    static var title: LocalizedStringResource = "Open prayer"
    static var description = IntentDescription("Open a prayer in your chosen siddur.")
    static var openAppWhenRun = true
    @Parameter(title: "Prayer") var prayer: AmudPrayer
    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$prayer)") }
    @MainActor
    func perform() async throws -> some IntentResult {
        let route = "amud://pray/\(prayer.rawValue)"
        AmudTimeline.defaults.set(route, forKey: "amudPendingRoute")
        NotificationCenter.default.post(name: Notification.Name("AmudOpenPrayer"), object: route)
        return .result()
    }
}
@available(iOS 16.0, macOS 13.0, *)
struct NextZmanIntent: AppIntent {
    static var title: LocalizedStringResource = "Next zman"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let entry = AmudTimeline.load()?.active()
        let text = entry.map { "The next zman is \($0.nextZman) at \($0.nextZmanTime), for your saved location." } ?? "Open Amud to refresh your zmanim."
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}
@available(iOS 16.0, macOS 13.0, *)
struct OmerIntent: AppIntent {
    static var title: LocalizedStringResource = "Omer count"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let entry = AmudTimeline.load()?.active()
        let text: String
        if let entry = entry { text = entry.omer > 0 ? "The current Hebrew day is day \(entry.omer) of the Omer." : "This date is outside the Omer season." }
        else { text = "Open Amud to refresh the Omer count." }
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}
@available(iOS 16.0, macOS 13.0, *)
struct AmudAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenPrayerIntent(), phrases: ["Open \(\.$prayer) in \(.applicationName)"], shortTitle: "Open prayer", systemImageName: "book")
        AppShortcut(intent: NextZmanIntent(), phrases: ["What is the next zman in \(.applicationName)"], shortTitle: "Next zman", systemImageName: "clock")
        AppShortcut(intent: OmerIntent(), phrases: ["What is the Omer count in \(.applicationName)"], shortTitle: "Omer", systemImageName: "calendar")
    }
}
