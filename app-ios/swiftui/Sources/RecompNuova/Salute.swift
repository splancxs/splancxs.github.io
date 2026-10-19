import Foundation
import HealthKit

// Salute: il peso nei due sensi, i pasti segnati (calorie e macro in Nutrizione), passi e calorie attive.
// Gli allenamenti fatti con l'orologio vanno in Salute da soli (li scrive l'app Watch).
@MainActor
final class Salute {
    static let shared = Salute()
    private let store = HKHealthStore()
    private let massa = HKQuantityType(.bodyMass)
    private let chilo = HKUnit.gramUnit(with: .kilo)
    // chiave, tipo di Salute, unità
    private let nutrienti: [(String, HKQuantityTypeIdentifier, HKUnit)] = [
        ("k", .dietaryEnergyConsumed, .kilocalorie()), ("p", .dietaryProtein, .gram()),
        ("c", .dietaryCarbohydrates, .gram()), ("f", .dietaryFatTotal, .gram()),
    ]

    var disponibile: Bool { HKHealthStore.isHealthDataAvailable() }
    private var attiva: Bool { disponibile && AppStore.shared.d.salute }

    func autorizza(_ fatto: @escaping (Bool) -> Void) {
        guard disponibile else { fatto(false); return }
        let scrivi = Set<HKSampleType>([massa] + nutrienti.map { HKQuantityType($0.1) })
        let leggi: Set<HKObjectType> = [massa, HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned)]
        store.requestAuthorization(toShare: scrivi, read: leggi) { ok, _ in DispatchQueue.main.async { fatto(ok) } }
    }

    private var versione: Int { Int(Date().timeIntervalSince1970) }   // un nuovo salvataggio con lo stesso codice sostituisce il vecchio

    // una pesata al giorno: ripesarsi lo stesso giorno sostituisce quella in Salute
    func salvaPeso(giorno: String, kg: Double, t: Double) {
        guard attiva else { return }
        let quando = Date(timeIntervalSince1970: t / 1000)
        let campione = HKQuantitySample(type: massa, quantity: HKQuantity(unit: chilo, doubleValue: kg), start: quando, end: quando,
                                        metadata: [HKMetadataKeySyncIdentifier: "recomp-peso-\(giorno)", HKMetadataKeySyncVersion: versione])
        store.save(campione) { _, _ in }
    }

    // pasto segnato come mangiato: calorie, proteine, carboidrati e grassi in Nutrizione, col nome del piatto
    func salvaPasto(id: String, t: Date, nome: String, k: Double, p: Double, c: Double, f: Double) {
        guard attiva else { return }
        let v = versione
        let valori = ["k": k, "p": p, "c": c, "f": f]
        let campioni: [HKSample] = nutrienti.compactMap { chiave, tipo, unita in
            guard let x = valori[chiave], x > 0 else { return nil }
            return HKQuantitySample(type: HKQuantityType(tipo), quantity: HKQuantity(unit: unita, doubleValue: x), start: t, end: t,
                                    metadata: [HKMetadataKeySyncIdentifier: "recomp-pasto-\(id)-\(chiave)", HKMetadataKeySyncVersion: v, HKMetadataKeyFoodType: nome])
        }
        guard !campioni.isEmpty else { return }
        store.save(campioni) { _, _ in }
    }

    func eliminaPasto(id: String) {
        guard attiva else { return }
        for (chiave, tipo, _) in nutrienti {
            let filtro = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: ["recomp-pasto-\(id)-\(chiave)"])
            store.deleteObjects(of: HKQuantityType(tipo), predicate: filtro) { _, _, _ in }
        }
    }

    // pesate di Salute (bilancia smart, app Salute…) degli ultimi giorni che non hai già qui; quelle scritte da Recomp restano fuori
    func importaPesi(giorni: Int = 60) {
        guard attiva else { return }
        let da = Date().addingTimeInterval(-Double(giorni) * 86400)
        let filtro = HKQuery.predicateForSamples(withStart: da, end: nil)
        let ordine = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let mio = Bundle.main.bundleIdentifier
        let q = HKSampleQuery(sampleType: massa, predicate: filtro, limit: 500, sortDescriptors: [ordine]) { [chilo] _, campioni, _ in
            let voci = (campioni as? [HKQuantitySample] ?? []).filter { $0.sourceRevision.source.bundleIdentifier != mio }
                .map { (Cal.key($0.startDate), $0.quantity.doubleValue(for: chilo), $0.startDate.timeIntervalSince1970 * 1000) }
            DispatchQueue.main.async {
                let s = AppStore.shared
                for (giorno, kg, t) in voci where !s.d.weights.contains(where: { $0.d == giorno }) {
                    s.d.weights.append(WeightEntry(d: giorno, kg: (kg * 100).rounded() / 100, w: nil, t: t))
                }
            }
        }
        store.execute(q)
    }
}

extension AppStore {
    var salute_disponibile: Bool { Salute.shared.disponibile }
    func collegaSalute(_ si: Bool) {
        if !si { d.salute = false; return }
        Salute.shared.autorizza { [weak self] ok in
            guard let self else { return }
            self.d.salute = ok
            if ok { Salute.shared.importaPesi() }
        }
    }
    // il pasto segnato (o tolto) passa anche in Salute
    func pastoInSalute(si: Int, mangiato: Bool) {
        let id = "\(oggiKey)-\(si)"
        guard let m = pianoOggi.meals[safe: si], !m.free else { return }
        if mangiato {
            Salute.shared.salvaPasto(id: id, t: Date(), nome: piano.recipe(m.code).name, k: m.tot.k, p: m.tot.p, c: m.tot.c, f: m.tot.fa)
        } else {
            Salute.shared.eliminaPasto(id: id)
        }
    }
}
