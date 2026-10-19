import Capacitor
import Foundation
import HealthKit
import UserNotifications
import WatchConnectivity
import WidgetKit

// Ponte tra l'app iPhone e l'app per Apple Watch (WatchConnectivity).
// JS: WatchBridge.update({ snapshot: "<json>" }) manda all'orologio lo stato di oggi (pasti, kcal, creatina, serie in corso);
//     WatchBridge.addListener("action", …) riceve i tocchi sull'orologio: { a: "eat", si } · { a: "crea" } · { a: "set", i, j }
//     · { a: "wo", w: "<json>" } (allenamento fatto sull'orologio, da salvare nella cronologia).
// Le azioni arrivate con l'app chiusa restano in coda finché il JavaScript non si mette in ascolto.
// Come gli altri plugin di Recomp, Capacitor lo crea perché prepara.sh aggiunge "WatchBridgePlugin" a packageClassList.
@objc(WatchBridgePlugin)
public class WatchBridgePlugin: CAPPlugin, CAPBridgedPlugin, WCSessionDelegate {
    public let identifier = "WatchBridgePlugin"
    public let jsName = "WatchBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "update", returnType: CAPPluginReturnPromise),
    ]
    private var last = ""

    override public func load() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    @objc func update(_ call: CAPPluginCall) {
        let snapshot = call.getString("snapshot") ?? ""
        DispatchQueue.main.async {
            self.last = snapshot
            Self.shareWithWidgets(snapshot)
            let sent = self.push()
            if sent { self.openWatchIfNeeded(snapshot) }
            call.resolve(["sent": sent])
        }
    }

    // Allenamento partito dal telefono: chiedo a Salute di aprire l'app dell'orologio con l'allenamento già pronto, anche se è chiusa
    // (come fanno Hevy e Strava). L'orologio poi legge lo stato appena mandato (applicationContext) e parte da solo.
    // Una volta sola per allenamento; non se l'allenamento è partito dall'orologio (fw = 1).
    private var openedFor = ""
    private func openWatchIfNeeded(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let act = obj["act"] as? [String: Any], let id = act["id"] as? String,
              (act["fw"] as? Int ?? 0) == 0, id != openedFor, HKHealthStore.isHealthDataAvailable() else { return }
        openedFor = id
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        HKHealthStore().startWatchApp(with: config) { _, _ in }
    }

    // Allenamento partito dall'orologio: notifica sul telefono (come «Workout Started on Watch» di Hevy). Toccandola si apre Recomp,
    // che mostra l'allenamento in tempo reale. Funziona anche con l'app chiusa: l'iPhone viene svegliato dal messaggio dell'orologio.
    private func notifyWorkoutStarted(_ message: [String: Any]) {
        let name = (message["name"] as? String) ?? "Allenamento"
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let post = {
                let content = UNMutableNotificationContent()
                content.title = "Allenamento iniziato su Apple Watch"
                content.body = name
                content.sound = nil
                center.add(UNNotificationRequest(identifier: "wstart-\(message["id"] as? String ?? "")", content: content, trigger: nil))
            }
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: post()
            case .notDetermined: center.requestAuthorization(options: [.alert]) { ok, _ in if ok { post() } }
            default: break
            }
        }
    }

    // Lo stesso stato va nel gruppo condiviso (chiave «snapshot», come per la complicazione dell'orologio): lo legge il widget della Home.
    // Il nome del gruppo ricalca WatchShared.group: con xtool gli identificativi hanno il prefisso «XTL-CODICE.».
    private static func shareWithWidgets(_ json: String) {
        guard !json.isEmpty, let data = json.data(using: .utf8) else { return }
        let id = Bundle.main.bundleIdentifier ?? ""
        var group = "group.io.github.splancxs.recomp"
        if id.hasPrefix("XTL-"), let punto = id.firstIndex(of: ".") { group = "group.\(id[..<punto]).io.github.splancxs.recomp" }
        guard let defaults = UserDefaults(suiteName: group), defaults.data(forKey: "snapshot") != data else { return }
        defaults.set(data, forKey: "snapshot")
        WidgetCenter.shared.reloadAllTimelines()
    }

    // stato più recente: applicationContext arriva anche se l'app Watch è chiusa; se è aperta lo mando subito
    @discardableResult
    private func push() -> Bool {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated, session.isPaired, session.isWatchAppInstalled, !last.isEmpty else { return false }
        try? session.updateApplicationContext(["s": last])
        if session.isReachable { session.sendMessage(["s": last], replyHandler: nil, errorHandler: nil) }
        return true
    }

    private func forward(_ message: [String: Any]) {
        guard let action = message["a"] as? String else { return }
        if action == "wstart" { notifyWorkoutStarted(message) }
        var data: [String: Any] = ["a": action]
        for (key, value) in message where value is String || value is NSNumber { data[key] = value } // numeri, testi e il JSON dell'allenamento
        DispatchQueue.main.async { self.notifyListeners("action", data: data, retainUntilConsumed: true) }
    }

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.push() }
    }
    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { forward(message) }
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { forward(userInfo) }
    public func sessionWatchStateDidChange(_ session: WCSession) { DispatchQueue.main.async { self.push() } }
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() } // cambio di orologio abbinato
}
