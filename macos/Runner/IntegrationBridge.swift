import FlutterMacOS
import WidgetKit

final class IntegrationBridge: NSObject {
    static let shared = IntegrationBridge()
    private var channel: FlutterMethodChannel?
    func register(_ messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "amud/integrations", binaryMessenger: messenger)
        self.channel = channel
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "takePendingRoute":
                let route = AmudTimeline.defaults.string(forKey: "amudPendingRoute")
                AmudTimeline.defaults.removeObject(forKey: "amudPendingRoute")
                result(route)
            case "publishTimeline":
                guard let json = call.arguments as? String else { result(FlutterError(code: "timeline", message: "Invalid timeline", details: nil)); return }
                AmudTimeline.defaults.set(json, forKey: "amudTimeline")
                if #available(macOS 11.0, *) { WidgetCenter.shared.reloadAllTimelines() }
                result(nil)
            default: result(FlutterMethodNotImplemented)
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(openPrayer(_:)), name: Notification.Name("AmudOpenPrayer"), object: nil)
        if #available(macOS 13.0, *) { AmudAppShortcuts.updateAppShortcutParameters() }
    }
    @objc private func openPrayer(_ notification: Notification) {
        if let route = notification.object as? String { channel?.invokeMethod("openRoute", arguments: route) }
    }
}
