import Foundation

// Un'icona per ogni alimento, così nel Piano i cibi si riconoscono a colpo d'occhio (non solo dal nome).
// Codici del piano v4 del nutrizionista (tools/dieta.json); i cibi senza icona prendono quella della categoria.
private let iconeCibi: [String: String] = [
    // pane, pasta e cereali
    "pane_bauletto": "🍞", "pane_comune": "🥖", "pane_int": "🍞", "wrap": "🌯", "crackers": "🍘",
    "pasta": "🍝", "pasta_int": "🍝", "riso": "🍚", "patate": "🥔", "patate_lw": "🍟", "avena": "🌾", "cereali": "🥣",
    // affettati, carne e pesce
    "tacchino_fette": "🦃", "pollo_fette": "🍗", "cotto": "🥓", "bresaola": "🥩",
    "pollo": "🍗", "tacchino": "🦃", "hamburger_pollo": "🍔", "hamburger": "🍔", "cordon_bleu": "🍗",
    "merluzzo": "🐟", "orata": "🐟", "tonno": "🥫", "sgombro": "🥫",
    // latticini e uova
    "uova": "🥚", "albume": "🥚", "yogurt": "🥣", "fiocchi_latte": "🧀", "mozz_light": "🧀",
    "formaggio_light": "🧀", "biraghini": "🧀", "budino": "🍮", "parmigiano": "🧀", "latte": "🥛",
    // verdura e frutta
    "pomodori": "🍅", "insalata": "🥗", "carote": "🥕", "peperoni": "🫑",
    "banana": "🍌", "kiwi": "🥝", "mela": "🍎", "frutti_bosco": "🫐",
    // condimenti e dispensa
    "passata": "🍅", "olio": "🫒", "mandorle": "🌰", "burro_arachidi": "🥜", "miele": "🍯",
]
private let iconeCategorie: [String: String] = [
    "Carne e pesce": "🍗", "Affettati": "🥓", "Latticini e uova": "🥚", "Pane, pasta e cereali": "🍞",
    "Frutta": "🍎", "Verdura cruda": "🥗", "Condimenti e dispensa": "🫙", "Integratori e snack": "🥤",
]

extension Piano {
    func icona(_ fid: String) -> String { iconeCibi[fid] ?? iconeCategorie[foods[fid]?.cat ?? ""] ?? "🍽️" }
    func iconaCategoria(_ cat: String) -> String { iconeCategorie[cat] ?? "🍽️" }
    // un'icona sola per il piatto: quella del cibo che dà il nome al piatto, cioè quello con più proteine (merluzzo, tonno,
    // uova…; le patate o il pane portano più calorie ma non dicono cos'è). I condimenti solo se non c'è altro
    func iconaPiatto(_ righe: [Line]) -> String {
        let principali = righe.filter { foods[$0.f]?.cat != "Condimenti e dispensa" }
        guard let r = (principali.isEmpty ? righe : principali).max(by: { ($0.p, $0.k) < ($1.p, $1.k) }) else { return "🍽️" }
        return icona(r.f)
    }
    // le icone degli ingredienti di un piatto, nell'ordine e senza doppioni («🍞🥓🧀🍎»)
    func iconePiatto(_ righe: [Line]) -> String {
        var viste = Set<String>()
        return righe.map { icona($0.f) }.filter { viste.insert($0).inserted }.joined()
    }
}
