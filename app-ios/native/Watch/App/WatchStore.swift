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
    var rt: Date?          // ultima modifica del recupero (per confrontarla con quella dell'iPhone)

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
    let health = HealthWorkout()   // allenamento in Salute: battito, calorie, anelli

    private var synced = false     // l'iPhone ha già confermato questo allenamento (vedi reconcile)
    private var finishing = false  // chiusura già in corso: evita di mandare due volte lo stesso allenamento
    private var restTimer: Timer?
    private var runtime: WKExtendedRuntimeSession?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        // un allenamento rimasto aperto da ore (app reinstallata o chiusa, allenamento finito altrove) non deve bloccare l'orologio
        if let s = session, Date().timeIntervalSince(s.start) > 6 * 3600 { session = nil; save() }
        if session != nil { armRest() }
    }

    // MARK: stato di oggi

    private func receive(_ payload: [String: Any]) {
        guard let json = payload["s"] as? String, let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return }
        DispatchQueue.main.async {
            self.store(snapshot)
            self.reconcile(snapshot)
        }
    }

    // Durante un allenamento fatto dal polso l'iPhone tiene la stessa scheda: le serie spuntate lì arrivano qui,
    // e il recupero vale quello cambiato per ultimo (iPhone o orologio). Se l'iPhone chiude o annulla, lo faccio anch'io.
    private func reconcile(_ snapshot: WatchSnapshot) {
        guard var s = session else { synced = false; return }
        guard let act = snapshot.act, act.id == s.id else {
            if snapshot.fin?.contains(s.id) == true {
                synced = false
                finish()   // l'iPhone l'ha già salvato: chiudo anche qui (vale anche dopo una reinstallazione o un riavvio dell'app)
            } else if synced, Date().timeIntervalSince(s.start) > 20 {
                synced = false
                cancel()   // l'iPhone l'ha annullato
            }
            return
        }
        synced = true
        var changed = false
        for (i, ai) in act.items.enumerated() where i < s.items.count && s.items[i].ex == ai.ex {
            for (j, v) in ai.s.enumerated() where j < s.items[i].sets.count && !s.items[i].sets[j].done {
                guard let v = v, v.count == 2, let r = v[1] else { continue }
                s.items[i].sets[j].kg = v[0]
                s.items[i].sets[j].r = Int(r)
                s.items[i].sets[j].done = true
                changed = true
            }
        }
        if changed { s.cur = nil }
        if let rv = act.rv, rv > (s.rt?.timeIntervalSince1970 ?? 0) * 1000 {
            let end = (act.re ?? 0) > Date().timeIntervalSince1970 * 1000 ? Date(timeIntervalSince1970: (act.re ?? 0) / 1000) : nil
            if end != s.restEnd {
                s.restEnd = end
                s.restNext = end == nil ? nil : (act.rn?.isEmpty == false ? act.rn : s.restNext)
                changed = true
            }
            s.rt = Date(timeIntervalSince1970: rv / 1000)
        }
        guard changed else { return }
        session = s
        save()
        armRest()
        if s.current == nil { WKInterfaceDevice.current().play(.success) }
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
        s.c += meal.c ?? 0
        s.f += meal.f ?? 0
        store(s)
        WKInterfaceDevice.current().play(.success)
        send(["a": "eat", "si": meal.si])
    }

    // toglie la spunta di un pasto segnato per sbaglio
    func uneat(_ meal: WatchMeal) {
        guard var s = snap, let index = s.meals.firstIndex(where: { $0.si == meal.si }), s.meals[index].eaten else { return }
        s.meals[index].eaten = false
        s.kcal = max(0, s.kcal - meal.k)
        s.p = max(0, s.p - meal.p)
        s.c = max(0, s.c - (meal.c ?? 0))
        s.f = max(0, s.f - (meal.f ?? 0))
        store(s)
        WKInterfaceDevice.current().play(.click)
        send(["a": "uneat", "si": meal.si])
    }

    // cambio piatto: si vede subito il nome nuovo con i suoi numeri; gli ingredienti arrivano dall'iPhone
    func swap(_ meal: WatchMeal, to alt: WatchAlt) {
        guard var s = snap, let index = s.meals.firstIndex(where: { $0.si == meal.si }), s.meals[index].code != alt.code else { return }
        if s.meals[index].eaten {
            s.kcal += alt.k - meal.k
            s.p += alt.p - meal.p
            s.c += alt.c - (meal.c ?? 0)
            s.f += alt.f - (meal.f ?? 0)
        }
        s.meals[index].name = alt.name
        s.meals[index].code = alt.code
        s.meals[index].k = alt.k
        s.meals[index].p = alt.p
        s.meals[index].c = alt.c
        s.meals[index].f = alt.f
        s.meals[index].ing = nil
        s.meals[index].alt = s.meals[index].alt?.map { var a = $0; a.cur = a.code == alt.code ? true : nil; return a }
        store(s)
        WKInterfaceDevice.current().play(.success)
        send(["a": "swap", "si": meal.si, "code": alt.code])
    }

    func creatine() {
        guard var s = snap, !s.crea else { return }
        s.crea = true
        store(s)
        WKInterfaceDevice.current().play(.success)
        send(["a": "crea"])
    }

    // serie dell'allenamento avviato sull'iPhone (quando l'app del telefono è aperta), con kg e ripetizioni fatti
    func phoneSetDone(kg: Double?, reps: Int) {
        guard let w = snap?.wo, let i = w.i, let j = w.j else { return }
        WKInterfaceDevice.current().play(.success)
        var message: [String: Any] = ["a": "set", "i": i, "j": j, "r": reps]
        if let kg { message["kg"] = kg }
        send(message)
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
        synced = false
        if let s = session {
            send(["a": "wstart", "id": s.id, "rid": s.rid, "name": s.name, "start": s.start.timeIntervalSince1970 * 1000])
        }
        WKInterfaceDevice.current().play(.start)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        // allenamento in Salute; se non è permesso, sessione «fisioterapia» per restare attivi col polso giù
        health.start { [weak self] ok in if !ok { self?.startRuntime() } }
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
        s.rt = Date()
        session = s
        save()
        WKInterfaceDevice.current().play(.success)
        armRest()
        // all'iPhone: la serie fatta, con scheda e inizio (se l'avvio è rimasto indietro) e il recupero deciso qui
        var m: [String: Any] = ["a": "wset", "id": s.id, "rid": s.rid, "name": s.name, "start": s.start.timeIntervalSince1970 * 1000,
                                "ex": s.items[c[0]].ex, "i": c[0], "j": c[1], "r": reps, "t": Date().timeIntervalSince1970 * 1000,
                                "re": (s.restEnd?.timeIntervalSince1970 ?? 0) * 1000, "rn": s.restNext ?? ""]
        if let kg { m["kg"] = kg }
        send(m)
    }

    func addRest(_ seconds: TimeInterval) {
        guard var s = session, let end = s.restEnd else { return }
        s.restEnd = max(Date().addingTimeInterval(1), end.addingTimeInterval(seconds))
        s.rt = Date()
        session = s
        save()
        armRest()
        sendRest(s)
    }

    func skipRest() {
        guard var s = session else { return }
        s.restEnd = nil
        s.rt = Date()
        session = s
        save()
        armRest()
        sendRest(s)
    }

    // recupero cambiato dal polso (+15″, salta): lo stesso sul timer dell'iPhone
    private func sendRest(_ s: WorkoutSession) {
        send(["a": "wrest", "id": s.id, "end": (s.restEnd?.timeIntervalSince1970 ?? 0) * 1000,
              "next": s.restNext ?? "", "t": Date().timeIntervalSince1970 * 1000])
    }

    func focus(_ i: Int) {
        guard var s = session, i < s.items.count, let j = s.items[i].sets.firstIndex(where: { !$0.done }) else { return }
        s.cur = [i, j]
        session = s
        save()
    }

    // fine allenamento: si chiude in Salute, poi le serie fatte (con battito medio e calorie) vanno all'iPhone
    // con consegna garantita, e la sessione si chiude
    func finish() {
        guard session != nil, !finishing else { return }
        finishing = true
        health.finish { [weak self] hr, kcal in self?.sendWorkout(hr: hr, kcal: kcal) }
    }

    private func sendWorkout(hr: Int?, kcal: Int) {
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
            var w: [String: Any] = ["id": s.id, "rid": s.rid, "name": s.name,
                                    "start": s.start.timeIntervalSince1970 * 1000, "end": Date().timeIntervalSince1970 * 1000, "items": items]
            if let hr { w["hr"] = hr }
            if kcal > 0 { w["kcal"] = kcal }
            if let data = try? JSONSerialization.data(withJSONObject: w), let json = String(data: data, encoding: .utf8) {
                send(["a": "wo", "w": json], queued: true)
            }
        }
        close()
    }

    // annullato senza salvare: niente all'iPhone né in Salute
    func cancel() {
        if let id = session?.id { send(["a": "wcancel", "id": id]) }
        health.discard()
        close()
    }

    private func close() {
        finishing = false
        synced = false
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
        content.sound = nil   // solo vibrazione, niente suono
        center.add(UNNotificationRequest(identifier: "rest", content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)))
    }

    private func restOver() {
        guard var s = session, s.restEnd != nil else { return }
        s.restEnd = nil
        session = s
        save()
        buzz()
    }

    // fine recupero: tre vibrazioni distinte, così si sentono anche con il polso fermo e il braccio in tensione.
    // «.notification» farebbe anche il suono di avviso: uso «.retry», che è solo vibrazione
    private func buzz() {
        let d = WKInterfaceDevice.current()
        d.play(.retry)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { d.play(.retry) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { d.play(.retry) }
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
