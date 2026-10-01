import ActivityKit
import Foundation

// Dati della Live Activity del recupero, condivisi tra l'app (che la avvia) e l'estensione RecompLive (che la disegna).
@available(iOS 16.1, *)
struct RestAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var start: Date        // inizio del recupero (per la barra che si svuota)
        var end: Date          // fine del recupero: il conto alla rovescia lo calcola iOS da solo
        var exercise: String   // prossimo esercizio, per esempio "Panca inclinata 30° con manubri"
        var detail: String     // la serie, per esempio "Serie 2 · 12,5 kg × 10" (può essere vuoto)
    }

    var workout: String        // nome dell'allenamento, per esempio "Torso B"
}
