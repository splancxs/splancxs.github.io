import SwiftUI

// Azioni dalla chat: quando serve, il coach aggiunge in fondo alla risposta un blocco ```azioni con un elenco JSON
// (pasto fuori piano, pasto del piano mangiato, creatina, pesata, cambio di piatto). L'app toglie il blocco dal testo e
// sotto la risposta mostra una scheda per azione con «Conferma» / «No»: niente cambia finché non tocchi tu.
// Vale per tutti i servizi (Gemini, Mistral, Claude): il protocollo è scritto nel messaggio di sistema (contestoCoach).

enum AzioneCoach: Hashable {
    case fuori(PastoFuori)          // si = nil: in più rispetto al piano
    case mangiato(Int)              // fascia
    case creatina
    case peso(Double, Double?)      // kg, vita in cm
    case scambio(Int, String)       // fascia, codice del piatto
}

enum AzioniCoach {
    // il testo da mostrare (senza il blocco) e il JSON del blocco, se c'è
    static func separa(_ testo: String) -> (testo: String, json: String?) {
        guard let inizio = testo.range(of: "```azioni") ?? bloccoJSON(testo) else { return (testo, nil) }
        let dopo = testo[inizio.upperBound...]
        let fine = dopo.range(of: "```")
        let json = String(fine.map { dopo[..<$0.lowerBound] } ?? dopo)
        let resto = String(testo[..<inizio.lowerBound]) + (fine.map { String(dopo[$0.upperBound...]) } ?? "")
        return (resto.trimmingCharacters(in: .whitespacesAndNewlines), json)
    }

    // qualche modello scrive ```json invece di ```azioni: va bene lo stesso, se dentro ci sono le azioni
    private static func bloccoJSON(_ testo: String) -> Range<String.Index>? {
        guard let r = testo.range(of: "```json") else { return nil }
        return testo[r.upperBound...].contains("\"tipo\"") ? r : nil
    }
}

extension AppStore {
    private func nomeFascia(_ m: MealPlan) -> String { m.label.components(separatedBy: " (").first ?? m.label }

    // dal JSON alle azioni: si tengono solo quelle sensate (fascia che c'è oggi, piatto che esiste, peso credibile…)
    func azioni(_ json: String) -> [AzioneCoach] {
        let pulito = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dati = pulito.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: dati) else { return [] }
        let lista: [[String: Any]] = (j as? [[String: Any]]) ?? ((j as? [String: Any]).map { ($0["azioni"] as? [[String: Any]]) ?? [$0] } ?? [])
        let plan = pianoOggi
        func num(_ v: Any?) -> Double? {
            if let n = v as? NSNumber { return n.doubleValue }
            return (v as? String).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        }
        func fascia(_ v: Any?) -> Int? { num(v).map { Int($0) }.flatMap { plan.meals.indices.contains($0) ? $0 : nil } }
        var out: [AzioneCoach] = []
        for a in lista.prefix(6) {
            var x: AzioneCoach?
            switch (a["tipo"] as? String)?.lowercased() {
            case "fuori":
                let fv = a["fascia"]
                let si = fascia(fv)
                if fv != nil, !(fv is NSNull), si == nil { continue }      // una fascia che oggi non c'è
                let voci = (a["voci"] as? [[String: Any]] ?? []).compactMap { v -> VoceCibo? in
                    guard let g = num(v["g"]), g > 0, g <= 3000 else { return nil }
                    // un cibo del database: valori veri del piano
                    if let fid = v["fid"] as? String, let c = piano.foods[fid] {
                        return VoceCibo(nome: piano.foodName(fid), g: g, k100: c.k, p100: c.p, c100: c.c, f100: c.f, fonte: fid)
                    }
                    // stimato dal coach: valori della porzione intera, riportati a 100 g (si possono correggere a mano)
                    guard let nome = (v["nome"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !nome.isEmpty,
                          let k = num(v["kcal"]), k >= 0, k * 100 / g <= 950 else { return nil }
                    let su = 100 / g
                    return VoceCibo(nome: nome, g: g, k100: k * su, p100: max(0, num(v["p"]) ?? 0) * su,
                                    c100: max(0, num(v["c"]) ?? 0) * su, f100: max(0, num(v["f"]) ?? 0) * su, fonte: "mano")
                }
                guard !voci.isEmpty else { continue }
                let nome = (a["nome"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                x = .fuori(PastoFuori(si: si, nome: nome.flatMap { $0.isEmpty ? nil : $0 } ?? voci.map(\.nome).joined(separator: ", "), voci: voci, t: 0))
            case "mangiato":
                guard let si = fascia(a["fascia"]), !plan.meals[si].free else { continue }
                x = .mangiato(si)
            case "creatina":
                x = .creatina
            case "peso":
                guard let kg = num(a["kg"]), (35...150).contains(kg) else { continue }
                x = .peso(kg, num(a["vita"]).flatMap { (40...150).contains($0) ? $0 : nil })
            case "scambio":
                guard let si = fascia(a["fascia"]), let codice = a["codice"] as? String, !plan.meals[si].free,
                      piano.variants[plan.meals[si].slot]?[codice] != nil else { continue }
                x = .scambio(si, codice)
            default:
                continue
            }
            if let x, !out.contains(x) { out.append(x) }
        }
        return out
    }

    // perché un'azione ora non si può fare (nil = si può)
    func motivoAzione(_ a: AzioneCoach) -> String? {
        let plan = pianoOggi
        switch a {
        case .fuori(let f):
            if let si = f.si, plan.meals[safe: si] == nil { return "Oggi questa fascia non c'è." }
            return nil
        case .mangiato(let si):
            guard plan.meals[safe: si] != nil else { return "Oggi questa fascia non c'è." }
            if fuoriPerFascia(si) != nil { return "Questo pasto è già segnato fuori piano." }
            return mangiati().contains(si) ? "Già segnato." : nil
        case .creatina:
            return creatinaPresa() ? "Già presa oggi." : nil
        case .peso(let kg, _):
            if let p = pesate.last, p.d == oggiKey, abs(p.kg - kg) < 0.01 { return "Già registrato." }
            return nil
        case .scambio(let si, let codice):
            guard let m = plan.meals[safe: si], piano.variants[m.slot]?[codice] != nil else { return "Non è più un'alternativa di oggi." }
            return m.code == codice ? "È già il piatto di oggi." : nil
        }
    }

    func applica(_ a: AzioneCoach) {
        switch a {
        case .fuori(var f):
            f.id = UUID().uuidString; f.t = Cal.ms()
            salvaFuori(f)
        case .mangiato(let si):
            segnaMangiato(si, true)
        case .creatina:
            if !creatinaPresa() { toccaCreatina() }
        case .peso(let kg, let vita):
            aggiungiPeso(giorno: oggiKey, kg: kg, vita: vita ?? pesate.last(where: { $0.d == oggiKey })?.w)
        case .scambio(let si, let codice):
            cambiaPiatto(di: oggiIdx, si: si, codice: codice)
        }
    }

    // titolo, riga sotto, icona e colore della scheda
    func descrivi(_ a: AzioneCoach) -> (titolo: String, sotto: String, icona: String, colore: Color) {
        let plan = pianoOggi
        switch a {
        case .fuori(let f):
            let t = f.tot
            let dove = f.si.flatMap { plan.meals[safe: $0] }.map { "Al posto di \(nomeFascia($0).lowercased())" } ?? "In più rispetto al piano"
            return ("Fuori piano: \(f.nome)", "\(dove) · \(Int(t.k)) kcal · P \(Int(t.p)) · C \(Int(t.c)) · G \(Int(t.fa))",
                    "takeoutbag.and.cup.and.straw.fill", Tema.ambra)
        case .mangiato(let si):
            guard let m = plan.meals[safe: si] else { return ("Segna un pasto", "", "checkmark.circle.fill", Tema.verde) }
            return ("Segna \(nomeFascia(m).lowercased()) come mangiato", "\(piano.recipe(m.code).name) · \(Int(m.tot.k)) kcal", "checkmark.circle.fill", Tema.verde)
        case .creatina:
            return ("Segna la creatina di oggi", serieCreatina() > 0 ? "Serie di \(serieCreatina()) giorni" : "Oggi", "pills.fill", Color(hex: 0x9B7BFF))
        case .peso(let kg, let vita):
            var sotto = vita.map { "Vita \(fmtNum($0)) cm" } ?? "Mattina a digiuno"
            if let p = pesate.last(where: { $0.d != oggiKey }) {
                let d = kg - p.kg
                sotto += " · \(d > 0 ? "+" : d < 0 ? "−" : "±")\(fmtPeso(abs(d))) dall'ultima"
            }
            return ("Pesata di oggi: \(fmtPeso(kg)) kg", sotto, "scalemass.fill", Tema.verde)
        case .scambio(let si, let codice):
            guard let m = plan.meals[safe: si] else { return ("Cambia piatto", "", "arrow.triangle.2.circlepath", Tema.g) }
            let nuovo = piano.sum(piano.mealLines(m.slot, codice))
            let d = Int(nuovo.k) - Int(m.tot.k)
            return ("\(nomeFascia(m)): \(piano.recipe(codice).name)", "Al posto di \(piano.recipe(m.code).name) · \(Int(nuovo.k)) kcal (\(d > 0 ? "+" : d < 0 ? "−" : "±")\(abs(d)))",
                    "arrow.triangle.2.circlepath", Tema.g)
        }
    }
}

// la scheda sotto la risposta del coach
struct SchedaAzione: View {
    enum Stato: Equatable { case daFare, fatta, scartata, bloccata(String) }
    @EnvironmentObject var s: AppStore
    let azione: AzioneCoach
    let stato: Stato
    let conferma: () -> Void
    let scarta: () -> Void

    var body: some View {
        let x = s.descrivi(azione)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: x.icona).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(x.colore, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(x.titolo).font(.system(size: 15, weight: .bold)).foregroundStyle(Tema.testo).fixedSize(horizontal: false, vertical: true)
                    if !x.sotto.isEmpty {
                        Text(x.sotto).font(.system(size: 13)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            if case .fuori(let f) = azione {
                VStack(spacing: 6) {
                    ForEach(f.voci) { v in
                        HStack {
                            Text(v.nome).font(.system(size: 14)).foregroundStyle(Tema.testo).lineLimit(1)
                            Spacer()
                            Text("\(Int(v.g)) g · \(Int(v.k)) kcal").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.tenue).monospacedDigit()
                        }
                    }
                }
                .padding(.leading, 46)
            }
            switch stato {
            case .daFare:
                HStack(spacing: 8) {
                    Button { conferma() } label: {
                        Label("Conferma", systemImage: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Tema.fondo)
                            .padding(.horizontal, 16).frame(minHeight: 38).background(Tema.testo, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button("No") { scarta() }.buttonStyle(PulsanteLeggero())
                    Spacer()
                }
                .padding(.leading, 46)
            case .fatta:
                Label("Fatto", systemImage: "checkmark.circle.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Tema.verde).padding(.leading, 46)
            case .scartata:
                Text("Lasciata stare").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.tenue).padding(.leading, 46)
            case .bloccata(let motivo):
                Text(motivo).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.tenue).padding(.leading, 46)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(stato == .daFare ? x.colore.opacity(0.5) : Tema.linea, lineWidth: 1))
        .opacity(stato == .daFare || stato == .fatta ? 1 : 0.7)
        .animation(.snappy, value: stato)
    }
}
