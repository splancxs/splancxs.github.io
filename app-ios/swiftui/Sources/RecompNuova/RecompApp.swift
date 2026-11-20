import SwiftUI
import UserNotifications

@main
struct RecompNuovaApp: App {
    @StateObject private var store = AppStore.shared
    @Environment(\.scenePhase) private var fase

    init() {
        WatchBridge.shared.avvia()
        UNUserNotificationCenter.current().delegate = DelegatoNotifiche.shared   // il riepilogo della domenica apre la sua pagina
        CodaIsola.eseguiDiretto = { tipo in
            await AppStore.shared.eseguiAzioneIsolaSubito(tipo)
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil,
            { _, _, _, _, _ in Task { @MainActor in await AppStore.shared.processaAzioniIsolaSubito() } },
            CodaIsola.notifica as CFString, nil, .deliverImmediately
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onOpenURL { url in store.apriIndirizzo(url) }
                // Live Activity dell'allenamento: segue ogni serie e ogni recupero; parte (o riparte) quando l'app torna davanti,
                // perché iOS non la fa partire con l'app in background
                .onChange(of: store.d.active) { _, _ in store.aggiornaRecuperoEsterno() }
                .onChange(of: fase) { _, f in
                    // uscendo dall'app: salvataggio, backup di oggi e i messaggi del coach di stasera e di domattina
                    if f == .background { store.salvaOra(); store.backupAutomatico(); store.preparaBigliettini() }
                    guard f == .active else { return }
                    store.processaAzioniIsola()
                    store.aggiornaRecuperoEsterno()
                    store.riprogrammaPromemoria()   // i promemoria dei prossimi 14 giorni restano sempre programmati
                }
                .task {
                    store.migraDalSito()
                    store.backupAutomatico()
                    store.riprogrammaPromemoria()
                    if store.d.salute { Salute.shared.importaPesi() }
                }
        }
    }
}

extension AppStore {
    // recomp://scheda?corrente=1 (Live Activity) · recomp://isola/... (pulsanti Dynamic Island) · recomp://oggi (widget della Home)
    func apriIndirizzo(_ url: URL) {
        switch url.host {
        case "oggi": tabAperta = 0
        case "scheda": tabAperta = 1
        case "isola":
            tabAperta = 1
            eseguiAzioneIsola(url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        case "piano": tabAperta = 2
        case "progressi": tabAperta = 3
        case "profilo": tabAperta = 4
        default: break
        }
    }
}

// La barra in basso è quella vera di iOS (TabView): con iOS 26 è il Liquid Glass, che rifrange la pagina. Non va mai disegnata a mano.
// Ordine come nell'app di prima: Oggi · Piano · Scheda · Progressi · Profilo. Chiaro e scuro seguono il telefono.
struct RootView: View {
    @EnvironmentObject var s: AppStore

    var body: some View {
        TabView(selection: $s.tabAperta) {
            Tab("Oggi", systemImage: "house", value: 0) { OggiView() }
            Tab("Piano", systemImage: "calendar", value: 2) { PianoView() }
            Tab("Scheda", systemImage: "dumbbell", value: 1) { AllenamentoView() }
                .badge(s.d.active != nil ? Text("•") : nil)   // un allenamento in corso si vede dalla barra
            Tab("Progressi", systemImage: "chart.line.uptrend.xyaxis", value: 3) { ProgressiView() }
            Tab("Profilo", systemImage: "person", value: 4) { ProfiloView() }
        }
        .tint(Tema.testo)
        .sheet(item: $s.mostraRiepilogo) { w in RiepilogoView(w: w).foglio() }
    }
}
