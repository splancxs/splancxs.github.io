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

private let lime = Color(red: 0.77, green: 0.94, blue: 0.19)

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

// iPhone: schermata di blocco
struct RestLockScreen: View {
    let context: ActivityViewContext<RestAttributes>

    var body: some View {
        let s = context.state
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(lime.opacity(0.18))
                    Image(systemName: context.isStale ? "checkmark" : "dumbbell.fill")
                        .font(.system(size: 18, weight: .bold)).foregroundColor(lime)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.isStale ? "Recupero finito · \(context.attributes.workout)" : "Recupero · \(context.attributes.workout)")
                        .font(.caption.weight(.semibold)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                    Text(s.exercise)
                        .font(.headline).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.75)
                    if !s.detail.isEmpty {
                        Text(s.detail).font(.subheadline.weight(.semibold)).foregroundColor(lime).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if context.isStale {
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
            if !context.isStale {
                ProgressView(timerInterval: progressSpan(s), countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                    .tint(lime)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

// Apple Watch: Smart Stack (spazio piccolo, si legge in un colpo d'occhio)
struct RestWatchView: View {
    let context: ActivityViewContext<RestAttributes>

    var body: some View {
        let s = context.state
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(context.isStale ? "Recupero finito" : "Recupero")
                    .font(.caption2.weight(.semibold)).foregroundColor(lime)
                if context.isStale {
                    Text("Via!").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundColor(.white)
                } else {
                    Text(timerInterval: span(s.end), countsDown: true)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .monospacedDigit().foregroundColor(.white)
                }
                Text(s.exercise).font(.caption2).foregroundColor(.white.opacity(0.7)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: context.isStale ? "checkmark.circle.fill" : "dumbbell.fill")
                .font(.system(size: 20, weight: .bold)).foregroundColor(lime)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestAttributes.self) { context in
            RestActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(lime)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.isStale ? "Via!" : "Recupero").font(.caption.bold()).foregroundColor(lime)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: span(context.state.end), countsDown: true)
                        .monospacedDigit().frame(width: 64)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.detail.isEmpty ? context.state.exercise : "\(context.state.exercise) · \(context.state.detail)")
                        .font(.caption).lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill").foregroundColor(lime)
            } compactTrailing: {
                Text(timerInterval: span(context.state.end), countsDown: true)
                    .monospacedDigit().frame(width: 44)
            } minimal: {
                Image(systemName: "timer").foregroundColor(lime)
            }
        }
        .supplementalActivityFamilies([.small]) // layout dedicato per lo Smart Stack dell'Apple Watch
    }
}
