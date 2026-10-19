import Foundation
import SQLite3

// Quando «Recomp 2» prende il posto di «Recomp» (stesso identificativo) la cartella dell'app resta la stessa: dentro c'è ancora
// la memoria del sito (LocalStorage, un file SQLite). La leggo (su una copia, senza toccare l'originale) e riprendo da lì
// pesi, allenamenti, pasti segnati, scambi e unità: nessun backup da fare a mano.
enum MigrazioneWeb {
    static func trovaFile() -> [URL] {
        let radice = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        guard let giro = FileManager.default.enumerator(at: radice, includingPropertiesForKeys: nil) else { return [] }
        var out: [URL] = []
        for case let u as URL in giro where u.lastPathComponent.lowercased() == "localstorage.sqlite3" { out.append(u) }
        return out
    }

    // WebKit salva i valori come testo UTF-16 (a volte UTF-8): provo l'uno e l'altro e tengo quello che è JSON valido
    private static func testo(_ dati: Data) -> String? {
        for codifica in [String.Encoding.utf16LittleEndian, .utf8] {
            if let s = String(data: dati, encoding: codifica), let d = s.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])) != nil { return s }
        }
        return nil
    }

    static func leggi() -> [String: Any]? {
        let fm = FileManager.default
        for url in trovaFile() {
            // copia con i file -wal e -shm (le scritture recenti stanno lì) in una cartella temporanea
            let tmp = fm.temporaryDirectory.appendingPathComponent("ls-\(UUID().uuidString)")
            try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tmp) }
            let nome = url.lastPathComponent
            for coda in ["", "-wal", "-shm"] {
                let sorgente = url.deletingLastPathComponent().appendingPathComponent(nome + coda)
                if fm.fileExists(atPath: sorgente.path) { try? fm.copyItem(at: sorgente, to: tmp.appendingPathComponent(nome + coda)) }
            }
            var db: OpaquePointer?
            guard sqlite3_open(tmp.appendingPathComponent(nome).path, &db) == SQLITE_OK else { sqlite3_close(db); continue }
            defer { sqlite3_close(db) }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT key, value FROM ItemTable WHERE key LIKE 'rc.%'", -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }
            var out: [String: Any] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let k = sqlite3_column_text(stmt, 0) else { continue }
                let n = Int(sqlite3_column_bytes(stmt, 1))
                guard n > 0, let p = sqlite3_column_blob(stmt, 1), let s = testo(Data(bytes: p, count: n)) else { continue }
                out[String(cString: k)] = s
            }
            if out["rc.weights"] != nil || out["rc.workouts"] != nil || out["rc.eaten"] != nil { return out }
        }
        return nil
    }
}

extension AppStore {
    // al primo avvio dopo l'aggiornamento: se qui non c'è ancora niente, riprendo i dati dell'app vecchia
    @discardableResult
    func migraDalSito(forza: Bool = false) -> String {
        if !forza && (d.migrato || !d.weights.isEmpty || !d.workouts.isEmpty) { return "" }
        guard let web = MigrazioneWeb.leggi() else { return forza ? "Non trovo i dati dell'app vecchia su questo telefono." : "" }
        let messaggio = importaWeb(web)
        d.migrato = true
        return messaggio
    }
}
