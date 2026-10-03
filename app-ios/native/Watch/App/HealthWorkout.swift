import Foundation
import HealthKit

// Allenamento registrato in Salute come «Forza funzionale»: battito e calorie in tempo reale, poi salvato
// e conteggiato negli anelli Attività. Con l'Apple ID gratuito funziona installando da Xcode.
// Tiene anche l'app attiva col polso giù. Se Salute non è permessa, l'allenamento va avanti lo stesso senza.
final class HealthWorkout: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    @Published var heartRate: Int?
    @Published var kcal = 0

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let bpm = HKUnit.count().unitDivided(by: .minute())

    var running: Bool { session != nil }

    func start(_ completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { completion(session != nil); return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        store.requestAuthorization(toShare: share, read: read) { ok, _ in
            DispatchQueue.main.async { completion(ok && self.begin()) }
        }
    }

    private func begin() -> Bool {
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        guard let s = try? HKWorkoutSession(healthStore: store, configuration: config) else { return false }
        let b = s.associatedWorkoutBuilder()
        b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        s.delegate = self
        b.delegate = self
        session = s
        builder = b
        heartRate = nil
        kcal = 0
        let now = Date()
        s.startActivity(with: now)
        b.beginCollection(withStart: now) { _, _ in }
        return true
    }

    // fine: salvo l'allenamento in Salute e restituisco battito medio e calorie attive
    func finish(_ completion: @escaping (Int?, Int) -> Void) {
        guard let s = session, let b = builder else { completion(nil, 0); return }
        s.end()
        b.endCollection(withEnd: Date()) { _, _ in
            let avg = b.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: self.bpm)
            let energy = b.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            b.finishWorkout { _, _ in
                DispatchQueue.main.async {
                    self.session = nil
                    self.builder = nil
                    completion(avg.map { Int($0.rounded()) }, Int(energy.rounded()))
                }
            }
        }
    }

    // annullato: niente in Salute
    func discard() {
        guard let s = session, let b = builder else { return }
        s.end()
        b.discardWorkout()
        session = nil
        builder = nil
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hr = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: bpm)
        let energy = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        DispatchQueue.main.async {
            if let hr { self.heartRate = Int(hr.rounded()) }
            if let energy { self.kcal = Int(energy.rounded()) }
        }
    }
}
