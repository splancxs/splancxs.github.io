import ActivityKit
import AppIntents
import Foundation

// Indirizzo con cui l'estensione (Live Activity, widget) riapre l'app: «recomp://scheda», «recomp://oggi»…
enum IndirizzoApp {
    static func url(_ percorso: String) -> URL? { URL(string: "recomp://\(percorso)") }
}

// Dati della Live Activity del recupero, condivisi tra l'app (che la avvia) e l'estensione RecompLive (che la disegna).
@available(iOS 16.1, *)
struct RestAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var start: Date        // inizio del recupero (per la barra che si svuota)
        var end: Date          // fine del recupero: il conto alla rovescia lo calcola iOS da solo
        var exercise: String   // prossimo esercizio, per esempio "Panca inclinata 30° con manubri"
        var detail: String     // la serie, per esempio "Serie 2 · 12,5 kg × 10" (può essere vuoto)
        // la Live Activity resta per tutto l'allenamento: «go» = tra una serie e l'altra (niente recupero), nil = recupero
        // (così si può aggiornare anche con l'app in background, per esempio quando la serie arriva dall'orologio)
        var mode: String? = nil
        var done: Int? = nil       // serie fatte
        var total: Int? = nil      // serie dell'allenamento
        var restSec: Int? = nil    // recupero della serie corrente (quando tocchi «Serie fatta» dall'isola)
        var nextEx: String? = nil  // esercizio dopo questa serie
        var nextDet: String? = nil // dettaglio della serie successiva
    }

    var workout: String        // nome dell'allenamento, per esempio "Torso B"
}

// MARK: Pulsanti interattivi nella Dynamic Island e schermata di blocco (iOS 17+)
// Aggiornano all'istante la Live Activity e avvisano l'app principale tramite il gruppo condiviso e notifica Darwin.

struct EventoIsola: Codable {
    var id: String = UUID().uuidString
    var tipo: String   // "meno15", "piu15", "salta", "fatta"
    var t: Double
}

enum CodaIsola {
    static let notifica = "io.github.splancxs.recomp.isola"
    static let notificaOk = "io.github.splancxs.recomp.isola.ok"
    private static let chiave = "azioniIsola"
    private static let chiaveAck = "azioniIsolaAck"
    private static var defaults: UserDefaults { UserDefaults(suiteName: WatchShared.group) ?? .standard }
    nonisolated(unsafe) static var eseguiDiretto: (@Sendable (String) async -> Void)?

    static func accoda(_ tipo: String) {
        var lista = leggi()
        lista.append(EventoIsola(tipo: tipo, t: Date().timeIntervalSince1970 * 1000))
        if let d = try? JSONEncoder().encode(Array(lista.suffix(20))) {
            defaults.set(d, forKey: chiave)
        }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notifica as CFString),
            nil, nil, true
        )
    }

    static func segnaCompletato() {
        defaults.set(Date().timeIntervalSince1970, forKey: chiaveAck)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificaOk as CFString),
            nil, nil, true
        )
    }

    static func leggi() -> [EventoIsola] {
        guard let d = defaults.data(forKey: chiave),
              let l = try? JSONDecoder().decode([EventoIsola].self, from: d) else { return [] }
        return l
    }

    static func leggiESvuota() -> [EventoIsola] {
        let l = leggi()
        if !l.isEmpty { defaults.removeObject(forKey: chiave) }
        return l
    }

    @available(iOS 16.2, *)
    static func esegui(_ tipo: String) async {
        // Se l'intent gira già nel processo dell'app principale, aggiorna direttamente senza passaggi intermedi
        if let diretto = eseguiDiretto {
            await diretto(tipo)
            return
        }
        // Se gira nell'estensione, sveglia l'app principale (che fa un unico update) e attende fino a 80 ms
        let prima = defaults.double(forKey: chiaveAck)
        accoda(tipo)
        for _ in 0..<16 {
            try? await Task.sleep(nanoseconds: 5_000_000)
            if defaults.double(forKey: chiaveAck) > prima { return }
        }
        // Fallback se l'app principale era chiusa
        await aggiornaSubitoLive(tipo)
    }

    @available(iOS 16.2, *)
    static func aggiornaSubitoLive(_ tipo: String) async {
        guard let a = Activity<RestAttributes>.activities.first(where: { $0.activityState == .active }) else { return }
        var s = a.content.state
        let ora = Date()
        switch tipo {
        case "meno15":
            let nuova = s.end.addingTimeInterval(-15)
            if nuova <= ora.addingTimeInterval(0.5) {
                s.mode = "go"
                s.end = ora
                await a.update(ActivityContent(state: s, staleDate: nil))
            } else {
                s.end = nuova
                await a.update(ActivityContent(state: s, staleDate: nuova))
            }
        case "piu15":
            let base = max(ora, s.end)
            let nuova = base.addingTimeInterval(15)
            s.end = nuova
            s.mode = nil
            await a.update(ActivityContent(state: s, staleDate: nuova))
        case "salta":
            s.mode = "go"
            s.end = ora
            await a.update(ActivityContent(state: s, staleDate: nil))
        case "fatta":
            let tot = s.total ?? 0
            let fatte = min(tot > 0 ? tot : 999, (s.done ?? 0) + 1)
            s.done = fatte
            let rec = s.restSec ?? 90
            if let nx = s.nextEx, !nx.isEmpty {
                s.exercise = nx
                s.detail = s.nextDet ?? ""
                s.nextEx = nil
                s.nextDet = nil
            } else if tot > 0 && fatte >= tot {
                s.exercise = "Tutte le serie fatte"
                s.detail = "Termina l'allenamento e fai il cardio"
            }
            if rec > 0 && (tot == 0 || fatte < tot) {
                let fine = ora.addingTimeInterval(Double(rec))
                s.start = ora
                s.end = fine
                s.mode = nil
                await a.update(ActivityContent(state: s, staleDate: fine))
            } else {
                s.mode = "go"
                s.end = ora
                await a.update(ActivityContent(state: s, staleDate: nil))
            }
        default:
            break
        }
    }
}

@available(iOS 17.0, *)
struct Meno15RecuperoIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Meno 15 secondi"
    init() {}
    func perform() async throws -> some IntentResult {
        await CodaIsola.esegui("meno15")
        return .result()
    }
}

@available(iOS 17.0, *)
struct Piu15RecuperoIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Più 15 secondi"
    init() {}
    func perform() async throws -> some IntentResult {
        await CodaIsola.esegui("piu15")
        return .result()
    }
}

@available(iOS 17.0, *)
struct SaltaRecuperoIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Salta recupero"
    init() {}
    func perform() async throws -> some IntentResult {
        await CodaIsola.esegui("salta")
        return .result()
    }
}

@available(iOS 17.0, *)
struct SegnaSerieIsolaIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Segna serie fatta"
    init() {}
    func perform() async throws -> some IntentResult {
        await CodaIsola.esegui("fatta")
        return .result()
    }
}
