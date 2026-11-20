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
        let leggi: Set<HKObjectType> = [massa, HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKCategoryType(.sleepAnalysis)]
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

    // MARK: sonno e passi della settimana (riepilogo della domenica)

    struct Settimana: Equatable {
        var sonno: TimeInterval?      // sonno medio a notte (secondi)
        var notti = 0                 // notti registrate
        var passi: Int?               // passi medi al giorno
        var sonnoPrima: TimeInterval?
        var passiPrima: Int?
    }

    // la settimana da «lunedi» (e quella prima, per il confronto). Il sonno lo registra l'orologio (o l'iPhone): conta solo
    // il tempo addormentato, unendo i pezzi che si sovrappongono (orologio e iPhone insieme non contano doppio)
    func settimana(da lunedi: Date) async -> Settimana? {
        guard attiva else { return nil }
        // chiede il permesso per il sonno a chi aveva già collegato Salute (se l'ha già dato, non compare niente)
        let leggi: Set<HKObjectType> = [massa, HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKCategoryType(.sleepAnalysis)]
        _ = try? await store.requestAuthorization(toShare: [], read: leggi)
        let fine = Cal.giorni(7, da: lunedi), prima = Cal.giorni(-7, da: lunedi)
        async let s1 = sonnoMedio(lunedi, fine)
        async let s0 = sonnoMedio(prima, lunedi)
        async let p1 = passiMedi(lunedi, fine)
        async let p0 = passiMedi(prima, lunedi)
        let (a, b, c, d) = await (s1, s0, p1, p0)
        return Settimana(sonno: a.0, notti: a.1, passi: c, sonnoPrima: b.0, passiPrima: d)
    }

    private func sonnoMedio(_ da: Date, _ a: Date) async -> (TimeInterval?, Int) {
        let vere = await sonnoNotti(da, a).values
        return (vere.isEmpty ? nil : vere.reduce(0, +) / Double(vere.count), vere.count)
    }

    // il sonno di ogni notte (chiave = giorno del risveglio), solo le notti con almeno un'ora
    private func sonnoNotti(_ da: Date, _ a: Date) async -> [String: TimeInterval] {
        let filtro = HKQuery.predicateForSamples(withStart: da.addingTimeInterval(-14 * 3600), end: a)
        let campioni: [HKCategorySample] = await withCheckedContinuation { c in
            let q = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: filtro, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, r, _ in
                c.resume(returning: (r as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        // solo il sonno vero (non «a letto» né «sveglio»), con il risveglio dentro la settimana
        let dormito = campioni.filter {
            $0.value != HKCategoryValueSleepAnalysis.inBed.rawValue && $0.value != HKCategoryValueSleepAnalysis.awake.rawValue
                && $0.endDate >= da && $0.endDate < a
        }
        // pezzi uniti (si sovrappongono quando registrano orologio e iPhone), poi sommati per notte (giorno del risveglio)
        var uniti: [(Date, Date)] = []
        for x in dormito.sorted(by: { $0.startDate < $1.startDate }) {
            if let u = uniti.last, x.startDate <= u.1 { uniti[uniti.count - 1].1 = max(u.1, x.endDate) } else { uniti.append((x.startDate, x.endDate)) }
        }
        var notti: [String: TimeInterval] = [:]
        for (i, f) in uniti { notti[Cal.key(f), default: 0] += f.timeIntervalSince(i) }
        return notti.filter { $0.value >= 3600 }   // meno di un'ora: un pisolino o un dato a metà
    }

    private func passiMedi(_ da: Date, _ a: Date) async -> Int? {
        let giorni = await passiGiorni(da, a).values
        return giorni.isEmpty ? nil : Int((giorni.reduce(0, +) / Double(giorni.count)).rounded())
    }

    // i passi di ogni giorno (chiave = giorno), solo i giorni con qualche passo
    private func passiGiorni(_ da: Date, _ a: Date) async -> [String: Double] {
        let fino = min(a, Date())
        guard fino > da else { return [:] }
        let filtro = HKQuery.predicateForSamples(withStart: da, end: fino)
        return await withCheckedContinuation { c in
            let q = HKStatisticsCollectionQuery(quantityType: HKQuantityType(.stepCount), quantitySamplePredicate: filtro,
                                                options: .cumulativeSum, anchorDate: da, intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, r, _ in
                var v: [String: Double] = [:]
                r?.enumerateStatistics(from: da, to: fino) { st, _ in
                    if let n = st.sumQuantity()?.doubleValue(for: .count()), n > 0 { v[Cal.key(st.startDate)] = n }
                }
                c.resume(returning: v)
            }
            store.execute(q)
        }
    }

    // MARK: sonno e passi di questi giorni, per il coach (si tengono da parte: la riga [Adesso…] si scrive al volo)

    struct Recenti: Equatable {
        var stanotte: TimeInterval?   // il sonno della notte appena passata
        var sonnoMedio: TimeInterval? // media delle ultime 7 notti
        var passiOggi: Int?
        var passiIeri: Int?
        var passiMedi: Int?           // media degli ultimi 7 giorni (oggi escluso: è ancora a metà)
    }
    private(set) var recenti: Recenti?

    func aggiornaRecenti() async {
        guard attiva else { recenti = nil; return }
        let leggi: Set<HKObjectType> = [massa, HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKCategoryType(.sleepAnalysis)]
        _ = try? await store.requestAuthorization(toShare: [], read: leggi)
        let oggi = Cal.greg.startOfDay(for: Date())
        let domani = Cal.giorni(1, da: oggi)
        async let notti = sonnoNotti(Cal.giorni(-6, da: oggi), domani)    // 7 notti, stanotte compresa
        async let passi = passiGiorni(Cal.giorni(-7, da: oggi), domani)   // 7 giorni prima di oggi, più oggi
        let (n, p) = await (notti, passi)
        let primaDiOggi = p.filter { $0.key != Cal.key(oggi) }.values
        recenti = Recenti(stanotte: n[Cal.key(oggi)], sonnoMedio: n.isEmpty ? nil : n.values.reduce(0, +) / Double(n.count),
                          passiOggi: p[Cal.key(oggi)].map { Int($0) }, passiIeri: p[Cal.key(Cal.giorni(-1, da: oggi))].map { Int($0) },
                          passiMedi: primaDiOggi.isEmpty ? nil : Int(primaDiOggi.reduce(0, +) / Double(primaDiOggi.count)))
    }

    // in parole, per il coach: «Sonno: stanotte 6 h 40′ (media 7 notti 7 h 05′). Passi: oggi 4.210, ieri 9.800, media 8.100.»
    var recentiTesto: String? {
        guard let r = recenti else { return nil }
        func ore(_ t: TimeInterval) -> String { let m = Int(t / 60); return "\(m / 60) h \(String(format: "%02d", m % 60))′" }
        var parti: [String] = []
        if r.stanotte != nil || r.sonnoMedio != nil {
            parti.append("Sonno: " + [r.stanotte.map { "stanotte \(ore($0))" } ?? "stanotte non registrato",
                                      r.sonnoMedio.map { "media 7 notti \(ore($0))" }].compactMap { $0 }.joined(separator: ", "))
        }
        let passi = [r.passiOggi.map { "oggi \(fmtMigliaia(Double($0)))" }, r.passiIeri.map { "ieri \(fmtMigliaia(Double($0)))" },
                     r.passiMedi.map { "media 7 giorni \(fmtMigliaia(Double($0)))" }].compactMap { $0 }
        if !passi.isEmpty { parti.append("Passi: " + passi.joined(separator: ", ")) }
        return parti.isEmpty ? nil : parti.joined(separator: ". ")
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
