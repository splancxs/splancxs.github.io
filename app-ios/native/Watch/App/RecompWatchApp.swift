import SwiftUI

// App per Apple Watch: tre pagine da scorrere con la corona.
// Allenamento (solo con un allenamento in corso sull'iPhone), Oggi (kcal, macro, creatina, prossimo pasto), Pasti.
@main
struct RecompWatchApp: App {
    @StateObject private var store = WatchStore()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(store) }
    }
}

struct RootView: View {
    @EnvironmentObject var store: WatchStore
    var body: some View {
        NavigationStack {
            if let s = store.snap, s.isToday {
                TabView {
                    if s.wo != nil { WorkoutPage(s: s) }
                    TodayPage(s: s)
                    MealsPage(s: s)
                }
                .tabViewStyle(.verticalPage)
            } else {
                WaitingView()
            }
        }
    }
}

// pulsante pieno lime con testo scuro, come nell'app
struct LimeButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Palette.lime.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
    }
}

struct WorkoutPage: View {
    @EnvironmentObject var store: WatchStore
    let s: WatchSnapshot
    var body: some View {
        // ogni secondo ricontrolla se il recupero è finito
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let w = s.wo ?? WatchWorkout(name: "")
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let rest = s.rest {
                        Text("RECUPERO").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.lime)
                        Text(timerInterval: Date()...rest, countsDown: true)
                            .font(.system(size: 44, weight: .heavy, design: .rounded)).monospacedDigit()
                        if let next = s.restNext {
                            Text(next).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(3)
                        }
                    } else if w.done == true {
                        Text("Tutte le serie fatte").font(.system(size: 18, weight: .bold))
                        Text("Termina l'allenamento dall'iPhone e fai il cardio.").font(.system(size: 14)).foregroundStyle(.secondary)
                    } else {
                        Text(w.ex ?? "").font(.system(size: 19, weight: .bold)).lineLimit(2).minimumScaleFactor(0.7)
                        Text("Serie \(w.set ?? 1) di \(w.of ?? 1)").font(.system(size: 14)).foregroundStyle(.secondary)
                        Text(w.target ?? "").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Palette.lime)
                            .minimumScaleFactor(0.6).lineLimit(1)
                        Button { store.setDone() } label: { Label("Fatto", systemImage: "checkmark") }
                            .buttonStyle(LimeButton())
                            .padding(.top, 4)
                        if let left = w.left { Text("\(left) serie in tutto ancora da fare").font(.system(size: 12)).foregroundStyle(.secondary) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(w.name)
        }
    }
}

struct TodayPage: View {
    @EnvironmentObject var store: WatchStore
    let s: WatchSnapshot
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 9)
                    Circle().trim(from: 0, to: s.progress)
                        .stroke(Palette.lime, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(s.left)").font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit()
                        Text("kcal rimaste").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 112, height: 112)
                HStack(spacing: 6) {
                    MacroPill(letter: "P", value: s.p, target: s.pTarget, color: Palette.p)
                    MacroPill(letter: "C", value: s.c, target: s.cTarget, color: Palette.c)
                    MacroPill(letter: "G", value: s.f, target: s.fTarget, color: Palette.f)
                }
                if let m = s.nextMeal {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(m.time) · \(m.label.uppercased())").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.lime)
                        Text(m.name).font(.system(size: 15, weight: .semibold)).lineLimit(3)
                        Text("\(m.k) kcal · P \(m.p)").font(.system(size: 13)).foregroundStyle(.secondary)
                        Button { store.eat(m) } label: { Label("Mangiato", systemImage: "checkmark") }
                            .buttonStyle(LimeButton())
                            .padding(.top, 2)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                } else {
                    Text("Pasti di oggi tutti segnati").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                }
                Button { store.creatine() } label: {
                    Label(s.crea ? "Creatina presa" : "Creatina 3–5 g", systemImage: s.crea ? "checkmark.circle.fill" : "pills")
                        .frame(maxWidth: .infinity)
                }
                .tint(s.crea ? Palette.lime : .gray)
                .disabled(s.crea)
            }
        }
        .navigationTitle("\(s.day) · \(s.type)")
    }
}

struct MacroPill: View {
    let letter: String
    let value: Int
    let target: Int
    let color: Color
    var body: some View {
        VStack(spacing: 1) {
            Text(letter).font(.system(size: 11, weight: .heavy)).foregroundStyle(color)
            Text("\(value)").font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
            Text("/\(target)").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct MealsPage: View {
    @EnvironmentObject var store: WatchStore
    let s: WatchSnapshot
    var body: some View {
        List(s.meals) { m in
            Button {
                store.eat(m)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: m.eaten ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(m.eaten ? Palette.lime : .secondary)
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(m.time) · \(m.label)").font(.system(size: 13, weight: .semibold))
                        Text(m.name).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 2)
                    Text("\(m.k)").font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
                }
                .opacity(m.eaten ? 0.6 : 1)
            }
            .disabled(m.eaten)
        }
        .navigationTitle("Pasti")
    }
}

struct WaitingView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.radiowaves.left.and.right").font(.system(size: 30)).foregroundStyle(Palette.lime)
            Text("Apri Recomp sull'iPhone").font(.system(size: 16, weight: .bold)).multilineTextAlignment(.center)
            Text("Il piano di oggi arriva da lì.").font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Recomp")
    }
}
