import Flutter
import WidgetKit
import WatchConnectivity

final class IntegrationBridge: NSObject, WCSessionDelegate {
    static let shared = IntegrationBridge()
    private var channel: FlutterMethodChannel?
    func register(_ messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "amud/integrations", binaryMessenger: messenger)
        self.channel = channel
        channel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "takePendingRoute":
                let route = AmudTimeline.defaults.string(forKey: "amudPendingRoute")
                AmudTimeline.defaults.removeObject(forKey: "amudPendingRoute")
                result(route)
            case "publishTimeline":
                guard let json = call.arguments as? String else { result(FlutterError(code: "timeline", message: "Invalid timeline", details: nil)); return }
                AmudTimeline.defaults.set(json, forKey: "amudTimeline")
                WidgetCenter.shared.reloadAllTimelines()
                self?.syncWatch(json)
                result(nil)
            default: result(FlutterMethodNotImplemented)
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(openPrayer(_:)), name: Notification.Name("AmudOpenPrayer"), object: nil)
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
        if #available(iOS 16.0, *) { AmudAppShortcuts.updateAppShortcutParameters() }
    }
    @objc private func openPrayer(_ notification: Notification) {
        guard let route = notification.object as? String else { return }
        channel?.invokeMethod("openRoute", arguments: route)
    }
    private func syncWatch(_ json: String) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        // File transfers avoid WatchConnectivity's small application-context
        // limit and deliver the full offline timeline and dated siddur.
        do {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("amud-\(UUID().uuidString).json")
            try json.data(using: .utf8)!.write(to: file, options: .atomic)
            for transfer in WCSession.default.outstandingFileTransfers {
                let old = transfer.file.fileURL
                transfer.cancel()
                try? FileManager.default.removeItem(at: old)
            }
            WCSession.default.transferFile(file, metadata: ["kind": "amudTimeline"])
        } catch { }

    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let json = AmudTimeline.defaults.string(forKey: "amudTimeline") { syncWatch(json) }
    }
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }
    func sessionWatchStateDidChange(_ session: WCSession) {
        if let json = AmudTimeline.defaults.string(forKey: "amudTimeline") { syncWatch(json) }
    }
    func sessionDidBecomeInactive(_ session: WCSession) { }
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
