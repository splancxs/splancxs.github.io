import Foundation
import FoundationModels
import SwiftUI

// MARK: Apple Intelligence sul telefono (FoundationModels, iOS 26+)
// Gira direttamente sull'iPhone (15 Pro / Pro Max e successivi), gratis, senza chiave API e anche senza internet.
// Il modello locale ha una finestra di circa 4.096 token: invece di mandare tutto il database in una volta sola,
// riceve un contesto compatto (regole + situazione e pasti di oggi) e usa gli strumenti (Tool) per leggere
// cibi, schede, allenamenti, record e pesate solo quando servono, o per preparare le schede «Conferma» delle azioni.

enum AppleCoach {
    enum Stato: Equatable {
        case pronto
        case daAttivare       // il telefono la supporta ma è spenta in Impostazioni
        case inPreparazione   // iOS sta scaricando il modello
        case nonSupportato    // iPhone precedente al 15 Pro o iOS < 26
    }

    static var stato: Stato {
        guard #available(iOS 26.0, *) else { return .nonSupportato }
        switch SystemLanguageModel.default.availability {
        case .available: return .pronto
        case .unavailable(let motivo):
            switch motivo {
            case .appleIntelligenceNotEnabled: return .daAttivare
            case .modelNotReady: return .inPreparazione
            default: return .nonSupportato
            }
        }
    }

    static var disponibile: Bool { stato == .pronto }

    static var avvisoStato: String? {
        switch stato {
        case .pronto: return nil
        case .daAttivare: return "Per usarla attiva Apple Intelligence in Impostazioni → Apple Intelligence e Siri."
        case .inPreparazione: return "iOS sta finendo di scaricare il modello di Apple Intelligence: riprova tra qualche minuto."
        case .nonSupportato: return "Questo dispositivo o la versione di iOS non supporta Apple Intelligence."
        }
    }

    // risposta alla chat del Coach usando il modello sul dispositivo + strumenti
    @MainActor
    static func chiedi(store: AppStore, messaggi: [MessaggioCoach]) async throws -> ClienteCoach.Risposta {
        guard #available(iOS 26.0, *) else {
            throw ClienteCoach.Errore(messaggio: "Apple Intelligence richiede iOS 26 o successivo.")
        }
        if let avviso = avvisoStato {
            throw ClienteCoach.Errore(messaggio: avviso)
        }
        let snapshot = store.snapshotAppleCoach()
        let memorie = RaccoglitoreMemorie()
        let r = try await chiediConRipiego(snapshot: snapshot, messaggi: messaggi, memorie: memorie)
        for nota in memorie.tutte() { store.aggiungiMemoriaCoach(nota) }
        return r
    }

    // risposta breve per i messaggi automatici (mattina, sera, domenica), senza strumenti
    static func chiediBigliettino(sistema: String, richiesta: String) async throws -> ClienteCoach.Risposta {
        guard #available(iOS 26.0, *), disponibile else {
            throw ClienteCoach.Errore(messaggio: "Apple Intelligence non disponibile.")
        }
        let sessione = LanguageModelSession(model: .default, instructions: sistema)
        let r = try await sessione.respond(to: richiesta)
        return ClienteCoach.Risposta(testo: r.content.trimmingCharacters(in: .whitespacesAndNewlines), contenuto: nil, rifiuto: false)
    }

    @available(iOS 26.0, *)
    private static func chiediConRipiego(snapshot: SnapshotCoach, messaggi: [MessaggioCoach], memorie: RaccoglitoreMemorie) async throws -> ClienteCoach.Risposta {
        // se la chat è lunga e supera i 4.096 token del modello locale, riprovo con meno cronologia
        for quanti in [6, 2, 1] {
            let raccoglitore = RaccoglitoreAzioni()
            let strumenti: [any Tool] = [
                StrumentoCibi(snapshot: snapshot),
                StrumentoPalestra(snapshot: snapshot),
                StrumentoPeso(snapshot: snapshot),
                StrumentoAzione(raccoglitore: raccoglitore),
                StrumentoMemoria(memorie: memorie)
            ]
            let sessione = LanguageModelSession(
                model: .default,
                tools: strumenti,
                instructions: snapshot.istruzioni
            )
            let prompt = costruisciPrompt(messaggi: messaggi, ultimi: quanti)
            do {
                let r = try await sessione.respond(to: prompt)
                var testo = r.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let blocco = raccoglitore.bloccoAzioni()
                if let blocco, !testo.contains("```azioni") {
                    testo = (testo.isEmpty ? "Ecco qui sotto:" : testo) + "\n\n" + blocco
                }
                return ClienteCoach.Risposta(testo: testo, contenuto: nil, rifiuto: false)
            } catch let err as LanguageModelSession.GenerationError {
                switch err {
                case .exceededContextWindowSize where quanti > 1:
                    continue
                case .guardrailViolation, .refusal:
                    return ClienteCoach.Risposta(testo: "", contenuto: nil, rifiuto: true)
                default:
                    throw traduciErrore(err)
                }
            } catch {
                let desc = String(describing: error)
                if desc.localizedCaseInsensitiveContains("context") && quanti > 1 { continue }
                if desc.localizedCaseInsensitiveContains("refusal") || desc.localizedCaseInsensitiveContains("guardrail") {
                    return ClienteCoach.Risposta(testo: "", contenuto: nil, rifiuto: true)
                }
                throw traduciErrore(error)
            }
        }
        // ultimo tentativo di emergenza: senza strumenti e solo con l'ultima domanda
        let sessione = LanguageModelSession(model: .default, instructions: snapshot.istruzioniCortissime)
        let ultima = costruisciPrompt(messaggi: messaggi, ultimi: 1)
        let r = try await sessione.respond(to: ultima)
        return ClienteCoach.Risposta(testo: r.content.trimmingCharacters(in: .whitespacesAndNewlines), contenuto: nil, rifiuto: false)
    }

    private static func costruisciPrompt(messaggi: [MessaggioCoach], ultimi: Int) -> String {
        guard let corrente = messaggi.last else { return "" }
        let testoCorrente = corrente.contenuto.flatMap { String(data: $0, encoding: .utf8) } ?? corrente.testo
        let precedenti = messaggi.dropLast().suffix(max(0, ultimi - 1))
        guard !precedenti.isEmpty else { return testoCorrente }
        let storia = precedenti.map { m -> String in
            let chi = m.ruolo == "assistant" ? "Coach" : "Utente"
            let pulito = AzioniCoach.separa(m.testo).testo
            let corto = pulito.count > 360 ? String(pulito.prefix(360)) + "…" : pulito
            return "\(chi): \(corto)"
        }.joined(separator: "\n")
        return "Messaggi precedenti:\n\(storia)\n\nDomanda attuale:\n\(testoCorrente)"
    }

    private static func traduciErrore(_ error: Error) -> ClienteCoach.Errore {
        let d = error.localizedDescription
        if d.localizedCaseInsensitiveContains("locale") || d.localizedCaseInsensitiveContains("language") {
            return ClienteCoach.Errore(messaggio: "Apple Intelligence non supporta ancora la lingua impostata sul telefono.")
        }
        if let avviso = avvisoStato { return ClienteCoach.Errore(messaggio: avviso) }
        return ClienteCoach.Errore(messaggio: "Apple Intelligence non è riuscita a rispondere: prova a fare una domanda più breve o avvia una Nuova chat.")
    }
}

// MARK: fotografia immutabile dei dati per gli strumenti (Sendable)

struct SnapshotCoach: Sendable {
    let istruzioni: String
    let istruzioniCortissime: String
    let cibi: [(id: String, nome: String, riga: String)]
    let schede: String
    let allenamenti: String
    let record: String
    let peso: String
}

extension AppStore {
    func snapshotAppleCoach() -> SnapshotCoach {
        let b = blocco
        let oggi = pianoOggi
        var pasti: [String] = []
        for m in oggi.meals {
            if m.free {
                pasti.append("Fascia \(m.si) (\(m.time) \(m.label)): pasto libero fuori (~\(Int(stimaPastoLibero)) kcal)")
                continue
            }
            let ingr = m.lines.map { "\(piano.nome($0)) \(Int($0.g)) \(piano.unitaPeso($0.f))" }.joined(separator: ", ")
            let alt = (piano.variants[m.slot] ?? [:]).keys.sorted().filter { $0 != m.code }
                .map { "\($0)=\(piano.recipe($0).name)" }
            pasti.append("Fascia \(m.si) (\(m.time) \(m.label)): \(piano.recipe(m.code).name) [codice \(m.code)] — \(ingr) (\(Int(m.tot.k)) kcal, P \(Int(m.tot.p)), C \(Int(m.tot.c)), G \(Int(m.tot.fa)))"
                         + (alt.isEmpty ? "" : ". Alternative: " + alt.joined(separator: "; ")))
        }
        let uPeso = pesate.last.map { "\(fmtPeso($0.kg)) kg (\(Cal.testo(Cal.date($0.d), "d MMM")))" } ?? "n/d"
        let memTesto = d.coachMem.isEmpty ? "" : "\nMEMORIA DEL COACH (cose da ricordare sempre su di lui):\n" + d.coachMem.map { "- \($0)" }.joined(separator: "\n")
        let istruzioni = """
        Sei il coach personale dell'app Recomp (alimentazione e palestra). Rispondi sempre in italiano, dando del tu, in modo semplice, diretto e concreto (3–6 frasi o un elenco corto). Usa i numeri veri (grammi, kcal, kg, serie, ripetizioni) e la virgola per i decimali. Non inventare dati. Niente legumi né proteine in polvere: non li mangia mai. Non cambiare gli obiettivi calorici: li decide il nutrizionista.
        Blocco \(b.ciclo), settimana \(b.n)/7 (\(b.fase)). Obiettivi ON: \(Int(piano.daytypes["ON"]?.target[0] ?? 0)) kcal; OFF: \(Int(piano.daytypes["OFF_S"]?.target[0] ?? 0)) kcal; proteine \(Int(piano.daytypes["ON"]?.target[1] ?? 0)) g. Ultimo peso: \(uPeso) (obiettivo 62,5 kg).\(memTesto)
        PASTI DI OGGI (\(oggi.day.name), \(oggi.conv.isEmpty ? oggi.day.type : oggi.conv), target \(Int(oggi.dt.target[0])) kcal, P \(Int(oggi.dt.target[1])), C \(Int(oggi.dt.target[2])), G \(Int(oggi.dt.target[3]))):
        \(pasti.joined(separator: "\n"))
        STRUMENTI:
        - Se chiede cibi o sostituzioni, usa «cercaCibi».
        - Se chiede di schede, esercizi, carichi o allenamenti, usa «schedeAllenamenti».
        - Se chiede dell'andamento del peso o della settimana, usa «storicoPeso».
        - Quando dice di aver mangiato un pasto del piano, un cibo fuori piano, preso la creatina, essersi pesato, o chiede di scambiare un piatto di oggi, chiama «proponiAzione» e digli di confermare nella scheda sotto la risposta.
        - Quando chiede di ricordarti qualcosa per il futuro (abitudini, orari, macchinari della palestra, preferenze), chiama «ricordaSempre» per salvarlo nella memoria permanente.
        """
        let cortissime = """
        Sei il coach di Recomp (dieta e palestra). Rispondi in italiano, diretto e breve (3–5 frasi). Niente legumi né proteine in polvere.
        Oggi (\(oggi.day.name)): target \(Int(oggi.dt.target[0])) kcal (P \(Int(oggi.dt.target[1])), C \(Int(oggi.dt.target[2])), G \(Int(oggi.dt.target[3]))).
        \(pasti.joined(separator: "\n"))
        """
        let cibi = piano.foods.values.sorted { $0.n < $1.n }.map { f in
            (id: f.id, nome: f.n.lowercased(), riga: "\(f.id) = \(f.n): \(Int(f.k)) kcal/100g (P \(fmtNum(f.p)), C \(fmtNum(f.c)), G \(fmtNum(f.f)))")
        }
        let schede = routines.map { r in
            "\(r.name) (\(r.day), \(r.focus)): " + r.items.map { "\(nomeBreve($0.ex)) \($0.s)×\($0.lo)–\($0.hi)" + ($0.rest > 0 ? " rec.\(tempoMMSS($0.rest))" : "") }.joined(separator: "; ")
        }.joined(separator: "\n")
        let ultimi = cronologia.prefix(6).map { w -> String in
            let es = w.items.map { it in
                let serie = it.sets.filter(\.isWork).map { esercizio(it.ex).unit == "sec" ? "\($0.r ?? 0)″" : "\(peso(it.ex, $0.kg))×\($0.r ?? 0)" + ($0.rpe.map { [" facile", " giusta", " limite"][max(0, min(2, $0 - 1))] } ?? "") }
                return "\(nomeBreve(it.ex)) \(serie.joined(separator: ", "))"
            }
            return "\(Cal.testo(Date(timeIntervalSince1970: w.start / 1000), "d MMM")) \(w.name) (\(w.minutes)′, \(fmtMigliaia(w.volume)) kg): " + es.joined(separator: "; ")
        }.joined(separator: "\n")
        let esercizi = Array(Set(cronologia.flatMap { $0.items.map(\.ex) })).sorted()
        let rec = esercizi.compactMap { ex -> String? in
            let r = primati(ex)
            if esercizio(ex).unit == "sec" { return r.sec > 0 ? "\(nomeBreve(ex)) \(r.sec)″" : nil }
            return r.kg > 0 ? "\(nomeBreve(ex)) \(pesoConUnita(ex, r.kg)) (1RM \(pesoConUnita(ex, r1(r.e1))))" : nil
        }.joined(separator: " · ")
        let ws = pesate.suffix(18).map { "\(Cal.testo(Cal.date($0.d), "d MMM")) \(fmtPeso($0.kg)) kg" + ($0.w.map { " (vita \(fmtNum($0)) cm)" } ?? "") }.joined(separator: " · ")
        let ritmo = ritmoTesto() ?? ""
        let testoPeso = "Partenza 64,70 kg (28 set), obiettivo 62,5 kg (ritmo atteso ~0,35 kg/settimana; regola: tra 0,15 e 0,45 avanti così). Pesate: \(ws). \(ritmo)"
        return SnapshotCoach(istruzioni: istruzioni, istruzioniCortissime: cortissime, cibi: cibi,
                             schede: schede, allenamenti: ultimi, record: rec, peso: testoPeso)
    }
}

// MARK: lettura sicura di GeneratedContent e strumenti per Apple Intelligence

@available(iOS 26.0, *)
private extension GeneratedContent {
    func stringa(_ chiave: String) -> String? {
        guard case .structure(let p, _) = kind, let v = p[chiave], case .string(let s) = v.kind else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    func numero(_ chiave: String) -> Double? {
        guard case .structure(let p, _) = kind, let v = p[chiave] else { return nil }
        switch v.kind {
        case .number(let n): return n
        case .string(let s): return Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
    func intero(_ chiave: String) -> Int? { numero(chiave).map { Int($0.rounded()) } }
}

@available(iOS 26.0, *)
private struct ArgCerca: Generable {
    var voce: String
    static var generationSchema: GenerationSchema {
        GenerationSchema(type: Self.self, description: "Ricerca", properties: [
            .init(name: "voce", description: "Parola da cercare (oppure vuoto per l'elenco completo)", type: String.self)
        ])
    }
    init(_ content: GeneratedContent) throws { voce = content.stringa("voce") ?? "" }
    var generatedContent: GeneratedContent { GeneratedContent(properties: ["voce": voce]) }
}

@available(iOS 26.0, *)
private struct StrumentoCibi: Tool {
    let name = "cercaCibi"
    let description = "Cerca nel database degli alimenti del piano (valori per 100 g e codice fid)."
    let snapshot: SnapshotCoach

    func call(arguments: ArgCerca) async throws -> String {
        let q = arguments.voce.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let trovati = q.isEmpty ? snapshot.cibi : snapshot.cibi.filter { $0.nome.contains(q) || $0.id.lowercased().contains(q) }
        let lista = (trovati.isEmpty ? snapshot.cibi : trovati).prefix(25).map(\.riga)
        return lista.joined(separator: "\n")
    }
}

@available(iOS 26.0, *)
private struct StrumentoPalestra: Tool {
    let name = "schedeAllenamenti"
    let description = "Legge le schede della palestra, gli ultimi allenamenti fatti e i record dei carichi."
    let snapshot: SnapshotCoach

    func call(arguments: ArgCerca) async throws -> String {
        var parti = ["SCHEDE:\n" + snapshot.schede]
        if !snapshot.allenamenti.isEmpty { parti.append("ULTIMI ALLENAMENTI:\n" + snapshot.allenamenti) }
        if !snapshot.record.isEmpty { parti.append("RECORD:\n" + snapshot.record) }
        return parti.joined(separator: "\n\n")
    }
}

@available(iOS 26.0, *)
private struct StrumentoPeso: Tool {
    let name = "storicoPeso"
    let description = "Legge lo storico delle pesate, la misura della vita e il ritmo settimanale del peso."
    let snapshot: SnapshotCoach

    func call(arguments: ArgCerca) async throws -> String { snapshot.peso }
}

// raccoglie in modo thread-safe le azioni generate dallo strumento durante la risposta
final class RaccoglitoreAzioni: @unchecked Sendable {
    private let lock = NSLock()
    private var lista: [[String: Any]] = []

    func aggiungi(_ a: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        lista.append(a)
    }
    func bloccoAzioni() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard !lista.isEmpty, let dati = try? JSONSerialization.data(withJSONObject: lista),
              let json = String(data: dati, encoding: .utf8) else { return nil }
        return "```azioni\n\(json)\n```"
    }
}

@available(iOS 26.0, *)
private struct ArgAzione: Generable {
    var tipo: String
    var fascia: Int?
    var nome: String?
    var grammi: Int?
    var kcal: Int?
    var proteine: Int?
    var carboidrati: Int?
    var grassi: Int?
    var kg: Double?
    var vita: Double?
    var codice: String?

    static var generationSchema: GenerationSchema {
        GenerationSchema(type: Self.self, description: "Azione da proporre nell'app", properties: [
            .init(name: "tipo", description: "Tipo di azione: mangiato, fuori, creatina, peso, scambio", type: String.self,
                  guides: [.anyOf(["mangiato", "fuori", "creatina", "peso", "scambio"])]),
            .init(name: "fascia", description: "Indice della fascia del pasto di oggi (0..4), se applicabile", type: Int?.self),
            .init(name: "nome", description: "Nome del piatto o cibo fuori piano", type: String?.self),
            .init(name: "grammi", description: "Grammi stimati della porzione fuori piano", type: Int?.self),
            .init(name: "kcal", description: "Calorie (kcal) della porzione intera fuori piano", type: Int?.self),
            .init(name: "proteine", description: "Proteine in grammi della porzione fuori piano", type: Int?.self),
            .init(name: "carboidrati", description: "Carboidrati in grammi della porzione fuori piano", type: Int?.self),
            .init(name: "grassi", description: "Grassi in grammi della porzione fuori piano", type: Int?.self),
            .init(name: "kg", description: "Peso corporeo in kg (es. 63.8)", type: Double?.self),
            .init(name: "vita", description: "Giro vita in cm, se indicato", type: Double?.self),
            .init(name: "codice", description: "Codice della ricetta alternativa per lo scambio", type: String?.self)
        ])
    }

    init(_ content: GeneratedContent) throws {
        tipo = content.stringa("tipo") ?? ""
        fascia = content.intero("fascia")
        nome = content.stringa("nome")
        grammi = content.intero("grammi")
        kcal = content.intero("kcal")
        proteine = content.intero("proteine")
        carboidrati = content.intero("carboidrati")
        grassi = content.intero("grassi")
        kg = content.numero("kg")
        vita = content.numero("vita")
        codice = content.stringa("codice")
    }

    var generatedContent: GeneratedContent {
        GeneratedContent(properties: ["tipo": tipo])
    }
}

@available(iOS 26.0, *)
private struct StrumentoAzione: Tool {
    let name = "proponiAzione"
    let description = "Prepara una scheda di conferma per segnare un pasto del piano (mangiato), un pasto fuori piano (fuori), la creatina (creatina), la pesata (peso) o cambiare piatto di oggi (scambio)."
    let raccoglitore: RaccoglitoreAzioni

    func call(arguments: ArgAzione) async throws -> String {
        switch arguments.tipo.lowercased() {
        case "mangiato":
            if let f = arguments.fascia { raccoglitore.aggiungi(["tipo": "mangiato", "fascia": f]) }
        case "creatina":
            raccoglitore.aggiungi(["tipo": "creatina"])
        case "peso":
            if let kg = arguments.kg {
                var d: [String: Any] = ["tipo": "peso", "kg": kg]
                if let v = arguments.vita { d["vita"] = v }
                raccoglitore.aggiungi(d)
            }
        case "scambio":
            if let f = arguments.fascia, let c = arguments.codice {
                raccoglitore.aggiungi(["tipo": "scambio", "fascia": f, "codice": c])
            }
        case "fuori":
            // senza kcal stimate dal modello non si prepara niente: numeri di ripiego inventati finirebbero nei totali
            guard let k = arguments.kcal, k > 0 else {
                return "Mancano le kcal: stima grammi, kcal, proteine, carboidrati e grassi della porzione e richiama proponiAzione."
            }
            let nome = arguments.nome ?? "Pasto fuori piano"
            let voce: [String: Any] = [
                "nome": nome, "g": max(1, arguments.grammi ?? 100), "kcal": k,
                "p": max(0, arguments.proteine ?? 0),
                "c": max(0, arguments.carboidrati ?? 0),
                "f": max(0, arguments.grassi ?? 0)
            ]
            var d: [String: Any] = ["tipo": "fuori", "nome": nome, "voci": [voce]]
            if let f = arguments.fascia { d["fascia"] = f }
            raccoglitore.aggiungi(d)
        default: break
        }
        return "Scheda pronta: l'utente vedrà il pulsante Conferma sotto la tua risposta."
    }
}

// raccoglie le note che il modello locale decide di salvare nella memoria permanente del coach
final class RaccoglitoreMemorie: @unchecked Sendable {
    private let lock = NSLock()
    private var note: [String] = []

    func aggiungi(_ t: String) {
        let p = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        if !note.contains(p) { note.append(p) }
    }
    func tutte() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return note
    }
}

@available(iOS 26.0, *)
private struct ArgMemoria: Generable {
    var nota: String
    static var generationSchema: GenerationSchema {
        GenerationSchema(type: Self.self, description: "Nota da ricordare", properties: [
            .init(name: "nota", description: "Frase breve da salvare nella memoria permanente del coach (es. macchinario, orario, preferenza)", type: String.self)
        ])
    }
    init(_ content: GeneratedContent) throws { nota = content.stringa("nota") ?? "" }
    var generatedContent: GeneratedContent { GeneratedContent(properties: ["nota": nota]) }
}

@available(iOS 26.0, *)
private struct StrumentoMemoria: Tool {
    let name = "ricordaSempre"
    let description = "Salva un'informazione importante (preferenze, macchinari della palestra, orari, abitudini) nella memoria permanente del coach, così resta anche nelle prossime chat."
    let memorie: RaccoglitoreMemorie

    func call(arguments: ArgMemoria) async throws -> String {
        memorie.aggiungi(arguments.nota)
        return "Nota salvata nella memoria permanente del coach."
    }
}
