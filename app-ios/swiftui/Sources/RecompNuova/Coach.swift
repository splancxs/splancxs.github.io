import SwiftUI
import Security

// Il coach: una chat con Claude (API di Anthropic) che conosce il piano, i pasti di oggi, le schede, gli allenamenti,
// i record e il peso. La chiave API la incolla l'utente e sta solo nel portachiavi del telefono (mai nel progetto,
// che è pubblico, né nel backup). I dati di partenza si fissano all'inizio della chat (messaggio di sistema che non cambia:
// la cronologia va rimandata identica); ogni domanda porta con sé una riga con la situazione di quel momento.

enum ChiaveCoach {
    private static let servizio = "io.github.splancxs.recomp.coach"
    private static var base: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servizio, kSecAttrAccount as String: "anthropic"] }

    static func leggi() -> String? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var r: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data, let k = String(data: d, encoding: .utf8), !k.isEmpty else { return nil }
        return k
    }
    static func salva(_ k: String) {
        cancella()
        var q = base
        q[kSecValueData as String] = Data(k.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
    static func cancella() { SecItemDelete(base as CFDictionary) }
}

// MARK: i servizi: Google Gemini e Mistral hanno un piano gratuito; Claude (Anthropic) è a pagamento.
// Il servizio si sceglie nella schermata della chiave; salvando, la chiave si prova davvero (e se non va con quello scelto,
// si provano gli altri). Quello che funziona resta salvato in «coach.fornitore».

enum FornitoreCoach: String, CaseIterable {
    case gemini, mistral, claude

    // ipotesi dal formato della chiave, quando è sicuro (nil = non si capisce)
    static func ipotesi(_ chiave: String) -> FornitoreCoach? {
        if chiave.hasPrefix("sk-ant-") { return .claude }
        if chiave.hasPrefix("AIza") { return .gemini }
        return nil
    }
    // il servizio della chiave salvata
    static var attuale: FornitoreCoach {
        UserDefaults.standard.string(forKey: "coach.fornitore").flatMap(FornitoreCoach.init(rawValue:)) ?? .gemini
    }
    var nomeBreve: String {
        switch self { case .gemini: "Gemini"; case .mistral: "Mistral"; case .claude: "Claude" }
    }
    var nome: String {
        switch self { case .gemini: "Google Gemini"; case .mistral: "Mistral"; case .claude: "Claude" }
    }
    var gratis: Bool { self != .claude }
}

enum ClienteCoach {
    struct Risposta { let testo: String; let contenuto: Data?; let rifiuto: Bool }
    struct Errore: Error { let messaggio: String }

    static func chiedi(sistema: String, messaggi: [MessaggioCoach], chiave: String) async throws -> Risposta {
        switch FornitoreCoach.attuale {
        case .gemini: return try await gemini(sistema, messaggi, chiave)
        case .mistral: return try await mistral(sistema, messaggi, chiave)
        case .claude: return try await claude(sistema, messaggi, chiave)
        }
    }

    enum Prova { case va, nonVa, senzaRete }

    // la chiave funziona con questo servizio? (chiede solo l'elenco dei modelli: non consuma domande)
    static func prova(_ chiave: String, _ f: FornitoreCoach) async -> Prova {
        var r: URLRequest
        switch f {
        case .gemini:
            r = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=5")!)
            r.setValue(chiave, forHTTPHeaderField: "x-goog-api-key")
        case .mistral:
            r = URLRequest(url: URL(string: "https://api.mistral.ai/v1/models")!)
            r.setValue("Bearer \(chiave)", forHTTPHeaderField: "authorization")
        case .claude:
            r = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
            r.setValue(chiave, forHTTPHeaderField: "x-api-key")
            r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        r.timeoutInterval = 20
        guard let (_, risposta) = try? await URLSession.shared.data(for: r) else { return .senzaRete }
        return (risposta as? HTTPURLResponse)?.statusCode == 200 ? .va : .nonVa
    }

    // con quale servizio va la chiave: prima quello scelto (o quello che si capisce dal formato), poi gli altri
    static func riconosci(_ chiave: String, preferito: FornitoreCoach) async -> (FornitoreCoach?, Bool) {
        var ordine = [preferito] + FornitoreCoach.allCases.filter { $0 != preferito }
        if let i = FornitoreCoach.ipotesi(chiave) { ordine = [i] + ordine.filter { $0 != i } }
        var rete = false
        for f in ordine {
            switch await prova(chiave, f) {
            case .va: return (f, false)
            case .senzaRete: rete = true
            case .nonVa: break
            }
        }
        return (nil, rete)
    }

    // il testo davvero inviato con ogni domanda (con la riga della situazione di quel momento)
    private static func inviato(_ m: MessaggioCoach) -> String { m.contenuto.flatMap { String(data: $0, encoding: .utf8) } ?? m.testo }

    private static func manda(_ r: URLRequest) async throws -> (Int, [String: Any]) {
        let (dati, risposta): (Data, URLResponse)
        do { (dati, risposta) = try await URLSession.shared.data(for: r) } catch {
            throw Errore(messaggio: "Nessuna connessione: il coach ha bisogno di internet.")
        }
        let codice = (risposta as? HTTPURLResponse)?.statusCode ?? 0
        return (codice, (try? JSONSerialization.jsonObject(with: dati)) as? [String: Any] ?? [:])
    }

    private static func errore(_ codice: Int, _ j: [String: Any], _ nome: String) -> Errore {
        let msg = ((j["error"] as? [String: Any])?["message"] as? String) ?? (j["message"] as? String) ?? ""
        switch codice {
        case 400 where msg.localizedCaseInsensitiveContains("api key"), 401, 403:
            return Errore(messaggio: "La chiave non è valida. Controllala in «•••» → Cambia chiave.")
        case 429: return Errore(messaggio: "Hai fatto tante domande: il piano gratuito di \(nome) ha un limite. Riprova tra un po' (o domani).")
        case 500...599: return Errore(messaggio: "\(nome) è occupato in questo momento: riprova tra un minuto.")
        default: return Errore(messaggio: "Errore \(codice)" + (msg.isEmpty ? "." : ": \(msg)"))
        }
    }

    // MARK: Google Gemini (gratis con un account Google): scelgo il modello «Flash» più recente disponibile per la chiave

    // i modelli da provare, in ordine: quello che ha risposto l'ultima volta, poi gli altri «Flash» della chiave (l'elenco
    // si chiede una volta sola e si tiene), poi due di riserva
    private static func modelliGemini(_ chiave: String) async -> [String] {
        var lista = UserDefaults.standard.stringArray(forKey: "coach.modelliGemini") ?? []
        if lista.isEmpty {
            lista = await elencoGemini(chiave)
            if !lista.isEmpty { UserDefaults.standard.set(lista, forKey: "coach.modelliGemini") }
        }
        for riserva in ["gemini-2.5-flash", "gemini-2.0-flash"] where !lista.contains(riserva) { lista.append(riserva) }
        if let buono = UserDefaults.standard.string(forKey: "coach.modelloGemini") {
            lista.removeAll { $0 == buono }
            lista.insert(buono, at: 0)
        }
        return lista
    }

    // un modello che la chiave non può usare esce dall'elenco
    private static func togliModelloGemini(_ m: String) {
        let lista = (UserDefaults.standard.stringArray(forKey: "coach.modelliGemini") ?? []).filter { $0 != m }
        UserDefaults.standard.set(lista, forKey: "coach.modelliGemini")
        if UserDefaults.standard.string(forKey: "coach.modelloGemini") == m { UserDefaults.standard.removeObject(forKey: "coach.modelloGemini") }
    }

    private static func elencoGemini(_ chiave: String) async -> [String] {
        var r = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200")!)
        r.setValue(chiave, forHTTPHeaderField: "x-goog-api-key")
        guard let (codice, j) = try? await manda(r), codice == 200, let lista = j["models"] as? [[String: Any]] else { return [] }
        let scarta = ["lite", "image", "tts", "live", "audio", "embedding", "vision", "thinking", "8b"]
        let nomi = lista.compactMap { m -> String? in
            guard let n = (m["name"] as? String)?.replacingOccurrences(of: "models/", with: ""), n.contains("flash"),
                  (m["supportedGenerationMethods"] as? [String])?.contains("generateContent") == true,
                  !scarta.contains(where: { n.contains($0) }) else { return nil }
            return n
        }
        // prima la versione più nuova; a parità, quella stabile prima della «preview»
        func versione(_ n: String) -> Double { Double(n.replacingOccurrences(of: "gemini-", with: "").split(separator: "-").first ?? "0") ?? 0 }
        let ordinati = nomi.sorted { a, b in
            versione(a) != versione(b) ? versione(a) > versione(b) : (!a.contains("preview") && b.contains("preview"))
        }
        return Array(ordinati.prefix(4))
    }

    private static func gemini(_ sistema: String, _ messaggi: [MessaggioCoach], _ chiave: String) async throws -> Risposta {
        let contenuti: [[String: Any]] = messaggi.map { m in
            ["role": m.ruolo == "assistant" ? "model" : "user", "parts": [["text": m.ruolo == "assistant" ? m.testo : inviato(m)]]]
        }
        let corpo: [String: Any] = ["system_instruction": ["parts": [["text": sistema]]], "contents": contenuti,
                                    "generationConfig": ["maxOutputTokens": 4096]]
        var ultimo: Errore?
        var occupati: [String] = []
        let modelli = await modelliGemini(chiave)
        for giro in 0..<2 {
            // secondo giro: dopo una pausa, di nuovo il primo modello che era occupato
            let elenco = giro == 0 ? modelli : Array(occupati.prefix(1))
            if giro == 1 {
                guard !elenco.isEmpty else { break }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            for modello in elenco {
                var r = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modello):generateContent")!)
                r.httpMethod = "POST"; r.timeoutInterval = 120
                r.setValue("application/json", forHTTPHeaderField: "content-type")
                r.setValue(chiave, forHTTPHeaderField: "x-goog-api-key")
                r.httpBody = try JSONSerialization.data(withJSONObject: corpo)
                let (codice, j) = try await manda(r)
                if codice == 200 {
                    UserDefaults.standard.set(modello, forKey: "coach.modelloGemini")
                    let c = (j["candidates"] as? [[String: Any]])?.first
                    let parti = (c?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
                    let testo = parti.compactMap { $0["text"] as? String }.joined()
                    let bloccato = (c?["finishReason"] as? String) == "SAFETY" || j["promptFeedback"].flatMap { ($0 as? [String: Any])?["blockReason"] } != nil
                    return Risposta(testo: testo.trimmingCharacters(in: .whitespacesAndNewlines), contenuto: nil, rifiuto: bloccato)
                }
                let e = errore(codice, j, "Gemini")
                ultimo = e
                let msg = ((j["error"] as? [String: Any])?["message"] as? String) ?? ""
                // un modello che la chiave non può usare (non c'è o non è nel piano gratuito): fuori dall'elenco, provo il prossimo
                if codice == 404 || (codice == 429 && msg.contains("limit: 0")) || (codice == 400 && msg.localizedCaseInsensitiveContains("model")) {
                    togliModelloGemini(modello); continue
                }
                // occupato o al limite di domande per quel modello: provo il prossimo (ognuno ha il suo limite)
                if codice == 429 || codice >= 500 { if giro == 0 { occupati.append(modello) }; continue }
                throw e   // chiave sbagliata o altro: inutile insistere
            }
        }
        throw ultimo ?? Errore(messaggio: "Gemini non ha risposto.")
    }

    // MARK: Mistral (gratis con il piano «Experiment»)

    private static func mistral(_ sistema: String, _ messaggi: [MessaggioCoach], _ chiave: String) async throws -> Risposta {
        let lista: [[String: Any]] = [["role": "system", "content": sistema]] + messaggi.map { m in
            ["role": m.ruolo == "assistant" ? "assistant" : "user", "content": m.ruolo == "assistant" ? m.testo : inviato(m)]
        }
        var ultimo: Errore?
        for modello in ["mistral-medium-latest", "mistral-large-latest", "mistral-small-latest"] {
            var r = URLRequest(url: URL(string: "https://api.mistral.ai/v1/chat/completions")!)
            r.httpMethod = "POST"; r.timeoutInterval = 120
            r.setValue("application/json", forHTTPHeaderField: "content-type")
            r.setValue("Bearer \(chiave)", forHTTPHeaderField: "authorization")
            r.httpBody = try JSONSerialization.data(withJSONObject: ["model": modello, "messages": lista, "max_tokens": 4096] as [String: Any])
            let (codice, j) = try await manda(r)
            if codice == 200 {
                let testo = ((j["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String ?? ""
                return Risposta(testo: testo.trimmingCharacters(in: .whitespacesAndNewlines), contenuto: nil, rifiuto: false)
            }
            ultimo = errore(codice, j, "Mistral")
            // modello non disponibile per questa chiave, occupato o al limite: provo il prossimo
            if codice == 404 || codice == 400 || codice == 429 || codice >= 500 { continue }
            break
        }
        throw ultimo ?? Errore(messaggio: "Mistral non ha risposto.")
    }

    // MARK: Claude (a pagamento): la risposta si tiene intera e si rimanda così com'è

    private static func claude(_ sistema: String, _ messaggi: [MessaggioCoach], _ chiave: String) async throws -> Risposta {
        let lista: [[String: Any]] = messaggi.map { m in
            if m.ruolo == "assistant", let c = m.contenuto, let j = try? JSONSerialization.jsonObject(with: c) {
                return ["role": "assistant", "content": j]
            }
            return ["role": m.ruolo == "assistant" ? "assistant" : "user", "content": m.ruolo == "assistant" ? m.testo : inviato(m)]
        }
        let corpo: [String: Any] = [
            "model": "claude-opus-5-5",
            "max_tokens": 16000,
            "system": sistema,
            "messages": lista,
            "output_config": ["effort": "medium"],
            "cache_control": ["type": "ephemeral"],
            "fallbacks": "default",
        ]
        var r = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        r.httpMethod = "POST"; r.timeoutInterval = 180
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue(chiave, forHTTPHeaderField: "x-api-key")
        r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        r.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        r.httpBody = try JSONSerialization.data(withJSONObject: corpo)
        let (codice, j) = try await manda(r)
        guard codice == 200 else { throw errore(codice, j, "Claude") }
        let contenuto = j["content"] as? [[String: Any]] ?? []
        let testo = contenuto.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n\n")
        return Risposta(testo: testo.trimmingCharacters(in: .whitespacesAndNewlines),
                        contenuto: try JSONSerialization.data(withJSONObject: contenuto),
                        rifiuto: (j["stop_reason"] as? String) == "refusal")
    }
}

// MARK: i dati che il coach conosce

extension AppStore {
    // il messaggio di sistema, fissato all'inizio di ogni chat
    func contestoCoach() -> String {
        var t: [String] = []
        t.append("""
        Sei il coach personale dell'app Recomp, per alimentazione e allenamento in palestra. Rispondi sempre in italiano, in modo semplice, \
        diretto e concreto, come un allenatore esperto che conosce bene la persona. Di solito bastano 3–8 frasi o un elenco corto; usa i numeri \
        veri dei dati qui sotto (grammi, kcal, kg, serie, ripetizioni) e la virgola per i decimali. Non inventare dati che non ci sono: se manca \
        qualcosa, dillo. Porzioni da piatto vero (niente quantità ridicole). Se proponi cibi, scegli tra quelli del database del piano: sono quelli \
        che mangia. Per i carichi segui la progressione della scheda: prima le ripetizioni fino al massimo dell'intervallo in tutte le serie, poi \
        il peso sale di un passo. Niente legumi né proteine in polvere: non li mangia, non proporli mai. Niente diagnosi: per dolori o problemi di salute consiglia un medico o un fisioterapista. Ogni domanda inizia con \
        una riga tra parentesi quadre con la situazione di quel momento: usala, ma non ripeterla.
        """)
        t.append(#"""
        AZIONI [azioni-v1]: puoi proporre di registrare cose nell'app. Quando la persona dice di aver mangiato qualcosa fuori piano, di aver mangiato un pasto del piano, di aver preso la creatina, di essersi pesata, oppure ti chiede di cambiare un piatto di oggi, aggiungi IN FONDO alla risposta un blocco come questo:
        ```azioni
        [{"tipo":"fuori","fascia":3,"nome":"Pizza con gli amici","voci":[{"nome":"Pizza margherita","g":330,"kcal":800,"p":30,"c":105,"f":28}]}]
        ```
        Tipi di azione:
        - "fuori": pasto fuori piano. "fascia" = il numero della fascia che sostituisce (vedi PASTI DI OGGI e la riga [Adesso…]), oppure null se è in più. "voci" = i cibi, con i grammi stimati (porzioni vere) e kcal, proteine "p", carboidrati "c" e grassi "f" della porzione intera. Per un cibo del database dei cibi metti "fid" con il suo codice (i valori li prende l'app).
        - "mangiato": {"tipo":"mangiato","fascia":2} segna come mangiato il pasto del piano di quella fascia.
        - "creatina": {"tipo":"creatina"} segna la creatina di oggi.
        - "peso": {"tipo":"peso","kg":64.2} registra la pesata di oggi; aggiungi "vita" in cm solo se la dice.
        - "scambio": {"tipo":"scambio","fascia":2,"codice":"…"} mette al posto del piatto di oggi in quella fascia una delle alternative elencate in PASTI DI OGGI.
        Regole: il blocco solo quando c'è davvero qualcosa da registrare, uno solo per risposta, nel JSON i numeri con il punto. Valgono solo per oggi. Non proporre cose già fatte (guarda la riga [Adesso…]). L'app mostra una scheda con «Conferma»: non dire che è già registrato, scrivi per esempio «Te lo segno: conferma qui sotto». Se non sai i grammi, stima porzioni normali e dillo in una frase.
        """#)
        t.append("PIANO ALIMENTARE [piano \(piano.version)]: preparato dal suo nutrizionista (obiettivi qui sotto); acqua 2,5 l nei giorni ON, 2 l negli OFF. Il pasto libero della domenica (pranzo fuori, senza pesare, circa \(Int(stimaPastoLibero)) kcal) è già dentro le kcal del giorno. Gli scambi si fanno dentro lo stesso pasto con la dose del giorno (ON o OFF). Primo controllo dei numeri con il nutrizionista lunedì 2 novembre: se il peso si ferma, prima si controllano conteggio, acqua e sonno, poi eventualmente si tolgono 100 kcal.")
        let b = blocco
        t.append("BLOCCO DI ALLENAMENTO: blocco \(b.ciclo), settimana \(b.n) di 7 · \(b.fase).")
        // peso
        let ws = pesate
        if !ws.isEmpty {
            let ultimi = ws.suffix(21).map { "\(Cal.testo(Cal.date($0.d), "d MMM")) \(fmtPeso($0.kg))" + ($0.w.map { " (vita \(fmtNum($0)) cm)" } ?? "") }
            t.append("PESO (kg, mattina a digiuno): partenza 64,70 (28 settembre); obiettivo 62,5, arrivo stimato verso il 22 novembre (tra il 13/11 e il 13/12), ritmo atteso circa 0,35 kg a settimana. Ultime pesate: " + ultimi.joined(separator: " · ") + ".")
        }
        // settimana del piano
        let settimana = (0..<7).map { di -> String in
            let p = pianoGiorno(di)
            let wo = p.day.wo.flatMap { routine($0)?.name }
            return "\(p.day.name): \(p.day.type), \(Int(p.tot.k)) kcal" + (wo.map { ", palestra \($0) alle 16:30" } ?? "") + (p.hasFree ? ", pasto libero" : "")
        }
        t.append("SETTIMANA TIPO DEL PIANO: " + settimana.joined(separator: " · ") + ". Obiettivi giornalieri ON: \(fmtMigliaia(piano.daytypes["ON"]?.target[0] ?? 0)) kcal; OFF: \(fmtMigliaia(piano.daytypes["OFF_S"]?.target[0] ?? 0)) kcal; proteine \(Int(piano.daytypes["ON"]?.target[1] ?? 0)) g.")
        // i pasti di oggi, con i grammi
        let oggi = pianoOggi
        var pasti: [String] = []
        for m in oggi.meals {
            if m.free { pasti.append("Fascia \(m.si) · \(m.time) \(m.label): pasto libero fuori, senza pesare (circa \(Int(stimaPastoLibero)) kcal; un primo o un secondo con contorno, oppure una pizza)"); continue }
            let ingr = m.lines.map { "\(piano.foodName($0.f)) \(Int($0.g)) \(piano.unitaPeso($0.f))" }.joined(separator: ", ")
            let alt = (piano.variants[m.slot] ?? [:]).keys.sorted().filter { $0 != m.code }
                .map { "\($0) = \(piano.recipe($0).name) \(Int(piano.sum(piano.mealLines(m.slot, $0)).k)) kcal" }
            pasti.append("Fascia \(m.si) · \(m.time) \(m.label): \(piano.recipe(m.code).name) [codice \(m.code)] — \(ingr) (\(Int(m.tot.k)) kcal, P \(fmtNum(r1(m.tot.p))), C \(fmtNum(r1(m.tot.c))), G \(fmtNum(r1(m.tot.fa))))"
                         + (alt.isEmpty ? "" : ". Alternative: " + alt.joined(separator: "; ")))
        }
        t.append("PASTI DI OGGI (\(oggi.day.name), giorno \(oggi.conv.isEmpty ? oggi.day.type : oggi.conv), obiettivo \(Int(oggi.dt.target[0])) kcal, P \(Int(oggi.dt.target[1])), C \(Int(oggi.dt.target[2])), G \(Int(oggi.dt.target[3]))):\n" + pasti.joined(separator: "\n"))
        // schede
        let schede = routines.map { r in
            "\(r.name) (\(r.day), \(r.focus)): " + r.items.map { "\(nomeBreve($0.ex)) \($0.s)×\($0.lo)–\($0.hi)" + ($0.rest > 0 ? " rec. \(tempoMMSS($0.rest))" : "") + ($0.sup.isEmpty ? "" : " [superserie \($0.sup)]") }.joined(separator: "; ")
        }
        t.append("SCHEDE:\n" + schede.joined(separator: "\n"))
        // ultimi allenamenti
        let ultimi = cronologia.prefix(8).map { w -> String in
            let es = w.items.map { it in
                let serie = it.sets.filter(\.isWork).map { esercizio(it.ex).unit == "sec" ? "\($0.r ?? 0)″" : "\(peso(it.ex, $0.kg))×\($0.r ?? 0)" + ($0.rpe.map { [" facile", " giusta", " al limite"][max(0, min(2, $0 - 1))] } ?? "") }
                return "\(nomeBreve(it.ex)) \(serie.joined(separator: ", "))"
            }
            return "\(Cal.testo(Date(timeIntervalSince1970: w.start / 1000), "EEE d MMM")) \(w.name), \(w.minutes)′, \(fmtMigliaia(w.volume)) kg: " + es.joined(separator: "; ")
        }
        if !ultimi.isEmpty { t.append("ULTIMI ALLENAMENTI (pesi in \(d.lbEx.isEmpty ? "kg" : "kg, tranne gli esercizi in libbre"); sforzo segnato dall'utente):\n" + ultimi.joined(separator: "\n")) }
        // record
        let esercizi = Array(Set(cronologia.flatMap { $0.items.map(\.ex) })).sorted()
        let rec = esercizi.compactMap { ex -> String? in
            let r = primati(ex)
            if esercizio(ex).unit == "sec" { return r.sec > 0 ? "\(nomeBreve(ex)) \(r.sec)″" : nil }
            return r.kg > 0 ? "\(nomeBreve(ex)) \(pesoConUnita(ex, r.kg)) (1RM stimato \(pesoConUnita(ex, r1(r.e1))))" : nil
        }
        if !rec.isEmpty { t.append("RECORD: " + rec.joined(separator: " · ")) }
        // database dei cibi
        let cibi = piano.foods.values.sorted { $0.n < $1.n }.map { "\($0.id) = \($0.n) \(Int($0.k)) kcal/100 g (P \(fmtNum($0.p)), C \(fmtNum($0.c)), G \(fmtNum($0.f)))" }
        t.append("DATABASE DEI CIBI DEL PIANO (codice = nome, valori per 100 g):\n" + cibi.joined(separator: "\n"))
        return t.joined(separator: "\n\n")
    }

    // la riga con la situazione di adesso, attaccata a ogni domanda
    func statoAdesso() -> String {
        let t = totaliMangiati()
        let plan = pianoOggi
        let segnati = Set(mangiati())
        let fasce = plan.meals.map { m -> String in
            let nome = m.label.components(separatedBy: " (").first ?? m.label
            if m.free { return "\(m.si) \(nome) libero" }
            if fuoriPerFascia(m.si) != nil { return "\(m.si) \(nome) fuori piano" }
            return "\(m.si) \(nome) \(m.code)" + (segnati.contains(m.si) ? " ✓" : "")
        }
        let fuori = fuoriOggi().map { "\($0.nome) \(Int($0.tot.k)) kcal" }
        var palestra = "nessun allenamento oggi"
        if let a = d.active { palestra = "allenamento \(a.name) in corso" }
        else if let rid = schedaOggi, let r = routine(rid) { palestra = "\(r.name) " + (fattoOggi(rid) ? "già fatto" : "ancora da fare") }
        let peso = pesate.last.map { "ultimo peso \(fmtPeso($0.kg)) kg (\(Cal.testo(Cal.date($0.d), "d MMM")))" } ?? "nessuna pesata"
        return "[Adesso: \(Cal.testo(Date(), "EEEE d MMMM")), ore \(Cal.fmtOra.string(from: Date())). Mangiato oggi \(Int(t.k)) kcal (P \(Int(t.p)), C \(Int(t.c)), G \(Int(t.fa))) su \(Int(plan.dt.target[0])). Fasce di oggi (numero, pasto, piatto; ✓ = mangiato): \(fasce.joined(separator: ", "))\(fuori.isEmpty ? "" : "; fuori piano: " + fuori.joined(separator: ", ")). Palestra: \(palestra). Creatina \(creatinaPresa() ? "presa" : "non ancora presa"). \(peso).]"
    }
}

// MARK: la chat

struct CoachView: View {
    @EnvironmentObject var s: AppStore
    @Environment(\.dismiss) private var chiudi
    @State private var testo = ""
    @State private var attesa = false
    @State private var errore = ""
    @State private var chiave = ChiaveCoach.leggi()
    @State private var nuovaChiave = ""
    @State private var cambiaChiave = false
    @State private var scelto: FornitoreCoach = .gemini
    @State private var provando = false
    @State private var esito = ""
    @FocusState private var scrivendo: Bool

    private let suggerimenti = ["Com'è andata questa settimana?", "Cosa mangio stasera?", "Perché non salgo alla chest press?",
                                "Sto andando verso l'obiettivo di peso?", "Oggi ho fame: cosa posso aggiungere?", "Cosa miglioro nella scheda?"]

    var body: some View {
        VStack(spacing: 0) {
            testata
            if chiave == nil || cambiaChiave { collega } else { chat }
        }
        .background(Tema.fondo.ignoresSafeArea())
        .onAppear {
            // una chat iniziata prima delle azioni o con un'altra dieta ricomincia: il coach parlerebbe del piano vecchio
            let sistema = s.d.coachSistema
            if !sistema.isEmpty && (!sistema.contains("[azioni-v1]") || !sistema.contains("[piano \(s.piano.version)]")) {
                s.d.coach = []; s.d.coachSistema = ""
            }
        }
    }

    private var testata: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "sparkles").font(.system(size: 18, weight: .bold)).foregroundStyle(Tema.inchiostro)
                .frame(width: 40, height: 40).background(Argento(raggio: 20))
            VStack(alignment: .leading, spacing: 0) {
                Text("COACH").font(.sport(28))
                Text((chiave == nil ? "Da collegare" : FornitoreCoach.attuale.nome) + " · conosce piano, schede e pesi").font(.system(size: 12)).foregroundStyle(Tema.tenue)
            }
            Spacer()
            Menu {
                // mentre il coach risponde la chat non si ricomincia e la chiave non si cambia
                Button { s.d.coach = []; s.d.coachSistema = ""; errore = "" } label: { Label("Nuova chat", systemImage: "square.and.pencil") }
                    .disabled(attesa)
                Button { cambiaChiave = true } label: { Label("Cambia chiave", systemImage: "key") }
                    .disabled(attesa)
                Section {
                    Button(role: .destructive) { ChiaveCoach.cancella(); chiave = nil } label: { Label("Togli la chiave", systemImage: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).frame(width: 34, height: 34).background(Tema.scheda, in: Circle())
            }
            .foregroundStyle(Tema.testo)
            Button { chiudi() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 34, height: 34).background(Tema.scheda, in: Circle()) }
                .foregroundStyle(Tema.testo).accessibilityLabel("Chiudi")
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 10)
    }

    // la prima volta: incolla una chiave (gratis: Google Gemini o Mistral; a pagamento: Claude)
    private var collega: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Collega il coach").font(.system(size: 22, weight: .bold))
                Text("Serve una chiave di un servizio di intelligenza artificiale. Le prime due sono gratis: crei la chiave, la copi e la incolli qui sotto. Resta solo nel portachiavi di questo iPhone.")
                    .font(.system(size: 14)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
                servizio("Google Gemini", "Gratis · consigliato", "Basta un account Google, senza carta. In Google AI Studio tocca «Create API key».",
                         "https://aistudio.google.com/apikey", "Prendi la chiave di Gemini", Tema.verde)
                servizio("Mistral", "Gratis", "Piano «Experiment» senza carta; chiede il numero di telefono. In «API Keys» crea una chiave.",
                         "https://console.mistral.ai/api-keys", "Prendi la chiave di Mistral", Tema.verde)
                servizio("Claude", "A pagamento", "Il più bravo, ma ogni domanda costa qualche centesimo dal credito di Anthropic.",
                         "https://console.anthropic.com/settings/keys", "Prendi la chiave di Claude", Tema.ambra)
                Text("Con i piani gratis, Google e Mistral possono usare le domande per migliorare i loro modelli: il coach manda i dati di dieta e allenamenti, senza nome.")
                    .font(.system(size: 12)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
                SecureField("Incolla qui la chiave", text: $nuovaChiave)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(14).background(Tema.scheda, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Picker("Di quale servizio è la chiave", selection: $scelto) {
                    ForEach(FornitoreCoach.allCases, id: \.self) { f in Text(f.nomeBreve).tag(f) }
                }
                .pickerStyle(.segmented)
                .onChange(of: nuovaChiave) { _, k in if let i = FornitoreCoach.ipotesi(k.trimmingCharacters(in: .whitespacesAndNewlines)) { scelto = i } }
                if !esito.isEmpty {
                    Text(esito).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.rosso).fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    salvaChiave()
                } label: {
                    HStack(spacing: 8) {
                        if provando { ProgressView().tint(Tema.fondo) }
                        Text(provando ? "Provo la chiave…" : "Salva la chiave")
                    }
                }
                .buttonStyle(PulsantePieno(colore: Tema.testo, testo: Tema.fondo))
                .disabled(provando || nuovaChiave.trimmingCharacters(in: .whitespaces).isEmpty)
                if cambiaChiave { Button("Annulla") { cambiaChiave = false }.buttonStyle(PulsanteLeggero()) }
            }
            .padding(20)
        }
    }

    // salvando, la chiave si prova: resta il servizio con cui funziona davvero
    private func salvaChiave() {
        let k = nuovaChiave.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty, !provando else { return }
        provando = true; esito = ""
        Task {
            let (f, rete) = await ClienteCoach.riconosci(k, preferito: scelto)
            provando = false
            guard let f else {
                esito = rete ? "Non riesco a provare la chiave: controlla la connessione."
                    : "La chiave non funziona con nessun servizio: copiala di nuovo tutta, senza spazi."
                return
            }
            ChiaveCoach.salva(k)
            UserDefaults.standard.set(f.rawValue, forKey: "coach.fornitore")
            UserDefaults.standard.removeObject(forKey: "coach.modelloGemini")
            UserDefaults.standard.removeObject(forKey: "coach.modelliGemini")
            chiave = k; nuovaChiave = ""; cambiaChiave = false; errore = ""
            Haptic.ok()
        }
    }

    private func servizio(_ nome: String, _ prezzo: String, _ come: String, _ url: String, _ link: String, _ colore: Color) -> some View {
        Scheda(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(nome).font(.system(size: 17, weight: .bold))
                    Spacer()
                    Text(prezzo.uppercased()).font(.system(size: 11, weight: .heavy)).foregroundStyle(Tema.inchiostro)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(colore, in: Capsule())
                }
                Text(come).font(.system(size: 13)).foregroundStyle(Tema.tenue).fixedSize(horizontal: false, vertical: true)
                Link(destination: URL(string: url)!) {
                    Label(link, systemImage: "arrow.up.right.square").font(.system(size: 14, weight: .semibold))
                }
            }
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if s.d.coach.isEmpty {
                            Text("Chiedimi qualcosa su pasti, allenamenti o peso: conosco il tuo piano, le schede e i tuoi numeri.")
                                .font(.system(size: 14)).foregroundStyle(Tema.tenue)
                            FlowLayout(spacing: 8) {
                                ForEach(suggerimenti, id: \.self) { q in
                                    Button { invia(q) } label: {
                                        Text(q).font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.testo)
                                            .padding(.horizontal, 12).padding(.vertical, 9).background(Tema.scheda, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        ForEach(s.d.coach) { m in bolla(m).id(m.id) }
                        if attesa {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Il coach sta pensando…").font(.system(size: 14)).foregroundStyle(Tema.tenue)
                            }
                            .id("attesa")
                        }
                        if !errore.isEmpty {
                            Text(errore).font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.rosso).id("errore")
                        }
                        if s.d.coach.count > 30 {
                            Text("La chat è lunga: con «•••» → Nuova chat le risposte tornano più veloci e i dati si aggiornano.").font(.system(size: 12)).foregroundStyle(Tema.tenue)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: s.d.coach.count) { _, _ in withAnimation { proxy.scrollTo(s.d.coach.last?.id, anchor: .bottom) } }
                .onChange(of: attesa) { _, v in if v { withAnimation { proxy.scrollTo("attesa", anchor: .bottom) } } }
                .onAppear { proxy.scrollTo(s.d.coach.last?.id, anchor: .bottom) }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Scrivi al coach…", text: $testo, axis: .vertical)
                    .lineLimit(1...5).focused($scrivendo)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Button { invia(testo) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 17, weight: .heavy)).foregroundStyle(Tema.fondo)
                        .frame(width: 44, height: 44).background(Tema.testo, in: Circle())
                }
                .disabled(attesa || testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(attesa || testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Tema.fondo)
        }
    }

    private func bolla(_ m: MessaggioCoach) -> some View {
        let mio = m.ruolo == "user"
        let parti: (testo: String, json: String?) = mio ? (m.testo, nil) : AzioniCoach.separa(m.testo)
        let testo = (try? AttributedString(markdown: parti.testo, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(parti.testo)
        let azioni = parti.json.map { s.azioni($0) } ?? []
        return VStack(alignment: .leading, spacing: 8) {
            if !parti.testo.isEmpty {
                HStack {
                    if mio { Spacer(minLength: 40) }
                    Text(testo).font(.system(size: 15)).foregroundStyle(mio ? Tema.inchiostro : Tema.testo)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background {
                            if mio { Argento(raggio: 18) } else { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Tema.scheda) }
                        }
                    if !mio { Spacer(minLength: 24) }
                }
            }
            ForEach(Array(azioni.enumerated()), id: \.offset) { e in
                SchedaAzione(azione: e.element, stato: stato(m, e.offset, e.element),
                             conferma: { conferma(m, e.offset, e.element) }, scarta: { scarta(m, e.offset) })
                    .padding(.trailing, 24)
            }
        }
    }

    // a che punto è l'azione i della risposta m
    private func stato(_ m: MessaggioCoach, _ i: Int, _ a: AzioneCoach) -> SchedaAzione.Stato {
        if m.fatte?.contains(i) == true { return .fatta }
        if m.scartate?.contains(i) == true { return .scartata }
        let giorno = Date(timeIntervalSince1970: m.t / 1000)
        if Cal.key(giorno) != s.oggiKey { return .bloccata("Era per \(Cal.testo(giorno, "EEEE d MMMM")): ormai è passata.") }
        if let motivo = s.motivoAzione(a) { return .bloccata(motivo) }
        return .daFare
    }

    private func conferma(_ m: MessaggioCoach, _ i: Int, _ a: AzioneCoach) {
        guard let k = s.d.coach.firstIndex(where: { $0.id == m.id }), stato(m, i, a) == .daFare else { return }
        s.applica(a)
        s.d.coach[k].fatte = (s.d.coach[k].fatte ?? []) + [i]
    }

    private func scarta(_ m: MessaggioCoach, _ i: Int) {
        guard let k = s.d.coach.firstIndex(where: { $0.id == m.id }) else { return }
        s.d.coach[k].scartate = (s.d.coach[k].scartate ?? []) + [i]
        Haptic.leggero()
    }

    private func invia(_ domanda: String) {
        let q = domanda.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let k = chiave, !q.isEmpty, !attesa else { return }
        if s.d.coach.isEmpty || s.d.coachSistema.isEmpty { s.d.coachSistema = s.contestoCoach() }
        let inviato = s.statoAdesso() + "\n\n" + q
        let domanda = MessaggioCoach(ruolo: "user", testo: q, contenuto: Data(inviato.utf8), t: Cal.ms())
        s.d.coach.append(domanda)
        testo = ""; errore = ""; attesa = true
        Haptic.leggero()
        Task {
            // la domanda si toglie per id (non «l'ultima»): nel frattempo la chat può essere cambiata
            do {
                let r = try await ClienteCoach.chiedi(sistema: s.d.coachSistema, messaggi: s.d.coach, chiave: k)
                // la risposta vale solo se la domanda è ancora l'ultima della chat (non ricominciata nel frattempo)
                guard s.d.coach.last?.id == domanda.id else { attesa = false; return }
                if r.rifiuto || r.testo.isEmpty {
                    s.d.coach.removeAll { $0.id == domanda.id }
                    errore = "Il coach non può rispondere a questa domanda: prova a chiederla in un altro modo."
                    testo = q
                } else {
                    s.d.coach.append(MessaggioCoach(ruolo: "assistant", testo: r.testo, contenuto: r.contenuto, t: Cal.ms()))
                    Haptic.ok()
                }
            } catch {
                if s.d.coach.contains(where: { $0.id == domanda.id }) {
                    s.d.coach.removeAll { $0.id == domanda.id }
                    errore = (error as? ClienteCoach.Errore)?.messaggio ?? "Qualcosa è andato storto: riprova."
                    testo = q
                }
            }
            attesa = false
        }
    }
}
