import SwiftUI
import UIKit
import UserNotifications

// Il coach ti scrive lui: la mattina (com'è la giornata, cosa mettere nello zaino), la sera (com'è andata, cosa sistemare)
// e la domenica sera la settimana intera. iOS non lascia girare l'app a un'ora precisa: i messaggi si preparano quando
// esci dall'app e arrivano come notifica all'ora fissata; se prima di quell'ora i dati cambiano, si riscrivono.
// Con l'AI al massimo 4 domande automatiche al giorno (il piano gratis di Gemini ne permette molte di più); senza chiave,
// oltre il limite o se l'AI non risponde, il messaggio lo scrive l'app con i numeri. Quello della sera lo scrive l'AI solo
// dalle 18:30 (dopo cena): prima resta quello coi numeri, così arriva comunque.

extension Bigliettino {
    var titolo: String {
        switch tipo { case "mattino": "Buongiorno"; case "settimana": "La settimana, dal coach"; default: "Com'è andata oggi" }
    }
    var icona: String {
        switch tipo { case "mattino": "sun.max.fill"; case "settimana": "calendar"; default: "moon.stars.fill" }
    }
    var arrivato: Bool { alle <= Cal.ms() }
}

extension AppStore {
    static let maxAutomatiche = 4
    private static var preparando = false
    private static var compito = UIBackgroundTaskIdentifier.invalid

    // mattina: 6:50 nei giorni di scuola (lun–ven), 9:15 nel weekend; sera: 21:30, dopo il promemoria dei panini
    private func oraMattino(_ giorno: Date) -> Date {
        let scuola = Cal.dayIdx(giorno) <= 4
        return Cal.greg.date(bySettingHour: scuola ? 6 : 9, minute: scuola ? 50 : 15, second: 0, of: giorno) ?? giorno
    }
    private func oraSera(_ giorno: Date) -> Date { Cal.greg.date(bySettingHour: 21, minute: 30, second: 0, of: giorno) ?? giorno }

    // i messaggi già arrivati nelle ultime «ore» (il più vecchio prima)
    func bigliettiniArrivati(ore: Double) -> [Bigliettino] {
        let da = Cal.ms() - ore * 3_600_000
        return d.bigliettini.filter { $0.arrivato && $0.alle >= da }.sorted { $0.alle < $1.alle }
    }
    func bigliettinoRecente() -> Bigliettino? { bigliettiniArrivati(ore: 14).last }

    // l'interruttore in Profilo: spento, si tolgono anche quelli già programmati
    func impostaCoachScrive(_ si: Bool) {
        d.coachScrive = si
        if si {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        } else {
            let ids = d.bigliettini.map { "coach-\($0.id)" }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // uscendo dall'app: prepara (o riscrive) il messaggio di stasera e quello della prossima mattina. iOS concede circa
    // 30 secondi in background, bastano per una risposta dell'AI
    func preparaBigliettini() {
        guard d.coachScrive, !AppStore.preparando else { return }
        AppStore.preparando = true
        AppStore.compito = UIApplication.shared.beginBackgroundTask(withName: "coach") {
            MainActor.assumeIsolated { AppStore.fineCompito() }
        }
        Task {
            await preparaOra()
            AppStore.preparando = false
            AppStore.fineCompito()
        }
    }
    private static func fineCompito() {
        guard compito != .invalid else { return }
        UIApplication.shared.endBackgroundTask(compito)
        compito = .invalid
    }

    private func preparaOra() async {
        let permesso = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard permesso == .authorized || permesso == .provisional else { return }
        let limite = Cal.ms() - 14 * 86_400_000
        d.bigliettini.removeAll { $0.alle < limite }
        let ora = Date()
        let oggi = Cal.greg.startOfDay(for: ora)
        await Salute.shared.aggiornaRecenti()
        // stasera (la domenica: la settimana), dalle 13 fino a pochi minuti prima delle 21:30
        let sera = oraSera(oggi)
        if Cal.greg.component(.hour, from: ora) >= 13 && sera.timeIntervalSince(ora) > 300 {
            await prepara(tipo: Cal.dayIdx(ora) == 6 ? "settimana" : "sera", giorno: oggi, alle: sera)
        }
        // la prossima mattina: oggi se non è ancora arrivata, se no domani
        var giorno = oggi
        if oraMattino(giorno).timeIntervalSince(ora) < 300 { giorno = Cal.giorni(1, da: oggi) }
        await prepara(tipo: "mattino", giorno: giorno, alle: oraMattino(giorno))
    }

    // MARK: un messaggio

    private func prepara(tipo: String, giorno: Date, alle: Date) async {
        let id = "\(tipo)-\(Cal.key(giorno))"
        let dati: (impronta: String, richiesta: String, locale: String)
        switch tipo {
        case "mattino": dati = datiMattino(giorno)
        case "settimana": dati = await datiDomenica()
        default: dati = datiSera()
        }
        let chiave = ChiaveCoach.leggi()
        let usaApple = FornitoreCoach.attuale == .apple && AppleCoach.disponibile
        let dopoCena = Cal.greg.component(.hour, from: Date()) * 60 + Cal.greg.component(.minute, from: Date()) >= 18 * 60 + 30
        let puoAI = (usaApple || (chiave != nil && automaticheOggi < AppStore.maxAutomatiche)) && (tipo == "mattino" || dopoCena)
        // già pronto con questi dati (e scritto dall'AI, o l'AI adesso non si può usare): non lo rifaccio
        if let e = d.bigliettini.first(where: { $0.id == id }), e.impronta == dati.impronta, e.ai || !puoAI { return }
        var testo = dati.locale, ai = false
        if puoAI {
            if usaApple,
               let r = try? await AppleCoach.chiediBigliettino(sistema: AppStore.sistemaBigliettini, richiesta: dati.richiesta),
               !r.rifiuto, let pulito = AppStore.pulisci(r.testo) {
                testo = pulito; ai = true
            }
            // se hai scelto Apple Intelligence i tuoi dati restano sul telefono: se non risponde, vale il testo coi numeri
            // (niente passaggio di nascosto a Gemini o agli altri servizi)
            if !ai, !usaApple, let chiave, automaticheOggi < AppStore.maxAutomatiche {
                contaAutomatica()
                let domanda = MessaggioCoach(ruolo: "user", testo: dati.richiesta, t: Cal.ms())
                if let r = try? await ClienteCoach.chiedi(sistema: AppStore.sistemaBigliettini, messaggi: [domanda], chiave: chiave, fornitore: FornitoreCoach.ultimoConChiave),
                   !r.rifiuto, let pulito = AppStore.pulisci(r.testo) {
                    testo = pulito; ai = true
                }
            }
        }
        guard alle.timeIntervalSinceNow > 60 else { return }   // nel frattempo è passata l'ora
        let b = Bigliettino(id: id, tipo: tipo, alle: Cal.ms(alle), testo: testo, impronta: dati.impronta, ai: ai)
        d.bigliettini.removeAll { $0.id == id }
        d.bigliettini.append(b)
        salvaOra()
        let n = UNMutableNotificationContent()
        n.title = b.titolo
        n.body = b.testo
        n.sound = .default
        n.threadIdentifier = "coach"
        n.userInfo = ["apri": "coach"]
        let quando = Cal.greg.dateComponents([.year, .month, .day, .hour, .minute], from: alle)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "coach-\(id)", content: n,
                                                                               trigger: UNCalendarNotificationTrigger(dateMatching: quando, repeats: false)))
    }

    private var automaticheOggi: Int {
        let v = (UserDefaults.standard.string(forKey: "coach.automatiche") ?? "").split(separator: "=")
        return v.count == 2 && v[0] == Cal.key() ? Int(v[1]) ?? 0 : 0
    }
    private func contaAutomatica() { UserDefaults.standard.set("\(Cal.key())=\(automaticheOggi + 1)", forKey: "coach.automatiche") }

    static let sistemaBigliettini = """
    Sei il coach dell'app Recomp (alimentazione e palestra). Scrivi TU un messaggio breve che arriva come notifica sul telefono, \
    senza che la persona abbia chiesto niente. In italiano, dagli del tu, tono diretto e amichevole da allenatore. Massimo 280 \
    caratteri, 2–3 frasi di testo semplice: niente elenchi, titoli, grassetti, saluti lunghi o firme; al massimo un'emoji. \
    Usa solo i dati che ti do (numeri veri, virgola per i decimali) e non inventare niente. Meglio una cosa concreta da fare \
    che tanti complimenti. Non cambiare kcal o porzioni del piano: le decide il suo nutrizionista. Niente legumi né proteine in polvere.
    """

    // il testo dell'AI pronto per la notifica: una riga sola, senza markdown, tagliato a fine frase se è troppo lungo
    private static func pulisci(_ t: String) -> String? {
        var s = t.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "").replacingOccurrences(of: "#", with: "")
        s = s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"«» ").union(.whitespacesAndNewlines))
        guard s.count >= 20 else { return nil }
        if s.count > 420 {
            let corto = String(s.prefix(420))
            if let fine = corto.range(of: ". ", options: .backwards) { s = String(corto[..<fine.lowerBound]) + "." } else { s = corto + "…" }
        }
        return s
    }

    // MARK: i dati di ogni messaggio: impronta (se cambia, si riscrive), domanda per l'AI, testo coi numeri senza AI

    private func pastiInBreve(_ p: DayPlan) -> String {
        p.meals.map { m in m.free ? "\(m.time) \(m.label): pasto libero fuori" : "\(m.time) \(m.label): \(piano.recipe(m.code).name)" }.joined(separator: "; ")
    }
    private func nomeCorto(_ m: MealPlan) -> String { piano.recipe(m.code).name.components(separatedBy: " (").first ?? piano.recipe(m.code).name }

    private func datiMattino(_ giorno: Date) -> (impronta: String, richiesta: String, locale: String) {
        let eOggi = Cal.key(giorno) == oggiKey
        let di = Cal.dayIdx(giorno)
        let p = eOggi ? pianoOggi : pianoGiorno(di)
        let tipo = p.conv.isEmpty ? p.day.type : p.conv
        let on = tipo.hasPrefix("ON")
        let rid = eOggi ? schedaOggi : piano.week[di].wo
        let scheda = rid.flatMap { routine($0) }
        let zaino = p.meals.filter { $0.slot == "m1" || $0.slot == "m2" }
        let r = ritmoPeso()
        var dati = ["Giorno: \(Cal.testo(giorno, "EEEE d MMMM")), giorno \(on ? "ON (palestra)" : "OFF (riposo)"), obiettivo \(fmtMigliaia(p.dt.target[0])) kcal e \(Int(p.dt.target[1])) g di proteine, acqua \(on ? "2,5" : "2") l."]
        dati.append("Pasti: " + pastiInBreve(p) + ".")
        if !zaino.isEmpty {
            dati.append("Nello zaino per la scuola (merende delle 9:30 e 12:10): " + zaino.map { m in
                nomeCorto(m) + " (" + m.lines.map { "\(piano.nome($0).lowercased()) \(Int($0.g)) g" }.joined(separator: ", ") + ")"
            }.joined(separator: " e ") + ".")
        }
        if let scheda { dati.append("Palestra alle 16:30: \(scheda.name), \(scheda.focus), \(scheda.items.count) esercizi. Blocco: settimana \(blocco.n) di 7, \(blocco.fase).") }
        if di == 0 { dati.append("È lunedì: oltre al peso misura la vita all'ombelico.") }
        if Cal.key(giorno) == "2026-11-02" { dati.append("Oggi c'è il primo check-in con il nutrizionista: media del peso, vita, foto, carichi.") }
        if let t = ritmoTesto() { dati.append(t) }
        if let m = Salute.shared.recenti?.sonnoMedio { dati.append("Sonno medio delle ultime notti: \(Int(m / 3600)) h \(String(format: "%02d", Int(m / 60) % 60))′.") }
        let impronta = [Cal.key(giorno), tipo, p.meals.map(\.code).joined(separator: ","), rid ?? "-", r.titolo].joined(separator: "|")
        let richiesta = "Messaggio del MATTINO (arriva alle \(Cal.testo(oraMattino(giorno), "H:mm"))): com'è la giornata e cosa non dimenticare. Dati:\n" + dati.joined(separator: "\n")
        var locale = "Oggi \(on ? "ON" : "OFF") · \(fmtMigliaia(p.dt.target[0])) kcal, \(Int(p.dt.target[1])) g di proteine."
        if let scheda { locale += " Palestra alle 16:30: \(scheda.name)." }
        if !zaino.isEmpty { locale += " Nello zaino: " + zaino.map { nomeCorto($0) }.joined(separator: " e ") + "." }
        if p.hasFree { locale += " A pranzo pasto libero." }
        locale += " Acqua \(on ? "2,5" : "2") l." + (di == 0 ? " Dopo la pesata misura la vita." : "")
        return (impronta, richiesta, locale)
    }

    private func datiSera() -> (impronta: String, richiesta: String, locale: String) {
        let p = pianoOggi
        let t = totaliMangiati()
        let segnati = Set(mangiati())
        let fuori = fuoriOggi()
        var mancano: [String] = []
        var righe: [String] = []
        for m in p.meals {
            let nome = m.label.components(separatedBy: " (").first ?? m.label
            if m.free { righe.append("\(nome): pasto libero"); continue }
            if pastoTolto(m.si) { righe.append("\(nome): tolto da oggi"); continue }
            if let f = fuoriPerFascia(m.si) {
                righe.append("\(nome): \(f.nome), \(Int(f.tot.k)) kcal " + (f.giaMangiato ? "(mangiato)" : "(da mangiare)"))
                if !f.giaMangiato { mancano.append(nome.lowercased()) }
                continue
            }
            righe.append("\(nome): \(nomeCorto(m)) " + (segnati.contains(m.si) ? "(mangiato)" : "(non segnato)"))
            if !segnati.contains(m.si) { mancano.append(nome.lowercased()) }
        }
        let extra = fuori.filter { $0.si == nil && $0.giaMangiato }
        let rid = schedaOggi
        let palestra: String = {
            if let a = d.active { return "allenamento \(a.name) ancora aperto" }
            guard let rid, let r = routine(rid) else { return "giorno senza palestra" }
            guard fattoOggi(rid), let w = cronologia.first(where: { $0.rid == rid && Cal.key(Date(timeIntervalSince1970: $0.start / 1000)) == oggiKey }) else { return "\(r.name) non fatto" }
            return "\(r.name) fatto: \(w.minutes)′, \(w.workSets) serie, \(fmtMigliaia(w.volume)) kg di volume" + (w.prs.isEmpty ? "" : ", \(w.prs.count) record")
        }()
        let pesata = pesate.last { $0.d == oggiKey }
        let domani = pianoGiorno(Cal.dayIdx(Cal.giorni(1, da: Date())))
        let schedaDomani = domani.day.wo.flatMap { routine($0)?.name }
        var dati = ["Oggi (\(Cal.testo(Date(), "EEEE d MMMM"))): mangiato \(fmtMigliaia(t.k)) kcal su \(fmtMigliaia(p.dt.target[0])), proteine \(Int(t.p)) su \(Int(p.dt.target[1])) g (carboidrati \(Int(t.c)), grassi \(Int(t.fa)))."]
        dati.append("Pasti: " + righe.joined(separator: "; ") + (extra.isEmpty ? "" : "; in più: " + extra.map { "\($0.nome) \(Int($0.tot.k)) kcal" }.joined(separator: ", ")) + ".")
        dati.append("Palestra: \(palestra). Creatina \(creatinaPresa() ? "presa" : "non ancora presa"). " + (pesata.map { "Pesata di stamattina: \(fmtPeso($0.kg)) kg." } ?? "Stamattina non si è pesato."))
        if let s = Salute.shared.recentiTesto { dati.append(s + ".") }
        dati.append("Domani: \(domani.day.type.hasPrefix("ON") ? "ON" : "OFF")" + (schedaDomani.map { ", palestra \($0)" } ?? "") + ".")
        let impronta = [oggiKey, String(Int(t.k / 25)), String(Int(t.p / 5)), segnati.sorted().map(String.init).joined(separator: ","),
                        fuori.map { "\($0.id)\($0.giaMangiato)" }.joined(separator: ","), (d.saltati[oggiKey] ?? []).map(String.init).joined(separator: ","),
                        "\(creatinaPresa())", palestra, pesata.map { fmtPeso($0.kg) } ?? "-"].joined(separator: "|")
        let richiesta = "Messaggio della SERA (arriva alle 21:30): com'è andata oggi e una cosa da fare (ancora stasera, come la creatina o segnare un pasto, oppure domani). Dati:\n" + dati.joined(separator: "\n")
        var locale = "Oggi \(fmtMigliaia(t.k)) su \(fmtMigliaia(p.dt.target[0])) kcal, proteine \(Int(t.p)) su \(Int(p.dt.target[1])) g."
        var daFare = mancano.isEmpty ? [] : ["segnare " + mancano.joined(separator: ", ")]
        if !creatinaPresa() { daFare.append("la creatina") }
        locale += daFare.isEmpty ? " Tutto segnato: bel lavoro." : " Manca: " + daFare.joined(separator: " e ") + "."
        if let schedaDomani { locale += " Domani palestra: \(schedaDomani)." }
        return (impronta, richiesta, locale)
    }

    private func datiDomenica() async -> (impronta: String, richiesta: String, locale: String) {
        let w = datiSettimana(0)
        let salute = await Salute.shared.settimana(da: w.lunedi)
        let sera = datiSera()
        var dati = ["Settimana da lunedì \(Cal.testo(w.lunedi, "d MMMM")): \(w.allenamenti.count) allenamenti su 4 (\(w.serie) serie, \(fmtMigliaia(w.volume)) kg di volume, la settimana prima \(fmtMigliaia(w.volumePrima)) kg), \(w.record) record. Giorni con tutti i pasti del piano segnati: \(w.giorniPiano) su \(w.giorniPassati); pasti fuori piano: \(w.fuoriPiano); creatina \(w.creatina) giorni su \(w.giorniPassati)."]
        if let p = w.pesoMedio { dati.append("Peso medio della settimana \(fmtPeso(p)) kg" + (w.pesoPrima.map { ", la settimana prima \(fmtPeso($0))" } ?? "") + ".") }
        if let t = ritmoTesto() { dati.append(t) }
        if let s = salute {
            var r: [String] = []
            if let x = s.sonno { r.append("sonno medio \(Int(x / 3600)) h \(String(format: "%02d", Int(x / 60) % 60))′ a notte (\(s.notti) notti)") }
            if let x = s.passi { r.append("passi medi \(fmtMigliaia(Double(x))) al giorno" + (s.passiPrima.map { " (prima \(fmtMigliaia(Double($0))))" } ?? "")) }
            if !r.isEmpty { dati.append("Da Salute: " + r.joined(separator: ", ") + ".") }
        }
        dati.append("Oggi, domenica: " + sera.richiesta.components(separatedBy: "Dati:\n").last!.replacingOccurrences(of: "\n", with: " "))
        let impronta = "settimana|\(w.allenamenti.count)|\(w.giorniPiano)|\(w.pesoMedio.map(fmtPeso) ?? "-")|" + sera.impronta
        let richiesta = "Messaggio della DOMENICA SERA (arriva alle 21:30): la settimana in breve (allenamenti, piano, peso e ritmo, sonno e passi se ci sono) e un obiettivo semplice per la prossima. Dati:\n" + dati.joined(separator: "\n")
        var locale = "Settimana: \(w.allenamenti.count)/4 allenamenti, \(w.giorniPiano)/\(w.giorniPassati) giorni col piano"
        if let p = w.pesoMedio { locale += ", peso medio \(fmtPeso(p))" }
        locale += "."
        let r = ritmoPeso()
        if r.stato != .pochi { locale += " Ritmo del peso: \(r.titolo.lowercased())." }
        return (impronta, richiesta, locale)
    }
}

// in Oggi: l'ultimo messaggio del coach arrivato (nelle ultime 12 ore), finché non lo chiudi
struct BigliettinoOggi: View {
    @EnvironmentObject var s: AppStore
    let b: Bigliettino

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: b.icona).font(.system(size: 13, weight: .bold)).foregroundStyle(Tema.inchiostro)
                    .frame(width: 28, height: 28).background(Argento(raggio: 14))
                Text("COACH · \(Cal.testo(Date(timeIntervalSince1970: b.alle / 1000), "HH:mm"))").font(.sport(17)).foregroundStyle(Tema.tenue)
                Spacer()
                Button {
                    if let i = s.d.bigliettini.firstIndex(where: { $0.id == b.id }) { withAnimation { s.d.bigliettini[i].visto = true } }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Tema.tenue)
                        .frame(width: 30, height: 30).background(Tema.scheda2, in: Circle())
                }
                .accessibilityLabel("Chiudi il messaggio")
            }
            Text(b.testo).font(.system(size: 15, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Button { s.mostraCoach = true } label: {
                Label("Rispondi al coach", systemImage: "arrowshape.turn.up.left.fill").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(Tema.testo)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
