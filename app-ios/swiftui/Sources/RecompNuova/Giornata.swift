import SwiftUI

// «Sistema la giornata»: quando la giornata va sopra il piano (un pasto fuori, cibi in più), l'app propone 2–3 cene con i cibi
// del piano, calcolate sulle kcal che restano e sulle proteine che mancano. Sotto il piano non compare niente.
// Rispetta il minimo del nutrizionista (2.000 kcal nei giorni ON, 100 sotto l'obiettivo negli altri) e le porzioni vere:
// carne e pesce a passi di 50 g, vaschette intere, pane a fette, un vasetto di yogurt. Scelta una, va al posto della cena
// come tuo pasto da mangiare; se non ci sta più, si toglie anche lo spuntino.

struct OpzioneCena: Identifiable {
    let id = UUID()
    let nome: String
    let voci: [VoceCibo]
    var tot: Tot { Tot(k: voci.reduce(0) { $0 + $1.k }, p: voci.reduce(0) { $0 + $1.p }, c: voci.reduce(0) { $0 + $1.c }, fa: voci.reduce(0) { $0 + $1.f }) }
}

struct PropostaGiornata {
    let pasto: MealPlan           // il pasto da sistemare (di solito la cena)
    let togli: [MealPlan]         // i pasti dopo da togliere (lo spuntino) quando non ci stanno più
    let proiezione: Tot           // dove arriva la giornata mangiando il resto del piano
    let obiettivo: Tot
    let kcal: Double              // kcal per il pasto
    let proteine: Double          // proteine che servono nel pasto
    let opzioni: [OpzioneCena]
}

extension AppStore {
    private var obiettivoOggi: Tot {
        let t = pianoOggi.dt.target
        return Tot(k: t[safe: 0] ?? 0, p: t[safe: 1] ?? 0, c: t[safe: 2] ?? 0, fa: t[safe: 3] ?? 0)
    }
    // il minimo del giorno: 2.000 nei giorni di allenamento (disponibilità energetica), 100 sotto l'obiettivo negli altri
    private var minimoOggi: Double {
        let tipo = pianoOggi.conv.isEmpty ? pianoOggi.day.type : pianoOggi.conv
        return tipo.hasPrefix("ON") ? min(2000, obiettivoOggi.k) : obiettivoOggi.k - 100
    }

    // i pasti del piano che restano da fare oggi (non mangiati, non sostituiti, non tolti; il pasto libero no)
    func pastiDaFare() -> [MealPlan] {
        let fatti = Set(mangiati())
        return pianoOggi.meals.filter { !$0.free && !fatti.contains($0.si) && fuoriPerFascia($0.si) == nil && !pastoTolto($0.si) }
    }

    // dove arriva la giornata se mangi quello che resta: mangiato + pasti del piano da fare + tuoi pasti da mangiare + pasto libero stimato
    func proiezioneOggi() -> Tot {
        var t = totaliMangiati()
        func piu(_ x: Tot) { t.k += x.k; t.p += x.p; t.c += x.c; t.fa += x.fa }
        for m in pastiDaFare() { piu(m.tot) }
        for f in fuoriOggi() where !f.giaMangiato { piu(f.tot) }
        for m in pianoOggi.meals where m.free && fuoriPerFascia(m.si) == nil && !pastoTolto(m.si) { piu(stimaLibero) }
        return t
    }

    func propostaGiornata() -> PropostaGiornata? {
        let restanti = pastiDaFare()
        // si sistema un pasto vero (la cena, o il pranzo se la cena non c'è più), non uno spuntino
        guard let pasto = restanti.last(where: { $0.slot.hasPrefix("cena") }) ?? restanti.last(where: { $0.slot.hasPrefix("pranzo") }) else { return nil }
        let obiettivo = obiettivoOggi, proiezione = proiezioneOggi()
        // serve solo se la giornata va sopra il piano di più di 150 kcal (sotto non si dice niente: non serve recuperare)
        guard proiezione.k - obiettivo.k > 150 else { return nil }
        let dopo = restanti.filter { $0.si > pasto.si }
        let kDopo = dopo.reduce(0) { $0 + $1.tot.k }, pDopo = dopo.reduce(0) { $0 + $1.tot.p }
        // il resto della giornata, senza il pasto da sistemare e quelli dopo
        let baseK = proiezione.k - pasto.tot.k - kDopo, baseP = proiezione.p - pasto.tot.p - pDopo
        var togli: [MealPlan] = []
        var kcal = obiettivo.k - baseK - kDopo
        var proteine = obiettivo.p - baseP - pDopo
        if kcal < 300 && !dopo.isEmpty {   // lo spuntino non ci sta più: si toglie e la cena prende tutto
            togli = dopo
            kcal = obiettivo.k - baseK
            proteine = obiettivo.p - baseP
        }
        let tenuti = togli.isEmpty ? kDopo : 0
        kcal = min(950, max(kcal, minimoOggi - baseK - tenuti, 250))   // mai sotto il minimo del giorno, mai una cena enorme
        proteine = min(90, max(proteine, 20))
        let opzioni = componiCene(kcal: kcal, proteine: proteine)
        guard !opzioni.isEmpty else { return nil }
        return PropostaGiornata(pasto: pasto, togli: togli, proiezione: proiezione, obiettivo: obiettivo, kcal: kcal, proteine: proteine, opzioni: opzioni)
    }

    // tre cene diverse con i cibi del piano (quelle con cibi che non ci sono più nel piano si saltano)
    private func componiCene(kcal: Double, proteine: Double) -> [OpzioneCena] {
        [
            componi("Pollo e pane", carne: ("pollo", [150, 200, 250]), fissi: [],
                    carbo: ("pane_comune", [40, 60, 80, 100, 120]), kcal: kcal, proteine: proteine),
            componi("Merluzzo e patate", carne: ("merluzzo", [200, 250, 300]), fissi: [],
                    carbo: ("patate", [200, 250, 350, 450]), kcal: kcal, proteine: proteine),
            componi("Senza cucinare: tacchino e fiocchi", carne: ("tacchino_fette", [100, 200]), fissi: [],
                    carbo: ("pane_comune", [40, 50, 80, 100]), latticino: ("fiocchi_latte", 150), kcal: kcal, proteine: proteine),
        ].compactMap { $0 }
    }

    private func componi(_ nome: String, carne: (String, [Double]), fissi: [(String, Double)], carbo: (String, [Double]),
                         latticino: (String, Double)? = nil, kcal: Double, proteine: Double) -> OpzioneCena? {
        let f = piano.foods
        guard f[carne.0] != nil, f[carbo.0] != nil, fissi.allSatisfy({ f[$0.0] != nil }) else { return nil }
        func k(_ id: String, _ g: Double) -> Double { (f[id]?.k ?? 0) * g / 100 }
        func p(_ id: String, _ g: Double) -> Double { (f[id]?.p ?? 0) * g / 100 }
        // dolce proteico: 200 g di yogurt greco quando servono tante proteine e ci sono le kcal
        var yogurt = proteine > 55 && kcal >= 380 && f["yogurt"] != nil
        // il latticino (fiocchi di latte) nella cena senza cucinare, se servono proteine
        let latte = latticino.flatMap { l in f[l.0] != nil && proteine - (yogurt ? p("yogurt", 200) : 0) > 30 ? l : nil }
        let pAltro = (yogurt ? p("yogurt", 200) : 0) + (latte.map { p($0.0, $0.1) } ?? 0)
        // la carne: la porzione più piccola che dà le proteine che mancano
        var i = carne.1.firstIndex { p(carne.0, $0) >= proteine - pAltro } ?? carne.1.count - 1
        var olio = f["olio"] != nil ? 10.0 : 0
        func totale() -> Double {
            k(carne.0, carne.1[i]) + fissi.reduce(0) { $0 + k($1.0, $1.1) } + k("olio", olio)
                + (yogurt ? k("yogurt", 200) : 0) + (latte.map { k($0.0, $0.1) } ?? 0)
        }
        // troppo per le kcal che restano: meno olio, poi meno carne, poi niente yogurt
        if totale() > kcal && olio > 5 { olio = 5 }
        while totale() > kcal && i > 0 { i -= 1 }
        if totale() > kcal && yogurt { yogurt = false }
        // i carboidrati riempiono quello che resta (porzioni vere; un po' sopra va bene, sotto è meglio che troppo)
        let spazio = kcal - totale()
        let gCarbo = carbo.1.last { k(carbo.0, $0) <= spazio + 40 }
        // le righe, con i valori del piano per 100 g
        var righe: [(String, Double)] = [(carne.0, carne.1[i])]
        if let l = latte { righe.append(l) }
        if let g = gCarbo { righe.append((carbo.0, g)) }
        righe += fissi
        if olio > 0 { righe.append(("olio", olio)) }
        if yogurt { righe.append(("yogurt", 200)) }
        let voci = righe.compactMap { id, g -> VoceCibo? in
            guard let x = f[id] else { return nil }
            return VoceCibo(nome: piano.foodName(id), g: g, k100: x.k, p100: x.p, c100: x.c, f100: x.f, fonte: id)
        }
        return OpzioneCena(nome: nome, voci: voci)
    }

    // la cena scelta va al posto del pasto (da mangiare, la segni con la spunta); lo spuntino si toglie se non ci sta
    func usaProposta(_ o: OpzioneCena, _ p: PropostaGiornata) {
        salvaFuori(PastoFuori(si: p.pasto.si, nome: o.nome, voci: o.voci, t: Cal.ms(), mangiato: false))
        for m in p.togli { togliPasto(m.si) }
        Haptic.ok()
    }
}

// la scheda in Oggi
struct SistemaGiornata: View {
    @EnvironmentObject var s: AppStore
    let p: PropostaGiornata

    var body: some View {
        let nomePasto = (p.pasto.label.components(separatedBy: " (").first ?? p.pasto.label).lowercased()
        let sopra = p.proiezione.k - p.obiettivo.k
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars").font(.system(size: 15, weight: .bold)).foregroundStyle(Tema.inchiostro)
                    .frame(width: 34, height: 34).background(Tema.ambra, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("SISTEMA LA GIORNATA").font(.sport(19))
                    Text("Obiettivo \(fmtMigliaia(p.obiettivo.k)) kcal · \(Int(p.obiettivo.p)) g di proteine").font(.system(size: 12)).foregroundStyle(Tema.tenue)
                }
            }
            Text("Con il resto del piano arrivi a \(fmtMigliaia(p.proiezione.k)) kcal (\(sopra > 0 ? "+" : "−")\(fmtMigliaia(abs(sopra)))) e \(Int(p.proiezione.p)) g di proteine. "
                 + "Al posto di \(nomePasto)\(p.togli.isEmpty ? "" : " (e senza " + p.togli.map { ($0.label.components(separatedBy: " (").first ?? $0.label).lowercased() }.joined(separator: ", ") + ")"), "
                 + "circa \(Int(p.kcal)) kcal e \(Int(p.proteine)) g di proteine:")
                .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            ForEach(p.opzioni) { o in riga(o, nomePasto) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Tema.ambra.opacity(0.5), lineWidth: 1))
    }

    private func riga(_ o: OpzioneCena, _ nomePasto: String) -> some View {
        let t = o.tot
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(o.nome).font(.system(size: 15, weight: .bold))
                Spacer(minLength: 4)
                Text("\(Int(t.k))").font(.sport(22)).monospacedDigit() + Text(" kcal · P \(Int(t.p.rounded()))").font(.system(size: 12, weight: .semibold)).foregroundColor(Tema.tenue)
            }
            Text(o.voci.map { "\($0.nome.lowercased()) \(Int($0.g)) \(s.piano.unitaPeso($0.fonte ?? ""))" }.joined(separator: " · "))
                .font(.system(size: 12)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
            Menu {
                Section("Al posto di \(nomePasto), da mangiare") {
                    Button { s.usaProposta(o, p) } label: {
                        Label(p.togli.isEmpty ? "Sì, mettila" : "Sì, mettila e togli lo spuntino", systemImage: "checkmark.circle")
                    }
                }
            } label: {
                Label("Usa questa", systemImage: "fork.knife").font(.system(size: 14, weight: .bold)).foregroundStyle(Tema.fondo)
                    .padding(.horizontal, 14).frame(minHeight: 34).background(Tema.testo, in: Capsule())
            }
        }
        .padding(12)
        .background(Tema.scheda2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
