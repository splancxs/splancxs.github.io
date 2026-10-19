import Foundation

// «2 fette», «1 vasetto», «3 cucchiai»: l'aiuto in pezzi accanto ai grammi (chi pesa il cibo guarda i grammi,
// l'unità è solo un aiuto). Il peso di un pezzo («u») viene dal piano del nutrizionista (tools/dieta.json).
private let unita: [String: (String, String)] = [
    "pane_bauletto": ("fetta", "fette"), "wrap": ("wrap", "wrap"),
    "tacchino_fette": ("vaschetta da 120 g", "vaschette da 120 g"), "pollo_fette": ("vaschetta da 130 g", "vaschette da 130 g"),
    "bresaola": ("confezione da 80 g", "confezioni da 80 g"), "hamburger": ("hamburger", "hamburger"),
    "tonno": ("scatoletta da 80 g", "scatolette da 80 g"), "sgombro": ("scatoletta", "scatolette"),
    "uova": ("uovo", "uova"), "yogurt": ("vasetto da 170 g", "vasetti da 170 g"), "fiocchi_latte": ("vaschetta da 175 g", "vaschette da 175 g"),
    "budino": ("vasetto", "vasetti"), "latte": ("tazza", "tazze"),
    "banana": ("banana", "banane"), "kiwi": ("kiwi", "kiwi"), "mela": ("mela", "mele"), "frutti_bosco": ("vaschetta da 125 g", "vaschette da 125 g"),
    "passata": ("brick da 200 g", "brick da 200 g"),
]
private let cucchiai: [String: (Double, String, String)] = [
    "avena": (10, "cucchiaio", "cucchiai"), "miele": (5, "cucchiaino", "cucchiaini"), "parmigiano": (5, "cucchiaino", "cucchiaini"),
    "burro_arachidi": (15, "cucchiaio", "cucchiai"),
]
private let pezzi: [String: (Double, String)] = ["mandorle": (1.2, "mandorle")]

extension Piano {
    // shop = lista della spesa: lì servono le confezioni intere da comprare, non i cucchiai
    func aiuto(_ fid: String, _ g: Double, spesa: Bool = false) -> String {
        if fid == "olio" {
            if spesa { return "" }
            if g < 4 { return "un filo" }
            if g.truncatingRemainder(dividingBy: 10) == 0 { return "\(Int(g / 10)) \(g == 10 ? "cucchiaio" : "cucchiai")" }
            return "\(Int((g / 5).rounded())) \(g <= 7 ? "cucchiaino" : "cucchiaini")"
        }
        // il latte nella spesa va in litri (brick da 1 l), non in tazze
        if fid == "latte" && spesa { let l = max(1, (g / 1000).rounded(.up)); return "≈ \(Int(l)) \(l == 1 ? "litro" : "litri")" }
        if !spesa, let (u, uno, molti) = cucchiai[fid] {
            let n = max(1, (g / u).rounded())
            return "\(abs(g / u - n) < 0.1 ? "" : "≈ ")\(Int(n)) \(n == 1 ? uno : molti)"
        }
        if !spesa, let (peso, nome) = pezzi[fid] { return "≈ \(Int((g / peso).rounded())) \(nome)" }
        guard let f = foods[fid], let u = f.u, let (uno, molti) = unita[fid] else { return "" }
        let n = g / u
        if spesa { let c = max(1, (n - 0.1).rounded(.up)); return "≈ \(Int(c)) \(c == 1 ? uno : molti)" }
        if ["mela", "banana"].contains(fid) && n > 1.15 && n < 1.45 { return "1 \(uno) grande" }
        let h = max(0.5, (n * 2).rounded() / 2)   // mezze unità: ½ vaschetta, 1 e ½ fette…
        let txt = h == 0.5 ? "½" : h.truncatingRemainder(dividingBy: 1) != 0 ? "\(Int(h)) e ½" : String(Int(h))
        return "\(abs(n - h) < 0.08 ? "" : "≈ ")\(txt) \(h <= 1 ? uno : molti)"
    }

    func unitaPeso(_ fid: String) -> String { ["latte", "latte_ps", "spremuta"].contains(fid) ? "ml" : "g" }
}
