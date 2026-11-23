import Foundation

// Controlli sul PC dei conti di Recomp, senza telefono (app-ios/xtool/controlli.sh): compila con Piano.swift, Modelli.swift,
// Cibi.swift, Aiuti.swift e CibiFuori.swift dell'app (gli stessi file, non copie da tenere allineate) e verifica sul
// piano.json vero: cibi esistenti, scambi a macro uguali (con l'olio), porzioni intere, totali dei giorni.
// Scrive solo i problemi e un riassunto; esce con 1 se c'è almeno un errore.

let percorso = CommandLine.arguments.dropFirst().first ?? "piano.json"
guard let dati = FileManager.default.contents(atPath: percorso),
      let piano = try? JSONDecoder().decode(Piano.self, from: dati) else {
    print("Non leggo il piano: \(percorso)"); exit(2)
}

var controlli = 0
var errori: [String] = []
var avvisi: [String] = []
func verifica(_ ok: Bool, _ testo: @autoclosure () -> String) {
    controlli += 1
    if !ok { errori.append(testo()) }
}
func n(_ x: Double) -> String { String(format: "%.1f", x) }

// 1 ─ ogni cibo delle ricette esiste nel piano, con grammi sensati
for (slot, piatti) in piano.variants {
    for (codice, cibi) in piatti {
        for c in cibi {
            verifica(piano.foods[c.f] != nil, "\(slot)/\(codice): il cibo «\(c.f)» non esiste in foods")
            verifica(c.g > 0 && c.g < 1000, "\(slot)/\(codice): \(c.f) con \(n(c.g)) g")
        }
        verifica(piano.recipes[codice] != nil, "\(slot)/\(codice): manca la ricetta (nome e preparazione)")
    }
}

// 2 ─ scambi: per ogni cibo di ogni ricetta, le alternative tengono il macro principale (proteine o carboidrati) e,
//     a pranzo e a cena, i grassi pareggiati con l'olio. Tolleranza: i cibi a pezzi si arrotondano al pezzo intero
//     (porzioni da piatto vero), l'olio a 5 g.
var scambiProvati = 0
for (slot, piatti) in piano.variants.sorted(by: { $0.key < $1.key }) {
    for (codice, cibi) in piatti.sorted(by: { $0.key < $1.key }) {
        for c in cibi where c.f != "olio" {
            guard let da = piano.foods[c.f] else { continue }
            let proteine = da.p >= da.c
            let principale = (proteine ? da.p : da.c) * c.g / 100
            guard principale > 1 else { continue }
            for x in piano.scambi(c.f, c.g, slot: slot) {
                scambiProvati += 1
                let dove = "\(slot)/\(codice): \(c.f) \(Int(c.g)) g → \(x.ref.f) \(Int(x.ref.g)) g"
                verifica(x.ref.f != c.f, "\(dove): propone lo stesso cibo")
                if let gruppo = Piano.gruppoScambio(c.f) {
                    verifica(gruppo.contains(x.ref.f), "\(dove): fuori dalla sua categoria (carne e pesce / latticini / uova)")
                }
                verifica(x.ref.g >= 5, "\(dove): porzione troppo piccola")
                guard let a = piano.foods[x.ref.f] else { verifica(false, "\(dove): cibo sconosciuto"); continue }
                let perCento = proteine ? a.p : a.c
                if perCento <= 0.5 { continue }   // scambio solo a calorie (per esempio frutta ↔ verdura)
                let nuovo = perCento * x.ref.g / 100
                let mezzoPezzo = (a.u ?? 0) / 2 * perCento / 100
                let tolleranza = max(3, principale * 0.12, mezzoPezzo + 1)
                verifica(abs(nuovo - principale) <= tolleranza,
                         "\(dove): \(proteine ? "proteine" : "carboidrati") \(n(principale)) → \(n(nuovo)) g (tolleranza \(n(tolleranza)))")
                if piano.conOlio(slot) {
                    let grassiDopo = a.f * x.ref.g / 100 + x.olio * 0.999
                    let grassiPrima = da.f * c.g / 100
                    // se l'olio va tolto ma la ricetta non ne ha abbastanza, nell'app restano le kcal in più (lo dice la nota)
                    let olioRicetta = cibi.filter { $0.f == "olio" }.reduce(0) { $0 + $1.g }
                    if x.olio < 0 && -x.olio > olioRicetta {
                        avvisi.append("\(dove): andrebbero tolti \(Int(-x.olio)) g d'olio, la ricetta ne ha \(Int(olioRicetta))")
                        continue
                    }
                    verifica(abs(grassiDopo - grassiPrima) <= 3,
                             "\(dove): grassi \(n(grassiPrima)) → \(n(grassiDopo)) g con \(Int(x.olio)) g d'olio")
                    verifica(x.olio.truncatingRemainder(dividingBy: 5) == 0, "\(dove): olio non a multipli di 5 g (\(x.olio))")
                }
            }
        }
    }
}

// 3 ─ le dosi «vere» sono stabili: rifare l'arrotondamento non cambia niente
for (fid, _) in piano.foods {
    for g in [37.0, 80, 125, 163, 250] {
        let a = piano.doseVera(fid, g)
        verifica(piano.doseVera(fid, a) == a, "doseVera(\(fid)): \(n(g)) → \(n(a)) → \(n(piano.doseVera(fid, a)))")
    }
}

// 4 ─ totali dei giorni contro l'obiettivo del nutrizionista (ON e OFF). Il pasto libero (~700 kcal) è fuori dai totali.
var tabella: [String] = []
for di in 0..<piano.week.count {
    for tipo in ["ON", "OFF_S"] {
        let p = piano.dayPlan(di, conv: Conv(type: tipo, keep: []))
        let obiettivo = piano.daytypes[p.conv.isEmpty ? p.day.type : p.conv]?.target ?? piano.daytypes[tipo]!.target
        let libero = p.hasFree ? 700.0 : 0
        let k = p.tot.k + libero
        let diff = (k - obiettivo[0]) / obiettivo[0]
        tabella.append("\(p.day.name.prefix(3)) \(tipo == "ON" ? "ON " : "OFF") \(Int(k)) / \(Int(obiettivo[0])) kcal · P \(Int(p.tot.p)) / \(Int(obiettivo[1]))")
        // le dosi sono del nutrizionista: oltre il 5% è un avviso, oltre il 12% vuol dire un errore nei conti dell'app
        verifica(abs(diff) <= 0.12, "\(p.day.name) \(tipo): \(Int(k)) kcal contro \(Int(obiettivo[0])) (\(Int(diff * 100))%)")
        if abs(diff) > 0.05 && abs(diff) <= 0.12 {
            avvisi.insert("\(p.day.name) \(tipo): \(Int(k)) kcal contro \(Int(obiettivo[0])) (\(diff > 0 ? "+" : "")\(Int((diff * 100).rounded()))%)", at: 0)
        }
        verifica(p.tot.p >= obiettivo[1] * 0.85 || p.hasFree, "\(p.day.name) \(tipo): proteine \(Int(p.tot.p)) contro \(Int(obiettivo[1]))")
        for m in p.meals where !m.free {
            verifica(!m.lines.isEmpty, "\(p.day.name) \(tipo): \(m.label) senza cibi")
        }
    }
}

// riassunto
if CommandLine.arguments.contains("--giorni") { tabella.forEach { print($0) } }
if !avvisi.isEmpty {
    print("Avvisi (\(avvisi.count)):"); avvisi.prefix(15).forEach { print("  · " + $0) }
    if avvisi.count > 15 { print("  … e altri \(avvisi.count - 15)") }
}
if errori.isEmpty {
    print("CONTROLLI OK: \(controlli) verifiche (\(scambiProvati) scambi) sul piano \(piano.version).")
    exit(0)
}
print("SBAGLIATI \(errori.count) su \(controlli):")
errori.prefix(40).forEach { print("  ✗ " + $0) }
if errori.count > 40 { print("  … e altri \(errori.count - 40)") }
exit(1)
