import SwiftUI
import UniformTypeIdentifiers

// «Profilo», come le Impostazioni dell'iPhone: il piano in argento in cima, poi gruppi di righe con un'icona colorata,
// un titolo corto (non va a capo) e l'interruttore o il valore a destra.
struct ProfiloView: View {
    @EnvironmentObject var s: AppStore
    @State private var importa = false
    @State private var messaggio = ""
    @State private var libbreAperto = false

    // promemoria: chiave, icona, colore, titolo, sottotitolo
    private let promemoria: [(String, String, Color, String, String)] = [
        ("merenda", "takeoutbag.and.cup.and.straw.fill", Tema.ambra, "Panini di domani", "Alle 21:00, con gli ingredienti in grammi"),
        ("peso", "scalemass.fill", Tema.verde, "Pesata", "Al mattino, a digiuno"),
        ("palestra", "dumbbell.fill", Tema.rosso, "Palestra", "Alle 16:00 nei giorni ON"),
        ("creatina", "pills.fill", Tema.g, "Creatina", "Se non l'hai ancora segnata"),
        ("riepilogo", "chart.bar.fill", Color(hex: 0x9B7BFF), "Riepilogo della domenica", "Alle 20:00, la settimana in numeri"),
    ]
    @State private var coach = false

    var body: some View {
        Pagina {
            Text("PROFILO").font(.sport(48))
            piano

            Titolo(testo: "Dati")
            gruppo {
                Button { importa = true } label: {
                    riga("square.and.arrow.down.fill", Tema.g, "Importa backup", "Da un file salvato") { freccia }
                }
                .buttonStyle(.plain)
                divisore
                ShareLink(item: FileBackup(), preview: SharePreview("Backup di Recomp")) {
                    riga("square.and.arrow.up.fill", Tema.verde, "Esporta backup", "Un file da tenere al sicuro") { freccia }
                }
                .buttonStyle(.plain)
                divisore
                Button { messaggio = s.migraDalSito(forza: true) } label: {
                    riga("arrow.triangle.2.circlepath", Color(hex: 0x8E8E93), "Dati dell'app di prima", "Riprende pesi e allenamenti del sito") { freccia }
                }
                .buttonStyle(.plain)
                if s.salute_disponibile {
                    divisore
                    riga("heart.fill", Tema.rosso, "Salute", "Peso e pasti con l'app Salute") {
                        Toggle("", isOn: Binding(get: { s.d.salute }, set: { s.collegaSalute($0) })).labelsHidden()
                    }
                }
            }
            if !messaggio.isEmpty { Text(messaggio).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.verde).padding(.horizontal, 4) }

            Titolo(testo: "Coach")
            gruppo {
                Button { coach = true } label: {
                    riga("sparkles", Color(hex: 0x5E5CE6), "Coach AI", ChiaveCoach.leggi() != nil ? "Collegato · " + FornitoreCoach.attuale.nome : "Da collegare (Gemini è gratis)") { freccia }
                }
                .buttonStyle(.plain)
            }

            Titolo(testo: "Promemoria")
            gruppo {
                ForEach(Array(promemoria.enumerated()), id: \.offset) { i, p in
                    if i > 0 { divisore }
                    riga(p.1, p.2, p.3, p.4) {
                        Toggle("", isOn: Binding(get: { s.d.promemoria[p.0] == true }, set: { s.impostaPromemoria(p.0, $0) })).labelsHidden()
                    }
                }
                if s.d.promemoria["creatina"] == true {
                    divisore
                    riga("clock.fill", Color(hex: 0x8E8E93), "Ora della creatina", nil) {
                        DatePicker("", selection: Binding(get: { Cal.fmtOra.date(from: s.d.creaOra) ?? Date() },
                                                          set: { s.d.creaOra = Cal.fmtOra.string(from: $0); s.riprogrammaPromemoria() }),
                                   displayedComponents: .hourAndMinute).labelsHidden()
                    }
                }
            }

            Titolo(testo: "Allenamento")
            gruppo {
                riga("timer", Color(hex: 0xFF9F43), "Fine recupero", "Notifica anche a schermo bloccato") {
                    Toggle("", isOn: $s.d.notifRest).labelsHidden()
                }
                divisore
                riga("calendar", Color(hex: 0x9B7BFF), "Inizio del blocco", "Ora settimana \(s.blocco.n) di 7") {
                    DatePicker("", selection: Binding(get: { Cal.date(s.d.blockStart) }, set: { s.d.blockStart = Cal.key($0) }), displayedComponents: .date)
                        .labelsHidden().environment(\.locale, Locale(identifier: "it_IT"))
                }
                divisore
                libbre
            }

        }
        .tint(Tema.verde)
        .sheet(isPresented: $coach) { CoachView().foglio() }
        .fileImporter(isPresented: $importa, allowedContentTypes: [.json, .plainText, .data]) { risultato in
            guard case .success(let url) = risultato else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { messaggio = s.importaBackup(data) } else { messaggio = "Non riesco a leggere il file." }
        }
    }

    // MARK: il piano, in argento

    private var piano: some View {
        let on = s.piano.daytypes["ON"]?.target ?? [], off = s.piano.daytypes["OFF_S"]?.target ?? []
        let b = s.blocco
        return VStack(alignment: .leading, spacing: 14) {
            Text("IL TUO PIANO").font(.sport(17)).opacity(0.7)
            HStack(alignment: .top, spacing: 0) {
                cifra(fmtMigliaia(on[safe: 0] ?? 0), "kcal giorni ON")
                cifra(fmtMigliaia(off[safe: 0] ?? 0), "kcal giorni OFF")
                cifra("\(Int(on[safe: 1] ?? 0)) g", "proteine")
            }
            Text("4 allenamenti a settimana · blocco \(b.ciclo), settimana \(b.n) di 7").font(.system(size: 14, weight: .medium)).opacity(0.75)
        }
        .foregroundStyle(Tema.inchiostro)
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(Argento())
    }

    private func cifra(_ v: String, _ u: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.sport(32)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(u).font(.system(size: 12, weight: .semibold)).opacity(0.65).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: esercizi in libbre (si apre e si chiude)

    @ViewBuilder private var libbre: some View {
        let esercizi = Array(Set(s.routines.flatMap { $0.items.map(\.ex) })).sorted { s.esercizio($0).n < s.esercizio($1).n }.filter { s.esercizio($0).unit != "sec" }
        let inLb = esercizi.filter { s.inLibbre($0) }.count
        Button { withAnimation(.easeInOut(duration: 0.2)) { libbreAperto.toggle() } } label: {
            riga("scalemass", Color(hex: 0x3CC7C1), "Esercizi in libbre", inLb == 0 ? "Nessuno: tutto in kg" : "\(inLb) \(inLb == 1 ? "esercizio" : "esercizi") in lb") {
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(Tema.tenue)
                    .rotationEffect(.degrees(libbreAperto ? 180 : 0))
            }
        }
        .buttonStyle(.plain)
        if libbreAperto {
            VStack(alignment: .leading, spacing: 10) {
                Text("Per i macchinari con i pesi in libbre. Vale su iPhone e orologio; si cambia anche durante l'allenamento.")
                    .font(.system(size: 12)).foregroundStyle(Tema.tenue)
                ForEach(esercizi, id: \.self) { ex in
                    Toggle(isOn: Binding(get: { s.inLibbre(ex) }, set: { s.impostaUnita(ex, lb: $0) })) {
                        Text(s.esercizio(ex).n).font(.system(size: 14))
                    }
                }
            }
            .padding(.leading, 44).padding(.bottom, 10)
        }
    }

    // MARK: pezzi delle righe

    private func gruppo<C: View>(@ViewBuilder _ contenuto: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { contenuto() }
            .padding(.horizontal, 16).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var divisore: some View { Rectangle().fill(Tema.linea).frame(height: 1).padding(.leading, 44) }

    private var freccia: some View { Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Tema.tenue) }

    private func riga<Fine: View>(_ icona: String, _ colore: Color, _ titolo: String, _ sotto: String?, @ViewBuilder fine: () -> Fine) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icona).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32).background(colore, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(titolo).font(.system(size: 16, weight: .semibold)).foregroundStyle(Tema.testo).lineLimit(1).minimumScaleFactor(0.85)
                if let sotto { Text(sotto).font(.system(size: 12)).foregroundStyle(Tema.tenue).lineLimit(1).minimumScaleFactor(0.85) }
            }
            Spacer(minLength: 8)
            fine()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
