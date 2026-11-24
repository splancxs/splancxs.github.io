import ActivityKit
import AudioToolbox
import Foundation
import UIKit
import UserNotifications

// L'allenamento in corso: serie, recupero, fine. Stessa logica dell'app web (allenamento.js), scritta una volta sola
// e usata sia dai tocchi sul telefono sia dagli eventi dell'orologio (WatchBridge).
extension AppStore {
    func nuovoId() -> String {
        "w" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String((0..<4).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
    }

    var inCorso: ActiveWorkout? { d.active }

    // allenamento nuovo da una scheda (o libero); id e inizio arrivano dall'orologio se parte da lì
    func nuovoAllenamento(_ r: Routine?, id: String? = nil, inizio: Double? = nil, daOrologio: Bool = false) -> ActiveWorkout {
        ActiveWorkout(
            id: id ?? nuovoId(), rid: r?.id, name: r?.name ?? "Allenamento libero", start: inizio ?? Cal.ms(),
            items: (r?.items ?? []).map { it in
                ItemRec(ex: it.ex, lo: it.lo, hi: it.hi, rest: it.rest, sup: it.sup, kg: it.kg, note: "",
                        sets: Array(repeating: SetRec(), count: it.s))
            },
            fromWatch: daOrologio)
    }

    func avvia(_ rid: String?) {
        if d.active != nil { tabAperta = 1; return }
        d.active = nuovoAllenamento(rid.flatMap { routine($0) })
        if !giornoOn() { impostaGiornoOn(true) }
        if let rid, var o = d.dayov[oggiKey] { o.rid = rid; d.dayov[oggiKey] = o }
        mostraRiepilogo = nil
        tabAperta = 1
        Haptic.medio()
        Notifiche.chiediPermesso()
        riprogrammaPromemoria()   // allenamento in corso: niente promemoria della palestra oggi
    }

    // MARK: serie

    // MARK: superserie (una per una)

    // «4a» e «4b» sono la superserie 4 della scheda: si spegne (o si riaccende) solo quella, e la scelta resta per le volte dopo
    func chiaveSuperserie(_ rid: String?, _ sup: String) -> String { "\(rid ?? ""):\(sup.dropLast())" }
    func superserieAttiva(_ rid: String?, _ sup: String) -> Bool { !sup.isEmpty && !d.supSpente.contains(chiaveSuperserie(rid, sup)) }
    func toccaSuperserie(_ rid: String?, _ sup: String) {
        let k = chiaveSuperserie(rid, sup)
        if let i = d.supSpente.firstIndex(of: k) { d.supSpente.remove(at: i) } else { d.supSpente.append(k) }
        Haptic.leggero()
    }
    // l'esercizio abbinato nella superserie (4a ↔ 4b), se c'è
    func compagno(_ a: ActiveWorkout, _ i: Int) -> Int? {
        guard a.items.indices.contains(i) else { return nil }
        let sup = a.items[i].sup
        guard !sup.isEmpty else { return nil }
        let base = String(sup.dropLast())
        return a.items.indices.first { $0 != i && !a.items[$0].sup.isEmpty && String(a.items[$0].sup.dropLast()) == base }
    }

    func recuperoDi(_ a: ActiveWorkout, _ i: Int) -> Int {
        guard a.items.indices.contains(i) else { return 90 }   // esercizio appena tolto: la sua scheda si sta chiudendo
        let it = a.items[i]
        if it.rest > 0 || it.sup.isEmpty || superserieAttiva(a.rid, it.sup) { return it.rest }
        let base = String(it.sup.dropLast())
        let mate = a.items.enumerated().first { $0.offset != i && !$0.element.sup.isEmpty && String($0.element.sup.dropLast()) == base }
        return (mate?.element.rest ?? 0) > 0 ? mate!.element.rest : 75
    }

    func etichettaProssima(_ a: ActiveWorkout, _ i: Int, _ j: Int) -> String {
        func fmt(_ ii: Int, _ jj: Int) -> String {
            let it = a.items[ii]
            let e = esercizio(it.ex)
            let ph = suggerito(it, jj)
            let s = it.sets[jj]
            let kg = s.kg ?? ph.kg
            let r = s.r ?? ph.r
            let dettaglio = e.unit == "sec" ? " · \(r)″" : kg != nil ? " · \(pesoConUnita(it.ex, kg)) × \(r)" : ""
            return "\(nomeBreve(it.ex)) · serie \(jj + 1)\(dettaglio)"
        }
        // in superserie si alterna: dopo la serie del primo esercizio la stessa serie del secondo, poi si torna al primo
        if superserieAttiva(a.rid, a.items[i].sup), let m = compagno(a, i) {
            let jm = a.items[i].sup.hasSuffix("a") ? j : j + 1
            if a.items[m].sets.indices.contains(jm), !a.items[m].sets[jm].done { return "Subito: " + fmt(m, jm) }
        }
        if let jn = a.items[i].sets.indices.first(where: { $0 > j && !a.items[i].sets[$0].done }) { return "Prossima: " + fmt(i, jn) }
        if i + 1 < a.items.count {
            for ii in (i + 1)..<a.items.count {
                if let jj = a.items[ii].sets.firstIndex(where: { !$0.done }) { return "Poi: " + fmt(ii, jj) }
            }
        }
        return "Ultima serie fatta: termina e fai il cardio"
    }

    // spunta (o toglie la spunta): riempie kg e ripetizioni vuoti con quelli suggeriti e fa partire il recupero
    func toccaSerie(_ i: Int, _ j: Int) {
        guard var a = d.active, a.items.indices.contains(i), a.items[i].sets.indices.contains(j) else { return }
        var s = a.items[i].sets[j]
        if !s.done {
            let ph = suggerito(a.items[i], j)
            if s.kg == nil && esercizio(a.items[i].ex).unit != "sec" { s.kg = ph.kg }
            if s.r == nil { s.r = ph.r }
            s.done = true
            a.items[i].sets[j] = s
            propagaPeso(&a, i, j)
            let rec = recuperoDi(a, i)
            if rec > 0 {
                let ora = Cal.ms()
                a.restStart = ora
                a.restEnd = ora + Double(rec) * 1000
                a.restRv = ora
                a.restNext = etichettaProssima(a, i, j)
            }
            d.active = a
            aggiornaRecuperoEsterno()
            Haptic.medio()
        } else {
            s.done = false
            a.items[i].sets[j] = s
            d.active = a
            aggiornaRecuperoEsterno()
        }
    }

    // serie spuntata da un evento esterno (orologio): non la toglie mai e non fa partire il recupero (lo manda l'orologio)
    @discardableResult
    func spuntaSerie(_ i: Int, _ j: Int, kg: Double?, r: Int?) -> Bool {
        guard var a = d.active, a.items.indices.contains(i), a.items[i].sets.indices.contains(j), !a.items[i].sets[j].done else { return false }
        if let kg, kg >= 0 { a.items[i].sets[j].kg = kg }
        if let r, r > 0 { a.items[i].sets[j].r = r }
        a.items[i].sets[j].done = true
        propagaPeso(&a, i, j)
        d.active = a
        return true
    }

    // le serie dopo dello stesso esercizio (ancora da fare e senza un peso scritto) partono dal carico appena usato:
    // lo fa anche l'orologio, così quando il telefono gli rimanda lo stato il peso non torna a quello suggerito di prima
    private func propagaPeso(_ a: inout ActiveWorkout, _ i: Int, _ j: Int) {
        guard let kg = a.items[i].sets[j].kg else { return }
        for k in a.items[i].sets.indices where k > j && !a.items[i].sets[k].done && a.items[i].sets[k].kg == nil {
            a.items[i].sets[k].kg = kg
        }
    }

    func scrivi(_ i: Int, _ j: Int, kg: Double?? = nil, r: Int?? = nil) {
        guard var a = d.active, a.items.indices.contains(i), a.items[i].sets.indices.contains(j) else { return }
        if let kg { a.items[i].sets[j].kg = kg }
        if let r { a.items[i].sets[j].r = r }
        d.active = a
    }

    func cambiaTipo(_ i: Int, _ j: Int) {
        guard var a = d.active, a.items.indices.contains(i), a.items[i].sets.indices.contains(j) else { return }
        let next = ["n": "w", "w": "d", "d": "f", "f": "n"]
        a.items[i].sets[j].type = next[a.items[i].sets[j].type] ?? "n"
        d.active = a
        Haptic.leggero()
    }
    func sforzo(_ i: Int, _ j: Int, _ v: Int) {
        guard var a = d.active, a.items.indices.contains(i), a.items[i].sets.indices.contains(j) else { return }
        a.items[i].sets[j].rpe = a.items[i].sets[j].rpe == v ? nil : v
        d.active = a
        Haptic.leggero()
    }
    func aggiungiSerie(_ i: Int) {
        guard var a = d.active, a.items.indices.contains(i) else { return }
        let ultima = a.items[i].sets.last
        a.items[i].sets.append(SetRec(kg: ultima?.kg))
        d.active = a
    }
    func togliSerie(_ i: Int) {
        guard var a = d.active, a.items.indices.contains(i), a.items[i].sets.count > 1 else { return }
        a.items[i].sets.removeLast()
        d.active = a
    }
    func spostaEsercizio(_ i: Int, _ delta: Int) {
        guard var a = d.active, a.items.indices.contains(i), a.items.indices.contains(i + delta) else { return }
        a.items.swapAt(i, i + delta)
        d.active = a
    }
    func togliEsercizio(_ i: Int) {
        guard var a = d.active, a.items.indices.contains(i) else { return }
        a.items.remove(at: i)
        d.active = a
    }
    func aggiungiEsercizio(_ ex: String) {
        guard var a = d.active else { return }
        let e = esercizio(ex)
        a.items.append(ItemRec(ex: ex, lo: e.unit == "sec" ? 30 : 8, hi: e.unit == "sec" ? 45 : 12, rest: 90,
                               sets: Array(repeating: SetRec(), count: 3)))
        d.active = a
    }
    func sostituisciEsercizio(_ i: Int, con ex: String) {
        guard var a = d.active, a.items.indices.contains(i) else { return }
        a.items[i].ex = ex
        a.items[i].kg = nil
        d.active = a
    }
    func nota(_ i: Int, _ testo: String) {
        guard var a = d.active, a.items.indices.contains(i) else { return }
        a.items[i].note = testo
        d.active = a
    }

    // MARK: recupero

    func avviaRecupero(_ secondi: Int, prossima: String) {
        guard var a = d.active else { return }
        let ora = Cal.ms()
        a.restStart = ora
        a.restEnd = ora + Double(secondi) * 1000
        a.restRv = ora
        a.restNext = prossima
        d.active = a
        aggiornaRecuperoEsterno()
        // la Live Activity non si chiude a fine recupero: mostra «Via!» con la prossima serie e resta fino alla fine dell'allenamento
    }
    func cambiaRecupero(_ delta: Double) {   // secondi in più o in meno
        guard var a = d.active, a.restEnd > Cal.ms() else { return }
        a.restEnd = max(Cal.ms() + 1000, a.restEnd + delta * 1000)
        a.restRv = Cal.ms()
        d.active = a
        aggiornaRecuperoEsterno()
    }
    func saltaRecupero() {
        guard var a = d.active else { return }
        a.restEnd = 0
        a.restRv = Cal.ms()
        d.active = a
        aggiornaRecuperoEsterno()
    }
    // recupero deciso dall'orologio (−15″, salta, serie fatta lì): il telefono lo segue
    func recuperoDaOrologio(fine: Double, prossima: String, quando: Double) {
        guard var a = d.active else { return }
        a.restEnd = fine > Cal.ms() ? fine : 0
        a.restStart = a.restEnd > 0 ? min(a.restStart == 0 ? Cal.ms() : a.restStart, a.restEnd - 1000) : a.restStart
        if !prossima.isEmpty { a.restNext = prossima }
        a.restRv = quando
        d.active = a
        aggiornaRecuperoEsterno()
    }
    func recuperoAttivo(_ a: ActiveWorkout?) -> Date? {
        guard let a, a.restEnd > Cal.ms() else { return nil }
        return Date(timeIntervalSince1970: a.restEnd / 1000)
    }
    // trova l'indice (i, j) della prossima serie da fare, rispettando anche l'alternanza delle superserie
    func indiceProssimaSerie(_ a: ActiveWorkout) -> (i: Int, j: Int)? {
        for (i, it) in a.items.enumerated() {
            guard let j = it.sets.firstIndex(where: { !$0.done }) else { continue }
            if superserieAttiva(a.rid, it.sup), it.sup.hasSuffix("a"), let m = compagno(a, i),
               let jm = a.items[m].sets.firstIndex(where: { !$0.done }), jm < j {
                return (m, jm)
            }
            return (i, j)
        }
        return nil
    }

    func descriviSerie(_ a: ActiveWorkout, _ i: Int, _ j: Int) -> (esercizio: String, dettaglio: String, rec: Int) {
        let it = a.items[i]
        let e = esercizio(it.ex)
        let ph = suggerito(it, j)
        let s = it.sets[j]
        let kg = s.kg ?? ph.kg
        let r = s.r ?? ph.r
        let numeri = e.unit == "sec" ? " · \(r)″" : kg != nil ? " · \(pesoConUnita(it.ex, kg)) × \(r)" : ""
        return (nomeBreve(it.ex), "Serie \(j + 1) di \(it.sets.count)" + numeri, recuperoDi(a, i))
    }

    // la prossima serie da fare (per la Live Activity tra una serie e l'altra): esercizio, dettaglio, recupero e serie successiva
    func prossimaDaFare(_ a: ActiveWorkout) -> (esercizio: String, dettaglio: String, rec: Int, nextEx: String?, nextDet: String?) {
        if let (i, j) = indiceProssimaSerie(a) {
            let cur = descriviSerie(a, i, j)
            var sim = a
            sim.items[i].sets[j].done = true
            let dopo = indiceProssimaSerie(sim).map { descriviSerie(sim, $0.i, $0.j) }
            return (cur.esercizio, cur.dettaglio, cur.rec, dopo?.esercizio, dopo?.dettaglio)
        }
        if a.items.isEmpty { return (a.name, "Aggiungi gli esercizi dall'app", 0, nil, nil) }
        return ("Tutte le serie fatte", "Termina l'allenamento e fai il cardio", 0, nil, nil)
    }

    // applica un pulsante toccato nella Dynamic Island o nella schermata di blocco (−15″, +15″, Salta, Serie fatta)
    // fine: il risultato già mostrato sull'isola dall'estensione (fine del recupero in ms, 0 = finito): si copia così com'è
    func eseguiAzioneIsola(_ tipo: String, fine: Double? = nil) {
        guard let a = d.active else { return }
        if let fine, tipo != "fatta" {
            var b = a
            if fine > Cal.ms() {
                if b.restEnd <= Cal.ms() { b.restStart = Cal.ms() }
                b.restEnd = fine
            } else {
                b.restEnd = 0
            }
            b.restRv = Cal.ms()
            d.active = b
            aggiornaRecuperoEsterno()
            Registro.evento("isola \(tipo) dall'estensione: recupero " + (fine > Cal.ms() ? "ancora \(Int((fine - Cal.ms()) / 1000)) s" : "finito"))
            return
        }
        switch tipo {
        case "meno15":
            if a.restEnd - 15_000 <= Cal.ms() + 500 {
                saltaRecupero()
            } else {
                cambiaRecupero(-15)
            }
            Haptic.leggero()
        case "piu15":
            if a.restEnd > Cal.ms() {
                cambiaRecupero(15)
            } else {
                avviaRecupero(15, prossima: a.restNext)
            }
            Haptic.leggero()
        case "salta":
            saltaRecupero()
            Haptic.medio()
        case "fatta":
            if let (i, j) = indiceProssimaSerie(a) {
                toccaSerie(i, j)
            }
        default:
            break
        }
    }

    // applica eventuali azioni accodate nel gruppo condiviso (−15″, +15″, Salta, Serie fatta)
    func processaAzioniIsola() {
        let eventi = CodaIsola.leggiESvuota()
        for ev in eventi { eseguiAzioneIsola(ev.tipo, fine: ev.fine) }
    }

    // l'isola è già aggiornata (CodaIsola.esegui): qui l'app copia il risultato. Senza isola attiva (fine nil) fa il conto lei.
    func eseguiAzioneIsolaSubito(_ tipo: String, fine: Double?) async {
        eseguiAzioneIsola(tipo, fine: fine)
        CodaIsola.segnaCompletato()
    }

    func processaAzioniIsolaSubito() async {
        let eventi = CodaIsola.leggiESvuota()
        guard !eventi.isEmpty else { return }
        for ev in eventi { eseguiAzioneIsola(ev.tipo, fine: ev.fine) }
        await RecuperoLive.attendiUltimoUpdate()
        CodaIsola.segnaCompletato()
    }

    // scatta al secondo esatto di fine recupero (anche in background breve) così la Dynamic Island non resta su 0:00
    func fineRecuperoAutomatica() {
        guard var a = d.active, a.restEnd > 0, a.restEnd <= Cal.ms() + 250 else { return }
        a.restEnd = 0
        d.active = a
        aggiornaRecuperoEsterno()
    }

    // Live Activity e notifica di fine recupero (la notifica non serve se avvisa già l'orologio).
    // La Live Activity c'è per tutto l'allenamento: col recupero il conto alla rovescia, se no la prossima serie.
    func aggiornaRecuperoEsterno() {
        guard let a = d.active else {
            RecuperoLive.termina()
            Notifiche.togliRecupero()
            return
        }
        let serie = a.items.flatMap(\.sets)
        let fatte = serie.filter(\.done).count
        let p = prossimaDaFare(a)
        guard a.restEnd > Cal.ms() else {
            RecuperoLive.avvia(inizio: Date(), fine: Date(), esercizio: p.esercizio, dettaglio: p.dettaglio, allenamento: a.name,
                               modo: "go", fatte: fatte, totali: serie.count,
                               restSec: p.rec, nextEx: p.nextEx, nextDet: p.nextDet)
            Notifiche.togliRecupero()
            return
        }
        let fine = Date(timeIntervalSince1970: a.restEnd / 1000)
        let inizio = Date(timeIntervalSince1970: a.restStart / 1000)
        let (es, dettaglio) = a.restNext.split(separator: "·", maxSplits: 1).count == 2
            ? (String(a.restNext.split(separator: "·", maxSplits: 1)[0]).replacingOccurrences(of: "Prossima: ", with: "").replacingOccurrences(of: "Poi: ", with: "").replacingOccurrences(of: "Subito: ", with: "").trimmingCharacters(in: .whitespaces),
               String(a.restNext.split(separator: "·", maxSplits: 1)[1]).trimmingCharacters(in: .whitespaces))
            : (a.restNext, "")
        RecuperoLive.avvia(inizio: inizio, fine: fine, esercizio: es.isEmpty ? p.esercizio : es, dettaglio: dettaglio.isEmpty ? p.dettaglio : dettaglio, allenamento: a.name,
                           modo: nil, fatte: fatte, totali: serie.count,
                           restSec: p.rec, nextEx: p.nextEx, nextDet: p.nextDet)
        if d.notifRest && !a.fromWatch { Notifiche.recupero(fine: fine, testo: a.restNext) } else { Notifiche.togliRecupero() }
    }

    // MARK: fine

    // salva l'allenamento attivo in cronologia (solo le serie fatte) e lo chiude
    @discardableResult
    func finisci(hr: Int? = nil, kcal: Int? = nil, daOrologio: Bool = false) -> Workout? {
        guard let a = d.active else { return nil }
        annullaTimer()
        let items = a.items.map { it -> ItemRec in var c = it; c.sets = it.sets.filter(\.done); return c }.filter { !$0.sets.isEmpty }
        d.active = nil
        aggiornaRecuperoEsterno()
        guard !items.isEmpty else { return nil }
        var w = Workout(id: a.id, rid: a.rid, name: a.name, start: a.start, end: Cal.ms(), items: items, hr: hr, kcal: kcal, watch: daOrologio ? true : nil)
        w.prs = calcolaPrimati(items, id: a.id)
        d.workouts.removeAll { $0.id == w.id }
        d.workouts.append(w)
        mostraRiepilogo = w
        riprogrammaPromemoria()   // il riepilogo della domenica conta anche questo allenamento
        Haptic.forte()
        return w
    }

    func annulla() {
        annullaTimer()
        d.active = nil
        aggiornaRecuperoEsterno()
        Haptic.leggero()
    }

    // MARK: timer degli esercizi a tempo (plank, side plank)

    // «Via» su una serie a tempo: 3″ per mettersi in posizione, poi il conto alla rovescia (nel side plank i due lati, con 5″
    // per girarsi). Alla fine la serie si segna da sola con i secondi e parte il recupero; «Ferma» salva i secondi tenuti.
    func avviaTimer(_ i: Int, _ j: Int) {
        guard timerSerie == nil, let a = d.active, let it = a.items[safe: i], it.sets.indices.contains(j), !it.sets[j].done else { return }
        let t = TimerTempo(dove: [i, j], ex: it.ex, durata: max(5, it.sets[j].r ?? suggerito(it, j).r), lati: TimerTempo.lati(it.ex),
                           inizio: Date().addingTimeInterval(TimerTempo.pronti))
        timerSerie = t
        UIApplication.shared.isIdleTimerDisabled = true   // il telefono resta acceso a terra accanto a te
        Haptic.medio()
        for c in t.cambi {
            DispatchQueue.main.asyncAfter(deadline: .now() + c.timeIntervalSinceNow) { [weak self] in
                if self?.timerSerie?.id == t.id { Haptic.forte(); AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + t.fine.timeIntervalSinceNow) { [weak self] in self?.chiudiTimer(t.id, fermato: false) }
        Notifiche.tempo(fine: t.fine, testo: "\(nomeBreve(it.ex)) · serie \(j + 1): fatta")
    }
    func fermaTimer() { if let t = timerSerie { chiudiTimer(t.id, fermato: true) } }
    func annullaTimer() {
        guard timerSerie != nil else { return }
        timerSerie = nil
        UIApplication.shared.isIdleTimerDisabled = false
        Notifiche.togliTempo()
    }
    private func chiudiTimer(_ id: UUID, fermato: Bool) {
        guard let t = timerSerie, t.id == id else { return }
        let tenuti = fermato ? t.tenuti(Date()) : t.durata
        annullaTimer()
        // la serie è ancora quella (nel frattempo l'esercizio non è stato spostato o tolto) e non è già fatta
        guard tenuti > 0, let a = d.active, a.items.indices.contains(t.dove[0]), a.items[t.dove[0]].ex == t.ex,
              a.items[t.dove[0]].sets.indices.contains(t.dove[1]), !a.items[t.dove[0]].sets[t.dove[1]].done else { return }
        scrivi(t.dove[0], t.dove[1], r: tenuti)
        toccaSerie(t.dove[0], t.dove[1])
        Haptic.ok()
        if !fermato { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
    }

    // record personali battuti rispetto alla cronologia precedente
    func calcolaPrimati(_ items: [ItemRec], id: String) -> [RecordPR] {
        var out: [RecordPR] = []
        for it in items {
            let old = primati(it.ex, escludi: id)
            let e = esercizio(it.ex)
            let work = it.sets.filter(\.isWork)
            if work.isEmpty || (old.kg == 0 && old.e1 == 0 && old.sec == 0) { continue }   // prima volta: nessun confronto
            // assistita: il record è ripetere di più con la stessa assistenza o meno (i kg sono aiuto, non carico)
            if e.assistita {
                let ora = work.compactMap { s in s.kg.map { ($0, s.r ?? 0) } }
                let prima = cronologia.filter { $0.id != id }.flatMap { $0.items.filter { $0.ex == it.ex } }.flatMap { $0.sets.filter(\.isWork) }
                    .compactMap { s in s.kg.map { ($0, s.r ?? 0) } }
                let minAss = prima.map(\.0).min() ?? .infinity
                if let meglio = ora.filter({ $0.0 < minAss && $0.1 >= it.lo }).min(by: { $0.0 < $1.0 }) {
                    out.append(RecordPR(ex: it.ex, k: "Assistenza minima", v: "\(fmtKg(meglio.0)) kg"))
                }
                continue
            }
            if e.unit == "sec" {
                let best = work.map { $0.r ?? 0 }.max() ?? 0
                if best > old.sec { out.append(RecordPR(ex: it.ex, k: "Tempo massimo", v: "\(best)″")) }
                continue
            }
            let bestKg = work.map { $0.kg ?? 0 }.max() ?? 0
            let bestE1 = work.map { e1rm($0.kg ?? 0, $0.r ?? 0) }.max() ?? 0
            let vol = volOf(it.sets)
            if bestKg > old.kg { out.append(RecordPR(ex: it.ex, k: "Carico massimo", v: "\(fmtKg(bestKg)) kg")) }
            if bestE1 > old.e1 + 0.05 { out.append(RecordPR(ex: it.ex, k: "1RM stimato", v: "\(fmtKg(r1(bestE1))) kg")) }
            if vol > old.vol { out.append(RecordPR(ex: it.ex, k: "Volume", v: "\(fmtNum(r0(vol), 0)) kg")) }
        }
        return out
    }

    func eliminaAllenamento(_ id: String) { d.workouts.removeAll { $0.id == id } }
}

// MARK: Live Activity del recupero (schermata di blocco, Dynamic Island, orologio)

// iOS fa partire una Live Activity solo con l'app aperta davanti; aggiornarla invece si può anche dal background (per
// esempio quando l'orologio manda una serie e il telefono è in tasca). Per questo resta aperta per tutto l'allenamento:
// parte appena l'app è davanti con un allenamento in corso e si chiude solo quando l'allenamento finisce.
@MainActor
enum RecuperoLive {
    private static var ultimo: String = ""   // l'ultimo stato mandato: lo stesso non si rimanda
    private static var timerFine: Timer?
    private static var bgTask: UIBackgroundTaskIdentifier = .invalid
    private static var taskInCorso: Task<Void, Never>?

    static func attendiUltimoUpdate() async {
        await taskInCorso?.value
    }

    private static func rinnovaBg() {
        let vecchio = bgTask
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "RecompRecupero") {
            Task { @MainActor in chiudiBg() }
        }
        if vecchio != .invalid {
            UIApplication.shared.endBackgroundTask(vecchio)
        }
    }

    private static func programmaFine(_ fine: Date?) {
        timerFine?.invalidate()
        timerFine = nil
        rinnovaBg()
        guard let fine, fine.timeIntervalSinceNow > 0 else { return }
        let t = Timer(fire: fine.addingTimeInterval(0.05), interval: 0, repeats: false) { _ in
            Task { @MainActor in
                AppStore.shared.fineRecuperoAutomatica()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timerFine = t
    }

    private static func chiudiBg() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }

    static func avvia(inizio: Date, fine: Date, esercizio: String, dettaglio: String, allenamento: String,
                      modo: String? = nil, fatte: Int? = nil, totali: Int? = nil,
                      restSec: Int? = nil, nextEx: String? = nil, nextDet: String? = nil) {
        guard #available(iOS 16.2, *), !AppStore.inProva || AppStore.liveInProva, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        programmaFine(modo == "go" ? nil : fine)
        let stato = RestAttributes.ContentState(start: min(inizio, fine), end: fine, exercise: esercizio, detail: dettaglio,
                                                mode: modo, done: fatte, total: totali,
                                                restSec: restSec, nextEx: nextEx, nextDet: nextDet)
        // nel recupero «scaduta» alla fine (l'estensione mostra «VIA!»); tra le serie non scade
        let contenuto = ActivityContent(state: stato, staleDate: modo == "go" ? nil : fine)
        let chiave = "\(allenamento)|\(modo ?? "r")|\(Int(fine.timeIntervalSince1970))|\(esercizio)|\(dettaglio)|\(fatte ?? 0)/\(totali ?? 0)"
        let aperte = Activity<RestAttributes>.activities
        if chiave == ultimo, aperte.contains(where: { $0.attributes.workout == allenamento && $0.activityState == .active }) { return }
        ultimo = chiave
        taskInCorso = Task {
            if let a = aperte.first(where: { $0.attributes.workout == allenamento && $0.activityState == .active }) {
                // l'isola mostra già questo (l'ha appena aggiornata il tocco su −15″, +15″, Salta): niente secondo
                // aggiornamento. Ogni aggiornamento fa ridisegnare all'estensione ~96 versioni dell'isola (~0,8 s)
                let c = a.content.state
                if abs(c.end.timeIntervalSince(stato.end)) < 1, c.mode == stato.mode, c.exercise == stato.exercise,
                   c.detail == stato.detail, c.done == stato.done, c.total == stato.total {
                    return
                }
                await a.update(contenuto)
                for b in aperte where b.id != a.id { await b.end(nil, dismissalPolicy: .immediate) }
                return
            }
            for a in aperte { await a.end(nil, dismissalPolicy: .immediate) }
            // con l'app in background non parte (iOS non lo permette): riprovo quando l'app torna davanti
            if (try? Activity.request(attributes: RestAttributes(workout: allenamento), content: contenuto)) == nil { ultimo = "" }
        }
    }
    static func termina() {
        guard #available(iOS 16.2, *), !AppStore.inProva || AppStore.liveInProva else { return }
        timerFine?.invalidate()
        timerFine = nil
        chiudiBg()
        ultimo = ""
        taskInCorso = Task { for a in Activity<RestAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) } }
    }
}

// MARK: notifiche

enum Notifiche {
    static func chiediPermesso() {
        let c = UNUserNotificationCenter.current()
        c.getNotificationSettings { s in
            if s.authorizationStatus == .notDetermined { c.requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        }
    }
    static func recupero(fine: Date, testo: String) {
        guard !AppStore.inProva else { return }
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: ["recupero"])
        let t = fine.timeIntervalSinceNow
        guard t > 1 else { return }
        let contenuto = UNMutableNotificationContent()
        contenuto.title = "Recupero finito"
        contenuto.body = testo.isEmpty ? "Via con la prossima serie" : testo
        contenuto.sound = .default
        c.add(UNNotificationRequest(identifier: "recupero", content: contenuto, trigger: UNTimeIntervalNotificationTrigger(timeInterval: t, repeats: false)))
    }
    static func togliRecupero() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["recupero"])
    }
    // fine del timer di un esercizio a tempo, se il telefono è bloccato
    static func tempo(fine: Date, testo: String) {
        guard !AppStore.inProva else { return }
        let c = UNUserNotificationCenter.current()
        let t = fine.timeIntervalSinceNow
        guard t > 1 else { return }
        let n = UNMutableNotificationContent()
        n.title = "Tempo!"
        n.body = testo
        n.sound = .default
        c.add(UNNotificationRequest(identifier: "tempo", content: n, trigger: UNTimeIntervalNotificationTrigger(timeInterval: t, repeats: false)))
    }
    static func togliTempo() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["tempo"]) }
}
