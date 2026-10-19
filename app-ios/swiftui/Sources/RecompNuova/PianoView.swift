import SwiftUI

// «Piano»: i giorni in pillole (kcal e icona: palestra, riposo, pasto libero), il giorno scelto con i totali in un riquadro,
// i pasti compatti (un cibo per riga: icona, nome, grammi), la lista della spesa, le sostituzioni.
struct PianoView: View {
    @EnvironmentObject var s: AppStore
    @State private var giorno = Cal.dayIdx()
    @State private var sezione = 0
    @State private var pasto: MealPlan?

    var body: some View {
        Pagina {
            Text("PIANO").font(.sport(48))
            Picker("Sezione", selection: $sezione) {
                Text("Settimana").tag(0); Text("Spesa").tag(1); Text("Sostituzioni").tag(2)
            }
            .pickerStyle(.segmented)
            switch sezione {
            case 1: SpesaView()
            case 2: SostituzioniView()
            default: settimana
            }
        }
        .sheet(item: $pasto) { m in PastoSheet(di: giorno, si: m.si, oggi: false).foglio() }
    }

    private var settimana: some View {
        let piani = (0..<7).map { s.pianoGiorno($0) }
        let media = piani.reduce(0) { $0 + $1.previsti.k } / 7
        let plan = piani[giorno]
        let scambiato = s.d.swaps.keys.contains { $0.hasPrefix("\(giorno):") }
        return VStack(alignment: .leading, spacing: 14) {
            // i giorni: pillole con kcal e icona; quella scelta in argento, oggi col puntino rosso
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { i in pillola(i, piani[i]) }
            }
            // il giorno scelto
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.day.name.uppercased()).font(.sport(38))
                    Text(etichettaGiorno(plan)).font(.system(size: 13, weight: .medium)).foregroundStyle(Tema.tenue).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                if scambiato {
                    Menu {
                        Section("Hai cambiato dei piatti") {
                            Button { s.ripristinaGiorno(giorno) } label: { Label("Rimetti gli originali", systemImage: "arrow.uturn.backward") }
                        }
                    } label: {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 15, weight: .bold)).foregroundStyle(Tema.ambra)
                            .frame(width: 40, height: 40).background(Tema.scheda, in: Circle())
                    }
                    .accessibilityLabel("Ripristina i piatti originali")
                }
            }
            totali(plan)
            if plan.hasFree {
                Text("Il totale comprende il pasto libero, stimato in circa \(Int(stimaPastoLibero)) kcal.")
                    .font(.system(size: 12)).foregroundStyle(Tema.tenue)
            }
            ForEach(plan.meals) { m in CartaPasto(m: m) { pasto = m } }
            Text("Media della settimana \(fmtMigliaia(media)) kcal (con il pasto libero stimato).").font(.system(size: 12)).foregroundStyle(Tema.tenue)
        }
    }

    private func pillola(_ i: Int, _ p: DayPlan) -> some View {
        let scelto = giorno == i
        let icona = p.hasFree ? "fork.knife" : p.day.type == "ON" ? "dumbbell.fill" : "moon.fill"
        return Button { giorno = i; Haptic.leggero() } label: {
            VStack(spacing: 5) {
                Text(giorni3[i]).font(.sport(16))
                Image(systemName: icona).font(.system(size: 11, weight: .bold)).opacity(scelto ? 0.8 : 0.6)
                Text("\(Int(p.previsti.k))").font(.system(size: 11, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).opacity(0.8)
                Circle().fill(i == s.oggiIdx ? Tema.rosso : .clear).frame(width: 5, height: 5)
            }
            .foregroundStyle(scelto ? Tema.inchiostro : Tema.testo)
            .padding(.top, 10).padding(.bottom, 6).frame(maxWidth: .infinity)
            .background {
                if scelto { Argento(raggio: 16) } else { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Tema.scheda) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(p.day.name), \(Int(p.previsti.k)) kcal")
    }

    private func etichettaGiorno(_ plan: DayPlan) -> String {
        let tipo = plan.day.type == "ON" ? "ON" : plan.day.type == "FREE" ? "OFF · pasto libero" : "OFF"
        let scuola = plan.day.type == "ON" || plan.day.type == "OFF_S" ? " · scuola" : ""
        let palestra = plan.day.wo.flatMap { s.routine($0) }.map { " · \($0.name) alle 16:30" } ?? ""
        return tipo + scuola + palestra
    }

    // i totali del giorno in un riquadro: kcal in grande, i tre macro con una barretta verso l'obiettivo
    private func totali(_ plan: DayPlan) -> some View {
        let t = plan.previsti
        return Scheda(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(fmtMigliaia(r0(t.k))).font(.sport(40)).monospacedDigit()
                    Text("/ \(fmtMigliaia(plan.dt.target[0])) kcal").font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.tenue)
                    Spacer()
                }
                HStack(spacing: 12) {
                    macro("Proteine", t.p, plan.dt.target[1], Tema.p)
                    macro("Carbo", t.c, plan.dt.target[2], Tema.c)
                    macro("Grassi", t.fa, plan.dt.target[3], Tema.g)
                }
            }
        }
    }

    private func macro(_ nome: String, _ v: Double, _ obiettivo: Double, _ colore: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(nome).font(.system(size: 11, weight: .semibold)).foregroundStyle(Tema.tenue).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(r0(v)))").font(.sport(22)).monospacedDigit()
                Text("/\(Int(obiettivo)) g").font(.system(size: 11)).foregroundStyle(Tema.tenue).lineLimit(1).minimumScaleFactor(0.7)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tema.scheda2)
                    Capsule().fill(colore).frame(width: g.size.width * min(1, v / max(1, obiettivo)))
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// un pasto nel Piano, compatto: intestazione con ora e kcal, il piatto, un cibo per riga (icona, nome, aiuto, grammi),
// i macro in una riga. Si tocca tutto il riquadro per i dettagli e lo scambio.
struct CartaPasto: View {
    @EnvironmentObject var s: AppStore
    let m: MealPlan
    var apri: () -> Void

    var body: some View {
        if m.free {
            Scheda(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(m.time) · PASTO LIBERO").font(.sport(17)).foregroundStyle(Tema.tenue)
                    Text("Fuori, senza pesare").font(.system(size: 16, weight: .bold))
                    Text("Un primo o un secondo con contorno, oppure una pizza; acqua o bibita zero. Circa \(Int(stimaPastoLibero)) kcal, già nel totale del giorno.")
                        .font(.system(size: 12)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Button(action: apri) {
                Scheda(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(m.time) · \((m.label.components(separatedBy: " (").first ?? m.label).uppercased())").font(.sport(17)).foregroundStyle(Tema.tenue).lineLimit(1)
                            if m.code != m.def { Image(systemName: "arrow.left.arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Tema.ambra) }
                            Spacer(minLength: 4)
                            Text("\(Int(m.tot.k))").font(.sport(24)).monospacedDigit() + Text(" kcal").font(.system(size: 12)).foregroundColor(Tema.tenue)
                        }
                        Text(s.piano.recipe(m.code).name).font(.system(size: 16, weight: .bold)).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 6) {
                            ForEach(Array(m.lines.enumerated()), id: \.offset) { _, l in
                                let aiuto = s.piano.aiuto(l.f, l.g)
                                HStack(spacing: 8) {
                                    Text(s.piano.icona(l.f)).font(.system(size: 15)).frame(width: 22)
                                    (Text(s.piano.foodName(l.f)).foregroundColor(Tema.testo)
                                        + Text(aiuto.isEmpty ? "" : "  \(aiuto)").foregroundColor(Tema.tenue))
                                        .font(.system(size: 14)).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text("\(Int(l.g)) \(s.piano.unitaPeso(l.f))").font(.system(size: 15, weight: .heavy)).monospacedDigit()
                                }
                            }
                        }
                        HStack(spacing: 12) {
                            puntino(Tema.p, "P", m.tot.p); puntino(Tema.c, "C", m.tot.c); puntino(Tema.g, "G", m.tot.fa)
                            Spacer()
                            Text("Dettagli e scambio").font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.tenue)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Tema.tenue)
                        }
                        .padding(.top, 2)
                    }
                    .foregroundStyle(Tema.testo)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Dettagli e scambio")
        }
    }

    private func puntino(_ colore: Color, _ l: String, _ v: Double) -> some View {
        HStack(spacing: 4) {
            Circle().fill(colore).frame(width: 7, height: 7)
            Text("\(l) \(Int(r0(v)))").font(.system(size: 12, weight: .bold)).foregroundStyle(Tema.tenue)
        }
    }
}

// dettagli di un pasto: ingredienti con i grammi (e l'aiuto in pezzi), preparazione, scambio con un'alternativa
struct PastoSheet: View {
    @EnvironmentObject var s: AppStore
    @Environment(\.dismiss) private var chiudi
    let di: Int
    let si: Int
    let oggi: Bool
    @State private var fuoriAperto = false

    var body: some View {
        let plan = s.pianoGiorno(di, oggi: oggi)
        let m = plan.meals[si]
        let mangiato = oggi && s.mangiati().contains(si)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    Text("\(m.time) · \(m.label.components(separatedBy: " (").first ?? m.label) · \(plan.day.name)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.tenue)
                    Spacer()
                    Button { chiudi() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 34, height: 34).background(Tema.scheda, in: Circle()) }
                        .foregroundStyle(Tema.testo).accessibilityLabel("Chiudi")
                }
                if m.free {
                    Text("Pasto libero").font(.system(size: 32, weight: .heavy))
                    Text("Fuori, senza pesare: un primo o un secondo con contorno, oppure una pizza; acqua o bibita zero. Vale circa \(Int(stimaPastoLibero)) kcal ed è già dentro le kcal del giorno. Se vuoi i numeri veri, segnalo da Oggi.")
                } else {
                    Text(s.piano.recipe(m.code).name).font(.system(size: 28, weight: .heavy))
                    HStack(spacing: 10) {
                        numero("Kcal", Int(m.tot.k), nil); numero("Prot.", Int(r0(m.tot.p)), Tema.p)
                        numero("Carbo", Int(r0(m.tot.c)), Tema.c); numero("Grassi", Int(r0(m.tot.fa)), Tema.g)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(m.lines.enumerated()), id: \.offset) { n, l in
                            let aiuto = s.piano.aiuto(l.f, l.g)
                            HStack(spacing: 12) {
                                Text(s.piano.icona(l.f)).font(.system(size: 22)).frame(width: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.piano.foodName(l.f)).font(.system(size: 16, weight: .semibold))
                                    if !aiuto.isEmpty { Text(aiuto).font(.system(size: 12)).foregroundStyle(Tema.tenue) }
                                }
                                Spacer()
                                Text("\(Int(l.g)) \(s.piano.unitaPeso(l.f))").font(.sport(24)).monospacedDigit()
                            }
                            .padding(.vertical, 10)
                            if n < m.lines.count - 1 { Divider().overlay(Tema.linea).padding(.leading, 42) }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    let come = s.piano.recipe(m.code).how
                    if !come.isEmpty { Text(come).font(.system(size: 14)).foregroundStyle(Tema.tenue) }
                    if oggi {
                        if s.fuoriPerFascia(si) == nil {
                            Button(mangiato ? "Togli la spunta" : "Segna come mangiato") { s.toccaMangiato(si) }.buttonStyle(PulsantePieno(colore: Tema.testo, testo: Tema.fondo))
                        }
                        Button { fuoriAperto = true } label: {
                            Label(s.fuoriPerFascia(si) == nil ? "Ho mangiato altro" : "Modifica quello che hai mangiato", systemImage: "fork.knife")
                        }
                        .buttonStyle(PulsanteLeggero()).frame(maxWidth: .infinity)
                    }
                    Titolo(testo: "Scambia con")
                    ForEach((s.piano.variants[m.slot] ?? [:]).keys.sorted(), id: \.self) { code in
                        opzione(code, m)
                    }
                }
            }
            .padding(20)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .sheet(isPresented: $fuoriAperto) { FuoriPianoSheet(si: si, esistente: s.fuoriPerFascia(si)).foglio() }
    }

    // un piatto alternativo: icona del cibo principale, nome, kcal con la differenza, macro; quello scelto ha il bordo verde
    private func opzione(_ code: String, _ m: MealPlan) -> some View {
        let righe = s.piano.mealLines(m.slot, code)
        let t = s.piano.sum(righe)
        let diff = Int(t.k - m.tot.k)
        let scelto = code == m.code
        return Button {
            s.cambiaPiatto(di: di, si: si, codice: code)
            Haptic.leggero()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(s.piano.iconaPiatto(righe)).font(.system(size: 24)).frame(width: 46, height: 46)
                    .background(Tema.scheda2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.piano.recipe(code).name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text("\(Int(t.k)) kcal").font(.system(size: 13, weight: .heavy)).foregroundStyle(Tema.testo)
                        if !scelto {
                            Text(diff == 0 ? "uguale" : "\(diff > 0 ? "+" : "−")\(abs(diff))").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Tema.tenue).padding(.horizontal, 6).padding(.vertical, 2).background(Tema.scheda2, in: Capsule())
                        }
                        if code == m.def { Text("originale").font(.system(size: 11, weight: .bold)).foregroundStyle(Tema.tenue) }
                    }
                    Text("P \(fmtNum(t.p)) · C \(fmtNum(t.c)) · G \(fmtNum(t.fa))").font(.system(size: 12)).foregroundStyle(Tema.tenue)
                }
                Spacer(minLength: 4)
                Image(systemName: scelto ? "checkmark.circle.fill" : "circle").font(.system(size: 22)).foregroundStyle(scelto ? Tema.verde : Tema.spento)
            }
            .padding(12)
            .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { if scelto { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Tema.verde, lineWidth: 1.5) } }
        }
        .buttonStyle(.plain)
    }

    private func numero(_ nome: String, _ v: Int, _ colore: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) { if let colore { Circle().fill(colore).frame(width: 7, height: 7) }; Text(nome).font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.tenue).lineLimit(1) }
            Text(fmtMigliaia(Double(v))).font(.sport(28)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading).padding(10)
        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// lista della spesa: le quantità di tutta la settimana (scambi compresi), con la spunta per quello che hai già preso.
// Un riquadro per categoria; ogni riga: spunta, icona, nome (note tra parentesi e pezzi in piccolo sotto), grammi.
struct SpesaView: View {
    @EnvironmentObject var s: AppStore
    @AppStorage("spesa.nascondiPresi") private var nascondi = false
    private let categorie = ["Carne e pesce", "Affettati", "Latticini e uova", "Pane, pasta e cereali", "Frutta", "Verdura cruda", "Condimenti e dispensa", "Integratori e snack"]

    private func totaliSettimana() -> [String: Double] {
        var tot: [String: Double] = [:]
        for di in 0..<7 { for m in s.pianoGiorno(di).meals where !m.free { for l in m.lines { tot[l.f, default: 0] += l.g } } }
        return tot
    }

    var body: some View {
        let tot = totaliSettimana()
        let presi = tot.keys.filter { s.d.shopGot[$0] == true }.count
        return VStack(alignment: .leading, spacing: 16) {
            Scheda(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("LISTA DELLA SPESA").font(.sport(24))
                        Spacer()
                        Text("\(presi)").font(.sport(26)).monospacedDigit() + Text(" / \(tot.count)").font(.sport(18)).foregroundColor(Tema.tenue)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Tema.scheda2)
                            Capsule().fill(Tema.verde).frame(width: g.size.width * (tot.isEmpty ? 0 : Double(presi) / Double(tot.count)))
                        }
                    }
                    .frame(height: 6)
                    Text("Per 7 giorni, scambi compresi. Carne, pesce, pasta, riso e patate pesati da crudi.").font(.system(size: 12)).foregroundStyle(Tema.tenue)
                    HStack(spacing: 8) {
                        Button { withAnimation(.snappy(duration: 0.2)) { nascondi.toggle() } } label: {
                            Label(nascondi ? "Mostra tutto" : "Nascondi presi", systemImage: nascondi ? "eye" : "eye.slash")
                        }
                        .buttonStyle(PulsanteLeggero())
                        Spacer()
                        if presi > 0 {
                            Menu {
                                Section("Togliere tutte le spunte?") {
                                    Button(role: .destructive) { s.d.shopGot = [:] } label: { Label("Azzera la lista", systemImage: "arrow.counterclockwise") }
                                }
                            } label: {
                                Label("Azzera", systemImage: "arrow.counterclockwise").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo)
                                    .padding(.horizontal, 14).frame(minHeight: 38).background(Tema.scheda2, in: Capsule())
                            }
                        }
                    }
                }
            }
            ForEach(categorie, id: \.self) { cat in
                let tutti = tot.keys.filter { s.piano.foods[$0]?.cat == cat }.sorted { s.piano.foodName($0) < s.piano.foodName($1) }
                let visibili = nascondi ? tutti.filter { s.d.shopGot[$0] != true } : tutti
                if !visibili.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(s.piano.iconaCategoria(cat)).font(.system(size: 18))
                            Text(cat.uppercased()).font(.sport(20)).foregroundStyle(Tema.tenue).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer()
                            Text("\(tutti.filter { s.d.shopGot[$0] == true }.count)/\(tutti.count)").font(.system(size: 13, weight: .bold)).foregroundStyle(Tema.tenue)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(visibili.enumerated()), id: \.element) { n, id in
                                riga(id, tot[id] ?? 0)
                                if n < visibili.count - 1 { Rectangle().fill(Tema.linea).frame(height: 1).padding(.leading, 78) }
                            }
                        }
                        .padding(.horizontal, 14)
                        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
            if nascondi && presi == tot.count && !tot.isEmpty {
                Scheda { Text("Hai preso tutto. 🎉").font(.system(size: 16, weight: .semibold)) }
            }
        }
    }

    private func riga(_ id: String, _ g: Double) -> some View {
        let preso = s.d.shopGot[id] == true
        let completo = s.piano.foods[id]?.n ?? id
        let nota = completo.contains(" (") ? String(completo.split(separator: "(", maxSplits: 1).last ?? "").replacingOccurrences(of: ")", with: "") : ""
        let pezzi = s.piano.aiuto(id, g, spesa: true)
        let sotto = [nota, pezzi].filter { !$0.isEmpty }.joined(separator: " · ")
        return Button {
            withAnimation(.snappy(duration: 0.2)) { s.d.shopGot[id] = preso ? nil : true }
            Haptic.leggero()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: preso ? "checkmark.circle.fill" : "circle").font(.system(size: 22)).foregroundStyle(preso ? Tema.verde : Tema.spento)
                Text(s.piano.icona(id)).font(.system(size: 17)).frame(width: 32, height: 32)
                    .background(Tema.scheda2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.piano.foodName(id)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo)
                        .strikethrough(preso).lineLimit(1).minimumScaleFactor(0.85)
                    if !sotto.isEmpty { Text(sotto).font(.system(size: 11)).foregroundStyle(Tema.tenue).lineLimit(1).minimumScaleFactor(0.85) }
                }
                Spacer(minLength: 6)
                Text("\(fmtMigliaia(g)) \(s.piano.unitaPeso(id))").font(.sport(21)).monospacedDigit().foregroundStyle(Tema.testo)
            }
            .padding(.vertical, 9)
            .opacity(preso ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// sostituzioni: tre regole con un'icona, poi un gruppo per tipo (proteine, carboidrati, grassi) con il riferimento in argento
// e gli alimenti equivalenti in un elenco compatto (icona, nome, kcal, grammi in grande)
struct SostituzioniView: View {
    @EnvironmentObject var s: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Scheda(padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    regola("arrow.left.arrow.right", Tema.ambra, "Un pasto intero", "Tocca il pasto nel Piano e scegli un'alternativa della stessa fascia: le calorie sono quasi uguali.")
                    regola("scalemass.fill", Tema.g, "Un solo alimento", "Sempre dentro lo stesso pasto e con la dose del giorno (ON o OFF): usa le quantità qui sotto.")
                    regola("drop.fill", Tema.c, "Hamburger e sgombro", "Hanno più grassi: se li scambi con pollo o pesce magro, quel giorno puoi aggiungere 20 g di mandorle allo spuntino.")
                    regola("takeoutbag.and.cup.and.straw.fill", Tema.verde, "Panini e spuntini", "I panini (tacchino, pollo, bresaola) si scambiano liberamente; la bresaola ha più sale. Gli spuntini della sera tra loro, e le due colazioni del weekend.")
                }
            }
            ForEach(s.piano.equivalents, id: \.title) { g in gruppo(g) }
        }
    }

    private func regola(_ icona: String, _ colore: Color, _ titolo: String, _ testo: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icona).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(colore, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(titolo).font(.system(size: 15, weight: .bold))
                Text(testo).font(.system(size: 13)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func gruppo(_ g: Equivalent) -> some View {
        let parti = g.title.components(separatedBy: " · ")
        return VStack(alignment: .leading, spacing: 8) {
            Text((parti.first ?? g.title).uppercased()).font(.sport(24))
            if parti.count > 1 { Text(maiuscolaIniziale(parti.dropFirst().joined(separator: " · ")) + ".").font(.system(size: 13)).foregroundStyle(Tema.tenue) }
            VStack(spacing: 0) {
                riga(g.ref, g.g, riferimento: true)
                ForEach(Array(g.rows.enumerated()), id: \.offset) { n, r in
                    riga(r.f, r.g, riferimento: false)
                    if n < g.rows.count - 1 { Rectangle().fill(Tema.linea).frame(height: 1).padding(.leading, 58) }
                }
            }
            .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func riga(_ f: String, _ g: Double, riferimento: Bool) -> some View {
        let kcal = r0((s.piano.foods[f]?.k ?? 0) * g / 100)
        return HStack(spacing: 12) {
            Text(s.piano.icona(f)).font(.system(size: 18)).frame(width: 34, height: 34)
                .background(riferimento ? Tema.inchiostro.opacity(0.1) : Tema.scheda2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(s.piano.foodName(f)).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(riferimento ? "riferimento · \(Int(kcal)) kcal" : "\(Int(kcal)) kcal").font(.system(size: 12)).opacity(0.65)
            }
            Spacer(minLength: 6)
            Text("\(Int(g)) g").font(.sport(26)).monospacedDigit()
        }
        .foregroundStyle(riferimento ? Tema.inchiostro : Tema.testo)
        .padding(.horizontal, 12).padding(.vertical, riferimento ? 12 : 9)
        .background { if riferimento { Argento(raggio: 0) } }
    }
}
