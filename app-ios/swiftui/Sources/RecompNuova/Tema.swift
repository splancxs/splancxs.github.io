import SwiftUI

// Lo stile della nuova app, preso da Lift: sfondo grafite quasi nero, schede grigie, scheda dell'allenamento di oggi in argento
// metallico con un numero grande, accento rosso, barra in basso con sole icone. Chiaro e scuro seguono il telefono.
extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    init(chiaro: UInt32, scuro: UInt32) {
        self = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: scuro)) : UIColor(Color(hex: chiaro)) })
    }
}

enum Tema {
    static let fondo = Color(chiaro: 0xF2F2F4, scuro: 0x111113)
    static let scheda = Color(chiaro: 0xFFFFFF, scuro: 0x1C1C1F)
    static let scheda2 = Color(chiaro: 0xE8E8EB, scuro: 0x28282C)
    static let linea = Color(chiaro: 0xDADADF, scuro: 0x2E2E33)
    static let testo = Color(chiaro: 0x111113, scuro: 0xF4F4F6)
    static let tenue = Color(chiaro: 0x6C6C72, scuro: 0x8F8F95)
    static let spento = Color(chiaro: 0xB4B4BA, scuro: 0x3A3A40)   // numeri grandi della lista, segmenti vuoti
    static let rosso = Color(hex: 0xE5483B)
    static let verde = Color(hex: 0x4FC47F)
    static let ambra = Color(hex: 0xF0A93A)
    // proteine, carboidrati, grassi
    static let p = Color(hex: 0xFF6A55)
    static let c = Color(hex: 0xF2B64A)
    static let g = Color(hex: 0x5BA4EC)
    static let inchiostro = Color(hex: 0x121214)   // testo sopra l'argento
}

// argento metallico: sfumatura con riflessi in diagonale, come la scheda di Lift
struct Argento: View {
    var raggio: CGFloat = 30
    var body: some View {
        RoundedRectangle(cornerRadius: raggio, style: .continuous)
            .fill(LinearGradient(stops: [
                .init(color: Color(hex: 0xB9BBBA), location: 0.00),
                .init(color: Color(hex: 0xD9DBDA), location: 0.18),
                .init(color: Color(hex: 0x9FA1A0), location: 0.38),
                .init(color: Color(hex: 0xC4C6C5), location: 0.55),
                .init(color: Color(hex: 0x8C8E8D), location: 0.78),
                .init(color: Color(hex: 0xB2B4B3), location: 1.00),
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: raggio, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
    }
}

// scheda grigia (superficie)
struct Scheda<Content: View>: View {
    var padding: CGFloat = 18
    var raggio: CGFloat = 24
    @ViewBuilder var contenuto: Content
    var body: some View {
        contenuto
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tema.scheda, in: RoundedRectangle(cornerRadius: raggio, style: .continuous))
    }
}

// titolo di sezione, come «Other workouts» di Lift
struct Titolo: View {
    let testo: String
    var body: some View { Text(testo.uppercased()).font(.sport(24)).foregroundStyle(Tema.tenue).padding(.top, 8) }
}

// pulsante principale e secondario
struct PulsantePieno: ButtonStyle {
    var colore: Color = Tema.inchiostro
    var testo: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(testo)
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(colore.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}
struct PulsanteLeggero: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Tema.testo)
            .padding(.horizontal, 14).frame(minHeight: 38)
            .background(Tema.scheda2.opacity(configuration.isPressed ? 0.6 : 1), in: Capsule())
    }
}

// barre dei macro (proteine · carboidrati · grassi) in un'unica barra
struct BarraMacro: View {
    let t: Tot
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                let tot = max(1, t.p * 4 + t.c * 4 + t.fa * 9)
                HStack(spacing: 3) {
                    Capsule().fill(Tema.p).frame(width: max(4, (g.size.width - 6) * t.p * 4 / tot))
                    Capsule().fill(Tema.c).frame(width: max(4, (g.size.width - 6) * t.c * 4 / tot))
                    Capsule().fill(Tema.g).frame(width: max(4, (g.size.width - 6) * t.fa * 9 / tot))
                }
            }
            .frame(height: 8)
            HStack(spacing: 14) {
                legenda(Tema.p, "P", t.p); legenda(Tema.c, "C", t.c); legenda(Tema.g, "G", t.fa)
            }
        }
    }
    private func legenda(_ colore: Color, _ l: String, _ v: Double) -> some View {
        HStack(spacing: 5) {
            Circle().fill(colore).frame(width: 8, height: 8)
            Text("\(l) \(Int(r0(v)))").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.tenue)
        }
    }
}

// etichette (ingredienti, muscoli) che vanno a capo
struct Etichette: View {
    let voci: [(String, String?)]   // testo, valore
    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(Array(voci.enumerated()), id: \.offset) { _, v in
                HStack(spacing: 6) {
                    Text(v.0).font(.system(size: 14, weight: .medium))
                    if let g = v.1 { Text(g).font(.system(size: 15, weight: .heavy)) }
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Tema.scheda2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

// disposizione a righe che vanno a capo
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let larghezza = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, riga: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x + d.width > larghezza && x > 0 { x = 0; y += riga + spacing; riga = 0 }
            x += d.width + spacing; riga = max(riga, d.height)
        }
        return CGSize(width: larghezza, height: y + riga)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, riga: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x + d.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += riga + spacing; riga = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(d))
            x += d.width + spacing; riga = max(riga, d.height)
        }
    }
}

// anello (calorie)
struct Anello: View {
    let valore: Double
    let totale: Double
    var spessore: CGFloat = 12
    var colore: Color = Tema.testo
    var body: some View {
        ZStack {
            Circle().stroke(Tema.scheda2, lineWidth: spessore)
            Circle().trim(from: 0, to: totale > 0 ? min(1, valore / totale) : 0)
                .stroke(colore, style: StrokeStyle(lineWidth: spessore, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// pagina con titolo grande a sinistra e contenuto che scorre
struct Pagina<Content: View>: View {
    @ViewBuilder var contenuto: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { contenuto }
                .padding(.horizontal, 20).padding(.top, 2).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Tema.fondo.ignoresSafeArea())
        // velo sotto l'ora e la batteria: quello che scorre sparisce in dissolvenza invece di finire sotto la barra di stato
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                Color.clear.frame(height: 0).background(Tema.fondo.ignoresSafeArea(edges: .top))
                LinearGradient(colors: [Tema.fondo, Tema.fondo.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 14)
            }
            .allowsHitTesting(false)
        }
    }
}

func tempoMMSS(_ secondi: Int) -> String {
    let s = max(0, secondi)
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

// finestre che salgono dal basso: un po' più basse dello schermo intero, con la barretta in alto, fondo grafite.
// Una sola altezza: il contenuto scorre subito e tirando giù si chiude (con due altezze il foglio prima si allargava
// e poi scorreva, e a scatti passava da sospeso a schermo intero: poco fluido)
extension View {
    func foglio() -> some View {
        presentationDetents([.fraction(0.92)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(34)
            .presentationBackground(Tema.fondo)
    }

    // un campo di testo nello stile dell'app (scheda grigia arrotondata)
    func campo() -> some View {
        padding(.horizontal, 14).padding(.vertical, 13)
            .background(Tema.scheda, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // il pulsante principale in fondo a una finestra: resta sopra la tastiera
    func pulsanteInFondo(_ titolo: String, attivo: Bool, _ azione: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Button(titolo, action: azione)
                .buttonStyle(PulsantePieno(colore: Tema.testo, testo: Tema.fondo))
                .disabled(!attivo).opacity(attivo ? 1 : 0.4)
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 6)
                .background(Tema.fondo)
        }
    }
}

// la testata delle finestre: titolo grande, riga sotto, pulsanti in più e la X per chiudere
struct TestataFoglio<Extra: View>: View {
    let titolo: String
    var sotto: String = ""
    let chiudi: () -> Void
    @ViewBuilder var extra: Extra

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(titolo.uppercased()).font(.sport(28)).lineLimit(1).minimumScaleFactor(0.7)
                if !sotto.isEmpty { Text(sotto).font(.system(size: 13)).foregroundStyle(Tema.tenue).lineLimit(2) }
            }
            Spacer(minLength: 8)
            extra
            Button(action: chiudi) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 34, height: 34).background(Tema.scheda, in: Circle())
            }
            .foregroundStyle(Tema.testo).accessibilityLabel("Chiudi")
        }
        .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 10)
    }
}

extension TestataFoglio where Extra == EmptyView {
    init(titolo: String, sotto: String = "", chiudi: @escaping () -> Void) {
        self.init(titolo: titolo, sotto: sotto, chiudi: chiudi, extra: { EmptyView() })
    }
}

// il cerchio grigio con un'icona, per i pulsanti della testata (••• , cestino…)
struct TondoIcona: View {
    let icona: String
    var colore: Color = Tema.testo
    var body: some View {
        Image(systemName: icona).font(.system(size: 15, weight: .bold)).foregroundStyle(colore)
            .frame(width: 34, height: 34).background(Tema.scheda, in: Circle())
    }
}

// titoletto di una parte della finestra
struct TitoloFoglio: View {
    let testo: String
    var body: some View { Text(testo.uppercased()).font(.sport(19)).foregroundStyle(Tema.tenue).padding(.top, 6) }
}
