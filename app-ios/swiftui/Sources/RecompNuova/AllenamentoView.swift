import SwiftUI

// «Allenamento»: se ce n'è uno in corso si vede quello; se no le schede, lo storico e i numeri.
struct AllenamentoView: View {
    @EnvironmentObject var s: AppStore
    @State private var sezione = 0
    @State private var dettaglio: Workout?

    var body: some View {
        if s.d.active != nil {
            SchedaAttivaView()
        } else {
            Pagina {
                Text("SCHEDA").font(.sport(48))
                Picker("Sezione", selection: $sezione) {
                    Text("Schede").tag(0); Text("Storico").tag(1); Text("Numeri").tag(2)
                }
                .pickerStyle(.segmented)
                switch sezione {
                case 1: storico
                case 2: NumeriView()
                default: schede
                }
            }
            .sheet(item: $dettaglio) { w in DettaglioAllenamento(w: w).foglio() }
        }
    }

    // MARK: schede

    private var schede: some View { SchedeLista() }

    // MARK: storico: gli allenamenti raggruppati per settimana, una riga compatta ciascuno

    @ViewBuilder private var storico: some View {
        let lista = Array(s.cronologia.prefix(80))
        if lista.isEmpty {
            Scheda { Text("Qui compariranno i tuoi allenamenti completati.").foregroundStyle(Tema.tenue) }
        }
        ForEach(settimane(lista), id: \.0) { settimana in
            let lunedi = settimana.0, ws = settimana.1
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(titoloSettimana(lunedi).uppercased()).font(.sport(20)).foregroundStyle(Tema.tenue)
                    Spacer()
                    Text("\(ws.count) \(ws.count == 1 ? "allenamento" : "allenamenti") · \(fmtMigliaia(ws.reduce(0) { $0 + $1.volume })) kg")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.tenue)
                }
                VStack(spacing: 0) {
                    ForEach(Array(ws.enumerated()), id: \.element.id) { n, w in
                        rigaStorico(w)
                        if n < ws.count - 1 { Rectangle().fill(Tema.linea).frame(height: 1).padding(.leading, 58) }
                    }
                }
                .padding(.horizontal, 14)
                .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private func settimane(_ lista: [Workout]) -> [(Date, [Workout])] {
        var out: [(Date, [Workout])] = []
        for w in lista {
            let giorno = Date(timeIntervalSince1970: w.start / 1000)
            let lun = Cal.lunedi(giorno)
            if let k = out.firstIndex(where: { $0.0 == lun }) { out[k].1.append(w) } else { out.append((lun, [w])) }
        }
        return out
    }

    private func titoloSettimana(_ lunedi: Date) -> String {
        if lunedi == Cal.lunedi() { return "Questa settimana" }
        if lunedi == Cal.lunedi(indietro: 1) { return "Settimana scorsa" }
        return "\(Cal.testo(lunedi, "d MMM")) – \(Cal.testo(Cal.giorni(6, da: lunedi), "d MMM"))"
    }

    private func rigaStorico(_ w: Workout) -> some View {
        let giorno = Date(timeIntervalSince1970: w.start / 1000)
        return Button { dettaglio = w } label: {
            HStack(spacing: 12) {
                VStack(spacing: -2) {
                    Text(Cal.testo(giorno, "d")).font(.sport(24)).monospacedDigit()
                    Text(Cal.testo(giorno, "EEE").uppercased()).font(.system(size: 10, weight: .heavy)).foregroundStyle(Tema.tenue)
                }
                .frame(width: 44, height: 46).background(Tema.scheda2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(w.name).font(.system(size: 17, weight: .bold)).foregroundStyle(Tema.testo).lineLimit(1)
                    Text("\(w.minutes)′ · \(w.workSets) serie · \(fmtMigliaia(w.volume)) kg").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tema.tenue).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    if !w.prs.isEmpty {
                        Text("🏆 \(w.prs.count)").font(.system(size: 12, weight: .heavy)).foregroundStyle(Tema.testo)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Tema.ambra.opacity(0.22), in: Capsule())
                    }
                    if let hr = w.hr { Text("♥ \(hr)").font(.system(size: 11, weight: .bold)).foregroundStyle(Tema.rosso) }
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Tema.tenue)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// «Inizia»: conferma in un menu con le icone, attaccato al pulsante (parte anche sull'orologio)
struct MenuInizia<L: View>: View {
    @EnvironmentObject var s: AppStore
    let r: Routine
    @ViewBuilder var etichetta: L
    var body: some View {
        Menu {
            Section("\(r.name) · \(r.items.count) esercizi") {
                Button { s.avvia(r.id) } label: {
                    Label { Text("Inizia ora"); Text("Parte anche sull'orologio") } icon: { Image(systemName: "play.fill") }
                }
            }
        } label: { etichetta }
    }
}

// «Numeri»: serie per muscolo (questa settimana o la scorsa) con una barra verso l'obiettivo,
// poi i record raggruppati per muscolo, una riga compatta per esercizio (si tocca per esecuzione e progressi)
struct NumeriView: View {
    @EnvironmentObject var s: AppStore
    @State private var aperto: IdEsercizio?
    @State private var scorsa = false

    private func serieSettimana(_ indietro: Int) -> [String: Int] {
        let lun = Cal.lunedi(indietro: indietro)
        let da = Cal.ms(lun), a = Cal.ms(Cal.giorni(7, da: lun))
        var serie: [String: Int] = [:]
        for w in s.cronologia where w.start >= da && w.start < a {
            for it in w.items { serie[s.esercizio(it.ex).m, default: 0] += it.sets.filter(\.isWork).count }
        }
        return serie
    }

    var body: some View {
        let serie = serieSettimana(scorsa ? 1 : 0)
        let muscoli = Array(Set(s.piano.muscleTargets.keys).union(serie.keys)).sorted()
        let fatte = serie.values.reduce(0, +), obiettivo = s.piano.muscleTargets.values.reduce(0, +)
        let esercizi = Array(Set(s.cronologia.flatMap { $0.items.map(\.ex) }))
        let gruppi = Dictionary(grouping: esercizi) { s.esercizio($0).m }
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Text("SERIE PER MUSCOLO").font(.sport(22))
                    Spacer()
                    Picker("Settimana", selection: $scorsa) { Text("Questa").tag(false); Text("Scorsa").tag(true) }
                        .pickerStyle(.segmented).frame(width: 150)
                }
                Text("\(fatte) serie su \(obiettivo) di obiettivo \(scorsa ? "la settimana scorsa" : "questa settimana")")
                    .font(.system(size: 12)).foregroundStyle(Tema.tenue)
                Scheda(padding: 16) {
                    VStack(spacing: 11) {
                        ForEach(muscoli, id: \.self) { m in
                            let v = serie[m] ?? 0
                            let t = s.piano.muscleTargets[m] ?? 0
                            HStack(spacing: 10) {
                                Text(m).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8).frame(width: 118, alignment: .leading)
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Tema.scheda2)
                                        Capsule().fill(t > 0 && v >= t ? Tema.verde : Tema.testo)
                                            .frame(width: v == 0 ? 0 : max(8, g.size.width * min(1, Double(v) / Double(max(1, t)))))
                                    }
                                }
                                .frame(height: 8)
                                Text("\(v)").font(.system(size: 14, weight: .heavy)).monospacedDigit()
                                    + Text(t > 0 ? "/\(t)" : "").font(.system(size: 12)).foregroundColor(Tema.tenue)
                            }
                        }
                    }
                }
            }
            if esercizi.isEmpty {
                Scheda { Text("Completa il primo allenamento per vedere i record.").foregroundStyle(Tema.tenue) }
            } else {
                Titolo(testo: "Record per esercizio")
                ForEach(gruppi.keys.sorted(), id: \.self) { m in
                    let lista = (gruppi[m] ?? []).sorted { s.nomeBreve($0) < s.nomeBreve($1) }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(m.uppercased()).font(.sport(18)).foregroundStyle(Tema.tenue)
                        VStack(spacing: 0) {
                            ForEach(Array(lista.enumerated()), id: \.element) { n, ex in
                                rigaRecord(ex)
                                if n < lista.count - 1 { Rectangle().fill(Tema.linea).frame(height: 1).padding(.leading, 54) }
                            }
                        }
                        .padding(.horizontal, 14)
                        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            }
        }
        .sheet(item: $aperto) { x in EsercizioSheet(ex: x.id).foglio() }
    }

    private func rigaRecord(_ ex: String) -> some View {
        let r = s.primati(ex)
        let sec = s.esercizio(ex).unit == "sec"
        return Button { aperto = IdEsercizio(id: ex) } label: {
            HStack(spacing: 12) {
                MiniaturaEsercizio(ex: ex, lato: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.esercizio(ex).n).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo).lineLimit(1).minimumScaleFactor(0.75)
                    if !sec { Text("1RM ≈ \(s.pesoConUnita(ex, r1(r.e1)))").font(.system(size: 11)).foregroundStyle(Tema.tenue) }
                }
                Spacer(minLength: 6)
                Text(sec ? "\(r.sec)″" : s.pesoConUnita(ex, r.kg)).font(.sport(22)).monospacedDigit().foregroundStyle(Tema.testo).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Tema.tenue)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// un allenamento fatto: in alto chiudi e «•••» (elimina), il nome grande, i numeri in un riquadro, i muscoli;
// poi un riquadro per esercizio con i suoi record 🏆 e le serie (la migliore evidenziata). Si tocca l'esercizio per esecuzione e progressi.
struct DettaglioAllenamento: View {
    @EnvironmentObject var s: AppStore
    @Environment(\.dismiss) private var chiudi
    let w: Workout
    @State private var esercizio: IdEsercizio?

    var body: some View {
        let muscoli = Array(Set(w.items.map { s.esercizio($0.ex).m })).sorted()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Menu {
                        Section("Togliere dalla cronologia?") {
                            Button(role: .destructive) { s.eliminaAllenamento(w.id); chiudi() } label: { Label("Elimina allenamento", systemImage: "trash") }
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).frame(width: 34, height: 34).background(Tema.scheda, in: Circle())
                    }
                    .foregroundStyle(Tema.testo)
                    Spacer()
                    Button { chiudi() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 34, height: 34).background(Tema.scheda, in: Circle()) }
                        .foregroundStyle(Tema.testo).accessibilityLabel("Chiudi")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(maiuscolaIniziale(Cal.testo(Date(timeIntervalSince1970: w.start / 1000), "EEEE d MMMM · HH:mm")))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.tenue)
                    Text(w.name.uppercased()).font(.sport(52)).lineLimit(1).minimumScaleFactor(0.6)
                }
                numeri
                FlowLayout(spacing: 6) {
                    ForEach(muscoli, id: \.self) { m in
                        Text(m).font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.tenue)
                            .padding(.horizontal, 10).padding(.vertical, 5).background(Tema.scheda, in: Capsule())
                    }
                }
                if !w.prs.isEmpty {
                    Text("🏆 \(w.prs.count) \(w.prs.count == 1 ? "record" : "record") in questo allenamento").font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Tema.ambra.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                ForEach(Array(w.items.enumerated()), id: \.offset) { _, it in carta(it) }
            }
            .padding(20)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .sheet(item: $esercizio) { x in EsercizioSheet(ex: x.id).foglio() }
    }

    // minuti, volume, serie (e battito, kcal) in un solo riquadro
    private var numeri: some View {
        var voci: [(String, String)] = [("\(w.minutes)′", "durata"), (fmtMigliaia(w.volume), "kg di volume"), ("\(w.workSets)", "serie")]
        if let hr = w.hr { voci.append(("\(hr)", "bpm medi")) }
        return HStack(spacing: 0) {
            ForEach(Array(voci.enumerated()), id: \.offset) { n, v in
                if n > 0 { Rectangle().fill(Tema.linea).frame(width: 1, height: 36) }
                VStack(spacing: 0) {
                    Text(v.0).font(.sport(28)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text(v.1).font(.system(size: 11, weight: .semibold)).foregroundStyle(Tema.tenue).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 14)
        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func carta(_ it: ItemRec) -> some View {
        let e = s.esercizio(it.ex)
        let sec = e.unit == "sec"
        let record = w.prs.filter { $0.ex == it.ex }
        let lavoro = it.sets.enumerated().filter { $0.element.type == "n" }
        let migliore = sec ? nil : lavoro.max { e1rm($0.element.kg ?? 0, $0.element.r ?? 0) < e1rm($1.element.kg ?? 0, $1.element.r ?? 0) }?.offset
        return VStack(alignment: .leading, spacing: 10) {
            Button { esercizio = IdEsercizio(id: it.ex) } label: {
                HStack(spacing: 12) {
                    MiniaturaEsercizio(ex: it.ex, lato: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.n).font(.system(size: 16, weight: .bold)).foregroundStyle(Tema.testo).lineLimit(1).minimumScaleFactor(0.75)
                        Text(e.m).font(.system(size: 12)).foregroundStyle(Tema.tenue)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Tema.tenue)
                }
            }
            .buttonStyle(.plain)
            if !record.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(record, id: \.self) { p in
                        (Text("🏆 ") + Text(p.k).foregroundColor(Tema.tenue) + Text(" " + valore(p)).bold())
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 9).padding(.vertical, 5).background(Tema.ambra.opacity(0.16), in: Capsule())
                    }
                }
            }
            if !it.note.isEmpty { Text("📝 \(it.note)").font(.system(size: 13)).foregroundStyle(Tema.tenue) }
            VStack(spacing: 4) {
                ForEach(Array(it.sets.enumerated()), id: \.offset) { j, st in
                    let top = j == migliore
                    HStack(spacing: 10) {
                        Text(st.type == "n" ? "\(it.sets[0...j].filter { $0.type == "n" }.count)" : st.type.uppercased())
                            .font(.system(size: 12, weight: .heavy)).foregroundStyle(top ? Tema.inchiostro : Tema.tenue)
                            .frame(width: 26, height: 26).background(top ? AnyShapeStyle(Tema.testo) : AnyShapeStyle(Tema.scheda2), in: Circle())
                        Text(sec ? "\(st.r ?? 0)″" : "\(s.pesoConUnita(it.ex, st.kg)) × \(st.r ?? 0)").font(.system(size: 16, weight: .bold)).monospacedDigit()
                        Spacer()
                        if let kg = st.kg, let r = st.r, st.type == "n", !sec {
                            Text("1RM ≈ \(s.pesoConUnita(it.ex, r1(e1rm(kg, r))))").font(.system(size: 12)).foregroundStyle(Tema.tenue).monospacedDigit()
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // i record salvati dicono «17,5 kg»: per gli esercizi in libbre li riscrivo in lb
    private func valore(_ p: RecordPR) -> String {
        guard s.inLibbre(p.ex), p.v.hasSuffix(" kg"),
              let n = Double(p.v.dropLast(3).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")) else { return p.v }
        return "\(fmtNum(lbFrom(kg: n))) lb"
    }
}

// riepilogo subito dopo «Termina»
struct RiepilogoView: View {
    @EnvironmentObject var s: AppStore
    @Environment(\.dismiss) private var chiudi
    let w: Workout
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Allenamento completato").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.tenue)
                Text(w.name).font(.system(size: 40, weight: .heavy))
                HStack(spacing: 10) {
                    cifra("\(w.minutes)", "minuti"); cifra(fmtMigliaia(w.volume), "kg"); cifra("\(w.workSets)", "serie")
                }
                if let hr = w.hr { Text("♥ battito medio \(hr)\(w.kcal.map { " · \($0) kcal attive" } ?? "")").font(.system(size: 15, weight: .semibold)) }
                if w.prs.isEmpty {
                    Text("Nessun nuovo record questa volta: la costanza è quello che conta.").foregroundStyle(Tema.tenue)
                } else {
                    Titolo(testo: "🏆 Record personali (\(w.prs.count))")
                    ElencoRecord(prs: w.prs)
                }
                Button("Fatto") { chiudi() }.buttonStyle(PulsantePieno(colore: Tema.testo, testo: Tema.fondo))
            }
            .padding(20)
        }
        .background(Tema.fondo.ignoresSafeArea())
    }
    private func cifra(_ v: String, _ u: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.system(size: 28, weight: .heavy)).monospacedDigit()
            Text(u).font(.system(size: 12)).foregroundStyle(Tema.tenue)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Tema.scheda, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// i record di un allenamento: un riquadro per esercizio (non uno per record), con il peso nell'unità dell'esercizio
struct ElencoRecord: View {
    @EnvironmentObject var s: AppStore
    let prs: [RecordPR]

    var body: some View {
        var visti = Set<String>()
        let esercizi = prs.map(\.ex).filter { visti.insert($0).inserted }   // nell'ordine in cui compaiono
        return VStack(spacing: 8) {
            ForEach(esercizi, id: \.self) { ex in
                VStack(alignment: .leading, spacing: 8) {
                    Text(s.esercizio(ex).n).font(.system(size: 16, weight: .semibold))
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(prs.filter { $0.ex == ex }, id: \.self) { p in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(valore(p)).font(.system(size: 19, weight: .heavy)).monospacedDigit()
                                Text(p.k).font(.system(size: 11)).foregroundStyle(Tema.tenue)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // i record salvati dicono «17,5 kg» o «1.044 kg»: per gli esercizi in libbre li riscrivo in lb
    private func valore(_ p: RecordPR) -> String {
        guard s.inLibbre(p.ex), p.v.hasSuffix(" kg"),
              let n = Double(p.v.dropLast(3).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")) else { return p.v }
        return "\(fmtNum(lbFrom(kg: n))) lb"
    }
}
