import Foundation
import os

// Debug dal PC, senza Mac. I messaggi finiscono nel registro di sistema dell'iPhone e si leggono con
// «app-ios\xtool\windows\debug.ps1 registro». Solo eventi e errori dell'app: mai dati personali, chiavi o testi del coach.
enum Registro {
    private static let log = Logger(subsystem: "io.github.splancxs.recomp", category: "app")
    static func evento(_ t: String) { log.notice("RECOMP \(t, privacy: .public)") }
    static func errore(_ t: String) { log.error("RECOMP ERRORE \(t, privacy: .public)") }
}

extension AppStore {
    // «debug.ps1 apri …» lancia l'app con RECOMP_APRI: apre una pagina o una finestra, senza toccare i dati.
    //   oggi · piano · scheda · progressi · profilo · coach · settimana
    //   pasto:3 (la finestra del pasto della fascia 3 di oggi) · cibo:3:1 (in quella, il cibo 1) · aggiungi:3 (Aggiungi al pasto)
    func apriPerDebug(_ a: String) {
        Registro.evento("apri per debug: \(a)")
        let p = a.split(separator: ":").map(String.init)
        switch p.first ?? "" {
        case "oggi": tabAperta = 0
        case "scheda": tabAperta = 1
        case "piano": tabAperta = 2
        case "progressi": tabAperta = 3
        case "profilo": tabAperta = 4
        case "coach": tabAperta = 0; mostraCoach = true
        case "settimana": tabAperta = 3; mostraSettimana = true
        case "pasto", "cibo", "aggiungi", "fuori": tabAperta = 0; debugApri = a
        case "spesa": tabAperta = 2; debugSezionePiano = 1
        case "scambi": tabAperta = 2; debugSezionePiano = 2
        case "miei": tabAperta = 2; debugSezionePiano = 3
        case "storico": tabAperta = 1; debugSezioneScheda = 1
        case "numeri": tabAperta = 1; debugSezioneScheda = 2
        case "dettaglio": tabAperta = 1; debugSezioneScheda = 3
        default: Registro.errore("apri per debug: «\(a)» non lo conosco")
        }
    }

    // modalità prova: dopo azioni e schermata, lo stato dell'app in testo nel registro («RECOMP STATO …»), poi «RECOMP pronto».
    // Il giro di controllo (debug.sh giro) aspetta «pronto» invece di un tempo fisso e salva lo stato accanto allo screenshot:
    // numeri esatti (grammi, kcal, macro, scambi proposti, serie) invece di leggerli dalle immagini. Solo sulla copia dei dati.
    func statoPerDebug(_ aperto: String) {
        guard AppStore.inProva else { return }
        func f(_ x: Double) -> String { fmtNum(r1(x)) }
        func tot(_ t: Tot) -> String { "\(Int(t.k)) kcal P \(f(t.p)) C \(f(t.c)) G \(f(t.fa))" }
        var r: [String] = []
        let p = pianoOggi
        let t = p.dt.target
        let fatti = Set(mangiati())
        r.append("giorno \(p.day.name) \(p.conv.isEmpty ? p.day.type : p.conv) · obiettivo \(Int(t[safe: 0] ?? 0)) kcal P \(Int(t[safe: 1] ?? 0)) · piano \(tot(p.tot)) · mangiato \(tot(totaliMangiati()))")
        for m in p.meals {
            if m.free { r.append("pasto \(m.si) \(m.time) \(m.label): libero"); continue }
            var stato: [String] = []
            if fatti.contains(m.si) { stato.append("mangiato") }
            if pastoTolto(m.si) { stato.append("tolto") }
            if m.cambiato { stato.append("cambiato") }
            if m.code != m.def { stato.append("piatto scambiato") }
            r.append("pasto \(m.si) \(m.time) \(m.label): \(m.code) «\(piano.recipe(m.code).name)» \(tot(m.tot))" + (stato.isEmpty ? "" : " [\(stato.joined(separator: ", "))]"))
            for (i, l) in m.lines.enumerated() {
                r.append("  cibo \(m.si):\(i) \(l.f) \(f(l.g)) \(piano.unitaPeso(l.f)) «\(piano.nome(l))» \(Int(l.k)) kcal P \(f(l.p)) C \(f(l.c)) G \(f(l.fa))")
            }
            if let x = fuoriPerFascia(m.si) { r.append("  al suo posto: «\(x.nome)» \(tot(x.tot))\(x.giaMangiato ? "" : " (da mangiare)")") }
        }
        // la scelta di un cibo aperta: gli scambi che l'app propone, con l'olio
        let a = aperto.split(separator: ":").compactMap { Int($0) }
        if aperto.hasPrefix("cibo"), a.count > 1, let m = p.meals[safe: a[0]], let l = m.lines[safe: a[1]] {
            for x in piano.scambi(l.f, l.g, slot: m.slot) {
                let n = piano.line(x.ref)
                r.append("  scambio \(l.f) → \(x.ref.f) \(f(x.ref.g)) g\(x.olio != 0 ? " olio \(x.olio > 0 ? "+" : "")\(Int(x.olio)) g" : "") · \(Int(n.k)) kcal P \(f(n.p)) C \(f(n.c)) G \(f(n.fa))")
            }
        }
        if let w = d.active {
            let fatte = w.items.reduce(0) { $0 + $1.sets.filter(\.done).count }, tutte = w.items.reduce(0) { $0 + $1.sets.count }
            r.append("allenamento in corso \(w.name): \(fatte)/\(tutte) serie")
            for it in w.items {
                r.append("  \(it.ex): " + it.sets.map { "\(peso(it.ex, $0.kg))×\($0.r ?? 0)\($0.done ? "✓" : "")" }.joined(separator: " "))
            }
        } else if let w = d.workouts.filter({ $0.del != true }).max(by: { $0.end < $1.end }) {
            r.append("ultimo allenamento \(w.name) \(Cal.key(Date(timeIntervalSince1970: w.end / 1000))): \(w.minutes) min, \(w.workSets) serie, \(Int(w.volume)) kg, \(w.prs.count) record")
        }
        for (i, riga) in r.enumerated() { Registro.evento(String(format: "STATO %02d ", i) + riga) }
        Registro.evento("pronto \(aperto)")
    }

    // modalità prova: azioni come se le toccassi tu, separate da «;» (solo sulla copia dei dati: vedi AppStore.inProva)
    //   aggiungi:3:parmigiano[:20] · scambia:3:0:pollo · grammi:3:1:+ (o - o =120) · togli:3:2 · piano:3 (come il piano)
    //   mangiato:3 · creatina · onoff:on|off · avvia:TA · serie:0:0 · kg:0:1:62.5 · salta · finisci · annulla
    func eseguiAzioniProva(_ testo: String) {
        guard AppStore.inProva else { Registro.errore("azioni ignorate: non sono in modalità prova"); return }
        for a in testo.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) where !a.isEmpty {
            Registro.evento("azione \(a)")
            let p = a.split(separator: ":").map(String.init)
            let n = p.dropFirst().compactMap { Int($0) }
            let pasto = n.first.flatMap { pianoOggi.meals[safe: $0] }
            switch p[0] {
            case "aggiungi":
                if let m = pasto, p.count > 2 {
                    let g = p.count > 3 ? Double(p[3]) : nil
                    aggiungiCiboRef(di: oggiIdx, m, IngredientRef(f: p[2], g: g ?? piano.doseNuova(p[2], slot: m.slot)))
                }
            case "scambia":
                if let m = pasto, n.count > 1, p.count > 3, let l = m.lines[safe: n[1]] {
                    // come il tocco nella scelta: stesse proteine (o carboidrati) e i grassi pareggiati con l'olio
                    if let x = piano.scambi(l.f, l.g, slot: m.slot).first(where: { $0.ref.f == p[3] }) {
                        scambiaCibo(di: oggiIdx, m, n[1], con: x.ref, olio: x.olio)
                    } else {
                        scambiaCibo(di: oggiIdx, m, n[1], con: IngredientRef(f: p[3], g: piano.doseNuova(p[3], slot: m.slot)))
                    }
                }
            case "grammi":
                if let m = pasto, n.count > 1, p.count > 3 {
                    if p[3] == "+" || p[3] == "-" { grammiCibo(di: oggiIdx, m, n[1], piu: p[3] == "+") }
                    else if let g = Double(p[3].replacingOccurrences(of: "=", with: "")) { impostaGrammiCibo(di: oggiIdx, m, n[1], grammi: g) }
                }
            case "togli": if let m = pasto, n.count > 1 { togliCibo(di: oggiIdx, m, n[1]) }
            case "piano": if let m = pasto { rimettiRicetta(di: oggiIdx, m) }
            case "mangiato": if let si = n.first { toccaMangiato(si) }
            case "creatina": toccaCreatina()
            case "onoff": impostaGiornoOn(p.count > 1 && p[1] == "on")
            case "avvia": avvia(p.count > 1 ? p[1] : schedaOggi)
            case "serie": if n.count > 1 { toccaSerie(n[0], n[1]) }
            case "kg": if n.count > 1, p.count > 3, let kg = Double(p[3]) { scrivi(n[0], n[1], kg: kg) }
            case "salta": saltaRecupero()
            case "finisci": finisci()
            case "annulla": annulla()
            default: Registro.errore("azione di prova sconosciuta: \(a)"); continue
            }
            Registro.evento("prova: \(a)")
        }
    }

    // le parti numeriche di debugApri («cibo:3:1» → [3, 1])
    var debugNumeri: [Int] { (debugApri ?? "").split(separator: ":").dropFirst().compactMap { Int($0) } }
    var debugTipo: String { (debugApri ?? "").split(separator: ":").first.map(String.init) ?? "" }
}
