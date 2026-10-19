import SwiftUI

// «Progressi», a colpo d'occhio: il peso (media di 7 giorni) in argento con la barra verso l'obiettivo, il grafico,
// due riquadri con anello e numeri della settimana, il calendario delle ultime 4 settimane, i record in schede che scorrono
// e le pesate (le ultime tre, le altre su richiesta). Grafico e «Nuova misurazione» sono in ProgressiPeso.swift.
struct ProgressiView: View {
    @EnvironmentObject var s: AppStore
    @State private var nuovoPeso = false
    @State private var tutte = false
    @State private var periodo = 1   // 0 un mese · 1 tre mesi · 2 tutto
    @State private var giorno: String?        // giorno toccato nel calendario
    @State private var dettaglio: Workout?

    private let partenza = 64.70
    private let obiettivo = 62.5

    var body: some View {
        let ws = s.pesate
        let ultimo = ws.last
        let media7: Double? = {
            guard let u = ultimo else { return nil }
            let limite = Cal.date(u.d).addingTimeInterval(-7 * 86400)
            let v = ws.filter { Cal.date($0.d) > limite }
            return v.isEmpty ? nil : v.reduce(0) { $0 + $1.kg } / Double(v.count)
        }()
        Pagina {
            HStack(alignment: .firstTextBaseline) {
                Text("PROGRESSI").font(.sport(48))
                Spacer()
                Button { nuovoPeso = true } label: { Label("Peso", systemImage: "plus") }.buttonStyle(PulsanteLeggero())
            }
            eroe(ultimo, media7)
            grafico(ws)
            Button { s.mostraSettimana = true } label: { settimana }.buttonStyle(.plain)
            calendario
            record
            registro(ws)
        }
        .sheet(isPresented: $nuovoPeso) { NuovoPesoView().foglio() }
        .sheet(item: $dettaglio) { w in DettaglioAllenamento(w: w).foglio() }
        .sheet(isPresented: $s.mostraSettimana) { RiepilogoSettimanaView().foglio() }
    }

    // MARK: peso in argento, con la strada verso l'obiettivo

    @ViewBuilder private func eroe(_ ultimo: WeightEntry?, _ media7: Double?) -> some View {
        if let u = ultimo, let m = media7 {
            let d = m - partenza
            let fatto = min(1, max(0, (partenza - m) / (partenza - obiettivo)))
            let manca = max(0, m - obiettivo)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("PESO · MEDIA 7 GIORNI").font(.sport(17)).opacity(0.7)
                    Spacer()
                    Text("\(d > 0 ? "+" : d < 0 ? "−" : "±")\(fmtPeso(abs(d))) dal via")
                        .font(.system(size: 13, weight: .heavy)).lineLimit(1)
                        .foregroundStyle(Tema.inchiostro)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(d <= 0 ? AnyShapeStyle(Tema.verde) : AnyShapeStyle(Tema.ambra), in: Capsule())
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(fmtPeso(m)).font(.sport(76)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    Text("kg").font(.sport(28)).opacity(0.55)
                }
                .padding(.vertical, -8)
                Text("Ultima pesata \(fmtPeso(u.kg)) kg · \(Cal.testo(Cal.date(u.d), "d MMMM"))").font(.system(size: 14, weight: .medium)).opacity(0.75)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Tema.inchiostro.opacity(0.14))
                        Capsule().fill(Tema.inchiostro).frame(width: max(12, g.size.width * fatto))
                    }
                }
                .frame(height: 10)
                HStack {
                    Text("Via \(fmtPeso(partenza))").font(.system(size: 12, weight: .semibold)).opacity(0.6)
                    Spacer()
                    Text(manca > 0 ? "Mancano \(fmtPeso(manca)) kg a \(fmtNum(obiettivo))" : "Obiettivo raggiunto").font(.system(size: 13, weight: .heavy))
                }
            }
            .foregroundStyle(Tema.inchiostro)
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Argento())
        } else {
            Scheda {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PESO").font(.sport(22))
                    Text("Pesati al mattino, a digiuno: tocca «+ Peso».").font(.system(size: 14)).foregroundStyle(Tema.tenue)
                }
            }
        }
    }

    // MARK: grafico

    private func grafico(_ ws: [WeightEntry]) -> some View {
        let giorni = [31.0, 92, 100_000][periodo]
        let limite = Date().addingTimeInterval(-giorni * 86400)
        let scelte = ws.filter { Cal.date($0.d) >= limite }
        return Scheda {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("ANDAMENTO").font(.sport(22))
                    Spacer()
                    Picker("Periodo", selection: $periodo) { Text("1M").tag(0); Text("3M").tag(1); Text("Tutto").tag(2) }
                        .pickerStyle(.segmented).frame(width: 170)
                }
                if scelte.count < 2 {
                    Text(ws.count < 2 ? "Il grafico compare dalla seconda pesata." : "Poche pesate in questo periodo: prova «Tutto».")
                        .font(.system(size: 14)).foregroundStyle(Tema.tenue)
                } else {
                    GraficoPeso(pesate: scelte, obiettivo: obiettivo).frame(height: 200).id(periodo)
                    Text("Tocca il grafico per leggere un giorno.").font(.system(size: 12)).foregroundStyle(Tema.tenue)
                    HStack(spacing: 14) {
                        HStack(spacing: 6) { Capsule().fill(Tema.testo).frame(width: 16, height: 3); legenda("media 7 giorni") }
                        HStack(spacing: 6) { Circle().fill(Tema.tenue.opacity(0.6)).frame(width: 6, height: 6); legenda("pesate") }
                        HStack(spacing: 6) { Capsule().fill(Tema.verde).frame(width: 16, height: 2); legenda("obiettivo") }
                    }
                }
            }
        }
    }
    private func legenda(_ testo: String) -> some View { Text(testo).font(.system(size: 12)).foregroundStyle(Tema.tenue) }

    // MARK: la settimana in due riquadri

    private var lunedi: Date { Cal.lunedi() }
    private func allenamenti(_ da: Date, _ a: Date) -> [Workout] {
        s.cronologia.filter { $0.start >= da.timeIntervalSince1970 * 1000 && $0.start < a.timeIntervalSince1970 * 1000 }
    }

    private var settimana: some View {
        let questa = allenamenti(lunedi, Cal.giorni(7, da: lunedi))
        let scorsa = allenamenti(Cal.giorni(-7, da: lunedi), lunedi)
        let vol = questa.reduce(0) { $0 + $1.volume }, volPrima = scorsa.reduce(0) { $0 + $1.volume }
        let serie = questa.reduce(0) { $0 + $1.workSets }
        // i due riquadri hanno la stessa forma: titolo su una riga, numero grande, riga sotto (niente testo che va a capo)
        return HStack(spacing: 10) {
            Scheda(padding: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allenamenti").font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    HStack(alignment: .center) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(questa.count)").font(.sport(30)).monospacedDigit()
                            Text("/4").font(.sport(17)).foregroundStyle(Tema.tenue)
                        }
                        Spacer(minLength: 4)
                        Anello(valore: Double(questa.count), totale: 4, spessore: 6).frame(width: 34, height: 34)
                    }
                    Text("Scorsa: \(scorsa.count)/4").font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.tenue)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Scheda(padding: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Volume").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(fmtMigliaia(vol)).font(.sport(30)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                        Text("kg").font(.sport(17)).foregroundStyle(Tema.tenue)
                    }
                    Group {
                        if volPrima > 0 && vol > 0 {
                            let p = (vol - volPrima) / volPrima * 100
                            Text("\(p >= 0 ? "▲" : "▼") \(Int(abs(p).rounded()))% sulla scorsa").foregroundStyle(p >= 0 ? Tema.verde : Tema.tenue)
                        } else {
                            Text("\(serie) serie").foregroundStyle(Tema.tenue)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
    }

    // MARK: calendario delle ultime 4 settimane (da lunedì): pieno = allenamento fatto, puntino verde = pesata

    private var calendario: some View {
        let inizio = Cal.giorni(-21, da: lunedi)
        let fatti = Set(s.cronologia.map { Cal.key(Date(timeIntervalSince1970: $0.start / 1000)) })
        let pesati = Set(s.pesate.map(\.d))
        let oggi = Cal.key()
        let giorni: [String] = (0..<28).map { Cal.key(Cal.giorni($0, da: inizio)) }
        let quanti = giorni.filter { fatti.contains($0) }.count
        return Scheda {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("ULTIME 4 SETTIMANE").font(.sport(22))
                    Spacer()
                    Text("\(quanti) allenamenti").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.tenue)
                }
                HStack(spacing: 6) {
                    ForEach(Array(["L", "M", "M", "G", "V", "S", "D"].enumerated()), id: \.offset) { _, g in
                        Text(g).font(.system(size: 11, weight: .bold)).foregroundStyle(Tema.tenue).frame(maxWidth: .infinity)
                    }
                }
                VStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { w in
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { g in
                                casella(giorni[w * 7 + g], fatti: fatti, pesati: pesati, oggi: oggi)
                            }
                        }
                    }
                }
                HStack(spacing: 14) {
                    HStack(spacing: 6) { RoundedRectangle(cornerRadius: 3).fill(Tema.testo).frame(width: 12, height: 12); legenda("allenamento") }
                    HStack(spacing: 6) { Circle().fill(Tema.verde).frame(width: 6, height: 6); legenda("pesata") }
                    HStack(spacing: 6) { RoundedRectangle(cornerRadius: 3).stroke(Tema.rosso, lineWidth: 2).frame(width: 12, height: 12); legenda("oggi") }
                }
                if let g = giorno { giornoScelto(g) } else {
                    Text("Tocca un giorno per vedere cosa hai fatto.").font(.system(size: 12)).foregroundStyle(Tema.tenue)
                }
            }
        }
    }

    private func casella(_ g: String, fatti: Set<String>, pesati: Set<String>, oggi: String) -> some View {
        let fatto = fatti.contains(g)
        let futuro = g > oggi
        let scelto = giorno == g
        return Button {
            withAnimation(.snappy(duration: 0.2)) { giorno = scelto ? nil : g }
        } label: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(fatto ? Tema.testo : Tema.scheda2.opacity(futuro ? 0.4 : 1))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if pesati.contains(g) { Circle().fill(fatto ? Tema.fondo : Tema.verde).frame(width: 6, height: 6) }
                }
                .overlay {
                    if scelto {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Tema.ambra, lineWidth: 3)
                    } else if g == oggi {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Tema.rosso, lineWidth: 2)
                    }
                }
                .scaleEffect(scelto ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .disabled(futuro)
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: scelto)
    }

    // cosa è successo il giorno toccato: allenamenti (si aprono) e pesata
    @ViewBuilder private func giornoScelto(_ g: String) -> some View {
        let lista = s.cronologia.filter { Cal.key(Date(timeIntervalSince1970: $0.start / 1000)) == g }
        let pesata = s.pesate.first { $0.d == g }
        VStack(alignment: .leading, spacing: 8) {
            Text(maiuscolaIniziale(Cal.testo(Cal.date(g), "EEEE d MMMM"))).font(.system(size: 16, weight: .bold))
            ForEach(lista) { w in
                Button { dettaglio = w } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "dumbbell.fill").font(.system(size: 15, weight: .semibold)).frame(width: 34, height: 34)
                            .foregroundStyle(Tema.inchiostro).background(Tema.testo, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(w.name).font(.system(size: 16, weight: .bold)).foregroundStyle(Tema.testo)
                            Text("\(w.minutes)′ · \(w.workSets) serie · \(fmtMigliaia(w.volume)) kg\(w.prs.isEmpty ? "" : " · 🏆 \(w.prs.count)")")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(Tema.tenue).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Tema.tenue)
                    }
                    .padding(10).background(Tema.scheda2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if let p = pesata {
                HStack(spacing: 12) {
                    Image(systemName: "scalemass.fill").font(.system(size: 15, weight: .semibold)).frame(width: 34, height: 34)
                        .foregroundStyle(Tema.inchiostro).background(Tema.verde, in: Circle())
                    Text("Peso \(fmtPeso(p.kg)) kg" + (p.w.map { " · vita \(fmtNum($0)) cm" } ?? "")).font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .padding(10).background(Tema.scheda2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if lista.isEmpty && pesata == nil {
                Text("Riposo: nessun allenamento e nessuna pesata.").font(.system(size: 13)).foregroundStyle(Tema.tenue)
            }
        }
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: ultimi record, in schede che scorrono

    @ViewBuilder private var record: some View {
        let ultimi = ultimiRecord()
        if !ultimi.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Titolo(testo: "Ultimi record")
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(ultimi.enumerated()), id: \.offset) { _, x in
                            VStack(alignment: .leading, spacing: 8) {
                                MiniaturaEsercizio(ex: x.0.ex, lato: 46)
                                Text(s.nomeBreve(x.0.ex)).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                                    .frame(height: 36, alignment: .topLeading)
                                Text(valore(x.0)).font(.sport(26)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                                Text("\(x.0.k) · \(Cal.testo(x.1, "d MMM"))").font(.system(size: 11)).foregroundStyle(Tema.tenue).lineLimit(1)
                            }
                            .padding(14).frame(width: 150, alignment: .leading)
                            .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
    private func ultimiRecord() -> [(RecordPR, Date)] {
        var out: [(RecordPR, Date)] = []
        for w in s.cronologia {
            for p in w.prs where out.count < 8 { out.append((p, Date(timeIntervalSince1970: w.start / 1000))) }
            if out.count >= 8 { break }
        }
        return out
    }
    // come in ElencoRecord: i kg degli esercizi in libbre si leggono in lb
    private func valore(_ p: RecordPR) -> String {
        guard s.inLibbre(p.ex), p.v.hasSuffix(" kg"),
              let n = Double(p.v.dropLast(3).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")) else { return p.v }
        return "\(fmtNum(lbFrom(kg: n))) lb"
    }

    // MARK: registro

    private func registro(_ ws: [WeightEntry]) -> some View {
        Scheda {
            VStack(alignment: .leading, spacing: 8) {
                Text("REGISTRO").font(.sport(22))
                if ws.isEmpty { Text("Le misure che salvi compaiono qui.").foregroundStyle(Tema.tenue).font(.system(size: 14)) }
                ForEach(ws.reversed().prefix(tutte ? 60 : 3)) { w in
                    HStack {
                        Text(Cal.testo(Cal.date(w.d), "d MMM")).font(.system(size: 14)).foregroundStyle(Tema.tenue).frame(width: 56, alignment: .leading)
                        Text("\(fmtPeso(w.kg)) kg").font(.system(size: 17, weight: .heavy)).monospacedDigit()
                        if let v = w.w { Text("· vita \(fmtNum(v)) cm").font(.system(size: 13)).foregroundStyle(Tema.tenue) }
                        Spacer()
                        Menu {
                            Button(role: .destructive) { s.eliminaPeso(w.d) } label: { Label("Elimina \(fmtPeso(w.kg)) kg", systemImage: "trash") }
                        } label: { Image(systemName: "trash").font(.system(size: 14)).frame(width: 34, height: 34) }
                        .foregroundStyle(Tema.tenue)
                    }
                }
                if ws.count > 3 {
                    Button(tutte ? "Mostra meno" : "Mostra di più (\(min(ws.count, 60) - 3))") { tutte.toggle() }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.tenue)
                }
            }
        }
    }
}
