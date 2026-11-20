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
                Text("Settimana").tag(0); Text("Spesa").tag(1); Text("Scambi").tag(2); Text("I miei").tag(3)
            }
            .pickerStyle(.segmented)
            switch sezione {
            case 1: SpesaView()
            case 2: SostituzioniView()
            case 3: MieiPastiView()
            default: settimana
            }
        }
        .sheet(item: $pasto) { m in PastoSheet(di: giorno, si: m.si, oggi: false).foglio() }
    }

    private var settimana: some View {
        let piani = (0..<7).map { s.pianoGiorno($0) }
        let media = piani.reduce(0) { $0 + $1.previsti.k } / 7
        let plan = piani[giorno]
        let scambiato = s.giornoCambiato(giorno)
        return VStack(alignment: .leading, spacing: 14) {
            // i giorni: pillole con kcal e icona; quella scelta in argento, oggi col puntino rosso
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { i in pillola(i, piani[i]) }
            }
            // il giorno scelto
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.day.name.uppercased()).font(.sport(38))
                    Text(etichettaGiorno(plan)).font(.system(size: 13, weight: .medium)).foregroundStyle(Tema.tenue).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                SwitchGiornoOnOff(on: s.giornoOn(giorno)) { s.impostaGiornoOn($0, di: giorno) }
                if scambiato {
                    Menu {
                        Section("Hai cambiato il piano del giorno") {
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
        let on = (p.conv.isEmpty ? p.day.type : p.conv).hasPrefix("ON")
        let icona = on ? "dumbbell.fill" : p.hasFree ? "fork.knife" : "moon.fill"
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
        let on = (plan.conv.isEmpty ? plan.day.type : plan.conv).hasPrefix("ON")
        let weekend = plan.day.type == "OFF_W" || plan.day.type == "FREE"
        let tipo = on ? "ON" : plan.day.type == "FREE" ? "OFF · pasto libero" : weekend ? "OFF · weekend" : "OFF"
        let contesto = weekend ? (on ? " · weekend" : "") : " · scuola"
        let palestra: String = {
            guard on else { return "" }
            if let rid = (plan.di == s.oggiIdx ? s.schedaOggi : nil) ?? plan.day.wo, let r = s.routine(rid) { return " · \(r.name) alle 16:30" }
            return " · recupero palestra"
        }()
        return tipo + contesto + palestra
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
                            if m.code != m.def || m.cambiato { Image(systemName: "arrow.left.arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Tema.ambra) }
                            Spacer(minLength: 4)
                            Text("\(Int(m.tot.k))").font(.sport(24)).monospacedDigit() + Text(" kcal").font(.system(size: 12)).foregroundColor(Tema.tenue)
                        }
                        Text(s.piano.recipe(m.code).name).font(.system(size: 16, weight: .bold)).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 6) {
                            ForEach(Array(m.lines.enumerated()), id: \.offset) { _, l in
                                let aiuto = s.piano.aiuto(l)
                                HStack(spacing: 8) {
                                    Text(s.piano.icona(l)).font(.system(size: 15)).frame(width: 22)
                                    (Text(s.piano.nome(l)).foregroundColor(Tema.testo)
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
    @State private var mio = false      // la finestra si apre con il pasto «da mangiare» (dopo) invece che «già mangiato»
    struct SceltaEsterna: Identifiable { let id = UUID(); let indice: Int?; var scanner = false }
    @State private var modifica = false // «Cambia i cibi»: − e + sui grammi, scambia, aggiungi, togli
    @State private var esterno: SceltaEsterna?
    @State private var rigaGrammi: Int?
    @State private var testoGrammi = ""
    private let categorieCibi = ["Carne e pesce", "Affettati", "Latticini e uova", "Pane, pasta e cereali", "Frutta", "Verdura cruda", "Condimenti e dispensa", "Integratori e snack"]

    var body: some View {
        let plan = s.pianoGiorno(di, oggi: oggi)
        let m = plan.meals[si]
        let mangiato = oggi && s.mangiati().contains(si)
        VStack(spacing: 0) {
            // la testata resta ferma: scorrendo fino agli scambi si vede sempre di che pasto si parla
            HStack(alignment: .center) {
                Text("\(m.time) · \(nomeFascia(m)) · \(plan.day.name)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.tenue).lineLimit(1)
                Spacer()
                Button { chiudi() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 34, height: 34).background(Tema.scheda, in: Circle()) }
                    .foregroundStyle(Tema.testo).accessibilityLabel("Chiudi")
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if m.free {
                        Text("Pasto libero").font(.system(size: 30, weight: .heavy))
                        Text("Fuori, senza pesare: un primo o un secondo con contorno, oppure una pizza; acqua o bibita zero. Vale circa \(Int(stimaPastoLibero)) kcal ed è già dentro le kcal del giorno. Se vuoi i numeri veri, segnalo da Oggi.")
                    } else {
                        Text(s.piano.recipe(m.code).name).font(.system(size: 28, weight: .heavy)).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            numero("Kcal", Int(m.tot.k), nil); numero("Prot.", Int(r0(m.tot.p)), Tema.p)
                            numero("Carbo", Int(r0(m.tot.c)), Tema.c); numero("Grassi", Int(r0(m.tot.fa)), Tema.g)
                        }
                        cibi(m)
                        let come = s.piano.recipe(m.code).how
                        if !come.isEmpty { Text(come).font(.system(size: 14)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true) }
                        if oggi { azioniOggi(m, mangiato) }
                        scambi(m, on: (plan.conv.isEmpty ? plan.day.type : plan.conv).hasPrefix("ON"))
                    }
                }
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 24)
            }
        }
        .background(Tema.fondo.ignoresSafeArea())
        .sheet(isPresented: $fuoriAperto) { FuoriPianoSheet(si: si, esistente: s.fuoriPerFascia(si), mio: mio).foglio() }
        .sheet(item: $esterno) { e in CiboPastoSheet(di: di, m: m, indice: e.indice, apriScanner: e.scanner).foglio() }
        // i grammi scritti a mano: una finestrella dal basso (niente avvisi in mezzo allo schermo)
        .sheet(isPresented: Binding(get: { rigaGrammi != nil }, set: { if !$0 { rigaGrammi = nil } })) {
            let l = rigaGrammi.flatMap { m.lines[safe: $0] }
            GrammiSheet(nome: l.map { s.piano.nome($0) } ?? "", unita: l.map { s.piano.unitaPeso($0.f) } ?? "g", testo: $testoGrammi) { v in
                if let i = rigaGrammi { s.impostaGrammiCibo(di: di, m, i, grammi: v) }
                rigaGrammi = nil
            }
            .presentationDetents([.height(300)])
            .presentationBackground(Tema.fondo)
        }
    }

    private func nomeFascia(_ m: MealPlan) -> String { m.label.components(separatedBy: " (").first ?? m.label }

    // MARK: i cibi del pasto

    // in lettura come sempre; con «Cambia i cibi» ogni cibo si scambia con uno equivalente (con i grammi giusti per la fascia),
    // i grammi si cambiano con − e +, se ne aggiunge o se ne toglie uno. Kcal e macro in alto si aggiornano subito.
    @ViewBuilder private func cibi(_ m: MealPlan) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(m.lines.enumerated()), id: \.offset) { n, l in
                if modifica { rigaModifica(n, l, m) } else { riga(l) }
                if n < m.lines.count - 1 { Divider().overlay(Tema.linea).padding(.leading, 42) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        HStack(spacing: 8) {
            if modifica {
                aggiungi(m)
                Button { esterno = SceltaEsterna(indice: nil, scanner: true) } label: {
                    Image(systemName: "barcode.viewfinder").font(.system(size: 16, weight: .bold)).foregroundStyle(Tema.testo)
                        .frame(width: 38, height: 38).background(Tema.scheda2, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scansiona codice a barre")
                Button { withAnimation(.snappy(duration: 0.2)) { modifica = false } } label: {
                    Text("Fatto").font(.system(size: 15, weight: .bold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(PulsanteLeggero())
            } else {
                Button { withAnimation(.snappy(duration: 0.2)) { modifica = true } } label: {
                    Label("Cambia i cibi", systemImage: "slider.horizontal.3").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(PulsanteLeggero())
            }
            if m.cambiato {
                Button { s.rimettiRicetta(di: di, m) } label: { Label("Ricetta", systemImage: "arrow.uturn.backward").lineLimit(1) }
                    .buttonStyle(PulsanteLeggero())
                    .accessibilityLabel("Rimetti la ricetta del piano")
            }
        }
        if m.cambiato {
            Text("Cibi cambiati da te: valgono ogni \(s.piano.week[di].name.lowercased()) per questo piatto, finché non cambi piatto o rimetti la ricetta.")
                .font(.system(size: 12)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
        }
    }

    // un cibo in lettura: icona, nome con l'aiuto in pezzi, grammi
    private func riga(_ l: Line) -> some View {
        let aiuto = s.piano.aiuto(l)
        return HStack(spacing: 12) {
            Text(s.piano.icona(l)).font(.system(size: 22)).frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.piano.nome(l)).font(.system(size: 16, weight: .semibold))
                if !aiuto.isEmpty { Text(aiuto).font(.system(size: 12)).foregroundStyle(Tema.tenue) }
            }
            Spacer()
            Text("\(Int(l.g)) \(s.piano.unitaPeso(l.f))").font(.sport(24)).monospacedDigit()
        }
        .padding(.vertical, 10)
    }

    // un cibo da cambiare: tocchi il nome per scambiarlo (anche con codice a barre o ricerca) o toglierlo, − e + o tocco sul numero per i grammi
    private func rigaModifica(_ n: Int, _ l: Line, _ m: MealPlan) -> some View {
        let alt = s.piano.alternative(l.f, l.g, slot: m.slot)
        let passo = s.piano.passo(l.ref)
        let togli = m.lines.count > 1
        return HStack(spacing: 10) {
            Menu {
                if !alt.isEmpty {
                    Section("Al posto di \(s.piano.nome(l).lowercased())") {
                        ForEach(alt, id: \.f) { a in
                            Button { s.scambiaCibo(di: di, m, n, con: a) } label: {
                                Label { Text(s.piano.foodName(a.f)); Text("\(Int(a.g)) \(s.piano.unitaPeso(a.f)) · \(Int(s.piano.line(a.f, a.g).k)) kcal") }
                                    icon: { Image(systemName: "arrow.left.arrow.right") }
                            }
                        }
                    }
                }
                Section("Un altro prodotto") {
                    Button { esterno = SceltaEsterna(indice: n, scanner: true) } label: {
                        Label("Scansiona codice a barre", systemImage: "barcode.viewfinder")
                    }
                    Button { esterno = SceltaEsterna(indice: n, scanner: false) } label: {
                        Label("Cerca o scrivi a mano…", systemImage: "magnifyingglass")
                    }
                }
                if togli {
                    Button(role: .destructive) { s.togliCibo(di: di, m, n) } label: { Label("Togli dal pasto", systemImage: "minus.circle") }
                }
            } label: {
                nomeCibo(l, sotto: "Scambia")
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                tondo("minus", attivo: l.g > 5) { s.grammiCibo(di: di, m, n, piu: false) }
                    .accessibilityLabel("Meno \(Int(passo)) \(s.piano.unitaPeso(l.f))")
                Button {
                    testoGrammi = "\(Int(l.g))"
                    rigaGrammi = n
                } label: {
                    Text("\(Int(l.g))").font(.sport(22)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).frame(minWidth: 44)
                        .foregroundStyle(Tema.testo)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Int(l.g)) \(s.piano.unitaPeso(l.f)), tocca per scrivere i grammi")
                tondo("plus", attivo: true) { s.grammiCibo(di: di, m, n, piu: true) }
                    .accessibilityLabel("Più \(Int(passo)) \(s.piano.unitaPeso(l.f))")
            }
        }
        .padding(.vertical, 8)
    }

    private func nomeCibo(_ l: Line, sotto: String) -> some View {
        HStack(spacing: 12) {
            Text(s.piano.icona(l)).font(.system(size: 22)).frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.piano.nome(l)).font(.system(size: 16, weight: .semibold)).foregroundStyle(Tema.testo)
                    .lineLimit(1).minimumScaleFactor(0.8)
                if !sotto.isEmpty {
                    HStack(spacing: 3) {
                        Text(sotto)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.tenue)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func tondo(_ icona: String, attivo: Bool, _ azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            Image(systemName: icona).font(.system(size: 13, weight: .bold))
                .frame(width: 32, height: 32).background(Tema.scheda2, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(attivo ? Tema.testo : Tema.spento)
        .disabled(!attivo)
    }

    // aggiungi un cibo al pasto: prodotto esterno (codice a barre, Open Food Facts, a mano) o dal piano
    private func aggiungi(_ m: MealPlan) -> some View {
        let presenti = Set(m.lines.map(\.f))
        return Menu {
            Section("Prodotto esterno") {
                Button { esterno = SceltaEsterna(indice: nil, scanner: true) } label: {
                    Label("Scansiona codice a barre", systemImage: "barcode.viewfinder")
                }
                Button { esterno = SceltaEsterna(indice: nil, scanner: false) } label: {
                    Label("Cerca o scrivi a mano…", systemImage: "magnifyingglass")
                }
            }
            ForEach(categorieCibi, id: \.self) { cat in
                let lista = s.piano.foods.values.filter { $0.cat == cat && !presenti.contains($0.id) }
                    .sorted { s.piano.foodName($0.id) < s.piano.foodName($1.id) }
                if !lista.isEmpty {
                    Menu(cat) {
                        ForEach(lista, id: \.id) { f in
                            Button("\(s.piano.foodName(f.id)) · \(Int(s.piano.doseNuova(f.id, slot: m.slot))) \(s.piano.unitaPeso(f.id))") {
                                s.aggiungiCibo(di: di, m, f.id)
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Aggiungi", systemImage: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo).lineLimit(1)
                .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 38).background(Tema.scheda2, in: Capsule())
        }
    }

    // oggi: un pulsante grande (segna), due piccoli (cambia pasto · i miei pasti) e «Togli da oggi»
    @ViewBuilder private func azioniOggi(_ m: MealPlan, _ mangiato: Bool) -> some View {
        if let f = s.fuoriPerFascia(si) {
            // al posto del piatto del piano c'è già un tuo pasto: si modifica o si torna al piano
            Text("Al suo posto: \(f.nome) · \(Int(f.tot.k)) kcal" + (f.giaMangiato ? "" : " (da mangiare)"))
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
            Button("Modifica il tuo pasto") { mio = !f.giaMangiato; fuoriAperto = true }.buttonStyle(PulsantePieno(colore: Tema.testo, testo: Tema.fondo))
            Button { s.togliFuori(f.id) } label: { Label("Torna al piatto del piano", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity) }
                .buttonStyle(PulsanteLeggero())
        } else {
            if s.pastoTolto(si) {
                Text("Tolto dal piano di oggi: non conta nei totali.").font(.system(size: 14)).foregroundStyle(Tema.tenue)
                Button("Rimetti nel piano di oggi") { s.rimettiPasto(si) }.buttonStyle(PulsantePieno(colore: Tema.testo, testo: Tema.fondo))
            } else {
                Button(mangiato ? "Togli la spunta" : "Segna come mangiato") { s.toccaMangiato(si) }.buttonStyle(PulsantePieno(colore: Tema.testo, testo: Tema.fondo))
            }
            HStack(spacing: 8) {
                Button { mio = s.ancoraDaMangiare(m); fuoriAperto = true } label: {
                    Label("Cambia pasto", systemImage: "fork.knife").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(PulsanteLeggero())
                Menu {
                    if !s.mieiPasti.isEmpty {
                        Section("Al posto di questo pasto") {
                            ForEach(s.mieiPasti.prefix(12)) { r in
                                Button { s.mettiMio(r, al: si) } label: {
                                    Label { Text(r.nome); Text("\(Int(r.tot.k)) kcal · P \(Int(r.tot.p))") } icon: { Image(systemName: "star") }
                                }
                            }
                        }
                    }
                    Button { mio = true; fuoriAperto = true } label: { Label("Nuovo pasto mio", systemImage: "plus") }
                } label: {
                    Label("I miei pasti", systemImage: "star").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo).lineLimit(1)
                        .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 38).background(Tema.scheda2, in: Capsule())
                }
            }
            if !s.pastoTolto(si) {
                Menu {
                    Section("Oggi non lo mangi?") {
                        Button(role: .destructive) { s.togliPasto(si); chiudi() } label: { Label("Sì, toglilo da oggi", systemImage: "minus.circle") }
                    }
                } label: {
                    Label("Togli da oggi", systemImage: "minus.circle").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.rosso)
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
            }
        }
    }

    // gli altri piatti della stessa fascia: prima quello di adesso, poi dal più vicino come kcal
    @ViewBuilder private func scambi(_ m: MealPlan, on: Bool) -> some View {
        let kcal = { (c: String) in s.piano.sum(s.piano.mealLines(m.slot, c)).k }
        let codici = (s.piano.variants[m.slot] ?? [:]).keys.sorted { a, b in
            if a == m.code || b == m.code { return a == m.code }
            let da = abs(kcal(a) - m.tot.k), db = abs(kcal(b) - m.tot.k)
            return da == db ? a < b : da < db
        }
        if codici.count > 1 {
            VStack(alignment: .leading, spacing: 2) {
                Titolo(testo: "Scambia con")
                Text("Stessa fascia, con le dosi di un giorno \(on ? "ON" : "OFF"): tocca un piatto per metterlo al posto di questo.")
                    .font(.system(size: 13)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(codici, id: \.self) { code in opzione(code, m) }
        }
    }

    // un piatto alternativo: icona del cibo principale, nome e macro, a destra le kcal con la differenza; quello scelto è in verde
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
                Text(s.piano.iconaPiatto(righe)).font(.system(size: 22)).frame(width: 42, height: 42)
                    .background(Tema.scheda2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.piano.recipe(code).name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Text("P \(fmtNum(t.p)) · C \(fmtNum(t.c)) · G \(fmtNum(t.fa))").font(.system(size: 12)).foregroundStyle(Tema.tenue)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(Int(t.k))").font(.system(size: 16, weight: .heavy)).monospacedDigit().foregroundColor(Tema.testo)
                        + Text(" kcal").font(.system(size: 11, weight: .semibold)).foregroundColor(Tema.tenue)
                    Text(scelto ? (code == m.def ? "adesso · originale" : "adesso") : diff == 0 ? "uguale" : "\(diff > 0 ? "+" : "−")\(abs(diff))")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(scelto ? Tema.inchiostro : Tema.tenue).lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(scelto ? AnyShapeStyle(Tema.verde) : AnyShapeStyle(Tema.scheda2), in: Capsule())
                }
            }
            .padding(12)
            .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { if scelto { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Tema.verde, lineWidth: 1.5) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(s.piano.recipe(code).name), \(Int(t.k)) kcal" + (scelto ? ", scelto" : ""))
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

// i grammi di un cibo scritti a mano (da «Cambia i cibi», toccando il numero)
struct GrammiSheet: View {
    @Environment(\.dismiss) private var chiudi
    let nome: String
    let unita: String
    @Binding var testo: String
    let salva: (Double) -> Void
    @FocusState private var scrivendo: Bool

    private var valore: Double? {
        Double(testo.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 && $0 < 5000 ? $0 : nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            TestataFoglio(titolo: nome, sotto: "Quanti \(unita == "ml" ? "millilitri" : "grammi")?", chiudi: { chiudi() })
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("0", text: $testo).keyboardType(.decimalPad).focused($scrivendo)
                    .font(.sport(52)).monospacedDigit()
                Text(unita).font(.sport(24)).foregroundStyle(Tema.tenue)
            }
            .padding(.horizontal, 18).padding(.vertical, 6)
            .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 20)
            Spacer(minLength: 0)
        }
        .pulsanteInFondo("Salva", attivo: valore != nil) { if let v = valore { salva(v) } }
        .background(Tema.fondo.ignoresSafeArea())
        .onAppear { scrivendo = true }
    }
}

// «I miei pasti»: i tuoi pasti salvati, da mettere al posto di un pasto di oggi con un tocco (anche dall'orologio)
struct MieiPastiView: View {
    @EnvironmentObject var s: AppStore
    @State private var nuovo = false
    @State private var modifica: PastoMio?

    var body: some View {
        let miei = s.mieiPasti
        VStack(alignment: .leading, spacing: 14) {
            Scheda(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("I MIEI PASTI").font(.sport(24))
                    Text("Pasti tuoi da rifare: li metti al posto di un pasto di oggi con un tocco, anche dall'orologio (Pasti → Cambia piatto). Poi li segni con la spunta, come gli altri.")
                        .font(.system(size: 13)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
                    Button { nuovo = true } label: { Label("Nuovo pasto", systemImage: "plus") }
                        .buttonStyle(PulsantePieno(colore: Tema.testo, testo: Tema.fondo))
                }
            }
            if miei.isEmpty {
                Text("Ancora niente: crea un pasto qui, oppure attiva «Salva tra i miei pasti» quando segni cosa hai mangiato.")
                    .font(.system(size: 14)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(miei) { r in carta(r) }
        }
        .sheet(isPresented: $nuovo) { FuoriPianoSheet(si: nil, perLibreria: true).foglio() }
        .sheet(item: $modifica) { r in FuoriPianoSheet(si: nil, libreria: r, perLibreria: true).foglio() }
    }

    private func carta(_ r: PastoMio) -> some View {
        let t = r.tot
        let oggi = s.pianoOggi.meals   // anche un pasto tolto: con un tuo pasto al suo posto torna nel piano
        return Scheda(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(r.nome).font(.system(size: 17, weight: .bold)).lineLimit(2)
                    Spacer(minLength: 4)
                    Text("\(Int(t.k))").font(.sport(24)).monospacedDigit() + Text(" kcal").font(.system(size: 12)).foregroundColor(Tema.tenue)
                }
                VStack(spacing: 5) {
                    ForEach(r.voci) { v in
                        HStack(spacing: 8) {
                            Text(v.fonte.flatMap { s.piano.foods[$0] != nil ? s.piano.icona($0) : nil } ?? "🍽️").font(.system(size: 14)).frame(width: 22)
                            Text(v.nome).font(.system(size: 14)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(Int(v.g)) g").font(.system(size: 14, weight: .heavy)).monospacedDigit()
                        }
                    }
                }
                HStack(spacing: 12) {
                    Text("P \(Int(r0(t.p))) · C \(Int(r0(t.c))) · G \(Int(r0(t.fa)))").font(.system(size: 12, weight: .bold)).foregroundStyle(Tema.tenue)
                    Spacer()
                }
                HStack(spacing: 8) {
                    Menu {
                        Section("Oggi, al posto di…") {
                            ForEach(oggi) { m in
                                Button { s.mettiMio(r, al: m.si) } label: {
                                    Text("\(m.time) · \(m.free ? "Pasto libero" : m.label.components(separatedBy: " (").first ?? m.label)")
                                }
                            }
                        }
                    } label: {
                        Label("Usa oggi", systemImage: "fork.knife").font(.system(size: 15, weight: .bold)).foregroundStyle(Tema.fondo)
                            .frame(maxWidth: .infinity, minHeight: 40).background(Tema.testo, in: Capsule())
                    }
                    Button { modifica = r } label: { Label("Modifica", systemImage: "pencil") }.buttonStyle(PulsanteLeggero())
                }
            }
        }
    }
}

// lista della spesa: le quantità di tutta la settimana (scambi compresi), con la spunta per quello che hai già preso.
// Un riquadro per categoria; ogni riga: spunta, icona, nome (note tra parentesi e pezzi in piccolo sotto), grammi.
struct SpesaView: View {
    @EnvironmentObject var s: AppStore
    @AppStorage("spesa.nascondiPresi") private var nascondi = false
    private let categorie = ["Carne e pesce", "Affettati", "Latticini e uova", "Pane, pasta e cereali", "Frutta", "Verdura cruda", "Condimenti e dispensa", "Integratori e snack"]

    private func totaliSettimana() -> (tot: [String: Double], esterni: [String: String]) {
        var tot: [String: Double] = [:]
        var esterni: [String: String] = [:]
        for di in 0..<7 {
            for m in s.pianoGiorno(di).meals where !m.free {
                for l in m.lines {
                    tot[l.f, default: 0] += l.g
                    if s.piano.foods[l.f] == nil, let n = l.nome { esterni[l.f] = n }
                }
            }
        }
        return (tot, esterni)
    }

    var body: some View {
        let (tot, esterni) = totaliSettimana()
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
            if !esterni.isEmpty {
                let tuttiEst = esterni.keys.sorted { (esterni[$0] ?? $0) < (esterni[$1] ?? $1) }
                let visEst = nascondi ? tuttiEst.filter { s.d.shopGot[$0] != true } : tuttiEst
                if !visEst.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("📦").font(.system(size: 18))
                            Text("PRODOTTI AGGIUNTI DA TE").font(.sport(20)).foregroundStyle(Tema.tenue).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer()
                            Text("\(tuttiEst.filter { s.d.shopGot[$0] == true }.count)/\(tuttiEst.count)").font(.system(size: 13, weight: .bold)).foregroundStyle(Tema.tenue)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(visEst.enumerated()), id: \.element) { n, id in
                                riga(id, tot[id] ?? 0, nomeEsterno: esterni[id])
                                if n < visEst.count - 1 { Rectangle().fill(Tema.linea).frame(height: 1).padding(.leading, 78) }
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

    private func riga(_ id: String, _ g: Double, nomeEsterno: String? = nil) -> some View {
        let preso = s.d.shopGot[id] == true
        let completo = nomeEsterno ?? s.piano.foods[id]?.n ?? id
        let nota = completo.contains(" (") ? String(completo.split(separator: "(", maxSplits: 1).last ?? "").replacingOccurrences(of: ")", with: "") : ""
        let pezzi = s.piano.aiuto(id, g, spesa: true)
        let sotto = [nota, pezzi].filter { !$0.isEmpty }.joined(separator: " · ")
        return Button {
            withAnimation(.snappy(duration: 0.2)) { s.d.shopGot[id] = preso ? nil : true }
            Haptic.leggero()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: preso ? "checkmark.circle.fill" : "circle").font(.system(size: 22)).foregroundStyle(preso ? Tema.verde : Tema.spento)
                Text(nomeEsterno != nil ? "📦" : s.piano.icona(id)).font(.system(size: 17)).frame(width: 32, height: 32)
                    .background(Tema.scheda2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(nomeEsterno?.components(separatedBy: " (").first ?? s.piano.foodName(id)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo)
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
                    regola("arrow.left.arrow.right", Tema.ambra, "Un pasto intero", "Tocca il pasto nel Piano e scegli un'alternativa della stessa fascia: tutti i piatti della fascia sono interscambiabili al 100 %.")
                    regola("scalemass.fill", Tema.g, "Un solo alimento", "Apri un pasto e tocca «Cambia i cibi»: scambi un cibo con uno equivalente (le dosi qui sotto), cambi i grammi con − e +, ne aggiungi o ne togli uno.")
                    regola("flame.fill", Tema.c, "Patate Lamb Weston, patate e pane", "Lo scambio nel pasto ricalcola i grammi esatti con le stesse kcal: 250 g Lamb Weston = 450 g patate = 130 g pane (giorni ON); 150 g Lamb Weston = 270 g patate = 80 g pane (giorni OFF); con gli hamburger di manzo OFF, 50 g pane = 95 g Lamb Weston = 170 g patate.")
                    regola("takeoutbag.and.cup.and.straw.fill", Tema.verde, "Panini e dopo cena", "I 2 panini di scuola hanno sempre 50 g di pan bauletto + 10 g di formaggio light + 50 g di affettato a panino (1 vaschetta da 100 g divisa in due: tacchino, pollo, cotto o bresaola). Gli spuntini del dopo cena (dolci con yogurt greco pesato o salati con fiocchi di latte / Biraghini e crackers) si scambiano liberamente.")
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
