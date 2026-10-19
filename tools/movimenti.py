# Genera app-ios/swiftui/Resources/movimenti.json: per ogni esercizio due pose del manichino 3D (A = partenza, B = picco),
# il ritmo, la telecamera e gli attrezzi. Lo leggono l'app (Manichino.swift) e l'anteprima nel browser (anteprima/manichino.js).
#
# Posa: p = bacino [x, y, z] (metri; x destra, y su, z avanti), t = busto inclinato in avanti (gradi; −90 = sdraiato sulla schiena,
# 90 = a pancia in giù), c = schiena curva (crunch), ro = busto inclinato di lato, hp = testa in avanti.
# Braccio ra/la = [φ, θ, gomito, verso x, y, z]: φ = piano (0 di lato, 90 avanti, −90 indietro), θ = alzata (0 giù, 90 orizzontale,
# 180 su), gomito = piegamento, verso = dove va l'avambraccio quando piega. Gamba rl/ll = [φ, θ, ginocchio, punta del piede].
# Se manca il lato sinistro è uguale al destro (specchiato). Gli angoli sono rispetto al busto (braccia) e al bacino (gambe).
import json, os

QUI = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(QUI, "..", "app-ios", "swiftui", "Resources", "movimenti.json")


def pt(nome, off=(0, 0, 0)):
    return {"pt": nome, "off": [round(x, 3) for x in off]}


def cap(a, b, r=0.025, col="metallo"):
    return {"k": "cap", "a": a, "b": b, "r": r, "col": col}


def box(c, s, rx=0, col="scuro"):
    return {"k": "box", "c": c, "s": s, "rx": rx, "col": col}


def sfera(c, r=0.04, col="metallo"):
    return {"k": "sfera", "c": c, "r": r, "col": col}


def disco(c, n, R, col="disco"):
    return {"k": "disco", "c": c, "n": n, "R": R, "col": col}


def linea(a, b):
    return {"k": "linea", "a": a, "b": b}


def cavo(da, a):
    return [linea(da, a), sfera(da, 0.045)]


def manubrio(mano, asse=(1, 0, 0)):
    ax = [x * 0.085 for x in asse]
    neg = [-x for x in ax]
    return [cap(pt(mano, neg), pt(mano, ax), 0.016),
            disco(pt(mano, [x * 0.8 for x in ax]), list(asse), 0.065), disco(pt(mano, [x * 0.8 for x in neg]), list(asse), 0.065)]


def bilanciere(est=0.3, R=0.2, giu=0.0):
    return [cap(pt("mano_l", (-est - 0.12, giu, 0)), pt("mano_r", (est + 0.12, giu, 0)), 0.015),
            disco(pt("mano_l", (-est, giu, 0)), [1, 0, 0], R), disco(pt("mano_r", (est, giu, 0)), [1, 0, 0], R),
            disco(pt("mano_l", (-est - 0.05, giu, 0)), [1, 0, 0], R * 0.8), disco(pt("mano_r", (est + 0.05, giu, 0)), [1, 0, 0], R * 0.8)]


def maniglia(mano, asse=(0, 1, 0), l=0.06):
    return cap(pt(mano, [-x * l for x in asse]), pt(mano, [x * l for x in asse]), 0.02)


def corda():
    return cap(pt("mano_l"), pt("mano_r"), 0.016, "cavo")


def sedile(alto=0.47, z=0.1, schienale=None):
    L = [box([0, alto - 0.05, z], [0.4, 0.1, 0.42], 0, "cuscino"), box([0, (alto - 0.1) / 2, z], [0.07, alto - 0.1, 0.07], 0, "metallo")]
    if schienale is not None:
        L.append(box([0, alto + 0.36, -0.17], [0.4, 0.66, 0.08], schienale, "cuscino"))
    return L


def torre(z, alto=2.3, x=0):
    return [cap([x, 0, z], [x, alto, z], 0.035)]


IN_PIEDI = {"p": [0, 0.97, 0], "rl": [90, 0, 0, 0]}
SEDUTO = {"p": [0, 0.58, 0], "rl": [86, 90, 90, 0]}
GIU = [0, 6, 8, 0, 0, 1]
PIEDI_A_TERRA = {"pt": "caviglie", "a": [0, 0.09, 0]}

TEMPO = [1.0, 0.4, 1.8, 0.4]


def es(cam, A, B, attrezzi=(), fasi=("Spingi", "Torna piano"), tempo=TEMPO, fisso=None, base=None):
    a = dict(base or {}); a.update(A)
    b = dict(base or {}); b.update(B)
    d = {"cam": {"yaw": cam[0], "pitch": cam[1]}, "tempo": tempo, "fasi": list(fasi), "A": a, "B": b, "attrezzi": list(attrezzi)}
    if fisso:
        d["fisso"] = fisso
    return d


def piatto(*liste):
    out = []
    for x in liste:
        out += x if isinstance(x, list) else [x]
    return out


E = {}

# ---------------- petto ----------------
E["chest_press"] = es((55, 12), {"t": -8, "ra": [-15, 80, 110, 0, 0, 1]}, {"t": -8, "ra": [75, 82, 8, 0, 0, 1]},
    piatto(sedile(schienale=-8), maniglia("mano_r"), maniglia("mano_l"),
           cap([0.33, 1.45, -0.3], pt("mano_r", (0.04, 0, 0))), cap([-0.33, 1.45, -0.3], pt("mano_l", (-0.04, 0, 0)))),
    base=SEDUTO)

E["pec_deck"] = es((20, 30), {"ra": [-12, 88, 90, 0, 1, 0]}, {"ra": [100, 88, 90, 0, 1, 0]},
    piatto(sedile(schienale=0),
           cap(pt("gomito_r", (0, 0.02, 0.07)), pt("polso_r", (0, 0.03, 0.07)), 0.045, "cuscino"),
           cap(pt("gomito_l", (0, 0.02, 0.07)), pt("polso_l", (0, 0.03, 0.07)), 0.045, "cuscino"),
           cap([0.22, 1.45, -0.12], pt("polso_r", (0, 0.08, 0.07)), 0.022), cap([-0.22, 1.45, -0.12], pt("polso_l", (0, 0.08, 0.07)), 0.022)),
    fasi=("Chiudi", "Riapri piano"), tempo=[1.0, 0.5, 1.8, 0.4], base=SEDUTO)

PANCA_PIANA = {"p": [0, 0.56, 0], "t": -90, "rl": [90, -30, 70, 10]}
panca = [box([0, 0.38, -0.22], [0.3, 0.1, 1.25], 0, "cuscino"), box([0, 0.17, -0.22], [0.08, 0.33, 0.08], 0, "metallo")]

E["bench_press_bb"] = es((55, 22), {"ra": [-5, 75, 105, 0, 0, 1]}, {"ra": [30, 72, 10, 0, 0, 1]},
    piatto(panca, bilanciere(), cap([0.55, 0, -0.15], [0.55, 1.15, -0.15], 0.03), cap([-0.55, 0, -0.15], [-0.55, 1.15, -0.15], 0.03)),
    base=PANCA_PIANA)

E["db_bench"] = es((55, 22), {"ra": [-10, 80, 110, 0, 0, 1]}, {"ra": [80, 88, 6, 0, 0, 1]},
    piatto(panca, manubrio("mano_r"), manubrio("mano_l")), base=PANCA_PIANA)

INCLINATA = {"p": [0, 0.56, 0], "t": -60, "rl": [90, 35, 85, 0]}
panca_incl = [box([0, 0.4, 0.05], [0.32, 0.09, 0.4], 0, "cuscino"), box([0, 0.72, -0.35], [0.32, 0.09, 0.85], 30, "cuscino"),
              box([0, 0.2, -0.1], [0.08, 0.4, 0.08], 0, "metallo")]
E["incline_db_press"] = es((60, 15), {"ra": [-12, 80, 110, 0, 0, 1]}, {"ra": [82, 88, 6, 0, 0, 1]},
    piatto(panca_incl, manubrio("mano_r"), manubrio("mano_l")), base=INCLINATA)

E["cable_fly"] = es((20, 15), {"t": 12, "ra": [-8, 82, 22, 0, 0, 1]}, {"t": 12, "ra": [100, 72, 22, 0, 0, 1]},
    piatto(cavo([0.95, 1.95, -0.1], pt("mano_r")), cavo([-0.95, 1.95, -0.1], pt("mano_l")), maniglia("mano_r"), maniglia("mano_l"),
           torre(-0.1, 2.0, 1.0), torre(-0.1, 2.0, -1.0)),
    fasi=("Chiudi", "Riapri piano"), base={"p": [0, 0.97, 0], "rl": [90, 12, 8, 0], "ll": [90, -12, 8, 0]}, fisso=PIEDI_A_TERRA)

E["dips"] = es((75, 8), {"t": 12, "ra": [-20, 10, 8, 0, -1, 0.3]}, {"t": 15, "ra": [-90, 58, 98, 0, -1, 0.3]},
    piatto(cap([0.27, 1.08, -0.35], [0.27, 1.08, 0.45], 0.022), cap([-0.27, 1.08, -0.35], [-0.27, 1.08, 0.45], 0.022),
           cap([0.27, 0, 0.4], [0.27, 1.08, 0.4], 0.03), cap([-0.27, 0, 0.4], [-0.27, 1.08, 0.4], 0.03)),
    fasi=("Spingi su", "Scendi piano"), base={"p": [0, 1.1, 0], "rl": [90, -10, 80, 30]}, fisso={"pt": "mani", "a": [0, 1.1, 0.02]})

# ---------------- dorsali ----------------
lat = piatto(sedile(), cap([-0.28, 0.72, 0.32], [0.28, 0.72, 0.32], 0.05, "cuscino"),
             cap([0, 0, -0.45], [0, 2.4, -0.45], 0.04), cap([0, 2.4, -0.45], [0, 2.4, 0.05], 0.04), cavo([0, 2.35, 0.05], pt("mani")))
E["lat_pulldown_wide"] = es((25, 6), {"t": -12, "ra": [0, 150, 12, 0, 1, 0]}, {"t": -18, "ra": [-12, 55, 115, 0, 1, 0]},
    piatto(lat, cap(pt("mano_l", (-0.2, 0, 0)), pt("mano_r", (0.2, 0, 0)), 0.014)),
    fasi=("Tira giù", "Risali piano"), base=SEDUTO)
E["lat_pulldown_neutral"] = es((40, 6), {"t": -10, "ra": [110, 165, 10, 0, 1, 0]}, {"t": -18, "ra": [70, 30, 125, 0, 1, 0]},
    piatto(lat, cap(pt("mano_l"), pt("mano_r"), 0.02)), fasi=("Tira giù", "Risali piano"), base=SEDUTO)

E["low_row"] = es((75, 10), {"t": 14, "ra": [95, 78, 4, 0, 0, 1]}, {"t": -6, "ra": [-75, 28, 95, 0, 0, 1]},
    piatto(box([0, 0.35, 0.0], [0.32, 0.1, 0.55], 0, "cuscino"), box([0, 0.2, 0.82], [0.45, 0.34, 0.05], -15, "metallo"),
           cap(pt("mano_l"), pt("mano_r"), 0.02), cavo([0, 0.34, 1.5], pt("mani")), torre(1.56, 1.3)),
    fasi=("Tira", "Allunga piano"), tempo=[1.0, 0.5, 1.8, 0.4], base={"p": [0, 0.51, 0], "rl": [88, 80, 40, -5]})

E["tbar_row"] = es((80, 10), {"t": 45, "ra": [90, 45, 5, 0, -0.7, 0.7]}, {"t": 45, "ra": [-60, 50, 95, 0, -0.7, 0.7]},
    piatto(box(pt("collo", (0, -0.25, 0.03)), [0.36, 0.5, 0.07], 45, "cuscino"), cap(pt("mano_l"), pt("mano_r"), 0.018),
           cap(pt("mani"), [0, 0.1, 1.0], 0.022), disco(pt("mani", (0, -0.12, 0.12)), [0, 0.6, 0.8], 0.2)),
    fasi=("Tira", "Allunga piano"), base={"p": [0, 0.97, 0], "rl": [90, 68, 42, -22]}, fisso=PIEDI_A_TERRA)

E["pullup"] = es((30, 0), {"ra": [0, 158, 10, 0, 1, 0]}, {"ra": [-12, 50, 120, 0, 1, 0]},
    [cap([-0.8, 2.3, 0], [0.8, 2.3, 0], 0.02), cap([0.8, 2.3, 0], [0.8, 0, 0], 0.03), cap([-0.8, 2.3, 0], [-0.8, 0, 0], 0.03)],
    fasi=("Sali", "Scendi piano"), base={"p": [0, 1.2, 0], "rl": [90, 10, 45, 25]}, fisso={"pt": "mani", "a": [0, 2.3, 0]})

E["db_row"] = es((-75, 12), {"t": 80, "ra": [90, 82, 5, 0, -0.2, 1], "la": [90, 82, 5, 0, -0.2, 1]},
    {"t": 80, "ra": [-80, 70, 95, 0, -0.2, 1], "la": [90, 82, 5, 0, -0.2, 1]},
    piatto(box([-0.12, 0.45, 0.25], [0.32, 0.1, 1.0], 0, "cuscino"), box([-0.12, 0.2, 0.25], [0.08, 0.4, 0.08], 0, "metallo"), manubrio("mano_r", (0, 0, 1))),
    fasi=("Tira", "Scendi piano"), base={"p": [0, 0.95, 0], "rl": [95, 70, 10, 0], "ll": [90, 85, 90, 40]},
    fisso={"pt": "mano_l", "a": [-0.18, 0.52, 0.55]})

E["straight_arm_pulldown"] = es((80, 8), {"t": 25, "ra": [90, 150, 8, 0, 1, 0]}, {"t": 25, "ra": [90, 18, 8, 0, 1, 0]},
    piatto(cap(pt("mano_l", (-0.1, 0, 0)), pt("mano_r", (0.1, 0, 0)), 0.014), cavo([0, 2.2, 0.6], pt("mani")), torre(0.66, 2.3)),
    fasi=("Tira giù", "Risali piano"), base={"p": [0, 0.97, 0], "rl": [90, 25, 20, 0]}, fisso=PIEDI_A_TERRA)

# ---------------- spalle ----------------
E["lateral_raise_cable"] = es((12, 6), {"ra": [5, 12, 15, 0, 0, 1], "la": [-10, 35, 100, 0, 0, 1]},
    {"ra": [5, 88, 15, 0, 0, 1], "la": [-10, 35, 100, 0, 0, 1]},
    piatto(cavo([-0.32, 0.15, 0.08], pt("mano_r")), maniglia("mano_r"), torre(0.08, 1.9, -0.45)),
    fasi=("Alza", "Scendi piano"), base=IN_PIEDI)
E["lateral_raise_machine"] = es((15, 10), {"ra": [0, 15, 90, 0, 0, 1]}, {"ra": [0, 85, 90, 0, 0, 1]},
    piatto(sedile(),
           cap(pt("gomito_r", (0.055, 0, -0.05)), pt("gomito_r", (0.055, 0, 0.06)), 0.045, "cuscino"),
           cap(pt("gomito_l", (-0.055, 0, -0.05)), pt("gomito_l", (-0.055, 0, 0.06)), 0.045, "cuscino"),
           cap([0.22, 1.2, -0.15], pt("gomito_r", (0.06, 0, -0.05))), cap([-0.22, 1.2, -0.15], pt("gomito_l", (-0.06, 0, -0.05)))),
    fasi=("Alza", "Scendi piano"), base=SEDUTO)
E["db_lateral_raise"] = es((15, 6), {"ra": [10, 10, 15, 0, 0, 1]}, {"ra": [10, 86, 15, 0, 0, 1]},
    piatto(manubrio("mano_r", (0, 0, 1)), manubrio("mano_l", (0, 0, 1))), fasi=("Alza", "Scendi piano"), base=IN_PIEDI)
E["reverse_pec_deck"] = es((205, 25), {"t": 8, "ra": [96, 88, 6, 0, 1, 0]}, {"t": 8, "ra": [-8, 86, 6, 0, 1, 0]},
    piatto(sedile(), box([0, 0.92, 0.24], [0.36, 0.55, 0.08], 8, "cuscino"), maniglia("mano_r"), maniglia("mano_l"),
           cap([0.15, 1.45, 0.35], pt("mano_r", (0, 0.06, 0))), cap([-0.15, 1.45, 0.35], pt("mano_l", (0, 0.06, 0)))),
    fasi=("Apri", "Torna piano"), base=SEDUTO)
E["face_pull"] = es((130, 10), {"ra": [92, 95, 5, 0, 1, 0]}, {"ra": [-5, 95, 110, 0, 1, 0]},
    piatto(corda(), cavo([0, 1.62, 1.05], pt("mani")), torre(1.1, 2.0)),
    fasi=("Tira", "Allunga piano"), base={"p": [0, 0.97, 0], "rl": [90, 10, 10, 0], "ll": [90, -10, 10, 0]}, fisso=PIEDI_A_TERRA)
E["shoulder_press_machine"] = es((30, 8), {"t": -5, "ra": [10, 85, 100, 0, 1, 0]}, {"t": -5, "ra": [10, 165, 10, 0, 1, 0]},
    piatto(sedile(schienale=-5), maniglia("mano_r", (0, 0, 1)), maniglia("mano_l", (0, 0, 1)),
           cap([0.3, 1.25, -0.35], pt("mano_r", (0.04, 0, 0))), cap([-0.3, 1.25, -0.35], pt("mano_l", (-0.04, 0, 0)))),
    fasi=("Spingi su", "Scendi piano"), base=SEDUTO)
E["db_shoulder_press"] = es((30, 8), {"t": -5, "ra": [10, 85, 100, 0, 1, 0]}, {"t": -5, "ra": [10, 165, 10, 0, 1, 0]},
    piatto(sedile(schienale=-5), manubrio("mano_r"), manubrio("mano_l")), fasi=("Spingi su", "Scendi piano"), base=SEDUTO)

# ---------------- braccia ----------------
E["db_curl"] = es((55, 8), {"ra": [88, 4, 5, 0, 0, 1]}, {"ra": [88, 6, 140, 0, 0, 1]},
    piatto(manubrio("mano_r"), manubrio("mano_l")), fasi=("Piega", "Scendi piano"), base=IN_PIEDI)
E["hammer_curl_rope"] = es((55, 8), {"ra": [92, 6, 6, 0, 0, 1]}, {"ra": [92, 8, 135, 0, 0, 1]},
    piatto(corda(), cavo([0, 0.12, 0.45], pt("mani")), torre(0.5, 1.6)), fasi=("Piega", "Scendi piano"), base=IN_PIEDI)
E["bayesian_curl"] = es((60, 8), {"ra": [-40, 25, 5, 0, 0, 1], "la": GIU}, {"ra": [-30, 25, 135, 0, 0, 1], "la": GIU},
    piatto(cavo([0.15, 0.3, -0.75], pt("mano_r")), maniglia("mano_r", (1, 0, 0)), torre(-0.8, 1.6, 0.15)),
    fasi=("Piega", "Scendi piano"), base={"p": [0, 0.97, 0], "rl": [90, 15, 10, 0], "ll": [90, -15, 5, 0]}, fisso=PIEDI_A_TERRA)
E["preacher_curl_machine"] = es((80, 10), {"t": 10, "ra": [90, 55, 10, 0, 1, -0.3]}, {"t": 10, "ra": [90, 55, 125, 0, 1, -0.3]},
    piatto(sedile(), box([0, 1.0, 0.3], [0.5, 0.06, 0.32], -35, "cuscino"), cap(pt("mano_l"), pt("mano_r"), 0.016),
           cap(pt("gomito_r", (0.12, 0, 0)), pt("mano_r", (0.12, 0, 0)), 0.02), cap(pt("gomito_l", (-0.12, 0, 0)), pt("mano_l", (-0.12, 0, 0)), 0.02)),
    fasi=("Piega", "Scendi piano"), base=SEDUTO)
E["incline_db_curl"] = es((70, 10), {"ra": [-90, 45, 5, 0, -0.71, 0.71]}, {"ra": [-90, 45, 135, 0, -0.71, 0.71]},
    piatto(box([0, 0.4, 0.05], [0.32, 0.09, 0.4], 0, "cuscino"), box([0, 0.8, -0.3], [0.32, 0.09, 0.95], 45, "cuscino"),
           manubrio("mano_r"), manubrio("mano_l")),
    fasi=("Piega", "Scendi piano"), base={"p": [0, 0.56, 0], "t": -45, "rl": [90, 45, 85, 0]})
E["triceps_pushdown"] = es((50, 8), {"t": 10, "ra": [80, 15, 110, 0, 1, 0]}, {"t": 10, "ra": [80, 15, 8, 0, 1, 0]},
    piatto(corda(), cavo([0, 1.95, 0.4], pt("mani", (0, 0.04, 0))), torre(0.46, 2.0)),
    fasi=("Spingi giù", "Risali piano"), base=IN_PIEDI, fisso=PIEDI_A_TERRA)
E["overhead_ext_rope"] = es((80, 8), {"t": 25, "ra": [90, 160, 125, 0, 0, -1]}, {"t": 25, "ra": [90, 160, 10, 0, 0, -1]},
    piatto(corda(), cavo([0, 1.65, -0.75], pt("mani")), torre(-0.8, 2.0)),
    fasi=("Stendi", "Torna piano"), base={"p": [0, 0.97, 0], "rl": [90, 20, 15, 0], "ll": [90, -20, 5, 0]}, fisso=PIEDI_A_TERRA)
E["ez_skullcrusher"] = es((60, 20), {"ra": [80, 95, 10, 0, 1, 0]}, {"ra": [80, 95, 110, 0, 1, 0]},
    piatto(panca, bilanciere(0.12, 0.13)), fasi=("Stendi", "Scendi piano"), base=PANCA_PIANA)

# ---------------- gambe ----------------
leg_press = piatto(box([0, 0.3, 0.05], [0.45, 0.08, 0.4], -20, "cuscino"), box([0, 0.66, -0.28], [0.45, 0.08, 0.75], 35, "cuscino"),
                   box(pt("piedi", (0, 0.035, 0.035)), [0.62, 0.05, 0.5], 45, "metallo"),
                   cap([0.38, 0.45, 0.1], [0.38, 1.5, 1.15], 0.03), cap([-0.38, 0.45, 0.1], [-0.38, 1.5, 1.15], 0.03))
E["leg_press"] = es((70, 8), {"rl": [86, 130, 99, -50]}, {"rl": [86, 80, 2, 0]}, leg_press,
    base={"p": [0, 0.42, 0], "t": -55, "ra": [0, 20, 30, 0, 0, 1]})
E["leg_press_high"] = es((70, 8), {"rl": [72, 132, 95, -45]}, {"rl": [72, 82, 2, 0]}, leg_press,
    base={"p": [0, 0.42, 0], "t": -55, "ra": [0, 20, 30, 0, 0, 1]})
E["calf_leg_press"] = es((70, 8), {"rl": [86, 80, 2, -20]}, {"rl": [86, 80, 2, 30]},
    piatto(leg_press[:2], box(pt("punte", (0, 0.035, 0.035)), [0.62, 0.05, 0.5], 45, "metallo"), leg_press[3:]),
    fasi=("Spingi", "Torna piano"), tempo=[0.8, 0.5, 1.5, 0.3], base={"p": [0, 0.42, 0], "t": -55, "ra": [0, 20, 30, 0, 0, 1]})
E["leg_extension"] = es((80, 8), {"rl": [88, 90, 95, -5], "ra": [0, 25, 40, 0, 0, 1]}, {"rl": [88, 92, 8, 10], "ra": [0, 25, 40, 0, 0, 1]},
    piatto(sedile(schienale=-10),
           cap(pt(["caviglia_l_davanti", "caviglia_r_davanti"], (-0.2, 0, 0)), pt(["caviglia_l_davanti", "caviglia_r_davanti"], (0.2, 0, 0)), 0.05, "cuscino"),
           cap([0.3, 0.55, 0.45], pt("caviglia_r_davanti", (0.25, 0, 0)))),
    fasi=("Stendi", "Scendi piano"), base={"p": [0, 0.58, 0], "t": -10})
E["leg_curl"] = es((80, 12), {"rl": [90, 8, 10, 30]}, {"rl": [90, 8, 110, 30]},
    piatto(box([0, 0.58, 0.2], [0.4, 0.12, 1.3], 0, "cuscino"), box([0, 0.26, 0.2], [0.08, 0.52, 0.08], 0, "metallo"),
           cap(pt(["caviglia_l_dietro", "caviglia_r_dietro"], (-0.22, 0, 0)), pt(["caviglia_l_dietro", "caviglia_r_dietro"], (0.22, 0, 0)), 0.05, "cuscino"),
           cap([0.3, 0.7, -0.5], pt("caviglia_r_dietro", (0.25, 0, 0)))),
    fasi=("Piega", "Stendi piano"), base={"p": [0, 0.79, 0.3], "t": 90, "ra": [90, 150, 70, 0, 1, 0]})
E["squat_bb"] = es((45, 8), {"t": 8, "rl": [90, 0, 3, 0]}, {"t": 38, "rl": [86, 100, 110, -35]},
    [cap(pt("trapezi", (-0.62, 0, 0)), pt("trapezi", (0.62, 0, 0)), 0.015),
     disco(pt("trapezi", (-0.5, 0, 0)), [1, 0, 0], 0.2), disco(pt("trapezi", (0.5, 0, 0)), [1, 0, 0], 0.2)],
    fasi=("Sali", "Scendi piano"), tempo=[1.0, 0.3, 2.0, 0.5],
    base={"p": [0, 0.97, 0], "ra": [-25, 62, 105, 0, 1, -0.3]}, fisso=PIEDI_A_TERRA)
E["hack_squat"] = es((80, 8), {"rl": [90, 25, 30, -15]}, {"rl": [88, 110, 115, -40]},
    piatto(box(pt("vita", (0, 0.05, -0.17)), [0.45, 0.85, 0.07], -20, "cuscino"),
           cap(pt("spalla_r", (0, 0.07, 0)), pt("spalla_r", (0, 0.07, 0.15)), 0.04, "cuscino"), cap(pt("spalla_l", (0, 0.07, 0)), pt("spalla_l", (0, 0.07, 0.15)), 0.04, "cuscino"),
           box([0, 0.06, 0.3], [0.7, 0.06, 0.55], -15, "metallo")),
    fasi=("Sali", "Scendi piano"), tempo=[1.0, 0.3, 2.0, 0.5],
    base={"p": [0, 0.97, 0], "t": -20, "ra": [-20, 30, 40, 0, 0, 1]}, fisso={"pt": "caviglie", "a": [0, 0.15, 0.3]})
E["rdl_db"] = es((80, 8), {"t": 0, "rl": [90, 0, 8, 0], "ra": [0, 5, 5, 0, 0, 1]}, {"t": 78, "rl": [90, 72, 15, 0], "ra": [90, 78, 5, 0, 0, 1]},
    piatto(manubrio("mano_r"), manubrio("mano_l")), fasi=("Sali", "Scendi piano"), tempo=[1.0, 0.3, 2.0, 0.4], base=IN_PIEDI, fisso=PIEDI_A_TERRA)
E["hip_thrust"] = es((55, 12), {"t": -55, "rl": [90, 75, 120, 10]}, {"t": -90, "rl": [90, 0, 90, 0]},
    piatto(box([0, 0.22, -0.55], [0.6, 0.44, 0.35], 0, "cuscino"),
           cap(pt("pelvi", (-0.55, 0.13, 0)), pt("pelvi", (0.55, 0.13, 0)), 0.015),
           disco(pt("pelvi", (-0.4, 0.13, 0)), [1, 0, 0], 0.16), disco(pt("pelvi", (0.4, 0.13, 0)), [1, 0, 0], 0.16)),
    fasi=("Spingi su", "Scendi piano"), tempo=[1.0, 0.8, 1.6, 0.3],
    base={"p": [0, 0.4, 0], "ra": [0, 30, 20, 0, 1, 0]}, fisso={"pt": "caviglie", "a": [0, 0.09, 0.42]})
E["lunges_db"] = es((80, 8), {"rl": [90, 25, 12, 0], "ll": [90, -22, 10, 20]}, {"rl": [90, 85, 88, -5], "ll": [90, -12, 98, 45]},
    piatto(manubrio("mano_r", (0, 0, 1)), manubrio("mano_l", (0, 0, 1))), fasi=("Sali", "Scendi piano"), tempo=[1.0, 0.3, 1.8, 0.4],
    base={"p": [0, 0.97, 0], "ra": GIU}, fisso={"pt": "caviglia_r", "a": [0, 0.09, 0.35]})
E["calf_standing"] = es((80, 8), {"rl": [90, 0, 2, -18]}, {"rl": [90, 0, 2, 32]},
    piatto(box([0, 0.05, 0.12], [0.5, 0.1, 0.22], 0, "metallo"),
           cap(pt("spalla_r", (0, 0.08, -0.05)), pt("spalla_r", (0, 0.08, 0.12)), 0.045, "cuscino"), cap(pt("spalla_l", (0, 0.08, -0.05)), pt("spalla_l", (0, 0.08, 0.12)), 0.045, "cuscino")),
    fasi=("Sali", "Scendi piano"), tempo=[0.8, 0.6, 1.5, 0.3], base={"p": [0, 0.97, 0], "ra": [-10, 40, 110, 0, 1, 0]},
    fisso={"pt": "punte", "a": [0, 0.13, 0.17]})

# ---------------- addome ----------------
E["cable_crunch"] = es((80, 8), {"t": 25, "c": 0, "hp": 10}, {"t": 50, "c": 45, "hp": 25},
    piatto(corda(), cavo([0, 2.1, 0.45], pt("mani")), torre(0.5, 2.2)),
    fasi=("Chiudi", "Torna piano"), base={"p": [0, 0.62, 0], "rl": [90, 0, 92, 70], "ra": [70, 150, 150, 0, 0, -1]})
E["crunch_machine"] = es((75, 8), {"t": -5, "c": 0}, {"t": 15, "c": 35, "hp": 20},
    piatto(sedile(schienale=-5), maniglia("mano_r", (1, 0, 0)), maniglia("mano_l", (1, 0, 0)),
           cap([0.3, 1.5, -0.3], pt("mano_r", (0.06, 0, 0))), cap([-0.3, 1.5, -0.3], pt("mano_l", (-0.06, 0, 0)))),
    fasi=("Chiudi", "Torna piano"), base={"p": [0, 0.58, 0], "rl": [86, 90, 90, 0], "ra": [80, 155, 145, 0, 0, -1]})
E["plank"] = es((70, -4), {"t": 90}, {"t": 87},
    [], fasi=("Tieni", "Tieni"), tempo=[1.6, 0, 1.6, 0],
    base={"p": [0, 0.36, 0], "rl": [90, 0, 0, 0], "ra": [90, 90, 90, 0, 1, 0]}, fisso={"pt": "gomito_r", "a": [0.19, 0.05, 0.4]})
E["side_plank"] = es((10, 8), {"ro": -75}, {"ro": -72},
    [], fasi=("Tieni", "Tieni"), tempo=[1.6, 0, 1.6, 0],
    base={"p": [0, 0.4, 0], "rl": [90, 0, 0, 0], "ra": [0, 25, 100, 0, 0, 1], "la": [0, 90, 90, 0, 0, 1]},
    fisso={"pt": "gomito_l", "a": [-0.55, 0.05, 0]})

assert len(E) == 44, len(E)

# video dell'esecuzione: YouTube (quasi tutti i clip di 10–15 secondi di Renaissance Periodization, solo il movimento).
# L'app li mostra incorporati (youtube-nocookie.com): non si scarica niente. «Verticali» = video corti 9:16.
VIDEO = {
    "chest_press": "NwzUje3z0qY",
    "pec_deck": "O-OBCfyh9Fw",
    "bench_press_bb": "gMgvBspQ9lk",
    "db_bench": "YQ2s_Y7g5Qk",
    "incline_db_press": "5CECBjd7HLQ",
    "cable_fly": "4mfLHnFL0Uw",
    "dips": "4LA1kF7yCGo",
    "lat_pulldown_wide": "YCKPD4BSD2E",
    "lat_pulldown_neutral": "--utaPT7XYQ",
    "low_row": "UCXxvVItLoM",
    "tbar_row": "0UBRfiO4zDs",
    "pullup": "iWpoegdfgtc",
    "db_row": "DMo3HJoawrU",
    "straight_arm_pulldown": "G9uNaXGTJ4w",
    "lateral_raise_cable": "lq7eLC30b9w",
    "lateral_raise_machine": "0o07iGKUarI",
    "db_lateral_raise": "OuG1smZTsQQ",
    "reverse_pec_deck": "5YK4bgzXDp0",
    "face_pull": "-MODnZdnmAQ",
    "shoulder_press_machine": "WvLMauqrnK8",
    "db_shoulder_press": "HzIiNhHhhtA",
    "db_curl": "iixND1P2lik",
    "hammer_curl_rope": "2CDKTFFp5fA",
    "bayesian_curl": "w3sXATQzGvc",
    "preacher_curl_machine": "Ja6ZlIDONac",
    "incline_db_curl": "aTYlqC_JacQ",
    "triceps_pushdown": "-xa-6cQaZKY",
    "overhead_ext_rope": "kqidUIf1eJE",
    "ez_skullcrusher": "l3rHYPtMUo8",
    "leg_press": "yZmx_Ac3880",
    "leg_press_high": "yZmx_Ac3880",
    "calf_leg_press": "KxEYX_cuesM",
    "leg_extension": "m0FOpMEgero",
    "leg_curl": "n5WDXD_mpVY",
    "squat_bb": "i7J5h7BJ07g",
    "hack_squat": "rYgNArpwE7E",
    "rdl_db": "cYKYGwcg0U8",
    "hip_thrust": "EF7jXP17DPE",
    "lunges_db": "eFWCn5iEbTU",
    "calf_standing": "N3awlEyTY98",
    "cable_crunch": "6GMKPQVERzw",
    "crunch_machine": "-OUSBPnHvsQ",
    "plank": "xe2MXatLTUw",
    "side_plank": "BtM0a9x1F5o",
}
VERTICALI = {"bayesian_curl", "plank", "side_plank"}
for k, v in VIDEO.items():
    E[k]["yt"] = v
    if k in VERTICALI:
        E[k]["ytv"] = True

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(E, f, ensure_ascii=False, separators=(",", ":"))
print("movimenti.json:", len(E), "esercizi")
