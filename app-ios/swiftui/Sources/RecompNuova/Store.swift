import Foundation
import SwiftUI
import UserNotifications

// Lo stato dell'app: tutto ciò che l'utente registra, salvato in un file sul telefono (Application Support/Recomp/dati.json).
// Le viste lo osservano; l'orologio (WatchBridge) e Salute (Salute.swift) lo seguono da fuori.
@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()
    let piano = Piano.shared

    @Published var d: AppData { didSet { salvaPresto() } }
    @Published var tabAperta = 0          // 0 Oggi · 1 Allenamento · 2 Piano · 3 Progressi · 4 Profilo
    @Published var mostraRiepilogo: Workout?   // allenamento appena finito
    @Published var mostraSettimana = false      // riepilogo della settimana (dalla notifica della domenica)
    @Published var timerSerie: TimerTempo?      // timer di un esercizio a tempo (plank) in corso

    private let file: URL
    private var salvataggio: DispatchWorkItem?

    private init() {
        let cartella = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Recomp", isDirectory: true)
        try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        file = cartella.appendingPathComponent("dati.json")
        if let data = try? Data(contentsOf: file), let letto = try? JSONDecoder().decode(AppData.self, from: data) { d = letto } else { d = AppData() }
        if !d.superserie {
            for w in piano.workouts { for e in w.ex { if let sup = e.sup, !sup.isEmpty { let k = "\(w.id):\(sup.dropLast())"; if !d.supSpente.contains(k) { d.supSpente.append(k) } } } }
            d.superserie = true
        }
        allineaPiano()
    }

    // dieta nuova (cambia la versione di piano.json): i piatti cambiati che non esistono più si tolgono (prima restavano
    // nascosti e il Piano diceva «hai cambiato dei piatti»), la lista della spesa riparte da zero
    private func allineaPiano() {
        guard d.pianoVersione != piano.version else { return }
        d.swaps = d.swaps.filter { chiave, codice in
            let n = chiave.split(separator: ":").compactMap { Int($0) }
            guard n.count == 2, let giorno = piano.week[safe: n[0]], let tipo = piano.daytypes[giorno.type],
                  let fascia = tipo.slots[safe: n[1]] else { return false }
            return piano.variants[fascia.slot]?[codice] != nil
        }
        if !d.pianoVersione.isEmpty || !d.shopGot.isEmpty { d.shopGot = [:] }
        d.pianoVersione = piano.version
    }

    private func salvaPresto() {
        salvataggio?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.salvaOra() }
        salvataggio = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
    }
    func salvaOra() {
        if let data = try? JSONEncoder().encode(d) { try? data.write(to: file, options: .atomic) }
    }

    // MARK: piano

    var oggiKey: String { Cal.key() }
    var oggiIdx: Int { Cal.dayIdx() }

    func ov(_ key: String) -> DayOv? { d.dayov[key] }

    // il piano di oggi tiene conto di un eventuale cambio fatto oggi; le altre pagine mostrano la settimana tipo
    func pianoGiorno(_ di: Int, oggi: Bool = false) -> DayPlan {
        var conv: Conv?
        if oggi, let o = ov(oggiKey), let t = o.type, !t.isEmpty { conv = Conv(type: t == "ON" ? "ON" : "OFF_S", keep: o.keep ?? []) }
        return piano.dayPlan(di, conv: conv, swaps: d.swaps)
    }
    var pianoOggi: DayPlan { pianoGiorno(oggiIdx, oggi: true) }

    func mangiati(_ key: String? = nil) -> [Int] { d.eaten[key ?? oggiKey] ?? [] }
    func toccaMangiato(_ si: Int) {
        let key = oggiKey
        var arr = Set(d.eaten[key] ?? [])
        if arr.contains(si) { arr.remove(si) } else { arr.insert(si) }
        d.eaten[key] = arr.sorted()
        // niente più di 60 giorni di memoria dei pasti
        let limite = Cal.date(key).addingTimeInterval(-60 * 86400)
        d.eaten = d.eaten.filter { Cal.date($0.key) >= limite }
        pastoInSalute(si: si, mangiato: arr.contains(si))
        Haptic.medio()
    }
    func segnaMangiato(_ si: Int, _ mangiato: Bool) {
        if mangiati().contains(si) != mangiato { toccaMangiato(si) }
    }
    func cambiaPiatto(di: Int, si: Int, codice: String) {
        let k = "\(di):\(si)"
        let m = pianoGiorno(di).meals[si]
        if codice == m.def { d.swaps.removeValue(forKey: k) } else { d.swaps[k] = codice }
        Haptic.leggero()
        if d.promemoria["merenda"] == true { riprogrammaPromemoria() }   // il promemoria della sera dice le merende giuste
    }
    func ripristinaGiorno(_ di: Int) {
        d.swaps = d.swaps.filter { !$0.key.hasPrefix("\(di):") }
    }

    func totaliMangiati(_ key: String? = nil) -> Tot {
        let k = key ?? oggiKey
        let plan = k == oggiKey ? pianoOggi : pianoGiorno(Cal.dayIdx(Cal.date(k)))
        let eaten = mangiati(k)
        let fuori = d.fuori[k] ?? []
        let sostituite = Set(fuori.compactMap(\.si))
        var t = Tot()
        for m in plan.meals where !m.free && eaten.contains(m.si) && !sostituite.contains(m.si) { t.k += m.tot.k; t.p += m.tot.p; t.c += m.tot.c; t.fa += m.tot.fa }
        // i pasti fuori piano contano per quello che hai mangiato davvero
        for f in fuori { let x = f.tot; t.k += x.k; t.p += x.p; t.c += x.c; t.fa += x.fa }
        return Tot(k: t.k, p: r1(t.p), c: r1(t.c), fa: r1(t.fa))
    }

    // creatina
    func creatinaPresa(_ key: String? = nil) -> Bool { d.creatina[key ?? oggiKey] ?? false }
    func toccaCreatina() {
        let key = oggiKey
        d.creatina[key] = !(d.creatina[key] ?? false)
        if d.promemoria["creatina"] == true { riprogrammaPromemoria() }   // la notifica di oggi si toglie (o si rimette)
        Haptic.medio()
    }
    func serieCreatina() -> Int {
        var n = 0
        var giorno = Date()
        var primo = true
        while n < 400 {
            if creatinaPresa(Cal.key(giorno)) { n += 1 } else if !primo { break }
            primo = false
            giorno = Cal.giorni(-1, da: giorno)
        }
        return n
    }

    // palestra saltata o recuperata
    func saltaPalestra(_ saltata: Bool, mangiaRiposo: Bool = true) {
        let key = oggiKey
        defer { riprogrammaPromemoria() }   // niente promemoria della palestra per un giorno saltato (e torna se ci ripensi)
        if !saltata { d.dayov.removeValue(forKey: key); return }
        var o = DayOv()
        o.skip = true
        if mangiaRiposo { o.type = "OFF"; o.keep = mangiati() }
        o.t = Cal.ms()
        d.dayov[key] = o
    }
    func recuperaAllenamento(_ si: Bool) {
        let key = oggiKey
        defer { riprogrammaPromemoria() }
        if !si { d.dayov.removeValue(forKey: key); return }
        var o = DayOv()
        o.type = "ON"; o.keep = mangiati(); o.t = Cal.ms()
        d.dayov[key] = o
    }

    // MARK: pesi

    var pesate: [WeightEntry] { d.weights.sorted { $0.d < $1.d } }
    func aggiungiPeso(giorno: String, kg: Double, vita: Double?) {
        d.weights.removeAll { $0.d == giorno }
        d.weights.append(WeightEntry(d: giorno, kg: (kg * 100).rounded() / 100, w: vita.map(r1), t: Cal.ms()))
        Salute.shared.salvaPeso(giorno: giorno, kg: (kg * 100).rounded() / 100, t: Cal.ms())
        Haptic.medio()
        riprogrammaPromemoria()   // il riepilogo della domenica ha il peso nuovo
    }
    func eliminaPeso(_ giorno: String) { d.weights.removeAll { $0.d == giorno } }

    // MARK: unità dei pesi

    func inLibbre(_ ex: String) -> Bool { d.lbEx.contains(ex) }
    func toccaUnita(_ ex: String) {
        if let i = d.lbEx.firstIndex(of: ex) { d.lbEx.remove(at: i) } else { d.lbEx.append(ex) }
        Haptic.leggero()
    }
    func impostaUnita(_ ex: String, lb: Bool) { if inLibbre(ex) != lb { toccaUnita(ex) } }
    // il peso come lo vedi (kg o lb dell'esercizio), senza unità
    func peso(_ ex: String, _ kg: Double?) -> String {
        guard let kg else { return "" }
        return fmtKg(inLibbre(ex) ? lbFrom(kg: kg) : kg)
    }
    func pesoConUnita(_ ex: String, _ kg: Double?) -> String { peso(ex, kg) + (inLibbre(ex) ? " lb" : " kg") }
    func unita(_ ex: String) -> String { inLibbre(ex) ? "lb" : "kg" }

    // MARK: schede e cronologia

    // le schede: quelle modificate dall'utente se ci sono, se no quelle del piano
    var routines: [Routine] { d.schede ?? routinesDelPiano }
    var routinesDelPiano: [Routine] {
        piano.workouts.map { w in
            Routine(id: w.id, name: w.name, day: w.day, focus: w.focus,
                    items: w.ex.map { RoutineItem(ex: $0.lib, s: $0.s, lo: $0.lo, hi: $0.hi, rest: $0.rest, sup: $0.sup ?? "", kg: $0.kg) })
        }
    }
    func routine(_ id: String?) -> Routine? { routines.first { $0.id == id } }
    var cronologia: [Workout] { d.workouts.filter { $0.del != true }.sorted { $0.start > $1.start } }
    func esercizio(_ id: String) -> ExLib {
        piano.exlib[id] ?? ExLib(id: id, n: id, m: "", sec: [], inc: 2.5, unit: "reps", eq: "", cue: "", img: "", eqv: nil)
    }
    func nomeBreve(_ ex: String) -> String { esercizio(ex).n.components(separatedBy: " · ").first ?? esercizio(ex).n }

    // l'ultima volta che hai fatto quell'esercizio
    func serieAltraVolta(_ ex: String, prima: Double? = nil) -> (sets: [SetRec], w: Workout)? {
        for w in cronologia {
            if let p = prima, w.start >= p { continue }
            if let it = w.items.first(where: { $0.ex == ex && !$0.sets.isEmpty }) { return (it.sets, w) }
        }
        return nil
    }

    struct Primati { var kg = 0.0, e1 = 0.0, reps = 0, vol = 0.0, sec = 0 }
    func primati(_ ex: String, escludi: String? = nil) -> Primati {
        var r = Primati()
        let sec = esercizio(ex).unit == "sec"
        for w in cronologia where w.id != escludi {
            for it in w.items where it.ex == ex {
                for s in it.sets where s.isWork {
                    if let kg = s.kg, kg > r.kg { r.kg = kg }
                    let e = e1rm(s.kg ?? 0, s.r ?? 0); if e > r.e1 { r.e1 = e }
                    if let rr = s.r, rr > r.reps { r.reps = rr }
                    if sec, let rr = s.r, rr > r.sec { r.sec = rr }
                }
                let v = volOf(it.sets); if v > r.vol { r.vol = v }
            }
        }
        return r
    }

    // kg e ripetizioni suggeriti per la serie j: quelli dell'ultima volta, se no il carico di partenza della scheda
    func suggerito(_ it: ItemRec, _ j: Int) -> (kg: Double?, r: Int) {
        let p = serieAltraVolta(it.ex)
        let work = p?.sets.filter { $0.isWork } ?? []
        let ps = work.isEmpty ? nil : work[min(j, work.count - 1)]
        return (ps?.kg ?? it.kg, ps?.r ?? it.lo)
    }

    // il consiglio sotto il nome dell'esercizio (doppia progressione)
    func consiglio(_ it: ItemRec) -> (su: Bool, testo: String) {
        let e = esercizio(it.ex)
        let p = serieAltraVolta(it.ex)
        let work = (p?.sets ?? []).filter { $0.isWork && $0.r != nil }
        if work.isEmpty {
            if e.unit == "sec" { return (false, "Tieni \(it.lo)″ su ogni serie, poi aumenta fino a \(it.hi)″.") }
            if let kg = it.kg { return (false, "Parti da \(pesoConUnita(it.ex, kg)): \(it.lo)–\(it.hi) ripetizioni lasciandone 1–2 in riserva.") }
            return (false, "Carico da testare: trova il peso con cui chiudi \(it.lo)–\(it.hi) ripetizioni con 1–2 in riserva.")
        }
        if e.unit == "sec" {
            let tutte = work.count >= it.sets.count && work.allSatisfy { ($0.r ?? 0) >= it.hi }
            if tutte { return (true, "Tenuto \(it.hi)″ ovunque: oggi prova \(it.hi + Int(e.inc))″.") }
            return (false, "Punta a \(min(it.hi, (work.map { $0.r ?? 0 }.max() ?? 0) + 5))″ su ogni serie.")
        }
        let kg = work.map { $0.kg ?? 0 }.max() ?? 0
        if kg == 0 { return (false, "Registra anche il carico per avere il consiglio.") }
        let obiettivo = max(1, it.sets.filter(\.isWork).count)
        let rp = work.compactMap(\.rpe)
        let meta = Int((Double(work.count) / 2).rounded(.up))
        let duro = !rp.isEmpty && rp.filter { $0 == 3 }.count >= meta
        let facile = rp.count >= meta && rp.allSatisfy { $0 == 1 }
        if work.count >= obiettivo && work.allSatisfy({ ($0.r ?? 0) >= it.hi }) {
            if duro { return (false, "Hai chiuso \(it.hi) ma al limite: oggi resta a \(pesoConUnita(it.ex, kg)) e falle più pulite, poi sali.") }
            return (true, "Tutte le serie a \(it.hi)\(facile ? " e facili" : ""): oggi sali a \(pesoConUnita(it.ex, r1(kg + e.inc))).")
        }
        if facile && !work.contains(where: { ($0.r ?? 0) < it.lo }) { return (true, "Serie facili la volta scorsa: oggi prova \(pesoConUnita(it.ex, r1(kg + e.inc))).") }
        if work.contains(where: { ($0.r ?? 0) < it.lo }) { return (false, "Qualche serie sotto le \(it.lo): resta a \(pesoConUnita(it.ex, kg)) (se ricapita, −5/10%).") }
        return (false, "Resta a \(pesoConUnita(it.ex, kg)) e aggiungi 1 ripetizione dove riesci.")
    }

    // blocco di 7 settimane: adattamento · progressione · scarico
    struct Blocco { var n: Int; var ciclo: Int; var fase: String; var scarico: Bool; var futuro: Bool }
    var blocco: Blocco {
        let giorni = Cal.greg.dateComponents([.day], from: Cal.date(d.blockStart), to: Cal.date(Cal.key())).day ?? 0
        let settimane = max(0, giorni / 7)
        let n = settimane % 7 + 1
        let fase = n <= 2 ? "Adattamento · 2–3 ripetizioni in riserva (RIR 2–3)"
            : n <= 6 ? "Progressione · RIR 1–2 (ultima serie di isolamento a RIR 0–1)" : "Scarico · metà delle serie, stessi carichi, RIR 3–4"
        return Blocco(n: n, ciclo: settimane / 7 + 1, fase: fase, scarico: n == 7, futuro: giorni < 0)
    }

    // allenamenti fatti da lunedì (per «n su 4»)
    func allenamentiSettimana() -> [Workout] {
        return cronologia.filter { $0.start >= Cal.ms(Cal.lunedi()) }
    }
    func fattoOggi(_ rid: String) -> Bool {
        cronologia.contains { $0.rid == rid && Cal.key(Date(timeIntervalSince1970: $0.start / 1000)) == oggiKey }
    }
    // la scheda di oggi (tiene conto di palestra saltata o recuperata)
    var schedaOggi: String? {
        if let o = ov(oggiKey) { if o.skip == true { return nil }; if let r = o.rid, !r.isEmpty { return r } }
        return piano.week[oggiIdx].wo
    }
}

// vibrazioni (tocchi del telefono)
enum Haptic {
    static func leggero() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medio() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func forte() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func ok() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
