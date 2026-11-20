import Foundation

// Cibi di tutti i giorni fuori casa (bar, pizzeria, fast food, mensa) con una porzione normale e i valori medi per 100 g.
// Sono stime, come quelle che faresti a occhio, ma bastano per segnare un pasto senza cercare ogni prodotto:
// i grammi si cambiano dopo. Per i prodotti confezionati c'è il codice a barre (Open Food Facts).
struct CiboFuori: Identifiable, Hashable {
    let id: String
    let nome: String
    let icona: String
    let porzione: Double      // grammi (o ml) di una porzione normale
    let quanto: String        // la porzione detta come la diresti («1 pizza intera», «1 lattina»)
    let k, p, c, f: Double    // per 100 g

    var voce: VoceCibo { VoceCibo(nome: nome, g: porzione, k100: k, p100: p, c100: c, f100: f, fonte: "fuori:" + id) }
}

enum CibiFuori {
    static let tutti: [CiboFuori] = [
        // bar
        .init(id: "cornetto", nome: "Cornetto semplice", icona: "🥐", porzione: 60, quanto: "1 cornetto", k: 410, p: 8, c: 46, f: 21),
        .init(id: "cornetto_marmellata", nome: "Cornetto alla marmellata", icona: "🥐", porzione: 80, quanto: "1 cornetto", k: 370, p: 6.5, c: 52, f: 15),
        .init(id: "cornetto_crema", nome: "Cornetto alla crema o al cioccolato", icona: "🥐", porzione: 80, quanto: "1 cornetto", k: 400, p: 7, c: 48, f: 20),
        .init(id: "bombolone", nome: "Bombolone (krapfen)", icona: "🍩", porzione: 80, quanto: "1 bombolone", k: 380, p: 6.5, c: 45, f: 19),
        .init(id: "cappuccino", nome: "Cappuccino", icona: "☕", porzione: 160, quanto: "1 tazza", k: 47, p: 2.5, c: 3.7, f: 2.5),
        .init(id: "caffe_zucchero", nome: "Caffè con zucchero", icona: "☕", porzione: 30, quanto: "1 tazzina con 1 bustina", k: 67, p: 0, c: 16.5, f: 0),
        .init(id: "toast", nome: "Toast prosciutto e formaggio", icona: "🥪", porzione: 130, quanto: "1 toast", k: 280, p: 14, c: 28, f: 12),
        .init(id: "tramezzino", nome: "Tramezzino", icona: "🥪", porzione: 100, quanto: "1 tramezzino", k: 250, p: 9, c: 22, f: 14),
        .init(id: "panino_salume", nome: "Panino con salume", icona: "🥪", porzione: 150, quanto: "1 panino", k: 280, p: 13, c: 33, f: 10),
        // pizzeria, piadineria, rosticceria
        .init(id: "pizza", nome: "Pizza margherita", icona: "🍕", porzione: 330, quanto: "1 pizza intera", k: 250, p: 10, c: 32, f: 8.5),
        .init(id: "pizza_taglio", nome: "Pizza al taglio", icona: "🍕", porzione: 150, quanto: "1 trancio", k: 260, p: 9, c: 35, f: 9),
        .init(id: "focaccia", nome: "Focaccia", icona: "🫓", porzione: 100, quanto: "1 pezzo", k: 300, p: 7, c: 45, f: 10),
        .init(id: "piadina", nome: "Piadina (solo la piadina)", icona: "🫓", porzione: 120, quanto: "1 piadina vuota", k: 310, p: 8, c: 50, f: 9),
        .init(id: "arancino", nome: "Arancino", icona: "🍙", porzione: 200, quanto: "1 arancino", k: 240, p: 7, c: 30, f: 10),
        .init(id: "kebab", nome: "Kebab nel pane", icona: "🥙", porzione: 350, quanto: "1 panino", k: 215, p: 12, c: 21, f: 9),
        // fast food
        .init(id: "panino_fast", nome: "Panino hamburger del fast food", icona: "🍔", porzione: 220, quanto: "1 panino grande", k: 250, p: 13, c: 21, f: 12.5),
        .init(id: "patatine", nome: "Patatine fritte", icona: "🍟", porzione: 120, quanto: "1 porzione media", k: 312, p: 3.4, c: 41, f: 15),
        .init(id: "crocchette_pollo", nome: "Crocchette di pollo (nuggets)", icona: "🍗", porzione: 110, quanto: "6 pezzi", k: 270, p: 15, c: 16, f: 16),
        // trattoria e mensa
        .init(id: "pasta_pomodoro", nome: "Pasta al pomodoro", icona: "🍝", porzione: 350, quanto: "1 piatto", k: 150, p: 5, c: 26, f: 3),
        .init(id: "pasta_carbonara", nome: "Pasta alla carbonara", icona: "🍝", porzione: 350, quanto: "1 piatto", k: 205, p: 8.5, c: 24, f: 8.5),
        .init(id: "pasta_ragu", nome: "Pasta al ragù", icona: "🍝", porzione: 350, quanto: "1 piatto", k: 170, p: 7.5, c: 24, f: 5),
        .init(id: "lasagne", nome: "Lasagne", icona: "🍝", porzione: 350, quanto: "1 porzione", k: 165, p: 8.5, c: 14, f: 8.5),
        .init(id: "risotto", nome: "Risotto", icona: "🍚", porzione: 350, quanto: "1 piatto", k: 160, p: 4, c: 25, f: 5),
        .init(id: "cotoletta", nome: "Cotoletta alla milanese", icona: "🍗", porzione: 150, quanto: "1 cotoletta", k: 250, p: 18, c: 12, f: 14),
        .init(id: "patate_forno", nome: "Patate al forno", icona: "🥔", porzione: 200, quanto: "1 contorno", k: 130, p: 2, c: 20, f: 5),
        .init(id: "insalatona", nome: "Insalatona con tonno e mozzarella", icona: "🥗", porzione: 350, quanto: "1 ciotola", k: 110, p: 8, c: 3, f: 7.5),
        .init(id: "sushi", nome: "Sushi misto", icona: "🍣", porzione: 240, quanto: "8 pezzi", k: 150, p: 6, c: 28, f: 1.5),
        // dolci e snack
        .init(id: "gelato", nome: "Gelato", icona: "🍨", porzione: 120, quanto: "1 coppetta, 2 gusti", k: 190, p: 3.5, c: 26, f: 8),
        .init(id: "tiramisu", nome: "Tiramisù", icona: "🍰", porzione: 120, quanto: "1 porzione", k: 290, p: 6, c: 28, f: 17),
        .init(id: "cioccolato", nome: "Cioccolato al latte", icona: "🍫", porzione: 25, quanto: "1 barretta piccola", k: 545, p: 7.5, c: 57, f: 31),
        .init(id: "patatine_busta", nome: "Patatine in busta", icona: "🥔", porzione: 45, quanto: "1 busta", k: 535, p: 6, c: 52, f: 33),
        .init(id: "biscotti", nome: "Biscotti secchi", icona: "🍪", porzione: 30, quanto: "4 biscotti", k: 440, p: 7, c: 72, f: 13),
        .init(id: "merendina", nome: "Merendina confezionata", icona: "🧁", porzione: 35, quanto: "1 merendina", k: 420, p: 6, c: 55, f: 19),
        // da bere
        .init(id: "cola", nome: "Coca-Cola", icona: "🥤", porzione: 330, quanto: "1 lattina", k: 42, p: 0, c: 10.6, f: 0),
        .init(id: "bibita_zero", nome: "Bibita zero", icona: "🥤", porzione: 330, quanto: "1 lattina", k: 0.3, p: 0, c: 0, f: 0),
        .init(id: "te_freddo", nome: "Tè freddo", icona: "🧃", porzione: 500, quanto: "1 bottiglia da 500 ml", k: 31, p: 0, c: 7.6, f: 0),
        .init(id: "succo", nome: "Succo di frutta", icona: "🧃", porzione: 200, quanto: "1 brick", k: 50, p: 0.3, c: 12, f: 0),
        .init(id: "birra", nome: "Birra", icona: "🍺", porzione: 400, quanto: "1 media", k: 43, p: 0.5, c: 3.6, f: 0),
    ]

    // quelli che compaiono subito, senza cercare
    static let rapidi = ["pizza", "cornetto", "cappuccino", "piadina", "patatine", "panino_fast", "kebab", "pasta_pomodoro", "gelato", "cola", "te_freddo"]

    static func cibo(_ id: String) -> CiboFuori? { tutti.first { $0.id == id } }
    // l'icona di una voce che viene da qui («fuori:pizza»)
    static func icona(_ fonte: String?) -> String? {
        guard let f = fonte, f.hasPrefix("fuori:") else { return nil }
        return cibo(String(f.dropFirst(6)))?.icona
    }
}

// la ricerca senza maiuscole né accenti: «caffe» trova «Caffè». Prima chi inizia con quello che scrivi, poi chi ha una
// parola che inizia così, poi chi lo contiene da qualche parte (nil = non c'entra)
func puntiRicerca(_ nome: String, _ cerca: String) -> Int? {
    let piega = { (x: String) in x.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT")) }
    let n = piega(nome), q = piega(cerca.trimmingCharacters(in: .whitespaces))
    guard !q.isEmpty else { return nil }
    if n.hasPrefix(q) { return 0 }
    if n.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(q) }) { return 1 }
    return n.contains(q) ? 2 : nil
}
