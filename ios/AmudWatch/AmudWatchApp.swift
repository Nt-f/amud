import SwiftUI
import WatchConnectivity
import WidgetKit

final class WatchSync: NSObject, ObservableObject, WCSessionDelegate {
    @Published var timeline = AmudTimeline.load()
    override init() {
        super.init()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    private func store(_ context: [String: Any]) {
        guard let json = context["timeline"] as? String, json.utf8.count <= 1024 * 1024 else { return }
        AmudTimeline.defaults.set(json, forKey: "amudTimeline")
        DispatchQueue.main.async { self.timeline = AmudTimeline.load(); WidgetCenter.shared.reloadAllTimelines() }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { store(session.receivedApplicationContext) }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) { store(applicationContext) }
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let bytes = try? Data(contentsOf: file.fileURL), bytes.count <= 1024 * 1024,
              let json = String(data: bytes, encoding: .utf8) else { return }
        store(["timeline": json])
    }
}
@main
struct AmudWatchApp: App {
    @StateObject private var sync = WatchSync()
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                TimelineView(.periodic(from: Date(), by: 30)) { context in
                    List {
                        if let current = sync.timeline?.active(at: context.date) {
                            Text(current.hebrewDate).font(.headline)
                            Text(current.parsha)
                            Text("\(current.nextZman)\n\(current.nextZmanTime)")
                            if current.omer > 0 { Text("Omer · \(current.omer)") }
                        } else { Text("Open Amud on your phone to sync.") }
                        ForEach(sync.timeline?.prayers(at: context.date) ?? []) { prayer in
                            NavigationLink(prayer.title) {
                                ScrollView { VStack(spacing: 16) {
                                    Text(prayer.hebrewTitle).font(.headline)
                                    Text(prayer.text).font(.system(size: 22)).multilineTextAlignment(.trailing)
                                        .environment(\.layoutDirection, .rightToLeft)
                                }.padding() }.navigationTitle(prayer.title)
                            }
                        }
                    }
                }.navigationTitle("Amud")
            }
        }
    }
}
