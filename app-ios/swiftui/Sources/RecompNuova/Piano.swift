import Foundation

// Il piano alimentare e le schede: i dati stanno in piano.json (generato da tools/piano_swift.py a partire da genera_piano.py);
// qui i modelli e il calcolo dei pasti, gli stessi dell'app web (app.js: dayPlan, mealLines, sumLines).

struct Food: Codable, Hashable {
    let id: String
    let n: String
    let cat: String
    let k: Double
    let p: Double
    let c: Double
    let f: Double
    let u: Double?        // peso di una unità (una fetta, un uovo…)
    let note: String?
    let src: String?
}

struct Recipe: Codable, Hashable {
    let name: String
    let how: String
    let kind: String
}

struct IngredientRef: Codable, Hashable {
    let f: String
    let g: Double
}

struct SlotDef: Codable, Hashable {
    let time: String
    let label: String
    let slot: String
}

struct DayType: Codable, Hashable {
    let label: String
    let target: [Double]   // kcal, proteine, carboidrati, grassi
    let slots: [SlotDef]
}

struct WeekDay: Codable, Hashable {
    let d: String
    let name: String
    let type: String
    let wo: String?
    let pick: [String?]
}

struct WorkoutEx: Codable, Hashable {
    let id: String
    let n: String
    let s: Int
    let lo: Int
    let hi: Int
    let rest: Int
    let start: String
    let inc: Double
    let cue: String
    let unit: String
    let kg: Double?
    let lib: String
    let sup: String?
}

struct WorkoutDef: Codable, Hashable {
    let id: String
    let day: String
    let name: String
    let focus: String
    let ex: [WorkoutEx]
}

struct ExLib: Codable, Hashable {
    let id: String
    let n: String
    let m: String          // muscolo principale
    let sec: [String]
    let inc: Double
    let unit: String       // "reps" o "sec"
    let eq: String
    let cue: String
    let img: String
    let eqv: Int?          // 1 = la foto è di un movimento equivalente
}

struct EquivRow: Codable, Hashable {
    let f: String
    let g: Double
}

struct Equivalent: Codable, Hashable {
    let title: String
    let ref: String
    let g: Double
    let rows: [EquivRow]
}

struct Piano: Codable {
    let version: String
    let foods: [String: Food]
    let recipes: [String: Recipe]
    let variants: [String: [String: [IngredientRef]]]
    let daytypes: [String: DayType]
    let week: [WeekDay]
    let workouts: [WorkoutDef]
    let exlib: [String: ExLib]
    let muscleTargets: [String: Int]
    let equivalents: [Equivalent]

    static let shared: Piano = {
        guard let url = Bundle.main.url(forResource: "piano", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let piano = try? JSONDecoder().decode(Piano.self, from: data) else {
            fatalError("piano.json mancante o illeggibile")
        }
        return piano
    }()
}

// MARK: calcolo dei pasti

struct Tot: Hashable {
    var k: Double = 0
    var p: Double = 0
    var c: Double = 0
    var fa: Double = 0
}

struct Line: Hashable {
    let f: String
    let g: Double
    let k: Double
    let p: Double
    let c: Double
    let fa: Double
}

struct MealPlan: Identifiable, Hashable {
    let si: Int
    let time: String
    let label: String
    let slot: String
    let free: Bool
    let code: String
    let def: String
    let lines: [Line]
    let tot: Tot
    var id: Int { si }
}

struct DayPlan: Hashable {
    let di: Int
    let day: WeekDay
    let dt: DayType
    let conv: String       // «ON» o «OFF_S» se la giornata usa le fasce dell'altro tipo
    let meals: [MealPlan]
    let tot: Tot
    var hasFree: Bool { meals.contains { $0.free } }
}

// cambio di giornata (palestra saltata o recuperata): le fasce sono quelle dell'altro tipo, i pasti già mangiati restano com'erano
struct Conv: Hashable {
    var type: String       // "ON" o "OFF_S"
    var keep: [Int]
}

func r0(_ x: Double) -> Double { x.rounded(.toNearestOrAwayFromZero) }
func r1(_ x: Double) -> Double { (x * 10).rounded(.toNearestOrAwayFromZero) / 10 }

extension Piano {
    func line(_ fid: String, _ g: Double) -> Line {
        guard let f = foods[fid] else { return Line(f: fid, g: g, k: 0, p: 0, c: 0, fa: 0) }   // alimento sconosciuto: non deve mai far chiudere l'app
        return Line(f: fid, g: g, k: r0(f.k * g / 100), p: r1(f.p * g / 100), c: r1(f.c * g / 100), fa: r1(f.f * g / 100))
    }

    func sum(_ ls: [Line]) -> Tot {
        var t = Tot()
        for l in ls { t.k += l.k; t.p += l.p; t.c += l.c; t.fa += l.fa }
        t.p = r1(t.p); t.c = r1(t.c); t.fa = r1(t.fa)
        return t
    }

    func mealLines(_ slot: String, _ code: String) -> [Line] {
        (variants[slot]?[code] ?? []).map { line($0.f, $0.g) }
    }

    // swaps: chiave «giorno:fascia» → codice del piatto scelto al posto di quello previsto
    func dayPlan(_ di: Int, conv: Conv? = nil, swaps: [String: String] = [:]) -> DayPlan {
        let day = week[di]
        let base = daytypes[day.type]!
        let other = conv.flatMap { $0.type != day.type ? daytypes[$0.type] : nil }
        let alt = other.flatMap { $0.slots.count == base.slots.count ? $0 : nil }
        let model = alt != nil ? week.first { $0.type == conv!.type } : nil   // giorno-modello per il piatto di default delle fasce nuove
        var meals: [MealPlan] = []
        for (si, s0) in base.slots.enumerated() {
            let useAlt = alt != nil && !(conv?.keep ?? []).contains(si)
            let s = useAlt ? alt!.slots[si] : s0
            if s.slot == "free" {
                meals.append(MealPlan(si: si, time: s.time, label: s.label, slot: s.slot, free: true, code: "", def: "", lines: [], tot: Tot()))
                continue
            }
            let own = si < day.pick.count ? day.pick[si] : nil
            let def: String = {
                if let own, variants[s.slot]?[own] != nil { return own }
                if let model, si < model.pick.count, let m = model.pick[si] { return m }
                return own ?? ""
            }()
            let sw = swaps["\(di):\(si)"]
            let code = sw.flatMap { variants[s.slot]?[$0] != nil ? $0 : nil } ?? def
            let lines = mealLines(s.slot, code)
            meals.append(MealPlan(si: si, time: s.time, label: s.label, slot: s.slot, free: false, code: code, def: def, lines: lines, tot: sum(lines)))
        }
        var t = Tot()
        for m in meals where !m.free { t.k += m.tot.k; t.p += m.tot.p; t.c += m.tot.c; t.fa += m.tot.fa }
        t.p = r1(t.p); t.c = r1(t.c); t.fa = r1(t.fa)
        return DayPlan(di: di, day: day, dt: alt ?? base, conv: alt != nil ? conv!.type : "", meals: meals, tot: t)
    }

    func recipe(_ code: String) -> Recipe { recipes[code] ?? Recipe(name: code, how: "", kind: "") }
    func foodName(_ id: String) -> String { (foods[id]?.n ?? id).components(separatedBy: " (").first ?? id }
    func exercise(_ id: String) -> ExLib? { exlib[id] }
}

let giorni3 = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]
// il pasto libero (la domenica a pranzo, fuori, senza pesare): per il nutrizionista vale circa 700 kcal ed è già dentro
// le kcal del giorno (piano v3: P 30, C 80, G 28)
let stimaPastoLibero = 700.0
let stimaLibero = Tot(k: stimaPastoLibero, p: 30, c: 80, fa: 28)

extension MealPlan {
    // quanto «vale» il pasto nei conti: il pasto libero con la sua stima
    var kcalPreviste: Double { free ? stimaPastoLibero : tot.k }
}
extension DayPlan {
    // i totali del giorno con il pasto libero stimato (quelli che il piano prevede davvero)
    var previsti: Tot {
        guard hasFree else { return tot }
        return Tot(k: tot.k + stimaLibero.k, p: r1(tot.p + stimaLibero.p), c: r1(tot.c + stimaLibero.c), fa: r1(tot.fa + stimaLibero.fa))
    }
}
