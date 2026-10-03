import SwiftUI

// App per Apple Watch, stile sportivo come l'app: scritte condensate maiuscole, numeri grandi, lime pieno con testo scuro.
// Pagine da scorrere con la corona: Allenamento (prima, se oggi c'è da allenarsi), Oggi, Pasti.
// Le schermate sono pensate per lo schermo più piccolo (Apple Watch SE da 40 mm).
@main
struct RecompWatchApp: App {
    @StateObject private var store = WatchStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(store.health)
                .environmentObject(store.counter)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: WatchStore
    // simulatore: «simctl launch … -recompPage pasti» apre una pagina, «-recompStart TB» avvia una scheda,
    // «-recompStop YES» chiude l'allenamento in corso senza salvarlo (argomenti di avvio)
    @State private var page = UserDefaults.standard.string(forKey: "recompPage") ?? ""
    var body: some View {
        NavigationStack {
            if let s = store.snap, s.isToday {
                let workoutFirst = store.session != nil || s.wo != nil || (s.todayPlan != nil && s.doneToday != true)
                TabView(selection: $page) {
                    if workoutFirst { WorkoutPage(s: s).tag("allenamento") }
                    TodayPage(s: s).tag("oggi")
                    MealsPage(s: s).tag("pasti")
                    if !workoutFirst { WorkoutPage(s: s).tag("allenamento") }
                }
                .tabViewStyle(.verticalPage)
                .onAppear {
                    if page.isEmpty { page = workoutFirst ? "allenamento" : "oggi" }
                    if UserDefaults.standard.bool(forKey: "recompStop"), store.session != nil { store.cancel() }
                    if store.session == nil, let rid = UserDefaults.standard.string(forKey: "recompStart"),
                       let p = s.plans?.first(where: { $0.rid == rid }) { store.start(p); page = "allenamento" }
                }
            } else if store.session != nil {
                SessionView()
            } else {
                WaitingView()
            }
        }
    }
}

// MARK: elementi comuni

// pulsante pieno lime con testo scuro, come nell'app
struct LimeButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sport(19))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(Palette.lime.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
    }
}

// riquadro scuro toccabile (schede, creatina)
struct CardButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(configuration.isPressed ? 0.18 : 0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct Tag: View {
    let text: String
    var color: Color = Palette.lime
    var body: some View { Text(text.uppercased()).font(.sport(14, .bold)).foregroundStyle(color).tracking(0.5) }
}

// nomi lunghi accorciati per lo schermo dell'orologio: «Panca inclinata 30° con manubri» → «Panca inclinata 30°»
func shortName(_ n: String) -> String {
    if n.count > 18, let r = n.range(of: " con ") { return String(n[..<r.lowerBound]) }
    return n
}

// sfondo della pagina: un velo di colore in alto che sfuma nel nero
func pageTint(_ color: Color, _ strength: Double = 0.3) -> LinearGradient {
    LinearGradient(colors: [color.opacity(strength), .black], startPoint: .top, endPoint: .center)
}

// battito e calorie dell'allenamento in Salute (se è attivo)
struct HeartLine: View {
    @EnvironmentObject var health: HealthWorkout
    var body: some View {
        if health.running {
            HStack(spacing: 3) {
                Image(systemName: "heart.fill").foregroundStyle(Palette.p)
                Text(health.heartRate.map(String.init) ?? "--").font(.sport(16)).monospacedDigit()
                if health.kcal > 0 { Text("· \(health.kcal) kcal").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            .font(.system(size: 12))
        }
    }
}

// MARK: serie (la stessa schermata per l'allenamento dal polso e per quello avviato sull'iPhone)

// Nome dell'esercizio, riquadri kg e ripetizioni (la corona cambia quello selezionato), FATTO.
// Le ripetizioni contate dal polso (prova) riempiono il riquadro finché non lo cambi a mano.
struct SetEditor: View {
    @EnvironmentObject var counter: RepCounter
    let key: String       // cambia a ogni nuova serie: riparto dai valori suggeriti
    let name: String
    let kg: Double?
    let reps: Int
    let unit: String
    let inc: Double
    let onDone: (Double?, Int) -> Void

    @State private var kgValue: Double = 0
    @State private var repsValue: Double = 0
    @State private var editingKg = true
    @State private var crown: Double = 0
    @State private var touched = false      // ripetizioni cambiate a mano: il conteggio non le sovrascrive più
    @FocusState private var crownFocus: Bool // la corona cambia i valori invece di scorrere le pagine

    private var sec: Bool { unit == "sec" }
    private var step: Double { inc > 0 ? inc : 2.5 }
    private var counted: Bool { !sec && !touched && counter.reps >= 3 }
    private var shownReps: Int { counted ? counter.reps : Int(repsValue) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shortName(name).uppercased()).font(.sport(22)).lineLimit(1).minimumScaleFactor(0.5)
            HStack(spacing: 6) {
                if !sec {
                    ValueBox(value: fmtKg(kgValue), unit: "kg", selected: editingKg) { editingKg = true; crown = kgValue }
                }
                ValueBox(value: "\(shownReps)", unit: sec ? "secondi" : counted ? "contate" : "ripetizioni",
                         selected: !editingKg || sec, accent: counted) {
                    if counted { repsValue = Double(counter.reps) }
                    editingKg = false
                    crown = repsValue
                }
            }
            .focusable(true)
            .focused($crownFocus)
            .digitalCrownRotation($crown, from: 0, through: editingKg && !sec ? 400 : 120, by: editingKg && !sec ? step : 1,
                                  sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
            .onChange(of: crown) { _, v in
                if editingKg && !sec {
                    kgValue = max(0, (v / step).rounded() * step)
                } else if v.rounded() != repsValue {
                    repsValue = max(1, v.rounded())
                    touched = true
                }
            }
            Button {
                counter.stop()
                onDone(sec ? nil : kgValue, shownReps)
            } label: { Label("FATTO", systemImage: "checkmark") }
                .buttonStyle(LimeButton())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: key) { load() }
        .onDisappear { counter.stop() }
    }

    private func load() {
        kgValue = kg ?? 0
        repsValue = Double(reps)
        editingKg = !sec && kg != nil
        crown = editingKg ? kgValue : repsValue
        touched = false
        crownFocus = true
        if !sec { counter.start() }
    }
}

struct ValueBox: View {
    let value: String
    let unit: String
    let selected: Bool
    var accent = false
    let tap: () -> Void
    var body: some View {
        VStack(spacing: -2) {
            Text(value).font(.sport(32)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(accent ? Palette.lime : .white)
            Text(unit).font(.system(size: 10, weight: .semibold)).foregroundStyle(selected || accent ? Palette.lime : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color.white.opacity(selected ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Palette.lime : .clear, lineWidth: 2))
        .onTapGesture(perform: tap)
    }
}

// conto alla rovescia del recupero, con la serie dopo
struct RestView: View {
    let end: Date
    let next: String?
    var onAdd: (() -> Void)?
    var onSkip: (() -> Void)?
    var body: some View {
        VStack(spacing: 3) {
            Text(timerInterval: Date()...end, countsDown: true)
                .font(.sport(54)).monospacedDigit()
            HeartLine()
            if let next {
                Text(next).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
            }
            if onAdd != nil || onSkip != nil {
                HStack(spacing: 8) {
                    if let onAdd { Button("+15″", action: onAdd) }
                    if let onSkip { Button("Salta", action: onSkip) }
                }
                .font(.sport(17))
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: allenamento

struct WorkoutPage: View {
    @EnvironmentObject var store: WatchStore
    let s: WatchSnapshot
    var body: some View {
        if store.session != nil {
            SessionView()
        } else if let w = s.wo {
            PhoneWorkoutView(s: s, w: w)
        } else {
            StartView(s: s)
        }
    }
}

// scelta della scheda: quella di oggi in grande, le altre sotto
struct StartView: View {
    @EnvironmentObject var store: WatchStore
    let s: WatchSnapshot
    var body: some View {
        let plans = s.plans ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let p = s.todayPlan {
                    Tag(text: s.doneToday == true ? "Fatto oggi ✓" : "Oggi")
                    Text(p.name.uppercased()).font(.sport(36)).lineLimit(1).minimumScaleFactor(0.6)
                    Text("\(p.items.count) esercizi · \(p.setCount) serie").font(.system(size: 13)).foregroundStyle(.secondary)
                    Button { store.start(p) } label: { Label("INIZIA", systemImage: "play.fill") }
                        .buttonStyle(LimeButton())
                        .padding(.top, 2)
                } else {
                    Tag(text: "Oggi")
                    Text("RIPOSO").font(.sport(36))
                    Text("Se vuoi allenarti lo stesso, scegli una scheda.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                let others = plans.filter { $0.rid != s.todayPlan?.rid }
                if !others.isEmpty {
                    Tag(text: "Altre schede", color: .secondary).padding(.top, 8)
                    ForEach(others) { p in
                        Button { store.start(p) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(p.name.uppercased()).font(.sport(19))
                                    Text(p.day.isEmpty ? "\(p.setCount) serie" : p.day).font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "play.circle.fill").font(.system(size: 22)).foregroundStyle(Palette.lime)
                            }
                        }
                        .buttonStyle(CardButton())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Allenamento")
        .containerBackground(pageTint(Palette.lime), for: .tabView)
    }
}

// allenamento in corso sull'orologio: serie da fare, recupero, fine
struct SessionView: View {
    @EnvironmentObject var store: WatchStore
    @State private var showList = false
    @State private var askEnd = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            if let s = store.session {
                if let end = s.restEnd, end > ctx.date {
                    RestView(end: end, next: s.restNext, onAdd: { store.addRest(15) }, onSkip: { store.skipRest() })
                } else if let c = s.current {
                    let it = s.items[c[0]], set = it.sets[c[1]]
                    SetEditor(key: "\(c[0])-\(c[1])", name: it.n, kg: set.kg, reps: set.r, unit: it.unit, inc: it.inc) { kg, reps in
                        store.complete(kg: kg, reps: reps)
                    }
                } else {
                    done(s)
                }
            }
        }
        .navigationTitle(title)
        .containerBackground(pageTint(Palette.lime, store.session?.restEnd != nil ? 0.55 : 0.3), for: .tabView)
        .containerBackground(pageTint(Palette.lime, store.session?.restEnd != nil ? 0.55 : 0.3), for: .navigation)
        .toolbar {
            if store.session?.current != nil {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { showList = true } label: { Image(systemName: "list.bullet") }
                    Spacer()
                    HeartLine()
                    Spacer()
                    Button { askEnd = true } label: { Image(systemName: "flag.checkered") }
                }
            }
        }
        .sheet(isPresented: $showList) { ExerciseList() }
        .confirmationDialog("Terminare l'allenamento?", isPresented: $askEnd, titleVisibility: .visible) {
            Button("Salva e termina") { store.finish() }
            Button("Annulla senza salvare", role: .destructive) { store.cancel() }
        }
    }

    // titolo in alto: serie o recupero (lo schermo del SE 40 mm è basso: niente riga in più nella pagina)
    private var title: String {
        guard let s = store.session else { return "" }
        if let end = s.restEnd, end > Date() { return "Recupero" }
        if let c = s.current { return "Serie \(c[1] + 1)/\(s.items[c[0]].sets.count)" }
        return s.name
    }

    private func done(_ s: WorkoutSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("FINITO!").font(.sport(40)).foregroundStyle(Palette.lime)
                Text("\(s.done) serie · \(fmtKg(s.volume)) kg di volume").font(.system(size: 14, weight: .semibold))
                Text("\(max(1, Int(Date().timeIntervalSince(s.start) / 60))) minuti. Ora il cardio!").font(.system(size: 13)).foregroundStyle(.secondary)
                HeartLine()
                Button { store.finish() } label: { Label("SALVA", systemImage: "square.and.arrow.down") }
                    .buttonStyle(LimeButton())
                    .padding(.top, 4)
                Text("Va nella cronologia dell'iPhone e in Salute, anche se ora il telefono è lontano.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

struct ExerciseList: View {
    @EnvironmentObject var store: WatchStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let items = store.session?.items ?? []
        List(Array(items.enumerated()), id: \.offset) { pair in
            let i = pair.offset, it = pair.element
            let done = it.sets.filter(\.done).count
            Button {
                store.focus(i)
                dismiss()
            } label: {
                HStack {
                    Text(shortName(it.n)).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                    Spacer(minLength: 4)
                    Text("\(done)/\(it.sets.count)").font(.sport(17)).foregroundStyle(done == it.sets.count ? Palette.lime : .secondary)
                }
            }
            .disabled(done == it.sets.count)
        }
        .navigationTitle("Esercizi")
    }
}

// allenamento avviato sull'iPhone: stessa schermata, i dati arrivano dal telefono (serve l'app del telefono aperta)
struct PhoneWorkoutView: View {
    @EnvironmentObject var store: WatchStore
    let s: WatchSnapshot
    let w: WatchWorkout
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let rest = s.rest {
                RestView(end: rest, next: s.restNext)
            } else if w.done == true {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TUTTE LE SERIE FATTE").font(.sport(24))
                    Text("Termina l'allenamento dall'iPhone e fai il cardio.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                SetEditor(key: "\(w.i ?? 0)-\(w.j ?? 0)", name: w.ex ?? "", kg: w.kg, reps: w.r ?? 8,
                          unit: w.unit ?? "reps", inc: w.inc ?? 2.5) { kg, reps in
                    store.phoneSetDone(kg: kg, reps: reps)
                }
            }
        }
        .navigationTitle(s.rest != nil ? "Recupero" : w.done == true ? w.name : "Serie \(w.set ?? 1)/\(w.of ?? 1)")
        .containerBackground(pageTint(Palette.lime, s.rest != nil ? 0.55 : 0.3), for: .tabView)
    }
}

// MARK: oggi

struct TodayPage: View {
    @EnvironmentObject var store: WatchStore
    let s: WatchSnapshot
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 11)
                    Circle().trim(from: 0, to: s.progress)
                        .stroke(Palette.lime, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: -2) {
                        Text("\(s.left)").font(.sport(42)).monospacedDigit()
                        Text("KCAL RIMASTE").font(.sport(12, .bold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 124, height: 124)
                VStack(spacing: 6) {
                    MacroBar(name: "Proteine", value: s.p, target: s.pTarget, color: Palette.p)
                    MacroBar(name: "Carboidrati", value: s.c, target: s.cTarget, color: Palette.c)
                    MacroBar(name: "Grassi", value: s.f, target: s.fTarget, color: Palette.f)
                }
                if let m = s.nextMeal {
                    VStack(alignment: .leading, spacing: 3) {
                        Tag(text: "\(m.time) · \(m.label)")
                        Text(m.name).font(.system(size: 15, weight: .semibold)).lineLimit(3)
                        Text("\(m.k) kcal · P \(m.p) g").font(.system(size: 13)).foregroundStyle(.secondary)
                        Button { store.eat(m) } label: { Label("MANGIATO", systemImage: "checkmark") }
                            .buttonStyle(LimeButton())
                            .padding(.top, 3)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                } else {
                    Text("PASTI DI OGGI TUTTI SEGNATI").font(.sport(16)).foregroundStyle(Palette.lime)
                }
                Button { store.creatine() } label: {
                    HStack {
                        Image(systemName: s.crea ? "checkmark.circle.fill" : "pills.fill").foregroundStyle(s.crea ? Palette.lime : .white)
                        Text(s.crea ? "CREATINA PRESA" : "CREATINA 3–5 G").font(.sport(17))
                        Spacer()
                    }
                }
                .buttonStyle(CardButton())
                .disabled(s.crea)
            }
        }
        .navigationTitle("\(s.day) · \(s.type)")
        .containerBackground(pageTint(Palette.lime, 0.18), for: .tabView)
    }
}

struct MacroBar: View {
    let name: String
    let value: Int
    let target: Int
    let color: Color
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(name.uppercased()).font(.sport(13, .bold)).foregroundStyle(color)
                Spacer()
                Text("\(value)").font(.sport(15)).monospacedDigit() + Text(" / \(target) g").font(.system(size: 11)).foregroundColor(.secondary)
            }
            ProgressView(value: target > 0 ? min(1, Double(value) / Double(target)) : 0)
                .tint(color)
        }
    }
}

// MARK: pasti

struct MealsPage: View {
    @EnvironmentObject var store: WatchStore
    let s: WatchSnapshot
    var body: some View {
        List(s.meals) { m in
            // schermo piccolo (SE 40 mm): ora e kcal sulla prima riga, il nome del pasto da solo, poi il piatto
            Button {
                store.eat(m)
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: m.eaten ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(m.eaten ? Palette.lime : .secondary)
                        .font(.system(size: 17))
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(m.time).font(.sport(15)).foregroundStyle(m.eaten ? .secondary : Palette.lime)
                            Spacer(minLength: 2)
                            Text("\(m.k)").font(.sport(15)).monospacedDigit() + Text(" kcal").font(.system(size: 10)).foregroundColor(.secondary)
                        }
                        Text(m.label.uppercased()).font(.sport(18)).lineLimit(1).minimumScaleFactor(0.6)
                        Text(m.name).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .opacity(m.eaten ? 0.6 : 1)
            }
        }
        .navigationTitle("Pasti")
        .containerBackground(pageTint(Palette.lime, 0.12), for: .tabView)
    }
}

struct WaitingView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Image(systemName: "iphone.radiowaves.left.and.right").font(.system(size: 28)).foregroundStyle(Palette.lime)
                Text("APRI RECOMP SULL'IPHONE").font(.sport(20)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Il piano di oggi arriva da lì.").font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Recomp")
    }
}
