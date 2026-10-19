import Foundation
import SwiftUI

// Stato di oggi mandato dall'app iPhone (app.js → WatchBridge). Lo usano l'app Watch e la complicazione sul quadrante,
// che lo leggono dal gruppo condiviso: l'app lo salva a ogni aggiornamento.
// un ingrediente da pesare: nome, quantità (g o ml) e l'aiuto in pezzi («2 fette», «1 vasetto da 150 g»)
struct WatchIng: Codable, Hashable {
    var n: String
    var g: Int
    var u: String
    var h: String?
}

// un piatto con cui si può scambiare il pasto
struct WatchAlt: Codable, Hashable, Identifiable {
    var code: String
    var name: String
    var k: Int
    var p: Int
    var c: Int
    var f: Int
    var cur: Bool?
    var id: String { code }
}

struct WatchMeal: Codable, Identifiable, Hashable {
    var si: Int
    var time: String
    var label: String
    var name: String
    var code: String?
    var k: Int
    var p: Int
    var c: Int?
    var f: Int?
    var eaten: Bool
    var ing: [WatchIng]?   // nil = ancora da aggiornare dall'iPhone (dopo uno scambio)
    var alt: [WatchAlt]?
    var fuori: Bool? = nil   // al posto del pasto del piano hai mangiato altro (segnato sul telefono): niente «Mangiato» né cambio
    var id: Int { si }
}

struct WatchWorkout: Codable, Hashable {
    var name: String
    var ex: String?
    var i: Int?
    var j: Int?
    var set: Int?
    var of: Int?
    var target: String?
    var kg: Double?
    var r: Int?
    var unit: String?
    var inc: Double?
    var left: Int?
    var done: Bool?
}

// una scheda (Torso A, Limbs B…) con kg e ripetizioni suggeriti per ogni serie, come nella Scheda dell'app
struct PlanSet: Codable, Hashable {
    var kg: Double?
    var r: Int
}

struct PlanItem: Codable, Hashable {
    var ex: String
    var n: String
    var unit: String   // "reps" oppure "sec"
    var inc: Double    // passo del carico (2,5 kg sulle macchine, 5 sulla Leg Press…)
    var lo: Int
    var hi: Int
    var rest: Int      // secondi di recupero (0 = superserie: si passa subito all'esercizio abbinato)
    var sup: String?
    var sets: [PlanSet]
}

struct WatchPlan: Codable, Identifiable, Hashable {
    var rid: String
    var name: String
    var day: String
    var items: [PlanItem]
    var id: String { rid }
    var setCount: Int { items.reduce(0) { $0 + $1.sets.count } }
}

// l'allenamento attivo sull'iPhone, completo: l'orologio ne fa una sessione sua (come se fosse partito dal polso) e la tiene allineata
struct WatchActItem: Codable, Hashable {
    var ex: String
    var n: String?        // nome breve dell'esercizio
    var u: String?        // "reps" o "sec"
    var inc: Double?      // passo del carico
    var lo: Double?
    var hi: Double?
    var rest: Double?     // secondi di recupero (0 = superserie)
    var sup: String?
    var s: [[Double?]]    // per ogni serie: [kg, ripetizioni, 1 se fatta]
}

struct WatchAct: Codable, Hashable {
    var id: String
    var rid: String?
    var name: String?
    var st: Double?       // inizio dell'allenamento sul telefono (ms)
    var q: Int?           // quanti eventi dell'orologio il telefono ha già applicato
    var items: [WatchActItem]
    var re: Double?       // fine del recupero sull'iPhone (ms), 0 = nessuno
    var rv: Double?       // quando il recupero è cambiato per ultimo (ms)
    var rn: String?
}
struct WatchSnapshot: Codable, Hashable {
    var date: String
    var day: String
    var type: String
    var kcal: Int
    var kcalTarget: Int
    var p: Int
    var pTarget: Int
    var c: Int
    var cTarget: Int
    var f: Int
    var fTarget: Int
    var meals: [WatchMeal]
    var crea: Bool
    var wo: WatchWorkout?
    var restEnd: Double?   // fine del recupero in millisecondi, come in JavaScript
    var restNext: String?
    var plans: [WatchPlan]?
    var todayRid: String?
    var doneToday: Bool?
    var act: WatchAct?
    var fin: [String]?    // allenamenti già salvati sull'iPhone nelle ultime 24 ore
    var lb: [String]?     // esercizi con i pesi in libbre (la scelta kg/lb vale su iPhone e orologio)

    var todayPlan: WatchPlan? { plans?.first { $0.rid == todayRid } }

    // serie fatte e totali dell'allenamento attivo sul telefono
    var actSets: (done: Int, total: Int) {
        let sets = (act?.items ?? []).flatMap { $0.s }
        return (sets.filter { $0.count > 2 && $0[2] == 1 }.count, sets.count)
    }

    var left: Int { max(0, kcalTarget - kcal) }
    var progress: Double { kcalTarget > 0 ? min(1, Double(kcal) / Double(kcalTarget)) : 0 }
    var nextMeal: WatchMeal? { meals.first { !$0.eaten } }
    var isToday: Bool { date == WatchSnapshot.todayKey() }
    var rest: Date? {
        guard let ms = restEnd else { return nil }
        let end = Date(timeIntervalSince1970: ms / 1000)
        return end > Date() ? end : nil
    }

    static func todayKey() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// Timer degli esercizi a tempo (plank): 3″ per mettersi in posizione, poi il tempo della serie; nel side plank i due lati,
// con 5″ per girarsi. Lo usano l'app iPhone e l'app Watch: alla fine la serie si segna da sola con i secondi tenuti.
struct TimerTempo: Equatable {
    var id = UUID()
    var dove: [Int]        // [esercizio, serie]
    var ex: String
    var durata: Int        // secondi (per lato)
    var lati: Int          // 1, oppure 2 nel side plank
    var inizio: Date       // fine dei 3″ per mettersi in posizione
    static let pronti: TimeInterval = 3
    static let cambio: TimeInterval = 5

    static func lati(_ ex: String) -> Int { ex.contains("side") ? 2 : 1 }
    var fine: Date { inizio.addingTimeInterval(Double(durata * lati) + (lati > 1 ? TimerTempo.cambio : 0)) }
    // quando parte un lato (o finisce il primo): lì vibra
    var cambi: [Date] {
        lati > 1 ? [inizio, inizio.addingTimeInterval(Double(durata)), inizio.addingTimeInterval(Double(durata) + TimerTempo.cambio)] : [inizio]
    }
    // fase: 0 in posizione · 1 primo lato (o l'unico) · 2 girati · 3 secondo lato · 4 finito; resto = secondi della fase; fatto 0…1
    func stato(_ ora: Date) -> (fase: Int, resto: Double, fatto: Double) {
        let t = ora.timeIntervalSince(inizio), d = Double(durata)
        let fatto = max(0, min(1, t / fine.timeIntervalSince(inizio)))
        if t < 0 { return (0, -t, 0) }
        if t < d { return (1, d - t, fatto) }
        if lati > 1 {
            if t < d + TimerTempo.cambio { return (2, d + TimerTempo.cambio - t, fatto) }
            if t < 2 * d + TimerTempo.cambio { return (3, 2 * d + TimerTempo.cambio - t, fatto) }
        }
        return (4, 0, 1)
    }
    // fermato prima della fine: i secondi tenuti (nel side plank quelli del secondo lato, se c'eri arrivato)
    func tenuti(_ ora: Date) -> Int {
        let t = ora.timeIntervalSince(inizio), d = Double(durata)
        if t <= 0 { return 0 }
        if lati == 1 || t <= d { return min(durata, Int(t.rounded())) }
        let secondo = t - d - TimerTempo.cambio
        return secondo <= 0 ? durata : min(durata, Int(secondo.rounded()))
    }
}

enum WatchShared {
    // Con Xcode il gruppo è «group.io.github.splancxs.recomp». Con xtool (Apple ID gratuito) gli identificativi hanno il
    // prefisso «XTL-CODICE.» e xtool rinomina anche il gruppo in «group.XTL-CODICE.io.github.splancxs.recomp»:
    // lo ricavo dall'identificativo dell'app (lo stesso per app Watch e complicazione).
    static let group: String = {
        let id = Bundle.main.bundleIdentifier ?? ""
        // l'app SwiftUI («Recomp 2», identificativo …recomp.nuova) ha il suo gruppo, separato da quello dell'app con il sito dentro
        let coda = id.contains(".recomp.nuova") ? ".nuova" : ""
        if id.hasPrefix("XTL-"), let punto = id.firstIndex(of: ".") {
            return "group.\(id[..<punto]).io.github.splancxs.recomp\(coda)"
        }
        return "group.io.github.splancxs.recomp\(coda)"
    }()
    private static let key = "snapshot"
    private static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    static func load() -> WatchSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }
    static func save(_ snapshot: WatchSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: key) }
    }
}

// carattere sportivo dell'app: condensato e pesante (i titoli vanno anche in maiuscolo)
extension Font {
    static func sport(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).width(.compressed)
    }
}

// colori dell'app (gli stessi di Recomp sull'iPhone): argento per l'accento con il testo scuro sopra, verde per ciò che è fatto,
// rosso, giallo e blu per proteine, carboidrati e grassi
enum Palette {
    static let accento = Color(red: 0.851, green: 0.859, blue: 0.855)   // argento
    static let fatto = Color(red: 0.310, green: 0.769, blue: 0.498)      // verde: serie fatta, pasto mangiato, creatina presa
    static let ink = Color(red: 0.071, green: 0.071, blue: 0.078)        // testo scuro sopra l'argento
    static let p = Color(red: 0.867, green: 0.310, blue: 0.227)
    static let c = Color(red: 0.847, green: 0.573, blue: 0.122)
    static let f = Color(red: 0.184, green: 0.498, blue: 0.812)
}
