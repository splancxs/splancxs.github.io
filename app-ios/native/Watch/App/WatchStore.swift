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
    var sent: Int?         // eventi «serie fatta» mandati al telefono: finché non li conferma (act.q) il suo stato non vale qui
    var adopted: Bool?     // partito dal telefono: se il telefono lo annulla, qui si annulla subito (senza aspettare i 20 secondi)
    var browsing: Bool?    // durante il recupero ho scelto con le frecce un'altra serie: si vede la serie, non il timer
    var picked: Bool?      // la serie di adesso l'ho scelta io con le frecce: resta quella anche se il telefono la fa
    var sentAt: Date?      // quando ho mandato l'ultimo evento al telefono

    var total: Int { items.reduce(0) { $0 + $1.sets.count } }
    var done: Int { items.reduce(0) { $0 + $1.sets.filter(\.done).count } }
    var finished: Bool { done == total }
    var volume: Double { items.reduce(0) { $0 + $1.sets.filter(\.done).reduce(0) { $0 + ($1.kg ?? 0) * Double($1.r) } } }

    func firstUndone() -> [Int]? {
        for (i, it) in items.enumerated() { if let j = it.sets.firstIndex(where: { !$0.done }) { return [i, j] } }
        return nil
    }
    // la serie che si vede: quella scelta con le frecce (anche già fatta, per correggerla) oppure la prima ancora da fare
    var current: [Int]? {
        if let c = cur, c.count == 2, c[0] < items.count, c[1] < items[c[0]].sets.count { return c }
        return firstUndone()
    }
    var editing: Bool { current.map { items[$0[0]].sets[$0[1]].done } ?? false }
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
    func label(_ c: [Int], lb: Set<String> = []) -> String {
        let it = items[c[0]], s = it.sets[c[1]]
        let usesLb = lb.contains(it.ex)
        let target = it.unit == "sec" ? "\(s.r)″" : s.kg.map { usesLb ? "\(fmtKg(lbFrom(kg: $0))) lb × \(s.r)" : "\(fmtKg($0)) kg × \(s.r)" } ?? "\(s.r) ripetizioni"
        return "\(shortName(it.n)) · serie \(c[1] + 1) · \(target)"
    }
}

// Alcuni macchinari hanno i pesi in libbre: per ogni esercizio si sceglie kg o lb (seconda schermata). Dentro l'app i pesi restano sempre
// in kg: in lb cambia solo ciò che si vede e si digita (100 lb = 45,36 kg).
let kgPerLb = 0.45359237
func lbFrom(kg: Double) -> Double { (kg / kgPerLb * 2).rounded() / 2 }          // al mezzo libbra, così non compare mai «99,9»
func kgFrom(lb: Double) -> Double { (lb * kgPerLb * 100).rounded() / 100 }
func lbStep(_ incKg: Double) -> Double { max(2.5, (incKg * 2.20462 / 2.5).rounded() * 2.5) }   // 2,5 kg → 5 lb, 5 kg → 10 lb

func fmtKg(_ kg: Double) -> String {
    kg.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(kg)) : String(format: "%.1f", kg).replacingOccurrences(of: ".", with: ",")
}

// Riceve lo stato di oggi dall'iPhone e gli manda i tocchi (pasto mangiato, creatina, serie, allenamento finito).
// I tocchi si vedono subito sull'orologio; l'iPhone poi conferma con lo stato aggiornato.
// Se l'iPhone non è raggiungibile, transferUserInfo li consegna appena torna vicino.
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate, WKExtendedRuntimeSessionDelegate, UNUserNotificationCenterDelegate {
    @Published var snap: WatchSnapshot? = WatchShared.load()
    @Published var session: WorkoutSession? = WatchStore.loadSession()
    let health = HealthWorkout()   // allenamento in Salute: battito, calorie, anelli
    // id dell'ultimo allenamento chiuso qui: finché l'iPhone non lo sa ancora (fuori portata) il suo stato lo mostra come «in corso»
    // e l'orologio lo riprenderebbe in carico (vedi adopt); lo ignoro
    @Published var closedId: String? = UserDefaults.standard.string(forKey: "closedId") {
        didSet { UserDefaults.standard.set(closedId, forKey: "closedId") }   // resta anche se l'app si riavvia
    }

    // esercizi con i pesi in libbre (la scelta resta anche negli allenamenti dopo)
    @Published var lbSet: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "lbEx") ?? [])
    func isLb(_ ex: String) -> Bool { lbSet.contains(ex) }
    private var lbLocalAt = Date.distantPast   // ultima scelta fatta qui: per qualche secondo lo stato del telefono non la scavalca
    func toggleLb(_ ex: String) {
        if lbSet.contains(ex) { lbSet.remove(ex) } else { lbSet.insert(ex) }
        UserDefaults.standard.set(Array(lbSet), forKey: "lbEx")
        lbLocalAt = Date()
        WKInterfaceDevice.current().play(.click)
        send(["a": "wunit", "ex": ex, "lb": lbSet.contains(ex) ? 1 : 0], queued: true)   // il telefono la tiene uguale
    }
    // la scelta kg/lb fatta sul telefono arriva con lo stato di oggi
    private func applyUnits(_ list: [String]?) {
        guard let list, Date().timeIntervalSince(lbLocalAt) > 10, Set(list) != lbSet else { return }
        lbSet = Set(list)
        UserDefaults.standard.set(list, forKey: "lbEx")
    }

    static let shared = WatchStore()   // unico: lo usano sia la schermata sia il delegato dell'app (apertura da iPhone)

    @Published var tempo: TimerTempo?   // timer di una serie a tempo (plank) in corso
    private var tempoTimer: [Timer] = []
    private var synced = false     // l'iPhone ha già confermato questo allenamento (vedi reconcile)
    private var finishing = false  // chiusura già in corso: evita di mandare due volte lo stesso allenamento
    private var restTimer: Timer?
    private var runtime: WKExtendedRuntimeSession?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        // un allenamento rimasto aperto da ore (app reinstallata o chiusa, allenamento finito altrove) non deve bloccare l'orologio
        if let s = session, Date().timeIntervalSince(s.start) > 6 * 3600 { session = nil; save() }
        if session != nil { armRest() }
        // prove nel simulatore («simulatore.sh orologio-prova»): azioni passate come argomenti di avvio
        let d = UserDefaults.standard
        if d.string(forKey: "recompStart") != nil || d.bool(forKey: "recompCancel") || d.bool(forKey: "recompFinish") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.simulatorTest() }
        }
    }

    private func simulatorTest() {
        let d = UserDefaults.standard
        if d.bool(forKey: "recompCancel") { cancel(); return }
        if d.bool(forKey: "recompFinish") { finish(); return }
        guard session == nil, let rid = d.string(forKey: "recompStart"), let snap else { return }
        if let plan = snap.plans?.first(where: { rid == "oggi" ? $0.rid == snap.todayRid : $0.rid == rid }) ?? snap.plans?.first { start(plan) }
    }

    // MARK: apertura dall'iPhone

    // L'allenamento è partito dal telefono e Salute ha aperto qui l'app (anche se era chiusa). Parte subito la sessione in Salute, che tiene
    // viva l'app, e si prende in carico lo stato dell'allenamento già consegnato dal telefono (applicationContext) o in arrivo tra poco.
    // Se entro 25 secondi non arriva nessun allenamento (telefono fuori portata), la sessione in Salute si chiude da sola.
    func phoneStartedWorkout() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.session == nil, !UserDefaults.standard.bool(forKey: "recompSimulator") {
                self.health.start { ok in if !ok { self.startRuntime() } }
            }
            let ctx = WCSession.default.receivedApplicationContext
            if !ctx.isEmpty { self.receive(ctx) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                guard self.session == nil else { return }
                self.health.discard()
                self.runtime?.invalidate()
                self.runtime = nil
            }
        }
    }

    // MARK: stato di oggi

    private func receive(_ payload: [String: Any]) {
        guard let json = payload["s"] as? String, let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return }
        DispatchQueue.main.async {
            self.store(snapshot)
            self.applyUnits(snapshot.lb)
            self.reconcile(snapshot)
        }
    }

    // Durante un allenamento fatto dal polso l'iPhone tiene la stessa scheda: le serie spuntate lì arrivano qui,
    // e il recupero vale quello cambiato per ultimo (iPhone o orologio). Se l'iPhone chiude o annulla, lo faccio anch'io.
    private func reconcile(_ snapshot: WatchSnapshot) {
        // allenamento partito dal telefono: l'orologio lo prende in carico e si comporta come se fosse partito dal polso
        if session == nil, snapshot.isToday, let act = snapshot.act, act.id != closedId, !finishing {
            adopt(act)
            return
        }
        guard var s = session else { synced = false; return }
        guard let act = snapshot.act, act.id == s.id else {
            if snapshot.fin?.contains(s.id) == true {
                synced = false
                finish()   // l'iPhone l'ha già salvato: chiudo anche qui (vale anche dopo una reinstallazione o un riavvio dell'app)
            } else if s.adopted == true || (synced && Date().timeIntervalSince(s.start) > 20) {
                // l'iPhone l'ha annullato. Se l'allenamento era partito dal telefono lo so per certo (ne ho avuto lo stato), quindi subito;
                // se era partito dal polso aspetto 20 secondi: all'inizio il telefono può non averlo ancora ricevuto
                synced = false
                cancel()
            }
            return
        }
        synced = true
        var changed = false
        // Il telefono è la fonte giusta: se ha già ricevuto tutti i miei eventi (act.q) prendo il suo stato com'è, cioè serie spuntate
        // o tolte, kg e ripetizioni, serie ed esercizi aggiunti, tolti o spostati. Se no, i miei sono ancora in viaggio e li tengo.
        // Se un mio evento si è perso (il telefono non lo conferma da più di 15 secondi pur mandando il suo stato), vale il telefono.
        let perso = (act.q ?? 0) < (s.sent ?? 0) && Date().timeIntervalSince(s.sentAt ?? .distantPast) > 15
        if (act.q ?? 0) >= (s.sent ?? 0) || perso {
            if perso { s.sent = act.q ?? 0 }
            let nuovi = WatchStore.items(from: act)
            if nuovi != s.items || (act.name != nil && act.name != s.name) {
                s.items = nuovi
                if let n = act.name { s.name = n }
                if let c = s.cur, c.count == 2, c[0] < s.items.count, c[1] < s.items[c[0]].sets.count {
                    // la serie che stavo per fare l'ha fatta il telefono: passo alla prossima (come se l'avessi fatta qui).
                    // Se invece l'avevo scelta io con le frecce (per guardarla o correggerla), resta quella
                    if s.picked != true && s.items[c[0]].sets[c[1]].done {
                        s.cur = s.next(after: c[0], c[1])
                        s.browsing = false
                    }
                } else {
                    s.cur = nil
                    s.picked = false
                }
                changed = true
            }
        }
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
        if s.current == nil { WKInterfaceDevice.current().play(.click) }
    }

    // Crea la sessione dell'orologio dall'allenamento attivo sul telefono: stesse serie, stesso inizio, stesso recupero.
    // Da qui in poi funziona come un allenamento partito dal polso: Salute (battito, kcal), vibrazioni, «Termina», musica.
    // Non parte se è vecchio di ore (stato rimasto indietro) e non manda «wstart»: il telefono ce l'ha già.
    private func adopt(_ act: WatchAct) {
        let start = (act.st ?? Date().timeIntervalSince1970 * 1000) / 1000
        guard Date().timeIntervalSince1970 - start < 6 * 3600, !act.items.isEmpty else { return }
        let items = WatchStore.items(from: act)
        var s = WorkoutSession(id: act.id, rid: act.rid ?? "", name: act.name ?? "Allenamento", start: Date(timeIntervalSince1970: start), items: items)
        s.sent = 0
        s.adopted = true
        if let re = act.re, re > Date().timeIntervalSince1970 * 1000 {
            s.restEnd = Date(timeIntervalSince1970: re / 1000)
            s.restNext = act.rn
        }
        if let rv = act.rv { s.rt = Date(timeIntervalSince1970: rv / 1000) }
        session = s
        save()
        synced = true
        armRest()
        send(["a": "wadopt", "id": act.id])   // il telefono sa che l'orologio avvisa: niente notifica di fine recupero sul telefono
        WKInterfaceDevice.current().play(.start)
        if UserDefaults.standard.bool(forKey: "recompSimulator") { return }
        health.start { [weak self] ok in if !ok { self?.startRuntime() } }
    }

    // le serie dell'allenamento del telefono come le vuole la sessione dell'orologio
    static func items(from act: WatchAct) -> [SessionItem] {
        act.items.map { it in
            SessionItem(ex: it.ex, n: it.n ?? it.ex, unit: it.u ?? "reps", inc: it.inc ?? 2.5, lo: Int(it.lo ?? 8), hi: Int(it.hi ?? 12),
                        rest: Int(it.rest ?? 90), sup: it.sup?.isEmpty == false ? it.sup : nil,
                        sets: it.s.map { SessionSet(kg: $0.first ?? nil, r: Int(($0.count > 1 ? $0[1] : nil) ?? 8), done: $0.count > 2 && $0[2] == 1) })
        }
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
        guard meal.fuori != true, var s = snap, let index = s.meals.firstIndex(where: { $0.si == meal.si }), !s.meals[index].eaten else { return }
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
        guard meal.fuori != true, var s = snap, let index = s.meals.firstIndex(where: { $0.si == meal.si }), s.meals[index].eaten else { return }
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
        // un tocco la segna presa, un altro tocco la toglie
        guard var s = snap else { return }
        s.crea.toggle()
        store(s)
        WKInterfaceDevice.current().play(s.crea ? .success : .click)
        send(["a": s.crea ? "crea" : "uncrea"])
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
        // nel simulatore (argomento di avvio -recompSimulator YES) niente richieste di permessi: coprirebbero lo schermo nelle prove
        if UserDefaults.standard.bool(forKey: "recompSimulator") { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        // allenamento in Salute; se non è permesso, sessione «fisioterapia» per restare attivi col polso giù
        health.start { [weak self] ok in if !ok { self?.startRuntime() } }
    }

    // «Fatto»: salva kg e ripetizioni fatti, poi recupero (se previsto) e serie dopo
    func complete(kg: Double?, reps: Int) {
        guard var s = session, let c = s.current else { return }
        // serie già fatta (raggiunta con le frecce): è una correzione di peso o ripetizioni, non una serie nuova
        if s.items[c[0]].sets[c[1]].done { correct(&s, c, kg: kg, reps: reps); return }
        s.browsing = false
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
            s.restNext = s.label(n, lb: lbSet)
        } else {
            s.restEnd = nil
            s.restNext = nil
        }
        s.rt = Date()
        s.sent = (s.sent ?? 0) + 1
        s.sentAt = Date()
        s.picked = false
        session = s
        save()
        WKInterfaceDevice.current().play(.click)   // serie fatta: solo un tocco, senza suono
        armRest()
        // all'iPhone: la serie fatta, con scheda e inizio (se l'avvio è rimasto indietro) e il recupero deciso qui
        var m: [String: Any] = ["a": "wset", "id": s.id, "rid": s.rid, "name": s.name, "start": s.start.timeIntervalSince1970 * 1000,
                                "ex": s.items[c[0]].ex, "i": c[0], "j": c[1], "r": reps, "t": Date().timeIntervalSince1970 * 1000,
                                "re": (s.restEnd?.timeIntervalSince1970 ?? 0) * 1000, "rn": s.restNext ?? "", "q": s.sent ?? 0]
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
        s.browsing = false
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

    // tutte le serie dell'allenamento, nell'ordine: le frecce dell'orologio scorrono tra queste (anche quelle già fatte, per correggerle)
    private func allSets(_ s: WorkoutSession) -> [[Int]] {
        s.items.enumerated().flatMap { i, it in it.sets.indices.map { j in [i, j] } }
    }
    func canMove(_ delta: Int) -> Bool {
        guard let s = session, let c = s.current, let k = allSets(s).firstIndex(of: c) else { return false }
        return allSets(s).indices.contains(k + delta)
    }
    // freccia ‹ o ›: passo alla serie precedente o seguente. Se ero in recupero si vede la serie scelta (il timer riparte da solo alla prossima)
    func moveSet(_ delta: Int) {
        guard var s = session, let c = s.current else { return }
        let list = allSets(s)
        guard let k = list.firstIndex(of: c), list.indices.contains(k + delta) else { return }
        let t = list[k + delta]
        s.cur = t
        s.picked = s.items[t[0]].sets[t[1]].done   // solo una serie già fatta è «scelta»: quella da fare segue il telefono
        s.browsing = s.restEnd != nil
        session = s
        save()
        WKInterfaceDevice.current().play(.click)
    }
    // a fine allenamento: torno all'ultima serie per correggerla
    func reviewLast() {
        guard var s = session, let last = s.items.indices.last, let j = s.items[last].sets.indices.last else { return }
        s.cur = [last, j]
        s.picked = true
        session = s
        save()
    }
    // corregge una serie già fatta: nuovi kg e ripetizioni, spunta e recupero restano; il telefono li riceve (wedit) e li conferma con q
    private func correct(_ s: inout WorkoutSession, _ c: [Int], kg: Double?, reps: Int) {
        s.items[c[0]].sets[c[1]].kg = kg
        s.items[c[0]].sets[c[1]].r = reps
        s.sent = (s.sent ?? 0) + 1
        s.sentAt = Date()
        s.cur = nil            // dopo la correzione si torna alla prossima serie da fare
        s.browsing = false
        s.picked = false
        session = s
        save()
        WKInterfaceDevice.current().play(.success)
        var m: [String: Any] = ["a": "wedit", "id": s.id, "ex": s.items[c[0]].ex, "i": c[0], "j": c[1], "r": reps, "q": s.sent ?? 0]
        if let kg { m["kg"] = kg }
        send(m)
    }

    // MARK: timer delle serie a tempo (plank, side plank)

    // ▶ sulla serie: 3″ per mettersi in posizione, poi il conto alla rovescia (side plank: i due lati, 5″ per girarsi).
    // Vibra a ogni lato; alla fine la serie si segna da sola (e parte il recupero), FERMA salva i secondi tenuti.
    func avviaTempo(_ secondi: Int) {
        guard tempo == nil, let s = session, let c = s.current, !s.items[c[0]].sets[c[1]].done else { return }
        let ex = s.items[c[0]].ex
        let t = TimerTempo(dove: c, ex: ex, durata: max(5, secondi), lati: TimerTempo.lati(ex), inizio: Date().addingTimeInterval(TimerTempo.pronti))
        tempo = t
        WKInterfaceDevice.current().play(.click)
        for (n, quando) in t.cambi.enumerated() {
            programma(quando) { [weak self] in
                guard self?.tempo?.id == t.id else { return }
                WKInterfaceDevice.current().play(n == 1 ? .directionDown : .start)   // n = 1: primo lato finito, girati
            }
        }
        programma(t.fine) { [weak self] in self?.chiudiTempo(t.id, fermato: false) }
    }
    func fermaTempo() { if let t = tempo { chiudiTempo(t.id, fermato: true) } }
    func annullaTempo() {
        tempoTimer.forEach { $0.invalidate() }
        tempoTimer = []
        tempo = nil
    }
    private func programma(_ quando: Date, _ blocco: @escaping () -> Void) {
        let x = Timer(fire: quando, interval: 0, repeats: false) { _ in blocco() }
        RunLoop.main.add(x, forMode: .common)
        tempoTimer.append(x)
    }
    private func chiudiTempo(_ id: UUID, fermato: Bool) {
        guard let t = tempo, t.id == id else { return }
        let tenuti = fermato ? t.tenuti(Date()) : t.durata
        annullaTempo()
        guard tenuti > 0, var s = session, s.items.indices.contains(t.dove[0]), s.items[t.dove[0]].ex == t.ex,
              s.items[t.dove[0]].sets.indices.contains(t.dove[1]), !s.items[t.dove[0]].sets[t.dove[1]].done else { return }
        s.cur = t.dove          // la serie che si segna è quella del timer
        session = s
        if !fermato { buzz() }  // tempo finito: la vibrazione forte, come a fine recupero
        complete(kg: nil, reps: tenuti)
    }

    func focus(_ i: Int) {
        guard var s = session, i < s.items.count, let j = s.items[i].sets.firstIndex(where: { !$0.done }) else { return }
        s.cur = [i, j]
        s.picked = false
        session = s
        save()
    }

    // fine allenamento: si chiude in Salute, poi le serie fatte (con battito medio e calorie) vanno all'iPhone
    // con consegna garantita, e la sessione si chiude
    func finish() {
        guard session != nil, !finishing else { return }
        finishing = true
        let id = session?.id
        health.finish { [weak self] hr, kcal in self?.sendWorkout(hr: hr, kcal: kcal) }
        // se Salute non risponde entro 5 secondi chiudo lo stesso: l'allenamento non deve restare aperto sul polso
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.finishing, self.session?.id == id else { return }
            self.health.discard()
            self.sendWorkout(hr: nil, kcal: 0)
        }
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
            w["full"] = s.items.map { it -> [String: Any] in
                let sets: [[Any]] = it.sets.map { set in [set.kg.map { $0 as Any } ?? NSNull(), set.r, set.done ? 1 : 0] }
                return ["ex": it.ex, "s": sets]
            }
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
        annullaTempo()
        finishing = false
        synced = false
        closedId = session?.id
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
        content.sound = nil   // senza suono
        // di riserva: arriva 3 secondi dopo la fine e solo se l'app non è più viva; se l'app c'è, restOver() la cancella prima
        center.add(UNNotificationRequest(identifier: "rest", content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow + 3), repeats: false)))
    }

    private func restOver() {
        guard var s = session, s.restEnd != nil else { return }
        s.restEnd = nil
        session = s
        save()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest"]) // l'app c'è: niente notifica doppia
        buzz()
    }

    // notifica con l'app aperta: si mostra lo stesso, ma mai con il suono
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }

    // fine recupero: la vibrazione «failure» (scelta dall'utente provando tutte), due volte. watchOS le abbina un suono
    // e non c'è modo di toglierlo da qui: sparisce solo con l'orologio in silenzioso (la vibrazione resta)
    private func buzz() {
        let d = WKInterfaceDevice.current()
        d.play(.failure)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { d.play(.failure) }
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
