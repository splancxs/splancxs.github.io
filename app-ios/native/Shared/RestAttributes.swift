import ActivityKit
import Foundation

// Dati della Live Activity del recupero, condivisi tra l'app (che la avvia) e l'estensione RecompLive (che la disegna).
@available(iOS 16.1, *)
struct RestAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var end: Date      // quando finisce il recupero: il conto alla rovescia lo calcola iOS da solo
        var next: String   // prossima serie, per esempio "Prossima: Leg Press · serie 2 · 118 kg × 8"
    }

    var workout: String    // nome dell'allenamento, per esempio "Limbs A"
}
