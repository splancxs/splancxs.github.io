import SwiftUI

// Modifica delle schede dall'app: nome, obiettivo, esercizi (aggiungi, togli, sposta, cambia), serie, ripetizioni,
// recupero e superserie. Le schede modificate si salvano in AppData.schede e valgono ovunque (allenamento, orologio, Numeri);
// «Torna all'originale» rimette quella del piano. Le schede nuove («Extra») non sono legate a un giorno.

extension AppStore {
    func salvaScheda(_ r: Routine) {
        var lista = d.schede ?? routinesDelPiano
        if let i = lista.firstIndex(where: { $0.id == r.id }) { lista[i] = r } else { lista.append(r) }
        d.schede = lista
        Haptic.ok()
    }
    func eliminaScheda(_ id: String) {
        var lista = d.schede ?? routinesDelPiano
        lista.removeAll { $0.id == id }
        d.schede = lista
    }
    func schedaOriginale(_ id: String) -> Routine? { routinesDelPiano.first { $0.id == id } }
    func schedaModificata(_ id: String) -> Bool {
        guard let mia = d.schede?.first(where: { $0.id == id }), let orig = schedaOriginale(id) else { return false }
        return mia != orig
    }
    func ripristinaScheda(_ id: String) {
        guard let orig = schedaOriginale(id) else { return }
        salvaScheda(orig)
    }
}

struct EditorScheda: View {
    @EnvironmentObject var s: AppStore
    @Environment(\.dismiss) private var chiudi
    @State var r: Routine
    let nuova: Bool
    @State private var insieme: [Bool] = []
    @State private var scelta: SceltaEsercizio?
    @State private var pronto = false

    enum SceltaEsercizio: Identifiable { case aggiungi, cambia(Int); var id: String { switch self { case .aggiungi: "a"; case .cambia(let i): "c\(i)" } } }

    private let recuperi = [0, 45, 60, 75, 90, 120, 150, 180, 210, 240]
    private let intervalli: [(Int, Int)] = [(4, 6), (5, 8), (6, 8), (6, 10), (8, 10), (8, 12), (10, 12), (10, 15), (12, 15), (15, 20), (20, 30)]
    private let tempi: [(Int, Int)] = [(20, 30), (30, 45), (30, 60), (45, 60), (60, 90)]

    var body: some View {
        let ripristina = !nuova && s.schedaModificata(r.id)
        let elimina = !nuova && s.schedaOriginale(r.id) == nil
        VStack(spacing: 0) {
            TestataFoglio(titolo: nuova ? "Nuova scheda" : "Modifica scheda",
                          sotto: "\(r.items.count) \(r.items.count == 1 ? "esercizio" : "esercizi") · \(r.items.reduce(0) { $0 + $1.s }) serie",
                          chiudi: { chiudi() }) {
                if ripristina || elimina {
                    Menu {
                        if ripristina {
                            Button(role: .destructive) { s.ripristinaScheda(r.id); chiudi() } label: {
                                Label { Text("Torna alla scheda originale"); Text("Togli tutte le modifiche") } icon: { Image(systemName: "arrow.uturn.backward") }
                            }
                        }
                        if elimina {
                            Button(role: .destructive) { s.eliminaScheda(r.id); chiudi() } label: { Label("Elimina questa scheda", systemImage: "trash") }
                        }
                    } label: { TondoIcona(icona: "ellipsis") }
                    .accessibilityLabel("Altre azioni")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Nome (per esempio: Torso C)", text: $r.name).campo()
                    TextField("Obiettivo (per esempio: petto + dorsali)", text: $r.focus).campo()
                    TitoloFoglio(testo: "Esercizi")
                    ForEach(Array(r.items.enumerated()), id: \.offset) { e in
                        VStack(spacing: 6) {
                            riga(e.offset)
                            if e.offset < insieme.count && insieme[e.offset] && e.offset < r.items.count - 1 {
                                Label("SUPERSERIE", systemImage: "link").font(.system(size: 11, weight: .heavy)).foregroundStyle(Tema.inchiostro)
                                    .padding(.horizontal, 10).padding(.vertical, 4).background(Tema.ambra, in: Capsule())
                            }
                        }
                    }
                    Button { scelta = .aggiungi } label: {
                        Label("Aggiungi esercizio", systemImage: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.testo)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Tema.linea, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                    }
                    .buttonStyle(.plain)
                    Text("«Superserie con il successivo»: i due esercizi si fanno uno dopo l'altro, con il recupero dopo il secondo.")
                        .font(.system(size: 12)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .pulsanteInFondo("Salva la scheda", attivo: !r.items.isEmpty && !r.name.trimmingCharacters(in: .whitespaces).isEmpty) { salva() }
        }
        .background(Tema.fondo.ignoresSafeArea())
        .sheet(item: $scelta) { c in
            ElencoEsercizi { ex in
                switch c {
                case .aggiungi:
                    let sec = s.esercizio(ex).unit == "sec"
                    r.items.append(RoutineItem(ex: ex, s: 3, lo: sec ? 30 : 8, hi: sec ? 45 : 12, rest: 90, sup: "", kg: nil))
                    insieme.append(false)
                case .cambia(let i):
                    r.items[i].ex = ex; r.items[i].kg = nil
                }
                scelta = nil
            }
            .foglio()
        }
        .onAppear {
            guard !pronto else { return }
            pronto = true
            // le superserie «Na/Nb» diventano «insieme al successivo»
            insieme = r.items.indices.map { i in
                let sup = r.items[i].sup
                return sup.hasSuffix("a") && i + 1 < r.items.count && r.items[i + 1].sup == String(sup.dropLast()) + "b"
            }
        }
    }

    private func riga(_ i: Int) -> some View {
        let it = r.items[i]
        let e = s.esercizio(it.ex)
        let sec = e.unit == "sec"
        let opzioni = (sec ? tempi : intervalli).map { "\($0.0)-\($0.1)" }
        let attuale = "\(it.lo)-\(it.hi)"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                MiniaturaEsercizio(ex: it.ex, lato: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.n).font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(e.m).font(.system(size: 12)).foregroundStyle(Tema.tenue)
                }
                Spacer(minLength: 4)
                Menu {
                    Button { scelta = .cambia(i) } label: { Label("Cambia esercizio", systemImage: "arrow.triangle.2.circlepath") }
                    Button { sposta(i, -1) } label: { Label("Sposta su", systemImage: "arrow.up") }.disabled(i == 0)
                    Button { sposta(i, 1) } label: { Label("Sposta giù", systemImage: "arrow.down") }.disabled(i == r.items.count - 1)
                    Section { Button(role: .destructive) { togli(i) } label: { Label("Togli dalla scheda", systemImage: "trash") } }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).frame(width: 32, height: 32).background(Tema.scheda2, in: Circle())
                }
                .foregroundStyle(Tema.testo)
            }
            HStack(spacing: 8) {
                // serie: − n +
                HStack(spacing: 0) {
                    Button { if r.items[safe: i].map({ $0.s > 1 }) == true { r.items[i].s -= 1; Haptic.leggero() } } label: { Image(systemName: "minus").frame(width: 28, height: 34) }
                        .disabled(it.s <= 1)
                    Text("\(it.s) serie").font(.system(size: 13, weight: .bold)).monospacedDigit().lineLimit(1)
                    Button { if r.items[safe: i].map({ $0.s < 8 }) == true { r.items[i].s += 1; Haptic.leggero() } } label: { Image(systemName: "plus").frame(width: 28, height: 34) }
                        .disabled(it.s >= 8)
                }
                .font(.system(size: 13, weight: .heavy)).foregroundStyle(Tema.testo)
                .background(Tema.scheda2, in: Capsule())
                Menu {
                    Picker(sec ? "Secondi" : "Ripetizioni", selection: Binding(
                        get: { r.items[safe: i].map { "\($0.lo)-\($0.hi)" } ?? attuale },
                        set: { v in let p = v.split(separator: "-").compactMap { Int($0) }; if p.count == 2, r.items.indices.contains(i) { r.items[i].lo = p[0]; r.items[i].hi = p[1] } })) {
                        ForEach(opzioni + (opzioni.contains(attuale) ? [] : [attuale]), id: \.self) { v in
                            Text(v.replacingOccurrences(of: "-", with: "–") + (sec ? "″" : " ripetizioni")).tag(v)
                        }
                    }
                } label: { chip(attuale.replacingOccurrences(of: "-", with: "–") + (sec ? "″" : " rip.")) }
                Menu {
                    // collegamenti «sicuri»: dopo «Togli» la riga sparisce e l'indice può non esserci più (prima l'app si chiudeva)
                    Picker("Recupero", selection: Binding(get: { r.items[safe: i]?.rest ?? it.rest },
                                                          set: { v in if r.items.indices.contains(i) { r.items[i].rest = v } })) {
                        ForEach(recuperi + (recuperi.contains(it.rest) ? [] : [it.rest]), id: \.self) { v in Text(v == 0 ? "Subito" : tempoMMSS(v)).tag(v) }
                    }
                } label: { chip(it.rest == 0 ? "subito" : tempoMMSS(it.rest), icona: "timer") }
                Spacer(minLength: 0)
            }
            if i < r.items.count - 1 && i < insieme.count {
                Toggle(isOn: Binding(
                    get: { insieme[safe: i] ?? false },
                    set: { v in
                        guard insieme.indices.contains(i) else { return }
                        insieme[i] = v
                        if v && i > 0 && insieme[i - 1] { insieme[i - 1] = false }
                        if v && i + 1 < insieme.count { insieme[i + 1] = false }
                    })) {
                    Text("Superserie con il successivo").font(.system(size: 14, weight: .medium))
                }
                .tint(Tema.ambra)
            }
        }
        .padding(14)
        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func chip(_ t: String, icona: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icona { Image(systemName: icona).font(.system(size: 12, weight: .bold)).foregroundStyle(Tema.tenue) }
            Text(t).font(.system(size: 13, weight: .bold)).monospacedDigit().lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .heavy)).foregroundStyle(Tema.tenue)
        }
        .foregroundStyle(Tema.testo)
        .padding(.horizontal, 10).frame(height: 34)
        .background(Tema.scheda2, in: Capsule())
    }

    private func sposta(_ i: Int, _ verso: Int) {
        let j = i + verso
        guard r.items.indices.contains(j) else { return }
        r.items.swapAt(i, j)
        insieme = Array(repeating: false, count: r.items.count)   // spostando, le coppie si rifanno a mano
        Haptic.leggero()
    }

    private func togli(_ i: Int) {
        r.items.remove(at: i)
        if i < insieme.count { insieme.remove(at: i) }
        if i > 0 && i - 1 < insieme.count { insieme[i - 1] = false }
    }

    private func salva() {
        // superserie: le coppie «insieme» diventano «1a/1b», «2a/2b»… nell'ordine
        var n = 1, i = 0
        while i < r.items.count {
            if i + 1 < r.items.count && i < insieme.count && insieme[i] {
                r.items[i].sup = "\(n)a"; r.items[i + 1].sup = "\(n)b"; n += 1; i += 2
            } else {
                r.items[i].sup = ""; i += 1
            }
        }
        r.name = r.name.trimmingCharacters(in: .whitespaces)
        s.salvaScheda(r)
        chiudi()
    }
}
