import SwiftUI
import UserNotifications

// Riepilogo della settimana: allenamenti, volume, serie, record, peso medio (con la differenza dalla settimana prima),
// giorni con tutti i pasti segnati, creatina. Una notifica la domenica alle 20:00 (promemoria «riepilogo») e una pagina che
// si apre dalla notifica o toccando i riquadri della settimana in Progressi.

struct DatiSettimana {
    var lunedi: Date
    var allenamenti: [Workout]
    var volume: Double
    var serie: Int
    var record: Int
    var minuti: Int
    var pesoMedio: Double?
    var pesoPrima: Double?
    var volumePrima: Double
    var giorniPiano: Int          // giorni con tutti i pasti del piano segnati (o sostituiti fuori piano)
    var giorniPassati: Int
    var creatina: Int
    var fuoriPiano: Int
}

extension AppStore {
    func datiSettimana(_ indietro: Int = 0) -> DatiSettimana {
        let lun = Cal.lunedi(indietro: indietro)
        func fra(_ da: Date) -> [Workout] {
            let a = Cal.ms(da), b = Cal.ms(Cal.giorni(7, da: da))
            return cronologia.filter { $0.start >= a && $0.start < b }
        }
        func pesoMedio(_ da: Date) -> Double? {
            let v = pesate.filter { Cal.date($0.d) >= da && Cal.date($0.d) < Cal.giorni(7, da: da) }
            return v.isEmpty ? nil : v.reduce(0) { $0 + $1.kg } / Double(v.count)
        }
        let ws = fra(lun)
        let prima = Cal.giorni(-7, da: lun)
        let passati = indietro > 0 ? 7 : oggiIdx + 1
        var piano = 0, crea = 0, fuori = 0
        for g in 0..<passati {
            let key = Cal.key(Cal.giorni(g, da: lun))
            let p = pianoGiorno(g)
            let sostituite = Set((d.fuori[key] ?? []).compactMap(\.si))
            let fatti = Set(mangiati(key)).union(sostituite)
            if p.meals.filter({ !$0.free }).allSatisfy({ fatti.contains($0.si) }) { piano += 1 }
            if creatinaPresa(key) { crea += 1 }
            fuori += (d.fuori[key] ?? []).count
        }
        return DatiSettimana(lunedi: lun, allenamenti: ws, volume: ws.reduce(0) { $0 + $1.volume }, serie: ws.reduce(0) { $0 + $1.workSets },
                             record: ws.reduce(0) { $0 + $1.prs.count }, minuti: ws.reduce(0) { $0 + $1.minutes },
                             pesoMedio: pesoMedio(lun), pesoPrima: pesoMedio(prima), volumePrima: fra(prima).reduce(0) { $0 + $1.volume },
                             giorniPiano: piano, giorniPassati: passati, creatina: crea, fuoriPiano: fuori)
    }

    // la notifica della domenica sera, con i numeri di adesso (si rifà a ogni allenamento, pesata, apertura dell'app)
    func programmaRiepilogo() {
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: ["160"])
        guard d.promemoria["riepilogo"] == true else { return }
        let w = datiSettimana()
        var righe = ["\(w.allenamenti.count)/4 allenamenti", "\(fmtMigliaia(w.volume)) kg"]
        if w.record > 0 { righe.append("🏆 \(w.record) record") }
        if let p = w.pesoMedio {
            var r = "peso medio \(fmtPeso(p))"
            if let q = w.pesoPrima { let d = p - q; r += " (\(d > 0 ? "+" : d < 0 ? "−" : "±")\(fmtPeso(abs(d))))" }
            righe.append(r)
        }
        let n = UNMutableNotificationContent()
        n.title = "La tua settimana"
        n.body = righe.joined(separator: " · ") + ". Tocca per il riepilogo."
        n.sound = .default
        n.userInfo = ["apri": "riepilogo"]
        let domenica = Cal.giorni(6, da: w.lunedi)
        guard let alle = Cal.greg.date(bySettingHour: 20, minute: 0, second: 0, of: domenica), alle.timeIntervalSinceNow > 30 else { return }
        c.add(UNNotificationRequest(identifier: "160", content: n,
                                    trigger: UNCalendarNotificationTrigger(dateMatching: Cal.greg.dateComponents([.year, .month, .day, .hour, .minute], from: alle), repeats: false)))
    }
}

// le notifiche toccate: il riepilogo apre la sua pagina (le altre aprono solo l'app, come prima)
final class DelegatoNotifiche: NSObject, UNUserNotificationCenterDelegate {
    static let shared = DelegatoNotifiche()
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler fatto: @escaping () -> Void) {
        let apri = r.notification.request.content.userInfo["apri"] as? String
        Task { @MainActor in
            if apri == "riepilogo" { AppStore.shared.tabAperta = 3; AppStore.shared.mostraSettimana = true }
            fatto()
        }
    }
    // con l'app aperta le notifiche non compaiono (come prima)
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler fatto: @escaping (UNNotificationPresentationOptions) -> Void) {
        fatto([])
    }
}

struct RiepilogoSettimanaView: View {
    @EnvironmentObject var s: AppStore
    @Environment(\.dismiss) private var chiudi
    @State private var indietro = 0
    @State private var dettaglio: Workout?

    var body: some View {
        let w = s.datiSettimana(indietro)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Picker("Settimana", selection: $indietro) { Text("Questa").tag(0); Text("Scorsa").tag(1) }.pickerStyle(.segmented).frame(width: 170)
                    Spacer()
                    Button { chiudi() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 34, height: 34).background(Tema.scheda, in: Circle()) }
                        .foregroundStyle(Tema.testo).accessibilityLabel("Chiudi")
                }
                // in argento: allenamenti e volume
                VStack(alignment: .leading, spacing: 12) {
                    Text("SETTIMANA \(Cal.testo(w.lunedi, "d MMM").uppercased()) – \(Cal.testo(Cal.giorni(6, da: w.lunedi), "d MMM").uppercased())")
                        .font(.sport(17)).opacity(0.7)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(w.allenamenti.count)").font(.sport(76)).monospacedDigit()
                        Text("/ 4 allenamenti").font(.sport(24)).opacity(0.6)
                    }
                    .padding(.vertical, -8)
                    HStack(spacing: 0) {
                        cifra(fmtMigliaia(w.volume) + " kg", variazione(w.volume, w.volumePrima) ?? "volume")
                        cifra("\(w.serie)", "serie")
                        cifra("\(w.minuti)′", "in palestra")
                    }
                }
                .foregroundStyle(Tema.inchiostro)
                .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(Argento())

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    riquadro("trophy.fill", Tema.ambra, "\(w.record)", w.record == 1 ? "record" : "record")
                    riquadro("scalemass.fill", Tema.verde, w.pesoMedio.map { fmtPeso($0) } ?? "—",
                             w.pesoMedio.flatMap { p in w.pesoPrima.map { q in let d = p - q; return "peso medio (\(d > 0 ? "+" : d < 0 ? "−" : "±")\(fmtPeso(abs(d))))" } } ?? "peso medio")
                    riquadro("fork.knife", Tema.g, "\(w.giorniPiano)/\(w.giorniPassati)", "giorni con il piano")
                    riquadro("pills.fill", Color(hex: 0x9B7BFF), "\(w.creatina)/\(w.giorniPassati)", "creatina")
                }
                if w.fuoriPiano > 0 {
                    Text("\(w.fuoriPiano) \(w.fuoriPiano == 1 ? "pasto fuori piano" : "pasti fuori piano") questa settimana.").font(.system(size: 13)).foregroundStyle(Tema.tenue)
                }
                if !w.allenamenti.isEmpty {
                    Titolo(testo: "Allenamenti")
                    VStack(spacing: 0) {
                        ForEach(Array(w.allenamenti.enumerated()), id: \.element.id) { n, x in
                            Button { dettaglio = x } label: {
                                HStack {
                                    Text(maiuscolaIniziale(Cal.testo(Date(timeIntervalSince1970: x.start / 1000), "EEE d"))).font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.tenue).frame(width: 54, alignment: .leading)
                                    Text(x.name).font(.system(size: 16, weight: .bold)).foregroundStyle(Tema.testo)
                                    Spacer()
                                    Text("\(fmtMigliaia(x.volume)) kg").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.tenue)
                                    if !x.prs.isEmpty { Text("🏆 \(x.prs.count)").font(.system(size: 12, weight: .bold)) }
                                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Tema.tenue)
                                }
                                .padding(.vertical, 12).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if n < w.allenamenti.count - 1 { Rectangle().fill(Tema.linea).frame(height: 1) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding(20)
        }
        .background(Tema.fondo.ignoresSafeArea())
        .sheet(item: $dettaglio) { x in DettaglioAllenamento(w: x).foglio() }
    }

    private func variazione(_ ora: Double, _ prima: Double) -> String? {
        guard prima > 0, ora > 0 else { return nil }
        let p = (ora - prima) / prima * 100
        return "\(p >= 0 ? "▲" : "▼") \(Int(abs(p).rounded()))% sulla scorsa"
    }

    private func cifra(_ v: String, _ u: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.sport(24)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(u).font(.system(size: 11, weight: .semibold)).opacity(0.65).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func riquadro(_ icona: String, _ colore: Color, _ v: String, _ u: String) -> some View {
        Scheda(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icona).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30).background(colore, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(v).font(.sport(28)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(u).font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.tenue).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
}
