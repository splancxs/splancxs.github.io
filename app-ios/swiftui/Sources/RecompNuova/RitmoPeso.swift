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
        let primaDellaDieta = Cal.lunedi(Cal.date(AppStore.inizioDieta))
        var perSettimana: [Date: [Double]] = [:]
        for p in pesate { perSettimana[Cal.lunedi(Cal.date(p.d)), default: []].append(p.kg) }
        r.settimane = perSettimana.filter { $0.value.count >= 3 }.keys.sorted().map { lun in
            let v = perSettimana[lun] ?? []
            return .init(lunedi: lun, media: v.reduce(0, +) / Double(v.count), pesate: v.count, finita: lun < questa)
        }
        // cali tra settimane finite (se ne manca una in mezzo, il calo si divide per le settimane passate);
        // il confronto con la prima settimana della dieta non conta
        let finite = r.settimane.filter(\.finita)
        for (a, b) in zip(finite, finite.dropFirst()) where a.lunedi > primaDellaDieta {
            let settimane = max(1, Double(Cal.greg.dateComponents([.day], from: a.lunedi, to: b.lunedi).day ?? 7) / 7)
            r.cali.append((a.media - b.media) / settimane)
        }

        let kg = { (x: Double) in fmtNum(r1Due(abs(x)), 2) }
        guard let c1 = r.cali.last else {
            r.testo = "Il ritmo si vede dopo 2 settimane intere con almeno 3 pesate ciascuna (la prima settimana della dieta non conta: è acqua)."
            return r
        }
        let c2 = r.cali.dropLast().last, c3 = r.cali.dropLast(2).last
        let questaSettimana = c1 >= 0 ? "hai perso \(kg(c1)) kg" : "sei salito di \(kg(c1)) kg"
        if c1 > 0.45, let c2, c2 > 0.45 {
            r.stato = .troppoVeloce; r.titolo = "Troppo veloce"
            r.testo = "Da 2 settimane scendi più di 0,45 kg a settimana: così rischi di perdere muscolo. La regola del nutrizionista è +150 kcal al giorno: chiedigli dove metterle."
        } else if c1 > 0.45 {
            r.stato = .veloce; r.titolo = "Veloce"
            r.testo = "L'ultima settimana \(questaSettimana), sopra 0,45. Una settimana sola può essere acqua; se succede anche la prossima, la regola è +150 kcal al giorno."
        } else if c1 < 0.15, let c2, c2 < 0.15 {
            r.stato = .fermo; r.titolo = "Fermo"
            if let c3, c3 < 0.15 {
                r.testo = "Da 3 settimane scendi meno di 0,15 kg. Se pesature, olio, weekend e uscite sono già a posto, il passo dopo sono più passi (circa 2.000 in più al giorno); solo se non basta, −100 kcal (lo decide il nutrizionista)."
            } else {
                r.testo = "Da 2 settimane scendi meno di 0,15 kg. Prima cerca gli errori: cibo pesato bene, olio col cucchiaio, weekend e uscite segnati davvero. Poi più passi, solo dopo −100 kcal."
            }
        } else if c1 < 0.15 {
            r.stato = .lento; r.titolo = "Più lento"
            r.testo = "L'ultima settimana \(questaSettimana), sotto 0,15. Una settimana sola può essere acqua (sale, pasto libero, allenamenti più duri): guarda la prossima."
        } else {
            r.stato = .inLinea; r.titolo = "In linea"
            r.testo = "L'ultima settimana \(questaSettimana): dentro 0,15–0,45, come vuole il nutrizionista. Avanti così."
        }
        let ultimi = Array(r.cali.suffix(2))
        let ritmo = ultimi.reduce(0, +) / Double(ultimi.count)
        r.ritmo = ritmo
        if ritmo > 0.05, let u = finite.last, u.media > AppStore.obiettivoPeso {
            // la media è il peso di metà settimana (giovedì)
            let giorni = (u.media - AppStore.obiettivoPeso) / ritmo * 7
            if giorni < 365 { r.arrivo = Cal.giorni(3 + Int(giorni.rounded()), da: u.lunedi) }
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
        let calo = prima.map { $0.media - w.media }
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
