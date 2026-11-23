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
    @Published var mostraCoach = false          // la chat del coach in Oggi (anche da una sua notifica)
    @Published var debugApri: String?           // finestra da aprire per il debug dal PC (Registro.swift)
    @Published var debugSezionePiano: Int?      // debug: sezione del Piano da aprire (0 settimana · 1 spesa · 2 scambi · 3 i miei)
    @Published var debugSezioneScheda: Int?     // debug: Scheda (1 storico · 2 numeri · 3 dettaglio dell'ultimo allenamento)
    @Published var timerSerie: TimerTempo?      // timer di un esercizio a tempo (plank) in corso

    // modalità prova (debug dal PC, «debug.ps1 prova …»): l'app lavora su una copia dei dati (dati-prova.json) e non
    // scrive in Salute, non manda niente all'orologio, niente notifiche né Live Activity. I dati veri restano intatti.
    nonisolated static let inProva = ProcessInfo.processInfo.environment["RECOMP_PROVA"] == "1"
    // prova della Dynamic Island («debug.ps1 isola»): in prova la Live Activity si accende lo stesso
    nonisolated static let liveInProva = inProva && ProcessInfo.processInfo.environment["RECOMP_LIVE"] == "1"

    private let file: URL
    private var salvataggio: DispatchWorkItem?

    private init() {
        let cartella = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Recomp", isDirectory: true)
        try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        let veri = cartella.appendingPathComponent("dati.json")
        file = AppStore.inProva ? cartella.appendingPathComponent("dati-prova.json") : veri
        // in prova si parte sempre dalla copia fresca dei dati veri
        if let data = try? Data(contentsOf: veri), let letto = try? JSONDecoder().decode(AppData.self, from: data) { d = letto } else { d = AppData() }
        if AppStore.inProva { d.salute = false; Registro.evento("MODALITÀ PROVA: copia dei dati, niente Salute, orologio e notifiche") }
        if !d.superserie {
            for w in piano.workouts { for e in w.ex { if let sup = e.sup, !sup.isEmpty { let k = "\(w.id):\(sup.dropLast())"; if !d.supSpente.contains(k) { d.supSpente.append(k) } } } }
            d.superserie = true
        }
        allineaPiano()
        allineaAllenamentoOggi()
        pulisciCibiPasto()
    }

    // i cibi cambiati a mano valgono solo per il loro giorno (chiave «2026-11-20:3»): le chiavi vecchie «giorno della
    // settimana:fascia» (valevano ogni settimana) e quelle di più di 60 giorni fa si tolgono
    private func pulisciCibiPasto() {
        let limite = Cal.key(Cal.giorni(-60, da: Date()))
        d.cibiPasto = d.cibiPasto.filter { k, _ in
            let data = k.split(separator: ":").first.map(String.init) ?? ""
            return data.count == 10 && data >= limite
        }
    }

    // i cibi cambiati di quel giorno, con le chiavi «giorno della settimana:fascia» che usa Piano.dayPlan
    private func cibiDelGiorno(_ key: String, di: Int) -> [String: CibiPasto] {
        var out: [String: CibiPasto] = [:]
        for (k, v) in d.cibiPasto where k.hasPrefix(key + ":") { out["\(di):\(k.dropFirst(key.count + 1))"] = v }
        return out
    }
    private func chiaveCibi(_ di: Int, _ si: Int) -> String { "\(chiaveGiorno(di)):\(si)" }

    // se oggi (giorno OFF di base) hai già registrato o avviato un allenamento e non hai ancora toccato lo switch ON/OFF, passa a ON
    private func allineaAllenamentoOggi() {
        let key = oggiKey
        guard d.dayov[key] == nil, piano.week[oggiIdx].type != "ON" else { return }
        let allenatoOggi = d.active != nil || cronologia.contains { Cal.key(Date(timeIntervalSince1970: $0.start / 1000)) == key }
        if allenatoOggi {
            let rid = d.active?.rid ?? cronologia.first { Cal.key(Date(timeIntervalSince1970: $0.start / 1000)) == key }?.rid
            // i pasti già mangiati restano con le dosi di prima (keep): cambiano solo quelli ancora da mangiare
            d.dayov[key] = DayOv(rid: rid, type: "ON", keep: mangiati(key), t: Cal.ms())
        }
    }

    // dieta nuova (cambia la versione di piano.json): i piatti cambiati che non esistono più si tolgono (prima restavano
    // nascosti e il Piano diceva «hai cambiato dei piatti»), i cibi cambiati a mano e la lista della spesa ripartono da zero
    private func allineaPiano() {
        guard d.pianoVersione != piano.version else { return }
        d.swaps = d.swaps.filter { chiave, codice in
            let n = chiave.split(separator: ":").compactMap { Int($0) }
            guard n.count == 2, let giorno = piano.week[safe: n[0]], let tipo = piano.daytypes[giorno.type],
                  let fascia = tipo.slots[safe: n[1]] else { return false }
            return piano.variants[fascia.slot]?[codice] != nil
        }
        d.cibiPasto = [:]
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

    // la data (yyyy-MM-dd) di un giorno (0 = lunedì … 6 = domenica) di questa settimana
    func chiaveGiorno(_ di: Int) -> String { Cal.key(Cal.giorni(di, da: Cal.lunedi())) }

    func pianoPerData(_ key: String) -> DayPlan {
        let di = Cal.dayIdx(Cal.date(key))
        var conv: Conv?
        if let o = ov(key), let t = o.type, !t.isEmpty { conv = Conv(type: t == "ON" ? "ON" : "OFF_S", keep: o.keep ?? []) }
        return piano.dayPlan(di, conv: conv, swaps: d.swaps, cibi: cibiDelGiorno(key, di: di))
    }

    // il piano del giorno di questa settimana (tiene conto se la giornata è stata passata a ON o OFF)
    func pianoGiorno(_ di: Int, oggi: Bool = true) -> DayPlan {
        var conv: Conv?
        if oggi, let o = ov(chiaveGiorno(di)), let t = o.type, !t.isEmpty {
            conv = Conv(type: t == "ON" ? "ON" : "OFF_S", keep: o.keep ?? [])
        }
        return piano.dayPlan(di, conv: conv, swaps: d.swaps, cibi: cibiDelGiorno(chiaveGiorno(di), di: di))
    }
    var pianoOggi: DayPlan { pianoGiorno(oggiIdx) }

    // se il giorno (di default oggi) è in modalità ON (allenamento) oppure OFF (riposo)
    func giornoOn(_ di: Int? = nil) -> Bool {
        let p = pianoGiorno(di ?? oggiIdx)
        return (p.conv.isEmpty ? p.day.type : p.conv).hasPrefix("ON")
    }

    // switch Giornata ON / OFF: cambia obiettivi e dosi di pranzo e cena per il giorno scelto (oggi o nella vista Piano)
    func impostaGiornoOn(_ on: Bool, di: Int? = nil) {
        let idx = di ?? oggiIdx
        let key = chiaveGiorno(idx)
        let baseOn = piano.week[idx].type == "ON"
        let haAllenamento = cronologia.contains { Cal.key(Date(timeIntervalSince1970: $0.start / 1000)) == key }
        defer {
            Haptic.medio()
            if idx == oggiIdx || idx == (oggiIdx + 1) % 7 { riprogrammaPromemoria() }
        }
        if on == baseOn && !haAllenamento {
            d.dayov.removeValue(forKey: key)
            return
        }
        var o = d.dayov[key] ?? DayOv()
        o.type = on ? "ON" : "OFF"
        o.skip = on ? nil : true
        if on, o.rid == nil, idx == oggiIdx {
            o.rid = d.active?.rid ?? cronologia.first { Cal.key(Date(timeIntervalSince1970: $0.start / 1000)) == key }?.rid
        }
        // i pasti già mangiati quel giorno restano con le dosi con cui li hai mangiati: cambiano solo quelli da mangiare
        o.keep = mangiati(key)
        o.t = Cal.ms()
        d.dayov[key] = o
    }

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
    // un piatto nuovo riparte dalla sua ricetta: i cibi cambiati a mano erano di quello di prima
    func cambiaPiatto(di: Int, si: Int, codice: String) {
        let k = "\(di):\(si)"
        let m = (di == oggiIdx ? pianoOggi : pianoGiorno(di)).meals[si]
        if codice == m.def { d.swaps.removeValue(forKey: k) } else { d.swaps[k] = codice }
        d.cibiPasto.removeValue(forKey: chiaveCibi(di, si))
        Haptic.leggero()
        if d.promemoria["merenda"] == true { riprogrammaPromemoria() }   // il promemoria della sera dice le merende giuste
    }
    func ripristinaGiorno(_ di: Int) {
        d.swaps = d.swaps.filter { !$0.key.hasPrefix("\(di):") }
        d.cibiPasto = d.cibiPasto.filter { !$0.key.hasPrefix(chiaveGiorno(di) + ":") }
        d.dayov.removeValue(forKey: chiaveGiorno(di))
        if d.promemoria["merenda"] == true { riprogrammaPromemoria() }
    }
    // il giorno ha piatti, cibi o modalità ON/OFF cambiati (il Piano mostra «Rimetti gli originali»)
    func giornoCambiato(_ di: Int) -> Bool {
        let p = pianoGiorno(di)
        return !p.conv.isEmpty || d.swaps.keys.contains { $0.hasPrefix("\(di):") } || p.meals.contains { $0.cambiato }
    }

    // MARK: i cibi di un pasto

    // si parte dai cibi che il pasto ha adesso (la ricetta o quelli già cambiati) e si salva la lista nuova, solo per
    // quel giorno (domani torna il piano); se torna uguale alla ricetta del piano, non resta niente di cambiato
    private func cambiaCibi(_ di: Int, _ m: MealPlan, _ cambia: (inout [IngredientRef]) -> Void) {
        guard !m.free else { return }
        var cibi = m.lines.map(\.ref)
        cambia(&cibi)
        let k = chiaveCibi(di, m.si)
        if cibi.isEmpty || cibi == piano.variants[m.slot]?[m.code] { d.cibiPasto.removeValue(forKey: k) }
        else { d.cibiPasto[k] = CibiPasto(slot: m.slot, piatto: m.code, cibi: cibi) }
        Registro.evento("cibi del pasto \(k): " + cibi.map { "\($0.f) \(Int($0.g))" }.joined(separator: ", "))
        // pasto di oggi già segnato: in Salute vanno i numeri nuovi (stesso identificativo, sostituisce quello di prima)
        if di == oggiIdx && mangiati().contains(m.si) { pastoInSalute(si: m.si, mangiato: true) }
        Haptic.leggero()
        if d.promemoria["merenda"] == true { riprogrammaPromemoria() }   // i panini di domani con i cibi giusti
    }
    // un cibo al posto di un altro (se c'è già nel pasto, si sommano i grammi; se rimetti il cibo della ricetta, torna ai grammi esatti della ricetta)
    // olio: grammi d'olio da aggiungere (+) o togliere (−) nel pasto per pareggiare i grassi (scambio a macro uguali)
    func scambiaCibo(di: Int, _ m: MealPlan, _ i: Int, con nuovo: IngredientRef, olio: Double = 0) {
        cambiaCibi(di, m) { c in
            guard c.indices.contains(i) else { return }
            var ref = nuovo
            if let orig = piano.variants[m.slot]?[m.code], orig.indices.contains(i), orig[i].f == ref.f, ref.nome == nil,
               let k = piano.foods[ref.f]?.k, abs((orig[i].g - ref.g) * k / 100) <= 18 {
                ref.g = orig[i].g
            }
            if let j = c.indices.first(where: { $0 != i && c[$0].f == ref.f && c[$0].nome == ref.nome }) {
                c[j].g += ref.g
                c.remove(at: i)
            } else { c[i] = ref }
            // l'olio del pasto sale o scende; se non basta da togliere, resta la differenza (si vede nelle kcal)
            guard olio != 0, ref.f != "olio" else { return }
            if let j = c.firstIndex(where: { $0.f == "olio" && $0.nome == nil }) {
                let g = c[j].g + olio
                if g < 3 { c.remove(at: j) } else { c[j].g = g }
            } else if olio > 0 {
                c.append(IngredientRef(f: "olio", g: olio))
            }
        }
    }
    func grammiCibo(di: Int, _ m: MealPlan, _ i: Int, piu: Bool) {
        cambiaCibi(di, m) { c in
            guard c.indices.contains(i) else { return }
            let passo = piano.passo(c[i])
            c[i].g = max(5, c[i].g + (piu ? passo : -passo))
        }
    }
    func impostaGrammiCibo(di: Int, _ m: MealPlan, _ i: Int, grammi: Double) {
        let g = max(1, r0(grammi))
        cambiaCibi(di, m) { c in
            guard c.indices.contains(i) else { return }
            c[i].g = g
        }
    }
    func togliCibo(di: Int, _ m: MealPlan, _ i: Int) {
        cambiaCibi(di, m) { c in if c.count > 1 && c.indices.contains(i) { c.remove(at: i) } }
    }
    func aggiungiCibo(di: Int, _ m: MealPlan, _ fid: String) {
        aggiungiCiboRef(di: di, m, IngredientRef(f: fid, g: piano.doseNuova(fid, slot: m.slot)))
    }
    func aggiungiCiboRef(di: Int, _ m: MealPlan, _ nuovo: IngredientRef) {
        cambiaCibi(di, m) { c in
            if let j = c.firstIndex(where: { $0.f == nuovo.f && $0.nome == nuovo.nome }) { c[j].g += nuovo.g } else { c.append(nuovo) }
        }
    }
    // i prodotti esterni usati di recente (codice a barre, Open Food Facts, a mano): pronti con un tocco
    func cibiEsterniRecenti() -> [IngredientRef] {
        var visti = Set<String>()
        var out: [IngredientRef] = []
        func metti(_ r: IngredientRef) {
            guard r.k100 != nil, piano.foods[r.f] == nil, let n = r.nome, !n.isEmpty else { return }
            guard visti.insert(n.lowercased()).inserted else { return }
            out.append(r)
        }
        for x in d.cibiPasto.values { for c in x.cibi { metti(c) } }
        for g in d.fuori.keys.sorted(by: >) {
            for p in d.fuori[g] ?? [] {
                for v in p.voci where v.fonte.map({ piano.foods[$0] == nil }) ?? true {
                    metti(IngredientRef(f: v.fonte ?? "fuori", g: v.g, nome: v.nome, k100: v.k100, p100: v.p100, c100: v.c100, f100: v.f100))
                }
            }
        }
        for p in d.mieiPasti {
            for v in p.voci where v.fonte.map({ piano.foods[$0] == nil }) ?? true {
                metti(IngredientRef(f: v.fonte ?? "fuori", g: v.g, nome: v.nome, k100: v.k100, p100: v.p100, c100: v.c100, f100: v.f100))
            }
        }
        return Array(out.prefix(8))
    }
    func rimettiRicetta(di: Int, _ m: MealPlan) {
        d.cibiPasto.removeValue(forKey: chiaveCibi(di, m.si))
        Haptic.leggero()
        if d.promemoria["merenda"] == true { riprogrammaPromemoria() }
    }

    func totaliMangiati(_ key: String? = nil) -> Tot {
        let k = key ?? oggiKey
        let plan = k == oggiKey ? pianoOggi : pianoPerData(k)
        let eaten = mangiati(k)
        let fuori = d.fuori[k] ?? []
        let sostituite = Set(fuori.compactMap(\.si))
        let tolti = Set(d.saltati[k] ?? [])
        var t = Tot()
        for m in plan.meals where !m.free && eaten.contains(m.si) && !sostituite.contains(m.si) && !tolti.contains(m.si) {
            t.k += m.tot.k; t.p += m.tot.p; t.c += m.tot.c; t.fa += m.tot.fa
        }
        // i pasti fuori piano contano per quello che hai mangiato davvero (i tuoi pasti preparati, solo quando li mangi)
        for f in fuori where f.giaMangiato { let x = f.tot; t.k += x.k; t.p += x.p; t.c += x.c; t.fa += x.fa }
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
        impostaGiornoOn(si)
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
    // la scheda di oggi (tiene conto di palestra saltata, recuperata o già fatta oggi)
    var schedaOggi: String? {
        if let o = ov(oggiKey) {
            if o.skip == true { return nil }
            if let r = o.rid, !r.isEmpty { return r }
        }
        if let r = piano.week[oggiIdx].wo { return r }
        if giornoOn() {
            return d.active?.rid ?? cronologia.first { Cal.key(Date(timeIntervalSince1970: $0.start / 1000)) == oggiKey }?.rid
        }
        return nil
    }
}

// vibrazioni (tocchi del telefono)
enum Haptic {
    static func leggero() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medio() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func forte() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func ok() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
