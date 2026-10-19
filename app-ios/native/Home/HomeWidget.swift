import SwiftUI
import WidgetKit

// Widget della schermata Home (colori di Recomp: argento su grafite).
// Legge lo stato di oggi che l'app salva nel gruppo condiviso (WatchBridgePlugin → UserDefaults del gruppo, chiave «snapshot»)
// e che l'app Watch usa per la complicazione: kcal rimaste, prossimo pasto, allenamento di oggi.
// Va dentro l'estensione RecompLive, insieme alla Live Activity: nessun nuovo identificativo da registrare.
struct HomeEntry: TimelineEntry {
    let date: Date
    let snap: WatchSnapshot?
}

struct HomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeEntry { HomeEntry(date: Date(), snap: nil) }
    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> Void) {
        completion(HomeEntry(date: Date(), snap: WatchShared.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) {
        // si aggiorna da solo ogni mezz'ora e ogni volta che l'app salva lo stato (reloadAllTimelines)
        completion(Timeline(entries: [HomeEntry(date: Date(), snap: WatchShared.load())], policy: .after(Date().addingTimeInterval(1800))))
    }
}

private let ds = (
    bg: Color(red: 0.051, green: 0.055, blue: 0.059),      // #0D0E0F
    card: Color(red: 0.086, green: 0.090, blue: 0.098),    // #161719
    orange: Color(red: 0.851, green: 0.859, blue: 0.855),  // argento
    green: Color(red: 0.310, green: 0.769, blue: 0.498),   // verde (fatto)
    ink: Color(red: 0.071, green: 0.071, blue: 0.078),     // testo scuro sull'argento
    text: Color(red: 0.945, green: 0.945, blue: 0.925),    // #F1F1EC
    muted: Color(red: 0.651, green: 0.651, blue: 0.624)    // #A6A69F
)
private func cond(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font { .system(size: size, weight: weight).width(.compressed) }

struct HomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HomeEntry

    var body: some View {
        Group {
            if let s = entry.snap, s.isToday {
                if family == .systemSmall { small(s) } else { medium(s) }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECOMP").font(cond(14)).padding(.horizontal, 6).padding(.vertical, 1).background(ds.text).foregroundStyle(ds.ink)
                    Text("APRI L'APP").font(cond(26)).foregroundStyle(ds.text)
                    Text("Il piano di oggi si aggiorna da lì.").font(.system(size: 12)).foregroundStyle(ds.muted)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .containerBackground(for: .widget) { ds.bg }
        .widgetURL(IndirizzoApp.url("oggi"))
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(cond(13, .bold)).tracking(1).padding(.horizontal, 6).padding(.vertical, 1)
            .background(ds.text).foregroundStyle(ds.ink)
    }

    private func small(_ s: WatchSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label("kcal rimaste")
            Text("\(s.left)").font(cond(52)).foregroundStyle(ds.text).minimumScaleFactor(0.6).lineLimit(1)
            ProgressView(value: s.progress).tint(ds.orange)
            Spacer(minLength: 0)
            if let m = s.nextMeal {
                Text("\(m.time) · \(m.label)".uppercased()).font(cond(15)).foregroundStyle(ds.orange).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text("PASTI FATTI").font(cond(15)).foregroundStyle(ds.green)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ s: WatchSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                label("kcal rimaste")
                Text("\(s.left)").font(cond(56)).foregroundStyle(ds.text).minimumScaleFactor(0.6).lineLimit(1)
                ProgressView(value: s.progress).tint(ds.orange)
                HStack(spacing: 8) {
                    macro("P", s.p, s.pTarget, Color(red: 0.97, green: 0.44, blue: 0.44))
                    macro("C", s.c, s.cTarget, Color(red: 0.98, green: 0.75, blue: 0.14))
                    macro("G", s.f, s.fTarget, Color(red: 0.38, green: 0.65, blue: 0.98))
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                if let m = s.nextMeal {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(m.time) · \(m.label)".uppercased()).font(cond(16)).foregroundStyle(ds.orange).lineLimit(1)
                        Text(m.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(ds.text).lineLimit(2)
                        Text("\(m.k) kcal").font(.system(size: 11)).foregroundStyle(ds.muted)
                    }
                } else {
                    Text("PASTI FATTI").font(cond(18)).foregroundStyle(ds.green)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: s.doneToday == true ? "checkmark.square.fill" : "dumbbell.fill").foregroundStyle(s.doneToday == true ? ds.green : ds.orange)
                    Text((s.todayPlan?.name ?? "Riposo").uppercased()).font(cond(18)).foregroundStyle(ds.text).lineLimit(1)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(Rectangle().stroke(ds.text, lineWidth: 1.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func macro(_ letter: String, _ v: Int, _ target: Int, _ color: Color) -> some View {
        (Text(letter + " ").font(cond(13, .bold)).foregroundColor(color) + Text("\(v)").font(cond(14)).foregroundColor(ds.text) + Text("/\(target)").font(.system(size: 9)).foregroundColor(ds.muted))
    }
}

struct RecompHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecompHome", provider: HomeProvider()) { entry in
            HomeWidgetView(entry: entry)
        }
        .configurationDisplayName("Recomp · oggi")
        .description("Kcal rimaste, prossimo pasto e allenamento di oggi.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
