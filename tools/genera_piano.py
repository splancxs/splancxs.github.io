# -*- coding: utf-8 -*-
"""
Generatore + verificatore del piano alimentare e delle schede.

- Il piano alimentare (alimenti, ricette, porzioni per fascia, settimana) arriva già pronto da tools/dieta.json,
  esportato dal progetto del nutrizionista.
- Calcola i totali ESATTAMENTE come li calcola il sito (stesso arrotondamento):
  kcal riga = round(kcal100 * g / 100) a intero, macro riga = round(x * 10) / 10;
  totale pasto = somma delle righe arrotondate; totale giorno = somma dei pasti.
- Scrive assets/js/data.js e stampa il report di verifica.

Uso:  python tools/genera_piano.py
"""
import itertools
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def r0(x):  # arrotondamento identico a Math.round (x >= 0)
    return int(math.floor(x + 0.5))


def r1(x):
    return math.floor(x * 10 + 0.5) / 10


# ---------------------------------------------------------------------------
# PIANO ALIMENTARE  (da tools/dieta.json)
# Il piano lo prepara il nutrizionista nel progetto «alimentazione» (valori, porzioni e settimana) e lo esporta
# in questo formato: foods, recipes, variants (fascia → ricetta → [alimento, grammi]), daytypes, targets, week,
# equivalents. Qui non si ricalcolano le porzioni: si verificano i conti come li fa il sito e si scrive data.js.
# Per aggiornarlo: sostituire tools/dieta.json con il nuovo export e rilanciare questo script (poi piano_swift.py).
# ---------------------------------------------------------------------------
with open(os.path.join(HERE, 'dieta.json'), encoding='utf-8') as fh:
    DIETA = json.load(fh)

F = DIETA['foods']
R = DIETA['recipes']
VARIANTS = {(code, slot): [tuple(x) for x in items]
            for slot, ricette in DIETA['variants'].items() for code, items in ricette.items()}
DAYTYPES = {k: dict(label=v['label'], target=tuple(v['target']), slots=[tuple(s) for s in v['slots']])
            for k, v in DIETA['daytypes'].items()}
WEEK = DIETA['week']
TARGETS = DIETA['targets']


def line(fid, g):
    f = F[fid]
    return dict(f=fid, g=g, k=r0(f['k'] * g / 100), p=r1(f['p'] * g / 100), c=r1(f['c'] * g / 100),
                fa=r1(f['f'] * g / 100))


def totals(lines):
    k = sum(l['k'] for l in lines)
    p = r1(sum(l['p'] for l in lines))
    c = r1(sum(l['c'] for l in lines))
    fa = r1(sum(l['fa'] for l in lines))
    return k, p, c, fa


def meal_lines(code, slot):
    return [line(f, g) for f, g in VARIANTS[(code, slot)]]


def report():
    """Totali di ogni giorno come li calcola il sito, con le regole del piano:
    ±100 kcal dal target, proteine almeno 135 g, grassi almeno 40 g (il giorno con il pasto libero non si conta)."""
    out = []
    ok = True
    for day in WEEK:
        dt = DAYTYPES[day['type']]
        dk = dp = dc = dfa = 0
        out.append(f"\n{day['name'].upper()} — {dt['label']}  target {dt['target']}")
        for (time, label, slot), code in zip(dt['slots'], day['pick']):
            if slot == 'free':
                out.append(f"  {time} {label}: pasto libero (non conteggiato)")
                continue
            ls = meal_lines(code, slot)
            k, p, c, fa = totals(ls)
            dk += k; dp += p; dc += c; dfa += fa
            items = ', '.join(f"{F[l['f']]['n'].split(' (')[0]} {l['g']}g" for l in ls)
            out.append(f"  {time} {code:14s} {k:4d} kcal P{p:5.1f} C{c:5.1f} F{fa:5.1f} | {items}")
        dp, dc, dfa = r1(dp), r1(dc), r1(dfa)
        out.append(f"  TOTALE {dk} kcal · P {dp} · C {dc} · F {dfa}")
        if day['type'] != 'FREE':
            if abs(dk - dt['target'][0]) > 100:
                ok = False
                out.append('  !!! fuori tolleranza kcal (±100)')
            if dp < 135:
                ok = False
                out.append('  !!! proteine sotto 135 g')
            if dfa < 40:
                ok = False
                out.append('  !!! grassi sotto 40 g')
    for day in WEEK:
        dt = DAYTYPES[day['type']]
        if len(dt['slots']) != len(day['pick']):
            ok = False
            out.append(f"  !!! {day['name']}: {len(day['pick'])} pasti per {len(dt['slots'])} fasce")
        for (_, _, slot), code in zip(dt['slots'], day['pick']):
            if slot != 'free' and (code, slot) not in VARIANTS:
                ok = False
                out.append(f"  !!! {day['name']}: {code} non sta nella fascia {slot}")
    # il cambio «salto / recupero l'allenamento» scambia le fasce ON e OFF_S una a una
    if len(DAYTYPES['ON']['slots']) != len(DAYTYPES['OFF_S']['slots']):
        ok = False
        out.append('  !!! ON e OFF_S devono avere lo stesso numero di fasce')
    for (code, slot), items in VARIANTS.items():
        if code not in R or any(f not in F for f, _ in items):
            ok = False
            out.append(f'  !!! {code} in {slot}: ricetta o alimento mancante')
    return '\n'.join(out), ok


def swap_ranges():
    """Min/max dei totali giornalieri su TUTTE le combinazioni possibili di scambi."""
    out = []
    for tname, dt in DAYTYPES.items():
        if tname == 'FREE':
            continue
        per_slot = [[totals(meal_lines(code, slot)) for (code, s) in VARIANTS if s == slot]
                    for _, _, slot in dt['slots']]
        ks, ps, cs, fs = [], [], [], []
        for combo in itertools.product(*per_slot):
            ks.append(sum(x[0] for x in combo)); ps.append(sum(x[1] for x in combo))
            cs.append(sum(x[2] for x in combo)); fs.append(sum(x[3] for x in combo))
        out.append(f"{tname:6s} combinazioni {len(ks):6d} | kcal {min(ks)}–{max(ks)} | P {min(ps):.0f}–{max(ps):.0f}"
                   f" | C {min(cs):.0f}–{max(cs):.0f} | F {min(fs):.0f}–{max(fs):.0f}")
    return '\n'.join(out)


def equivalents():
    return DIETA['equivalents']


# ---------------------------------------------------------------------------
# SCHEDA TORSO / LIMBS
# ---------------------------------------------------------------------------
def ex(id, name, sets, lo, hi, rest, start, inc, cue, sup=None, unit='reps', kg=None):
    d = dict(id=id, n=name, s=sets, lo=lo, hi=hi, rest=rest, start=start, inc=inc, cue=cue, unit=unit)
    if sup:
        d['sup'] = sup
    if kg is not None:
        d['kg'] = kg
    return d


WORKOUTS = [
    dict(id='TA', day='Lunedì', name='Torso A', focus='Petto + larghezza dorsali', ex=[
        ex('TA1', 'Chest Press', 3, 6, 10, 150, '29 kg', 2.5,
           'Scapole addotte e basse, schiena incollata allo schienale. 2-3" in discesa, spingi senza bloccare i gomiti.', kg=29),
        ex('TA2', 'Lat Pulldown · presa larga prona', 3, 8, 10, 120, '34–36 kg', 2.5,
           'Petto alto verso la barra, gomiti verso le tasche. Niente slancio col busto, controlla la risalita.', kg=34),
        ex('TA3', 'Pec Deck', 3, 10, 15, 90, 'da testare', 2.5,
           'Gomiti leggermente piegati e fissi, abbraccia un albero. Pausa di 1" a braccia chiuse.'),
        ex('TA4', 'Low Row · presa neutra (triangolo)', 3, 10, 12, 120, '21–23 kg', 2.5,
           'Busto fermo e dritto, tira coi gomiti verso i fianchi, pausa 1" con le scapole strette.', kg=21),
        ex('TA5', 'Alzate laterali al cavo · 1 braccio', 3, 12, 15, 60, '4–5 kg', 1.25,
           'Busto leggermente inclinato, gomito appena piegato, porta il braccio "in fuori" fino all\'altezza della spalla.', kg=4),
        ex('TA6', 'Reverse Pec Deck', 3, 12, 15, 60, 'da testare', 2.5,
           'Braccia quasi tese, pensa ad "allargare" più che a stringere le scapole. Nessuno slancio.'),
    ]),
    dict(id='LA', day='Martedì', name='Limbs A', focus='Quadricipiti + braccia', ex=[
        ex('LA1', 'Leg Press', 3, 6, 10, 165, '118 kg', 5,
           'Piedi a larghezza spalle al centro della pedana. Scendi finché il bacino resta appoggiato, non bloccare le ginocchia.', kg=118),
        ex('LA2', 'Leg Curl', 3, 8, 12, 90, '50–52 kg', 5,
           'Bacino schiacciato sul pad, piega fino in fondo, risalita lenta in 2-3".', kg=50),
        ex('LA3', 'Leg Extension', 3, 10, 15, 90, '27–29 kg', 2.5,
           'Schiena appoggiata, estendi completamente con 1" di pausa in alto, scendi controllato.', kg=27),
        ex('LA4', 'Bayesian Curl al cavo basso', 3, 10, 12, 0, 'test ~5–7,5 kg', 1.25,
           'Di spalle al cavo, braccio dietro il busto: massimo allungamento del bicipite. Gomito fermo.', sup='4a'),
        ex('LA5', 'Triceps Pushdown', 3, 10, 12, 75, '12–13 kg', 2.5,
           'Gomiti incollati ai fianchi, estendi completamente e apri leggermente le mani in fondo.', sup='4b', kg=12),
        ex('LA6', 'Hammer Curl con corda', 2, 10, 12, 0, 'da testare', 2.5,
           'Presa neutra sulla corda, gomiti fermi, sali fino alle spalle senza dondolare.', sup='5a'),
        ex('LA7', 'Overhead Extension con corda', 2, 12, 15, 60, 'da testare', 2.5,
           'Di spalle al cavo, gomiti puntati in avanti e fermi, massimo allungamento dietro la testa.', sup='5b'),
        ex('LA8', 'Cable Crunch', 3, 10, 15, 60, 'da testare', 2.5,
           'In ginocchio, corda vicino alla fronte, arrotola la colonna portando i gomiti verso le cosce. Il bacino non si muove.'),
        ex('LA9', 'Plank frontale', 2, 45, 60, 45, '—', 10,
           'Gomiti sotto le spalle, glutei e addome contratti, corpo in linea. Non far cadere il bacino.', unit='sec'),
    ]),
    dict(id='TB', day='Giovedì', name='Torso B', focus='Spessore schiena + spalle', ex=[
        ex('TB1', 'Panca inclinata 30° con manubri', 3, 8, 12, 150, '8 kg/manubrio', 2,
           'Scapole indietro e in basso, manubri che scendono all\'altezza del petto alto, gomiti a ~45°.', kg=8),
        ex('TB2', 'T-Bar Row con petto in appoggio', 3, 8, 10, 120, 'da testare', 2.5,
           'Petto sempre appoggiato, tira coi gomiti verso il bacino, pausa di 1" in alto.'),
        ex('TB3', 'Shoulder Press Machine', 3, 8, 10, 120, '13 kg (obiettivo 18)', 2.5,
           'Schiena appoggiata, impugnature all\'altezza delle orecchie, spingi senza inarcare la lombare.', kg=13),
        ex('TB4', 'Lat Pulldown · presa neutra stretta', 3, 10, 12, 90, '32–34 kg', 2.5,
           'Tira verso lo sterno con i gomiti vicini al corpo, allunga bene in alto senza perdere la postura.', kg=32),
        ex('TB5', 'Pec Deck', 2, 12, 15, 75, 'come lunedì', 2.5,
           'Stesso gesto del lunedì, più ripetizioni: cerca la contrazione, non il carico.'),
        ex('TB6', 'Alzate laterali alla macchina (o al cavo)', 4, 12, 15, 60, '10–11 kg', 2.5,
           'Spalle basse, sali fino all\'orizzontale guidando coi gomiti, discesa lenta.', kg=10),
        ex('TB7', 'Reverse Pec Deck', 2, 15, 20, 60, 'come lunedì', 2.5,
           'Più ripetizioni del lunedì: tensione continua sui deltoidi posteriori.'),
    ]),
    dict(id='LB', day='Venerdì', name='Limbs B', focus='Femorali + braccia', ex=[
        ex('LB1', 'Leg Curl', 4, 8, 12, 90, '52 kg', 5,
           'Primo esercizio: massima qualità. Risalita lenta, niente colpi di bacino.', kg=52),
        ex('LB2', 'Leg Press · piedi alti e larghi', 3, 10, 12, 150, '100–105 kg', 5,
           'Piedi alti sulla pedana: lavorano di più glutei e femorali. Spingi coi talloni.', kg=100),
        ex('LB3', 'Leg Extension', 3, 12, 15, 75, '25–27 kg', 2.5,
           'Più ripetizioni del martedì, 1" di pausa in alto su ogni ripetizione.', kg=25),
        ex('LB4', 'Preacher Curl alla macchina', 3, 8, 12, 0, '13–15 kg', 2.5,
           'Braccio ben appoggiato al cuscino, scendi fino quasi a distendere, sali senza staccare i gomiti.', sup='4a', kg=13),
        ex('LB5', 'Overhead Extension con corda', 3, 10, 12, 75, 'come martedì', 2.5,
           'Gomiti fermi e puntati in avanti, allungamento completo dietro la testa.', sup='4b'),
        ex('LB6', 'Hammer Curl con corda', 2, 10, 12, 0, 'come martedì', 2.5,
           'Presa neutra, nessun dondolio, discesa in 2".', sup='5a'),
        ex('LB7', 'Triceps Pushdown', 2, 12, 15, 60, '11–12 kg', 2.5,
           'Gomiti ai fianchi, estensione completa, 1" di contrazione in basso.', sup='5b', kg=11),
        ex('LB8', 'Crunch Machine', 3, 10, 15, 60, 'da testare', 2.5,
           'Espira mentre ti chiudi, arrotola la colonna. Movimento controllato, niente strappi con le braccia.'),
        ex('LB9', 'Side Plank', 2, 30, 45, 30, '— (per lato)', 10,
           'Gomito sotto la spalla, corpo in linea, bacino alto. Tempo per ciascun lato.', unit='sec'),
    ]),
]

# ---------------------------------------------------------------------------
# LIBRERIA ESERCIZI (allenamento live stile Hevy)
# id: (nome, muscolo principale, muscoli secondari, incremento kg, unità, attrezzo)
# ---------------------------------------------------------------------------
EXLIB_BASE = {
    'chest_press': ('Chest Press', 'Petto', ['Tricipiti', 'Deltoidi anteriori'], 2.5, 'reps', 'Macchina'),
    'lat_pulldown_wide': ('Lat Pulldown · presa larga prona', 'Dorsali', ['Bicipiti'], 2.5, 'reps', 'Cavo'),
    'pec_deck': ('Pec Deck', 'Petto', [], 2.5, 'reps', 'Macchina'),
    'low_row': ('Low Row · presa neutra', 'Dorsali', ['Bicipiti', 'Deltoidi posteriori'], 2.5, 'reps', 'Cavo'),
    'lateral_raise_cable': ('Alzate laterali al cavo', 'Deltoidi laterali', [], 1.25, 'reps', 'Cavo'),
    'reverse_pec_deck': ('Reverse Pec Deck', 'Deltoidi posteriori', ['Dorsali'], 2.5, 'reps', 'Macchina'),
    'leg_press': ('Leg Press', 'Quadricipiti', ['Glutei'], 5, 'reps', 'Macchina'),
    'leg_curl': ('Leg Curl', 'Femorali', [], 5, 'reps', 'Macchina'),
    'leg_extension': ('Leg Extension', 'Quadricipiti', [], 2.5, 'reps', 'Macchina'),
    'bayesian_curl': ('Bayesian Curl al cavo', 'Bicipiti', [], 1.25, 'reps', 'Cavo'),
    'triceps_pushdown': ('Triceps Pushdown', 'Tricipiti', [], 2.5, 'reps', 'Cavo'),
    'hammer_curl_rope': ('Hammer Curl con corda', 'Bicipiti', [], 2.5, 'reps', 'Cavo'),
    'overhead_ext_rope': ('Overhead Extension con corda', 'Tricipiti', [], 2.5, 'reps', 'Cavo'),
    'cable_crunch': ('Cable Crunch', 'Addome', [], 2.5, 'reps', 'Cavo'),
    'plank': ('Plank frontale', 'Addome', [], 10, 'sec', 'Corpo libero'),
    'incline_db_press': ('Panca inclinata 30° con manubri', 'Petto', ['Deltoidi anteriori', 'Tricipiti'], 2, 'reps', 'Manubri'),
    'tbar_row': ('T-Bar Row con petto in appoggio', 'Dorsali', ['Bicipiti', 'Deltoidi posteriori'], 2.5, 'reps', 'Macchina'),
    'shoulder_press_machine': ('Shoulder Press Machine', 'Deltoidi anteriori', ['Tricipiti', 'Deltoidi laterali'], 2.5, 'reps', 'Macchina'),
    'lat_pulldown_neutral': ('Lat Pulldown · presa neutra stretta', 'Dorsali', ['Bicipiti'], 2.5, 'reps', 'Cavo'),
    'lateral_raise_machine': ('Alzate laterali alla macchina', 'Deltoidi laterali', [], 2.5, 'reps', 'Macchina'),
    'leg_press_high': ('Leg Press · piedi alti e larghi', 'Glutei', ['Femorali', 'Quadricipiti'], 5, 'reps', 'Macchina'),
    'preacher_curl_machine': ('Preacher Curl alla macchina', 'Bicipiti', [], 2.5, 'reps', 'Macchina'),
    'crunch_machine': ('Crunch Machine', 'Addome', [], 2.5, 'reps', 'Macchina'),
    'side_plank': ('Side Plank', 'Addome', [], 10, 'sec', 'Corpo libero'),
    # esercizi in più, da aggiungere alle routine quando vuoi
    'bench_press_bb': ('Panca piana con bilanciere', 'Petto', ['Tricipiti', 'Deltoidi anteriori'], 2.5, 'reps', 'Bilanciere'),
    'db_bench': ('Panca piana con manubri', 'Petto', ['Tricipiti'], 2, 'reps', 'Manubri'),
    'cable_fly': ('Croci ai cavi', 'Petto', [], 2.5, 'reps', 'Cavo'),
    'pullup': ('Trazioni alla sbarra', 'Dorsali', ['Bicipiti'], 2.5, 'reps', 'Corpo libero'),
    'db_row': ('Rematore con manubrio', 'Dorsali', ['Bicipiti'], 2, 'reps', 'Manubri'),
    'straight_arm_pulldown': ('Pulldown a braccia tese', 'Dorsali', [], 2.5, 'reps', 'Cavo'),
    'face_pull': ('Face Pull', 'Deltoidi posteriori', [], 2.5, 'reps', 'Cavo'),
    'db_shoulder_press': ('Military press con manubri', 'Deltoidi anteriori', ['Tricipiti'], 2, 'reps', 'Manubri'),
    'db_lateral_raise': ('Alzate laterali con manubri', 'Deltoidi laterali', [], 1, 'reps', 'Manubri'),
    'squat_bb': ('Squat con bilanciere', 'Quadricipiti', ['Glutei'], 2.5, 'reps', 'Bilanciere'),
    'hack_squat': ('Hack Squat', 'Quadricipiti', ['Glutei'], 5, 'reps', 'Macchina'),
    'rdl_db': ('Stacco rumeno con manubri', 'Femorali', ['Glutei'], 2, 'reps', 'Manubri'),
    'hip_thrust': ('Hip Thrust', 'Glutei', ['Femorali'], 5, 'reps', 'Bilanciere'),
    'lunges_db': ('Affondi con manubri', 'Quadricipiti', ['Glutei'], 2, 'reps', 'Manubri'),
    'calf_leg_press': ('Calf alla Leg Press', 'Polpacci', [], 5, 'reps', 'Macchina'),
    'calf_standing': ('Calf in piedi', 'Polpacci', [], 5, 'reps', 'Macchina'),
    'db_curl': ('Curl con manubri', 'Bicipiti', [], 1, 'reps', 'Manubri'),
    'incline_db_curl': ('Curl su panca inclinata', 'Bicipiti', [], 1, 'reps', 'Manubri'),
    'dips': ('Dip alle parallele', 'Tricipiti', ['Petto'], 2.5, 'reps', 'Corpo libero'),
    'ez_skullcrusher': ('French press con bilanciere EZ', 'Tricipiti', [], 2.5, 'reps', 'Bilanciere'),
}
# esercizio della scheda → voce della libreria
EX_MAP = {
    'TA1': 'chest_press', 'TA2': 'lat_pulldown_wide', 'TA3': 'pec_deck', 'TA4': 'low_row', 'TA5': 'lateral_raise_cable',
    'TA6': 'reverse_pec_deck', 'LA1': 'leg_press', 'LA2': 'leg_curl', 'LA3': 'leg_extension', 'LA4': 'bayesian_curl',
    'LA5': 'triceps_pushdown', 'LA6': 'hammer_curl_rope', 'LA7': 'overhead_ext_rope', 'LA8': 'cable_crunch', 'LA9': 'plank',
    'TB1': 'incline_db_press', 'TB2': 'tbar_row', 'TB3': 'shoulder_press_machine', 'TB4': 'lat_pulldown_neutral',
    'TB5': 'pec_deck', 'TB6': 'lateral_raise_machine', 'TB7': 'reverse_pec_deck', 'LB1': 'leg_curl', 'LB2': 'leg_press_high',
    'LB3': 'leg_extension', 'LB4': 'preacher_curl_machine', 'LB5': 'overhead_ext_rope', 'LB6': 'hammer_curl_rope',
    'LB7': 'triceps_pushdown', 'LB8': 'crunch_machine', 'LB9': 'side_plank',
}
# foto free-exercise-db (pubblico dominio, Unlicense) in assets/esercizi/<nome>-0.jpg e <nome>-1.jpg
EX_IMG = {
    'chest_press': 'Leverage_Chest_Press', 'lat_pulldown_wide': 'Wide-Grip_Lat_Pulldown', 'pec_deck': 'Butterfly',
    'low_row': 'Seated_Cable_Rows', 'lateral_raise_cable': 'Cable_Seated_Lateral_Raise', 'reverse_pec_deck': 'Reverse_Machine_Flyes',
    'leg_press': 'Leg_Press', 'leg_curl': 'Lying_Leg_Curls', 'leg_extension': 'Leg_Extensions',
    'bayesian_curl': 'Standing_One-Arm_Cable_Curl', 'triceps_pushdown': 'Triceps_Pushdown_-_Rope_Attachment', 'hammer_curl_rope': 'Cable_Hammer_Curls_-_Rope_Attachment',
    'overhead_ext_rope': 'Cable_Rope_Overhead_Triceps_Extension', 'cable_crunch': 'Cable_Crunch', 'plank': 'Plank',
    'incline_db_press': 'Incline_Dumbbell_Press', 'tbar_row': 'Lying_T-Bar_Row', 'shoulder_press_machine': 'Machine_Shoulder_Military_Press',
    'lat_pulldown_neutral': 'V-Bar_Pulldown', 'lateral_raise_machine': 'Side_Lateral_Raise', 'leg_press_high': 'Leg_Press',
    'preacher_curl_machine': 'Machine_Preacher_Curls', 'crunch_machine': 'Ab_Crunch_Machine', 'side_plank': 'Side_Bridge',
    'bench_press_bb': 'Barbell_Bench_Press_-_Medium_Grip', 'db_bench': 'Dumbbell_Bench_Press', 'cable_fly': 'Cable_Crossover',
    'pullup': 'Pullups', 'db_row': 'One-Arm_Dumbbell_Row', 'straight_arm_pulldown': 'Straight-Arm_Pulldown',
    'face_pull': 'Face_Pull', 'db_shoulder_press': 'Dumbbell_Shoulder_Press', 'db_lateral_raise': 'Side_Lateral_Raise',
    'squat_bb': 'Barbell_Squat', 'hack_squat': 'Hack_Squat', 'rdl_db': 'Stiff-Legged_Dumbbell_Deadlift',
    'hip_thrust': 'Barbell_Hip_Thrust', 'lunges_db': 'Dumbbell_Lunges', 'calf_leg_press': 'Calf_Press_On_The_Leg_Press_Machine',
    'calf_standing': 'Standing_Calf_Raises', 'db_curl': 'Dumbbell_Bicep_Curl', 'incline_db_curl': 'Incline_Dumbbell_Curl',
    'dips': 'Dips_-_Triceps_Version', 'ez_skullcrusher': 'EZ-Bar_Skullcrusher',
}
# foto di un movimento equivalente (la tua macchina può essere diversa)
EX_EQV = {'lateral_raise_machine', 'bayesian_curl', 'leg_press_high'}
# serie dirette a settimana previste dalla scheda (per le statistiche)
MUSCLE_TARGETS = {'Petto': 11, 'Dorsali': 12, 'Deltoidi laterali': 7, 'Deltoidi posteriori': 5, 'Quadricipiti': 12,
                  'Femorali': 7, 'Bicipiti': 10, 'Tricipiti': 10, 'Addome': 6}


def build_exlib():
    cues = {}
    for w in WORKOUTS:
        for e in w['ex']:
            e['lib'] = EX_MAP[e['id']]
            cues.setdefault(e['lib'], e['cue'])
    lib = {}
    for k, (n, m, sec, inc, unit, eq) in EXLIB_BASE.items():
        lib[k] = dict(id=k, n=n, m=m, sec=sec, inc=inc, unit=unit, eq=eq, cue=cues.get(k, ''))
        if k in EX_IMG:
            lib[k]['img'] = EX_IMG[k]
        if k in EX_EQV:
            lib[k]['eqv'] = 1
    return lib


EXLIB = build_exlib()

def build_data():
    variants = {}
    for (code, slot), items in VARIANTS.items():
        variants.setdefault(slot, {})[code] = [[f, g] for f, g in items]
    recipes = R
    return dict(
        version=DIETA['version'],
        foods=F,
        recipes=recipes,
        variants=variants,
        daytypes={k: dict(label=v['label'], target=v['target'], slots=v['slots']) for k, v in DAYTYPES.items()},
        week=WEEK,
        workouts=WORKOUTS,
        exlib=EXLIB,
        muscleTargets=MUSCLE_TARGETS,
        targets=TARGETS,
        equivalents=equivalents(),
    )


if __name__ == '__main__':
    txt, ok = report()
    print(txt)
    print('\nIntervalli con qualsiasi scambio:')
    print(swap_ranges())
    data = build_data()
    js = '/* File generato da tools/genera_piano.py — non modificare a mano */\nwindow.PIANO = ' + \
         json.dumps(data, ensure_ascii=False, separators=(',', ':')) + ';\n'
    out = os.path.join(ROOT, 'assets', 'js', 'data.js')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as fh:
        fh.write(js)
    print('\nScritto', out, f'({len(js)} byte)')
    print('VERIFICA:', 'OK' if ok else 'ERRORI')
