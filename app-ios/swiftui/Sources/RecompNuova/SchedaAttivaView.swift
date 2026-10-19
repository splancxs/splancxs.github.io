import SwiftUI

// L'allenamento in corso: timer di recupero in alto, un riquadro per esercizio con le serie (kg, ripetizioni, spunta).
// Tutto quello che succede qui succede anche sull'orologio e viceversa (WatchBridge).
struct SchedaAttivaView: View {
    @EnvironmentObject var s: AppStore
    @State private var scelta: SceltaEsercizio?
    @State private var notaAperta: Set<Int> = []
    @State private var esercizioAperto: IdEsercizio?

    enum SceltaEsercizio: Identifiable { case aggiungi, cambia(Int); var id: String { switch self { case .aggiungi: "a"; case .cambia(let i): "c\(i)" } } }

    var body: some View {
        if let a = s.d.active {
            Pagina {
                testata(a)
                ForEach(Array(a.items.enumerated()), id: \.offset) { i, it in
                    CartaEsercizio(i: i, it: it, nota: Binding(get: { notaAperta.contains(i) || !it.note.isEmpty }, set: { if $0 { notaAperta.insert(i) } else { notaAperta.remove(i) } }),
                                   cambia: { scelta = .cambia(i) }, apri: { esercizioAperto = IdEsercizio(id: it.ex) })
                    // tra i due esercizi della superserie: si passa subito all'altro, il recupero è dopo il secondo
                    if s.superserieAttiva(a.rid, it.sup), it.sup.hasSuffix("a"), let m = s.compagno(a, i), m == i + 1 {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down").font(.system(size: 12, weight: .bold))
                            Text("Subito dopo, senza recupero").font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Tema.ambra)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, -8)
                    }
                }
                Button { scelta = .aggiungi } label: { Label("Aggiungi esercizio", systemImage: "plus") }.buttonStyle(PulsanteLeggero())
                Scheda { Text("Cardio finale: tapis roulant 15–20′ al 14%, 4,0–4,5 km/h, senza corrimano.").font(.system(size: 14)).foregroundStyle(Tema.tenue) }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let t = s.timerSerie { timer(t) } else { recupero(a) }
            }
            // la tastiera dei numeri non ha «invio»: un solo pulsante «Fine» per tutta la pagina
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fine") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
            .sheet(item: $esercizioAperto) { x in EsercizioSheet(ex: x.id).foglio() }
            .sheet(item: $scelta) { c in
                ElencoEsercizi { ex in
                    switch c { case .aggiungi: s.aggiungiEsercizio(ex); case .cambia(let i): s.sostituisciEsercizio(i, con: ex) }
                    scelta = nil
                }
                .foglio()
            }
        }
    }

    private func testata(_ a: ActiveWorkout) -> some View {
        let fatte = a.items.flatMap(\.sets).filter { $0.done && $0.isWork }.count
        let totali = a.items.flatMap(\.sets).filter(\.isWork).count
        let volume = a.items.reduce(0) { $0 + volOf($1.sets.filter(\.done)) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) { Circle().fill(Tema.rosso).frame(width: 10, height: 10); Text("In corso").font(.system(size: 14, weight: .bold)).foregroundStyle(Tema.tenue) }
                    Text(a.name).font(.system(size: 38, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer()
                Menu {
                    Button { scelta = .aggiungi } label: { Label("Aggiungi esercizio", systemImage: "plus") }
                    Section {
                        // sottomenu: annullare chiede un secondo tocco, ma resta un menu come gli altri
                        Menu {
                            Button(role: .destructive) { s.annulla() } label: { Label("Sì, non salvare", systemImage: "trash") }
                        } label: { Label("Annulla", systemImage: "xmark.circle") }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold)).frame(width: 40, height: 40).background(Tema.scheda, in: Circle())
                }
                .foregroundStyle(Tema.testo)
            }
            HStack(spacing: 10) {
                statistica("Durata") { TimelineView(.periodic(from: .now, by: 1)) { _ in Text(tempoMMSS(Int((Cal.ms() - a.start) / 1000))).monospacedDigit() } }
                statistica("Volume") { Text("\(fmtMigliaia(volume)) kg").monospacedDigit() }
                statistica("Serie") { Text("\(fatte)/\(totali)").monospacedDigit() }
            }
            menuTermina(a)
        }
    }

    // «Termina»: menu con le icone attaccato al pulsante (salva, oppure chiudi senza salvare)
    private func menuTermina(_ a: ActiveWorkout) -> some View {
        let spuntate = a.items.flatMap(\.sets).filter(\.done).count
        return Menu {
            if spuntate > 0 {
                Section(spuntate == 1 ? "1 serie spuntata" : "\(spuntate) serie spuntate") {
                    Button { s.finisci() } label: { Label("Salva e termina", systemImage: "checkmark.circle.fill") }
                }
                Section {
                    Button(role: .destructive) { s.annulla() } label: { Label("Chiudi senza salvare", systemImage: "trash") }
                }
            } else {
                Section("Nessuna serie spuntata") {
                    Button(role: .destructive) { s.annulla() } label: { Label("Annulla allenamento", systemImage: "trash") }
                }
            }
        } label: {
            Text("Termina").font(.system(size: 17, weight: .bold)).foregroundStyle(Tema.fondo)
                .frame(maxWidth: .infinity, minHeight: 50).background(Tema.testo, in: Capsule())
        }
    }

    private func statistica<V: View>(_ nome: String, @ViewBuilder _ valore: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(nome).font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.tenue)
            valore().font(.system(size: 20, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // timer di una serie a tempo: fase («Mettiti in posizione», «Tieni», «Girati»…), secondi grandi, barra, Ferma e Annulla
    private func timer(_ t: TimerTempo) -> some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            let st = t.stato(ctx.date)
            let attesa = st.fase == 0 || st.fase == 2
            let fase = ["Mettiti in posizione", t.lati > 1 ? "Primo lato" : "Tieni", "Girati sull'altro lato", "Secondo lato", "Fatto"][st.fase]
            VStack(spacing: 8) {
                HStack {
                    Text(s.nomeBreve(t.ex)).font(.system(size: 13, weight: .bold)).foregroundStyle(Tema.tenue).lineLimit(1)
                    Spacer()
                    Text("Serie \(t.dove[1] + 1) · \(t.durata)″\(t.lati > 1 ? " per lato" : "")").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.tenue)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(fase).font(.system(size: 18, weight: .bold)).foregroundStyle(attesa ? Tema.ambra : Tema.testo)
                    Spacer()
                    Text(attesa ? "\(Int(ceil(st.resto)))" : tempoMMSS(Int(ceil(st.resto)))).font(.sport(54)).monospacedDigit()
                }
                ProgressView(value: st.fatto).tint(attesa ? Tema.ambra : Tema.verde)
                HStack(spacing: 8) {
                    Button("Annulla") { s.annullaTimer() }.buttonStyle(PulsanteLeggero())
                    Spacer()
                    Button { s.fermaTimer() } label: { Label("Ferma e salva", systemImage: "stop.fill") }.buttonStyle(PulsanteLeggero())
                }
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) { Rectangle().fill(Tema.linea).frame(height: 1) }
        }
    }

    // recupero: conto alla rovescia sempre in vista (resta fermo in alto mentre scorri)
    @ViewBuilder private func recupero(_ a: ActiveWorkout) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            if let fine = s.recuperoAttivo(a) {
                let resto = Int(ceil(fine.timeIntervalSinceNow))
                VStack(spacing: 6) {
                    HStack {
                        Text("Recupero").font(.system(size: 13, weight: .bold)).foregroundStyle(Tema.tenue)
                        Spacer()
                        Text(tempoMMSS(resto)).font(.system(size: 34, weight: .heavy)).monospacedDigit()
                    }
                    if !a.restNext.isEmpty { Text(a.restNext).font(.system(size: 13)).foregroundStyle(Tema.tenue).frame(maxWidth: .infinity, alignment: .leading).lineLimit(2) }
                    HStack(spacing: 8) {
                        Button("−15″") { s.cambiaRecupero(-15) }.buttonStyle(PulsanteLeggero())
                        Button("+15″") { s.cambiaRecupero(15) }.buttonStyle(PulsanteLeggero())
                        Spacer()
                        Button("Salta") { s.saltaRecupero() }.buttonStyle(PulsanteLeggero())
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Rectangle().fill(Tema.linea).frame(height: 1) }
            }
        }
    }
}

// l'esercizio con le sue serie
struct CartaEsercizio: View {
    @EnvironmentObject var s: AppStore
    let i: Int
    let it: ItemRec
    @Binding var nota: Bool
    var cambia: () -> Void
    var apri: () -> Void

    var body: some View {
        let e = s.esercizio(it.ex)
        let consiglio = s.consiglio(it)
        let prec = s.serieAltraVolta(it.ex)
        let sec = e.unit == "sec"
        let a = s.d.active
        let rec = a.map { s.recuperoDi($0, i) } ?? it.rest
        let inSuper = !it.sup.isEmpty
        let superAttiva = s.superserieAttiva(a?.rid, it.sup)
        let compagno = a.flatMap { s.compagno($0, i) }.flatMap { a?.items[safe: $0] }.map { s.nomeBreve($0.ex) }
        Scheda(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                // superserie: si vede subito con chi è abbinato l'esercizio
                if inSuper {
                    HStack(spacing: 6) {
                        Image(systemName: superAttiva ? "link" : "link.badge.plus").font(.system(size: 12, weight: .bold))
                        Text(superAttiva ? "SUPERSERIE \(it.sup.dropLast())" + (compagno.map { " · con \($0)" } ?? "") : "Superserie \(it.sup.dropLast()) separata")
                            .font(.system(size: 12, weight: .heavy)).lineLimit(1)
                    }
                    .foregroundStyle(superAttiva ? Tema.ambra : Tema.tenue)
                }
                HStack(alignment: .top, spacing: 12) {
                    Button(action: apri) {
                        HStack(alignment: .top, spacing: 12) {
                            MiniaturaEsercizio(ex: it.ex)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(e.n).font(.system(size: 18, weight: .bold)).foregroundStyle(Tema.testo).multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(e.m) · \(it.sets.count) × \(it.lo)–\(it.hi)\(sec ? "″" : "") · rec.\u{00A0}\(rec > 0 ? tempoMMSS(rec) : "subito l'altro")")
                                    .font(.system(size: 12)).foregroundStyle(Tema.tenue).multilineTextAlignment(.leading)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(e.n): esecuzione e progressi")
                    Spacer(minLength: 4)
                    if !sec {
                        Button(s.unita(it.ex)) { s.toccaUnita(it.ex) }
                            .font(.system(size: 14, weight: .heavy)).foregroundStyle(s.inLibbre(it.ex) ? Tema.inchiostro : Tema.testo)
                            .padding(.horizontal, 12).frame(height: 32)
                            .background(s.inLibbre(it.ex) ? AnyShapeStyle(Tema.ambra) : AnyShapeStyle(Tema.scheda2), in: Capsule())
                    }
                    // voci corte: con il testo grande del telefono quelle lunghe andavano a capo
                    Menu {
                        Section {
                            Button(action: apri) { Label("Esecuzione", systemImage: "figure.strengthtraining.traditional") }
                            Button { nota.toggle() } label: { Label(nota ? "Nascondi nota" : "Aggiungi nota", systemImage: "note.text") }
                        }
                        if inSuper {
                            Section {
                                Button { s.toccaSuperserie(a?.rid, it.sup) } label: {
                                    Label(superAttiva ? "Separa i due" : "Rimetti insieme", systemImage: superAttiva ? "link.badge.plus" : "link")
                                }
                            }
                        }
                        Section {
                            Button { s.spostaEsercizio(i, -1) } label: { Label("Sposta su", systemImage: "arrow.up") }
                            Button { s.spostaEsercizio(i, 1) } label: { Label("Sposta giù", systemImage: "arrow.down") }
                            Button(action: cambia) { Label("Cambia", systemImage: "arrow.triangle.2.circlepath") }
                        }
                        Section {
                            Button(role: .destructive) { s.togliEsercizio(i) } label: { Label("Togli", systemImage: "trash") }
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).frame(width: 32, height: 32).background(Tema.scheda2, in: Circle())
                    }
                    .foregroundStyle(Tema.testo)
                }
                Text(consiglio.testo).font(.system(size: 13, weight: .medium)).foregroundStyle(consiglio.su ? Tema.verde : Tema.tenue)
                if nota {
                    TextField("Nota (sedile, impugnatura, sensazioni…)", text: Binding(get: { it.note }, set: { s.nota(i, $0) }), axis: .vertical)
                        .font(.system(size: 14)).padding(10).background(Tema.scheda2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                HStack(spacing: 8) {
                    Text("Serie").frame(width: 34)
                    Text("Prima").frame(maxWidth: .infinity)
                    Text(sec ? "Timer" : s.unita(it.ex)).frame(width: 66)
                    Text(sec ? "sec" : "Rip").frame(width: 56)
                    Text("✓").frame(width: 44)
                }
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Tema.tenue)
                ForEach(Array(it.sets.enumerated()), id: \.offset) { j, st in
                    let etichetta: String = st.type == "n" ? "\(it.sets[0...j].filter { $0.type == "n" }.count)" : st.type.uppercased()
                    let ph = s.suggerito(it, j)
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Button { s.cambiaTipo(i, j) } label: {
                                Text(etichetta).font(.system(size: 14, weight: .heavy)).frame(width: 34, height: 34)
                                    .background(st.type == "n" ? Tema.scheda2 : Tema.ambra.opacity(0.35), in: Circle())
                            }
                            .foregroundStyle(Tema.testo)
                            Text(prec.flatMap { $0.sets[safe: j] }.map { sec ? "\($0.r ?? 0)″" : "\(s.peso(it.ex, $0.kg).isEmpty ? "–" : s.peso(it.ex, $0.kg)) × \($0.r ?? 0)" } ?? "—")
                                .font(.system(size: 13)).foregroundStyle(Tema.tenue).frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.7)
                            if sec {
                                // serie a tempo: «Via» fa partire il timer, che alla fine segna la serie da solo
                                Button { s.avviaTimer(i, j) } label: {
                                    Label("Via", systemImage: "play.fill").font(.system(size: 14, weight: .heavy))
                                        .foregroundStyle(st.done ? Tema.tenue : Tema.fondo)
                                        .frame(width: 62, height: 34)
                                        .background(st.done ? AnyShapeStyle(Tema.scheda2) : AnyShapeStyle(Tema.testo), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(st.done || s.timerSerie != nil)
                                .frame(width: 66)
                                .accessibilityLabel("Avvia il timer della serie \(j + 1)")
                            } else {
                                CampoNumero(valore: s.peso(it.ex, st.kg), segnaposto: s.peso(it.ex, ph.kg), decimali: true) { t in
                                    let v = Double(t.replacingOccurrences(of: ",", with: "."))
                                    s.scrivi(i, j, kg: .some(v.map { s.inLibbre(it.ex) ? kgFrom(lb: $0) : $0 }))
                                }
                                .frame(width: 66)
                            }
                            CampoNumero(valore: st.r.map(String.init) ?? "", segnaposto: String(ph.r), decimali: false) { t in
                                s.scrivi(i, j, r: .some(Int(t)))
                            }
                            .frame(width: 56)
                            Button { s.toccaSerie(i, j) } label: {
                                Image(systemName: "checkmark").font(.system(size: 17, weight: .heavy)).frame(width: 44, height: 40)
                                    .foregroundStyle(st.done ? Tema.inchiostro : Tema.tenue)
                                    .background(st.done ? AnyShapeStyle(Tema.verde) : AnyShapeStyle(Tema.scheda2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        if st.done && st.isWork {
                            HStack(spacing: 6) {
                                Text("Sforzo").font(.system(size: 12)).foregroundStyle(Tema.tenue)
                                ForEach([(1, "Facile"), (2, "Giusta"), (3, "Al limite")], id: \.0) { v, l in
                                    Button(l) { s.sforzo(i, j, v) }
                                        .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).frame(height: 26)
                                        .foregroundStyle(st.rpe == v ? Tema.inchiostro : Tema.tenue)
                                        .background(st.rpe == v ? AnyShapeStyle([Tema.verde, Tema.ambra, Tema.rosso][v - 1]) : AnyShapeStyle(Tema.scheda2), in: Capsule())
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .opacity(st.done ? 0.85 : 1)
                }
                HStack(spacing: 8) {
                    Button { s.aggiungiSerie(i) } label: { Label("Serie", systemImage: "plus") }.buttonStyle(PulsanteLeggero())
                    if it.sets.count > 1 { Button { s.togliSerie(i) } label: { Label("Serie", systemImage: "minus") }.buttonStyle(PulsanteLeggero()) }
                    Spacer()
                }
            }
        }
        // la superserie ha il bordo ambra: si distingue dalle serie normali anche scorrendo veloce
        .overlay {
            if inSuper && superAttiva {
                RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Tema.ambra.opacity(0.7), lineWidth: 1.5)
            }
        }
    }
}

// campo numerico con il testo suo: non si riscrive mentre digiti (così le virgole non spariscono) ma segue le modifiche che arrivano da fuori
struct CampoNumero: View {
    let valore: String
    let segnaposto: String
    let decimali: Bool
    let scrivi: (String) -> Void
    @State private var testo = ""
    @FocusState private var attivo: Bool

    var body: some View {
        TextField(segnaposto, text: $testo)
            .keyboardType(decimali ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 18, weight: .bold)).monospacedDigit()
            .focused($attivo)
            .frame(height: 40)
            .background(Tema.scheda2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onAppear { testo = valore }
            .onChange(of: testo) { _, t in if attivo { scrivi(t) } }
            .onChange(of: valore) { _, v in if !attivo { testo = v } }
    }
}

// scelta di un esercizio dalla libreria (per aggiungerlo o cambiarlo)
struct ElencoEsercizi: View {
    @EnvironmentObject var s: AppStore
    @Environment(\.dismiss) private var chiudi
    var scelto: (String) -> Void
    @State private var cerca = ""

    var body: some View {
        let tutti = s.piano.exlib.values.filter { cerca.isEmpty || $0.n.localizedCaseInsensitiveContains(cerca) || $0.m.localizedCaseInsensitiveContains(cerca) }
        let muscoli = Array(Set(tutti.map(\.m))).sorted()
        VStack(spacing: 0) {
            TestataFoglio(titolo: "Scegli l'esercizio", sotto: "\(s.piano.exlib.count) esercizi, divisi per muscolo", chiudi: { chiudi() })
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.tenue)
                TextField("Cerca un esercizio o un muscolo", text: $cerca).autocorrectionDisabled()
                if !cerca.isEmpty {
                    Button { cerca = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tema.tenue) }.accessibilityLabel("Cancella la ricerca")
                }
            }
            .campo()
            .padding(.horizontal, 20).padding(.bottom, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if muscoli.isEmpty {
                        Text("Nessun esercizio con «\(cerca)».").font(.system(size: 14)).foregroundStyle(Tema.tenue).padding(.top, 10)
                    }
                    ForEach(muscoli, id: \.self) { m in
                        TitoloFoglio(testo: m)
                        let lista = tutti.filter { $0.m == m }.sorted { $0.n < $1.n }
                        VStack(spacing: 0) {
                            ForEach(lista, id: \.id) { e in
                                if e.id != lista.first?.id { Rectangle().fill(Tema.linea).frame(height: 1).padding(.leading, 14) }
                                Button { scelto(e.id) } label: {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(e.n).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo).lineLimit(1)
                                            Text(e.eq).font(.system(size: 12)).foregroundStyle(Tema.tenue).lineLimit(1)
                                        }
                                        Spacer(minLength: 4)
                                        Image(systemName: "plus").font(.system(size: 13, weight: .heavy)).foregroundStyle(Tema.fondo)
                                            .frame(width: 28, height: 28).background(Tema.testo, in: Circle())
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 11).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Tema.fondo.ignoresSafeArea())
    }
}
