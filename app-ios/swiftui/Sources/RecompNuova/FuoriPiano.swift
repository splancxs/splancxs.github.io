import SwiftUI
import VisionKit

// Pasto fuori piano: segni cosa hai mangiato davvero (cibi del piano, prodotti di Open Food Facts cercati per nome o con il
// codice a barre, oppure scritti a mano) al posto di un pasto o in più. I totali di oggi lo contano, e se hai sforato
// l'app dice cosa togliere dal pasto che resta.

extension AppStore {
    func fuoriOggi() -> [PastoFuori] { d.fuori[oggiKey] ?? [] }
    func fuoriPerFascia(_ si: Int) -> PastoFuori? { fuoriOggi().first { $0.si == si } }

    func salvaFuori(_ f: PastoFuori) {
        let key = oggiKey
        var lista = d.fuori[key] ?? []
        lista.removeAll { $0.id == f.id || (f.si != nil && $0.si == f.si) }
        lista.append(f)
        d.fuori[key] = lista
        // il pasto del piano che sostituisce non conta più come mangiato
        if let si = f.si, mangiati().contains(si) {
            var arr = Set(d.eaten[key] ?? []); arr.remove(si); d.eaten[key] = arr.sorted()
            pastoInSalute(si: si, mangiato: false)
        }
        // niente più di 60 giorni di memoria
        let limite = Cal.date(key).addingTimeInterval(-60 * 86400)
        d.fuori = d.fuori.filter { Cal.date($0.key) >= limite }
        if d.salute {
            let t = f.tot
            Salute.shared.salvaPasto(id: "\(key)-f-\(f.id)", t: Date(timeIntervalSince1970: f.t / 1000), nome: f.nome, k: t.k, p: t.p, c: t.c, f: t.fa)
        }
        Haptic.medio()
    }

    func togliFuori(_ id: String) {
        let key = oggiKey
        d.fuori[key]?.removeAll { $0.id == id }
        if d.salute { Salute.shared.eliminaPasto(id: "\(key)-f-\(id)") }
        Haptic.leggero()
    }

    // quanto hai mangiato in più (o in meno) del piano con i pasti fuori piano di oggi
    func scartoFuori() -> Double {
        let plan = pianoOggi
        var scarto = 0.0
        for f in fuoriOggi() {
            scarto += f.tot.k
            if let si = f.si, let m = plan.meals[safe: si] { scarto -= m.kcalPreviste }
        }
        return scarto
    }

    // il consiglio per il resto della giornata: dal pasto che manca (l'ultimo) togli un po' della fonte di carboidrati
    func consiglioFuori() -> (testo: String, su: Bool)? {
        let scarto = scartoFuori()
        guard !fuoriOggi().isEmpty, abs(scarto) >= 60 else { return nil }
        let mangiati = Set(self.mangiati())
        let sostituite = Set(fuoriOggi().compactMap(\.si))
        let restano = pianoOggi.meals.filter { !$0.free && !mangiati.contains($0.si) && !sostituite.contains($0.si) }
        if scarto < 0 {
            return ("Hai mangiato \(Int(-scarto)) kcal meno del piano: non serve recuperarle, segui i prossimi pasti come sono.", false)
        }
        guard let ultimo = restano.last else {
            return ("Oggi sei \(Int(scarto)) kcal sopra il piano. Nessun problema per un giorno: domani si torna al piano normale.", true)
        }
        let carbo = ultimo.lines.filter { piano.foods[$0.f]?.cat == "Pane, pasta e cereali" }.max { $0.k < $1.k }
        let nomePasto = (ultimo.label.components(separatedBy: " (").first ?? ultimo.label).lowercased()
        if let l = carbo, let cibo = piano.foods[l.f], cibo.k > 0 {
            let togli = min(l.g * 0.6, (scarto / (cibo.k / 100) / 5).rounded() * 5)
            if togli >= 10 {
                return ("Sei \(Int(scarto)) kcal sopra il piano. A \(nomePasto) prendi \(Int(l.g - togli)) g di \(piano.foodName(l.f).lowercased()) invece di \(Int(l.g)) g (−\(Int(togli * cibo.k / 100)) kcal).", true)
            }
        }
        return ("Sei \(Int(scarto)) kcal sopra il piano: a \(nomePasto) dimezza l'olio e salta il pane, se c'è.", true)
    }
}

// MARK: Open Food Facts

struct ProdottoOFF: Identifiable, Hashable {
    let id: String
    let nome: String
    let marca: String
    let k100, p100, c100, f100: Double
    let porzione: Double?
}

enum OpenFoodFacts {
    private static func richiesta(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue("Recomp/1.0 (app personale)", forHTTPHeaderField: "User-Agent")
        r.timeoutInterval = 15
        return r
    }
    private static func numero(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }
    private static func prodotto(_ codice: String, _ p: [String: Any]) -> ProdottoOFF? {
        let n = p["nutriments"] as? [String: Any] ?? [:]
        guard let k = numero(n["energy-kcal_100g"]) else { return nil }
        let marca = (p["brands"] as? String) ?? (p["brands"] as? [String])?.joined(separator: ", ") ?? ""
        let nome = (p["product_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Prodotto \(codice)"
        return ProdottoOFF(id: codice, nome: nome, marca: marca, k100: k, p100: numero(n["proteins_100g"]) ?? 0,
                           c100: numero(n["carbohydrates_100g"]) ?? 0, f100: numero(n["fat_100g"]) ?? 0, porzione: numero(p["serving_quantity"]))
    }

    // un prodotto dal codice a barre
    static func cerca(codice: String) async -> ProdottoOFF? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(codice)?fields=product_name,brands,nutriments,serving_quantity"),
              let (dati, _) = try? await URLSession.shared.data(for: richiesta(url)),
              let j = try? JSONSerialization.jsonObject(with: dati) as? [String: Any],
              let p = j["product"] as? [String: Any] else { return nil }
        return prodotto(codice, p)
    }

    // prodotti per nome (prima quelli italiani)
    static func cerca(testo: String) async -> [ProdottoOFF] {
        var c = URLComponents(string: "https://search.openfoodfacts.org/search")!
        c.queryItems = [URLQueryItem(name: "q", value: testo), URLQueryItem(name: "page_size", value: "12"),
                        URLQueryItem(name: "langs", value: "it"), URLQueryItem(name: "fields", value: "code,product_name,brands,nutriments,serving_quantity")]
        guard let url = c.url, let (dati, _) = try? await URLSession.shared.data(for: richiesta(url)),
              let j = try? JSONSerialization.jsonObject(with: dati) as? [String: Any],
              let hits = j["hits"] as? [[String: Any]] else { return [] }
        return hits.compactMap { h in (h["code"] as? String).flatMap { prodotto($0, h) } }
    }
}

// MARK: la finestra «Fuori piano»

struct FuoriPianoSheet: View {
    @EnvironmentObject var s: AppStore
    @Environment(\.dismiss) private var chiudi
    let si: Int?                 // fascia sostituita, nil = in più
    var esistente: PastoFuori?

    @State private var nome = ""
    @State private var voci: [VoceCibo] = []
    @State private var cerca = ""
    @State private var trovatiOFF: [ProdottoOFF] = []
    @State private var cercando = false
    @State private var scanner = false
    @State private var messaggio = ""
    @State private var aMano = false
    @State private var caricato = false

    var body: some View {
        let m = si.flatMap { s.pianoOggi.meals[safe: $0] }
        let tot = Tot(k: voci.reduce(0) { $0 + $1.k }, p: voci.reduce(0) { $0 + $1.p }, c: voci.reduce(0) { $0 + $1.c }, fa: voci.reduce(0) { $0 + $1.f })
        VStack(spacing: 0) {
            TestataFoglio(titolo: si == nil ? "Mangiato in più" : m?.free == true ? "Pasto libero" : "Fuori piano",
                          sotto: m.map { $0.free ? "Circa \(Int(stimaPastoLibero)) kcal previste: basta una stima" : "Al posto di \(nomePasto($0).lowercased()) · \(Int($0.tot.k)) kcal dal piano" }
                              ?? "In più rispetto al piano di oggi",
                          chiudi: { chiudi() }) {
                if let e = esistente {
                    Menu {
                        Button(role: .destructive) { s.togliFuori(e.id); chiudi() } label: { Label("Sì, togli questo pasto", systemImage: "trash") }
                    } label: { TondoIcona(icona: "trash", colore: Tema.rosso) }
                    .accessibilityLabel("Togli questo pasto")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Nome (per esempio: pizza con gli amici)", text: $nome).campo()
                    if !voci.isEmpty { totale(tot, m) }
                    TitoloFoglio(testo: "Cosa hai mangiato")
                    if voci.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "fork.knife").font(.system(size: 16, weight: .bold)).foregroundStyle(Tema.tenue)
                            Text("Cerca un cibo qui sotto, scansiona il codice a barre della confezione o scrivilo a mano.")
                                .font(.system(size: 14)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Tema.linea, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                    } else {
                        VStack(spacing: 0) {
                            ForEach($voci) { $v in
                                if v.id != voci.first?.id { Rectangle().fill(Tema.linea).frame(height: 1).padding(.leading, 60) }
                                rigaVoce($v)
                            }
                        }
                        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    TitoloFoglio(testo: "Aggiungi")
                    HStack(spacing: 10) {
                        riquadro("barcode.viewfinder", "Codice a barre") { scanner = true }
                        riquadro("square.and.pencil", "Scrivi a mano") { aMano = true }
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.tenue)
                        TextField("Cerca un cibo o un prodotto", text: $cerca).autocorrectionDisabled().submitLabel(.search)
                        if cercando {
                            ProgressView()
                        } else if !cerca.isEmpty {
                            Button { cerca = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tema.tenue) }.accessibilityLabel("Cancella la ricerca")
                        }
                    }
                    .campo()
                    if !messaggio.isEmpty { Text(messaggio).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ambra) }
                    risultati
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
                .animation(.snappy, value: voci)
            }
            .scrollDismissesKeyboard(.interactively)
            .pulsanteInFondo(voci.isEmpty ? "Aggiungi almeno un cibo" : "Salva · \(Int(tot.k)) kcal", attivo: !voci.isEmpty) { salva() }
        }
        .background(Tema.fondo.ignoresSafeArea())
        .task(id: cerca) { await cercaOFF() }
        .sheet(isPresented: $scanner) {
            ScannerCodici { codice in
                scanner = false
                Task { await daCodice(codice) }
            }
            .ignoresSafeArea()
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $aMano) { CiboAMano { voci.append($0) }.foglio() }
        .onAppear {
            guard !caricato else { return }
            caricato = true
            if let e = esistente { nome = e.nome; voci = e.voci } else {
                let m = si.flatMap { s.pianoOggi.meals[safe: $0] }
                nome = si == nil ? "Spuntino" : m?.free == true ? "Pasto libero" : ""
            }
        }
    }

    private func nomePasto(_ m: MealPlan) -> String { m.label.components(separatedBy: " (").first ?? m.label }

    // il totale in argento, con la differenza dal pasto del piano
    private func totale(_ t: Tot, _ m: MealPlan?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOTALE").font(.sport(17)).opacity(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(t.k))").font(.sport(56)).monospacedDigit()
                Text("kcal").font(.sport(22)).opacity(0.6)
                Spacer(minLength: 4)
                if let m {
                    let d = Int(t.k - m.kcalPreviste)
                    Text(d == 0 ? "come il piano" : "\(d > 0 ? "+" : "−")\(abs(d)) sul piano").font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 10).padding(.vertical, 5).background(Tema.inchiostro.opacity(0.12), in: Capsule())
                }
            }
            .padding(.vertical, -6)
            Text("P \(Int(r0(t.p))) g · C \(Int(r0(t.c))) g · G \(Int(r0(t.fa))) g").font(.system(size: 14, weight: .semibold)).opacity(0.75)
        }
        .foregroundStyle(Tema.inchiostro)
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Argento())
    }

    private func iconaVoce(_ v: VoceCibo) -> some View {
        Group {
            if let f = v.fonte, s.piano.foods[f] != nil {
                Text(s.piano.icona(f)).font(.system(size: 18))
            } else {
                Image(systemName: v.fonte == "mano" ? "square.and.pencil" : "barcode").font(.system(size: 15, weight: .bold)).foregroundStyle(Tema.tenue)
            }
        }
        .frame(width: 34, height: 34).background(Tema.scheda2, in: Circle())
    }

    private func rigaVoce(_ v: Binding<VoceCibo>) -> some View {
        let x = v.wrappedValue
        return HStack(spacing: 10) {
            iconaVoce(x)
            VStack(alignment: .leading, spacing: 1) {
                Text(x.nome).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text("\(Int(x.k)) kcal · P \(fmtNum(r1(x.p))) · C \(fmtNum(r1(x.c))) · G \(fmtNum(r1(x.f)))").font(.system(size: 12)).foregroundStyle(Tema.tenue).lineLimit(1)
            }
            Spacer(minLength: 4)
            if x.fonte != "mano" {
                HStack(spacing: 3) {
                    TextField("g", value: v.g, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .font(.system(size: 16, weight: .bold)).monospacedDigit().frame(width: 50)
                    Text("g").font(.system(size: 13)).foregroundStyle(Tema.tenue)
                }
                .padding(.vertical, 7).padding(.horizontal, 10).background(Tema.scheda2, in: Capsule())
            }
            Button { voci.removeAll { $0.id == x.id }; Haptic.leggero() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .heavy)).frame(width: 28, height: 28).background(Tema.scheda2, in: Circle())
            }
            .buttonStyle(.plain).foregroundStyle(Tema.tenue).accessibilityLabel("Togli \(x.nome)")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func riquadro(_ icona: String, _ testo: String, _ azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icona).font(.system(size: 17, weight: .bold)).foregroundStyle(Tema.testo)
                    .frame(width: 36, height: 36).background(Tema.scheda2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text(testo).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // i risultati della ricerca: prima i cibi del piano, poi Open Food Facts
    @ViewBuilder private var risultati: some View {
        let dalPiano = cibiPiano()
        if !dalPiano.isEmpty || !trovatiOFF.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if !dalPiano.isEmpty {
                    etichettaRisultati("Dal tuo piano")
                    ForEach(dalPiano, id: \.self) { id in
                        Button { aggiungiDalPiano(id) } label: {
                            risultato(Text(s.piano.icona(id)).font(.system(size: 18)), s.piano.foodName(id), s.piano.foods[id]?.cat ?? "", s.piano.foods[id]?.k ?? 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !trovatiOFF.isEmpty {
                    etichettaRisultati("Open Food Facts")
                    ForEach(trovatiOFF) { p in
                        Button { aggiungi(p) } label: {
                            risultato(Image(systemName: "cart.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Tema.tenue), p.nome, p.marca, p.k100)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 6)
            .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func etichettaRisultati(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .bold)).foregroundStyle(Tema.tenue).padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 2)
    }

    private func risultato<I: View>(_ icona: I, _ nome: String, _ sotto: String, _ k100: Double) -> some View {
        HStack(spacing: 10) {
            icona.frame(width: 34, height: 34).background(Tema.scheda2, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(nome).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo).lineLimit(1)
                Text((sotto.isEmpty ? "" : sotto + " · ") + "\(Int(k100)) kcal/100 g").font(.system(size: 12)).foregroundStyle(Tema.tenue).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "plus").font(.system(size: 13, weight: .heavy)).foregroundStyle(Tema.fondo)
                .frame(width: 28, height: 28).background(Tema.testo, in: Circle())
        }
        .padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
    }

    // i cibi del piano che corrispondono a quello che scrivi
    private func cibiPiano() -> [String] {
        let q = cerca.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        return s.piano.foods.values.filter { $0.n.localizedCaseInsensitiveContains(q) }.map(\.id).sorted().prefix(6).map { $0 }
    }

    private func aggiungiDalPiano(_ id: String) {
        guard let f = s.piano.foods[id] else { return }
        voci.append(VoceCibo(nome: s.piano.foodName(id), g: f.u ?? 100, k100: f.k, p100: f.p, c100: f.c, f100: f.f, fonte: id))
        cerca = ""
        Haptic.leggero()
    }

    private func aggiungi(_ p: ProdottoOFF) {
        voci.append(VoceCibo(nome: p.marca.isEmpty ? p.nome : "\(p.nome) (\(p.marca))", g: p.porzione ?? 100, k100: p.k100, p100: p.p100, c100: p.c100, f100: p.f100, fonte: p.id))
        if nome.isEmpty || nome == "Spuntino" || nome == "Pasto libero" { nome = p.nome }
        cerca = ""
        Haptic.leggero()
    }

    private func cercaOFF() async {
        let q = cerca.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { trovatiOFF = []; cercando = false; return }
        try? await Task.sleep(nanoseconds: 450_000_000)   // aspetto che finisci di scrivere
        if Task.isCancelled { return }
        cercando = true
        let r = await OpenFoodFacts.cerca(testo: q)
        if !Task.isCancelled { trovatiOFF = r; cercando = false }
    }

    private func daCodice(_ codice: String) async {
        messaggio = "Cerco il prodotto \(codice)…"
        if let p = await OpenFoodFacts.cerca(codice: codice) {
            aggiungi(p)
            messaggio = ""
        } else {
            messaggio = "Prodotto \(codice) non trovato su Open Food Facts: scrivilo a mano."
        }
    }

    private func salva() {
        let f = PastoFuori(id: esistente?.id ?? UUID().uuidString, si: si,
                           nome: nome.trimmingCharacters(in: .whitespaces).isEmpty ? (voci.first?.nome ?? "Fuori piano") : nome,
                           voci: voci, t: esistente?.t ?? Cal.ms())
        s.salvaFuori(f)
        chiudi()
    }
}

// un cibo scritto a mano: nome, kcal e macro della porzione
struct CiboAMano: View {
    @Environment(\.dismiss) private var chiudi
    var aggiungi: (VoceCibo) -> Void
    @State private var nome = ""
    @State private var k = ""
    @State private var p = ""
    @State private var c = ""
    @State private var g = ""

    var body: some View {
        VStack(spacing: 0) {
            TestataFoglio(titolo: "Scrivi a mano", sotto: "Kcal e macro della porzione che hai mangiato", chiudi: { chiudi() })
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Cosa (per esempio: 2 fette di pizza)", text: $nome).campo()
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        numero("Kcal", "kcal", $k, Tema.testo)
                        numero("Proteine", "g", $p, Tema.p)
                        numero("Carboidrati", "g", $c, Tema.c)
                        numero("Grassi", "g", $g, Tema.g)
                    }
                    Text("Se non sai i macro, basta una stima delle kcal.").font(.system(size: 12)).foregroundStyle(Tema.tenue)
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .pulsanteInFondo("Aggiungi", attivo: n(k) > 0) {
                aggiungi(VoceCibo(nome: nome.isEmpty ? "Cibo" : nome, g: 100, k100: n(k), p100: n(p), c100: n(c), f100: n(g), fonte: "mano"))
                chiudi()
            }
        }
        .background(Tema.fondo.ignoresSafeArea())
    }

    private func n(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    private func numero(_ titolo: String, _ unita: String, _ v: Binding<String>, _ colore: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(colore).frame(width: 8, height: 8)
                Text(titolo).font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.tenue)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField("0", text: v).keyboardType(.decimalPad).font(.sport(34)).monospacedDigit()
                Text(unita).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.tenue)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: lettore del codice a barre (fotocamera, VisionKit)

struct ScannerCodici: View {
    var trovato: (String) -> Void
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        ZStack(alignment: .bottom) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                LettoreCodici(trovato: trovato)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill").font(.system(size: 40)).foregroundStyle(Tema.tenue)
                    Text("La fotocamera non è disponibile: controlla il permesso in Impostazioni → Recomp.").multilineTextAlignment(.center).foregroundStyle(Tema.tenue)
                }
                .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).background(Tema.fondo)
            }
            Text("Inquadra il codice a barre della confezione").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10).background(.black.opacity(0.55), in: Capsule()).padding(.bottom, 50)
        }
    }
}

private struct LettoreCodici: UIViewControllerRepresentable {
    var trovato: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let v = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
                                          qualityLevel: .balanced, recognizesMultipleItems: false,
                                          isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        v.delegate = context.coordinator
        return v
    }

    func updateUIViewController(_ v: DataScannerViewController, context: Context) {
        if !v.isScanning { try? v.startScanning() }
    }

    func makeCoordinator() -> Coordinatore { Coordinatore(trovato: trovato) }

    final class Coordinatore: NSObject, DataScannerViewControllerDelegate {
        let trovato: (String) -> Void
        private var fatto = false
        init(trovato: @escaping (String) -> Void) { self.trovato = trovato }
        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !fatto else { return }
            for i in items {
                if case .barcode(let b) = i, let codice = b.payloadStringValue {
                    fatto = true
                    s.stopScanning()
                    Haptic.ok()
                    trovato(codice)
                    return
                }
            }
        }
    }
}
