import Foundation
import WatchConnectivity
import WidgetKit

// Riceve lo stato di oggi dall'iPhone e gli manda i tocchi (pasto mangiato, creatina, serie fatta).
// I tocchi si vedono subito sull'orologio; l'iPhone poi conferma con lo stato aggiornato.
// Se l'iPhone non è raggiungibile, transferUserInfo li consegna appena torna vicino.
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var snap: WatchSnapshot? = WatchShared.load()

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func receive(_ payload: [String: Any]) {
        guard let json = payload["s"] as? String, let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return }
        DispatchQueue.main.async { self.store(snapshot) }
    }

    private func store(_ snapshot: WatchSnapshot) {
        snap = snapshot
        WatchShared.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines() // la complicazione sul quadrante
    }

    private func send(_ message: [String: Any]) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { _ in session.transferUserInfo(message) }
        } else {
            session.transferUserInfo(message)
        }
    }

    func eat(_ meal: WatchMeal) {
        guard var s = snap, let index = s.meals.firstIndex(where: { $0.si == meal.si }), !s.meals[index].eaten else { return }
        s.meals[index].eaten = true
        s.kcal += meal.k
        s.p += meal.p
        store(s)
        send(["a": "eat", "si": meal.si])
    }

    func creatine() {
        guard var s = snap, !s.crea else { return }
        s.crea = true
        store(s)
        send(["a": "crea"])
    }

    func setDone() {
        guard let w = snap?.wo, let i = w.i, let j = w.j else { return }
        send(["a": "set", "i": i, "j": j])
    }

    // WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        receive(session.receivedApplicationContext)
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receive(applicationContext) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receive(message) }
}
