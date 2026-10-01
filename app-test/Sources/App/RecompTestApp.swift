import ActivityKit
import SwiftUI

// Mini app di prova: avvia, allunga e chiude una Live Activity di recupero finta.
@main
struct RecompTestApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var status = ""
    private let lime = Color(red: 0.77, green: 0.94, blue: 0.19)

    var body: some View {
        VStack(spacing: 18) {
            Text("Recomp Test").font(.largeTitle.bold())
            Text("Prova della Live Activity del recupero").foregroundColor(.secondary)
            Text(ActivityAuthorizationInfo().areActivitiesEnabled
                 ? "Live Activity consentite"
                 : "Live Activity disattivate: Impostazioni › Recomp Test › Live Activity")
                .font(.footnote.bold())
                .foregroundColor(ActivityAuthorizationInfo().areActivitiesEnabled ? .green : .red)
            Button("Avvia recupero di 90 secondi") { start(90) }
                .buttonStyle(.borderedProminent).tint(lime).foregroundColor(.black)
            HStack(spacing: 12) {
                Button("+15 s") { add(15) }.buttonStyle(.bordered)
                Button("−15 s") { add(-15) }.buttonStyle(.bordered)
                Button("Chiudi") { stop() }.buttonStyle(.bordered)
            }
            Text(status).font(.footnote).multilineTextAlignment(.center)
            Text("Dopo «Avvia» blocca il telefono: sulla schermata di blocco deve comparire il conto alla rovescia.")
                .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private func start(_ seconds: Double) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "Le Live Activity sono disattivate per questa app."
            return
        }
        let old = Activity<RestAttributes>.activities // solo quelle già aperte, non quella che sto per creare
        Task { for a in old { await a.end(nil, dismissalPolicy: .immediate) } }
        let state = RestAttributes.ContentState(end: Date().addingTimeInterval(seconds), next: "Leg Press · serie 2 · 118 kg × 8")
        do {
            let a = try Activity.request(attributes: RestAttributes(workout: "Limbs A"),
                                         content: ActivityContent(state: state, staleDate: state.end.addingTimeInterval(60)))
            status = "Live Activity avviata (\(a.id.prefix(8)))."
        } catch {
            status = "Errore: \(error.localizedDescription)"
        }
    }

    private func add(_ seconds: Double) {
        guard let a = Activity<RestAttributes>.activities.first else { status = "Nessuna Live Activity attiva."; return }
        Task {
            var state = a.content.state
            state.end = max(Date().addingTimeInterval(1), state.end.addingTimeInterval(seconds))
            await a.update(ActivityContent(state: state, staleDate: state.end.addingTimeInterval(60)))
            status = "Aggiornata: \(seconds > 0 ? "+" : "")\(Int(seconds)) s."
        }
    }

    private func stop() {
        Task {
            for a in Activity<RestAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
            status = "Chiusa."
        }
    }
}
