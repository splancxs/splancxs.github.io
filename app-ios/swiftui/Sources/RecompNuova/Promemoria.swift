import Foundation
import UserNotifications

// Promemoria (notifiche locali): la merenda di domani, la pesata, la palestra, la creatina se non l'hai segnata.
// Si riprogrammano da zero a ogni cambiamento: gli identificativi sono fissi, quindi non si creano doppioni.
enum Promemoria {
    static let nomi: [(String, String)] = [
        ("merenda", "Panini di domani (21:00)"), ("peso", "Pesata del mattino"),
        ("palestra", "Palestra (16:00 nei giorni ON)"), ("creatina", "Creatina, se non l'hai ancora segnata"),
    ]
}

extension AppStore {
    func impostaPromemoria(_ chiave: String, _ attivo: Bool) {
        if attivo {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
                DispatchQueue.main.async {
                    self.d.promemoria[chiave] = ok && attivo
                    self.riprogrammaPromemoria()
                }
            }
        } else {
            d.promemoria[chiave] = false
            riprogrammaPromemoria()
        }
    }

    // weekday delle notifiche: 1 = domenica … 7 = sabato; di: 0 = lunedì … 6 = domenica
    private func giornoNotifica(_ di: Int) -> Int { (di + 1) % 7 + 1 }

    func riprogrammaPromemoria() {
        let c = UNUserNotificationCenter.current()
        let id100 = (100..<160).map(String.init)
        c.removePendingNotificationRequests(withIdentifiers: id100)
        func aggiungi(_ id: Int, _ titolo: String, _ corpo: String, _ comp: DateComponents, ripeti: Bool) {
            let n = UNMutableNotificationContent()
            n.title = titolo; n.body = corpo; n.sound = .default
            c.add(UNNotificationRequest(identifier: String(id), content: n, trigger: UNCalendarNotificationTrigger(dateMatching: comp, repeats: ripeti)))
        }
        if d.promemoria["merenda"] == true {
            for di in 0..<7 {
                let domani = (di + 1) % 7
                if domani > 4 { continue }   // domani non c'è scuola
                let p = pianoGiorno(domani)
                // i due panini di scuola: nome e ingredienti con i grammi
                let panini = p.meals.filter { $0.slot == "m1" || $0.slot == "m2" }.map { m in
                    (piano.recipe(m.code).name.components(separatedBy: " (").first ?? piano.recipe(m.code).name) + ": "
                        + m.lines.map { "\(piano.foodName($0.f).lowercased()) \(Int($0.g)) g" }.joined(separator: ", ")
                }
                guard !panini.isEmpty else { continue }
                aggiungi(100 + di, "Prepara i panini per \(p.day.name.lowercased())", panini.joined(separator: " · "),
                         DateComponents(hour: 21, minute: 0, weekday: giornoNotifica(di)), ripeti: true)
            }
        }
        if d.promemoria["peso"] == true {
            for di in 0..<7 {
                aggiungi(110 + di, "Pesata del mattino", "A digiuno, dopo il bagno. Poi segnalo in Progressi." + (di == 0 ? " Oggi misura anche la vita." : ""),
                         DateComponents(hour: di <= 4 ? 6 : 9, minute: di <= 4 ? 35 : 0, weekday: giornoNotifica(di)), ripeti: true)
            }
        }
        // palestra: una per giorno di allenamento nei prossimi 14 giorni (non ripetuta: oggi non arriva se l'hai saltata,
        // se l'allenamento è già fatto o in corso; arriva invece se oggi recuperi un allenamento)
        if d.promemoria["palestra"] == true {
            for i in 0..<14 {
                guard let giorno = Cal.greg.date(byAdding: .day, value: i, to: Date()),
                      let alle = Cal.greg.date(bySettingHour: 16, minute: 0, second: 0, of: giorno), alle.timeIntervalSinceNow > 30 else { continue }
                let di = Cal.dayIdx(giorno)
                let rid = i == 0 ? schedaOggi : piano.week[di].wo
                guard let id = rid, let r = routine(id) else { continue }
                if i == 0 && (fattoOggi(id) || d.active != nil) { continue }
                aggiungi(120 + i, "Alle 16:30: \(r.name)", "\(r.focus). Borraccia (2,5 l d'acqua oggi) e asciugamano.",
                         Cal.greg.dateComponents([.year, .month, .day, .hour, .minute], from: alle), ripeti: false)
            }
        }
        // creatina: una al giorno per i prossimi 14 giorni, tolta il giorno in cui la segni
        if d.promemoria["creatina"] == true {
            let parti = d.creaOra.split(separator: ":").compactMap { Int($0) }
            let (h, m) = (parti.first ?? 20, parti.count > 1 ? parti[1] : 30)
            for i in 0..<14 {
                guard let giorno = Cal.greg.date(byAdding: .day, value: i, to: Date()),
                      let alle = Cal.greg.date(bySettingHour: h, minute: m, second: 0, of: giorno),
                      alle.timeIntervalSinceNow > 30, !creatinaPresa(Cal.key(giorno)) else { continue }
                aggiungi(140 + i, "Creatina", "Oggi non l'hai ancora segnata: 3–5 g con un bicchiere d'acqua.",
                         Cal.greg.dateComponents([.year, .month, .day, .hour, .minute], from: alle), ripeti: false)
            }
        }
        programmaRiepilogo()
    }
}
