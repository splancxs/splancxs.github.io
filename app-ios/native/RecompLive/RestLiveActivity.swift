import ActivityKit
import SwiftUI
import WidgetKit

// Estensione che disegna la Live Activity del recupero: schermata di blocco (iPhone 14) e Dynamic Island (modelli Pro).
@main
struct RecompLiveWidgets: WidgetBundle {
    var body: some Widget { RestLiveActivity() }
}

private let lime = Color(red: 0.77, green: 0.94, blue: 0.19)

// intervallo sempre valido anche a recupero finito (un intervallo rovesciato chiuderebbe l'estensione)
private func span(_ end: Date) -> ClosedRange<Date> { min(Date(), end)...end }

struct RestLockScreen: View {
    let context: ActivityViewContext<RestAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(context.isStale ? "Recupero finito · \(context.attributes.workout)" : "Recupero · \(context.attributes.workout)")
                    .font(.caption.bold()).foregroundColor(lime)
                if context.isStale {
                    Text("Via!")
                        .font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundColor(.white)
                } else {
                    Text(timerInterval: span(context.state.end), countsDown: true)
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .monospacedDigit().foregroundColor(.white)
                }
                Text(context.state.next)
                    .font(.footnote).foregroundColor(.white.opacity(0.75)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: context.isStale ? "dumbbell.fill" : "timer")
                .font(.system(size: 30, weight: .semibold)).foregroundColor(lime)
        }
        .padding(16)
    }
}

struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestAttributes.self) { context in
            RestLockScreen(context: context)
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
                    Text(context.state.next).font(.caption).lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundColor(lime)
            } compactTrailing: {
                Text(timerInterval: span(context.state.end), countsDown: true)
                    .monospacedDigit().frame(width: 44)
            } minimal: {
                Image(systemName: "timer").foregroundColor(lime)
            }
        }
    }
}
