import SwiftUI
import UserNotifications
import WatchKit

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
        }
    }
}

// Una pagina «Oggi» che dice tutto (kcal, macro, prossimo pasto, allenamento); da lì si entra nei Pasti e nelle schede.
// L'allenamento in corso (sull'orologio o avviato sull'iPhone) prende tutto lo schermo finché non finisce.
struct RootView: View {
    @EnvironmentObject var store: WatchStore
    var body: some View {
        NavigationStack {
            if store.session != nil {
                SessionView()
            } else if let s = store.snap, s.isToday {
                if let w = s.wo { PhoneWorkoutView(s: s, w: w) } else { TodayHome(s: s) }
            } else {
                WaitingView()
            }
        }
    }
}

extension View {
    // sfondo della pagina: vale sia dentro una navigazione sia in una vista a pagine
    func pageBackground(_ color: Color = Palette.lime, _ strength: Double = 0.3) -> some View {
        self.containerBackground(pageTint(color, strength), for: .tabView)
            .containerBackground(pageTint(color, strength), for: .navigation)
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
    var body: some View { Text(text.uppercased()).font(.sport(14, .bold)).foregroundStyle(color).tracking(0.5).lineLimit(1).minimumScaleFactor(0.6) }
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
struct SetEditor: View {
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
    @FocusState private var crownFocus: Bool // la corona cambia i valori invece di scorrere le pagine

    private var sec: Bool { unit == "sec" }
    private var step: Double { inc > 0 ? inc : 2.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shortName(name).uppercased()).font(.sport(22)).lineLimit(1).minimumScaleFactor(0.5)
            HStack(spacing: 6) {
                if !sec {
                    ValueBox(value: fmtKg(kgValue), unit: "kg", selected: editingKg) { editingKg = true; crown = kgValue }
                }
                ValueBox(value: "\(Int(repsValue))", unit: sec ? "secondi" : "ripetizioni", selected: !editingKg || sec) {
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
                }
            }
            Button {
                onDone(sec ? nil : kgValue, Int(repsValue))
            } label: { Label("FATTO", systemImage: "checkmark") }
                .buttonStyle(LimeButton())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .task(id: key) { load() }
    }

    private func load() {
        kgValue = kg ?? 0
        repsValue = Double(reps)
        editingKg = !sec && kg != nil
        crown = editingKg ? kgValue : repsValue
        crownFocus = true
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
    var onLess: (() -> Void)?   // −15″: accorcia il recupero
    var onSkip: (() -> Void)?
    var body: some View {
        // lo schermo del SE 40 mm è basso: timer, serie dopo, due pulsanti e battito devono stare tutti senza scorrere
        VStack(spacing: 5) {
            Text(timerInterval: Date()...end, countsDown: true)
                .font(.sport(48)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            if let next {
                Text(next).font(.system(size: 12, weight: .medium)).multilineTextAlignment(.center).lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            if onLess != nil || onSkip != nil {
                HStack(spacing: 6) {
                    if let onLess { Button("−15″", action: onLess).buttonStyle(PillButton(filled: false)) }
                    if let onSkip { Button("SALTA", action: onSkip).buttonStyle(PillButton(filled: true)) }
                }
            }
            HeartLine()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }
}

// pulsante a pillola: pieno lime (azione principale) o grigio scuro (secondaria)
struct PillButton: ButtonStyle {
    let filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sport(17))
            .foregroundStyle(filled ? Palette.ink : .white)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(filled ? Palette.lime.opacity(configuration.isPressed ? 0.7 : 1) : Color.white.opacity(configuration.isPressed ? 0.25 : 0.14), in: Capsule())
    }
}

// MARK: allenamento

// scelta della scheda: quella di oggi in grande, le altre sotto
struct StartView: View {
    @EnvironmentObject var store: WatchStore
    @Environment(\.dismiss) private var dismiss
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
            .padding(.horizontal, 6)   // le scritte non devono toccare il bordo curvo dello schermo
        }
        .navigationTitle("Allenamento")
        .pageBackground()
        // quando parte l'allenamento torno alla pagina principale, che si trasforma nella schermata della serie
        .onChange(of: store.session != nil) { _, started in if started { dismiss() } }
    }
}

// allenamento in corso sull'orologio: serie da fare, recupero, fine
struct SessionView: View {
    @EnvironmentObject var store: WatchStore
    @State private var showList = false
    @State private var askEnd = false

    // due pagine, si scorre di lato: la serie (o il recupero) e il riepilogo con la fine dell'allenamento
    var body: some View {
        TabView {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                if let s = store.session {
                    if let end = s.restEnd, end > ctx.date {
                        RestView(end: end, next: s.restNext, onLess: { store.addRest(-15) }, onSkip: { store.skipRest() })
                    } else if let c = s.current {
                        let it = s.items[c[0]], set = it.sets[c[1]]
                        VStack(spacing: 6) {
                            SetEditor(key: "\(c[0])-\(c[1])", name: it.n, kg: set.kg, reps: set.r, unit: it.unit, inc: it.inc) { kg, reps in
                                store.complete(kg: kg, reps: reps)
                            }
                            HeartLine()
                        }
                    } else {
                        done(s)
                    }
                }
            }
            .navigationTitle(title)
            .pageBackground(Palette.lime, store.session?.restEnd != nil ? 0.55 : 0.3)

            if let s = store.session {
                summary(s)
                    .navigationTitle("Riepilogo")
                    .pageBackground(Palette.lime, 0.2)
            }
        }
        .tabViewStyle(.page)
        .sheet(isPresented: $showList) { ExerciseList() }
        .confirmationDialog("Terminare l'allenamento?", isPresented: $askEnd, titleVisibility: .visible) {
            Button("Salva e termina") { store.finish() }
            Button("Annulla senza salvare", role: .destructive) { store.cancel() }
        }
    }

    // pagina 2: a che serie sono, da quanto mi alleno, battito e calorie; da qui si vede la lista e si termina
    private func summary(_ s: WorkoutSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Tag(text: "Tempo")
                    Spacer(minLength: 0)
                    Text(timerInterval: s.start...Date.distantFuture, countsDown: false, showsHours: false)
                        .font(.sport(30)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Tag(text: "Serie")
                    Spacer(minLength: 0)
                    Text("\(s.done)").font(.sport(30)).monospacedDigit() + Text("/\(s.total)").font(.system(size: 14)).foregroundColor(.secondary)
                }
                ProgressView(value: s.total > 0 ? Double(s.done) / Double(s.total) : 0).tint(Palette.lime)
                HeartLine()
                Button { showList = true } label: {
                    HStack { Image(systemName: "list.bullet").foregroundStyle(Palette.lime); Text("ESERCIZI").font(.sport(17)); Spacer() }
                }
                .buttonStyle(CardButton())
                .padding(.top, 2)
                Button { askEnd = true } label: {
                    HStack { Image(systemName: "flag.checkered").foregroundStyle(Palette.lime); Text("TERMINA").font(.sport(17)); Spacer() }
                }
                .buttonStyle(CardButton())
            }
            .padding(.horizontal, 6)
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
            .padding(.horizontal, 6)
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
                .padding(.horizontal, 6)
            } else {
                SetEditor(key: "\(w.i ?? 0)-\(w.j ?? 0)", name: w.ex ?? "", kg: w.kg, reps: w.r ?? 8,
                          unit: w.unit ?? "reps", inc: w.inc ?? 2.5) { kg, reps in
                    store.phoneSetDone(kg: kg, reps: reps)
                }
            }
        }
        .navigationTitle(s.rest != nil ? "Recupero" : w.done == true ? w.name : "Serie \(w.set ?? 1)/\(w.of ?? 1)")
        .pageBackground(Palette.lime, s.rest != nil ? 0.55 : 0.3)
    }
}

// MARK: oggi

// Un solo schermo che dice tutto: kcal rimaste e macro in alto, poi il prossimo pasto con «Mangiato»,
// l'allenamento di oggi, i pasti e la creatina. Pensato per il SE da 40 mm: niente righe sprecate.
struct TodayHome: View {
    @EnvironmentObject var store: WatchStore
    let s: WatchSnapshot

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.12), lineWidth: 7)
                        Circle().trim(from: 0, to: s.progress)
                            .stroke(Palette.lime, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: -4) {
                            Text("\(s.left)").font(.sport(22)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                            Text("KCAL").font(.sport(9, .bold)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 64, height: 64)
                    VStack(spacing: 5) {
                        MacroRow(letter: "P", value: s.p, target: s.pTarget, color: Palette.p)
                        MacroRow(letter: "C", value: s.c, target: s.cTarget, color: Palette.c)
                        MacroRow(letter: "G", value: s.f, target: s.fTarget, color: Palette.f)
                    }
                }
                nextMeal
                Button { store.creatine() } label: {
                    HStack {
                        Image(systemName: s.crea ? "checkmark.circle.fill" : "pills.fill").foregroundStyle(s.crea ? Palette.lime : .white)
                        Text(s.crea ? "CREATINA PRESA" : "CREATINA 3–5 G").font(.sport(17))
                        Spacer()
                    }
                }
                .buttonStyle(CardButton())
                NavigationLink { MealsPage(s: s) } label: {
                    HStack {
                        Image(systemName: "fork.knife").foregroundStyle(Palette.lime)
                        Text("PASTI").font(.sport(17))
                        Spacer(minLength: 4)
                        Text("\(s.meals.filter(\.eaten).count)/\(s.meals.count)").font(.sport(17)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(CardButton())
                workoutCard

            }
            .padding(.horizontal, 6)   // l'anello e i riquadri non devono toccare il bordo curvo dello schermo
        }
        .pageBackground(Palette.lime, 0.18)   // niente titolo: lo schermo del SE da 40 mm è basso
    }

    @ViewBuilder private var nextMeal: some View {
        if let m = s.nextMeal {
            VStack(alignment: .leading, spacing: 3) {
                Tag(text: "\(m.time) · \(m.label)")
                Text(m.name).font(.system(size: 14, weight: .semibold)).lineLimit(3)
                Text("\(m.k) kcal · P \(m.p) g").font(.system(size: 12)).foregroundStyle(.secondary)
                Button { store.eat(m) } label: { Label("MANGIATO", systemImage: "checkmark") }
                    .buttonStyle(LimeButton())
                    .padding(.top, 2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        } else {
            Text("PASTI DI OGGI TUTTI SEGNATI").font(.sport(16)).foregroundStyle(Palette.lime).multilineTextAlignment(.center)
        }
    }

    private var workoutCard: some View {
        NavigationLink { StartView(s: s) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Tag(text: s.doneToday == true ? "Allenamento fatto" : "Allenamento")
                    Text(s.todayPlan?.name.uppercased() ?? "RIPOSO").font(.sport(22)).lineLimit(1).minimumScaleFactor(0.6)
                    if let p = s.todayPlan {
                        Text("\(p.items.count) esercizi · \(p.setCount) serie").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: s.doneToday == true ? "checkmark.circle.fill" : s.todayPlan == nil ? "chevron.right" : "play.circle.fill")
                    .font(.system(size: 26)).foregroundStyle(Palette.lime)
            }
        }
        .buttonStyle(CardButton())
    }
}

// una riga di macro: lettera, quanto fatto su quanto, barra
struct MacroRow: View {
    let letter: String
    let value: Int
    let target: Int
    let color: Color
    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 2) {
                Text(letter).font(.sport(12, .bold)).foregroundStyle(color)
                Spacer(minLength: 0)
                Text("\(value)").font(.sport(13)).monospacedDigit() + Text("/\(target)").font(.system(size: 10)).foregroundColor(.secondary)
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
        // si legge lo stato aggiornato (non la copia passata): dopo «Mangiato» o un cambio piatto l'elenco si aggiorna da solo
        let meals = store.snap?.meals ?? s.meals
        List(meals) { m in
            // schermo piccolo (SE 40 mm): ora e kcal sulla prima riga, il nome del pasto da solo, poi il piatto per intero
            NavigationLink {
                MealDetail(si: m.si)
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
                        Text(m.name).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .opacity(m.eaten ? 0.6 : 1)
            }
        }
        .navigationTitle("Pasti")
        .pageBackground(Palette.lime, 0.12)
    }
}

// dettaglio di un pasto: quanto pesare di ogni ingrediente, i numeri, «Mangiato» o «Annulla», e il cambio piatto
struct MealDetail: View {
    @EnvironmentObject var store: WatchStore
    let si: Int
    private var meal: WatchMeal? { store.snap?.meals.first { $0.si == si } }

    var body: some View {
        ScrollView {
            if let m = meal {
                VStack(alignment: .leading, spacing: 8) {
                    // il nome del pasto è già nel titolo in alto: qui solo l'ora e il piatto
                    VStack(alignment: .leading, spacing: 1) {
                        Tag(text: m.time, color: m.eaten ? .secondary : Palette.lime)
                        Text(m.name).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                    macros(m)
                    // il pulsante sta subito sotto i numeri: non serve scorrere tutti gli ingredienti per segnare il pasto
                    if m.eaten {
                        Button { store.uneat(m) } label: { Label("ANNULLA", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(CardButton())
                    } else {
                        Button { store.eat(m) } label: { Label("MANGIATO", systemImage: "checkmark") }
                            .buttonStyle(LimeButton())
                    }
                    ingredients(m)
                    if let alt = m.alt, alt.count > 1 {
                        NavigationLink { AltPicker(si: m.si) } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Palette.lime)
                                Text("CAMBIA PIATTO").font(.sport(17)).lineLimit(1).minimumScaleFactor(0.6)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(CardButton())
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .navigationTitle(meal?.label ?? "Pasto")
        .pageBackground(Palette.lime, 0.12)
    }

    // kcal grandi e, sotto, proteine, carboidrati e grassi con i loro colori
    private func macros(_ m: WatchMeal) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // numero e «KCAL» impilati e centrati in altezza rispetto alle tre righe dei macro
            VStack(spacing: -4) {
                Text("\(m.k)").font(.sport(34)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text("KCAL").font(.sport(11, .bold)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                macro("P", m.p, Palette.p)
                if let c = m.c { macro("C", c, Palette.c) }
                if let f = m.f { macro("G", f, Palette.f) }
            }
        }
    }

    private func macro(_ letter: String, _ v: Int, _ color: Color) -> some View {
        (Text(letter + " ").font(.sport(12, .bold)).foregroundColor(color) + Text("\(v)").font(.sport(13)).monospacedDigit() + Text(" g").font(.system(size: 10)).foregroundColor(.secondary))
    }

    @ViewBuilder private func ingredients(_ m: WatchMeal) -> some View {
        if let ing = m.ing {
            VStack(spacing: 4) {
                Tag(text: "Ingredienti", color: .secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
                ForEach(Array(ing.enumerated()), id: \.offset) { _, it in
                    // il nome senza le parentesi («Insalata mista cruda (lattuga, pomodori…)» → «Insalata mista cruda»): sul polso non c'è spazio
                    HStack(alignment: .center, spacing: 6) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(it.n.components(separatedBy: " (").first ?? it.n).font(.system(size: 13, weight: .semibold))
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            if let h = it.h, !h.isEmpty { Text(h).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7) }
                        }
                        Spacer(minLength: 2)
                        Text("\(it.g)").font(.sport(20)).monospacedDigit().foregroundColor(Palette.lime) + Text(" \(it.u)").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        } else {
            Text("Ingredienti in aggiornamento: apri Recomp sull'iPhone.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

// i piatti della stessa fascia, con la differenza di kcal rispetto a quello di adesso
struct AltPicker: View {
    @EnvironmentObject var store: WatchStore
    @Environment(\.dismiss) private var dismiss
    let si: Int

    var body: some View {
        let m = store.snap?.meals.first { $0.si == si }
        List(m?.alt ?? []) { a in
            Button {
                if let m { store.swap(m, to: a) }
                dismiss()
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: a.cur == true ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(a.cur == true ? Palette.lime : .secondary)
                        .font(.system(size: 17))
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(a.name).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 4) {
                            Text("\(a.k) kcal").font(.sport(13)).monospacedDigit()
                            Text("P \(a.p)").font(.system(size: 11)).foregroundStyle(.secondary)
                            if a.cur != true, let m {
                                let d = a.k - m.k
                                Text("\(d > 0 ? "+" : d < 0 ? "−" : "±")\(abs(d))").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(d > 0 ? Palette.c : d < 0 ? Palette.lime : .secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Cambia")
        .pageBackground(Palette.lime, 0.12)
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
            .padding(.horizontal, 6)
        }
        .navigationTitle("Recomp")
    }
}
