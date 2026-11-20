import SwiftUI
import VisionKit

// Pasto fuori piano: segni cosa hai mangiato davvero (cibi del piano, prodotti di Open Food Facts cercati per nome o con il
// codice a barre, oppure scritti a mano) al posto di un pasto o in più. I totali di oggi lo contano, e se hai sforato
// l'app dice cosa togliere dal pasto che resta.

extension AppStore {
    func fuoriOggi() -> [PastoFuori] { d.fuori[oggiKey] ?? [] }
    func fuoriPerFascia(_ si: Int) -> PastoFuori? { fuoriOggi().first { $0.si == si } }

    // MARK: pasti tolti da oggi

    func pastoTolto(_ si: Int, _ key: String? = nil) -> Bool { (d.saltati[key ?? oggiKey] ?? []).contains(si) }
    // «Togli da oggi»: il pasto del piano non c'è più per oggi (non conta e non si aspetta); se c'era un tuo pasto al suo posto, va via anche quello
    func togliPasto(_ si: Int) {
        let key = oggiKey
        if mangiati().contains(si) { segnaMangiato(si, false) }
        if let f = fuoriPerFascia(si) { togliFuori(f.id) }
        var arr = Set(d.saltati[key] ?? []); arr.insert(si); d.saltati[key] = arr.sorted()
        let limite = Cal.date(key).addingTimeInterval(-60 * 86400)
        d.saltati = d.saltati.filter { Cal.date($0.key) >= limite }
        Haptic.medio()
    }
    func rimettiPasto(_ si: Int) {
        let key = oggiKey
        var arr = Set(d.saltati[key] ?? []); arr.remove(si)
        d.saltati[key] = arr.isEmpty ? nil : arr.sorted()
        Haptic.leggero()
    }

    // quello che oggi è previsto davvero: i pasti tolti valgono zero, quelli sostituiti da un tuo pasto valgono il tuo pasto,
    // il pasto libero la sua stima (i pasti in più no: sono fuori dal piano)
    func previstiOggi() -> Tot {
        var t = Tot()
        for m in pianoOggi.meals where !pastoTolto(m.si) {
            let x = fuoriPerFascia(m.si)?.tot ?? (m.free ? stimaLibero : m.tot)
            t.k += x.k; t.p += x.p; t.c += x.c; t.fa += x.fa
        }
        return Tot(k: r0(t.k), p: r1(t.p), c: r1(t.c), fa: r1(t.fa))
    }

    // l'ora del pasto deve ancora arrivare: cambiandolo, il tuo pasto resta «da mangiare» (lo segni quando lo mangi)
    func ancoraDaMangiare(_ m: MealPlan) -> Bool {
        let p = m.time.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2, let ora = Cal.greg.date(bySettingHour: p[0], minute: p[1], second: 0, of: Date()) else { return false }
        return ora > Date()
    }

    // un tuo pasto preparato prima («da mangiare»): ora l'hai mangiato
    func mangiaFuori(_ id: String) {
        guard var f = fuoriOggi().first(where: { $0.id == id }), !f.giaMangiato else { return }
        f.mangiato = nil
        f.t = Cal.ms()
        salvaFuori(f)
    }
    func nonMangiatoFuori(_ id: String) {
        guard var f = fuoriOggi().first(where: { $0.id == id }), f.si != nil, f.giaMangiato else { return }
        f.mangiato = false
        salvaFuori(f)
    }

    // MARK: i miei pasti (salvati)

    var mieiPasti: [PastoMio] { d.mieiPasti.sorted { $0.t > $1.t } }
    // salva (o aggiorna, se c'è già uno con lo stesso nome o lo stesso id) un tuo pasto
    @discardableResult
    func salvaMio(id: String? = nil, nome: String, voci: [VoceCibo]) -> PastoMio {
        let pulito = nome.trimmingCharacters(in: .whitespaces)
        var lista = d.mieiPasti
        lista.removeAll { $0.id == id || $0.nome.lowercased() == pulito.lowercased() }
        let mio = PastoMio(id: id ?? UUID().uuidString, nome: pulito.isEmpty ? "Il mio pasto" : pulito, voci: voci, t: Cal.ms())
        lista.append(mio)
        d.mieiPasti = Array(lista.sorted { $0.t > $1.t }.prefix(40))
        return mio
    }
    func eliminaMio(_ id: String) { d.mieiPasti.removeAll { $0.id == id }; Haptic.leggero() }
    // uno dei tuoi pasti al posto di un pasto del piano di oggi, da mangiare (lo segni con la spunta)
    func mettiMio(_ mio: PastoMio, al si: Int) {
        let voci = mio.voci.map { var v = $0; v.id = UUID().uuidString; return v }
        salvaFuori(PastoFuori(si: si, nome: mio.nome, voci: voci, t: Cal.ms(), mangiato: false))
        if let i = d.mieiPasti.firstIndex(where: { $0.id == mio.id }) { d.mieiPasti[i].t = Cal.ms() }   // usato: sale in cima
    }

    // i tuoi pasti degli ultimi giorni non ancora salvati (un nome una volta sola, i più recenti prima)
    func pastiRecenti() -> [PastoFuori] {
        var visti = Set(d.mieiPasti.map { $0.nome.lowercased() })
        return d.fuori.values.flatMap { $0 }.sorted { $0.t > $1.t }
            .filter { !$0.voci.isEmpty && visti.insert($0.nome.lowercased()).inserted }
            .prefix(6).map { $0 }
    }

    func salvaFuori(_ f: PastoFuori) {
        let key = oggiKey
        var lista = d.fuori[key] ?? []
        lista.removeAll { $0.id == f.id || (f.si != nil && $0.si == f.si) }
        lista.append(f)
        d.fuori[key] = lista
        // un pasto tolto che ora ha un tuo pasto al suo posto torna nel piano di oggi
        if let si = f.si, pastoTolto(si) { rimettiPasto(si) }
        // il pasto del piano che sostituisce non conta più come mangiato
        if let si = f.si, mangiati().contains(si) {
            var arr = Set(d.eaten[key] ?? []); arr.remove(si); d.eaten[key] = arr.sorted()
            pastoInSalute(si: si, mangiato: false)
        }
        // niente più di 60 giorni di memoria
        let limite = Cal.date(key).addingTimeInterval(-60 * 86400)
        d.fuori = d.fuori.filter { Cal.date($0.key) >= limite }
        // in Salute solo quello che hai mangiato davvero
        if d.salute {
            if f.giaMangiato {
                let t = f.tot
                Salute.shared.salvaPasto(id: "\(key)-f-\(f.id)", t: Date(timeIntervalSince1970: f.t / 1000), nome: f.nome, k: t.k, p: t.p, c: t.c, f: t.fa)
            } else {
                Salute.shared.eliminaPasto(id: "\(key)-f-\(f.id)")
            }
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
        guard !fuoriOggi().isEmpty, scarto >= 60 else { return nil }
        let mangiati = Set(self.mangiati())
        let sostituite = Set(fuoriOggi().compactMap(\.si))
        let restano = pianoOggi.meals.filter { !$0.free && !mangiati.contains($0.si) && !sostituite.contains($0.si) && !pastoTolto($0.si) }
        if scarto < 0 {
            return ("Con i pasti cambiati oggi sei \(Int(-scarto)) kcal sotto il piano: non serve recuperarle, segui i prossimi pasti come sono.", false)
        }
        guard let ultimo = restano.last else {
            return ("Con i pasti cambiati oggi sei \(Int(scarto)) kcal sopra il piano. Nessun problema per un giorno: domani si torna al piano normale.", true)
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
    var mio = false              // da mangiare dopo (lo segni quando lo mangi) invece che già mangiato
    var libreria: PastoMio? = nil   // modifica di uno dei tuoi pasti salvati
    var perLibreria = false         // nuovo pasto da salvare tra i tuoi (da Piano → I miei pasti)

    @State private var nome = ""
    @State private var voci: [VoceCibo] = []
    @State private var cerca = ""
    @State private var trovatiOFF: [ProdottoOFF] = []
    @State private var cercando = false
    @State private var scanner = false
    @State private var messaggio = ""
    @State private var aMano = false
    @State private var caricato = false
    @State private var giaMangiato = true
    @State private var traMiei = false
    @FocusState private var scrivendo: Bool

    // le ricerche su Open Food Facts già fatte (finché l'app resta aperta): tornando indietro col testo non si richiede niente
    @MainActor private static var memoriaOFF: [String: [ProdottoOFF]] = [:]

    var body: some View {
        let m = si.flatMap { s.pianoOggi.meals[safe: $0] }
        let tot = Tot(k: voci.reduce(0) { $0 + $1.k }, p: voci.reduce(0) { $0 + $1.p }, c: voci.reduce(0) { $0 + $1.c }, fa: voci.reduce(0) { $0 + $1.f })
        VStack(spacing: 0) {
            TestataFoglio(titolo: titolo(m), sotto: sottotitolo(m), chiudi: { chiudi() }) {
                if let l = libreria {
                    Menu {
                        Button(role: .destructive) { s.eliminaMio(l.id); chiudi() } label: { Label("Sì, eliminalo dai miei pasti", systemImage: "trash") }
                    } label: { TondoIcona(icona: "trash", colore: Tema.rosso) }
                    .accessibilityLabel("Elimina dai miei pasti")
                } else if let e = esistente {
                    Menu {
                        Button(role: .destructive) { s.togliFuori(e.id); chiudi() } label: { Label("Sì, togli questo pasto", systemImage: "trash") }
                    } label: { TondoIcona(icona: "trash", colore: Tema.rosso) }
                    .accessibilityLabel("Togli questo pasto")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 1. cerca (o codice a barre, o a mano): è la cosa che si fa di più, quindi sta in cima
                    barraRicerca
                    if !messaggio.isEmpty { Text(messaggio).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ambra) }
                    if cerca.trimmingCharacters(in: .whitespaces).count >= 2 {
                        risultati
                    } else {
                        scorciatoie
                    }
                    // 2. il piatto: i cibi con i grammi, e il totale con la differenza dal piano
                    if !voci.isEmpty {
                        HStack(alignment: .firstTextBaseline) {
                            TitoloFoglio(testo: perLibreria || mio ? "Cosa c'è dentro" : "Cosa hai mangiato")
                            Spacer()
                            riassunto(tot, perLibreria ? nil : m)
                        }
                        VStack(spacing: 0) {
                            ForEach($voci) { $v in
                                if v.id != voci.first?.id { Rectangle().fill(Tema.linea).frame(height: 1).padding(.leading, 60) }
                                rigaVoce($v)
                            }
                        }
                        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        Text("P \(Int(r0(tot.p))) g · C \(Int(r0(tot.c))) g · G \(Int(r0(tot.fa))) g").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.tenue)
                    }
                    // 3. i dettagli: nome, già mangiato o da mangiare, salvarlo tra i tuoi
                    TitoloFoglio(testo: "Dettagli")
                    TextField(mio || perLibreria ? "Nome (per esempio: la mia cena)" : "Nome (se lo lasci vuoto: il primo cibo)", text: $nome).campo()
                    if si != nil && !perLibreria {
                        Toggle(isOn: $giaMangiato) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("L'ho già mangiato").font(.system(size: 15, weight: .semibold))
                                Text(giaMangiato ? "Conta subito nei totali di oggi" : "Resta da mangiare: lo segni con la spunta, come gli altri pasti")
                                    .font(.system(size: 12)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(Tema.verde)
                        .campo()
                    }
                    if !perLibreria {
                        Toggle(isOn: $traMiei) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Salva tra i miei pasti").font(.system(size: 15, weight: .semibold))
                                Text("Lo rifai con un tocco, anche dall'orologio").font(.system(size: 12)).foregroundStyle(Tema.tenue)
                            }
                        }
                        .tint(Tema.verde)
                        .campo()
                    }
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
            if let l = libreria { nome = l.nome; voci = l.voci; return }
            if perLibreria { return }
            if let e = esistente {
                nome = e.nome; voci = e.voci; giaMangiato = e.giaMangiato
                traMiei = s.d.mieiPasti.contains { $0.nome.lowercased() == e.nome.lowercased() }
            } else {
                nome = m?.free == true ? "Pasto libero" : ""
                giaMangiato = !mio
                traMiei = mio
            }
        }
    }

    private func nomePasto(_ m: MealPlan) -> String { m.label.components(separatedBy: " (").first ?? m.label }

    private func titolo(_ m: MealPlan?) -> String {
        if perLibreria { return libreria == nil ? "Nuovo pasto" : "Il mio pasto" }
        guard let m else { return "Mangiato in più" }
        return m.free ? "Pasto libero" : nomePasto(m)
    }
    private func sottotitolo(_ m: MealPlan?) -> String {
        if perLibreria { return "Tra i tuoi pasti: lo rifai con un tocco, anche dall'orologio" }
        guard let m else { return "In più rispetto al piano di oggi" }
        if m.free { return "Circa \(Int(stimaPastoLibero)) kcal previste: basta una stima" }
        return "Al posto di \(s.piano.recipe(m.code).name) · \(Int(m.tot.k)) kcal"
    }

    // MARK: ricerca

    private var barraRicerca: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.tenue)
                TextField("Cerca: pizza, cornetto, pollo…", text: $cerca).autocorrectionDisabled().submitLabel(.search).focused($scrivendo)
                if cercando {
                    ProgressView()
                } else if !cerca.isEmpty {
                    Button { cerca = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tema.tenue) }.accessibilityLabel("Cancella la ricerca")
                }
            }
            .campo()
            tondo("barcode.viewfinder", "Codice a barre") { scanner = true }
            tondo("square.and.pencil", "Scrivi a mano") { aMano = true }
        }
    }

    private func tondo(_ icona: String, _ nome: String, _ azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            Image(systemName: icona).font(.system(size: 17, weight: .bold)).foregroundStyle(Tema.testo)
                .frame(width: 48, height: 48).background(Tema.scheda, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain).accessibilityLabel(nome)
    }

    // senza ricerca: i tuoi pasti e quelli recenti (a piatto vuoto) e i cibi più comuni fuori casa
    @ViewBuilder private var scorciatoie: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CibiFuori.rapidi.compactMap(CibiFuori.cibo), id: \.id) { c in
                    Button { aggiungiFuori(c) } label: {
                        Text("\(c.icona) \(c.nome.components(separatedBy: " (").first ?? c.nome)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.testo)
                            .padding(.horizontal, 12).padding(.vertical, 9).background(Tema.scheda, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
        if voci.isEmpty && libreria == nil {
            let miei = Array(s.mieiPasti.prefix(5))
            let recenti = Array(s.pastiRecenti().prefix(4))
            if !miei.isEmpty || !recenti.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    if !miei.isEmpty {
                        etichettaRisultati("I miei pasti")
                        ForEach(miei) { r in pastoPronto(r.nome, r.voci, mio: true) }
                    }
                    if !recenti.isEmpty {
                        etichettaRisultati("Mangiati di recente")
                        ForEach(recenti) { r in pastoPronto(r.nome, r.voci, mio: false) }
                    }
                }
                .padding(.bottom, 6)
                .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    // un pasto già fatto (tuo o recente): un tocco e i suoi cibi, con i grammi, entrano nel piatto
    private func pastoPronto(_ n: String, _ v: [VoceCibo], mio: Bool) -> some View {
        let k = v.reduce(0) { $0 + $1.k }
        return Button {
            voci += v.map { var x = $0; x.id = UUID().uuidString; return x }
            if nome.isEmpty || nome == "Pasto libero" { nome = n }
            if mio { traMiei = true }
            cerca = ""
            Haptic.leggero()
        } label: {
            risultato(Image(systemName: mio ? "star.fill" : "clock.arrow.circlepath").font(.system(size: 13, weight: .bold)).foregroundStyle(mio ? Tema.ambra : Tema.tenue),
                      n, "\(v.count) \(v.count == 1 ? "cibo" : "cibi") · \(Int(k)) kcal in tutto", nil)
        }
        .buttonStyle(.plain)
    }

    // i risultati: i tuoi pasti, i cibi del piano, quelli fuori casa, poi Open Food Facts
    @ViewBuilder private var risultati: some View {
        let q = cerca.trimmingCharacters(in: .whitespaces)
        let tuoi: [(String, [VoceCibo], Bool)] = (s.mieiPasti.map { ($0.nome, $0.voci, true) } + s.pastiRecenti().map { ($0.nome, $0.voci, false) })
            .filter { puntiRicerca($0.0, q) != nil }.prefix(4).map { $0 }
        let dalPiano = s.piano.foods.values.compactMap { f in puntiRicerca(f.n, q).map { (f.id, f.n, $0) } }
            .sorted { ($0.2, $0.1) < ($1.2, $1.1) }.prefix(6).map(\.0)
        let fuori = CibiFuori.tutti.compactMap { c in puntiRicerca(c.nome, q).map { (c, $0) } }
            .sorted { ($0.1, $0.0.nome) < ($1.1, $1.0.nome) }.prefix(6).map(\.0)
        if tuoi.isEmpty && dalPiano.isEmpty && fuori.isEmpty && trovatiOFF.isEmpty && !cercando {
            Text(q.count < 3 ? "Scrivi ancora qualche lettera." : "Niente con «\(q)»: prova con un'altra parola, il codice a barre o scrivilo a mano.")
                .font(.system(size: 14)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if !tuoi.isEmpty {
                    etichettaRisultati("I tuoi pasti")
                    ForEach(Array(tuoi.enumerated()), id: \.offset) { _, t in pastoPronto(t.0, t.1, mio: t.2) }
                }
                if !dalPiano.isEmpty {
                    etichettaRisultati("Dal tuo piano")
                    ForEach(dalPiano, id: \.self) { id in
                        Button { aggiungiDalPiano(id) } label: {
                            risultato(Text(s.piano.icona(id)).font(.system(size: 18)), s.piano.foodName(id), s.piano.foods[id]?.cat ?? "", s.piano.foods[id]?.k ?? 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !fuori.isEmpty {
                    etichettaRisultati("Fuori casa · valori medi")
                    ForEach(fuori) { c in
                        Button { aggiungiFuori(c) } label: {
                            risultato(Text(c.icona).font(.system(size: 18)), c.nome, "\(c.quanto) · \(Int(c.porzione)) g · \(Int(c.k * c.porzione / 100)) kcal", nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !trovatiOFF.isEmpty {
                    etichettaRisultati("Prodotti · Open Food Facts")
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

    // MARK: il piatto

    // kcal del piatto e la differenza dal pasto del piano che sostituisce
    private func riassunto(_ t: Tot, _ m: MealPlan?) -> some View {
        HStack(spacing: 6) {
            Text("\(Int(t.k)) kcal").font(.system(size: 15, weight: .heavy)).monospacedDigit()
            if let m, !m.free {
                let d = Int(t.k - m.kcalPreviste)
                Text(d == 0 ? "come il piano" : "\(d > 0 ? "+" : "−")\(abs(d)) sul piano").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Tema.inchiostro)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(abs(d) <= 100 ? Tema.verde : Tema.ambra, in: Capsule())
            }
        }
    }

    private func iconaVoce(_ v: VoceCibo) -> some View {
        Group {
            if let f = v.fonte, s.piano.foods[f] != nil {
                Text(s.piano.icona(f)).font(.system(size: 18))
            } else if let i = CibiFuori.icona(v.fonte) {
                Text(i).font(.system(size: 18))
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

    private func etichettaRisultati(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .bold)).foregroundStyle(Tema.tenue).padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 2)
    }

    private func risultato<I: View>(_ icona: I, _ nome: String, _ sotto: String, _ k100: Double?) -> some View {
        HStack(spacing: 10) {
            icona.frame(width: 34, height: 34).background(Tema.scheda2, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(nome).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo).lineLimit(1)
                Text(k100.map { (sotto.isEmpty ? "" : sotto + " · ") + "\(Int($0)) kcal/100 g" } ?? sotto).font(.system(size: 12)).foregroundStyle(Tema.tenue).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "plus").font(.system(size: 13, weight: .heavy)).foregroundStyle(Tema.fondo)
                .frame(width: 28, height: 28).background(Tema.testo, in: Circle())
        }
        .padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
    }

    // MARK: aggiungere

    private func aggiunto(_ v: VoceCibo, nomeSeVuoto: String) {
        voci.append(v)
        if nome.isEmpty || nome == "Pasto libero" { nome = nomeSeVuoto }
        cerca = ""
        scrivendo = false
        Haptic.leggero()
    }

    private func aggiungiDalPiano(_ id: String) {
        guard let f = s.piano.foods[id] else { return }
        voci.append(VoceCibo(nome: s.piano.foodName(id), g: f.u ?? 100, k100: f.k, p100: f.p, c100: f.c, f100: f.f, fonte: id))
        cerca = ""
        scrivendo = false
        Haptic.leggero()
    }

    private func aggiungiFuori(_ c: CiboFuori) { aggiunto(c.voce, nomeSeVuoto: c.nome) }

    private func aggiungi(_ p: ProdottoOFF) {
        aggiunto(VoceCibo(nome: p.marca.isEmpty ? p.nome : "\(p.nome) (\(p.marca))", g: p.porzione ?? 100, k100: p.k100, p100: p.p100, c100: p.c100, f100: p.f100, fonte: p.id),
                 nomeSeVuoto: p.nome)
    }

    private func cercaOFF() async {
        let q = cerca.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { trovatiOFF = []; cercando = false; return }
        let chiave = q.lowercased()
        if let r = Self.memoriaOFF[chiave] { trovatiOFF = r; cercando = false; return }
        try? await Task.sleep(nanoseconds: 450_000_000)   // aspetto che finisci di scrivere
        if Task.isCancelled { return }
        cercando = true
        let r = await OpenFoodFacts.cerca(testo: q)
        if Task.isCancelled { return }
        if !r.isEmpty { Self.memoriaOFF[chiave] = r }
        trovatiOFF = r
        cercando = false
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

    // il nome, se non l'hai scritto: i primi due cibi («Pizza margherita e Coca-Cola»)
    private var nomeDaiCibi: String {
        let nomi = voci.prefix(2).map { $0.nome.components(separatedBy: " (").first ?? $0.nome }
        return nomi.isEmpty ? "Il mio pasto" : nomi.joined(separator: " e ") + (voci.count > 2 ? "…" : "")
    }

    private func salva() {
        let scelto = nome.trimmingCharacters(in: .whitespaces)
        let n = scelto.isEmpty ? nomeDaiCibi : scelto
        // un pasto solo per «I miei pasti»
        if perLibreria {
            s.salvaMio(id: libreria?.id, nome: n, voci: voci)
            Haptic.ok()
            chiudi()
            return
        }
        if traMiei { s.salvaMio(nome: n, voci: voci) }
        let f = PastoFuori(id: esistente?.id ?? UUID().uuidString, si: si, nome: n,
                           voci: voci, t: esistente?.t ?? Cal.ms(), mangiato: si != nil && !giaMangiato ? false : nil)
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


// MARK: scegliere un cibo esterno dentro un pasto del piano (codice a barre, Open Food Facts, fuori casa, a mano)

struct CiboPastoSheet: View {
    @EnvironmentObject var s: AppStore
    @Environment(\.dismiss) private var chiudi
    let di: Int
    let m: MealPlan
    let indice: Int?             // nil = aggiungi al pasto; Int = metti al posto di quel cibo
    var apriScanner = false

    @State private var cerca = ""
    @State private var trovatiOFF: [ProdottoOFF] = []
    @State private var cercando = false
    @State private var scanner = false
    @State private var aMano = false
    @State private var messaggio = ""
    @State private var avviato = false
    @FocusState private var scrivendo: Bool
    @MainActor private static var memoriaOFF: [String: [ProdottoOFF]] = [:]

    private var vecchio: Line? { indice.flatMap { m.lines[safe: $0] } }

    var body: some View {
        VStack(spacing: 0) {
            TestataFoglio(
                titolo: vecchio.map { "Al posto di \(s.piano.nome($0).lowercased())" } ?? "Aggiungi al pasto",
                sotto: "\(s.piano.recipe(m.code).name) · codice a barre, ricerca o a mano",
                chiudi: { chiudi() }
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    barraRicerca
                    if !messaggio.isEmpty { Text(messaggio).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.ambra) }
                    if cerca.trimmingCharacters(in: .whitespaces).count >= 2 {
                        risultati
                    } else {
                        scorciatoie
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
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
        .sheet(isPresented: $aMano) {
            CiboAMano { v in
                scegli(IngredientRef(f: "mano", g: 100, nome: v.nome, k100: v.k100, p100: v.p100, c100: v.c100, f100: v.f100))
            }
            .foglio()
        }
        .onAppear {
            guard !avviato else { return }
            avviato = true
            if apriScanner { scanner = true } else { scrivendo = true }
        }
    }

    private var barraRicerca: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.tenue)
                TextField("Cerca: crackers, yogurt, pane…", text: $cerca).autocorrectionDisabled().submitLabel(.search).focused($scrivendo)
                if cercando {
                    ProgressView()
                } else if !cerca.isEmpty {
                    Button { cerca = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tema.tenue) }.accessibilityLabel("Cancella la ricerca")
                }
            }
            .campo()
            tondo("barcode.viewfinder", "Codice a barre") { scanner = true }
            tondo("square.and.pencil", "Scrivi a mano") { aMano = true }
        }
    }

    private func tondo(_ icona: String, _ nome: String, _ azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            Image(systemName: icona).font(.system(size: 17, weight: .bold)).foregroundStyle(Tema.testo)
                .frame(width: 48, height: 48).background(Tema.scheda, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain).accessibilityLabel(nome)
    }

    @ViewBuilder private var scorciatoie: some View {
        let recenti = s.cibiEsterniRecenti()
        if !recenti.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                etichetta("Usati di recente")
                ForEach(Array(recenti.enumerated()), id: \.offset) { _, r in
                    Button {
                        var nuovo = r
                        if let v = vecchio, r.u == nil { nuovo.g = v.g }
                        scegli(nuovo)
                    } label: {
                        rigaRisultato(Text("📦").font(.system(size: 18)), r.nome ?? r.f, "\(Int(r.g)) g · \(Int(r0((r.k100 ?? 0) * r.g / 100))) kcal", r.k100)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 6)
            .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        VStack(alignment: .leading, spacing: 0) {
            etichetta("Fuori casa · valori medi")
            ForEach(CibiFuori.rapidi.compactMap(CibiFuori.cibo), id: \.id) { c in
                Button { scegliFuori(c) } label: {
                    rigaRisultato(Text(c.icona).font(.system(size: 18)), c.nome, "\(c.quanto) · \(Int(c.porzione)) g · \(Int(c.k * c.porzione / 100)) kcal", nil)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 6)
        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder private var risultati: some View {
        let q = cerca.trimmingCharacters(in: .whitespaces)
        let dalPiano = s.piano.foods.values.compactMap { f in puntiRicerca(f.n, q).map { (f.id, f.n, $0) } }
            .sorted { ($0.2, $0.1) < ($1.2, $1.1) }.prefix(6).map(\.0)
        let fuori = CibiFuori.tutti.compactMap { c in puntiRicerca(c.nome, q).map { (c, $0) } }
            .sorted { ($0.1, $0.0.nome) < ($1.1, $1.0.nome) }.prefix(6).map(\.0)
        if dalPiano.isEmpty && fuori.isEmpty && trovatiOFF.isEmpty && !cercando {
            Text(q.count < 3 ? "Scrivi ancora qualche lettera." : "Niente con «\(q)»: prova con un'altra parola, il codice a barre o scrivilo a mano.")
                .font(.system(size: 14)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if !trovatiOFF.isEmpty {
                    etichetta("Prodotti · Open Food Facts")
                    ForEach(trovatiOFF) { p in
                        Button { scegliOFF(p) } label: {
                            rigaRisultato(Image(systemName: "barcode").font(.system(size: 14, weight: .bold)).foregroundStyle(Tema.tenue), p.nome, p.marca, p.k100)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !dalPiano.isEmpty {
                    etichetta("Dal tuo piano")
                    ForEach(dalPiano, id: \.self) { id in
                        Button { scegli(IngredientRef(f: id, g: vecchio?.g ?? s.piano.doseNuova(id, slot: m.slot))) } label: {
                            rigaRisultato(Text(s.piano.icona(id)).font(.system(size: 18)), s.piano.foodName(id), s.piano.foods[id]?.cat ?? "", s.piano.foods[id]?.k ?? 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !fuori.isEmpty {
                    etichetta("Fuori casa · valori medi")
                    ForEach(fuori) { c in
                        Button { scegliFuori(c) } label: {
                            rigaRisultato(Text(c.icona).font(.system(size: 18)), c.nome, "\(c.quanto) · \(Int(c.porzione)) g · \(Int(c.k * c.porzione / 100)) kcal", nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 6)
            .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func etichetta(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .bold)).foregroundStyle(Tema.tenue).padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 2)
    }

    private func rigaRisultato<I: View>(_ icona: I, _ nome: String, _ sotto: String, _ k100: Double?) -> some View {
        HStack(spacing: 10) {
            icona.frame(width: 34, height: 34).background(Tema.scheda2, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(nome).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo).lineLimit(1)
                Text(k100.map { (sotto.isEmpty ? "" : sotto + " · ") + "\(Int($0)) kcal/100 g" } ?? sotto).font(.system(size: 12)).foregroundStyle(Tema.tenue).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "plus").font(.system(size: 13, weight: .heavy)).foregroundStyle(Tema.fondo)
                .frame(width: 28, height: 28).background(Tema.testo, in: Circle())
        }
        .padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
    }

    private func scegli(_ ref: IngredientRef) {
        if let i = indice { s.scambiaCibo(di: di, m, i, con: ref) }
        else { s.aggiungiCiboRef(di: di, m, ref) }
        chiudi()
    }

    private func scegliFuori(_ c: CiboFuori) {
        // «fuori:pizza», come nei pasti fuori piano: così ha la sua icona e non si confonde con un cibo del piano
        scegli(IngredientRef(f: "fuori:" + c.id, g: c.porzione, nome: c.nome, k100: c.k, p100: c.p, c100: c.c, f100: c.f, u: c.porzione))
    }

    private func scegliOFF(_ p: ProdottoOFF) {
        let g = p.porzione.flatMap { $0 > 0 ? r0($0) : nil } ?? vecchio?.g ?? 100
        let nome = p.marca.isEmpty ? p.nome : "\(p.nome) (\(p.marca))"
        scegli(IngredientRef(f: p.id, g: g, nome: nome, k100: p.k100, p100: p.p100, c100: p.c100, f100: p.f100, u: p.porzione))
    }

    private func cercaOFF() async {
        let q = cerca.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { trovatiOFF = []; cercando = false; return }
        let chiave = q.lowercased()
        if let r = Self.memoriaOFF[chiave] { trovatiOFF = r; cercando = false; return }
        try? await Task.sleep(nanoseconds: 450_000_000)
        if Task.isCancelled { return }
        cercando = true
        let r = await OpenFoodFacts.cerca(testo: q)
        if Task.isCancelled { return }
        if !r.isEmpty { Self.memoriaOFF[chiave] = r }
        trovatiOFF = r
        cercando = false
    }

    private func daCodice(_ codice: String) async {
        messaggio = "Cerco il prodotto \(codice)…"
        if let p = await OpenFoodFacts.cerca(codice: codice) {
            messaggio = ""
            scegliOFF(p)
        } else {
            messaggio = "Prodotto \(codice) non trovato su Open Food Facts: cercalo per nome o scrivilo a mano."
        }
    }
}
