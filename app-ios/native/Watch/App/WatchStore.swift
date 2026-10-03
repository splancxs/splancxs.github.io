import Foundation
import UserNotifications
import WatchConnectivity
import WatchKit
import WidgetKit

// Allenamento in corso sull'orologio: parte da una scheda mandata dall'iPhone e vive qui (salvato a ogni serie),
// così il telefono può restare in tasca. Alla fine va all'iPhone, che lo mette nella cronologia.
struct SessionSet: Codable, Hashable {
    var kg: Double?
    var r: Int
    var done: Bool
}

struct SessionItem: Codable, Hashable {
    var ex: String
    var n: String
    var unit: String
    var inc: Double
    var lo: Int
    var hi: Int
    var rest: Int
    var sup: String?
    var sets: [SessionSet]
}

struct WorkoutSession: Codable {
    var id: String
    var rid: String
    var name: String
    var start: Date
    var items: [SessionItem]
    var cur: [Int]?        // [esercizio, serie] da fare adesso
    var restEnd: Date?
    var restNext: String?

    var total: Int { items.reduce(0) { $0 + $1.sets.count } }
    var done: Int { items.reduce(0) { $0 + $1.sets.filter(\.done).count } }
    var finished: Bool { done == total }
    var volume: Double { items.reduce(0) { $0 + $1.sets.filter(\.done).reduce(0) { $0 + ($1.kg ?? 0) * Double($1.r) } } }

    func firstUndone() -> [Int]? {
        for (i, it) in items.enumerated() { if let j = it.sets.firstIndex(where: { !$0.done }) { return [i, j] } }
        return nil
    }
    var current: [Int]? {
        if let c = cur, c.count == 2, c[0] < items.count, c[1] < items[c[0]].sets.count, !items[c[0]].sets[c[1]].done { return c }
        return firstUndone()
    }
    // dopo una serie: in superserie si alterna con l'esercizio abbinato, se no si resta sullo stesso esercizio
    func next(after i: Int, _ j: Int) -> [Int]? {
        let it = items[i]
        if let sup = it.sup, !sup.isEmpty {
            let base = sup.dropLast()
            let mateLetter = sup.hasSuffix("a") ? "b" : "a"
            if let m = items.firstIndex(where: { $0.sup == base + mateLetter }) {
                let mj = sup.hasSuffix("a") ? j : j + 1
                if mj < items[m].sets.count, !items[m].sets[mj].done { return [m, mj] }
            }
        }
        if let nj = it.sets.firstIndex(where: { !$0.done }) { return [i, nj] }
        return firstUndone()
    }
    func label(_ c: [Int]) -> String {
        let it = items[c[0]], s = it.sets[c[1]]
        let target = it.unit == "sec" ? "\(s.r)″" : s.kg.map { "\(fmtKg($0)) kg × \(s.r)" } ?? "\(s.r) ripetizioni"
        return "\(shortName(it.n)) · serie \(c[1] + 1) · \(target)"
    }
}

func fmtKg(_ kg: Double) -> String {
    kg.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(kg)) : String(format: "%.1f", kg).replacingOccurrences(of: ".", with: ",")
}

// Riceve lo stato di oggi dall'iPhone e gli manda i tocchi (pasto mangiato, creatina, serie, allenamento finito).
// I tocchi si vedono subito sull'orologio; l'iPhone poi conferma con lo stato aggiornato.
// Se l'iPhone non è raggiungibile, transferUserInfo li consegna appena torna vicino.
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate, WKExtendedRuntimeSessionDelegate {
    @Published var snap: WatchSnapshot? = WatchShared.load()
    @Published var session: WorkoutSession? = WatchStore.loadSession()

    private var restTimer: Timer?
    private var runtime: WKExtendedRuntimeSession?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        if session != nil { armRest() }
    }

    // MARK: stato di oggi

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

    private func send(_ message: [String: Any], queued: Bool = false) {
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        if !queued, s.isReachable {
            s.sendMessage(message, replyHandler: nil) { _ in s.transferUserInfo(message) }
        } else {
            s.transferUserInfo(message) // consegna garantita, anche più tardi
        }
    }

    func eat(_ meal: WatchMeal) {
        guard var s = snap, let index = s.meals.firstIndex(where: { $0.si == meal.si }), !s.meals[index].eaten else { return }
        s.meals[index].eaten = true
        s.kcal += meal.k
        s.p += meal.p
        store(s)
        WKInterfaceDevice.current().play(.success)
        send(["a": "eat", "si": meal.si])
    }

    func creatine() {
        guard var s = snap, !s.crea else { return }
        s.crea = true
        store(s)
        WKInterfaceDevice.current().play(.success)
        send(["a": "crea"])
    }

    // serie dell'allenamento avviato sull'iPhone (quando l'app del telefono è aperta)
    func phoneSetDone() {
        guard let w = snap?.wo, let i = w.i, let j = w.j else { return }
        WKInterfaceDevice.current().play(.click)
        send(["a": "set", "i": i, "j": j])
    }

    // MARK: allenamento sull'orologio

    private static func loadSession() -> WorkoutSession? {
        guard let data = UserDefaults.standard.data(forKey: "session") else { return nil }
        return try? JSONDecoder().decode(WorkoutSession.self, from: data)
    }
    private func save() {
        if let s = session, let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: "session") }
        else { UserDefaults.standard.removeObject(forKey: "session") }
    }

    func start(_ plan: WatchPlan) {
        session = WorkoutSession(
            id: "w" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + "o",
            rid: plan.rid, name: plan.name, start: Date(),
            items: plan.items.map { it in
                SessionItem(ex: it.ex, n: it.n, unit: it.unit, inc: it.inc, lo: it.lo, hi: it.hi, rest: it.rest, sup: it.sup,
                            sets: it.sets.map { SessionSet(kg: $0.kg, r: $0.r, done: false) })
            })
        save()
        WKInterfaceDevice.current().play(.start)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        startRuntime()
    }

    // «Fatto»: salva kg e ripetizioni fatti, poi recupero (se previsto) e serie dopo
    func complete(kg: Double?, reps: Int) {
        guard var s = session, let c = s.current else { return }
        s.items[c[0]].sets[c[1]].kg = kg
        s.items[c[0]].sets[c[1]].r = reps
        s.items[c[0]].sets[c[1]].done = true
        // le serie dopo dello stesso esercizio partono dal carico appena usato
        for j in (c[1] + 1)..<s.items[c[0]].sets.count where !s.items[c[0]].sets[j].done { s.items[c[0]].sets[j].kg = kg }
        let next = s.next(after: c[0], c[1])
        s.cur = next
        let rest = s.items[c[0]].rest
        if let n = next, rest > 0 {
            s.restEnd = Date().addingTimeInterval(TimeInterval(rest))
            s.restNext = s.label(n)
        } else {
            s.restEnd = nil
            s.restNext = nil
        }
        session = s
        save()
        WKInterfaceDevice.current().play(.success)
        armRest()
    }

    func addRest(_ seconds: TimeInterval) {
        guard var s = session, let end = s.restEnd else { return }
        s.restEnd = max(Date().addingTimeInterval(1), end.addingTimeInterval(seconds))
        session = s
        save()
        armRest()
    }

    func skipRest() {
        guard var s = session else { return }
        s.restEnd = nil
        session = s
        save()
        armRest()
    }

    func focus(_ i: Int) {
        guard var s = session, i < s.items.count, let j = s.items[i].sets.firstIndex(where: { !$0.done }) else { return }
        s.cur = [i, j]
        session = s
        save()
    }

    // fine allenamento: le serie fatte vanno all'iPhone (consegna garantita) e la sessione si chiude
    func finish() {
        guard let s = session else { return }
        let items: [[String: Any]] = s.items.compactMap { it in
            let sets = it.sets.filter(\.done).map { set -> [String: Any] in
                var o: [String: Any] = ["r": set.r]
                if let kg = set.kg { o["kg"] = kg }
                return o
            }
            return sets.isEmpty ? nil : ["ex": it.ex, "lo": it.lo, "hi": it.hi, "sets": sets]
        }
        if !items.isEmpty {
            let w: [String: Any] = ["id": s.id, "rid": s.rid, "name": s.name,
                                    "start": s.start.timeIntervalSince1970 * 1000, "end": Date().timeIntervalSince1970 * 1000, "items": items]
            if let data = try? JSONSerialization.data(withJSONObject: w), let json = String(data: data, encoding: .utf8) {
                send(["a": "wo", "w": json], queued: true)
            }
        }
        cancel()
    }

    func cancel() {
        session = nil
        save()
        armRest()
        runtime?.invalidate()
        runtime = nil
        WKInterfaceDevice.current().play(.stop)
    }

    // timer di fine recupero: vibrazione sull'orologio; la notifica serve se l'app non è più attiva
    private func armRest() {
        restTimer?.invalidate()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["rest"])
        guard let end = session?.restEnd else { return }
        if end <= Date() { restOver(); return }
        let t = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in self?.restOver() }
        RunLoop.main.add(t, forMode: .common)
        restTimer = t
        let content = UNMutableNotificationContent()
        content.title = "Recupero finito"
        content.body = session?.restNext ?? "Via con la prossima serie"
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "rest", content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)))
    }

    private func restOver() {
        guard var s = session, s.restEnd != nil else { return }
        s.restEnd = nil
        session = s
        save()
        WKInterfaceDevice.current().play(.notification)
    }

    // sessione «fisioterapia»: l'app resta attiva anche col polso giù (fino a un'ora), così timer e vibrazione arrivano puntuali
    private func startRuntime() {
        guard runtime == nil || runtime?.state == .invalid else { return }
        let r = WKExtendedRuntimeSession()
        r.delegate = self
        r.start()
        runtime = r
    }
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        DispatchQueue.main.async { if self.runtime === extendedRuntimeSession { self.runtime = nil } }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        receive(session.receivedApplicationContext)
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receive(applicationContext) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receive(message) }
}
