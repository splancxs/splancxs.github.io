import Capacitor
import Foundation
import WatchConnectivity

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
            call.resolve(["sent": self.push()])
        }
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
