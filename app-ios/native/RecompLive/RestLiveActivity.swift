import ActivityKit
import SwiftUI
import WidgetKit

// Estensione che disegna la Live Activity del recupero:
// - schermata di blocco dell'iPhone (famiglia .medium);
// - Smart Stack dell'Apple Watch (famiglia .small, watchOS 11 o successivo);
// - Dynamic Island sui modelli che ce l'hanno.
@main
struct RecompLiveWidgets: WidgetBundle {
    var body: some Widget { RestLiveActivity() }
}

private let lime = Color(red: 0.851, green: 0.859, blue: 0.855)   // accento dell'app: argento (prima era lime)

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

// tra una serie e l'altra (mode «go»): niente conto alla rovescia, la prossima serie e quante ne hai fatte
private func traLeSerie(_ s: RestAttributes.ContentState) -> Bool { s.mode == "go" }
private func conteggio(_ s: RestAttributes.ContentState) -> String? {
    guard let d = s.done, let t = s.total, t > 0 else { return nil }
    return "\(d)/\(t) serie"
}

// iPhone: schermata di blocco
struct RestLockScreen: View {
    let context: ActivityViewContext<RestAttributes>

    var body: some View {
        let s = context.state
        let go = traLeSerie(s)
        let finito = go || context.isStale
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(lime.opacity(0.18))
                    Image(systemName: go ? "dumbbell.fill" : context.isStale ? "checkmark" : "timer")
                        .font(.system(size: 18, weight: .bold)).foregroundColor(lime)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text((go ? "Prossima serie" : context.isStale ? "Recupero finito" : "Recupero") + " · \(context.attributes.workout)")
                        .font(.caption.weight(.semibold)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                    Text(s.exercise)
                        .font(.headline).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.75)
                    if !s.detail.isEmpty {
                        Text(s.detail).font(.subheadline.weight(.semibold)).foregroundColor(lime).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 8)
                if go {
                    VStack(alignment: .trailing, spacing: -2) {
                        Text("\(s.done ?? 0)").font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit().foregroundColor(.white)
                        Text("di \(s.total ?? 0) serie").font(.caption2.weight(.semibold)).foregroundColor(.white.opacity(0.6))
                    }
                } else if context.isStale {
                    Text("Via!")
                        .font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundColor(lime)
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
            }
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
        let go = traLeSerie(s)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: go ? "dumbbell.fill" : context.isStale ? "checkmark" : "timer")
                    .font(.system(size: 11, weight: .bold))
                Text(go ? "PROSSIMA SERIE" : context.isStale ? "RECUPERO FINITO" : "RECUPERO")
                    .font(.system(size: 12, weight: .bold)).tracking(0.6)
                Spacer(minLength: 0)
                if let c = conteggio(s) { Text(c).font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.6)) }
            }
            .foregroundColor(lime)
            Group {
                if go {
                    Text(s.exercise).foregroundColor(.white).minimumScaleFactor(0.5)
                } else if context.isStale {
                    Text("Via!").foregroundColor(lime)
                } else {
                    Text(timerInterval: span(s.end), countsDown: true).foregroundColor(.white)
                }
            }
            .font(.system(size: go ? 20 : 27, weight: .heavy, design: .rounded))
            .monospacedDigit().lineLimit(1)
            Text(go ? s.detail : s.exercise)
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
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(traLeSerie(context.state) ? "Prossima" : context.isStale ? "Via!" : "Recupero").font(.caption.bold()).foregroundColor(lime)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if traLeSerie(context.state) {
                        Text("\(context.state.done ?? 0)/\(context.state.total ?? 0)").monospacedDigit()
                    } else {
                        Text(timerInterval: span(context.state.end), countsDown: true)
                            .monospacedDigit().frame(width: 64)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.detail.isEmpty ? context.state.exercise : "\(context.state.exercise) · \(context.state.detail)")
                        .font(.caption).lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill").foregroundColor(lime)
            } compactTrailing: {
                if traLeSerie(context.state) {
                    Text("\(context.state.done ?? 0)/\(context.state.total ?? 0)").monospacedDigit()
                } else {
                    Text(timerInterval: span(context.state.end), countsDown: true)
                        .monospacedDigit().frame(width: 44)
                }
            } minimal: {
                Image(systemName: "timer").foregroundColor(lime)
            }
            .widgetURL(IndirizzoApp.url("scheda?corrente=1"))
        }
        .supplementalActivityFamilies([.small]) // layout dedicato per lo Smart Stack dell'Apple Watch
    }
}
