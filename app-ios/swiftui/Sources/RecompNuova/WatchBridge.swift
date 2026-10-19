import Combine
import Foundation
import HealthKit
import UserNotifications
import WatchConnectivity
import WidgetKit

// Il ponte con l'app per Apple Watch (WatchConnectivity). Costruisce lo stato di oggi (pasti, allenamento attivo completo,
// schede, unità) e lo manda all'orologio; riceve i suoi tocchi (pasti, creatina, serie, recupero, fine allenamento).
// Il protocollo è lo stesso dell'app web, quindi l'app dell'orologio (app-ios/native/Watch) non cambia.
@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()
    private let store = AppStore.shared
    private var ultimo = ""
    private var apertoPer = ""
    private var bag = Set<AnyCancellable>()

    func avvia() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        // ogni cambiamento dei dati → stato nuovo all'orologio (dopo un attimo, così i tocchi ravvicinati diventano un solo invio)
        store.$d.debounce(for: .milliseconds(400), scheduler: DispatchQueue.main).sink { [weak self] _ in self?.invia() }.store(in: &bag)
        invia()
    }

    // MARK: stato verso l'orologio

    private func invia() {
        apriOrologioSeServe()
        let snap = costruisci()
        guard let data = try? JSONEncoder().encode(snap), let json = String(data: data, encoding: .utf8), json != ultimo else { return }
        ultimo = json
        WatchShared.save(snap)                              // anche per la complicazione e il widget della Home
        WidgetCenter.shared.reloadAllTimelines()
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        try? s.updateApplicationContext(["s": json])        // arriva anche se l'app Watch è chiusa
        if s.isReachable { s.sendMessage(["s": json], replyHandler: nil, errorHandler: nil) }
    }

    // Allenamento partito dal telefono: Salute apre l'app dell'orologio con l'allenamento già pronto, anche se è chiusa
    // (come Hevy e Strava). Una volta sola per allenamento, e non se è partito dall'orologio.
    private func apriOrologioSeServe() {
        guard let a = store.d.active, !a.fromWatch, a.id != apertoPer, HKHealthStore.isHealthDataAvailable() else { return }
        apertoPer = a.id
        let cfg = HKWorkoutConfiguration()
        cfg.activityType = .traditionalStrengthTraining
        cfg.locationType = .indoor
        HKHealthStore().startWatchApp(with: cfg) { _, _ in }
    }

    private func costruisci() -> WatchSnapshot {
        let p = store.piano
        let oggi = store.pianoOggi
        let eaten = store.mangiati()
        let pasti = oggi.meals.filter { !$0.free }
        // i totali sono quelli veri di oggi: contano anche i pasti fuori piano (al posto di un pasto o in più)
        let mangiato = store.totaliMangiati()
        let meals: [WatchMeal] = pasti.map { m in
            // al posto di questo pasto hai mangiato altro: sull'orologio si vede quello, già segnato
            if let f = store.fuoriPerFascia(m.si) {
                let t = f.tot
                return WatchMeal(si: m.si, time: m.time, label: m.label, name: f.nome, code: nil,
                                 k: Int(r0(t.k)), p: Int(r0(t.p)), c: Int(r0(t.c)), f: Int(r0(t.fa)), eaten: true,
                                 ing: f.voci.map { WatchIng(n: $0.nome, g: Int($0.g.rounded()), u: "g", h: nil) }, alt: nil, fuori: true)
            }
            return WatchMeal(si: m.si, time: m.time, label: m.label, name: p.recipe(m.code).name, code: m.code,
                      k: Int(r0(m.tot.k)), p: Int(r0(m.tot.p)), c: Int(r0(m.tot.c)), f: Int(r0(m.tot.fa)), eaten: eaten.contains(m.si),
                      ing: m.lines.map { l in
                          let h = p.aiuto(l.f, l.g)
                          return WatchIng(n: p.foods[l.f]?.n ?? l.f, g: Int(l.g), u: p.unitaPeso(l.f), h: h.isEmpty ? nil : h)
                      },
                      alt: (p.variants[m.slot] ?? [:]).keys.sorted().map { code in
                          let t = p.sum(p.mealLines(m.slot, code))
                          return WatchAlt(code: code, name: p.recipe(code).name, k: Int(r0(t.k)), p: Int(r0(t.p)), c: Int(r0(t.c)), f: Int(r0(t.fa)), cur: code == m.code ? true : nil)
                      })
        }
        let rid = store.schedaOggi
        let tipo = (oggi.conv.isEmpty ? oggi.day.type : oggi.conv).hasPrefix("ON") ? "ON" : "OFF"
        let rec = store.d.active.flatMap { store.recuperoAttivo($0) }
        var snap = WatchSnapshot(
            date: Cal.key(), day: oggi.day.name, type: tipo,
            kcal: Int(r0(mangiato.k)), kcalTarget: Int(r0(oggi.previsti.k)), p: Int(r0(mangiato.p)), pTarget: Int(r0(oggi.previsti.p)),
            c: Int(r0(mangiato.c)), cTarget: Int(r0(oggi.previsti.c)), f: Int(r0(mangiato.fa)), fTarget: Int(r0(oggi.previsti.fa)),
            meals: meals, crea: store.creatinaPresa())
        snap.plans = piani()
        snap.todayRid = rid
        snap.doneToday = rid.map { store.fattoOggi($0) } ?? false
        snap.act = azione()
        snap.fin = store.cronologia.filter { $0.start > Cal.ms() - 864e5 }.map(\.id)
        snap.lb = store.d.lbEx
        snap.restEnd = rec.map { $0.timeIntervalSince1970 * 1000 }
        snap.restNext = rec != nil ? store.d.active?.restNext : nil
        return snap
    }

    // le schede con kg e ripetizioni suggeriti per ogni serie (gli stessi dell'app) e il recupero vero
    private func piani() -> [WatchPlan] {
        store.routines.map { r in
            let recs = r.items.map { ItemRec(ex: $0.ex, lo: $0.lo, hi: $0.hi, rest: $0.rest, sup: $0.sup, kg: $0.kg, sets: Array(repeating: SetRec(), count: $0.s)) }
            let prov = ActiveWorkout(id: "", rid: r.id, name: r.name, start: 0, items: recs)
            return WatchPlan(rid: r.id, name: r.name, day: r.day, items: recs.enumerated().map { i, it in
                let e = store.esercizio(it.ex)
                return PlanItem(ex: it.ex, n: store.nomeBreve(it.ex), unit: e.unit == "sec" ? "sec" : "reps", inc: e.inc, lo: it.lo, hi: it.hi,
                                rest: store.recuperoDi(prov, i), sup: store.superserieAttiva(r.id, it.sup) ? it.sup : nil,
                                sets: it.sets.indices.map { j in let ph = store.suggerito(it, j); return PlanSet(kg: ph.kg, r: ph.r) })
            })
        }
    }

    // l'allenamento attivo per l'orologio, completo: per ogni serie [kg, ripetizioni, 1 se fatta]
    private func azione() -> WatchAct? {
        guard let a = store.d.active else { return nil }
        let rec = store.recuperoAttivo(a)
        return WatchAct(
            id: a.id, rid: a.rid ?? "", name: a.name, st: a.start, q: a.wq,
            items: a.items.enumerated().map { i, it in
                let e = store.esercizio(it.ex)
                return WatchActItem(
                    ex: it.ex, n: store.nomeBreve(it.ex), u: e.unit == "sec" ? "sec" : "reps", inc: e.inc, lo: Double(it.lo), hi: Double(it.hi),
                    rest: Double(store.recuperoDi(a, i)), sup: store.superserieAttiva(a.rid, it.sup) ? it.sup : "",
                    s: it.sets.indices.map { j in
                        let s = it.sets[j]; let ph = store.suggerito(it, j)
                        return [s.kg ?? ph.kg, Double(s.r ?? ph.r), s.done ? 1 : 0]
                    })
            },
            re: rec.map { $0.timeIntervalSince1970 * 1000 } ?? 0, rv: a.restRv, rn: rec != nil ? a.restNext : "")
    }

    // MARK: eventi dall'orologio

    private func gestisci(_ e: [String: Any]) {
        guard let a = e["a"] as? String else { return }
        let num: (String) -> Double? = { (e[$0] as? NSNumber)?.doubleValue }
        let testo: (String) -> String? = { e[$0] as? String }
        switch a {
        case "eat": if let si = num("si"), store.fuoriPerFascia(Int(si)) == nil { store.segnaMangiato(Int(si), true) }
        case "uneat": if let si = num("si") { store.segnaMangiato(Int(si), false) }
        case "swap":
            if let si = num("si"), let code = testo("code"), let m = store.pianoOggi.meals[safe: Int(si)], !m.free, store.piano.variants[m.slot]?[code] != nil {
                store.cambiaPiatto(di: store.oggiIdx, si: Int(si), codice: code)
            }
        case "crea": if !store.creatinaPresa() { store.toccaCreatina() }
        case "uncrea": if store.creatinaPresa() { store.toccaCreatina() }
        case "wstart": inizia(e)
        case "wset":
            if segnaSerie(e), store.d.active != nil, let re = num("re") {
                store.recuperoDaOrologio(fine: re, prossima: testo("rn") ?? "Recupero", quando: num("t") ?? Cal.ms())
            }
        case "wedit": correggi(e)
        case "wunit": if let ex = testo("ex"), let lb = num("lb") { store.impostaUnita(ex, lb: lb == 1) }
        case "wrest":
            if store.d.active != nil { store.recuperoDaOrologio(fine: num("end") ?? 0, prossima: testo("next") ?? "Recupero", quando: num("t") ?? Cal.ms()) }
        case "wcancel": if store.d.active?.id == testo("id") { store.annulla() }
        case "wadopt":
            if var att = store.d.active, att.id == testo("id"), !att.fromWatch { att.fromWatch = true; store.d.active = att }
        case "wo": if let j = testo("w") { importaAllenamento(j) }
        default: break
        }
        // la Live Activity segue anche quello che arriva dall'orologio (col telefono in tasca si aggiorna dal background)
        if a.hasPrefix("w") { store.aggiornaRecuperoEsterno() }
        // lo stato si rimanda sempre, anche se qui non è cambiato niente: l'orologio ha già cambiato il suo da solo
        // (per esempio «Mangiato» su un pasto già segnato) e deve tornare a quello giusto
        ultimo = ""
        invia()
    }

    // allenamento partito dal polso: stesso id, stessa scheda; sul telefono compare «in corso»
    @discardableResult
    private func inizia(_ e: [String: Any]) -> Bool {
        guard let id = e["id"] as? String, store.d.active == nil, !store.d.workouts.contains(where: { $0.id == id }),
              let rid = e["rid"] as? String, let r = store.routine(rid) else { return false }
        let inizio = (e["start"] as? NSNumber)?.doubleValue ?? Cal.ms()
        store.d.active = store.nuovoAllenamento(r, id: id, inizio: inizio, daOrologio: true)
        notificaInizio(nome: r.name, id: id)
        store.riprogrammaPromemoria()
        return true
    }

    // Allenamento partito dall'orologio: notifica sul telefono (come «Workout Started on Watch» di Hevy). Toccandola si apre l'app,
    // che mostra l'allenamento in tempo reale. Funziona anche con l'app chiusa: l'iPhone viene svegliato dal messaggio dell'orologio.
    private func notificaInizio(nome: String, id: String) {
        let c = UNUserNotificationCenter.current()
        c.getNotificationSettings { s in
            let manda = {
                let n = UNMutableNotificationContent()
                n.title = "Allenamento iniziato su Apple Watch"
                n.body = nome
                c.add(UNNotificationRequest(identifier: "wstart-\(id)", content: n, trigger: nil))
            }
            switch s.authorizationStatus {
            case .authorized, .provisional, .ephemeral: manda()
            case .notDetermined: c.requestAuthorization(options: [.alert]) { ok, _ in if ok { manda() } }
            default: break
            }
        }
    }

    private func indiceEsercizio(_ a: ActiveWorkout, _ e: [String: Any]) -> Int? {
        let ex = e["ex"] as? String
        let i = (e["i"] as? NSNumber)?.intValue ?? -1
        // l'esercizio si riconosce dall'id, non dalla posizione: se sul telefono è stato spostato la serie va comunque a lui
        if a.items.indices.contains(i), a.items[i].ex == ex { return i }
        return a.items.firstIndex { $0.ex == ex }
    }

    @discardableResult
    private func segnaSerie(_ e: [String: Any]) -> Bool {
        guard let id = e["id"] as? String else { return false }
        if store.d.active == nil { inizia(e) }   // l'avvio può arrivare dopo (consegna in differita)
        guard var a = store.d.active, a.id == id else { return false }
        // confermo all'orologio che ho ricevuto questo suo evento (q): finché non lo faccio lui non accetta il mio stato
        if let q = (e["q"] as? NSNumber)?.intValue, q > a.wq { a.wq = q }
        a.fromWatch = true
        store.d.active = a
        guard let i = indiceEsercizio(a, e), let j = (e["j"] as? NSNumber)?.intValue, a.items[i].sets.indices.contains(j) else { return false }
        return store.spuntaSerie(i, j, kg: (e["kg"] as? NSNumber)?.doubleValue, r: (e["r"] as? NSNumber)?.intValue)
    }

    // serie già fatta e corretta sull'orologio: cambio i numeri senza togliere la spunta né far partire il recupero
    private func correggi(_ e: [String: Any]) {
        guard var a = store.d.active, a.id == e["id"] as? String else { return }
        if let q = (e["q"] as? NSNumber)?.intValue, q > a.wq { a.wq = q }
        if let i = indiceEsercizio(a, e), let j = (e["j"] as? NSNumber)?.intValue, a.items[i].sets.indices.contains(j) {
            if let kg = (e["kg"] as? NSNumber)?.doubleValue, kg >= 0 { a.items[i].sets[j].kg = kg }
            if let r = (e["r"] as? NSNumber)?.intValue, r > 0 { a.items[i].sets[j].r = r }
        }
        store.d.active = a
    }

    // allenamento chiuso sull'orologio: si salva quello del telefono, che ha tutto (serie, note, tipi di serie),
    // dopo aver aggiunto le serie fatte sull'orologio che gli mancassero
    private func importaAllenamento(_ json: String) {
        guard let data = json.data(using: .utf8), let w = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = w["id"] as? String, let items = w["items"] as? [[String: Any]] else { return }
        let hr = (w["hr"] as? NSNumber).map { Int($0.doubleValue.rounded()) }
        let kcal = (w["kcal"] as? NSNumber).map { Int($0.doubleValue.rounded()) }
        if var a = store.d.active, a.id == id {
            if let full = w["full"] as? [[String: Any]] { unisci(&a, full) }
            store.d.active = a
            if store.d.workouts.contains(where: { $0.id == id }) { store.d.active = nil; store.aggiornaRecuperoEsterno() }
            else { store.finisci(hr: hr, kcal: kcal, daOrologio: true) }
            return
        }
        if let i = store.d.workouts.firstIndex(where: { $0.id == id }) {   // già salvato (finito prima sull'iPhone): aggiungo battito e calorie
            if (hr != nil || kcal != nil) && store.d.workouts[i].hr == nil && store.d.workouts[i].kcal == nil {
                store.d.workouts[i].hr = hr; store.d.workouts[i].kcal = kcal; store.d.workouts[i].watch = true
            }
            return
        }
        let recs: [ItemRec] = items.compactMap { it in
            guard let ex = it["ex"] as? String, let sets = it["sets"] as? [[String: Any]] else { return nil }
            let s: [SetRec] = sets.compactMap { x in
                guard let r = (x["r"] as? NSNumber)?.intValue else { return nil }
                return SetRec(kg: (x["kg"] as? NSNumber)?.doubleValue, r: r, type: "n", done: true)
            }
            return s.isEmpty ? nil : ItemRec(ex: ex, lo: (it["lo"] as? NSNumber)?.intValue ?? 8, hi: (it["hi"] as? NSNumber)?.intValue ?? 12, rest: 90, sets: s)
        }
        guard !recs.isEmpty else { return }
        let rid = w["rid"] as? String
        var nuovo = Workout(id: id, rid: (rid?.isEmpty ?? true) ? nil : rid, name: (w["name"] as? String) ?? "Allenamento",
                            start: (w["start"] as? NSNumber)?.doubleValue ?? Cal.ms(), end: (w["end"] as? NSNumber)?.doubleValue ?? Cal.ms(),
                            items: recs, hr: hr, kcal: kcal, watch: true)
        nuovo.prs = store.calcolaPrimati(recs, id: id)
        store.d.workouts.append(nuovo)
        store.mostraRiepilogo = nuovo
    }

    // le serie fatte sull'orologio che il telefono non aveva ancora (full: [{ ex, s: [[kg, rip, fatta]] }] nell'ordine dell'orologio)
    private func unisci(_ a: inout ActiveWorkout, _ full: [[String: Any]]) {
        for (idx, fi) in full.enumerated() {
            guard let ex = fi["ex"] as? String, let serie = fi["s"] as? [[Any]] else { continue }
            let i = a.items.indices.contains(idx) && a.items[idx].ex == ex ? idx : (a.items.firstIndex { $0.ex == ex } ?? -1)
            guard i >= 0 else { continue }
            for (j, v) in serie.enumerated() where a.items[i].sets.indices.contains(j) && v.count > 2 {
                guard !a.items[i].sets[j].done, (v[2] as? NSNumber)?.intValue == 1 else { continue }
                if let kg = v[0] as? NSNumber { a.items[i].sets[j].kg = kg.doubleValue }
                if let r = v[1] as? NSNumber { a.items[i].sets[j].r = Int(r.doubleValue.rounded()) }
                a.items[i].sets[j].done = true
            }
        }
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.ultimo = ""; self.invia() }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { Task { @MainActor in self.gestisci(message) } }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { Task { @MainActor in self.gestisci(userInfo) } }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in self.ultimo = ""; self.invia() } }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }   // cambio di orologio abbinato
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
