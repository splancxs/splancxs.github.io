import ActivityKit
import Capacitor
import Foundation

// Ponte tra il JavaScript dell'app e la Live Activity del recupero.
// JS: RestActivity.start({ end: <millisecondi>, next: "Prossima: …", workout: "Limbs A" }) avvia o aggiorna,
//     RestActivity.end() la chiude.
@objc(RestActivityPlugin)
public class RestActivityPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "RestActivityPlugin"
    public let jsName = "RestActivity"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "end", returnType: CAPPluginReturnPromise),
    ]

    @objc func start(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *), ActivityAuthorizationInfo().areActivitiesEnabled else {
            call.resolve(["ok": false])
            return
        }
        let end = Date(timeIntervalSince1970: (call.getDouble("end") ?? 0) / 1000)
        let state = RestAttributes.ContentState(end: end, next: call.getString("next") ?? "")
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
