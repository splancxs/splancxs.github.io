import SwiftUI

// «Oggi», come nell'app di prima (giorno, anelli, «Adesso», la tua giornata) ma con i colori di Lift: grafite, argento, rosso.
struct OggiView: View {
    @EnvironmentObject var s: AppStore
    @State private var pasto: MealPlan?
    @State private var fuori: AperturaFuori?
    @State private var coach = false

    // quale finestra «fuori piano» aprire: al posto di un pasto (si) o in più, nuova o da modificare
    struct AperturaFuori: Identifiable { let id = UUID(); let si: Int?; let esistente: PastoFuori? }

    var body: some View {
        let plan = s.pianoOggi
        Pagina {
            testata(plan)
            cruscotto(plan)
            if let c = s.consiglioFuori() { consiglio(c) }
            adesso(plan)
            creatina
            giornata(plan)
        }
        .sheet(item: $pasto) { m in PastoSheet(di: s.oggiIdx, si: m.si, oggi: true).foglio() }
        .sheet(item: $fuori) { f in FuoriPianoSheet(si: f.si, esistente: f.esistente).foglio() }
        .sheet(isPresented: $coach) { CoachView().foglio() }
    }

    // dopo un pasto fuori piano: cosa cambiare nel resto della giornata
    private func consiglio(_ c: (testo: String, su: Bool)) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: c.su ? "scalemass.fill" : "checkmark.seal.fill").font(.system(size: 16, weight: .bold))
                .foregroundStyle(Tema.inchiostro).frame(width: 34, height: 34).background(c.su ? Tema.ambra : Tema.verde, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("RESTO DELLA GIORNATA").font(.sport(17)).foregroundStyle(Tema.tenue)
                Text(c.testo).font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background((c.su ? Tema.ambra : Tema.verde).opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // «Oggi la salto»: un menu con le icone che si apre dal pulsante stesso (niente avviso in mezzo allo schermo)
    private func menuSalto<L: View>(@ViewBuilder _ etichetta: () -> L) -> some View {
        Menu {
            Section("Niente palestra oggi: come mangi?") {
                Button { s.saltaPalestra(true, mangiaRiposo: true) } label: {
                    Label { Text("Come a riposo"); Text("I pasti passano a quelli OFF") } icon: { Image(systemName: "bed.double.fill") }
                }
                Button { s.saltaPalestra(true, mangiaRiposo: false) } label: {
                    Label { Text("Tieni il piano ON"); Text("I pasti restano quelli di oggi") } icon: { Image(systemName: "flame.fill") }
                }
            }
        } label: { etichetta() }
    }

    // MARK: testata e cruscotto

    private func testata(_ plan: DayPlan) -> some View {
        let tipo = plan.conv.isEmpty ? plan.day.type : plan.conv
        let etichetta: String = {
            if tipo.hasPrefix("ON") { return "ON · " + (s.schedaOggi.flatMap { s.routine($0)?.name } ?? "palestra") }
            if tipo == "FREE" { return "OFF · pasto libero" }
            return "OFF" + (tipo == "OFF_S" ? " · scuola" : tipo == "OFF_W" ? " · weekend" : "")
        }()
        return VStack(alignment: .leading, spacing: 6) {
            Text(Date().formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "it_IT"))))
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Tema.tenue)
            HStack(alignment: .center, spacing: 12) {
                Text(plan.day.name.uppercased()).font(.sport(54)).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                Button { coach = true } label: {
                    Label("Coach", systemImage: "sparkles").font(.system(size: 15, weight: .bold)).foregroundStyle(Tema.inchiostro)
                        .padding(.horizontal, 14).frame(height: 38).background(Argento(raggio: 19))
                }
                .accessibilityLabel("Apri il coach")
            }
            Text(etichetta).font(.sport(17)).padding(.horizontal, 12).padding(.vertical, 5)
                .foregroundStyle(tipo.hasPrefix("ON") ? Tema.inchiostro : tipo == "FREE" ? Tema.ambra : Tema.tenue)
                .background(tipo.hasPrefix("ON") ? AnyShapeStyle(Color(hex: 0xC4C6C5)) : AnyShapeStyle(tipo == "FREE" ? Tema.ambra.opacity(0.18) : Tema.scheda), in: Capsule())
        }
    }

    private func cruscotto(_ plan: DayPlan) -> some View {
        let t = s.totaliMangiati()
        return Scheda {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    ZStack {
                        Anello(valore: t.k, totale: plan.previsti.k, spessore: 12)
                        VStack(spacing: -2) {
                            Text("\(Int(t.k))").font(.sport(40)).monospacedDigit()
                            Text("di \(Int(plan.previsti.k)) kcal").font(.system(size: 12, weight: .medium)).foregroundStyle(Tema.tenue)
                        }
                    }
                    .frame(width: 128, height: 128)
                    VStack(alignment: .leading, spacing: 10) {
                        macro("Proteine", t.p, plan.dt.target[1], Tema.p)
                        macro("Carboidrati", t.c, plan.dt.target[2], Tema.c)
                        macro("Grassi", t.fa, plan.dt.target[3], Tema.g)
                    }
                }
                Text("\(Int(max(0, plan.previsti.k - t.k))) kcal").font(.system(size: 17, weight: .heavy)) + Text(" ancora da mangiare oggi").font(.system(size: 15)).foregroundColor(Tema.tenue)
                if plan.hasFree && !plan.meals.contains(where: { $0.free && s.fuoriPerFascia($0.si) != nil }) {
                    Text("Il pasto libero conta circa \(Int(stimaPastoLibero)) kcal: quando l'hai fatto, toccalo e segna cosa hai mangiato.")
                        .font(.system(size: 12)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func macro(_ nome: String, _ v: Double, _ obiettivo: Double, _ colore: Color) -> some View {
        HStack(spacing: 10) {
            Anello(valore: v, totale: obiettivo, spessore: 5, colore: colore).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(nome).font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.tenue)
                Text("\(Int(r0(v)))").font(.sport(21)).monospacedDigit() + Text(" / \(Int(obiettivo)) g").font(.system(size: 12)).foregroundColor(Tema.tenue)
            }
        }
    }

    // MARK: «Adesso»: la prossima cosa da fare, in argento

    private enum Voce { case pasto(MealPlan), palestra(Routine) }

    private func prossima(_ plan: DayPlan) -> (Voce, String)? {
        let ora = Calendar.current.component(.hour, from: Date()) * 60 + Calendar.current.component(.minute, from: Date())
        func minuti(_ t: String) -> Int { let p = t.split(separator: ":").compactMap { Int($0) }; return (p.first ?? 0) * 60 + (p.count > 1 ? p[1] : 0) }
        let fatti = Set(s.mangiati()).union(s.fuoriOggi().compactMap(\.si))   // anche i pasti sostituiti fuori piano
        var voci: [(Int, Voce, Bool)] = plan.meals.map { m in
            let t = minuti(m.time)
            return (t, .pasto(m), fatti.contains(m.si) || (m.free && ora > t + 150))
        }
        if let rid = s.schedaOggi, let r = s.routine(rid) { voci.append((minuti("16:30"), .palestra(r), s.fattoOggi(rid))) }
        voci.sort { $0.0 < $1.0 }
        guard let v = voci.first(where: { !$0.2 && $0.0 >= ora - 60 }) ?? voci.first(where: { !$0.2 }) else { return nil }
        let d = v.0 - ora
        let quando = d < -15 ? "da segnare" : d <= 0 ? "adesso" : d < 60 ? "tra \(d) min" : "tra \(d / 60) h \(String(format: "%02d", d % 60))"
        return (v.1, quando)
    }

    @ViewBuilder private func adesso(_ plan: DayPlan) -> some View {
        if s.d.active != nil {
            argento {
                VStack(alignment: .leading, spacing: 10) {
                    Text("In corso").font(.sport(17)).opacity(0.7)
                    Text(s.d.active?.name.uppercased() ?? "").font(.sport(40))
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(tempoMMSS(Int((Cal.ms() - (s.d.active?.start ?? Cal.ms())) / 1000))).font(.sport(26)).monospacedDigit()
                    }
                    Button("Riprendi l'allenamento") { s.tabAperta = 1 }.buttonStyle(PulsantePieno())
                }
            }
        } else if let (voce, quando) = prossima(plan) {
            switch voce {
            case .pasto(let m) where m.free:
                argento {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Adesso · \(quando)").font(.sport(17)).opacity(0.7)
                        Text("\(m.time) · PASTO LIBERO").font(.sport(34)).lineLimit(1).minimumScaleFactor(0.7)
                        Text("Fuori, senza pesare: un primo o un secondo con contorno, oppure una pizza. Circa \(Int(stimaPastoLibero)) kcal.")
                            .font(.system(size: 15, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                        Button("Segna cosa hai mangiato") { fuori = AperturaFuori(si: m.si, esistente: nil) }.buttonStyle(PulsantePieno())
                    }
                }
            case .pasto(let m):
                argento {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Adesso · \(quando)").font(.sport(17)).opacity(0.7)
                        Text("\(m.time) · \(m.label.uppercased())").font(.sport(34)).lineLimit(2).minimumScaleFactor(0.7)
                        Text("\(s.piano.recipe(m.code).name) · \(Int(m.tot.k)) kcal · P \(fmtNum(m.tot.p))").font(.system(size: 15, weight: .medium))
                        HStack(spacing: 10) {
                            Button("Segna come mangiato") { s.toccaMangiato(m.si) }.buttonStyle(PulsantePieno())
                            Button("Dettagli") { pasto = m }
                                .font(.system(size: 15, weight: .semibold)).padding(.horizontal, 16).frame(height: 50)
                                .background(Tema.inchiostro.opacity(0.14), in: Capsule())
                        }
                    }
                }
            case .palestra(let r):
                argento {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Adesso · \(quando)").font(.sport(17)).opacity(0.7)
                        HStack(alignment: .firstTextBaseline) {
                            Text("16:30 · \(r.name.uppercased())").font(.sport(34)).lineLimit(1).minimumScaleFactor(0.6)
                            Spacer()
                            Text(String(format: "%02d", (s.routines.firstIndex { $0.id == r.id } ?? 0) + 1)).font(.sport(64)).opacity(0.85)
                        }
                        Text("\(r.focus) · pesi ~60′ + tapis 15–20′").font(.system(size: 15, weight: .medium))
                        HStack(spacing: 10) {
                            Button { s.avvia(r.id) } label: { Label("Inizia", systemImage: "play.fill") }.buttonStyle(PulsantePieno())
                            menuSalto {
                                Text("Oggi la salto").foregroundStyle(Tema.inchiostro)
                                    .font(.system(size: 15, weight: .semibold)).padding(.horizontal, 16).frame(height: 50)
                                    .background(Tema.inchiostro.opacity(0.14), in: Capsule())
                            }
                        }
                    }
                }
            }
        } else {
            Scheda {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 28)).foregroundStyle(Tema.verde)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GIORNATA COMPLETATA").font(.sport(22))
                        Text("Hai segnato tutti i pasti\(s.schedaOggi != nil ? " e fatto l'allenamento" : ""). Domani si continua.").font(.system(size: 14)).foregroundStyle(Tema.tenue)
                    }
                }
            }
        }
    }

    private func argento<C: View>(@ViewBuilder _ contenuto: () -> C) -> some View {
        contenuto()
            .foregroundStyle(Tema.inchiostro)
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Argento())
    }

    // MARK: la tua giornata

    private func giornata(_ plan: DayPlan) -> some View {
        let mangiati = s.mangiati()
        return VStack(alignment: .leading, spacing: 10) {
            Text("LA TUA GIORNATA").font(.sport(26)).padding(.top, 6)
            VStack(spacing: 8) {
                ForEach(righeInOrdine(plan), id: \.self) { voce in
                    switch voce {
                    case .scuola: rigaSemplice("07:40", "Scuola fino alle 14:05 · i due panini nello zaino")
                    case .palestra: palestra
                    case .pasto(let si): if let m = plan.meals[safe: si] { riga(m, mangiati.contains(m.si)) }
                    case .extra(let id): if let f = s.fuoriOggi().first(where: { $0.id == id }) { rigaExtra(f) }
                    }
                }
                Button { fuori = AperturaFuori(si: nil, esistente: nil) } label: {
                    Label("Ho mangiato qualcos'altro", systemImage: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo)
                        .frame(maxWidth: .infinity, minHeight: 46).background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private enum RigaGiornata: Hashable { case scuola, palestra, pasto(Int), extra(String) }

    private func righeInOrdine(_ plan: DayPlan) -> [RigaGiornata] {
        var righe: [(String, RigaGiornata)] = plan.meals.map { ($0.time, .pasto($0.si)) }
        if s.oggiIdx <= 4 { righe.append(("07:40", .scuola)) }
        righe.append(("16:30", .palestra))
        for f in s.fuoriOggi() where f.si == nil { righe.append((Cal.fmtOra.string(from: Date(timeIntervalSince1970: f.t / 1000)), .extra(f.id))) }
        // a parità di orario la palestra viene prima del pasto (il post-workout è dopo)
        return righe.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 == .palestra }.map(\.1)
    }

    private func rigaSemplice(_ ora: String, _ testo: String) -> some View {
        HStack(spacing: 12) {
            Text(ora).font(.sport(20)).frame(width: 52, alignment: .leading).foregroundStyle(Tema.tenue)
            Text(testo).font(.system(size: 14)).foregroundStyle(Tema.tenue)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // la palestra è una riga come le altre, con i suoi pulsanti dentro
    @ViewBuilder private var palestra: some View {
        let ov = s.ov(s.oggiKey)
        let conv = s.pianoOggi.conv
        if s.d.active != nil, let a = s.d.active {
            rigaPalestra(titolo: "Palestra · \(a.name)", dettaglio: "in corso") { Button("Riprendi") { s.tabAperta = 1 }.buttonStyle(PulsanteLeggero()) }
        } else if let rid = s.schedaOggi, let r = s.routine(rid) {
            let fatto = s.fattoOggi(rid)
            rigaPalestra(titolo: "Palestra · \(r.name)", dettaglio: r.focus + (fatto ? " · fatta ✓" : "")) {
                if !fatto {
                    HStack(spacing: 8) {
                        Button { s.avvia(rid) } label: { Label("Inizia", systemImage: "play.fill") }.buttonStyle(PulsanteLeggero())
                        menuSalto {
                            Text("Oggi la salto").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo)
                                .padding(.horizontal, 14).frame(minHeight: 38).background(Tema.scheda2, in: Capsule())
                        }
                    }
                }
            }
        } else if ov?.skip == true {
            rigaPalestra(titolo: "Palestra saltata", dettaglio: conv.isEmpty ? "il piano dei pasti resta quello ON" : "oggi mangi come in un giorno di riposo (\(Int(s.pianoOggi.tot.k)) kcal)") {
                Button("Annulla: oggi mi alleno") { s.saltaPalestra(false) }.buttonStyle(PulsanteLeggero())
            }
        } else if conv == "ON" {
            rigaPalestra(titolo: "Palestra · recupero", dettaglio: "scegli la scheda in Scheda") {
                HStack(spacing: 8) {
                    Button("Apri Scheda") { s.tabAperta = 1 }.buttonStyle(PulsanteLeggero())
                    Button("Torna al piano OFF") { s.recuperaAllenamento(false) }.buttonStyle(PulsanteLeggero())
                }
            }
        } else if s.piano.week[s.oggiIdx].type == "OFF_S" {
            rigaPalestra(titolo: "Giorno di riposo", dettaglio: "") {
                Button("Oggi recupero un allenamento") { s.recuperaAllenamento(true) }.buttonStyle(PulsanteLeggero())
            }
        }
    }

    private func rigaPalestra<A: View>(titolo: String, dettaglio: String, @ViewBuilder azioni: () -> A) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("16:30").font(.sport(20)).frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text(titolo).font(.system(size: 17, weight: .bold))
                if !dettaglio.isEmpty { Text(dettaglio).font(.system(size: 13)).foregroundStyle(Tema.tenue) }
                azioni()
            }
            Spacer(minLength: 0)
        }
        .padding(14).background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // un pasto fuori piano in più (non al posto di un pasto del piano)
    private func rigaExtra(_ f: PastoFuori) -> some View {
        Button { fuori = AperturaFuori(si: nil, esistente: f) } label: {
            HStack(spacing: 12) {
                Text(Cal.fmtOra.string(from: Date(timeIntervalSince1970: f.t / 1000))).font(.sport(20)).frame(width: 52, alignment: .leading).foregroundStyle(Tema.tenue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fuori piano").font(.system(size: 17, weight: .bold)).foregroundStyle(Tema.testo)
                    Text(f.nome).font(.system(size: 13)).foregroundStyle(Tema.tenue).lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(f.tot.k))").font(.sport(24)).monospacedDigit().foregroundStyle(Tema.ambra)
                    Text("P \(fmtNum(r1(f.tot.p)))").font(.system(size: 11)).foregroundStyle(Tema.tenue)
                }
                Image(systemName: "fork.knife").font(.system(size: 15, weight: .bold)).frame(width: 40, height: 40)
                    .foregroundStyle(Tema.inchiostro).background(Tema.ambra, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func riga(_ m: MealPlan, _ mangiato: Bool) -> some View {
        if let f = s.fuoriPerFascia(m.si) { return AnyView(rigaSostituita(m, f)) }
        return AnyView(rigaPiano(m, mangiato))
    }

    // un pasto del piano sostituito da quello che hai mangiato davvero
    private func rigaSostituita(_ m: MealPlan, _ f: PastoFuori) -> some View {
        Button { fuori = AperturaFuori(si: m.si, esistente: f) } label: {
            HStack(spacing: 12) {
                Text(m.time).font(.sport(20)).frame(width: 52, alignment: .leading).foregroundStyle(Tema.tenue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.label.components(separatedBy: " (").first ?? m.label).font(.system(size: 17, weight: .bold)).foregroundStyle(Tema.testo).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(m.free ? "LIBERO" : "FUORI PIANO").font(.system(size: 10, weight: .heavy)).foregroundStyle(Tema.inchiostro)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Tema.ambra, in: Capsule())
                        Text(f.nome).font(.system(size: 13)).foregroundStyle(Tema.tenue).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(f.tot.k))").font(.sport(24)).monospacedDigit().foregroundStyle(Tema.testo)
                    Text("P \(fmtNum(r1(f.tot.p)))").font(.system(size: 11)).foregroundStyle(Tema.tenue)
                }
                Image(systemName: "checkmark").font(.system(size: 16, weight: .heavy)).frame(width: 40, height: 40)
                    .foregroundStyle(Tema.inchiostro).background(Tema.ambra, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func rigaPiano(_ m: MealPlan, _ mangiato: Bool) -> some View {
        HStack(spacing: 12) {
            Text(m.time).font(.sport(20)).frame(width: 52, alignment: .leading).foregroundStyle(mangiato ? Tema.tenue : Tema.testo)
            Button { if m.free { fuori = AperturaFuori(si: m.si, esistente: nil) } else { pasto = m } } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.free ? "Pasto libero" : m.label.components(separatedBy: " (").first ?? m.label).font(.system(size: 17, weight: .bold)).foregroundStyle(Tema.testo).lineLimit(1)
                        if m.free {
                            Text("Fuori, senza pesare · circa \(Int(stimaPastoLibero)) kcal").font(.system(size: 13)).foregroundStyle(Tema.tenue).lineLimit(1)
                        } else {
                            // una sola icona (il cibo principale) in un tondo, poi il nome del piatto
                            HStack(spacing: 6) {
                                Text(s.piano.iconaPiatto(m.lines)).font(.system(size: 12)).frame(width: 22, height: 22).background(Tema.scheda2, in: Circle())
                                Text(s.piano.recipe(m.code).name).font(.system(size: 13)).foregroundStyle(Tema.tenue).lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 6)
                    if !m.free {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(Int(m.tot.k))").font(.sport(24)).monospacedDigit().foregroundStyle(Tema.testo)
                            Text("P \(fmtNum(m.tot.p))").font(.system(size: 11)).foregroundStyle(Tema.tenue)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            if !m.free {
                Button { s.toccaMangiato(m.si) } label: {
                    Image(systemName: "checkmark").font(.system(size: 16, weight: .heavy)).frame(width: 40, height: 40)
                        .foregroundStyle(mangiato ? Tema.inchiostro : Tema.tenue)
                        .background(mangiato ? AnyShapeStyle(Tema.verde) : AnyShapeStyle(Tema.scheda2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityLabel("Segna \(m.label) come mangiato")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(mangiato ? 0.65 : 1)
        .contextMenu {
            if !m.free {
                Button { fuori = AperturaFuori(si: m.si, esistente: nil) } label: { Label("Ho mangiato altro", systemImage: "fork.knife") }
                Button { pasto = m } label: { Label("Dettagli e scambio", systemImage: "list.bullet") }
            }
        }
    }

    private var creatina: some View {
        let presa = s.creatinaPresa()
        let serie = s.serieCreatina()
        return Button { s.toccaCreatina() } label: {
            HStack(spacing: 12) {
                Image(systemName: "pills.fill").font(.system(size: 20)).frame(width: 52, alignment: .leading).foregroundStyle(Tema.tenue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CREATINA · 3–5 G").font(.sport(19)).foregroundStyle(Tema.testo)
                    Text(presa ? "Presa oggi" + (serie > 1 ? " · \(serie) giorni di fila" : "") : "Ogni giorno, a qualsiasi ora").font(.system(size: 13)).foregroundStyle(Tema.tenue)
                }
                Spacer()
                Image(systemName: "checkmark").font(.system(size: 16, weight: .heavy)).frame(width: 40, height: 40)
                    .foregroundStyle(presa ? Tema.inchiostro : Tema.tenue)
                    .background(presa ? AnyShapeStyle(Tema.verde) : AnyShapeStyle(Tema.scheda2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
