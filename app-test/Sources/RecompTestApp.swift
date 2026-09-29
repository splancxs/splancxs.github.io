// Recomp Test: mini app 100% nativa (SwiftUI, nessun sito dentro).
// Serve solo a verificare se, installata con AltStore e Apple ID gratuito, l'app ottiene il permesso HealthKit.
import HealthKit
import SwiftUI

@main
struct RecompTestApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var result = "Premi il pulsante qui sopra."
    @State private var ok = false
    private let store = HKHealthStore()

    var body: some View {
        VStack(spacing: 22) {
            Text("Recomp Test").font(.largeTitle.bold())
            Text("App 100% nativa in Swift, senza nessun sito dentro.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Chiedi accesso a Salute", action: ask)
                .buttonStyle(.borderedProminent).tint(.green).controlSize(.large)
            Text(result)
                .font(.body.monospaced()).multilineTextAlignment(.center)
                .foregroundStyle(ok ? .green : .primary).padding()
        }
        .padding(24)
    }

    private func ask() {
        guard HKHealthStore.isHealthDataAvailable() else {
            result = "Salute non disponibile su questo dispositivo."
            return
        }
        let weight = HKQuantityType(.bodyMass)
        store.requestAuthorization(toShare: [weight], read: [weight]) { granted, error in
            DispatchQueue.main.async {
                if let error {
                    ok = false
                    result = "ERRORE:\n\(error.localizedDescription)"
                } else {
                    ok = true
                    result = "OK: nessun errore, HealthKit funziona.\n(richiesta completata: \(granted))"
                    readLatestWeight()
                }
            }
        }
    }

    private func readLatestWeight() {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: HKQuantityType(.bodyMass), predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            guard let s = samples?.first as? HKQuantitySample else { return }
            let kg = s.quantity.doubleValue(for: .gramUnit(with: .kilo))
            DispatchQueue.main.async { result += String(format: "\nUltimo peso in Salute: %.1f kg", kg) }
        }
        store.execute(query)
    }
}
