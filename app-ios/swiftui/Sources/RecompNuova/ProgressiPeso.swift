import SwiftUI

// grafico del peso: linea spessa = media di 7 giorni (con l'ombra sotto), puntini = pesate, tratteggio verde = obiettivo.
// Le cifre stanno a destra, fuori dalle linee, così non si sovrappongono. Si tocca (o si scorre col dito) per leggere
// data, pesata e media di quel giorno.
struct GraficoPeso: View {
    let pesate: [WeightEntry]
    let obiettivo: Double
    @State private var scelto: Int?

    var body: some View {
        GeometryReader { g in
            let destra = 40.0, basso = 20.0
            let w = Double(g.size.width) - destra, h = Double(g.size.height) - basso
            let giorni = pesate.map { Cal.date($0.d).timeIntervalSince1970 }
            let t0 = giorni.first ?? 0, t1 = max(giorni.last ?? 1, t0 + 86400)
            let valori = pesate.map(\.kg) + [obiettivo]
            let lo = (valori.min() ?? 60) - 0.3, hi = (valori.max() ?? 70) + 0.3
            let x: (Double) -> Double = { ($0 - t0) / (t1 - t0) * (w - 8) + 4 }
            let y: (Double) -> Double = { (1 - ($0 - lo) / (hi - lo)) * (h - 8) + 4 }
            let medie = medieMobili()
            let media = zip(giorni, medie).map { CGPoint(x: x($0.0), y: y($0.1)) }
            // il punto più vicino al dito
            let vicino: (Double) -> Int? = { lx in giorni.indices.min { abs(x(giorni[$0]) - lx) < abs(x(giorni[$1]) - lx) } }
            ZStack(alignment: .topLeading) {
                ForEach([0.15, 0.5, 0.85], id: \.self) { f in
                    let v = lo + (hi - lo) * f
                    Path { p in p.move(to: CGPoint(x: 0, y: y(v))); p.addLine(to: CGPoint(x: w, y: y(v))) }.stroke(Tema.linea, lineWidth: 1)
                    Text(fmtNum((v * 10).rounded() / 10)).font(.system(size: 10, weight: .medium)).foregroundStyle(Tema.tenue)
                        .position(x: w + destra / 2 + 2, y: y(v))
                }
                Path { p in p.move(to: CGPoint(x: 0, y: y(obiettivo))); p.addLine(to: CGPoint(x: w, y: y(obiettivo))) }
                    .stroke(Tema.verde, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                ombra(media, h).fill(LinearGradient(colors: [Tema.testo.opacity(0.18), Tema.testo.opacity(0)], startPoint: .top, endPoint: .bottom))
                ForEach(Array(pesate.enumerated()), id: \.offset) { _, p in
                    Circle().fill(Tema.tenue.opacity(0.6)).frame(width: 5, height: 5).position(x: x(Cal.date(p.d).timeIntervalSince1970), y: y(p.kg))
                }
                linea(media).stroke(Tema.testo, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if let i = scelto, i < pesate.count {
                    // il giorno toccato: linea verticale, pesata (ambra), media (bianco) e il cartellino in alto
                    let px = x(giorni[i])
                    Path { p in p.move(to: CGPoint(x: px, y: 0)); p.addLine(to: CGPoint(x: px, y: h)) }
                        .stroke(Tema.tenue, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Circle().fill(Tema.ambra).frame(width: 9, height: 9).position(x: px, y: y(pesate[i].kg))
                    Circle().fill(Tema.testo).frame(width: 11, height: 11).overlay(Circle().stroke(Tema.scheda, lineWidth: 2)).position(media[i])
                    VStack(alignment: .leading, spacing: 1) {
                        Text(maiuscolaIniziale(Cal.testo(Cal.date(pesate[i].d), "EEE d MMM"))).font(.system(size: 11, weight: .semibold)).foregroundStyle(Tema.tenue)
                        Text("\(fmtPeso(pesate[i].kg)) kg").font(.system(size: 15, weight: .heavy)).monospacedDigit()
                        Text("media \(fmtPeso(medie[i]))").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tema.tenue).monospacedDigit()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Tema.scheda2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .fixedSize()
                    .position(x: min(max(px, 52), w - 52), y: 28)
                } else if let u = media.last {
                    Circle().fill(Tema.testo).frame(width: 10, height: 10).overlay(Circle().stroke(Tema.scheda, lineWidth: 2)).position(u)
                }
                HStack {
                    Text(Cal.testo(Cal.date(pesate.first?.d ?? Cal.key()), "d MMM"))
                    Spacer()
                    Text(Cal.testo(Cal.date(pesate.last?.d ?? Cal.key()), "d MMM"))
                }
                .font(.system(size: 11)).foregroundStyle(Tema.tenue)
                .frame(width: w).position(x: w / 2, y: h + basso / 2 + 2)
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { v in
                let i = vicino(Double(v.location.x))
                scelto = (i == scelto) ? nil : i
            })
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { v in scelto = vicino(Double(v.location.x)) })
            .sensoryFeedback(.selection, trigger: scelto)
        }
    }

    // media mobile di 7 giorni per ogni pesata
    private func medieMobili() -> [Double] {
        pesate.map { p in
            let t = Cal.date(p.d).timeIntervalSince1970
            let v = pesate.filter { let u = Cal.date($0.d).timeIntervalSince1970; return u <= t && u > t - 7 * 86400 }
            return v.reduce(0) { $0 + $1.kg } / Double(max(1, v.count))
        }
    }
    private func linea(_ m: [CGPoint]) -> Path {
        Path { p in for (i, q) in m.enumerated() { if i == 0 { p.move(to: q) } else { p.addLine(to: q) } } }
    }
    private func ombra(_ m: [CGPoint], _ h: Double) -> Path {
        Path { p in
            guard let primo = m.first, let ultimo = m.last else { return }
            p.move(to: CGPoint(x: primo.x, y: h)); p.addLine(to: primo)
            for q in m.dropFirst() { p.addLine(to: q) }
            p.addLine(to: CGPoint(x: ultimo.x, y: h)); p.closeSubpath()
        }
    }
}

struct NuovoPesoView: View {
    @EnvironmentObject var s: AppStore
    @Environment(\.dismiss) private var chiudi
    @State private var giorno = Date()
    @State private var peso = ""
    @State private var vita = ""
    @State private var errore = ""

    var body: some View {
        VStack(spacing: 0) {
            TestataFoglio(titolo: "Nuova pesata", sotto: "Mattina, a digiuno, dopo il bagno", chiudi: { chiudi() })
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        numero("Peso", "kg", s.pesate.last.map { fmtPeso($0.kg) } ?? "64,70", $peso, grande: true)
                        numero("Vita · facoltativa", "cm", "78,5", $vita, grande: false)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "calendar").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.tenue)
                        Text("Giorno").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        DatePicker("Giorno", selection: $giorno, in: ...Date(), displayedComponents: .date)
                            .labelsHidden().environment(\.locale, Locale(identifier: "it_IT"))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if !errore.isEmpty { Text(errore).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.rosso) }
                    Text("La vita si misura all'altezza dell'ombelico, ogni lunedì.").font(.system(size: 12)).foregroundStyle(Tema.tenue)
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .pulsanteInFondo("Salva la pesata", attivo: !peso.trimmingCharacters(in: .whitespaces).isEmpty) { salva() }
        }
        .background(Tema.fondo.ignoresSafeArea())
    }

    private func numero(_ titolo: String, _ unita: String, _ esempio: String, _ v: Binding<String>, grande: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titolo).font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.tenue).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField(esempio, text: v).keyboardType(.decimalPad).font(.sport(grande ? 44 : 34)).monospacedDigit()
                Text(unita).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.tenue)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func salva() {
        guard let kg = Double(peso.replacingOccurrences(of: ",", with: ".")), kg >= 35, kg <= 150 else { errore = "Scrivi un peso valido in kg (es. 64,7)."; return }
        var v: Double?
        if !vita.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let x = Double(vita.replacingOccurrences(of: ",", with: ".")), x >= 40, x <= 150 else { errore = "La vita va in centimetri (es. 78,5) oppure lasciala vuota."; return }
            v = x
        }
        s.aggiungiPeso(giorno: Cal.key(giorno), kg: kg, vita: v)
        chiudi()
    }
}
