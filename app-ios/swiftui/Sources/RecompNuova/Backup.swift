import CoreTransferable
import Foundation
import UniformTypeIdentifiers

// il file del backup per «Esporta backup»: si prepara solo quando lo condividi (prima si riscriveva a ogni ridisegno del Profilo)
struct FileBackup: Transferable {
    struct Errore: Error {}
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { _ in
            guard let url = await AppStore.shared.esportaDati() else { throw Errore() }
            return SentTransferredFile(url)
        }
    }
}

// Esporta e importa i dati. L'importazione legge anche il backup dell'app web (Profilo → Esporta backup: un file JSON con le
// chiavi rc.*): così passi da «Recomp» a «Recomp 2» senza perdere pesi, allenamenti e scambi.
extension AppStore {
    func esportaDati() -> URL? {
        guard let data = try? JSONEncoder().encode(d) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recomp2-backup-\(Cal.key()).json")
        try? data.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    func importaBackup(_ data: Data) -> String {
        guard let radice = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "File non valido." }
        // backup dell'app web: { app: "recomp", data: { "rc.weights": "<json>", … } }
        if let web = radice["data"] as? [String: Any] { return importaWeb(web) }
        // backup di Recomp 2: la stessa forma dei dati dell'app
        if let nuovo = try? JSONDecoder().decode(AppData.self, from: data) { d = nuovo; return "Dati ripristinati." }
        return "File non riconosciuto."
    }

    private func json(_ web: [String: Any], _ chiave: String) -> Any? {
        guard let testo = web["rc." + chiave] as? String, let dati = testo.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: dati, options: [.fragmentsAllowed])
    }
    private func decodifica<T: Decodable>(_ tipo: T.Type, _ v: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(v), let dati = try? JSONSerialization.data(withJSONObject: v) else { return nil }
        return try? JSONDecoder().decode(tipo, from: dati)
    }

    func importaWeb(_ web: [String: Any]) -> String {
        var nuovo = d
        var conta: [String] = []

        if let lista = json(web, "weights") as? [[String: Any]] {
            var n = 0
            for x in lista {
                guard let giorno = x["d"] as? String, let kg = (x["kg"] as? NSNumber)?.doubleValue else { continue }
                nuovo.weights.removeAll { $0.d == giorno }
                nuovo.weights.append(WeightEntry(d: giorno, kg: kg, w: (x["w"] as? NSNumber)?.doubleValue, t: (x["t"] as? NSNumber)?.doubleValue))
                n += 1
            }
            conta.append("\(n) pesate")
        }
        if let m = json(web, "eaten") as? [String: [Int]] { for (k, v) in m { nuovo.eaten[k] = v }; conta.append("pasti segnati") }
        if let m = json(web, "swaps") as? [String: String] { for (k, v) in m { nuovo.swaps[k] = v }; conta.append("scambi") }
        if let m = json(web, "creatina") as? [String: Any] {
            for (k, v) in m { if let o = v as? [String: Any] { nuovo.creatina[k] = ((o["on"] as? NSNumber)?.intValue ?? 0) != 0 } }
            conta.append("creatina")
        }
        if let m = json(web, "dayov") as? [String: Any] {
            for (k, v) in m {
                guard let o = v as? [String: Any], o["del"] == nil, let ov = decodificaOv(o) else { continue }
                nuovo.dayov[k] = ov
            }
        }
        if let lista = json(web, "workouts") as? [[String: Any]] {
            var n = 0
            for x in lista where x["del"] == nil && x["start"] != nil {
                guard let w = decodifica(Workout.self, x) else { continue }
                nuovo.workouts.removeAll { $0.id == w.id }
                nuovo.workouts.append(w)
                n += 1
            }
            conta.append("\(n) allenamenti")
        }
        if let l = json(web, "lbEx") as? [String] { nuovo.lbEx = l }
        if let b = json(web, "blockStart") as? String { nuovo.blockStart = b }
        if let sup = json(web, "superserie") as? Bool { nuovo.superserie = sup }
        d = nuovo
        salvaOra()
        return conta.isEmpty ? "Nessun dato trovato nel file." : "Importati: " + conta.joined(separator: ", ") + "."
    }

    private func decodificaOv(_ o: [String: Any]) -> DayOv? {
        var ov = DayOv()
        ov.skip = ((o["skip"] as? NSNumber)?.intValue ?? 0) != 0 ? true : nil
        ov.rid = o["rid"] as? String
        ov.type = o["type"] as? String
        ov.keep = o["keep"] as? [Int]
        ov.t = (o["t"] as? NSNumber)?.doubleValue
        return ov
    }
}
