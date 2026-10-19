import ActivityKit
import Foundation

// Indirizzo con cui l'estensione (Live Activity, widget) riapre l'app: l'app con il sito dentro risponde a «recomp://»,
// l'app SwiftUI («Recomp 2», identificativo …recomp.nuova) a «recomp2://».
enum IndirizzoApp {
    static var schema: String { (Bundle.main.bundleIdentifier ?? "").contains(".recomp.nuova") ? "recomp2" : "recomp" }
    static func url(_ percorso: String) -> URL? { URL(string: "\(schema)://\(percorso)") }
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
        var done: Int? = nil   // serie fatte
        var total: Int? = nil  // serie dell'allenamento
    }

    var workout: String        // nome dell'allenamento, per esempio "Torso B"
}
