import SwiftUI
import UserNotifications

@main
struct RecompNuovaApp: App {
    @StateObject private var store = AppStore.shared
    @Environment(\.scenePhase) private var fase

    init() {
        WatchBridge.shared.avvia()
        UNUserNotificationCenter.current().delegate = DelegatoNotifiche.shared   // il riepilogo della domenica apre la sua pagina
        CodaIsola.eseguiDiretto = { tipo, fine in
            await AppStore.shared.eseguiAzioneIsolaSubito(tipo, fine: fine)
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
                    Registro.evento(f == .active ? "app davanti" : f == .background ? "app in background" : "app inattiva")
                    // uscendo dall'app: salvataggio, backup di oggi e i messaggi del coach di stasera e di domattina
                    if f == .background { store.salvaOra(); store.backupAutomatico(); store.preparaBigliettini() }
                    guard f == .active else { return }
                    store.processaAzioniIsola()
                    store.aggiornaRecuperoEsterno()
                    store.riprogrammaPromemoria()   // i promemoria dei prossimi 14 giorni restano sempre programmati
                }
                .task {
                    Registro.evento("avvio · piano \(store.piano.version)")
                    // debug dal PC: «debug.ps1 apri pasto:3» lancia l'app con RECOMP_APRI
                    let env = ProcessInfo.processInfo.environment
                    if let az = env["RECOMP_AZIONI"], !az.isEmpty { store.eseguiAzioniProva(az) }
                    if let a = env["RECOMP_APRI"], !a.isEmpty {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        store.apriPerDebug(a)
                    }
                    // modalità prova: il tempo per finestre e scorrimento, poi lo stato in testo e il segnale «pronto»
                    // (finestre una dentro l'altra o scorrimento: 1,7 s; una pagina semplice: 0,5 s)
                    if AppStore.inProva {
                        let a = env["RECOMP_APRI"] ?? "oggi"
                        let lento = a.contains(":") || ["coach", "settimana", "fuori"].contains(a) || !(env["RECOMP_SCORRI"] ?? "").isEmpty
                            || (env["RECOMP_AZIONI"] ?? "").contains("finisci")
                        try? await Task.sleep(nanoseconds: lento ? 1_700_000_000 : 500_000_000)
                        store.statoPerDebug(a)
                    }
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
        // modalità prova (debug dal PC): ben visibile, così non si scambia per l'app vera
        .overlay(alignment: .top) {
            if AppStore.inProva {
                Text("MODALITÀ PROVA · copia dei dati").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2).background(Tema.rosso, in: Capsule())
                    .allowsHitTesting(false)
            }
        }
    }
}
