import SwiftUI
import WidgetKit

// Complicazione sul quadrante: kcal rimaste di oggi e prossimo pasto. Legge lo stato che l'app Watch salva
// nel gruppo condiviso a ogni aggiornamento dall'iPhone (e che poi le chiede di ridisegnarsi).
struct RecompEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot?
}

struct RecompProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecompEntry { RecompEntry(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (RecompEntry) -> Void) {
        completion(RecompEntry(date: Date(), snapshot: WatchShared.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RecompEntry>) -> Void) {
        // a mezzanotte lo stato di ieri non vale più: ricontrollo ogni ora
        completion(Timeline(entries: [RecompEntry(date: Date(), snapshot: WatchShared.load())], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct RecompComplication: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecompEntry

    var body: some View {
        let s = entry.snapshot.flatMap { $0.isToday ? $0 : nil }
        let left = s.map { "\($0.left)" } ?? "–"
        switch family {
        case .accessoryCircular:
            Gauge(value: s?.progress ?? 0) {
                Image(systemName: "fork.knife")
            } currentValueLabel: {
                Text(left).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Palette.lime)
        case .accessoryCorner:
            Image(systemName: "fork.knife")
                .font(.system(size: 20, weight: .semibold))
                .widgetLabel { Text("\(left) kcal") }
        case .accessoryInline:
            Text(s == nil ? "Recomp" : "\(left) kcal rimaste")
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text("\(left) KCAL RIMASTE").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.lime)
                if let m = s?.nextMeal {
                    Text("\(m.time) \(m.label)").font(.system(size: 13, weight: .semibold))
                    Text(m.name).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(s == nil ? "Apri Recomp sull'iPhone" : "Pasti di oggi segnati").font(.system(size: 13))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@main
struct RecompWatchWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecompOggi", provider: RecompProvider()) { entry in
            RecompComplication(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recomp")
        .description("Kcal rimaste e prossimo pasto")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}
