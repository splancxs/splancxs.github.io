import SwiftUI

// «Schede»: il blocco con le settimane, la scheda di oggi in argento (con gli esercizi in miniatura e «Inizia»),
// poi tutte le schede in righe compatte: si toccano per vedere gli esercizi.
struct SchedeLista: View {
    @EnvironmentObject var s: AppStore
    @State private var aperta: Routine?
    @State private var nuova = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            blocco
            oggi
            Titolo(testo: "Tutte le schede")
            VStack(spacing: 8) {
                ForEach(Array(s.routines.enumerated()), id: \.element.id) { i, r in riga(i, r) }
                Menu {
                    Section("Senza scheda: aggiungi tu gli esercizi") {
                        Button { s.avvia(nil) } label: { Label("Inizia vuoto", systemImage: "play.fill") }
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "play.fill").font(.system(size: 16, weight: .bold)).frame(width: 40)
                        Text("Allenamento libero").font(.system(size: 17, weight: .bold))
                        Spacer()
                    }
                    .foregroundStyle(Tema.testo)
                    .padding(14).background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                Button { nuova = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .bold)).frame(width: 40)
                        Text("Nuova scheda").font(.system(size: 17, weight: .bold))
                        Spacer()
                    }
                    .foregroundStyle(Tema.testo)
                    .padding(14).background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $aperta) { r in SchedaRoutineSheet(r: r).foglio() }
        .sheet(isPresented: $nuova) {
            EditorScheda(r: Routine(id: "U" + String(UUID().uuidString.prefix(6)), name: "", day: "Extra", focus: "", items: []), nuova: true).foglio()
        }
    }

    // il blocco di 7 settimane: una barra a segmenti, la settimana in corso in rosso
    private var blocco: some View {
        let b = s.blocco
        let nome = b.scarico ? "Scarico" : b.n <= 2 ? "Adattamento" : "Progressione"
        return Scheda {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(nome.uppercased()).font(.sport(26))
                    Spacer()
                    Text("Blocco \(b.ciclo) · settimana \(b.n) di 7").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.tenue)
                }
                HStack(spacing: 4) {
                    ForEach(1...7, id: \.self) { i in
                        Capsule().fill(i < b.n ? Tema.testo : i == b.n ? Tema.rosso : Tema.scheda2).frame(height: 6)
                    }
                }
                Text(b.fase.components(separatedBy: " · ").dropFirst().joined(separator: " · ")).font(.system(size: 13)).foregroundStyle(Tema.tenue)
            }
        }
    }

    // la scheda di oggi (o la prossima, nei giorni di riposo)
    @ViewBuilder private var oggi: some View {
        if let rid = s.schedaOggi, let r = s.routine(rid) {
            let fatta = s.fattoOggi(rid)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(fatta ? "Oggi · fatta ✓" : "Oggi · 16:30").font(.sport(17)).opacity(0.7)
                    Spacer()
                    Text(numero(r)).font(.sport(44)).opacity(0.45)
                }
                Text(r.name.uppercased()).font(.sport(46)).lineLimit(1).minimumScaleFactor(0.6).padding(.top, -14)
                Text("\(r.items.count) esercizi · \(r.focus)").font(.system(size: 15, weight: .medium))
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(r.items.enumerated()), id: \.offset) { _, it in MiniaturaEsercizio(ex: it.ex, lato: 54) }
                    }
                }
                .scrollIndicators(.hidden)
                HStack(spacing: 10) {
                    if !fatta {
                        MenuInizia(r: r) {
                            Text("Inizia").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 50).background(Tema.inchiostro, in: Capsule())
                        }
                    }
                    Button { aperta = r } label: {
                        Label("Esercizi", systemImage: "list.bullet").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.inchiostro)
                            .padding(.horizontal, 16).frame(maxWidth: fatta ? .infinity : nil, minHeight: 50)
                            .background(Tema.inchiostro.opacity(0.14), in: Capsule())
                    }
                }
            }
            .foregroundStyle(Tema.inchiostro)
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Argento())
        } else if let (giorno, r) = prossima {
            Scheda {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Oggi riposo · prossima \(giorno.lowercased())").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.tenue)
                    Text(r.name.uppercased()).font(.sport(36))
                    Text("\(r.items.count) esercizi · \(r.focus)").font(.system(size: 14)).foregroundStyle(Tema.tenue)
                    HStack(spacing: 10) {
                        Button { aperta = r } label: { Label("Esercizi", systemImage: "list.bullet") }.buttonStyle(PulsanteLeggero())
                        MenuInizia(r: r) {
                            Label("Inizia lo stesso", systemImage: "play.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo)
                                .padding(.horizontal, 14).frame(minHeight: 38).background(Tema.scheda2, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    // la prossima scheda della settimana dopo oggi
    private var prossima: (String, Routine)? {
        for d in 1...7 {
            let g = s.piano.week[(s.oggiIdx + d) % 7]
            if let rid = g.wo, let r = s.routine(rid) { return (g.name, r) }
        }
        return nil
    }

    private func numero(_ r: Routine) -> String { String(format: "%02d", (s.routines.firstIndex { $0.id == r.id } ?? 0) + 1) }

    private func riga(_ i: Int, _ r: Routine) -> some View {
        let diOggi = s.schedaOggi == r.id
        let muscoli = Array(Set(r.items.map { s.esercizio($0.ex).m })).sorted().joined(separator: " · ")
        return Button { aperta = r } label: {
            HStack(spacing: 14) {
                Text(String(format: "%02d", i + 1)).font(.sport(30)).foregroundStyle(diOggi ? Tema.rosso : Tema.spento).frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(r.name).font(.system(size: 18, weight: .bold)).foregroundStyle(Tema.testo)
                        if diOggi {
                            Text("OGGI").font(.sport(13)).foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 2).background(Tema.rosso, in: Capsule())
                        }
                    }
                    Text("\(r.day) · \(r.items.count) esercizi").font(.system(size: 13)).foregroundStyle(Tema.tenue)
                    Text(muscoli).font(.system(size: 12)).foregroundStyle(Tema.tenue).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Tema.tenue)
            }
            .padding(14).background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// una scheda aperta: esercizi con il manichino, serie, recupero; le superserie raggruppate col bordo ambra
struct SchedaRoutineSheet: View {
    @EnvironmentObject var s: AppStore
    @Environment(\.dismiss) private var chiudi
    let r0: Routine
    @State private var esercizio: IdEsercizio?
    @State private var modifica = false

    init(r: Routine) { r0 = r }
    private var r: Routine { s.routine(r0.id) ?? r0 }

    var body: some View {
        let serie = r.items.reduce(0) { $0 + $1.s }
        let minuti = r.items.reduce(0) { $0 + $1.s * (45 + max($1.rest, 0)) } / 60
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { modifica = true } label: {
                        Label("Modifica", systemImage: "pencil").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo)
                            .padding(.horizontal, 14).frame(minHeight: 34).background(Tema.scheda, in: Capsule())
                    }
                    Spacer()
                    Button { chiudi() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 34, height: 34).background(Tema.scheda, in: Circle()) }
                        .foregroundStyle(Tema.testo).accessibilityLabel("Chiudi")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text((r.day + (s.schedaModificata(r.id) ? " · modificata" : "")).uppercased()).font(.sport(17)).foregroundStyle(Tema.tenue)
                    Text(r.name.uppercased()).font(.sport(52)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(r.focus).font(.system(size: 15)).foregroundStyle(Tema.tenue)
                }
                HStack(spacing: 10) {
                    cifra("\(r.items.count)", "esercizi"); cifra("\(serie)", "serie"); cifra("~\(Int((Double(minuti) / 5).rounded()) * 5)′", "durata")
                }
                VStack(spacing: 8) {
                    ForEach(gruppi, id: \.self) { g in
                        if g.count == 2 {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("SUPERSERIE · senza recupero tra i due", systemImage: "link").font(.system(size: 12, weight: .heavy)).foregroundStyle(Tema.ambra)
                                    .padding(.leading, 4)
                                ForEach(g, id: \.self) { i in rigaEsercizio(r.items[i]) }
                            }
                            .padding(8)
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Tema.ambra.opacity(0.7), lineWidth: 1.5))
                        } else {
                            ForEach(g, id: \.self) { i in rigaEsercizio(r.items[i]) }
                        }
                    }
                }
                MenuInizia(r: r) {
                    Text("Inizia \(r.name)").font(.system(size: 17, weight: .bold)).foregroundStyle(Tema.fondo)
                        .frame(maxWidth: .infinity, minHeight: 52).background(Tema.testo, in: Capsule())
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .sheet(item: $esercizio) { x in EsercizioSheet(ex: x.id).foglio() }
        .sheet(isPresented: $modifica) { EditorScheda(r: r, nuova: false).foglio() }
        // scheda eliminata dall'editor: si chiude anche questa finestra (prima restava aperta su una scheda che non c'era più)
        .onChange(of: s.routine(r0.id) == nil) { _, sparita in if sparita { chiudi() } }
    }

    // indici degli esercizi: le coppie in superserie (attive) stanno insieme
    private var gruppi: [[Int]] {
        var out: [[Int]] = []
        var i = 0
        while i < r.items.count {
            let it = r.items[i]
            if it.sup.hasSuffix("a"), s.superserieAttiva(r.id, it.sup), i + 1 < r.items.count, r.items[i + 1].sup == String(it.sup.dropLast()) + "b" {
                out.append([i, i + 1]); i += 2
            } else {
                out.append([i]); i += 1
            }
        }
        return out
    }

    private func rigaEsercizio(_ it: RoutineItem) -> some View {
        let e = s.esercizio(it.ex)
        let sec = e.unit == "sec"
        return Button { esercizio = IdEsercizio(id: it.ex) } label: {
            HStack(spacing: 12) {
                MiniaturaEsercizio(ex: it.ex, lato: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text(e.n).font(.system(size: 16, weight: .bold)).foregroundStyle(Tema.testo).multilineTextAlignment(.leading)
                    Text("\(it.s) × \(it.lo)–\(it.hi)\(sec ? "″" : "")" + (it.rest > 0 ? " · rec.\u{00A0}\(tempoMMSS(it.rest))" : ""))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.tenue).monospacedDigit()
                    Text(e.m).font(.system(size: 12)).foregroundStyle(Tema.tenue)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Tema.tenue)
            }
            .padding(10).background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func cifra(_ v: String, _ u: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.sport(28)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(u).font(.system(size: 12)).foregroundStyle(Tema.tenue)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Tema.scheda, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
