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
    var f: String
    var g: Double
    var nome: String? = nil    // cibo esterno (codice a barre, Open Food Facts, fuori casa, a mano): nome e valori per 100 g
    var k100: Double? = nil
    var p100: Double? = nil
    var c100: Double? = nil
    var f100: Double? = nil
    var u: Double? = nil       // porzione della confezione, se nota
}

// i cibi di un piatto cambiati a mano (uno scambiato, i grammi, uno aggiunto o tolto): valgono per quel piatto in quella
// fascia; se cambi piatto o la giornata passa da ON a OFF, torna la ricetta del piano
struct CibiPasto: Codable, Hashable {
    var slot: String
    var piatto: String
    var cibi: [IngredientRef]
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
    var nome: String? = nil    // presente quando il cibo è esterno al piano (codice a barre, Open Food Facts, a mano)
    var k100: Double? = nil
    var p100: Double? = nil
    var c100: Double? = nil
    var f100: Double? = nil
    var u: Double? = nil

    var ref: IngredientRef { IngredientRef(f: f, g: g, nome: nome, k100: k100, p100: p100, c100: c100, f100: f100, u: u) }
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
    var cambiato = false   // i cibi del piatto sono stati cambiati a mano
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

    func line(_ r: IngredientRef) -> Line {
        if let k100 = r.k100, foods[r.f] == nil {
            let g = r.g, p100 = r.p100 ?? 0, c100 = r.c100 ?? 0, f100 = r.f100 ?? 0
            return Line(f: r.f, g: g, k: r0(k100 * g / 100), p: r1(p100 * g / 100), c: r1(c100 * g / 100), fa: r1(f100 * g / 100),
                        nome: r.nome, k100: k100, p100: p100, c100: c100, f100: f100, u: r.u)
        }
        return line(r.f, r.g)
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
    // cibi: chiave «giorno:fascia» → i cibi del piatto cambiati a mano (valgono solo per quel piatto in quella fascia)
    func dayPlan(_ di: Int, conv: Conv? = nil, swaps: [String: String] = [:], cibi: [String: CibiPasto] = [:]) -> DayPlan {
        let day = week[di]
        let base = daytypes[day.type]!
        let baseOn = day.type == "ON"
        let vuoleOn = conv.map { $0.type.hasPrefix("ON") } ?? baseOn
        let cambiato = vuoleOn != baseOn
        // ogni giornata (anche del weekend, a 4 pasti) può passare tra ON e OFF: cambiano l'obiettivo e le fasce di pranzo e cena
        let dt: DayType = {
            guard cambiato else { return base }
            if vuoleOn {
                let target = daytypes["ON"]?.target ?? base.target
                let etichetta = (day.type == "OFF_W" || day.type == "FREE") ? "Giorno ON · weekend + palestra" : (daytypes["ON"]?.label ?? base.label)
                let slots = base.slots.map { s in
                    SlotDef(time: s.time, label: s.label, slot: s.slot == "pranzo_off" ? "pranzo_on" : s.slot == "cena_off" ? "cena_on" : s.slot)
                }
                return DayType(label: etichetta, target: target, slots: slots)
            } else {
                let target = daytypes["OFF_S"]?.target ?? base.target
                let etichetta = daytypes["OFF_S"]?.label ?? base.label
                let slots = base.slots.map { s in
                    SlotDef(time: s.time, label: s.label, slot: s.slot == "pranzo_on" ? "pranzo_off" : s.slot == "cena_on" ? "cena_off" : s.slot)
                }
                return DayType(label: etichetta, target: target, slots: slots)
            }
        }()
        let model = cambiato ? week.first { ($0.type == "ON") == vuoleOn } : nil   // giorno-modello per il piatto di default delle fasce nuove
        var meals: [MealPlan] = []
        for (si, s0) in base.slots.enumerated() {
            let useAlt = cambiato && !(conv?.keep ?? []).contains(si)
            let s = useAlt ? dt.slots[si] : s0
            if s.slot == "free" {
                meals.append(MealPlan(si: si, time: s.time, label: s.label, slot: s.slot, free: true, code: "", def: "", lines: [], tot: Tot()))
                continue
            }
            let own = si < day.pick.count ? day.pick[si] : nil
            let def: String = {
                if let own, variants[s.slot]?[own] != nil { return own }
                if let model, si < model.pick.count, let m = model.pick[si], variants[s.slot]?[m] != nil { return m }
                return variants[s.slot]?.keys.sorted().first ?? (own ?? "")
            }()
            let sw = swaps["\(di):\(si)"]
            let code = sw.flatMap { variants[s.slot]?[$0] != nil ? $0 : nil } ?? def
            // i cibi cambiati valgono solo se il piatto è ancora quello (e la fascia la stessa: un giorno passato da ON a OFF torna al piano)
            let miei = cibi["\(di):\(si)"].flatMap { $0.slot == s.slot && $0.piatto == code && !$0.cibi.isEmpty ? $0.cibi : nil }
            let lines = miei.map { $0.map { line($0) } } ?? mealLines(s.slot, code)
            meals.append(MealPlan(si: si, time: s.time, label: s.label, slot: s.slot, free: false, code: code, def: def, lines: lines, tot: sum(lines), cambiato: miei != nil))
        }
        var t = Tot()
        for m in meals where !m.free { t.k += m.tot.k; t.p += m.tot.p; t.c += m.tot.c; t.fa += m.tot.fa }
        t.p = r1(t.p); t.c = r1(t.c); t.fa = r1(t.fa)
        return DayPlan(di: di, day: day, dt: dt, conv: cambiato ? (vuoleOn ? "ON" : "OFF_S") : "", meals: meals, tot: t)
    }

    func recipe(_ code: String) -> Recipe { recipes[code] ?? Recipe(name: code, how: "", kind: "") }
    func foodName(_ id: String) -> String { (foods[id]?.n ?? id).components(separatedBy: " (").first ?? id }
    func nome(_ l: Line) -> String { l.nome ?? foodName(l.f) }
    func icona(_ l: Line) -> String { foods[l.f] != nil ? icona(l.f) : (CibiFuori.icona(l.f) ?? (l.f == "mano" ? "✏️" : "📦")) }
    func aiuto(_ l: Line) -> String { foods[l.f] != nil ? aiuto(l.f, l.g) : "\(Int(l.k)) kcal" }
    func passo(_ r: IngredientRef) -> Double { foods[r.f] != nil ? passoGrammi(r.f, r.g) : (r.g < 50 ? 5 : 10) }
    func exercise(_ id: String) -> ExLib? { exlib[id] }
}

// MARK: cambiare un cibo dentro un pasto

// i cibi che si mangiano a pezzi interi: un hamburger, una scatoletta, un vasetto, una fetta (niente «1 hamburger e mezzo»)
private let aPezzi: Set<String> = ["hamburger_pollo", "hamburger", "cordon_bleu", "tonno", "sgombro", "uova", "fiocchi_latte",
                                   "mozz_light", "budino", "crackers", "wrap", "pane_bauletto", "biraghini"]

extension Piano {
    // un giorno OFF ha le fasce «_off» (pranzo e cena): lì le dosi sono quelle OFF
    func fasciaOn(_ slot: String) -> Bool { !slot.hasSuffix("_off") }

    // una dose vera: a pezzi interi per i cibi a pezzi (a metà si scende), se no a 10 g (5 g sotto i 50 g)
    func doseVera(_ fid: String, _ g: Double) -> Double {
        if aPezzi.contains(fid), let u = foods[fid]?.u, u > 0 { return max(1, (g / u - 0.01).rounded()) * u }
        let p = g < 50 ? 5.0 : 10.0
        return max(p, (g / p).rounded() * p)
    }

    // di quanto cambiano i grammi con «−» e «+»: un pezzo per i cibi a pezzi, 50 g per le patate, 5 g per le dosi piccole, se no 10 g
    func passoGrammi(_ fid: String, _ g: Double) -> Double {
        if aPezzi.contains(fid), let u = foods[fid]?.u, u > 0 { return u }
        if fid == "patate" || fid == "patate_lw" { return 50 }
        return g < 50 ? 5 : 10
    }

    // i grammi di un contorno che danno le stesse kcal del cibo sostituito (arrotondati a 5 g sotto i 100 g, a 10 g sopra)
    func doseIsocalorica(_ fid: String, kcal: Double) -> Double {
        guard let k = foods[fid]?.k, k > 0, kcal > 0 else { return 100 }
        let g = kcal * 100 / k
        let p = g < 100 ? 5.0 : 10.0
        return max(p, (g / p).rounded() * p)
    }

    // patate, Lamb Weston e pane si scambiano a calorie uguali (il nutrizionista: «l'app calcola i grammi esatti sulle kcal»)
    private static let aCalorie: Set<String> = ["patate", "patate_lw", "pane_comune", "pane_int"]

    // la tabella di scambio del nutrizionista che vale per questo cibo in questa fascia: proteine (solo pranzo e cena),
    // affettati, primi. Le patate e il pane no: quelli si scambiano a calorie uguali
    private func tabellaScambio(_ fid: String, slot: String) -> Equivalent? {
        guard !Piano.aCalorie.contains(fid) else { return nil }
        return equivalents.first { t in
            guard t.ref == fid || t.rows.contains(where: { $0.f == fid }) else { return false }
            if t.title.hasPrefix("Patate") { return false }
            if t.title.hasPrefix("Proteine") { return slot.hasPrefix("pranzo") || slot.hasPrefix("cena") }
            return true
        }
    }

    // come si calcolano i grammi delle alternative (la riga sotto «Al suo posto»)
    func notaScambio(_ fid: String, slot: String) -> String {
        let proteine = (foods[fid]?.p ?? 0) >= (foods[fid]?.c ?? 0)
        return conOlio(slot)
            ? "Stessi macro: \(proteine ? "le stesse proteine" : "gli stessi carboidrati"), e i grassi pareggiati con l'olio del pasto (se il pasto non ha olio da togliere, restano le kcal in più)."
            : "\(proteine ? "Le stesse proteine" : "Gli stessi carboidrati") (i grassi possono cambiare un po')."
    }

    // nei pasti cucinati (pranzo e cena) i grassi si pareggiano con l'olio; nei panini, colazione e dopo cena no
    func conOlio(_ slot: String) -> Bool { slot.hasPrefix("pranzo") || slot.hasPrefix("cena") }

    // uno scambio a macro uguali: il cibo nuovo con i grammi che danno lo stesso macro principale (proteine per carne, pesce,
    // latticini, affettati; carboidrati per pasta, riso, pane, patate) e l'olio da aggiungere (+) o togliere (−) nel pasto per
    // pareggiare i grassi. Esempio: 200 g di hamburger di manzo (P 40, G 20) = 175 g di pollo + 18 g di olio
    struct Scambio { var ref: IngredientRef; var olio: Double }

    func scambi(_ fid: String, _ g: Double, slot: String) -> [Scambio] {
        let candidati = alternative(fid, g, slot: slot)
        guard let da = foods[fid] else { return candidati.map { Scambio(ref: $0, olio: 0) } }
        let proteine = da.p >= da.c
        let principaleDa = (proteine ? da.p : da.c) * g / 100
        return candidati.map { a in
            guard let t = foods[a.f], principaleDa > 1 else { return Scambio(ref: a, olio: 0) }
            let perCento = proteine ? t.p : t.c
            guard perCento > 0.5 else { return Scambio(ref: a, olio: 0) }
            let g2 = doseVera(a.f, principaleDa / perCento * 100)
            var olio = 0.0
            if conOlio(slot), foods["olio"] != nil {
                let diff = (da.f * g - t.f * g2) / 100 / 0.999   // grammi d'olio che danno la differenza di grassi
                olio = abs(diff) < 3 ? 0 : (diff / 5).rounded() * 5
            }
            return Scambio(ref: IngredientRef(f: a.f, g: g2), olio: olio)
        }
    }

    // i cibi che possono prendere il posto di questo nel pasto: dalle tabelle di scambio del nutrizionista (in proporzione
    // ai grammi di adesso: 200 g di hamburger = 160 g di pollo = 168 g di tonno), se no a calorie uguali o porzioni normali
    func alternative(_ fid: String, _ g: Double, slot: String) -> [IngredientRef] {
        let lista: [IngredientRef]
        if let t = tabellaScambio(fid, slot: slot), let base = ([EquivRow(f: t.ref, g: t.g)] + t.rows).first(where: { $0.f == fid })?.g, base > 0 {
            let r = g / base
            lista = ([EquivRow(f: t.ref, g: t.g)] + t.rows).filter { $0.f != fid && foods[$0.f] != nil }
                .map { IngredientRef(f: $0.f, g: doseVera($0.f, $0.g * r)) }
        } else {
            lista = alternativeACalorie(fid, g, slot: slot)
        }
        // si scambia solo dentro la stessa categoria: carne e pesce tra loro, latticini tra loro, uova tra loro
        guard let gruppo = Piano.gruppoScambio(fid) else { return lista }
        return lista.filter { gruppo.contains($0.f) }
    }

    // categorie di scambio (scelte dall'utente il 2026-11-20): il pollo si scambia con altra carne o pesce, mai con i
    // latticini; la mozzarella con i fiocchi di latte. I cibi senza categoria seguono solo le tabelle del nutrizionista.
    static let gruppiScambio: [[String]] = [
        ["pollo", "tacchino", "hamburger_pollo", "hamburger", "tonno", "merluzzo", "orata"],   // carne e pesce
        ["mozz_light", "fiocchi_latte", "biraghini"],                                         // latticini
        ["uova", "albume"],                                                                   // uova
    ]
    static func gruppoScambio(_ fid: String) -> [String]? { gruppiScambio.first { $0.contains(fid) } }

    private func alternativeACalorie(_ fid: String, _ g: Double, slot: String) -> [IngredientRef] {
        let on = fasciaOn(slot)
        let panino = slot == "m1" || slot == "m2" || slot == "colazione"
        let gCarne = slot.hasPrefix("pranzo") ? 160.0 : 200.0
        let kcalContorno = max(100, (foods[fid]?.k ?? 0) * g / 100)
        let lista: [IngredientRef]
        switch fid {
        case "patate_lw", "patate":
            lista = [
                IngredientRef(f: "patate_lw", g: doseIsocalorica("patate_lw", kcal: kcalContorno)),
                IngredientRef(f: "patate", g: doseIsocalorica("patate", kcal: kcalContorno)),
                IngredientRef(f: "pane_comune", g: doseIsocalorica("pane_comune", kcal: kcalContorno)),
                IngredientRef(f: "pane_int", g: doseIsocalorica("pane_int", kcal: kcalContorno)),
            ]
        case "pane_bauletto":
            lista = [
                IngredientRef(f: "pane_comune", g: g),
                IngredientRef(f: "pane_int", g: g),
            ]
        case "pane_comune", "pane_int":
            if panino {
                lista = [
                    IngredientRef(f: "pane_bauletto", g: doseVera("pane_bauletto", g)),
                    IngredientRef(f: "pane_comune", g: g),
                    IngredientRef(f: "pane_int", g: g),
                ]
            } else {
                lista = [
                    IngredientRef(f: "patate_lw", g: doseIsocalorica("patate_lw", kcal: kcalContorno)),
                    IngredientRef(f: "patate", g: doseIsocalorica("patate", kcal: kcalContorno)),
                    IngredientRef(f: "pane_comune", g: doseIsocalorica("pane_comune", kcal: kcalContorno)),
                    IngredientRef(f: "pane_int", g: doseIsocalorica("pane_int", kcal: kcalContorno)),
                ]
            }
        case "pasta", "pasta_int", "riso":
            let gPrimo = (g == 80 || g == 100) ? g : (on ? 100 : 80)
            lista = [
                IngredientRef(f: "pasta", g: gPrimo),
                IngredientRef(f: "riso", g: gPrimo),
                IngredientRef(f: "pasta_int", g: gPrimo),
                IngredientRef(f: "wrap", g: 120),
            ]
        case "wrap":
            let gPrimo = on ? 100.0 : 80.0
            lista = [
                IngredientRef(f: "pasta", g: gPrimo),
                IngredientRef(f: "riso", g: gPrimo),
                IngredientRef(f: "pasta_int", g: gPrimo),
            ]
        case "pollo", "tacchino", "hamburger_pollo", "hamburger", "tonno", "merluzzo", "orata":
            lista = [
                IngredientRef(f: "pollo", g: gCarne),
                IngredientRef(f: "tacchino", g: gCarne),
                IngredientRef(f: "hamburger_pollo", g: 200),
                IngredientRef(f: "hamburger", g: 200),
                IngredientRef(f: "tonno", g: 168),
                IngredientRef(f: "merluzzo", g: 250),
                IngredientRef(f: "orata", g: 200),
            ]
        case "tacchino_fette", "pollo_fette", "cotto", "bresaola":
            lista = [
                IngredientRef(f: "tacchino_fette", g: g),
                IngredientRef(f: "pollo_fette", g: g),
                IngredientRef(f: "cotto", g: g),
                IngredientRef(f: "bresaola", g: g),
            ]
        case "fiocchi_latte", "biraghini", "mozz_light":
            lista = [
                IngredientRef(f: "mozz_light", g: 125),
                IngredientRef(f: "fiocchi_latte", g: 150),
                IngredientRef(f: "biraghini", g: 33),
            ]
        case "uova", "albume":
            lista = [
                IngredientRef(f: "uova", g: 110),
                IngredientRef(f: "albume", g: 250),
            ]
        case "banana", "mela":
            lista = [
                IngredientRef(f: "banana", g: 120),
                IngredientRef(f: "mela", g: 180),
            ]
        default:
            lista = []
        }
        return lista.filter { $0.f != fid && foods[$0.f] != nil }
    }

    // la dose di un cibo aggiunto a un pasto: quella che il piano usa più spesso (prima nella stessa fascia), se no un pezzo o 100 g
    func doseNuova(_ fid: String, slot: String) -> Double {
        func dosi(_ vv: [[IngredientRef]]) -> [Double] { vv.flatMap { $0.filter { $0.f == fid }.map(\.g) } }
        var tutte = dosi(Array((variants[slot] ?? [:]).values))
        if tutte.isEmpty { tutte = dosi(variants.values.flatMap { $0.values }) }
        let conta = Dictionary(tutte.map { ($0, 1) }, uniquingKeysWith: +)
        if let g = conta.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key })?.key { return g }
        return doseVera(fid, foods[fid]?.u ?? 100)
    }
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
