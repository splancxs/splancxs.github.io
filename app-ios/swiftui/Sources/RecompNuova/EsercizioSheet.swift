import SwiftUI

struct IdEsercizio: Identifiable, Hashable { let id: String }

// Scheda dell'esercizio, come in Lift: esecuzione animata (manichino 3D), muscoli, istruzioni a passi, progressi nel tempo.
struct EsercizioSheet: View {
    @EnvironmentObject var s: AppStore
    @Environment(\.dismiss) private var chiudi
    let ex: String
    @State private var metrica = 0     // 0 1RM · 1 carico · 2 volume · 3 ripetizioni
    @State private var periodo = 1     // 0 1 mese · 1 3 mesi · 2 6 mesi · 3 1 anno · 4 tutto

    var body: some View {
        let e = s.esercizio(ex)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    Button { chiudi() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 34, height: 34).background(Tema.scheda, in: Circle()) }
                        .foregroundStyle(Tema.testo).accessibilityLabel("Chiudi")
                }
                EsecuzioneAnimata(ex: ex)
                Text(e.n).font(.system(size: 30, weight: .heavy)).fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 7) {
                    if !e.eq.isEmpty { etichetta("dumbbell", e.eq, false) }
                    etichetta("scope", e.m, true)
                    ForEach(e.sec, id: \.self) { m in etichetta("circle.dashed", m, false) }
                }

                let passi = istruzioni(e.cue)
                if !passi.isEmpty {
                    Titolo(testo: "Istruzioni")
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(passi.enumerated()), id: \.offset) { n, p in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(n + 1)").font(.sport(18)).frame(width: 30, height: 30).background(Tema.scheda2, in: Circle())
                                Text(p).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                            }
                        }
                    }
                }

                progressi(e)

                if Movimenti.tutti[ex]?.yt != nil {
                    Text("Video da YouTube (soprattutto Renaissance Periodization).").font(.system(size: 11)).foregroundStyle(Tema.tenue)
                }
            }
            .padding(20)
        }
        .background(Tema.fondo.ignoresSafeArea())
    }

    private func etichetta(_ icona: String, _ testo: String, _ principale: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icona).font(.system(size: 12, weight: .semibold))
            Text(testo).font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(principale ? Tema.inchiostro : Tema.testo)
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(principale ? AnyShapeStyle(Color(hex: 0xC4C6C5)) : AnyShapeStyle(Tema.scheda), in: Capsule())
    }

    // la tecnica scritta in frasi → passi numerati
    private func istruzioni(_ cue: String) -> [String] {
        cue.replacingOccurrences(of: ". ", with: ".\n").split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // MARK: progressi nel tempo

    private struct Punto { let data: Date; let valore: Double; let serie: [SetRec] }

    private func punti(_ e: ExLib) -> [Punto] {
        let sec = e.unit == "sec"
        let giorni = [31.0, 92, 183, 366, 100_000][periodo]
        let limite = Date().addingTimeInterval(-giorni * 86400)
        return s.cronologia.reversed().compactMap { w -> Punto? in
            let data = Date(timeIntervalSince1970: w.start / 1000)
            guard data >= limite, let it = w.items.first(where: { $0.ex == ex }) else { return nil }
            let work = it.sets.filter(\.isWork)
            guard !work.isEmpty else { return nil }
            let v: Double
            switch sec ? 3 : metrica {
            case 0: v = work.map { e1rm($0.kg ?? 0, $0.r ?? 0) }.max() ?? 0
            case 1: v = work.map { $0.kg ?? 0 }.max() ?? 0
            case 2: v = volOf(work)
            default: v = Double(work.map { $0.r ?? 0 }.max() ?? 0)
            }
            return v > 0 ? Punto(data: data, valore: v, serie: work) : nil
        }
    }

    // i kg nell'unità dell'esercizio (lb se è un macchinario in libbre)
    private func peso(_ kg: Double) -> Double { s.inLibbre(ex) ? lbFrom(kg: kg) : kg }

    @ViewBuilder private func progressi(_ e: ExLib) -> some View {
        let sec = e.unit == "sec"
        let r = s.primati(ex)
        let lista = punti(e)
        let unita = sec ? "″" : metrica == 3 ? " rip." : " " + s.unita(ex)
        Titolo(testo: "Progressi")
        if sec {
            cifra("Tempo massimo", "\(r.sec)″")
        } else {
            HStack(spacing: 8) {
                cifra("Carico max", s.pesoConUnita(ex, r.kg))
                cifra("1RM stimato", s.pesoConUnita(ex, r1(r.e1)))
                cifra("Rip. max", "\(r.reps)")
            }
        }
        Picker("Periodo", selection: $periodo) { Text("1M").tag(0); Text("3M").tag(1); Text("6M").tag(2); Text("1A").tag(3); Text("Tutto").tag(4) }
            .pickerStyle(.segmented)
        if !sec {
            Picker("Misura", selection: $metrica) { Text("1RM").tag(0); Text("Carico").tag(1); Text("Volume").tag(2); Text("Rip.").tag(3) }
                .pickerStyle(.segmented)
        }
        Scheda {
            VStack(alignment: .leading, spacing: 10) {
                if let ultimo = lista.last, let primo = lista.first {
                    let v = metrica == 3 || sec ? ultimo.valore : peso(ultimo.valore)
                    let v0 = metrica == 3 || sec ? primo.valore : peso(primo.valore)
                    let diff = v0 > 0 ? (v - v0) / v0 * 100 : 0
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(fmtNum(r1(v)) + unita).font(.system(size: 30, weight: .heavy)).monospacedDigit()
                        if lista.count > 1 {
                            Text("\(diff >= 0 ? "▲" : "▼") \(fmtNum(abs(r1(diff))))%").font(.system(size: 14, weight: .bold))
                                .foregroundStyle(diff >= 0 ? Tema.verde : Tema.rosso)
                        }
                    }
                    if lista.count > 1 {
                        GraficoLinea(valori: lista.map { ($0.data, metrica == 3 || sec ? $0.valore : peso($0.valore)) }).frame(height: 170)
                    } else {
                        Text("Il grafico compare dalla seconda seduta.").font(.system(size: 14)).foregroundStyle(Tema.tenue)
                    }
                } else {
                    Text("Nessuna seduta in questo periodo.").font(.system(size: 14)).foregroundStyle(Tema.tenue)
                }
            }
        }
        if !lista.isEmpty {
            Titolo(testo: "Sedute")
            VStack(spacing: 0) {
                ForEach(Array(lista.reversed().prefix(10).enumerated()), id: \.offset) { _, p in
                    HStack(alignment: .firstTextBaseline) {
                        Text(maiuscolaIniziale(Cal.testo(p.data, "EEE d MMM"))).font(.system(size: 13)).foregroundStyle(Tema.tenue).frame(width: 82, alignment: .leading)
                        Text(p.serie.map { sec ? "\($0.r ?? 0)″" : "\(s.peso(ex, $0.kg))×\($0.r ?? 0)" }.joined(separator: " · "))
                            .font(.system(size: 14, weight: .semibold)).monospacedDigit().lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                    Divider().overlay(Tema.linea)
                }
            }
        }
    }

    private func cifra(_ nome: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(nome).font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.tenue).lineLimit(1)
            Text(v).font(.sport(24)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// grafico a linea semplice: punti collegati, minimo e massimo a sinistra, prima e ultima data in basso
struct GraficoLinea: View {
    let valori: [(Date, Double)]
    var body: some View {
        GeometryReader { g in
            let t0 = valori.first!.0.timeIntervalSince1970, t1 = max(valori.last!.0.timeIntervalSince1970, t0 + 1)
            let lo = (valori.map(\.1).min() ?? 0), hi = max(valori.map(\.1).max() ?? 1, lo + 1)
            let x: (Date) -> CGFloat = { CGFloat(($0.timeIntervalSince1970 - t0) / (t1 - t0)) * (g.size.width - 44) + 40 }
            let y: (Double) -> CGFloat = { CGFloat(1 - ($0 - lo) / (hi - lo)) * (g.size.height - 30) + 8 }
            ZStack(alignment: .topLeading) {
                ForEach([lo, hi], id: \.self) { v in
                    Path { p in p.move(to: CGPoint(x: 40, y: y(v))); p.addLine(to: CGPoint(x: g.size.width, y: y(v))) }.stroke(Tema.linea, lineWidth: 1)
                    Text(fmtNum(r1(v))).font(.system(size: 10)).foregroundStyle(Tema.tenue).position(x: 18, y: y(v))
                }
                Path { p in
                    for (i, v) in valori.enumerated() {
                        let pt = CGPoint(x: x(v.0), y: y(v.1))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(Tema.testo, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                ForEach(Array(valori.enumerated()), id: \.offset) { _, v in
                    Circle().fill(Tema.testo).frame(width: 6, height: 6).position(x: x(v.0), y: y(v.1))
                }
                Text(Cal.testo(valori.first!.0, "d MMM")).font(.system(size: 10)).foregroundStyle(Tema.tenue).position(x: 56, y: g.size.height - 6)
                Text(Cal.testo(valori.last!.0, "d MMM")).font(.system(size: 10)).foregroundStyle(Tema.tenue).position(x: g.size.width - 22, y: g.size.height - 6)
            }
        }
    }
}
