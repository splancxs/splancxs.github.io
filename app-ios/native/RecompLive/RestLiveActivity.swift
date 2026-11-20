import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// Estensione che disegna la Live Activity del recupero:
// - schermata di blocco dell'iPhone (famiglia .medium);
// - Smart Stack dell'Apple Watch (famiglia .small, watchOS 11 o successivo);
// - Dynamic Island sui modelli che ce l'hanno.
@main
struct RecompLiveWidgets: WidgetBundle {
    var body: some Widget { RestLiveActivity(); RecompHomeWidget() }   // Live Activity e widget della schermata Home
}

private let lime = Color(red: 0.851, green: 0.859, blue: 0.855)       // accento dell'app: argento (prima era lime)
private let inchiostro = Color(red: 0.071, green: 0.071, blue: 0.078) // testo scuro sopra l'argento

// intervallo sempre valido anche a recupero finito (un intervallo rovesciato chiuderebbe l'estensione)
private func span(_ end: Date) -> ClosedRange<Date> { min(Date(), end)...end }
private func progressSpan(_ s: RestAttributes.ContentState) -> ClosedRange<Date> { min(s.start, s.end)...s.end }

// Sceglie il disegno in base a dove compare: Apple Watch o iPhone
struct RestActivityView: View {
    let context: ActivityViewContext<RestAttributes>
    @Environment(\.activityFamily) private var family

    var body: some View {
        switch family {
        case .small: RestWatchView(context: context)
        default: RestLockScreen(context: context)
        }
    }
}

// tra una serie e l'altra (mode «go») o quando il timer è arrivato a zero: mostra «Via!» con la serie da fare
private func traLeSerie(_ s: RestAttributes.ContentState) -> Bool { s.mode == "go" }
private func recuperoFinito(_ context: ActivityViewContext<RestAttributes>) -> Bool {
    let s = context.state
    return traLeSerie(s) || context.isStale || Date().addingTimeInterval(0.4) >= s.end
}
private func iconaStato(_ finito: Bool) -> String {
    finito ? "dumbbell.fill" : "timer"
}
private func conteggio(_ s: RestAttributes.ContentState) -> String? {
    guard let d = s.done, let t = s.total, t > 0 else { return nil }
    return "\(d)/\(t) serie"
}

// Pulsanti rapidi per la Dynamic Island espansa e la schermata di blocco:
// - durante il recupero: −15″ · +15″ · Salta
// - a recupero finito (Via!): ✓ Serie fatta
struct PulsantiIsola: View {
    let s: RestAttributes.ContentState
    let finito: Bool

    var body: some View {
        if !finito {
            HStack(spacing: 8) {
                Button(intent: Meno15RecuperoIntent()) {
                    Text("−15″")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                Button(intent: Piu15RecuperoIntent()) {
                    Text("+15″")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                Button(intent: SaltaRecuperoIntent()) {
                    Text("Salta")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(inchiostro)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(lime, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        } else if (s.total ?? 1) == 0 || (s.done ?? 0) < (s.total ?? 1) {
            Button(intent: SegnaSerieIsolaIntent()) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                    Text("Serie fatta")
                        .font(.system(size: 13, weight: .heavy))
                }
                .foregroundColor(inchiostro)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(lime, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

// iPhone: schermata di blocco
struct RestLockScreen: View {
    let context: ActivityViewContext<RestAttributes>

    var body: some View {
        let s = context.state
        let finito = recuperoFinito(context)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().fill(lime.opacity(0.18))
                    Image(systemName: iconaStato(finito))
                        .font(.system(size: 18, weight: .bold)).foregroundColor(lime)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text((finito ? "Prossima serie" : "Recupero") + " · \(context.attributes.workout)")
                        .font(.caption.weight(.semibold)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                    Text(s.exercise)
                        .font(.headline).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.75)
                    if !s.detail.isEmpty {
                        Text(s.detail).font(.subheadline.weight(.semibold)).foregroundColor(lime).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 8)
                if finito {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Via!")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundColor(lime)
                        if let c = conteggio(s) {
                            Text(c).font(.caption2.weight(.semibold)).foregroundColor(.white.opacity(0.6))
                        }
                    }
                } else {
                    Text(timerInterval: span(s.end), countsDown: true)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .monospacedDigit().foregroundColor(.white)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 96, alignment: .trailing)
                }
            }
            if !finito {
                ProgressView(timerInterval: progressSpan(s), countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                    .tint(lime)
            } else if let d = s.done, let t = s.total, t > 0 {
                ProgressView(value: Double(min(d, t)), total: Double(t)).tint(lime)
            } else {
                ProgressView(value: 1, total: 1).tint(lime)
            }
            PulsantiIsola(s: s, finito: finito)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

// Apple Watch: Smart Stack. Tre righe a tutta larghezza (etichetta con icona, timer o serie, esercizio):
// l'icona non ruba più spazio al nome dell'esercizio, che si rimpicciolisce invece di essere tagliato.
struct RestWatchView: View {
    let context: ActivityViewContext<RestAttributes>

    var body: some View {
        let s = context.state
        let finito = recuperoFinito(context)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: iconaStato(finito))
                    .font(.system(size: 11, weight: .bold))
                Text(finito ? "PROSSIMA SERIE" : "RECUPERO")
                    .font(.system(size: 12, weight: .bold)).tracking(0.6)
                Spacer(minLength: 0)
                if let c = conteggio(s) { Text(c).font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.6)) }
            }
            .foregroundColor(lime)
            Group {
                if finito {
                    Text(s.exercise).foregroundColor(.white).minimumScaleFactor(0.5)
                } else {
                    Text(timerInterval: span(s.end), countsDown: true).foregroundColor(.white)
                }
            }
            .font(.system(size: finito ? 20 : 27, weight: .heavy, design: .rounded))
            .monospacedDigit().lineLimit(1)
            Text(finito ? s.detail : s.exercise)
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.75))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestAttributes.self) { context in
            RestActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(lime)
                .widgetURL(IndirizzoApp.url("scheda?corrente=1")) // toccandola l'app si apre sulla Scheda, sull'esercizio che stai facendo
        } dynamicIsland: { context in
            let s = context.state
            let finito = recuperoFinito(context)
            return DynamicIsland {
                // In alto ai lati della fotocamera: stato con icona nel cerchietto a sinistra, nome scheda a destra.
                // Sotto la fotocamera (.bottom, a tutta larghezza): esercizio + serie, timer o «Via!», barra e pulsanti rapidi.
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().fill(lime.opacity(0.2))
                            Image(systemName: iconaStato(finito))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(lime)
                        }
                        .frame(width: 24, height: 24)
                        Text(finito ? "Prossima" : "Recupero")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.leading, 4)
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.workout)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.trailing, 6)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.exercise)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                if !s.detail.isEmpty {
                                    Text(s.detail)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(lime)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                            Spacer(minLength: 8)
                            if finito {
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text("Via!")
                                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                                        .foregroundColor(lime)
                                    if let c = conteggio(s) {
                                        Text(c)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                            } else {
                                Text(timerInterval: span(s.end), countsDown: true)
                                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 88, alignment: .trailing)
                            }
                        }
                        if !finito {
                            ProgressView(timerInterval: progressSpan(s), countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                                .tint(lime)
                        } else if let d = s.done, let t = s.total, t > 0 {
                            ProgressView(value: Double(min(d, t)), total: Double(t))
                                .tint(lime)
                        } else {
                            ProgressView(value: 1, total: 1)
                                .tint(lime)
                        }
                        PulsantiIsola(s: s, finito: finito)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                ZStack {
                    Circle().fill(lime.opacity(0.2))
                    Image(systemName: iconaStato(finito))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(lime)
                }
                .frame(width: 22, height: 22)
            } compactTrailing: {
                if finito {
                    Text("Via!")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(lime)
                } else {
                    Text(timerInterval: span(s.end), countsDown: true)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 38, alignment: .trailing)
                }
            } minimal: {
                ZStack {
                    Circle().fill(lime.opacity(0.2))
                    Image(systemName: iconaStato(finito))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(lime)
                }
                .frame(width: 22, height: 22)
            }
            .keylineTint(lime)
            .widgetURL(IndirizzoApp.url("scheda?corrente=1"))
        }
        .supplementalActivityFamilies([.small]) // layout dedicato per lo Smart Stack dell'Apple Watch
    }
}
