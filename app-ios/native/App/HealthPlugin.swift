import Capacitor
import Foundation
import HealthKit

// Salute sull'iPhone: peso (letto e scritto), pasti segnati (calorie e macro in Nutrizione), passi e calorie attive.
// Funziona solo nelle installazioni da Xcode: prepara.sh (WATCH=1) aggiunge il permesso HealthKit e la voce RecompHealth
// in Info.plist. Con AltStore il permesso non c'è e available() risponde di no.
// JS: Health.available() · authorize() · weights({ since }) · saveWeight({ d, kg, t }) · saveMeal({ id, t, k, p, c, f, name })
//     · deleteMeal({ id }) · activity({ days }). Tempi in millisecondi, come in JavaScript.
@objc(HealthPlugin)
public class HealthPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "HealthPlugin"
    public let jsName = "Health"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "available", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "authorize", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "weights", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveWeight", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveMeal", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "deleteMeal", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "activity", returnType: CAPPluginReturnPromise),
    ]
    private let store = HKHealthStore()
    private let mass = HKQuantityType(.bodyMass)
    private let kilo = HKUnit.gramUnit(with: .kilo)
    // chiave usata da JavaScript, tipo di Salute, unità
    private let nutrients: [(String, HKQuantityTypeIdentifier, HKUnit)] = [
        ("k", .dietaryEnergyConsumed, .kilocalorie()), ("p", .dietaryProtein, .gram()),
        ("c", .dietaryCarbohydrates, .gram()), ("f", .dietaryFatTotal, .gram()),
    ]

    private var enabled: Bool {
        HKHealthStore.isHealthDataAvailable() && (Bundle.main.object(forInfoDictionaryKey: "RecompHealth") as? Bool ?? false)
    }
    private func date(_ ms: Double?) -> Date { ms.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date() }
    private var version: Int { Int(Date().timeIntervalSince1970) } // un nuovo salvataggio con lo stesso codice sostituisce il vecchio

    @objc func available(_ call: CAPPluginCall) { call.resolve(["ok": enabled]) }

    @objc func authorize(_ call: CAPPluginCall) {
        guard enabled else { call.resolve(["ok": false]); return }
        let write = Set<HKSampleType>([mass] + nutrients.map { HKQuantityType($0.1) })
        let read: Set<HKObjectType> = [mass, HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned)]
        store.requestAuthorization(toShare: write, read: read) { ok, error in
            call.resolve(["ok": ok, "error": error?.localizedDescription ?? ""])
        }
    }

    // pesate di Salute (bilancia smart, app Salute…) dal momento indicato; quelle scritte da Recomp restano fuori
    @objc func weights(_ call: CAPPluginCall) {
        guard enabled else { call.resolve(["items": []]); return }
        let predicate = HKQuery.predicateForSamples(withStart: date(call.getDouble("since")), end: nil)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let mine = Bundle.main.bundleIdentifier
        let query = HKSampleQuery(sampleType: mass, predicate: predicate, limit: 1000, sortDescriptors: [sort]) { _, samples, _ in
            let items: [[String: Any]] = (samples as? [HKQuantitySample] ?? [])
                .filter { $0.sourceRevision.source.bundleIdentifier != mine }
                .map { ["t": $0.startDate.timeIntervalSince1970 * 1000, "kg": $0.quantity.doubleValue(for: self.kilo), "src": $0.sourceRevision.source.name] }
            call.resolve(["items": items])
        }
        store.execute(query)
    }

    // una pesata al giorno: ripesarsi lo stesso giorno sostituisce quella in Salute
    @objc func saveWeight(_ call: CAPPluginCall) {
        guard enabled, let kg = call.getDouble("kg"), let day = call.getString("d") else { call.resolve(["ok": false]); return }
        let t = date(call.getDouble("t"))
        let sample = HKQuantitySample(type: mass, quantity: HKQuantity(unit: kilo, doubleValue: kg), start: t, end: t,
                                      metadata: [HKMetadataKeySyncIdentifier: "recomp-peso-\(day)", HKMetadataKeySyncVersion: version])
        store.save(sample) { ok, _ in call.resolve(["ok": ok]) }
    }

    // pasto segnato come mangiato: calorie, proteine, carboidrati e grassi in Nutrizione, col nome del piatto
    @objc func saveMeal(_ call: CAPPluginCall) {
        guard enabled, let id = call.getString("id") else { call.resolve(["ok": false]); return }
        let t = date(call.getDouble("t"))
        let name = call.getString("name") ?? "Pasto"
        let v = version
        let samples: [HKSample] = nutrients.compactMap { key, type, unit in
            guard let value = call.getDouble(key), value > 0 else { return nil }
            return HKQuantitySample(type: HKQuantityType(type), quantity: HKQuantity(unit: unit, doubleValue: value), start: t, end: t,
                                    metadata: [HKMetadataKeySyncIdentifier: "recomp-pasto-\(id)-\(key)", HKMetadataKeySyncVersion: v,
                                               HKMetadataKeyFoodType: name])
        }
        guard !samples.isEmpty else { call.resolve(["ok": false]); return }
        store.save(samples) { ok, _ in call.resolve(["ok": ok]) }
    }

    // pasto tolto dai mangiati: tolgo anche da Salute quello che avevo scritto
    @objc func deleteMeal(_ call: CAPPluginCall) {
        guard enabled, let id = call.getString("id") else { call.resolve(["ok": false]); return }
        let group = DispatchGroup()
        for (key, type, _) in nutrients {
            group.enter()
            let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: ["recomp-pasto-\(id)-\(key)"])
            store.deleteObjects(of: HKQuantityType(type), predicate: predicate) { _, _, _ in group.leave() }
        }
        group.notify(queue: .main) { call.resolve(["ok": true]) }
    }

    // passi e calorie attive per giorno, ultimi N giorni: [{ d: "AAAA-MM-GG", steps, kcal }]
    @objc func activity(_ call: CAPPluginCall) {
        guard enabled else { call.resolve(["days": []]); return }
        let days = max(1, min(60, call.getInt("days") ?? 14))
        let cal = Calendar.current
        let end = Date()
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: end)) else { call.resolve(["days": []]); return }
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        var steps: [String: Double] = [:]
        var kcal: [String: Double] = [:]
        let group = DispatchGroup()
        func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ done: @escaping ([String: Double]) -> Void) {
            group.enter()
            let query = HKStatisticsCollectionQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                                                    options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, results, _ in
                var out: [String: Double] = [:]
                results?.enumerateStatistics(from: start, to: end) { s, _ in
                    if let v = s.sumQuantity()?.doubleValue(for: unit) { out[fmt.string(from: s.startDate)] = v }
                }
                DispatchQueue.main.async { done(out); group.leave() }
            }
            store.execute(query)
        }
        sum(.stepCount, .count()) { steps = $0 }
        sum(.activeEnergyBurned, .kilocalorie()) { kcal = $0 }
        group.notify(queue: .main) {
            let list: [[String: Any]] = Set(steps.keys).union(kcal.keys).sorted().map { ["d": $0, "steps": steps[$0] ?? 0, "kcal": kcal[$0] ?? 0] }
            call.resolve(["days": list])
        }
    }
}
