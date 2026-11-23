import SwiftUI

// Ritmo del peso: la media di ogni settimana (da lunedì a domenica, almeno 3 pesate) confrontata con quella prima, letta con
// le regole del nutrizionista (piano v3): calo tra 0,15 e 0,45 kg a settimana = si va avanti così; sopra 0,45 per 2 settimane
// = +150 kcal; sotto 0,15 per 2–3 settimane = prima si cercano gli errori (pesature, olio, weekend, uscite), poi più passi,
// solo dopo −100 kcal. La prima settimana della dieta non conta: il peso scende di più per acqua e glicogeno.

struct RitmoPeso {
    struct Settimana: Hashable { let lunedi: Date; let media: Double; let pesate: Int; let finita: Bool }
    enum Stato { case pochi, inLinea, veloce, troppoVeloce, lento, fermo }

    var settimane: [Settimana] = []   // dalla più vecchia; solo quelle con almeno 3 pesate
    var cali: [Double] = []           // kg persi a settimana, settimana finita per settimana finita (positivo = scendi), dalla più vecchia
    var stato: Stato = .pochi
    var titolo = "Pochi dati"
    var testo = ""
    var ritmo: Double?                // kg a settimana, media delle ultime 2 settimane
    var arrivo: Date?                 // quando arrivi all'obiettivo a questo ritmo

    var colore: Color {
        switch stato {
        case .inLinea: Tema.verde
        case .veloce, .lento: Tema.ambra
        case .troppoVeloce, .fermo: Tema.rosso
        case .pochi: Tema.tenue
        }
    }
}

extension AppStore {
    static let inizioDieta = "2026-09-28"
    static let obiettivoPeso = 62.5

    func ritmoPeso() -> RitmoPeso {
        var r = RitmoPeso()
        let questa = Cal.lunedi()
        let inizio = Cal.date(AppStore.inizioDieta)
        // la prima settimana della dieta non conta (acqua e glicogeno)
        let valide = pesate.filter { Cal.date($0.d) >= Cal.giorni(7, da: inizio) }
        var perSettimana: [Date: [Double]] = [:]
        for p in pesate where Cal.date(p.d) >= inizio { perSettimana[Cal.lunedi(Cal.date(p.d)), default: []].append(p.kg) }
        r.settimane = perSettimana.keys.sorted().map { lun in
            let v = perSettimana[lun] ?? []
            return .init(lunedi: lun, media: v.reduce(0, +) / Double(v.count), pesate: v.count, finita: lun < questa)
        }

        // il ritmo è la retta delle pesate (minimi quadrati): regge anche con 1–2 pesate a settimana, dove le medie
        // settimanali salterebbero. c1 = ultime 3 settimane, c2 = ultime 6 (per le regole «da 2–3 settimane»)
        guard let ultima = valide.last else {
            r.testo = "Il ritmo si vede dopo qualche settimana di pesate (la prima settimana della dieta non conta: è acqua)."
            return r
        }
        let fine = Cal.date(ultima.d)
        func ritmo(_ giorni: Int, minimo: Int, arco: Int) -> (kgSett: Double, valore: Double)? {
            let da = Cal.giorni(-giorni, da: fine)
            let punti = valide.filter { Cal.date($0.d) >= da }.map { (Cal.date($0.d).timeIntervalSince(fine) / 86400, $0.kg) }
            guard punti.count >= minimo, let x0 = punti.first?.0, -x0 >= Double(arco) else { return nil }
            let n = Double(punti.count)
            let mx = punti.reduce(0) { $0 + $1.0 } / n, my = punti.reduce(0) { $0 + $1.1 } / n
            let sxx = punti.reduce(0) { $0 + ($1.0 - mx) * ($1.0 - mx) }
            guard sxx > 0 else { return nil }
            let b = punti.reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / sxx
            return (-b * 7, my - b * mx)   // calo a settimana (positivo = scendi) e peso «di oggi» sulla retta
        }
        let c2 = ritmo(42, minimo: 4, arco: 14)
        guard let c1 = ritmo(21, minimo: 3, arco: 10) ?? c2 else {
            r.testo = "Servono almeno 4 pesate in 2 settimane per vedere il ritmo: pesati 2–3 volte a settimana, a digiuno."
            return r
        }
        let principale = c2 ?? c1
        r.cali = [principale.kgSett, c1.kgSett]
        let kg = { (x: Double) in fmtNum(r1Due(abs(x)), 2) }
        let ora = c1.kgSett >= 0 ? "scendi di \(kg(c1.kgSett)) kg a settimana" : "sali di \(kg(c1.kgSett)) kg a settimana"
        let lungo = principale.kgSett
        if c1.kgSett > 0.45 && lungo > 0.45 {
            r.stato = .troppoVeloce; r.titolo = "Troppo veloce"
            r.testo = "Da settimane scendi più di 0,45 kg a settimana: così rischi di perdere muscolo. La regola del nutrizionista è +150 kcal al giorno: chiedigli dove metterle."
        } else if c1.kgSett > 0.45 {
            r.stato = .veloce; r.titolo = "Veloce"
            r.testo = "Nelle ultime 3 settimane \(ora), sopra 0,45. Può essere acqua; se continua, la regola è +150 kcal al giorno."
        } else if c1.kgSett < 0.15 && lungo < 0.15 {
            r.stato = .fermo; r.titolo = "Fermo"
            r.testo = "Da settimane scendi meno di 0,15 kg a settimana. Prima cerca gli errori: cibo pesato bene, olio col cucchiaio, weekend e uscite segnati davvero. Poi più passi (circa 2.000 in più al giorno), solo dopo −100 kcal (lo decide il nutrizionista)."
        } else if c1.kgSett < 0.15 {
            r.stato = .lento; r.titolo = "Più lento"
            r.testo = "Nelle ultime 3 settimane \(ora), sotto 0,15. Può essere acqua (sale, pasto libero, allenamenti più duri): guarda le prossime pesate."
        } else {
            r.stato = .inLinea; r.titolo = "In linea"
            r.testo = "Nelle ultime 3 settimane \(ora); sulle ultime 6 il ritmo è quello qui sopra. Dentro 0,15–0,45, come vuole il nutrizionista: avanti così."
        }
        let giorniFa = Cal.greg.dateComponents([.day], from: fine, to: Cal.greg.startOfDay(for: Date())).day ?? 0
        if giorniFa > 6 {
            r.testo += " Ultima pesata il \(Cal.testo(fine, "d MMMM")): pesati 2–3 volte a settimana, a digiuno, così il ritmo è affidabile."
        }
        r.ritmo = lungo
        if lungo > 0.05, principale.valore > AppStore.obiettivoPeso {
            let giorni = (principale.valore - AppStore.obiettivoPeso) / lungo * 7
            if giorni < 365 { r.arrivo = Cal.giorni(Int(giorni.rounded()), da: fine) }
        }
        return r
    }
    // in parole, per il coach e i suoi messaggi
    func ritmoTesto() -> String? {
        let r = ritmoPeso()
        guard r.stato != .pochi, let ritmo = r.ritmo else { return nil }
        let medie = r.settimane.filter(\.finita).suffix(4).map { "\(Cal.testo($0.lunedi, "d MMM")) \(fmtPeso($0.media))" }
        var t = "Ritmo del peso: \(ritmo >= 0 ? "−" : "+")\(fmtNum(r1Due(abs(ritmo)), 2)) kg a settimana (medie settimanali: \(medie.joined(separator: " → "))). Stato: \(r.titolo.lowercased()). \(r.testo)"
        if let a = r.arrivo { t += " A questo ritmo arriva a \(fmtNum(AppStore.obiettivoPeso)) kg verso il \(Cal.testo(a, "d MMMM"))." }
        return t
    }
}

func r1Due(_ x: Double) -> Double { (x * 100).rounded() / 100 }

// la scheda in Progressi, sotto il peso: lo stato, le medie delle ultime settimane e cosa fare
struct RitmoPesoScheda: View {
    @EnvironmentObject var s: AppStore

    var body: some View {
        let r = s.ritmoPeso()
        Scheda {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text("RITMO").font(.sport(22))
                    Spacer()
                    Text(r.titolo.uppercased()).font(.system(size: 12, weight: .heavy)).foregroundStyle(Tema.inchiostro)
                        .padding(.horizontal, 10).frame(height: 24).background(r.colore, in: Capsule())
                }
                if let ritmo = r.ritmo {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(ritmo >= 0 ? "−" : "+")\(fmtNum(r1Due(abs(ritmo)), 2))").font(.sport(48)).monospacedDigit()
                        Text("kg a settimana").font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.tenue)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, -4)
                    fascia(ritmo)
                }
                let viste = Array(r.settimane.suffix(4))
                if !viste.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(viste.enumerated()), id: \.offset) { i, w in
                            colonna(w, prima: i > 0 ? Optional(viste[i - 1]) : r.settimane.dropLast(viste.count).last)
                        }
                    }
                }
                Text(r.testo).font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                if let a = r.arrivo {
                    Label("A questo ritmo: \(fmtNum(AppStore.obiettivoPeso)) kg verso il \(Cal.testo(a, "d MMMM"))", systemImage: "flag.checkered")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.tenue)
                }
            }
        }
    }

    // dove cade il ritmo: la zona giusta del nutrizionista (0,15–0,45) in verde, il puntino è il tuo
    private func fascia(_ ritmo: Double) -> some View {
        GeometryReader { g in
            let lo = -0.1, hi = 0.7
            let x = { (v: Double) in (min(hi, max(lo, v)) - lo) / (hi - lo) * Double(g.size.width) }
            ZStack(alignment: .leading) {
                Capsule().fill(Tema.scheda2).frame(height: 8)
                Capsule().fill(Tema.verde.opacity(0.55)).frame(width: x(0.45) - x(0.15), height: 8).offset(x: x(0.15))
                Circle().fill(Tema.testo).frame(width: 14, height: 14).overlay(Circle().stroke(Tema.scheda, lineWidth: 2))
                    .offset(x: x(ritmo) - 7)
            }
            .frame(height: 14)
        }
        .frame(height: 14)
        .overlay(alignment: .bottomLeading) {
            HStack {
                Text("fermo").font(.system(size: 10, weight: .semibold))
                Spacer()
                Text("0,15–0,45 kg").font(.system(size: 10, weight: .semibold))
                Spacer()
                Text("veloce").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Tema.tenue).offset(y: 16)
        }
        .padding(.bottom, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ritmo \(fmtNum(r1Due(ritmo), 2)) kg a settimana; la zona giusta è tra 0,15 e 0,45")
    }

    private func colonna(_ w: RitmoPeso.Settimana, prima: RitmoPeso.Settimana?) -> some View {
        // la differenza solo con la settimana subito prima (se in mezzo ne manca una, non si confronta)
        let calo = prima.flatMap { p in Cal.greg.dateComponents([.day], from: p.lunedi, to: w.lunedi).day == 7 ? p.media - w.media : nil }
        return VStack(alignment: .leading, spacing: 2) {
            Text(w.finita ? Cal.testo(w.lunedi, "d MMM") : "Questa").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tema.tenue).lineLimit(1)
            Text(fmtPeso(w.media)).font(.system(size: 15, weight: .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            if let calo {
                Text("\(calo >= 0 ? "−" : "+")\(fmtNum(r1Due(abs(calo)), 2))").font(.system(size: 11, weight: .bold)).monospacedDigit()
                    .foregroundStyle(calo >= 0.15 && calo <= 0.45 ? Tema.verde : Tema.ambra)
            } else {
                Text(" ").font(.system(size: 11))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.scheda2.opacity(w.finita ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
