import ActivityKit
import Capacitor
import Foundation
import UIKit

// Ponte tra il JavaScript dell'app e la Live Activity del recupero.
// JS: RestActivity.start({ start, end: <millisecondi>, exercise: "Leg Press", detail: "Serie 2 · 118 kg × 8", workout: "Limbs A" })
//     avvia o aggiorna,
//     RestActivity.end() la chiude.
// Capacitor lo crea all'avvio perché il workflow aggiunge "RestActivityPlugin" a packageClassList
// (ios/App/App/capacitor.config.json): il nome Objective-C qui sotto deve restare uguale.
@objc(RestActivityPlugin)
public class RestActivityPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "RestActivityPlugin"
    public let jsName = "RestActivity"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "end", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "status", returnType: CAPPluginReturnPromise),
    ]

    // diagnosi per la scheda in Profilo: dice in quale punto la Live Activity si ferma
    @objc func status(_ call: CAPPluginCall) {
        let plist = Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool ?? false
        let ext = Bundle.main.builtInPlugInsURL
            .map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("RecompLive.appex").path) } ?? false
        if #available(iOS 16.2, *) {
            call.resolve([
                "ios": UIDevice.current.systemVersion, "supported": true, "plist": plist, "extension": ext,
                "enabled": ActivityAuthorizationInfo().areActivitiesEnabled,
                "open": Activity<RestAttributes>.activities.count,
            ])
        } else {
            call.resolve(["ios": UIDevice.current.systemVersion, "supported": false, "plist": plist, "extension": ext])
        }
    }

    @objc func start(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *) else {
            call.resolve(["ok": false, "reason": "iOS troppo vecchio (serve 16.2)"])
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            call.resolve(["ok": false, "reason": "Live Activity disattivate per Recomp"])
            return
        }
        let end = Date(timeIntervalSince1970: (call.getDouble("end") ?? 0) / 1000)
        let start = min(end, Date(timeIntervalSince1970: (call.getDouble("start") ?? Date().timeIntervalSince1970 * 1000) / 1000))
        let state = RestAttributes.ContentState(start: start, end: end,
                                                exercise: call.getString("exercise") ?? "Recupero",
                                                detail: call.getString("detail") ?? "")
        let workout = call.getString("workout") ?? "Allenamento"
        // «scaduta» alla fine del recupero: l'estensione allora mostra «Via!» al posto del conto alla rovescia
        let content = ActivityContent(state: state, staleDate: end)
        Task {
            let open = Activity<RestAttributes>.activities
            if let a = open.first, a.attributes.workout == workout {
                await a.update(content) // stesso allenamento: aggiorno quella già sulla schermata di blocco
                call.resolve(["ok": true])
                return
            }
            for a in open { await a.end(nil, dismissalPolicy: .immediate) }
            do {
                _ = try Activity.request(attributes: RestAttributes(workout: workout), content: content)
                call.resolve(["ok": true])
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func end(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *) else {
            call.resolve()
            return
        }
        Task {
            for a in Activity<RestAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
            call.resolve()
        }
    }
}
