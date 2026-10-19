import SwiftUI

// Il manichino 3D dell'esecuzione: un corpo fatto di capsule che fa il movimento dell'esercizio con il suo ritmo,
// con i muscoli che lavorano in rosso. Le pose stanno in movimenti.json (generato da tools/movimenti.py); lo stesso calcolo
// è in app-ios/swiftui/anteprima/manichino.js per provarlo nel browser: se cambi qualcosa qui, cambialo anche là.
// Assi del corpo: x = destra della persona, y = su, z = avanti; metri; pavimento a y = 0.

typealias V3 = SIMD3<Double>

private let D2R = Double.pi / 180
private func prodotto(_ a: V3, _ b: V3) -> Double { (a * b).sum() }
private func unit(_ a: V3, _ d: V3 = V3(0, 0, 1)) -> V3 { let l = prodotto(a, a).squareRoot(); return l < 1e-6 ? d : a / l }
private func perp(_ h: V3, _ u: V3, _ d: V3) -> V3 { unit(h - u * prodotto(h, u), d) }   // parte di h perpendicolare a u
private func meta(_ a: V3, _ b: V3) -> V3 { (a + b) * 0.5 }
private func rotX(_ v: V3, _ a: Double) -> V3 { let c = cos(a), s = sin(a); return V3(v.x, v.y * c - v.z * s, v.y * s + v.z * c) }
private func rotY(_ v: V3, _ a: Double) -> V3 { let c = cos(a), s = sin(a); return V3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c) }
private func rotZ(_ v: V3, _ a: Double) -> V3 { let c = cos(a), s = sin(a); return V3(v.x * c - v.y * s, v.x * s + v.y * c, v.z) }
private func v3(_ a: [Double]) -> V3 { V3(a[safe: 0] ?? 0, a[safe: 1] ?? 0, a[safe: 2] ?? 0) }

// MARK: dati (movimenti.json)

struct Posa: Decodable {
    var p: [Double]?
    var t, c, ro, ya, hp: Double?
    var ra, la, rl, ll: [Double]?   // braccio [φ, θ, gomito, verso x y z]; gamba [φ, θ, ginocchio, punta]

    // posa intermedia tra due pose
    static func mescola(_ a: Posa, _ b: Posa, _ k: Double) -> Posa {
        func n(_ x: Double?, _ y: Double?) -> Double? { guard let x0 = x ?? y, let y0 = y ?? x else { return nil }; return x0 + (y0 - x0) * k }
        func v(_ x: [Double]?, _ y: [Double]?) -> [Double]? {
            guard let x0 = x ?? y, let y0 = y ?? x else { return nil }
            return x0.indices.map { x0[$0] + ((y0[safe: $0] ?? x0[$0]) - x0[$0]) * k }
        }
        return Posa(p: v(a.p, b.p), t: n(a.t, b.t), c: n(a.c, b.c), ro: n(a.ro, b.ro), ya: n(a.ya, b.ya), hp: n(a.hp, b.hp),
                    ra: v(a.ra, b.ra), la: v(a.la, b.la), rl: v(a.rl, b.rl), ll: v(a.ll, b.ll))
    }
}

// estremo di un attrezzo: un punto fisso [x, y, z] oppure un punto del corpo (o la media di più punti) più uno spostamento
enum Estremo: Decodable {
    case fisso(V3)
    case corpo([String], V3)

    private enum K: String, CodingKey { case pt, off }
    init(from d: Decoder) throws {
        if let a = try? d.singleValueContainer().decode([Double].self) { self = .fisso(v3(a)); return }
        let c = try d.container(keyedBy: K.self)
        let nomi: [String]
        if let uno = try? c.decode(String.self, forKey: .pt) { nomi = [uno] } else { nomi = try c.decode([String].self, forKey: .pt) }
        self = .corpo(nomi, v3(try c.decodeIfPresent([Double].self, forKey: .off) ?? [0, 0, 0]))
    }
    func punto(_ pt: [String: V3]) -> V3 {
        switch self {
        case .fisso(let v): return v
        case .corpo(let nomi, let off): return nomi.reduce(V3()) { $0 + (pt[$1] ?? V3()) } / Double(max(1, nomi.count)) + off
        }
    }
}

struct Attrezzo: Decodable {
    let k: String
    let a, b, c: Estremo?
    let r, R, rx: Double?
    let n, s: [Double]?
    let col: String?
}

struct Movimento: Decodable {
    struct Cam: Decodable { let yaw: Double; let pitch: Double }
    struct Fisso: Decodable { let pt: String; let a: [Double] }
    let cam: Cam
    let tempo: [Double]       // salita, fermo, discesa, pausa (secondi)
    let fasi: [String]        // «Spingi», «Torna piano»
    let A: Posa
    let B: Posa
    let attrezzi: [Attrezzo]
    let fisso: Fisso?         // punto del corpo che resta fermo (piedi a terra, mani sulla sbarra…)
    let yt: String?           // video dell'esecuzione su YouTube (id), se c'è (VideoEsercizio.swift)
    let ytv: Bool?            // video verticale (9:16)
}

enum Movimenti {
    static let tutti: [String: Movimento] = {
        guard let url = Bundle.main.url(forResource: "movimenti", withExtension: "json"), let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode([String: Movimento].self, from: data) else { return [:] }
        return m
    }()
}

// MARK: corpo

private struct Corpo {
    var pt: [String: V3] = [:]
    var dir: [String: V3] = [:]
    var Fp: (V3) -> V3 = { $0 }
    var Fc: (V3) -> V3 = { $0 }
}

// direzione di un arto: φ = piano (0 di lato, 90 avanti, −90 indietro), θ = alzata (0 giù, 90 orizzontale, 180 su)
private func dirArto(_ lato: Double, _ fi: Double, _ te: Double) -> V3 {
    let f = fi * D2R, t = te * D2R
    return V3(lato * cos(f) * sin(t), -cos(t), sin(f) * sin(t))
}

private func corpo(_ q: Posa) -> Corpo {
    let t = (q.t ?? 0) * D2R, ro = (q.ro ?? 0) * D2R, ya = (q.ya ?? 0) * D2R, cu = (q.c ?? 0) * D2R
    let Fp: (V3) -> V3 = { rotY(rotZ(rotX($0, t), ro), ya) }   // bacino
    let Fc: (V3) -> V3 = { Fp(rotX($0, cu)) }                   // petto (si curva sul bacino: crunch)
    var c = Corpo(Fp: Fp, Fc: Fc)
    let P = q.p.map(v3) ?? V3(0, 0.97, 0)
    c.pt["pelvi"] = P
    let vita = P + Fp(V3(0, 0.22, 0)); c.pt["vita"] = vita
    let collo = vita + Fc(V3(0, 0.30, 0)); c.pt["collo"] = collo
    let dt = Fc(rotX(V3(0, 1, 0), (q.hp ?? 0) * D2R))
    c.pt["testa"] = collo + dt * 0.17
    c.pt["nuca"] = collo + dt * 0.07
    c.dir["su_p"] = Fp(V3(0, 1, 0)); c.dir["av_p"] = Fp(V3(0, 0, 1)); c.dir["dx"] = Fp(V3(1, 0, 0))
    c.dir["su_c"] = Fc(V3(0, 1, 0)); c.dir["av_c"] = Fc(V3(0, 0, 1)); c.dir["dx_c"] = Fc(V3(1, 0, 0))
    c.pt["trapezi"] = collo + Fc(V3(0, 0, 1)) * -0.1 + Fc(V3(0, 1, 0)) * -0.02   // dove appoggia il bilanciere dello squat
    for (s, lato) in [("r", 1.0), ("l", -1.0)] {
        // braccio
        let a = (lato > 0 ? q.ra : (q.la ?? q.ra)) ?? [0, 6, 8, 0, 0, 1]
        let u = dirArto(lato, a[0], a[1])
        let h = V3(lato * (a[safe: 3] ?? 0), a[safe: 4] ?? 0, a[safe: 5] ?? 1)
        let b = perp(h, u, V3(0, 0, 1))
        let eps = a[2] * D2R
        let f = u * cos(eps) + b * sin(eps)
        let S = collo + Fc(V3(lato * 0.19, -0.05, -0.01))
        let uw = Fc(u), fw = Fc(f)
        let gomito = S + uw * 0.29, polso = gomito + fw * 0.26
        c.pt["spalla_" + s] = S; c.pt["gomito_" + s] = gomito; c.pt["polso_" + s] = polso; c.pt["mano_" + s] = polso + fw * 0.05
        c.dir["braccio_" + s] = uw; c.dir["avambraccio_" + s] = fw; c.dir["piega_" + s] = Fc(b)
        // gamba
        let g = (lato > 0 ? q.rl : (q.ll ?? q.rl)) ?? [90, 0, 0, 0]
        let tl = dirArto(lato, g[0], g[1])
        let bk = perp(V3(0, -tl.z, tl.y), tl, V3(0, 0, -1))        // il ginocchio piega all'indietro
        let ka = g[2] * D2R
        let sl = tl * cos(ka) + bk * sin(ka)
        let fwd = perp(V3(0, sl.z, -sl.y), sl, V3(0, 0, 1))         // davanti alla gamba
        let pa = (g[safe: 3] ?? 0) * D2R
        let fo = fwd * cos(pa) + sl * sin(pa)
        let dietro = perp(V3(0, -sl.z, sl.y), sl, V3(0, 0, -1))     // lato del polpaccio
        let H = P + Fp(V3(lato * 0.09, -0.03, 0))
        let tw = Fp(tl), sw = Fp(sl), fow = Fp(fo), dw = Fp(dietro)
        let ginocchio = H + tw * 0.43, caviglia = ginocchio + sw * 0.42
        let base = caviglia + sw * 0.045
        let tallone = base - fow * 0.05, punta = base + fow * 0.16
        c.pt["anca_" + s] = H; c.pt["ginocchio_" + s] = ginocchio; c.pt["caviglia_" + s] = caviglia
        c.pt["tallone_" + s] = tallone; c.pt["punta_" + s] = punta
        c.pt["caviglia_" + s + "_dietro"] = caviglia + dw * 0.075
        c.pt["caviglia_" + s + "_davanti"] = caviglia - dw * 0.07
        c.pt["pianta_" + s] = meta(tallone, punta) + sw * 0.035
        c.dir["coscia_" + s] = tw; c.dir["gamba_" + s] = sw; c.dir["piegag_" + s] = Fp(bk); c.dir["polpaccio_" + s] = dw
    }
    func m(_ a: String, _ b: String) -> V3 { meta(c.pt[a]!, c.pt[b]!) }
    c.pt["mani"] = m("mano_r", "mano_l"); c.pt["spalle"] = m("spalla_r", "spalla_l"); c.pt["caviglie"] = m("caviglia_r", "caviglia_l")
    c.pt["piedi"] = m("pianta_r", "pianta_l"); c.pt["punte"] = m("punta_r", "punta_l"); c.pt["ginocchia"] = m("ginocchio_r", "ginocchio_l")
    return c
}

// MARK: pezzi da disegnare

private struct Pezzo {
    enum Forma { case capsula(V3, V3, Double), sfera(V3, Double), disco(V3, V3, Double), scatola(V3, V3, Double), linea(V3, V3, Double) }
    var forma: Forma
    var col: String
    var tag: String? = nil
    var forza = 1.0          // muscoli: 1 principale, 0,45 secondario
    var verso: V3? = nil     // muscoli: dove guardano (per nasconderli se sono dietro)
    var sopra: String? = nil // muscoli: il pezzo del corpo su cui stanno
}

private let MUSCOLI = ["Petto": "petto", "Dorsali": "dorsali", "Deltoidi laterali": "delt_lat", "Deltoidi anteriori": "delt_ant",
                       "Deltoidi posteriori": "delt_post", "Bicipiti": "bicipiti", "Tricipiti": "tricipiti", "Quadricipiti": "quadricipiti",
                       "Femorali": "femorali", "Glutei": "glutei", "Polpacci": "polpacci", "Addome": "addome"]

private func pezziCorpo(_ c: Corpo) -> [Pezzo] {
    let pt = c.pt
    var L: [Pezzo] = []
    func cap(_ a: V3, _ b: V3, _ r: Double, _ tag: String) { L.append(Pezzo(forma: .capsula(a, b, r), col: "corpo", tag: tag)) }
    cap(pt["anca_l"]!, pt["anca_r"]!, 0.1, "bacino")
    cap(pt["pelvi"]!, pt["vita"]!, 0.115, "pancia")
    cap(pt["vita"]!, pt["collo"]! + c.dir["su_c"]! * -0.04, 0.135, "torace")
    cap(pt["spalla_l"]!, pt["spalla_r"]!, 0.072, "spalle")
    cap(pt["collo"]!, pt["nuca"]!, 0.048, "collo")
    L.append(Pezzo(forma: .sfera(pt["testa"]!, 0.1), col: "corpo", tag: "testa"))
    for s in ["r", "l"] {
        cap(pt["spalla_" + s]!, pt["gomito_" + s]!, 0.052, "braccio_" + s)
        cap(pt["gomito_" + s]!, pt["polso_" + s]!, 0.043, "avambraccio_" + s)
        cap(pt["polso_" + s]!, pt["mano_" + s]!, 0.038, "mano_" + s)
        cap(pt["anca_" + s]!, pt["ginocchio_" + s]!, 0.078, "coscia_" + s)
        cap(pt["ginocchio_" + s]!, pt["caviglia_" + s]!, 0.056, "gamba_" + s)
        cap(pt["tallone_" + s]!, pt["punta_" + s]!, 0.042, "piede_" + s)
    }
    return L
}

private func pezziMuscoli(_ c: Corpo, _ principale: String, _ secondari: [String]) -> [Pezzo] {
    let pt = c.pt, dir = c.dir
    var L: [Pezzo] = []
    func mus(_ nome: String, _ forza: Double) {
        guard let k = MUSCOLI[nome] else { return }
        func add(_ f: Pezzo.Forma, _ o: V3, _ sopra: String) { L.append(Pezzo(forma: f, col: "muscolo", forza: forza, verso: o, sopra: sopra)) }
        for (s, lato) in [("r", 1.0), ("l", -1.0)] {
            let S = pt["spalla_" + s]!
            switch k {
            case "petto":
                add(.capsula(pt["collo"]! + c.Fc(V3(lato * 0.025, -0.13, 0.085)), pt["collo"]! + c.Fc(V3(lato * 0.12, -0.1, 0.07)), 0.062), dir["av_c"]!, "torace")
            case "dorsali":
                add(.capsula(pt["collo"]! + c.Fc(V3(lato * 0.13, -0.1, -0.06)), pt["vita"]! + c.Fc(V3(lato * 0.085, 0.03, -0.075)), 0.06),
                    unit(dir["dx_c"]! * (lato * 0.6) - dir["av_c"]!), "torace")
            case "addome" where s == "r":
                add(.capsula(pt["pelvi"]! + c.Fp(V3(0, 0.04, 0.065)), pt["vita"]! + c.Fc(V3(0, 0.06, 0.08)), 0.062), dir["av_p"]!, "pancia")
            case "delt_lat", "delt_ant", "delt_post":
                let off = k == "delt_lat" ? V3(lato * 0.03, 0.005, 0) : k == "delt_ant" ? V3(lato * 0.012, 0, 0.03) : V3(lato * 0.012, 0, -0.03)
                add(.sfera(S + c.Fc(off), 0.06), unit(c.Fc(off)), "braccio_" + s)
            case "bicipiti", "tricipiti":
                let u = dir["braccio_" + s]!, b = dir["piega_" + s]!
                let o = k == "bicipiti" ? b : b * -1
                add(.capsula(S + u * 0.08 + o * 0.026, S + u * 0.23 + o * 0.026, 0.036), o, "braccio_" + s)
            case "quadricipiti", "femorali":
                let H = pt["anca_" + s]!, tw = dir["coscia_" + s]!, bk = dir["piegag_" + s]!
                let o = k == "femorali" ? bk : bk * -1
                add(.capsula(H + tw * 0.09 + o * 0.03, H + tw * 0.36 + o * 0.03, 0.054), o, "coscia_" + s)
            case "glutei":
                add(.sfera(pt["anca_" + s]! + c.Fp(V3(lato * 0.015, -0.02, -0.07)), 0.075), dir["av_p"]! * -1, "bacino")
            case "polpacci":
                let K = pt["ginocchio_" + s]!, sw = dir["gamba_" + s]!, o = dir["polpaccio_" + s]!
                add(.capsula(K + sw * 0.06 + o * 0.024, K + sw * 0.24 + o * 0.024, 0.043), o, "gamba_" + s)
            default: break
            }
        }
    }
    mus(principale, 1)
    for x in secondari { mus(x, 0.45) }
    return L
}

private func pezziAttrezzi(_ lista: [Attrezzo], _ pt: [String: V3]) -> [Pezzo] {
    lista.compactMap { a in
        let col = a.col ?? (a.k == "disco" ? "disco" : a.k == "box" ? "scuro" : a.k == "linea" ? "cavo" : "metallo")
        switch a.k {
        case "cap": guard let x = a.a, let y = a.b else { return nil }; return Pezzo(forma: .capsula(x.punto(pt), y.punto(pt), a.r ?? 0.025), col: col)
        case "sfera": guard let x = a.c else { return nil }; return Pezzo(forma: .sfera(x.punto(pt), a.r ?? 0.04), col: col)
        case "disco": guard let x = a.c, let n = a.n else { return nil }; return Pezzo(forma: .disco(x.punto(pt), v3(n), a.R ?? 0.2), col: col)
        case "box": guard let x = a.c, let s = a.s else { return nil }; return Pezzo(forma: .scatola(x.punto(pt), v3(s), a.rx ?? 0), col: col)
        case "linea": guard let x = a.a, let y = a.b else { return nil }; return Pezzo(forma: .linea(x.punto(pt), y.punto(pt), 0.012), col: col)
        default: return nil
        }
    }
}

// tutta la scena in un istante (k da 0 = partenza a 1 = picco), spostata perché il punto «fisso» resti dov'è
private func scena(_ m: Movimento, _ k: Double, _ muscolo: String, _ secondari: [String]) -> [Pezzo] {
    var q = Posa.mescola(m.A, m.B, k)
    var c = corpo(q)
    if let f = m.fisso, let ora = c.pt[f.pt] {
        let nuovo = (q.p.map(v3) ?? V3(0, 0.97, 0)) + (v3(f.a) - ora)
        q.p = [nuovo.x, nuovo.y, nuovo.z]
        c = corpo(q)
    }
    return pezziCorpo(c) + pezziMuscoli(c, muscolo, secondari) + pezziAttrezzi(m.attrezzi, c.pt)
}

// MARK: tempo

enum Manichino {
    // fase del movimento: 0 salita, 1 fermo, 2 discesa, 3 pausa; k = quanto è avanti il movimento (0…1)
    static func fase(_ tempo: [Double], _ secondi: Double) -> (k: Double, fase: Int) {
        let su = tempo[safe: 0] ?? 1, fe = tempo[safe: 1] ?? 0, giu = tempo[safe: 2] ?? 1.8, pa = tempo[safe: 3] ?? 0.4
        let ease: (Double) -> Double = { $0 * $0 * (3 - 2 * $0) }
        var x = secondi.truncatingRemainder(dividingBy: su + fe + giu + pa)
        if x < su { return (ease(x / su), 0) }
        x -= su; if x < fe { return (1, 1) }
        x -= fe; if x < giu { return (1 - ease(x / giu), 2) }
        return (0, 3)
    }

    // MARK: disegno

    private static let colori: [String: (Double, Double, Double)] = [
        "corpo": (212, 215, 219), "metallo": (120, 123, 130), "scuro": (52, 53, 58), "cuscino": (66, 67, 74), "disco": (70, 72, 78), "cavo": (150, 153, 160),
    ]
    private static let rosso = (229.0, 72.0, 59.0)

    private static func colore(_ c: (Double, Double, Double), _ k: Double, _ a: Double = 1) -> Color {
        Color(red: min(255, c.0 * k) / 255, green: min(255, c.1 * k) / 255, blue: min(255, c.2 * k) / 255).opacity(a)
    }

    struct Camera { var yaw: Double; var pitch: Double }

    private static func vista(_ v: V3, _ cam: Camera) -> V3 {
        let a = cam.yaw * D2R, b = cam.pitch * D2R
        let x = v.x * cos(a) + v.z * sin(a)
        let d0 = -v.x * sin(a) + v.z * cos(a)
        return V3(x, v.y * cos(b) - d0 * sin(b), v.y * sin(b) + d0 * cos(b))
    }

    private static func vertici(_ c: V3, _ s: V3, _ rx: Double) -> [V3] {
        var V: [V3] = []
        for sx in [-1.0, 1] { for sy in [-1.0, 1] { for sz in [-1.0, 1] { V.append(c + rotX(V3(sx * s.x / 2, sy * s.y / 2, sz * s.z / 2), rx * D2R)) } } }
        return V
    }

    private struct Inquadratura { let sc: Double; let cx: Double; let cy: Double }

    // tutti i punti di partenza, metà e picco devono stare dentro
    private static func inquadra(_ m: Movimento, _ cam: Camera, _ size: CGSize, _ muscolo: String, _ sec: [String]) -> Inquadratura {
        var x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9
        for k in [0.0, 0.5, 1] {
            for p in scena(m, k, muscolo, sec) {
                var punti: [V3] = [], r = 0.0
                switch p.forma {
                case .capsula(let a, let b, let rr): punti = [a, b]; r = rr
                case .linea(let a, let b, _): punti = [a, b]
                case .sfera(let c, let rr): punti = [c]; r = rr
                case .disco(let c, _, let R): punti = [c]; r = R
                case .scatola(let c, let s, let rx): punti = vertici(c, s, rx)
                }
                for v in punti {
                    let s = vista(v, cam)
                    x0 = min(x0, s.x - r); x1 = max(x1, s.x + r); y0 = min(y0, s.y - r); y1 = max(y1, s.y + r)
                }
            }
        }
        let sc = min(Double(size.width) * 0.84 / max(0.1, x1 - x0), Double(size.height) * 0.82 / max(0.1, y1 - y0))
        return Inquadratura(sc: sc, cx: Double(size.width) / 2 - (x0 + x1) / 2 * sc, cy: Double(size.height) / 2 + (y0 + y1) / 2 * sc)
    }

    static func disegna(_ ctx: inout GraphicsContext, _ size: CGSize, _ m: Movimento, _ k: Double, _ cam: Camera, _ muscolo: String, _ sec: [String]) {
        let fr = inquadra(m, cam, size, muscolo, sec)
        let pezzi = scena(m, k, muscolo, sec)
        func P(_ v: V3) -> CGPoint { let s = vista(v, cam); return CGPoint(x: fr.cx + s.x * fr.sc, y: fr.cy - s.y * fr.sc) }

        // ombra sul pavimento
        let o = P(V3(0, 0, 0)), ro = 0.75 * fr.sc
        let rv = ro * max(0.12, abs(sin(cam.pitch * D2R)))
        ctx.fill(Path(ellipseIn: CGRect(x: o.x - ro, y: o.y - rv, width: ro * 2, height: rv * 2)),
                 with: .radialGradient(Gradient(colors: [.black.opacity(0.45), .black.opacity(0)]), center: o, startRadius: 0, endRadius: ro))

        // profondità di ogni pezzo: si disegna dal più lontano; i muscoli subito sopra il loro pezzo
        func prof(_ p: Pezzo) -> Double {
            switch p.forma {
            case .capsula(let a, let b, _), .linea(let a, let b, _): return vista(meta(a, b), cam).z
            case .scatola(let c, _, _): return vista(c, cam).z - 0.02
            case .sfera(let c, _), .disco(let c, _, _): return vista(c, cam).z
            }
        }
        var perTag: [String: Double] = [:]
        for p in pezzi { if let t = p.tag { perTag[t] = prof(p) } }
        var voci: [(Pezzo, Double, Int)] = []
        for (i, p) in pezzi.enumerated() {
            var d = prof(p)
            if p.col == "muscolo", let t = p.sopra, let base = perTag[t] { d = base + 0.0005 }
            voci.append((p, d, i))
        }
        voci.sort { $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 < $1.2 }
        var ds: [Double] = []
        for v in voci where v.0.col == "corpo" { ds.append(v.1) }
        let dmin = ds.min() ?? 0, dmax = ds.max() ?? 1

        for (p, d, _) in voci {
            let luce = 0.62 + 0.38 * min(1, max(0, (d - dmin) / max(1e-3, dmax - dmin)))
            let col = p.col == "muscolo" ? rosso : (colori[p.col] ?? colori["metallo"]!)
            var alfa = 1.0
            if p.col == "muscolo", let o = p.verso {
                alfa = min(1, max(0, (vista(o, cam).z + 0.3) / 0.45)) * p.forza
                if alfa <= 0.02 { continue }
            }
            let lum = p.col == "corpo" || p.col == "muscolo" ? luce : 0.85 + 0.15 * luce
            switch p.forma {
            case .capsula(let a, let b, let r): capsula(&ctx, P(a), P(b), r * fr.sc, col, lum, alfa, p.col == "muscolo")
            case .sfera(let c, let r): sfera(&ctx, P(c), r * fr.sc, col, lum, alfa, p.col == "muscolo")
            case .linea(let a, let b, let w):
                var l = Path(); l.move(to: P(a)); l.addLine(to: P(b))
                ctx.stroke(l, with: .color(colore(col, 1)), lineWidth: max(1.2, w * fr.sc))
            case .disco(let c, let n, let R): disco(&ctx, P(c), vista(n, cam), R * fr.sc, col)
            case .scatola(let c, let s, let rx): scatola(&ctx, c, s, rx, cam, P, col)
            }
        }
    }

    // capsula con la sfumatura di un cilindro: luce dall'alto a sinistra
    private static func capsula(_ ctx: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ r: Double, _ col: (Double, Double, Double), _ lum: Double, _ alfa: Double, _ muscolo: Bool) {
        var nx = -(b.y - a.y), ny = b.x - a.x
        let l = max(1e-6, (nx * nx + ny * ny).squareRoot()); nx /= l; ny /= l
        if l < 0.01 { nx = 0.6; ny = 0.8 }
        if nx * -0.6 + ny * -0.8 < 0 { nx = -nx; ny = -ny }
        let m = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let g = Gradient(stops: [.init(color: colore(col, lum * 1.12, alfa), location: 0), .init(color: colore(col, lum, alfa), location: 0.35),
                                 .init(color: colore(col, lum * 0.5, alfa), location: 1)])
        let shading = GraphicsContext.Shading.linearGradient(g, startPoint: CGPoint(x: m.x + nx * r, y: m.y + ny * r), endPoint: CGPoint(x: m.x - nx * r, y: m.y - ny * r))
        // linea con le punte tonde larga quanto la capsula (se è cortissima, un cerchio)
        var forma = Path()
        if hypot(b.x - a.x, b.y - a.y) < 0.5 {
            forma.addEllipse(in: CGRect(x: a.x - r, y: a.y - r, width: r * 2, height: r * 2))
        } else {
            var l = Path(); l.move(to: a); l.addLine(to: b)
            forma = l.strokedPath(StrokeStyle(lineWidth: r * 2, lineCap: .round))
        }
        if muscolo {
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: Color(red: 229 / 255, green: 72 / 255, blue: 59 / 255).opacity(0.6 * alfa), radius: r * 0.9))
                l.fill(forma, with: shading)
            }
        } else {
            ctx.fill(forma, with: shading)
        }
    }

    private static func sfera(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: Double, _ col: (Double, Double, Double), _ lum: Double, _ alfa: Double, _ muscolo: Bool) {
        let g = Gradient(stops: [.init(color: colore(col, lum * 1.15, alfa), location: 0), .init(color: colore(col, lum, alfa), location: 0.6),
                                 .init(color: colore(col, lum * 0.55, alfa), location: 1)])
        let shading = GraphicsContext.Shading.radialGradient(g, center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35), startRadius: r * 0.05, endRadius: r * 1.25)
        let path = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        if muscolo {
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: Color(red: 229 / 255, green: 72 / 255, blue: 59 / 255).opacity(0.6 * alfa), radius: r * 0.9))
                l.fill(path, with: shading)
            }
        } else {
            ctx.fill(path, with: shading)
        }
    }

    // disco (bilanciere, manubri): un'ellisse che si schiaccia quando lo vedi di taglio
    private static func disco(_ ctx: inout GraphicsContext, _ c: CGPoint, _ n: V3, _ R: Double, _ col: (Double, Double, Double)) {
        let ang = hypot(n.x, n.y) < 1e-4 ? 0 : atan2(-n.y, n.x)
        let rx = R * max(0.12, abs(n.z)), ry = R
        let t = CGAffineTransform(rotationAngle: ang).concatenating(CGAffineTransform(translationX: c.x, y: c.y))
        let path = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)).applying(t)
        ctx.fill(path, with: .linearGradient(Gradient(colors: [colore(col, 1.35), colore(col, 0.7)]),
                                             startPoint: CGPoint(x: 0, y: -ry).applying(t), endPoint: CGPoint(x: 0, y: ry).applying(t)))
        ctx.stroke(path, with: .color(colore(col, 1.7, 0.5)), lineWidth: 1)
    }

    // panche, sedili, pedane: solo le facce rivolte verso di noi, più chiare quelle in alto
    private static func scatola(_ ctx: inout GraphicsContext, _ c: V3, _ s: V3, _ rx: Double, _ cam: Camera, _ P: (V3) -> CGPoint, _ col: (Double, Double, Double)) {
        let V = vertici(c, s, rx)   // indice = sx*4 + sy*2 + sz (0 = −, 1 = +)
        let facce: [([Int], V3)] = [([0, 1, 3, 2], V3(-1, 0, 0)), ([4, 6, 7, 5], V3(1, 0, 0)), ([0, 4, 5, 1], V3(0, -1, 0)),
                                    ([2, 3, 7, 6], V3(0, 1, 0)), ([0, 2, 6, 4], V3(0, 0, -1)), ([1, 5, 7, 3], V3(0, 0, 1))]
        for (idx, n0) in facce {
            let n = vista(rotX(n0, rx * D2R), cam)
            if n.z <= 0.001 { continue }
            let luce = 0.75 + 0.45 * max(0, n.y) + 0.1 * n.x
            var path = Path()
            for (j, i) in idx.enumerated() { if j == 0 { path.move(to: P(V[i])) } else { path.addLine(to: P(V[i])) } }
            path.closeSubpath()
            ctx.fill(path, with: .color(colore(col, luce)))
            ctx.stroke(path, with: .color(colore(col, luce * 1.25, 0.6)), lineWidth: 0.8)
        }
    }
}

// MARK: viste

// l'esecuzione: il video vero (YouTube) se c'è, se no (o a scelta) il manichino 3D con il ritmo sotto
// («Spingi 1″ · Fermo · Torna piano 1,8″»), che si gira trascinando col dito
struct EsecuzioneAnimata: View {
    let ex: String
    var altezza: CGFloat = 300
    @State private var giro = 0.0
    @State private var giroInizio: Double?
    @State private var modo = 0          // 0 video · 1 manichino 3D

    var body: some View {
        let m = Movimenti.tutti[ex]
        VStack(spacing: 12) {
            if let m, let v = m.yt, modo == 0 {
                VideoYouTube(id: v)
                    .aspectRatio(m.ytv == true ? 9.0 / 16 : 16.0 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: m.ytv == true ? 480 : nil)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                ritmoFisso(m)
            } else if let m {
                manichino(m)
            } else {
                Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 60)).foregroundStyle(Tema.tenue)
                    .frame(maxWidth: .infinity).frame(height: altezza).background(Palco()).clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            if m?.yt != nil {
                Picker("Vista", selection: $modo) { Text("Video").tag(0); Text("Manichino 3D").tag(1) }.pickerStyle(.segmented)
                if modo == 0 {
                    Text("Il video ha bisogno di internet; senza rete usa il manichino.")
                        .font(.system(size: 12)).foregroundStyle(Tema.tenue).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func manichino(_ m: Movimento) -> some View {
        let lib = Piano.shared.exlib[ex]
        return TimelineView(.animation) { tl in
            let f = Manichino.fase(m.tempo, tl.date.timeIntervalSinceReferenceDate)
            VStack(spacing: 12) {
                Canvas { ctx, size in
                    Manichino.disegna(&ctx, size, m, f.k, Manichino.Camera(yaw: m.cam.yaw + giro, pitch: m.cam.pitch), lib?.m ?? "", lib?.sec ?? [])
                }
                .frame(maxWidth: .infinity).frame(height: altezza)
                .background(Palco())
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        if giroInizio == nil { giroInizio = giro }
                        giro = (giroInizio ?? 0) - Double(v.translation.width) * 0.6
                    }
                    .onEnded { _ in giroInizio = nil })
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "rotate.3d").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.45)).padding(12)
                }
                ritmo(m, f.fase)
            }
        }
    }

    private func voci(_ m: Movimento) -> [(String, Int)] {
        [("\(m.fasi[safe: 0] ?? "Su") \(fmtNum(m.tempo[safe: 0] ?? 1))″", 0)]
            + ((m.tempo[safe: 1] ?? 0) > 0 ? [("Fermo", 1)] : [])
            + [("\(m.fasi[safe: 1] ?? "Giù") \(fmtNum(m.tempo[safe: 2] ?? 2))″", 2)]
    }

    // le fasi del movimento: si accende quella in corso
    private func ritmo(_ m: Movimento, _ fase: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(voci(m), id: \.1) { v in
                Text(v.0).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    .padding(.horizontal, 11).frame(height: 30)
                    .foregroundStyle(fase == v.1 ? Color.white : Tema.tenue)
                    .background(fase == v.1 ? AnyShapeStyle(Tema.rosso) : AnyShapeStyle(Tema.scheda), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.15), value: fase)
    }

    // sotto il video il ritmo resta scritto (il video ha i suoi tempi)
    private func ritmoFisso(_ m: Movimento) -> some View {
        HStack(spacing: 6) {
            Text("Ritmo").font(.system(size: 13, weight: .semibold)).foregroundStyle(Tema.tenue)
            ForEach(voci(m), id: \.1) { v in
                Text(v.0).font(.system(size: 13, weight: .bold)).lineLimit(1).foregroundStyle(Tema.testo)
                    .padding(.horizontal, 11).frame(height: 30).background(Tema.scheda, in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }
}

// sfondo del manichino: grafite con una luce in alto (resta scuro anche col tema chiaro, come un palco)
struct Palco: View {
    var body: some View {
        RadialGradient(colors: [Color(hex: 0x2A2A2F), Color(hex: 0x151517)], center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 320)
    }
}

// la miniatura nella scheda dell'allenamento: la copertina del video (sopra il manichino fermo al picco del movimento,
// che resta se non c'è rete); si tocca per vedere l'esecuzione
struct MiniaturaEsercizio: View {
    let ex: String
    var lato: CGFloat = 54

    var body: some View {
        let lib = Piano.shared.exlib[ex]
        let m = Movimenti.tutti[ex]
        ZStack(alignment: .bottomTrailing) {
            if let m {
                Canvas { ctx, size in
                    Manichino.disegna(&ctx, size, m, 0.85, Manichino.Camera(yaw: m.cam.yaw, pitch: m.cam.pitch), lib?.m ?? "", lib?.sec ?? [])
                }
                .background(Palco())
                if let v = m.yt { CopertinaVideo(id: v).frame(width: lato, height: lato) }
            } else {
                Image(systemName: "figure.strengthtraining.traditional").font(.system(size: lato * 0.45)).foregroundStyle(Tema.tenue)
                    .frame(width: lato, height: lato).background(Tema.scheda2)
            }
            Image(systemName: "play.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                .frame(width: 16, height: 16).background(Color.black.opacity(0.55), in: Circle()).padding(3)
        }
        .frame(width: lato, height: lato)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
