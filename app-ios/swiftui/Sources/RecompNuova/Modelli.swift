import Foundation

// I dati dell'utente (pesi, pasti mangiati, allenamenti…). Stessa forma dell'app web (chiavi rc.*) dove possibile,
// così «Importa backup» riprende tutto da un file esportato dal sito. I tempi sono in millisecondi, come in JavaScript.

struct WeightEntry: Codable, Hashable, Identifiable {
    var d: String          // AAAA-MM-GG
    var kg: Double
    var w: Double?         // vita in cm
    var t: Double?
    var id: String { d }
}

struct DayOv: Codable, Hashable {
    var skip: Bool?        // palestra saltata
    var rid: String?       // allenamento recuperato
    var type: String?      // «ON» o «OFF»: oggi si mangia come in un giorno dell'altro tipo
    var keep: [Int]?       // pasti già mangiati al momento del cambio
    var t: Double?
}

struct SetRec: Codable, Hashable {
    var kg: Double?
    var r: Int?
    var type: String = "n"     // n normale · w riscaldamento · d drop set · f a cedimento
    var done: Bool = false
    var rpe: Int?

    init(kg: Double? = nil, r: Int? = nil, type: String = "n", done: Bool = false, rpe: Int? = nil) {
        self.kg = kg; self.r = r; self.type = type; self.done = done; self.rpe = rpe
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        kg = try c.decodeIfPresent(Double.self, forKey: .kg)
        r = try c.decodeIfPresent(Int.self, forKey: .r)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "n"
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        rpe = try c.decodeIfPresent(Int.self, forKey: .rpe)
    }
    enum Keys: String, CodingKey { case kg, r, type, done, rpe }
    var isWork: Bool { type != "w" }
}

struct ItemRec: Codable, Hashable {
    var ex: String            // id dell'esercizio nella libreria
    var lo: Int
    var hi: Int
    var rest: Int
    var sup: String = ""
    var kg: Double?           // carico di partenza della scheda
    var note: String = ""
    var sets: [SetRec]

    init(ex: String, lo: Int, hi: Int, rest: Int, sup: String = "", kg: Double? = nil, note: String = "", sets: [SetRec]) {
        self.ex = ex; self.lo = lo; self.hi = hi; self.rest = rest; self.sup = sup; self.kg = kg; self.note = note; self.sets = sets
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        ex = try c.decode(String.self, forKey: .ex)
        lo = try c.decodeIfPresent(Int.self, forKey: .lo) ?? 8
        hi = try c.decodeIfPresent(Int.self, forKey: .hi) ?? 12
        rest = try c.decodeIfPresent(Int.self, forKey: .rest) ?? 90
        sup = try c.decodeIfPresent(String.self, forKey: .sup) ?? ""
        kg = try c.decodeIfPresent(Double.self, forKey: .kg)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        sets = try c.decodeIfPresent([SetRec].self, forKey: .sets) ?? []
    }
    enum Keys: String, CodingKey { case ex, lo, hi, rest, sup, kg, note, sets }
}

// l'allenamento in corso
struct ActiveWorkout: Codable, Hashable {
    var id: String
    var rid: String?
    var name: String
    var start: Double
    var items: [ItemRec]
    var fromWatch: Bool = false     // l'orologio avvisa lui: il telefono non manda la notifica di fine recupero
    var wq: Int = 0                 // quanti eventi dell'orologio ho già applicato (lo conferma all'orologio)
    var restStart: Double = 0
    var restEnd: Double = 0         // fine del recupero (ms), 0 = nessuno
    var restRv: Double = 0          // ultima modifica del recupero (ms): lo confronta l'orologio
    var restNext: String = ""
}

struct RecordPR: Codable, Hashable {
    var ex: String
    var k: String
    var v: String
}

// allenamento finito, in cronologia
struct Workout: Codable, Hashable, Identifiable {
    var id: String
    var rid: String?
    var name: String
    var start: Double
    var end: Double
    var items: [ItemRec]
    var prs: [RecordPR] = []
    var hr: Int?
    var kcal: Int?
    var watch: Bool?
    var del: Bool?
    var t: Double?

    init(id: String, rid: String?, name: String, start: Double, end: Double, items: [ItemRec], prs: [RecordPR] = [], hr: Int? = nil, kcal: Int? = nil, watch: Bool? = nil) {
        self.id = id; self.rid = rid; self.name = name; self.start = start; self.end = end; self.items = items
        self.prs = prs; self.hr = hr; self.kcal = kcal; self.watch = watch; self.t = Date().timeIntervalSince1970 * 1000
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        rid = try c.decodeIfPresent(String.self, forKey: .rid)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Allenamento"
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decodeIfPresent(Double.self, forKey: .end) ?? start
        items = try c.decodeIfPresent([ItemRec].self, forKey: .items) ?? []
        prs = try c.decodeIfPresent([RecordPR].self, forKey: .prs) ?? []
        hr = try c.decodeIfPresent(Int.self, forKey: .hr)
        kcal = try c.decodeIfPresent(Int.self, forKey: .kcal)
        watch = Workout.flag(c, .watch)
        del = Workout.flag(c, .del)
        t = try c.decodeIfPresent(Double.self, forKey: .t)
    }
    enum Keys: String, CodingKey { case id, rid, name, start, end, items, prs, hr, kcal, watch, del, t }
    // nell'app web i flag sono 1 oppure assenti; qui sono Bool: li leggo in tutti e due i modi
    private static func flag(_ c: KeyedDecodingContainer<Keys>, _ k: Keys) -> Bool? {
        if let b = try? c.decodeIfPresent(Bool.self, forKey: k) { return b }
        if let n = try? c.decodeIfPresent(Int.self, forKey: k) { return n != 0 }
        return nil
    }

    var minutes: Int { max(1, Int((end - start) / 60000)) }
    var volume: Double { items.reduce(0) { $0 + volOf($1.sets) } }
    var workSets: Int { items.reduce(0) { $0 + $1.sets.filter(\.isWork).count } }
}

func volOf(_ sets: [SetRec]) -> Double {
    sets.filter(\.isWork).reduce(0) { $0 + (($1.kg ?? 0) > 0 && ($1.r ?? 0) > 0 ? ($1.kg ?? 0) * Double($1.r ?? 0) : 0) }
}
func e1rm(_ kg: Double, _ r: Int) -> Double { kg > 0 && r > 0 ? kg * (1 + Double(r) / 30) : 0 }   // formula di Epley

// una scheda (routine): quelle del piano, più eventuali modificate
struct RoutineItem: Codable, Hashable {
    var ex: String
    var s: Int
    var lo: Int
    var hi: Int
    var rest: Int
    var sup: String
    var kg: Double?
}
struct Routine: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var day: String
    var focus: String
    var items: [RoutineItem]
}

// un cibo mangiato fuori piano: valori per 100 g (dal piano, da Open Food Facts o scritti a mano)
struct VoceCibo: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var nome: String
    var g: Double
    var k100: Double
    var p100: Double
    var c100: Double
    var f100: Double
    var fonte: String?            // id del cibo del piano, codice a barre, oppure «mano»
    var k: Double { k100 * g / 100 }
    var p: Double { p100 * g / 100 }
    var c: Double { c100 * g / 100 }
    var f: Double { f100 * g / 100 }
}

// un pasto fuori piano: al posto di una fascia (si) o in più (si = nil)
struct PastoFuori: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var si: Int?
    var nome: String
    var voci: [VoceCibo]
    var t: Double
    var tot: Tot { Tot(k: voci.reduce(0) { $0 + $1.k }, p: voci.reduce(0) { $0 + $1.p }, c: voci.reduce(0) { $0 + $1.c }, fa: voci.reduce(0) { $0 + $1.f }) }
}

// un messaggio della chat con il coach; per le risposte si tiene anche il contenuto esatto restituito da Claude
// (va rimandato così com'è nelle domande successive)
struct MessaggioCoach: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var ruolo: String             // «user» o «assistant»
    var testo: String
    var contenuto: Data?          // JSON del campo «content» della risposta
    var t: Double
    var fatte: [Int]?             // azioni proposte in questa risposta e confermate (indici)
    var scartate: [Int]?          // azioni a cui hai detto «No»
}

// tutto quello che si salva sul telefono
struct AppData: Codable {
    var weights: [WeightEntry] = []
    var eaten: [String: [Int]] = [:]          // data → pasti mangiati (indice della fascia)
    var swaps: [String: String] = [:]         // «giorno:fascia» → piatto scelto
    var creatina: [String: Bool] = [:]
    var dayov: [String: DayOv] = [:]
    var workouts: [Workout] = []
    var active: ActiveWorkout?
    var lbEx: [String] = []                   // esercizi con i pesi in libbre
    var shopGot: [String: Bool] = [:]         // lista della spesa: cosa è già nel carrello
    var blockStart: String = "2026-09-28"
    var superserie: Bool = true               // vecchio interruttore unico: ora ogni superserie si spegne da sola (supSpente)
    var supSpente: [String] = []              // superserie fatte separate: «scheda:numero» (per esempio «LA:4»)
    var notifRest: Bool = true
    var salute: Bool = false                  // collegata a Salute (peso, pasti)
    var promemoria: [String: Bool] = [:]      // merenda · peso · palestra · creatina
    var creaOra: String = "20:30"
    var migrato: Bool = false                 // i dati dell'app vecchia sono già stati ripresi
    var fuori: [String: [PastoFuori]] = [:]   // data → pasti fuori piano
    var schede: [Routine]?                    // schede modificate dall'utente (nil = quelle del piano)
    var coach: [MessaggioCoach] = []          // la chat in corso con il coach
    var coachSistema: String = ""             // i dati dati al coach all'inizio della chat (restano fissi per tutta la chat)
    var pianoVersione: String = ""            // versione di piano.json con cui valgono scambi e lista della spesa

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        weights = try c.decodeIfPresent([WeightEntry].self, forKey: .weights) ?? []
        eaten = try c.decodeIfPresent([String: [Int]].self, forKey: .eaten) ?? [:]
        swaps = try c.decodeIfPresent([String: String].self, forKey: .swaps) ?? [:]
        creatina = try c.decodeIfPresent([String: Bool].self, forKey: .creatina) ?? [:]
        dayov = try c.decodeIfPresent([String: DayOv].self, forKey: .dayov) ?? [:]
        workouts = try c.decodeIfPresent([Workout].self, forKey: .workouts) ?? []
        active = try c.decodeIfPresent(ActiveWorkout.self, forKey: .active)
        lbEx = try c.decodeIfPresent([String].self, forKey: .lbEx) ?? []
        shopGot = try c.decodeIfPresent([String: Bool].self, forKey: .shopGot) ?? [:]
        blockStart = try c.decodeIfPresent(String.self, forKey: .blockStart) ?? "2026-09-28"
        superserie = try c.decodeIfPresent(Bool.self, forKey: .superserie) ?? true
        supSpente = try c.decodeIfPresent([String].self, forKey: .supSpente) ?? []
        notifRest = try c.decodeIfPresent(Bool.self, forKey: .notifRest) ?? true
        salute = try c.decodeIfPresent(Bool.self, forKey: .salute) ?? false
        promemoria = try c.decodeIfPresent([String: Bool].self, forKey: .promemoria) ?? [:]
        creaOra = try c.decodeIfPresent(String.self, forKey: .creaOra) ?? "20:30"
        migrato = try c.decodeIfPresent(Bool.self, forKey: .migrato) ?? false
        fuori = try c.decodeIfPresent([String: [PastoFuori]].self, forKey: .fuori) ?? [:]
        schede = try c.decodeIfPresent([Routine].self, forKey: .schede)
        coach = try c.decodeIfPresent([MessaggioCoach].self, forKey: .coach) ?? []
        coachSistema = try c.decodeIfPresent(String.self, forKey: .coachSistema) ?? ""
        pianoVersione = try c.decodeIfPresent(String.self, forKey: .pianoVersione) ?? ""
    }
    enum Keys: String, CodingKey { case weights, eaten, swaps, creatina, dayov, workouts, active, lbEx, shopGot, blockStart, superserie, supSpente, notifRest, salute, promemoria, creaOra, migrato, fuori, schede, coach, coachSistema, pianoVersione }
}

// MARK: date e unità

enum Cal {
    static let greg: Calendar = { var c = Calendar(identifier: .gregorian); c.locale = Locale(identifier: "it_IT"); return c }()
    static let fmt: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static let fmtOra: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"; return f
    }()
    static func key(_ d: Date = Date()) -> String { fmt.string(from: d) }
    static func date(_ key: String) -> Date { fmt.date(from: key) ?? Date() }
    // 0 = lunedì … 6 = domenica
    static func dayIdx(_ d: Date = Date()) -> Int { (greg.component(.weekday, from: d) + 5) % 7 }
    static func ms(_ d: Date = Date()) -> Double { d.timeIntervalSince1970 * 1000 }
    // il lunedì (a mezzanotte) della settimana di d, oppure di «indietro» settimane prima. Con il calendario, non togliendo
    // secondi: nella notte del cambio dell'ora 6 × 24 h non fanno 6 giorni (la domenica sera la settimana partiva da martedì)
    static func lunedi(_ d: Date = Date(), indietro: Int = 0) -> Date {
        let giorno = greg.startOfDay(for: d)
        return greg.date(byAdding: .day, value: -(dayIdx(d) + indietro * 7), to: giorno) ?? giorno
    }
    // n giorni dopo (o prima, se negativo), sempre con il calendario
    static func giorni(_ n: Int, da d: Date) -> Date { greg.date(byAdding: .day, value: n, to: d) ?? d.addingTimeInterval(Double(n) * 86400) }
}

// pesi: dentro l'app sempre kg; per gli esercizi in libbre cambia solo ciò che si vede e si digita (100 lb = 45,36 kg)
let kgPerLb = 0.45359237
func lbFrom(kg: Double) -> Double { (kg / kgPerLb * 2).rounded() / 2 }   // al mezzo libbra: mai «99,9»
func kgFrom(lb: Double) -> Double { (lb * kgPerLb * 100).rounded() / 100 }
func lbStep(_ incKg: Double) -> Double { max(2.5, (incKg * 2.20462 / 2.5).rounded() * 2.5) }   // 2,5 kg → 5 lb, 5 kg → 10 lb

func fmtNum(_ x: Double, _ decimals: Int = 1) -> String {
    if x.truncatingRemainder(dividingBy: 1) == 0 { return String(Int(x)) }
    return String(format: "%.\(decimals)f", x).replacingOccurrences(of: ".", with: ",")
}
func fmtKg(_ kg: Double) -> String { fmtNum(kg, 1) }
// il peso corporeo sempre con due decimali, come sulla bilancia: 64 → «64,00», 64,3 → «64,30»
func fmtPeso(_ kg: Double) -> String { String(format: "%.2f", kg).replacingOccurrences(of: ".", with: ",") }

// 9815 → «9.815» (all'italiana, anche per i numeri a quattro cifre)
func fmtMigliaia(_ x: Double) -> String {
    let n = Int(x.rounded())
    let cifre = String(abs(n))
    var out = ""
    for (i, c) in cifre.reversed().enumerated() { if i > 0 && i % 3 == 0 { out.append(".") }; out.append(c) }
    return (n < 0 ? "-" : "") + String(out.reversed())
}
// «sab 17 ott» → «Sab 17 ott»: solo la prima lettera maiuscola (non ogni parola)
func maiuscolaIniziale(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

extension Cal {
    private static var formattatori: [String: DateFormatter] = [:]
    // data in italiano con il formato indicato (per esempio «EEE d MMM», «EEEE d MMMM · HH:mm»)
    static func testo(_ d: Date, _ formato: String) -> String {
        let f = formattatori[formato] ?? { let x = DateFormatter(); x.locale = Locale(identifier: "it_IT"); x.dateFormat = formato; formattatori[formato] = x; return x }()
        return f.string(from: d)
    }
}
